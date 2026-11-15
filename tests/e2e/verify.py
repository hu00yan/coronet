#!/usr/bin/env python3
"""
Coronet End-to-End Verification and Benchmarking Harness
Verifies the full pipeline:
Haskell (.hs) -> GHC Core (.core) -> Coronet CLI -> HVM2 / HVM3 execution
Compares semantic equivalence and benchmarks execution times.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

# Root paths
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures"
DEFAULT_BUILD_DIR = REPO_ROOT / "_build" / "e2e"
HVM2_BIN = REPO_ROOT / "vendor" / "HVM2" / "target" / "release" / "hvm"
RUN_HVM2_SCRIPT = REPO_ROOT / "scripts" / "run_hvm2.sh"
RUN_HVM3_SCRIPT = REPO_ROOT / "scripts" / "run_hvm3.sh"
EXTRACT_CORE_SCRIPT = REPO_ROOT / "frontend" / "extract_core.sh"


def run_command(
    cmd: List[str], cwd: Optional[Path] = None, timeout: int = 30
) -> Tuple[int, str, str, float]:
    """Runs a command and returns (exit_code, stdout, stderr, elapsed_seconds)."""
    start = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd or REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        elapsed = time.perf_counter() - start
        return proc.returncode, proc.stdout, proc.stderr, elapsed
    except subprocess.TimeoutExpired:
        elapsed = time.perf_counter() - start
        return -1, "", f"Timed out after {timeout}s", elapsed
    except Exception as e:
        elapsed = time.perf_counter() - start
        return -1, "", str(e), elapsed


def parse_hvm2_output(stdout: str) -> Dict[str, Any]:
    """Parses output from HVM2 runtime.

    Expected typical output:
    Result: 55
    - ITRS: 123
    - TIME: 0.00s
    - MIPS: 1.23
    """
    res: Dict[str, Any] = {"raw": stdout, "value": None, "itrs": None, "time": None}
    lines = stdout.strip().splitlines()
    for line in lines:
        line_s = line.strip()
        if line_s.startswith("Result:"):
            res["value"] = line_s[len("Result:") :].strip()
        elif line_s.startswith("- ITRS:"):
            try:
                res["itrs"] = int(line_s[len("- ITRS:") :].strip())
            except ValueError:
                pass
        elif line_s.startswith("- TIME:"):
            res["time"] = line_s[len("- TIME:") :].strip()
    if res["value"] is None and lines:
        res["value"] = lines[0].strip()
    return res


def parse_hvm3_output(stdout: str) -> Dict[str, Any]:
    """Parses output from HVM3 runtime."""
    res: Dict[str, Any] = {"raw": stdout, "value": None}
    lines = [l.strip() for l in stdout.strip().splitlines() if l.strip()]
    if not lines:
        return res
    # Look for Result: or use the last non-empty line or first line
    for line in lines:
        if line.startswith("Result:"):
            res["value"] = line[len("Result:") :].strip()
            return res
    res["value"] = lines[-1]
    return res


def normalize_value(val: Optional[str]) -> str:
    """Normalizes string representation of value for semantic comparison."""
    if val is None:
        return ""
    v = val.strip()
    # Strip enclosing parentheses if simple: e.g. (42) -> 42
    if v.startswith("(") and v.endswith(")"):
        inner = v[1:-1].strip()
        if "(" not in inner and ")" not in inner:
            v = inner
    return v


def are_semantically_equivalent(expected_ghc: str, actual_target: str) -> bool:
    """Checks semantic equivalence between Haskell stdout and HVM output."""
    exp = normalize_value(expected_ghc)
    act = normalize_value(actual_target)

    if not exp and not act:
        return True
    if exp == act:
        return True

    # Check numeric equivalence
    try:
        if int(exp) == int(act):
            return True
    except ValueError:
        pass

    # Check boolean equivalence
    # Scott-encoded booleans: True = \t \f t or \a \b a; False = \t \f f or \a \b b
    if exp in ("True", "true"):
        if act in ("True", "true", "1"):
            return True
        if "λt λf t" in act or "λa λb a" in act or "λt. λf. t" in act:
            return True
    if exp in ("False", "false"):
        if act in ("False", "false", "0"):
            return True
        if "λt λf f" in act or "λa λb b" in act or "λt. λf. f" in act:
            return True

    # Check list or ADT representations: e.g. [1,2,3] vs (Cons 1 (Cons 2 Nil))
    # Or string representations
    if exp.replace(" ", "") == act.replace(" ", ""):
        return True

    return False


class FixtureTest:
    def __init__(self, name: str, hs_path: Optional[Path], core_path: Optional[Path]):
        self.name = name
        self.hs_path = hs_path
        self.core_path = core_path


def discover_fixtures(fixtures_dir: Path) -> List[FixtureTest]:
    """Discovers test fixtures from fixtures_dir."""
    hs_dir = fixtures_dir / "hs"
    core_dir = fixtures_dir / "core"

    tests: Dict[str, Dict[str, Optional[Path]]] = {}

    if hs_dir.exists():
        for p in sorted(hs_dir.glob("*.hs")):
            name = p.stem
            tests.setdefault(name, {"hs": None, "core": None})["hs"] = p

    if core_dir.exists():
        for p in sorted(core_dir.glob("*.core")):
            name = p.stem
            tests.setdefault(name, {"hs": None, "core": None})["core"] = p

    # Also check flat directory
    for p in sorted(fixtures_dir.glob("*.hs")):
        name = p.stem
        tests.setdefault(name, {"hs": None, "core": None})["hs"] = p
    for p in sorted(fixtures_dir.glob("*.core")):
        name = p.stem
        tests.setdefault(name, {"hs": None, "core": None})["core"] = p

    # Canonical order: 01_arith, 02_fib, 03_adt, 04_higher_order, 05_tree
    result = []
    for name in sorted(tests.keys()):
        result.append(FixtureTest(name, tests[name]["hs"], tests[name]["core"]))
    return result


def resolve_hvm2_runner() -> Optional[List[str]]:
    if RUN_HVM2_SCRIPT.exists() and os.access(RUN_HVM2_SCRIPT, os.X_OK):
        return [str(RUN_HVM2_SCRIPT)]
    if HVM2_BIN.exists() and os.access(HVM2_BIN, os.X_OK):
        return [str(HVM2_BIN), "run"]
    return None


def resolve_hvm3_runner() -> Optional[List[str]]:
    if RUN_HVM3_SCRIPT.exists() and os.access(RUN_HVM3_SCRIPT, os.X_OK):
        return [str(RUN_HVM3_SCRIPT)]
    # Check if cabal / hvm3 binary exists in dist-newstyle
    hvm3_dist = REPO_ROOT / "vendor" / "HVM3" / "dist-newstyle"
    if hvm3_dist.exists():
        bins = list(hvm3_dist.glob("**/build/**/hvm"))
        for b in bins:
            if b.is_file() and os.access(b, os.X_OK):
                return [str(b), "run"]
    return None


def run_e2e_verification(
    fixtures_dir: Path,
    build_dir: Path,
    targets: List[str],
    filter_pattern: Optional[str] = None,
    timeout: int = 30,
    verbose: bool = False,
) -> Tuple[bool, List[Dict[str, Any]]]:
    build_dir.mkdir(parents=True, exist_ok=True)
    fixtures = discover_fixtures(fixtures_dir)

    if filter_pattern:
        fixtures = [f for f in fixtures if filter_pattern in f.name]

    if not fixtures:
        print(f"Warning: No test fixtures found in {fixtures_dir}")
        return True, []

    hvm2_runner = resolve_hvm2_runner() if "hvm2" in targets else None
    hvm3_runner = resolve_hvm3_runner() if "hvm3" in targets else None

    results = []
    all_passed = True

    for fix in fixtures:
        test_info: Dict[str, Any] = {
            "name": fix.name,
            "ghc_out": None,
            "ghc_time_s": None,
            "ghc_ok": False,
            "targets": {},
            "status": "PASS",
            "errors": [],
        }

        print(f"--> Running test fixture: {fix.name}")

        # 1. Haskell reference run
        if fix.hs_path and fix.hs_path.exists():
            code, out, err, el = run_command(["runghc", str(fix.hs_path)], timeout=timeout)
            if code == 0:
                test_info["ghc_out"] = out.strip()
                test_info["ghc_time_s"] = el
                test_info["ghc_ok"] = True
                if verbose:
                    print(f"    GHC out ({el:.3f}s): {test_info['ghc_out']}")
            else:
                test_info["errors"].append(f"GHC failed: {err.strip()}")
                if verbose:
                    print(f"    GHC failed ({el:.3f}s): {err.strip()}")
        else:
            test_info["errors"].append("No .hs source available")

        # 2. Ensure .core exists
        core_file = fix.core_path
        if (not core_file or not core_file.exists()) and fix.hs_path and EXTRACT_CORE_SCRIPT.exists():
            target_core = fixtures_dir / "core" / f"{fix.name}.core"
            target_core.parent.mkdir(parents=True, exist_ok=True)
            code, out, err, el = run_command(
                [str(EXTRACT_CORE_SCRIPT), str(fix.hs_path), str(target_core)],
                timeout=timeout,
            )
            if code == 0 and target_core.exists():
                core_file = target_core
            else:
                test_info["errors"].append(f"extract_core failed: {err.strip()}")

        # 3. For each target
        for tgt in targets:
            tgt_res: Dict[str, Any] = {
                "compiled": False,
                "compile_time_s": None,
                "executed": False,
                "run_time_s": None,
                "out": None,
                "equiv": False,
                "error": None,
            }

            if not core_file or not core_file.exists():
                tgt_res["error"] = "Missing .core file"
                test_info["status"] = "FAIL"
                all_passed = False
                test_info["targets"][tgt] = tgt_res
                continue

            # Compile with Coronet CLI
            out_file = build_dir / f"{fix.name}.{tgt}"
            comp_cmd = [
                "moon",
                "run",
                "cmd/main",
                "--",
                str(core_file),
                "--target",
                tgt,
                "-o",
                str(out_file),
            ]
            code, out, err, el = run_command(comp_cmd, timeout=timeout)
            tgt_res["compile_time_s"] = el

            # If CLI wrote to stdout or -o file
            if code == 0:
                if not out_file.exists() or out_file.stat().st_size == 0:
                    # Check if output was written to stdout
                    if out.strip():
                        out_file.write_text(out)
                if out_file.exists() and out_file.stat().st_size > 0:
                    tgt_res["compiled"] = True
                else:
                    tgt_res["error"] = f"Compilation produced empty output: {err}"
            else:
                tgt_res["error"] = f"Compiler failed (exit {code}): {err.strip() or out.strip()}"

            # Execute runtime
            if tgt_res["compiled"]:
                runner = hvm2_runner if tgt == "hvm2" else hvm3_runner
                if not runner:
                    tgt_res["error"] = f"No runner available for {tgt}"
                else:
                    run_cmd = runner + [str(out_file)]
                    rcode, rout, rerr, rel = run_command(run_cmd, timeout=timeout)
                    tgt_res["run_time_s"] = rel
                    if rcode == 0:
                        tgt_res["executed"] = True
                        if tgt == "hvm2":
                            parsed = parse_hvm2_output(rout)
                            tgt_res["out"] = parsed.get("value") or rout.strip()
                        else:
                            parsed = parse_hvm3_output(rout)
                            tgt_res["out"] = parsed.get("value") or rout.strip()

                        # Equivalence check
                        if test_info["ghc_out"] is not None:
                            equiv = are_semantically_equivalent(
                                test_info["ghc_out"], tgt_res["out"]
                            )
                            tgt_res["equiv"] = equiv
                            if not equiv:
                                test_info["status"] = "FAIL"
                                all_passed = False
                                tgt_res["error"] = (
                                    f"Semantic mismatch: GHC='{test_info['ghc_out']}' vs {tgt.upper()}='{tgt_res['out']}'"
                                )
                        else:
                            tgt_res["equiv"] = True
                    else:
                        tgt_res["error"] = f"Execution failed (exit {rcode}): {rerr.strip() or rout.strip()}"
                        test_info["status"] = "FAIL"
                        all_passed = False
            else:
                test_info["status"] = "FAIL"
                all_passed = False

            test_info["targets"][tgt] = tgt_res

        results.append(test_info)

    return all_passed, results


def format_markdown_matrix(results: List[Dict[str, Any]], targets: List[str]) -> str:
    lines = []
    lines.append("# Coronet End-to-End Verification Matrix\n")

    # Header
    cols = ["Fixture", "Status", "GHC (runghc)"]
    for t in targets:
        cols.extend([f"{t.upper()} Out", f"{t.upper()} Equiv", f"{t.upper()} Time"])
    cols.append("GHC Time")
    lines.append("| " + " | ".join(cols) + " |")
    lines.append("| " + " | ".join(["---"] * len(cols)) + " |")

    for r in results:
        row = [
            f"`{r['name']}`",
            "✅ PASS" if r["status"] == "PASS" else "❌ FAIL",
            f"`{r['ghc_out']}`" if r["ghc_out"] is not None else "N/A",
        ]
        for t in targets:
            tgt = r["targets"].get(t, {})
            out_val = tgt.get("out")
            out_str = f"`{out_val}`" if out_val is not None else (tgt.get("error") or "FAIL")
            # Truncate if too long
            if len(out_str) > 30:
                out_str = out_str[:27] + "..."
            equiv_str = "✅ YES" if tgt.get("equiv") else ("❌ NO" if tgt.get("executed") else "N/A")
            time_str = f"{tgt.get('run_time_s', 0):.4f}s" if tgt.get("run_time_s") is not None else "N/A"
            row.extend([out_str, equiv_str, time_str])

        ghc_time = f"{r['ghc_time_s']:.4f}s" if r["ghc_time_s"] is not None else "N/A"
        row.append(ghc_time)
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Coronet E2E Test & Benchmark Harness")
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=DEFAULT_FIXTURES_DIR,
        help="Path to test fixtures directory",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_BUILD_DIR,
        help="Path to output build directory",
    )
    parser.add_argument(
        "--target",
        choices=["hvm2", "hvm3", "all"],
        default="all",
        help="Target backend to test",
    )
    parser.add_argument(
        "--filter",
        type=str,
        default=None,
        help="Filter fixtures matching substring",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Execution timeout per step in seconds",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Verbose log output",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output raw JSON results",
    )

    args = parser.parse_args()
    targets = ["hvm2", "hvm3"] if args.target == "all" else [args.target]

    success, results = run_e2e_verification(
        fixtures_dir=args.fixtures,
        build_dir=args.build_dir,
        targets=targets,
        filter_pattern=args.filter,
        timeout=args.timeout,
        verbose=args.verbose,
    )

    md_report = format_markdown_matrix(results, targets)
    report_file = args.build_dir / "report.md"
    args.build_dir.mkdir(parents=True, exist_ok=True)
    report_file.write_text(md_report)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print("\n" + md_report + "\n")
        print(f"Detailed report saved to: {report_file}")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
