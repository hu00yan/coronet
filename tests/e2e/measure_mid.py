#!/usr/bin/env python3
"""Measure the expansion of Coronet output at the book level.

Reports, per CoreLite input and per target: emitted bytes, definition count,
definitions reachable from @main, and how many definitions are alpha-identical
duplicates of another definition. Those are the three numbers a middle-end that
prunes and merges early has to move, and they are cheap to reproduce.

Usage:
  python3 tests/e2e/measure_mid.py                  # measure the default corpus
  python3 tests/e2e/measure_mid.py --json base.json # save a baseline
  python3 tests/e2e/measure_mid.py --baseline base.json  # diff against it
  python3 tests/e2e/measure_mid.py --run            # also run HVM2 for ITRS/time
"""

import argparse
import collections
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
COMPILER = REPO_ROOT / "_build" / "native" / "debug" / "build" / "cmd" / "main" / "main.exe"
HVM2_BIN = REPO_ROOT / "vendor" / "HVM2" / "target" / "release" / "hvm"

DEFAULT_CORPUS = [
    "tests/fixtures/core/01_arith.core",
    "tests/fixtures/core/03_adt.core",
    "tests/fixtures/core/05_tree.core",
    "tests/fixtures/core/07_nqueens.core",
    "tests/fixtures/core/08_mergesort.core",
    "tests/packages/bytestring_core.core",
    "tests/packages/map_core.core",
    "tests/packages/ghc/GhcCompiler.core",
]

DEF_LINE = re.compile(r"^@([A-Za-z0-9_$.'\-]+)\s*[=(]")
REF = re.compile(r"@([A-Za-z0-9_$.'\-]+)")
IDENT = re.compile(r"\b[A-Za-z_][A-Za-z0-9_$.'\-]*\b")


def split_defs(text):
    """Split an HVM book into {name: block}. The block includes the definition
    header, so callers that compare bodies must strip it first."""
    defs = {}
    order = []
    current = None
    for line in text.splitlines():
        m = DEF_LINE.match(line)
        if m:
            current = m.group(1)
            defs[current] = [line]
            order.append(current)
        elif current is not None:
            defs[current].append(line)
    return {name: "\n".join(defs[name]) for name in order}


def def_value(block):
    _, _, value = block.partition("=")
    return value


def alpha_key(body):
    """Alpha-canonical form: local names renamed by first occurrence."""
    body = def_value(body)
    mapping = {}

    def rename(match):
        tok = match.group(0)
        if tok not in mapping:
            mapping[tok] = "v%d" % len(mapping)
        return mapping[tok]

    out = []
    for part in re.split(r"(@[A-Za-z0-9_$.'\-]+)", body):
        out.append(part if part.startswith("@") else IDENT.sub(rename, part))
    return "".join(out)


def reachable(defs, roots):
    seen = set()
    stack = [r for r in roots if r in defs]
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        for ref in REF.findall(defs[name]):
            if ref in defs and ref not in seen:
                stack.append(ref)
    return seen


def measure_text(text):
    defs = split_defs(text)
    live = reachable(defs, ["main"])
    groups = collections.defaultdict(list)
    for name, body in defs.items():
        groups[alpha_key(body)].append(name)
    dup_groups = [g for g in groups.values() if len(g) > 1 and len(defs[g[0]]) > 8]
    return {
        "bytes": len(text),
        "defs": len(defs),
        "reachable": len(live),
        "dead": len(defs) - len(live),
        "dup_groups": len(dup_groups),
        "dup_defs": sum(len(g) for g in dup_groups),
    }


def compile_target(core, target, extra=()):
    proc = subprocess.run(
        [str(COMPILER), str(core), "--target", target, *extra],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=600,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_hvm2(text):
    path = REPO_ROOT / "_build" / "mid" / "measure.hvm"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    proc = subprocess.run(
        [str(HVM2_BIN), "run", str(path)],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=600,
    )
    itrs = re.search(r"ITRS:\s*([0-9]+)", proc.stdout)
    elapsed = re.search(r"TIME:\s*([0-9.]+)s", proc.stdout)
    result = re.search(r"Result:\s*(.+)", proc.stdout)
    return {
        "itrs": int(itrs.group(1)) if itrs else None,
        "time": float(elapsed.group(1)) if elapsed else None,
        "result": result.group(1).strip() if result else None,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="*", default=DEFAULT_CORPUS)
    parser.add_argument("--json", help="write measurements to this file")
    parser.add_argument("--baseline", help="diff against a saved measurement file")
    parser.add_argument("--run", action="store_true", help="also run HVM2")
    parser.add_argument(
        "--raw",
        action="store_true",
        help="also measure with --no-prune, i.e. the unpruned, unmerged book",
    )
    args = parser.parse_args()

    if not COMPILER.exists():
        sys.exit("compiler not built: moon build --target native")

    rows = {}
    for rel in args.inputs:
        core = REPO_ROOT / rel
        row = {"input": rel, "core_bytes": core.stat().st_size}
        for target in ("hvm2", "hvm3"):
            start = time.perf_counter()
            code, out, err = compile_target(core, target)
            row[target] = measure_text(out) if code == 0 else {"error": err.strip()[:200]}
            row[target]["compile_s"] = round(time.perf_counter() - start, 2)
        if args.raw:
            code, out, err = compile_target(core, "hvm2", ("--no-prune",))
            row["hvm2_raw"] = measure_text(out) if code == 0 else {"error": err.strip()[:200]}
        if args.run and "error" not in row["hvm2"]:
            _, out, _ = compile_target(core, "hvm2")
            row["run"] = run_hvm2(out)
        rows[rel] = row

    header = "| input | hvm2 bytes | hvm2 defs | reachable | dead | alpha-dup defs | hvm3 bytes | hvm3 defs |"
    if args.raw:
        header = header[:-1] + " raw bytes | raw defs | raw alpha-dup defs |"
    print(header)
    cols = "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    if args.raw:
        cols += " ---: | ---: | ---: |"
    print(cols)
    for rel, row in rows.items():
        h2, h3 = row["hvm2"], row["hvm3"]
        if args.raw:
            raw = row.get("hvm2_raw", {})
            print(
                "| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |"
                % (
                    Path(rel).name,
                    h2.get("bytes", "-"), h2.get("defs", "-"), h2.get("reachable", "-"),
                    h2.get("dead", "-"), h2.get("dup_defs", "-"),
                    h3.get("bytes", "-"), h3.get("defs", "-"),
                    raw.get("bytes", "-"), raw.get("defs", "-"), raw.get("dup_defs", "-"),
                )
            )
            continue
        print(
            "| `%s` | %s | %s | %s | %s | %s | %s | %s |"
            % (
                Path(rel).name,
                h2.get("bytes", "-"),
                h2.get("defs", "-"),
                h2.get("reachable", "-"),
                h2.get("dead", "-"),
                h2.get("dup_defs", "-"),
                h3.get("bytes", "-"),
                h3.get("defs", "-"),
            )
        )
    if args.run:
        print()
        for rel, row in rows.items():
            if "run" in row:
                print("`%s` run: %s" % (Path(rel).name, row["run"]))

    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=2) + "\n")
        print("\nwrote %s" % args.json)

    if args.baseline:
        base = json.loads(Path(args.baseline).read_text())
        print("\n| input | hvm2 defs | delta | hvm2 bytes | delta | alpha-dup defs | delta |")
        print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for rel, row in rows.items():
            old = base.get(rel)
            if not old:
                continue
            for target in ("hvm2",):
                o, n = old[target], row[target]
                print(
                    "| `%s` | %s | %+d | %s | %+d | %s | %+d |"
                    % (
                        Path(rel).name,
                        o.get("defs"), n.get("defs", 0) - o.get("defs", 0),
                        o.get("bytes"), n.get("bytes", 0) - o.get("bytes", 0),
                        o.get("dup_defs"), n.get("dup_defs", 0) - o.get("dup_defs", 0),
                    )
                )


if __name__ == "__main__":
    main()
