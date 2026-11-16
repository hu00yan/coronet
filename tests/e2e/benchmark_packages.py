#!/usr/bin/env python3
"""
Coronet Real Package Benchmark Harness
Benchmarks Hackage package workloads:
1. Data.ByteString (tests/packages/bytestring_core.hs)
2. Data.Map (tests/packages/map_core.hs)
Compares execution across GHC -O2, HVM2 (multi-core / compiled C), and HVM3.
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PACKAGES_DIR = REPO_ROOT / "tests" / "packages"
CORONET_BIN = REPO_ROOT / "bin" / "coronet"
BUILD_DIR = REPO_ROOT / "_build" / "packages"

BENCHMARKS = [
    {
        "name": "bytestring_core",
        "hs": PACKAGES_DIR / "bytestring_core.hs",
        "core": PACKAGES_DIR / "bytestring_core.core",
        "expected": "960463596",
        "description": "Hackage Data.ByteString packing, memory offsets, and checksum folding",
    },
    {
        "name": "map_core",
        "hs": PACKAGES_DIR / "map_core.hs",
        "core": PACKAGES_DIR / "map_core.core",
        "expected": "10570",
        "description": "Hackage Data.Map Size-Balanced BST with rotations, balanceL/R, and key lookups",
    },
]


def run_cmd(cmd, timeout=60, bypass=False):
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        elapsed = time.perf_counter() - start
        return proc.returncode, proc.stdout, proc.stderr, elapsed
    except subprocess.TimeoutExpired:
        elapsed = time.perf_counter() - start
        return -1, "", f"Timeout after {timeout}s", elapsed
    except Exception as e:
        elapsed = time.perf_counter() - start
        return -1, "", str(e), elapsed


def benchmark_ghc_native(hs_path: Path) -> Dict[str, Any]:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    bin_path = BUILD_DIR / f"{hs_path.stem}_ghc"
    # Compile with ghc -O2
    code, out, err, _ = run_cmd(["ghc", "-O2", str(hs_path), "-o", str(bin_path)])
    if code != 0:
        return {"ok": False, "error": f"GHC compile failed: {err}"}
    
    # Warmup and timed runs
    times = []
    output = ""
    for _ in range(5):
        code, out, err, dur = run_cmd([str(bin_path)])
        if code != 0:
            return {"ok": False, "error": f"GHC binary failed: {err}"}
        times.append(dur)
        output = out.strip()
    
    return {
        "ok": True,
        "result": output,
        "time": min(times),
    }


def benchmark_hvm2(core_path: Path) -> Dict[str, Any]:
    code, out, err, dur = run_cmd([str(CORONET_BIN), str(core_path), "--target", "hvm2"])
    if code != 0:
        return {"ok": False, "error": f"HVM2 run failed (code {code}): {err}\n{out}"}
    
    res_m = re.search(r"Result:\s*(.+)", out)
    itrs_m = re.search(r"ITRS:\s*([\d_]+)", out)
    time_m = re.search(r"TIME:\s*([\d\.]+)s", out)
    mips_m = re.search(r"MIPS:\s*([\d\.]+)", out)
    
    res = res_m.group(1).strip() if res_m else out.strip()
    itrs = int(itrs_m.group(1).replace("_", "")) if itrs_m else None
    t = float(time_m.group(1)) if time_m else dur
    mips = float(mips_m.group(1)) if mips_m else None
    
    return {
        "ok": True,
        "result": res,
        "time": t,
        "itrs": itrs,
        "mips": mips,
    }


def benchmark_hvm3(core_path: Path) -> Dict[str, Any]:
    code, out, err, dur = run_cmd([str(CORONET_BIN), str(core_path), "--target", "hvm3"])
    if code != 0:
        return {"ok": False, "error": f"HVM3 run failed (code {code}): {err}\n{out}"}
    
    lines = [l.strip() for l in out.strip().splitlines() if l.strip()]
    res = lines[-1] if lines else ""
    return {
        "ok": True,
        "result": res,
        "time": dur,
    }


def main():
    print("=== Coronet Real Package Benchmarks (Data.ByteString & Data.Map) ===\n")
    results = []
    
    for bench in BENCHMARKS:
        name = bench["name"]
        print(f"--> Benchmarking {name}...")
        expected = bench["expected"]
        
        # GHC Native
        ghc_res = benchmark_ghc_native(bench["hs"])
        print(f"    GHC -O2:    result={ghc_res.get('result')} time={ghc_res.get('time', 0):.4f}s")
        
        # HVM2
        hvm2_res = benchmark_hvm2(bench["core"])
        if hvm2_res["ok"]:
            print(f"    HVM2:       result={hvm2_res.get('result')} time={hvm2_res.get('time', 0):.4f}s itrs={hvm2_res.get('itrs')} mips={hvm2_res.get('mips')}")
        else:
            print(f"    HVM2:       FAILED ({hvm2_res['error'][:80]}...)")
            
        # HVM3
        hvm3_res = benchmark_hvm3(bench["core"])
        if hvm3_res["ok"]:
            print(f"    HVM3:       result={hvm3_res.get('result')} time={hvm3_res.get('time', 0):.4f}s")
        else:
            print(f"    HVM3:       FAILED ({hvm3_res['error'][:80]}...)")
            
        results.append({
            "name": name,
            "desc": bench["description"],
            "expected": expected,
            "ghc": ghc_res,
            "hvm2": hvm2_res,
            "hvm3": hvm3_res,
        })
    
    # Save Report
    report_path = BUILD_DIR / "package_report.md"
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w") as f:
        f.write("# Coronet Real Package Benchmark Report\n\n")
        f.write("| Package Workload | Target / Metric | GHC -O2 Native | HVM2 (Interaction Nets) | HVM3 (C Mode) |\n")
        f.write("|---|---|:---:|:---:|:---:|\n")
        for r in results:
            name = r["name"]
            exp = r["expected"]
            ghc_val = r["ghc"].get("result", "ERR")
            ghc_time = f"{r['ghc'].get('time', 0):.4f}s" if r["ghc"]["ok"] else "FAIL"
            
            h2_val = r["hvm2"].get("result", "ERR")
            h2_time = f"{r['hvm2'].get('time', 0):.4f}s" if r["hvm2"]["ok"] else "FAIL"
            h2_itrs = f"{r['hvm2'].get('itrs', 0):,}" if r["hvm2"].get("itrs") else "—"
            h2_mips = f"{r['hvm2'].get('mips', 0):.1f} MIPS" if r["hvm2"].get("mips") else "—"
            
            h3_val = r["hvm3"].get("result", "ERR")
            h3_time = f"{r['hvm3'].get('time', 0):.4f}s" if r["hvm3"]["ok"] else "FAIL"
            
            f.write(f"| `{name}` | **Result** | `{ghc_val}` | `{h2_val}` | `{h3_val}` |\n")
            f.write(f"| | **Execution Time** | {ghc_time} | {h2_time} | {h3_time} |\n")
            f.write(f"| | **ITRS (Rewrites)** | — | {h2_itrs} | — |\n")
            f.write(f"| | **Throughput** | — | {h2_mips} | — |\n")
    
    print(f"\nReport written to: {report_path}")


if __name__ == "__main__":
    main()
