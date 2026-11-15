#!/usr/bin/env python3
"""
Coronet Level 2 Benchmark Harness:
Compares GHC -O2 vs HVM3 (C mode) vs HVM2 (Multi-core CPU) vs HVM2 (Colab Tesla T4 GPU)
on realistic heavy workloads (Raytracer & Sha256).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple, List

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
BUILD_DIR = REPO_ROOT / "_build" / "heavy"
HEAVY_DIR = REPO_ROOT / "tests" / "fixtures" / "heavy"
RUN_HVM2 = REPO_ROOT / "scripts" / "run_hvm2.sh"
RUN_HVM3 = REPO_ROOT / "scripts" / "run_hvm3.sh"
RUN_COLAB_GPU = REPO_ROOT / "scripts" / "run_colab_gpu.sh"
CORONET_CLI = REPO_ROOT / "bin" / "coronet"


def run_cmd(cmd: List[str], timeout: int = 300) -> Tuple[int, str, str, float]:
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
        return -1, "", f"Timeout after {timeout}s", time.perf_counter() - start
    except Exception as e:
        return -1, "", str(e), time.perf_counter() - start


def parse_hvm2_stats(stdout: str) -> Dict[str, Any]:
    stats = {"result": None, "itrs": None, "time": None, "mips": None}
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("Result:"):
            stats["result"] = line[len("Result:") :].strip()
        elif line.startswith("- ITRS:"):
            try:
                stats["itrs"] = int(line[len("- ITRS:") :].strip())
            except ValueError:
                pass
        elif line.startswith("- TIME:"):
            stats["time"] = line[len("- TIME:") :].strip()
        elif line.startswith("- MIPS:"):
            stats["mips"] = line[len("- MIPS:") :].strip()
    return stats


def parse_hvm3_stats(stdout: str) -> Dict[str, Any]:
    stats = {"result": None, "time": None}
    lines = [l.strip() for l in stdout.splitlines() if l.strip()]
    if lines:
        for l in lines:
            if l.startswith("Result:"):
                stats["result"] = l[len("Result:") :].strip()
                break
        if not stats["result"]:
            stats["result"] = lines[-1]
    return stats


def benchmark_workload(
    name: str, hs_file: Path, core_file: Path, hvm2_file: Path, hvm3_file: Path, run_gpu: bool = True
) -> Dict[str, Any]:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    results: Dict[str, Any] = {"name": name, "metrics": {}}

    print(f"\n=======================================================")
    print(f" Benchmarking Workload: {name}")
    print(f"=======================================================")

    # 1. GHC -O2 baseline
    ghc_bin = BUILD_DIR / f"{name}_ghc"
    print(f"[1/4] Compiling GHC -O2 baseline...")
    c_code, c_out, c_err, _ = run_cmd(
        ["ghc", "-O2", str(hs_file), "-outputdir", str(BUILD_DIR / f"{name}_ghc_objs"), "-o", str(ghc_bin)]
    )
    if c_code == 0 and ghc_bin.exists():
        print(f"      Running GHC -O2 native binary...")
        code, out, err, el = run_cmd([str(ghc_bin)])
        results["metrics"]["ghc_o2"] = {
            "result": out.strip(),
            "time_s": el,
            "status": "OK" if code == 0 else "FAIL",
        }
        print(f"      GHC -O2 Output: {out.strip()} ({el:.4f}s)")
    else:
        print(f"      GHC -O2 compilation failed: {c_err}")
        results["metrics"]["ghc_o2"] = {"status": "FAIL", "error": c_err}

    # 2. HVM3 (Compiled C mode)
    if hvm3_file.exists():
        print(f"[2/4] Executing HVM3 (C mode)...")
        code, out, err, el = run_cmd([str(RUN_HVM3), "-c", str(hvm3_file)])
        stats = parse_hvm3_stats(out)
        results["metrics"]["hvm3_c"] = {
            "result": stats.get("result") or out.strip(),
            "time_s": el,
            "status": "OK" if code == 0 else "FAIL",
            "raw": out,
        }
        print(f"      HVM3 -c Output: {results['metrics']['hvm3_c']['result']} ({el:.4f}s)")
    else:
        print(f"      HVM3 file {hvm3_file} not found.")

    # 3. HVM2 (8 CPU cores)
    if hvm2_file.exists():
        print(f"[3/4] Executing HVM2 (Multi-core CPU)...")
        env_cmd = ["env", "RAYON_NUM_THREADS=8", str(RUN_HVM2), str(hvm2_file)]
        code, out, err, el = run_cmd(env_cmd)
        stats = parse_hvm2_stats(out)
        results["metrics"]["hvm2_cpu"] = {
            "result": stats.get("result") or out.strip(),
            "time_s": el,
            "itrs": stats.get("itrs"),
            "mips": stats.get("mips"),
            "status": "OK" if code == 0 else "FAIL",
        }
        print(
            f"      HVM2 CPU Output: {results['metrics']['hvm2_cpu']['result']} ({el:.4f}s, {stats.get('itrs')} ITRS, {stats.get('mips')} MIPS)"
        )
    else:
        print(f"      HVM2 file {hvm2_file} not found.")

    # 4. HVM2 (Colab GPU)
    if run_gpu and hvm2_file.exists() and RUN_COLAB_GPU.exists():
        print(f"[4/4] Executing HVM2 on Colab Tesla T4 GPU...")
        code, out, err, el = run_cmd([str(RUN_COLAB_GPU), str(hvm2_file)])
        stats = parse_hvm2_stats(out)
        results["metrics"]["hvm2_gpu"] = {
            "result": stats.get("result") or out.strip(),
            "total_time_s": el,
            "kernel_time": stats.get("time"),
            "itrs": stats.get("itrs"),
            "mips": stats.get("mips"),
            "status": "OK" if code == 0 else "FAIL",
            "raw": out,
        }
        print(
            f"      HVM2 GPU Output: {results['metrics']['hvm2_gpu']['result']} (Kernel: {stats.get('time')}, {stats.get('itrs')} ITRS)"
        )

    return results


def format_summary_table(all_results: List[Dict[str, Any]]) -> str:
    lines = []
    lines.append("# Coronet Level 2 Heavy Benchmark Comparison Matrix\n")
    headers = [
        "Workload",
        "GHC -O2 Out",
        "HVM3 Out",
        "HVM2 Out",
        "GPU Out",
        "GHC -O2 Time",
        "HVM3 (-c) Time",
        "HVM2 CPU Time",
        "GPU Kernel Time",
        "HVM2 ITRS",
    ]
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for r in all_results:
        m = r["metrics"]
        name = r["name"]
        ghc_res = m.get("ghc_o2", {})
        hvm3_res = m.get("hvm3_c", {})
        hvm2_res = m.get("hvm2_cpu", {})
        gpu_res = m.get("hvm2_gpu", {})

        row = [
            f"`{name}`",
            f"`{ghc_res.get('result', 'N/A')}`",
            f"`{hvm3_res.get('result', 'N/A')}`",
            f"`{hvm2_res.get('result', 'N/A')}`",
            f"`{gpu_res.get('result', 'N/A')}`",
            f"{ghc_res.get('time_s', 0):.4f}s" if ghc_res.get("time_s") else "N/A",
            f"{hvm3_res.get('time_s', 0):.4f}s" if hvm3_res.get("time_s") else "N/A",
            f"{hvm2_res.get('time_s', 0):.4f}s" if hvm2_res.get("time_s") else "N/A",
            f"{gpu_res.get('kernel_time', 'N/A')}",
            f"{hvm2_res.get('itrs', 'N/A'):,}" if isinstance(hvm2_res.get("itrs"), int) else "N/A",
        ]
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Coronet Heavy Workload Benchmarks")
    parser.add_argument("--skip-gpu", action="store_true", help="Skip remote GPU run")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    args = parser.parse_args()

    workloads = ["Raytracer", "Sha256"]
    all_results = []

    for w in workloads:
        hs = HEAVY_DIR / f"{w}.hs"
        core = HEAVY_DIR / f"{w}.core"
        hvm2 = HEAVY_DIR / f"{w}.hvm"
        hvm3 = HEAVY_DIR / f"{w}.hvm3"
        if hs.exists():
            res = benchmark_workload(w, hs, core, hvm2, hvm3, run_gpu=not args.skip_gpu)
            all_results.append(res)

    md = format_summary_table(all_results)
    report_file = BUILD_DIR / "heavy_report.md"
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    report_file.write_text(md)

    if args.json:
        print(json.dumps(all_results, indent=2))
    else:
        print("\n" + md)
        print(f"\nReport saved to: {report_file}")


if __name__ == "__main__":
    main()
