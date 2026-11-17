#!/usr/bin/env python3
"""Profile a compiled .hvm program on the HVM2 runtime.

GHC's profiling and heap tooling describe GHC's RTS: cost centres attached to
ticked closures, and a generational moving collector. Coronet has neither, so
this reports the quantities that actually exist in an interaction net:

  ITRS    interactions performed (the honest unit of work)
  NODES   peak live graph nodes: the leak signal
  VARS    peak live variables
  PROFILE per-definition call interactions, i.e. cost centres by definition
  RSS     peak resident memory of the process, sampled from the outside

A leak shows up as NODES/RSS that keep climbing while the result is unchanged.
Nothing here is GHC-specific, so the numbers are comparable across programs
compiled by Coronet itself.

    scripts/hvm_profile.py prog.hvm
    scripts/hvm_profile.py prog.hvm --top 15 --json
    scripts/hvm_profile.py prog.hvm --timeout 300
"""

import argparse
import json
import os
import pathlib
import re
import resource
import shutil
import subprocess
import sys
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_BIN = ROOT / "vendor" / "HVM2" / "target" / "release" / "hvm"

RESULT_RE = re.compile(r"^Result: (.*)$")
SCALAR_RE = re.compile(r"^- (ITRS|TIME|MIPS|NODES|VARS|RULE_ITRS|TID_ITRS):\s*(.*)$")
DEF_ROW_RE = re.compile(r"^\s{2}(\S+) (\d+)$")
NODES_RE = re.compile(r"^(\d+)\s*/\s*(\d+)$")
KV_RE = re.compile(r"(\w+)=([\d.]+)")


def runtime_binary() -> pathlib.Path:
    override = os.environ.get("HVM2_BIN")
    if override:
        return pathlib.Path(override)
    return DEFAULT_BIN


def _rss_kb(pid: int) -> int | None:
    """Resident set size in KiB, without psutil."""
    try:
        out = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    text = out.stdout.strip()
    if not text:
        return None
    try:
        return int(text.split()[0])
    except ValueError:
        return None


class RssSampler:
    """Samples the child's RSS while it runs; a leak is a rising curve."""

    def __init__(self, pid: int, interval: float):
        self.pid = pid
        self.interval = interval
        self.samples: list[tuple[float, int]] = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        start = time.monotonic()
        while not self._stop.is_set():
            rss = _rss_kb(self.pid)
            if rss is not None:
                self.samples.append((time.monotonic() - start, rss))
            self._stop.wait(self.interval)

    def __enter__(self) -> "RssSampler":
        self._thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def peak_kb(self) -> int:
        return max((rss for _, rss in self.samples), default=0)

    def growth(self) -> tuple[float, int, int]:
        """(relative growth, first-quarter RSS, last-quarter RSS)."""
        if len(self.samples) < 8:
            return 0.0, 0, 0
        quarter = max(1, len(self.samples) // 4)
        head = sum(r for _, r in self.samples[:quarter]) / quarter
        tail = sum(r for _, r in self.samples[-quarter:]) / quarter
        if head <= 0:
            return 0.0, int(head), int(tail)
        return (tail - head) / head, int(head), int(tail)


def parse_output(text: str) -> dict:
    data = {
        "result": None,
        "itrs": None,
        "time_s": None,
        "mips": None,
        "nodes": None,
        "nodes_cap": None,
        "vars": None,
        "vars_cap": None,
        "rules": {},
        "profile": [],
    }
    in_defs = False
    for line in text.splitlines():
        if in_defs:
            m = DEF_ROW_RE.match(line)
            if m:
                data["profile"].append({"def": m.group(1), "count": int(m.group(2))})
                continue
            in_defs = False
        stripped = line.strip()
        m = RESULT_RE.match(stripped)
        if m:
            data["result"] = m.group(1)
            continue
        if stripped == "- DEF_ITRS:":
            in_defs = True
            continue
        m = SCALAR_RE.match(stripped)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if key == "ITRS":
            data["itrs"] = int(value)
        elif key == "TIME":
            data["time_s"] = float(value.rstrip("s"))
        elif key == "MIPS":
            data["mips"] = float(value)
        elif key == "NODES":
            n = NODES_RE.match(value)
            if n:
                data["nodes"], data["nodes_cap"] = int(n.group(1)), int(n.group(2))
        elif key == "VARS":
            n = NODES_RE.match(value)
            if n:
                data["vars"], data["vars_cap"] = int(n.group(1)), int(n.group(2))
        elif key == "RULE_ITRS":
            data["rules"] = {k: int(float(v)) for k, v in KV_RE.findall(value)}
    # Stable order: hottest definition first, ties broken by name.
    data["profile"].sort(key=lambda r: (-r["count"], r["def"]))
    return data


def run(path: pathlib.Path, timeout: float, interval: float, runtime: str) -> tuple[dict, str]:
    binary = runtime_binary()
    if not binary.exists():
        raise SystemExit(f"missing HVM2 binary at {binary}; run `cargo build --release` in vendor/HVM2")

    env = dict(os.environ)
    env["HVM_DIAG"] = "1"

    proc = subprocess.Popen(
        [str(binary), "run-c" if runtime == "c" else "run", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    with RssSampler(proc.pid, interval) as sampler:
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = proc.communicate()
            out += "\n- TIMEOUT"
    data = parse_output(out)
    data["exit"] = proc.returncode
    peak = sampler.peak_kb()
    if peak == 0:
        # Short programs exit before the first poll. RUSAGE_CHILDREN still knows
        # their high-water mark; macOS reports bytes, Linux reports KiB.
        raw = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        peak = raw // 1024 if sys.platform == "darwin" else raw
    data["peak_rss_kb"] = peak
    growth, head, tail = sampler.growth()
    data["rss_growth"] = round(growth, 4)
    data["rss_head_kb"] = head
    data["rss_tail_kb"] = tail
    if err.strip():
        data["stderr"] = err.strip()[-4000:]
    return data, out


def fmt_kb(kb: int) -> str:
    if kb >= 1024 * 1024:
        return f"{kb / 1024 / 1024:.1f} GiB"
    if kb >= 1024:
        return f"{kb / 1024:.1f} MiB"
    return f"{kb} KiB"


def report(data: dict, top: int, path: pathlib.Path) -> None:
    print(f"# {path}")
    print(f"result     {data['result']}")
    print(f"exit       {data['exit']}")
    if data["time_s"] is not None:
        print(f"time       {data['time_s']:.3f}s")
    if data["itrs"] is not None:
        print(f"itrs       {data['itrs']:,}")
    if data["mips"] is not None:
        print(f"mips       {data['mips']:.2f}")
    if data["nodes"] is not None:
        pct = 100.0 * data["nodes"] / data["nodes_cap"] if data["nodes_cap"] else 0.0
        print(f"nodes      {data['nodes']:,} / {data['nodes_cap']:,} ({pct:.3f}%)")
    if data["vars"] is not None:
        pct = 100.0 * data["vars"] / data["vars_cap"] if data["vars_cap"] else 0.0
        print(f"vars       {data['vars']:,} / {data['vars_cap']:,} ({pct:.3f}%)")
    print(f"rss peak   {fmt_kb(data['peak_rss_kb'])}")
    print(f"rss trend  {data['rss_growth']:+.1%} ({fmt_kb(data['rss_head_kb'])} -> {fmt_kb(data['rss_tail_kb'])})")
    if data["rss_growth"] > 0.25 and data["peak_rss_kb"] > 64 * 1024:
        print("warning    resident memory kept climbing; treat as a possible leak")
    elif data["rss_growth"] > 0.25:
        print("note       memory grew, but the absolute footprint is small")
    if data.get("stderr"):
        print("stderr")
        for line in data["stderr"].splitlines()[-10:]:
            print(f"           {line}")
    rules = {k: v for k, v in data["rules"].items() if k not in ("total", "itrs_inc")}
    if rules:
        total = data["rules"].get("total", sum(rules.values()))
        parts = [f"{k} {v:,} ({100.0 * v / total:.0f}%)" for k, v in rules.items()]
        print(f"rules      {total:,}: " + ", ".join(parts))
    rows = data["profile"][:top]
    if rows:
        total = sum(r["count"] for r in data["profile"])
        print(f"profile    {len(data['profile'])} definition(s), {total:,} call interactions")
        width = max(len(r["def"]) for r in rows)
        for row in rows:
            share = 100.0 * row["count"] / total if total else 0.0
            print(f"  {row['count']:>12,}  {share:5.1f}%  {row['def']:<{width}}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("program", type=pathlib.Path, help="compiled .hvm file")
    parser.add_argument("--top", type=int, default=20, help="profile rows to show (default: 20)")
    parser.add_argument("--timeout", type=float, default=600.0, help="wall-clock limit in seconds")
    parser.add_argument("--interval", type=float, default=0.02, help="RSS sampling interval in seconds")
    parser.add_argument(
        "--runtime",
        choices=("interp", "c"),
        default="interp",
        help="interp (default) or the compiled C runtime, which also reports per-thread ITRS",
    )
    parser.add_argument("--json", action="store_true", help="emit the raw numbers as JSON")
    args = parser.parse_args()

    if shutil.which("ps") is None:
        print("warning: `ps` not found; RSS will not be sampled", file=sys.stderr)

    data, _ = run(args.program, args.timeout, args.interval, args.runtime)
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        report(data, args.top, args.program)
    return 0 if data["exit"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
