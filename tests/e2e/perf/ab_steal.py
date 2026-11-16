#!/usr/bin/env python3
"""Interleaved A/B of the HVM2 steal strategies (CORONET-STEAL patch).

Reproduces every number in the PERF_BASELINE.md scheduling section:

    python3 tests/e2e/perf/ab_steal.py                     # full matrix
    python3 tests/e2e/perf/ab_steal.py --rounds 15
    python3 tests/e2e/perf/ab_steal.py --modes half,halfscan

Design:
* Inputs: nqueens9 (22.9M ITRS, the showcase), 07_nqueens (4.5M, medium),
  map300 (2.1M, spawn-dominated control).
* Configs: baseline (HVM_STEAL unset), half, scan, halfscan, boot.
* Each round runs every (input, threads, config) once, configs in a rotated
  order so no config systematically sees early/late machine drift; a stub
  run (same book, @main = 0) per (input, threads, round) gives eval = wall
  real - wall stub with the same process-spawn cost on both sides.
* Reports median/min/max wall and eval seconds per cell, the Result line
  (bit-identical check), and ITRS per cell (confluence check).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import perf_baseline as P

INPUTS = ["tests/e2e/perf/inputs/nqueens9.core",
          "tests/fixtures/core/07_nqueens.core",
          "tests/e2e/perf/inputs/map300.core"]
MODES = ["", "half", "walk", "scan", "scanwalk", "scancap", "boot"]
THREADS = [0, 1, 2, 3]  # TPC_L2 values => 1, 2, 4, 8 threads

ITRS_RE = re.compile(r"- ITRS: (\d+)")
RESULT_RE = re.compile(r"Result: (.*)")


def one_run(exe, mode):
    env = {k: v for k, v in os.environ.items()
           if k not in ("HVM_STEAL", "HVM_DIAG")}
    if mode:
        env["HVM_STEAL"] = mode
    start = time.perf_counter()
    proc = subprocess.run([str(exe)], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=300, env=env)
    wall = time.perf_counter() - start
    itrs = ITRS_RE.search(proc.stdout)
    res = RESULT_RE.search(proc.stdout)
    return {
        "wall_s": round(wall, 4),
        "rc": proc.returncode,
        "itrs": int(itrs.group(1)) if itrs else None,
        "result": res.group(1).strip() if res else None,
    }


def load1():
    out = subprocess.run(["uptime"], capture_output=True, text=True).stdout
    return out.strip().split("load averages:")[-1].strip()


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=15)
    ap.add_argument("--modes", default=",".join(MODES))
    ap.add_argument("--threads", default=",".join(str(t) for t in THREADS))
    ap.add_argument("--json", default="_build/perf/ab_steal.json")
    args = ap.parse_args()
    modes = args.modes.split(",")
    threads = [int(t) for t in args.threads.split(",")]

    # Build every binary once up front.
    print("building binaries...", file=sys.stderr)
    bins = {}  # (stem, tpc, is_stub) -> exe
    for core in INPUTS:
        book, err = P.compile_artifact(core, "hvm2", 300)
        assert book, err
        stub = P.make_stub(book)
        for tpc in threads:
            exe, err = P.build_c(book, tpc, 300)
            assert exe, err
            stub_exe, err = P.build_c(stub, tpc, 300)
            assert stub_exe, err
            bins[(book.parent.name, tpc, False)] = exe
            bins[(book.parent.name, tpc, True)] = stub_exe
            print("  built %s t%d" % (book.parent.name, tpc), file=sys.stderr)

    stems = [Path(c).stem + ".hvm2" for c in INPUTS]

    # Warm every binary once: the first execution of a fresh binary pays a
    # page-in cost of up to 10x on this machine, which would otherwise land
    # on whichever mode runs first.
    print("warming binaries...", file=sys.stderr)
    for (stem, tpc, is_stub), exe in sorted(bins.items()):
        one_run(exe, "")
    print("warm.", file=sys.stderr)

    rows = []
    for rnd in range(args.rounds):
        t0 = time.perf_counter()
        # rotate the mode order each round so no config systematically runs
        # first (warm caches) or last (accumulated drift) within a round
        order = modes[rnd % len(modes):] + modes[:rnd % len(modes)]
        cells = [(stem, tpc, mode) for stem in stems for tpc in threads for mode in order]
        for stem, tpc, mode in cells:
            row = one_run(bins[(stem, tpc, False)], mode)
            row.update(stem=stem, tpc=tpc, mode=mode or "base", round=rnd)
            rows.append(row)
            print(json.dumps(row), flush=True)
        for stem in stems:
            for tpc in threads:
                srow = one_run(bins[(stem, tpc, True)], "")
                srow.update(stem=stem, tpc=tpc, mode="stub", round=rnd)
                rows.append(srow)
        print("round %d done in %.1fs, load %s" % (rnd, time.perf_counter() - t0, load1()),
              file=sys.stderr)
    Path(args.json).parent.mkdir(parents=True, exist_ok=True)
    Path(args.json).write_text(json.dumps(rows, indent=1))

    # ---- report ----
    print("\n# A/B steal matrix, %d rounds, median (min..max) wall/eval seconds\n" % args.rounds)
    print("| input | thr | mode | wall med | wall min..max | eval med | eval min..max | result | ITRS |")
    print("| --- | ---: | --- | ---: | --- | ---: | --- | --- | ---: |")
    for stem, tpc in sorted({(c[0], c[1]) for c in cells}):
        stub_wall = median([r["wall_s"] for r in rows
                            if r["stem"] == stem and r["tpc"] == tpc and r["mode"] == "stub"])
        for mode in modes:
            rs = [r for r in rows if r["stem"] == stem and r["tpc"] == tpc
                  and r["mode"] == (mode or "base")]
            walls = sorted(r["wall_s"] for r in rs)
            evals = sorted(max(1e-6, r["wall_s"] - stub_wall) for r in rs)
            results = {r["result"] for r in rs}
            itrss = {r["itrs"] for r in rs}
            res = next(iter(results)) if len(results) == 1 else "MISMATCH:%s" % results
            itr = next(iter(itrss)) if len(itrss) == 1 else "VARIES:%s" % itrss
            print("| `%s` | %d | %s | %.4f | %.4f..%.4f | %.4f | %.4f..%.4f | %s | %s |"
                  % (stem, 1 << tpc, mode or "base", median(walls),
                     walls[0], walls[-1], median(evals), evals[0], evals[-1], res, itr))
    print("\nload at end: %s" % load1())


if __name__ == "__main__":
    main()
