#!/usr/bin/env python3
"""Coronet performance baseline: compile cost, artifact size, runtime, scaling.

One command reproduces every number in ``docs/PERF_BASELINE.md``:

    python3 tests/e2e/perf/perf_baseline.py
    python3 tests/e2e/perf/perf_baseline.py --json /tmp/perf.json
    python3 tests/e2e/perf/perf_baseline.py --doc docs/PERF_BASELINE.md
    python3 tests/e2e/perf/perf_baseline.py --only map300

What it measures, per input:

* **Compile** — wall time of each pipeline stage (read/parse/link/mid/lower/prune)
  from ``src/mid/trace/main``, the instrumented twin of ``cmd/main``. The harness
  asserts the traced book is byte-identical to the shipping CLI's book, so the
  instrument cannot drift from the compiler. Compiler is the MoonBit *release*
  build: debug numbers are ~2.6x slower and say nothing about the shipped tool.
* **Artifact** — emitted HVM2 book bytes and definition count.
* **Load/startup** — the book is recompiled to a stub whose ``@main`` is the
  constant ``0`` and nothing else changes, so the stub pays process start, book
  read, book build, thread spawn and readback but performs no rewriting.
  ``load = wall(stub)``; ``eval = wall(real) - wall(stub)``. This is the only way
  to get sub-centisecond resolution: the runtimes print ``TIME`` with two
  decimals, which is 7% quantization on a 0.15 s run.
* **Run** — HVM2 result, ITRS, evaluator seconds, load seconds, wall seconds.
* **Scaling** — the same book through ``hvm gen-c`` compiled at TPC_L2 = 0,1,2,3
  (1, 2, 4, 8 threads) with ``clang -O3``. Speedup is stall-free evaluator time
  at 1 thread over N threads. ITRS is reported per thread count because a
  well-behaved net rewrites the same number of times regardless of scheduling —
  a changing count would mean the runtime is not confluent under its scheduler.

Every subprocess is wrapped in a timeout; a run that does not finish is recorded
as ``timeout`` instead of hanging the suite.
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
RELEASE_COMPILER = REPO_ROOT / "_build/native/release/build/cmd/main/main.exe"
RELEASE_TRACE = REPO_ROOT / "_build/native/release/build/src/mid/trace/main/main.exe"
DEBUG_COMPILER = REPO_ROOT / "_build/native/debug/build/cmd/main/main.exe"
HVM2_BIN = REPO_ROOT / "vendor/HVM2/target/release/hvm"
HVM3_BIN = (
    REPO_ROOT
    / "vendor/HVM3/dist-newstyle/build/aarch64-osx/ghc-9.14.1/HVM-0.1.0.0/x/hvm/opt/build/hvm/hvm"
)
SCRATCH = REPO_ROOT / "_build/perf"

#: Semantic fixtures. They are all small (1 to 8.4M ITRS); they exist to prove
#: compile and run cost on a broad shape vocabulary, not to scale.
FIXTURES = [
    "tests/fixtures/core/01_arith.core",
    "tests/fixtures/core/02_fib.core",
    "tests/fixtures/core/03_adt.core",
    "tests/fixtures/core/04_higher_order.core",
    "tests/fixtures/core/05_tree.core",
    "tests/fixtures/core/06_lazy_stream.core",
    "tests/fixtures/core/07_nqueens.core",
    "tests/fixtures/core/08_mergesort.core",
]

#: Real GHC Core extracted from Hackage packages. These are the compile-cost
#: inputs: bytestring and map are program-sized, GhcCompiler is the 1127-def
#: scale ladder.
PACKAGES = [
    "tests/packages/bytestring_core.core",
    "tests/packages/map_core.core",
    "tests/packages/ghc/GhcCompiler.core",
]

#: Scaled duplicates of two fixtures, kept here rather than in tests/fixtures
#: (which the correctness line owns). Sizes chosen so a single-thread run is
#: 0.5 s to 3 s, which is where a speedup curve means something.
SCALED = [
    "tests/e2e/perf/inputs/nqueens9.core",
    "tests/e2e/perf/inputs/map300.core",
]

CORPUS = FIXTURES + PACKAGES + SCALED

ITRS_RE = re.compile(r"ITRS:\s*([0-9]+)")
TIME_RE = re.compile(r"TIME:\s*([0-9.]+)s")
MIPS_RE = re.compile(r"MIPS:\s*([0-9.]+)")
RESULT_RE = re.compile(r"Result:\s*(.+)")


def run(cmd, timeout, cwd=None):
    """Run a command, never hang. Returns (rc, stdout, stderr, wall_seconds)."""
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            [str(c) for c in cmd],
            cwd=str(cwd or REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr, time.perf_counter() - start
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        return "timeout", out, "", time.perf_counter() - start


# ---------------------------------------------------------------------------
# compile
# ---------------------------------------------------------------------------

def trace_compile(core, target, reps, timeout):
    """Per-stage compile time (microseconds, minimum over `reps`), plus artifact size."""
    rc, out, _err, _wall = run(
        [RELEASE_TRACE, core, "--target", target, "--repeat", reps], timeout
    )
    if rc != 0:
        return {"error": (_err or out).strip()[:300]}
    try:
        return json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"error": out.strip()[:300]}


def check_trace_matches_cli(core, target, timeout):
    """The instrument must emit exactly what the shipping CLI emits."""
    cli_book = SCRATCH / "cli_check.hvm"
    trace_book = SCRATCH / "trace_check.hvm"
    SCRATCH.mkdir(parents=True, exist_ok=True)
    rc, _out, _err, _ = run([RELEASE_COMPILER, core, "--target", target, "-o", cli_book], timeout)
    if rc != 0:
        return False
    rc, _out, _err, _ = run(
        [RELEASE_TRACE, core, "--target", target, "--repeat", 0, "--emit", trace_book],
        timeout,
    )
    if rc != 0 or not trace_book.exists():
        return False
    return cli_book.read_bytes() == trace_book.read_bytes()


# ---------------------------------------------------------------------------
# artifacts
# ---------------------------------------------------------------------------

def compile_artifact(core, target, timeout):
    """Emit the book into a per-input scratch directory."""
    path = SCRATCH / (Path(core).stem + "." + target) / "book.hvm"
    path.parent.mkdir(parents=True, exist_ok=True)
    rc, out, err, _ = run([RELEASE_COMPILER, core, "--target", target, "-o", path], timeout)
    if rc != 0:
        return None, (err or out).strip()[:300]
    return path, None


def make_stub(book):
    """Same book, ``@main`` replaced by the constant 0.

    Pruning already removed every definition ``@main`` cannot reach, so this
    leaves the reference graph intact (the definitions are still present as text
    and still parsed and built) while making the evaluator do zero work. The
    difference between running the real book and running the stub is therefore
    pure startup plus rewriting.
    """
    stub = book.parent / (book.stem + ".stub.hvm")
    lines = book.read_text().splitlines(keepends=True)
    out = []
    skipping = False
    for line in lines:
        if line.startswith("@main"):
            out.append("@main = 0\n")
            skipping = True
            continue
        if skipping:
            # A definition block continues while lines are indented.
            if line[:1] in (" ", "\t", "") and not line.startswith("@"):
                continue
            skipping = False
        out.append(line)
    stub.write_text("".join(out))
    return stub


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

def parse_hvm_output(text):
    itrs = ITRS_RE.search(text)
    elapsed = TIME_RE.search(text)
    mips = MIPS_RE.search(text)
    result = RESULT_RE.search(text)
    return {
        "itrs": int(itrs.group(1)) if itrs else None,
        "reported_eval_s": float(elapsed.group(1)) if elapsed else None,
        "reported_mips": float(mips.group(1)) if mips else None,
        "result": result.group(1).strip() if result else None,
    }


def time_binary(exe, reps, timeout):
    """Minimum wall time over `reps` runs of an executable plus its report."""
    best = None
    for _ in range(reps):
        rc, out, err, wall = run([exe], timeout)
        if rc == "timeout":
            return {"status": "timeout", "wall_s": round(wall, 3)}
        if rc != 0:
            return {"status": "error", "rc": rc, "detail": (err or out).strip()[:300]}
        row = parse_hvm_output(out)
        row["wall_s"] = wall
        if best is None or wall < best["wall_s"]:
            best = row
    return best or {"status": "error", "detail": "no run"}


def run_rust(book, stub, reps, timeout):
    """HVM2's Rust interpreter. `hvm run` has no thread flag: TMem::new(0, 1)."""
    real = time_binary_rust(book, reps, timeout)
    if real.get("status") != "ok":
        return real
    base = time_binary_rust(stub, reps, timeout)
    if base.get("status") != "ok":
        return real
    real["load_s"] = round(base["wall_s"], 4)
    real["eval_s"] = round(real["wall_s"] - base["wall_s"], 4)
    return real


def time_binary_rust(book, reps, timeout):
    best = None
    for _ in range(reps):
        rc, out, err, wall = run([HVM2_BIN, "run", book], timeout)
        if rc == "timeout":
            return {"status": "timeout", "wall_s": round(wall, 3)}
        if rc != 0:
            return {"status": "error", "rc": rc, "detail": (err or out).strip()[:300]}
        row = parse_hvm_output(out)
        row["wall_s"] = wall
        if best is None or wall < best["wall_s"]:
            best = row
    best["status"] = "ok"
    return best


def build_c(book, tpc, timeout):
    """`hvm gen-c` the book and compile it at a fixed thread count."""
    stem = book.stem
    gen = book.parent / (stem + ".generated.c")
    if not gen.exists():
        rc, out, err, _ = run([HVM2_BIN, "gen-c", book], max(120, timeout))
        if rc != 0 or not out.strip():
            return None, (err or out).strip()[:300] or "gen-c produced nothing"
        gen.write_text(out)
    source = gen.read_text()
    # `gen-c` writes `#define TPC_L2 <log2(cores)>` inside an #ifndef guard, so
    # rewriting that line is how a thread count is selected (no rebuild of HVM2).
    patched = re.sub(
        r"^#define TPC_L2 \d+.*$", "#define TPC_L2 %d" % tpc, source, count=1, flags=re.M
    )
    src = book.parent / ("%s.t%d.c" % (stem, tpc))
    exe = book.parent / ("%s.t%d" % (stem, tpc))
    src.write_text(patched)
    rc, _out, err, _ = run(["clang", "-O3", "-w", src, "-o", exe, "-lpthread", "-lm"],
                           max(180, timeout))
    if rc != 0:
        return None, "clang: " + err.strip()[:250]
    return exe, None


def run_c_scaling(book, stub, thread_counts, reps, timeout):
    rows = {}
    for tpc in thread_counts:
        exe, err = build_c(book, tpc, timeout)
        if exe is None:
            rows[str(tpc)] = {"status": "error", "detail": err}
            continue
        real = time_binary(exe, reps, timeout)
        if real.get("status", "ok") != "ok":
            rows[str(tpc)] = real
            if real.get("status") == "timeout":
                # Nothing to be learned from narrower or wider thread counts if
                # the single-thread run does not finish.
                break
            continue
        stub_exe, stub_err = build_c(stub, tpc, timeout)
        if stub_exe is None:
            rows[str(tpc)] = {"status": "error", "detail": stub_err}
            continue
        base = time_binary(stub_exe, reps, timeout)
        if base.get("status", "ok") != "ok":
            rows[str(tpc)] = base
            continue
        eval_s = max(1e-6, real["wall_s"] - base["wall_s"])
        rows[str(tpc)] = {
            "status": "ok",
            "threads": 1 << tpc,
            "itrs": real["itrs"],
            "eval_s": round(eval_s, 4),
            "load_s": round(base["wall_s"], 4),
            "wall_s": round(real["wall_s"], 4),
            "reported_eval_s": real["reported_eval_s"],
            "mips": round(real["itrs"] / eval_s / 1e6, 2) if real["itrs"] else None,
            "result": real["result"],
        }
    return rows


def run_hvm3(core, timeout):
    if not HVM3_BIN.exists():
        return {"status": "unavailable"}
    book, err = compile_artifact(core, "hvm3", timeout)
    if book is None:
        return {"status": "error", "detail": err}
    rc, out, err, wall = run([HVM3_BIN, "run", book, "-s"], timeout)
    if rc == "timeout":
        return {"status": "timeout", "wall_s": round(wall, 3)}
    if rc != 0:
        return {"status": "error", "detail": (err or out).strip()[:200]}
    work = re.search(r"WORK:\s*([0-9]+)", out)
    secs = re.search(r"TIME:\s*([0-9.]+)\s*seconds", out)
    return {
        "status": "ok",
        "itrs": int(work.group(1)) if work else None,
        "eval_s": float(secs.group(1)) if secs else None,
        "wall_s": round(wall, 4),
    }


# ---------------------------------------------------------------------------
# tables
# ---------------------------------------------------------------------------

def us_to_ms(value):
    """Stage timings are microseconds in JSON; the tables are milliseconds."""
    return "-" if value is None else "%.3f" % (value / 1000.0)


def sec(value, digits=3):
    return "-" if value is None else "%.*f" % (digits, value)


def markdown(report):
    meta = report["meta"]
    rows = report["rows"]
    out = []
    out.append("Machine: %s, %s, %s performance cores, %s logical cores."
               % (meta["cpu"], meta["machine"], meta["physical_cores"], meta["logical_cores"]))
    out.append("Compiler: MoonBit native release build. HVM2: `%s`." % meta["hvm2"])
    out.append("Thread counts: `hvm gen-c` output compiled with `TPC_L2=n` (n=0..3 => 1,2,4,8 threads).")
    out.append("")
    out.append("#### Compile time per stage (ms, min of %d runs)" % meta["reps"])
    out.append("")
    out.append("| input | core KB | read | parse | link | mid | lower | prune | total | out bytes | out defs | CLI match |")
    out.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :---: |")
    for name, row in rows.items():
        c = row.get("compile") or {}
        match = "yes" if row.get("trace_matches_cli") else "NO"
        if "error" in c:
            out.append("| `%s` | %s | ERROR: %s ||||||||| %s |"
                       % (name, row["core_kb"], c["error"][:50], match))
            continue
        out.append(
            "| `%s` | %.1f | %s | %s | %s | %s | %s | %s | **%s** | %s | %s | %s |"
            % (
                name, row["core_kb"],
                us_to_ms(c.get("read_us")), us_to_ms(c.get("parse_us")), us_to_ms(c.get("link_us")),
                us_to_ms(c.get("mid_us")), us_to_ms(c.get("lower_us")), us_to_ms(c.get("prune_us")),
                us_to_ms(c.get("total_us")), c.get("out_bytes"), c.get("out_defs"), match,
            )
        )
    out.append("")
    out.append("#### Runtime, HVM2 Rust interpreter (1 thread), seconds")
    out.append("")
    out.append("| input | result | ITRS | eval | load | wall | MIPS |")
    out.append("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for name, row in rows.items():
        r = row.get("rust")
        if not r:
            continue
        if r.get("status") != "ok":
            out.append("| `%s` | **%s** | - | - | - | %s | - |"
                       % (name, r.get("status"), sec(r.get("wall_s")), ))
            continue
        mips = None
        if r.get("itrs") and r.get("eval_s"):
            mips = r["itrs"] / r["eval_s"] / 1e6
        out.append("| `%s` | `%s` | %s | %s | %s | %s | %s |"
                   % (name, r.get("result"), r.get("itrs"), sec(r.get("eval_s")),
                      sec(r.get("load_s")), sec(r.get("wall_s")), sec(mips, 1)))
    out.append("")
    if any(row.get("c") for row in rows.values()):
        threads = meta["threads"]
        out.append("#### HVM2 C runtime scaling (evaluator seconds, min of %d runs)" % meta["reps"])
        out.append("")
        out.append("| input | ITRS | " + " | ".join("%dT" % (1 << t) for t in threads) + " | "
                   + " | ".join("x%d" % (1 << t) for t in threads) + " |")
        out.append("| --- | ---: | " + " | ".join("---:" for _ in threads) + " | "
                   + " | ".join("---:" for _ in threads) + " |")
        for name, row in rows.items():
            c = row.get("c")
            if not c:
                continue
            base = (c.get(str(threads[0])) or {}).get("eval_s")
            itrs = (c.get(str(threads[0])) or {}).get("itrs")
            cells, speeds = [], []
            for t in threads:
                cell = c.get(str(t)) or {}
                if cell.get("status") != "ok":
                    cells.append(cell.get("status", "-"))
                    speeds.append("-")
                else:
                    cells.append(sec(cell.get("eval_s")))
                    speeds.append("%.2fx" % (base / cell["eval_s"]) if base and cell.get("eval_s") else "-")
            out.append("| `%s` | %s | %s | %s |" % (name, itrs, " | ".join(cells), " | ".join(speeds)))
        out.append("")
        out.append("#### ITRS and throughput per thread count (scheduler confluence check)")
        out.append("")
        out.append("| input | " + " | ".join("%dT ITRS / MIPS" % (1 << t) for t in threads) + " |")
        out.append("| --- | " + " | ".join("---:" for _ in threads) + " |")
        for name, row in rows.items():
            c = row.get("c")
            if not c:
                continue
            cells = []
            for t in threads:
                cell = c.get(str(t)) or {}
                if cell.get("status") != "ok":
                    cells.append(cell.get("status", "-"))
                else:
                    cells.append("%s / %s" % (cell.get("itrs"), sec(cell.get("mips"), 1)))
            out.append("| `%s` | %s |" % (name, " | ".join(cells)))
        out.append("")
    if any(row.get("hvm3") for row in rows.values()):
        out.append("#### HVM3 (`hvm run -s`, interpreted, single thread)")
        out.append("")
        out.append("| input | interactions | eval s | wall s |")
        out.append("| --- | ---: | ---: | ---: |")
        for name, row in rows.items():
            h = row.get("hvm3")
            if not h:
                continue
            if h.get("status") != "ok":
                out.append("| `%s` | - | - | %s |" % (name, h.get("status")))
                continue
            out.append("| `%s` | %s | %s | %s |"
                       % (name, h.get("itrs"), sec(h.get("eval_s"), 6), sec(h.get("wall_s"))))
        out.append("")
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="*", default=CORPUS)
    parser.add_argument("--reps", type=int, default=5, help="repetitions, minimum is kept")
    parser.add_argument("--timeout", type=int, default=120, help="per-subprocess timeout (s)")
    parser.add_argument("--threads", default="0,1,2,3", help="TPC_L2 values: 0=1T,1=2T,2=4T,3=8T")
    parser.add_argument("--json", help="write raw measurements here")
    parser.add_argument("--doc", help="write the markdown tables here")
    parser.add_argument("--no-run", action="store_true", help="compile only")
    parser.add_argument("--no-threads", action="store_true", help="skip the C scaling sweep")
    parser.add_argument("--no-hvm3", action="store_true", help="skip HVM3")
    parser.add_argument("--only", help="substring filter on input name")
    args = parser.parse_args()

    for tool in (RELEASE_COMPILER, RELEASE_TRACE, HVM2_BIN):
        if not tool.exists():
            sys.exit("missing tool: %s\n  build with: moon build --target native --release"
                     % tool)
    if not shutil.which("clang"):
        sys.exit("clang not found (needed for the scaling sweep)")
    SCRATCH.mkdir(parents=True, exist_ok=True)

    threads = [int(t) for t in args.threads.split(",") if t.strip()]
    rows = {}
    for rel in args.inputs:
        core = REPO_ROOT / rel
        if not core.exists():
            print("skip (missing): %s" % rel, file=sys.stderr)
            continue
        name = Path(rel).stem
        if args.only and args.only not in name:
            continue
        print("... %s" % name, file=sys.stderr)
        row = {"input": rel, "core_kb": core.stat().st_size / 1024.0}
        row["compile"] = trace_compile(core, "hvm2", args.reps, args.timeout)
        row["trace_matches_cli"] = check_trace_matches_cli(core, "hvm2", args.timeout)
        if not args.no_run:
            book, err = compile_artifact(core, "hvm2", args.timeout)
            if book is None:
                row["rust"] = {"status": "compile-error", "detail": err}
            else:
                stub = make_stub(book)
                row["rust"] = run_rust(book, stub, args.reps, args.timeout)
                if not args.no_threads:
                    row["c"] = run_c_scaling(book, stub, threads, args.reps, args.timeout)
            if not args.no_hvm3:
                row["hvm3"] = run_hvm3(core, args.timeout)
        rows[name] = row

    def sysctl(key):
        try:
            return subprocess.run(["sysctl", "-n", key], stdout=subprocess.PIPE,
                                  text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return "?"

    rc, out, _e, _w = run([HVM2_BIN, "--version"], 20)
    report = {
        "meta": {
            "cpu": sysctl("machdep.cpu.brand_string") or platform.processor(),
            "machine": platform.machine(),
            "physical_cores": sysctl("hw.perflevel0.physicalcpu"),
            "logical_cores": os.cpu_count(),
            "reps": args.reps,
            "threads": threads,
            "hvm2": out.strip().splitlines()[0] if rc == 0 and out.strip() else "unknown",
        },
        "rows": rows,
    }
    text = markdown(report)
    print(text)
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=2) + "\n")
        print("\nwrote %s" % args.json, file=sys.stderr)
    if args.doc:
        Path(args.doc).write_text(text + "\n")
        print("wrote %s" % args.doc, file=sys.stderr)


if __name__ == "__main__":
    main()
