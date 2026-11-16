#!/usr/bin/env python3
"""
Coronet real-world harness.

Takes a real Haskell program that depends on a real Hackage/cabal package,
compiles every module it needs from source with GHC's Core plugin, links the
result with Coronet, runs it on HVM2 and HVM3, and compares the value with what
GHC itself prints.

    tests/e2e/real_world/run.py                # every case
    tests/e2e/real_world/run.py containers_map # cases matching a substring
    tests/e2e/real_world/run.py --target hvm3 --verbose

A case is a directory under cases/ with

    case.hs        the program. It must define `result :: Int` and `main = print result`
    case.json      {"deps": ["containers-0.8"], "timeout": 300}

`deps` are cabal package ids fetched with `cabal get`; every module GHC needs
from them is compiled from source with -O2 and the Coronet plugin, so the
CoreLite the linker sees is the whole program, not a snapshot of one file.

Nothing in a case's Haskell source is modified. The package source is not
modified either: it is unpacked into _build/real_world/deps/ and built in place
with .o/.hi files landing next to the sources, exactly like a manual ghc build.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
CASES_DIR = SCRIPT_DIR / "cases"
WORK_DIR = REPO_ROOT / "_build" / "real_world"
DEPS_DIR = WORK_DIR / "deps"
RUN_HVM2 = REPO_ROOT / "scripts" / "run_hvm2.sh"
RUN_HVM3 = REPO_ROOT / "scripts" / "run_hvm3.sh"


def log(msg, verbose_only=False, verbose=True):
    if verbose_only and not verbose:
        return
    print(msg, flush=True)


def run(cmd, cwd=None, timeout=600, env=None):
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=env,
        )
        return proc.returncode, proc.stdout, proc.stderr, time.perf_counter() - started
    except subprocess.TimeoutExpired:
        return -1, "", "timed out after %ss" % timeout, time.perf_counter() - started


def which(name):
    found = shutil.which(name)
    if not found:
        sys.exit("error: %s is not on PATH" % name)
    return found


# ---------------------------------------------------------------------------
# dependency provisioning
# ---------------------------------------------------------------------------


def ensure_dep(pkg_id, verbose):
    """Unpack a Hackage package once. Returns its root directory."""
    target = DEPS_DIR / pkg_id
    if target.exists():
        return target
    DEPS_DIR.mkdir(parents=True, exist_ok=True)
    code, out, err, _ = run(["cabal", "get", "--destdir", str(DEPS_DIR), pkg_id], timeout=600)
    if code != 0:
        sys.exit("error: cabal get %s failed:\n%s\n%s" % (pkg_id, out, err))
    # `cabal get --destdir X pkg` unpacks to X/pkg (name only, no version)
    guess = DEPS_DIR / pkg_id.split("-")[0]
    if guess.exists() and not target.exists():
        guess.rename(target)
    if not target.exists():
        sys.exit("error: could not locate unpacked %s in %s" % (pkg_id, DEPS_DIR))
    log("  fetched %s" % pkg_id, verbose_only=True, verbose=verbose)
    return target


def dep_src_dirs(dep_root):
    dirs = []
    for candidate in ("src", "src/lib", "."):
        path = dep_root / candidate
        if path.is_dir():
            dirs.append(path)
    return dirs


def dep_include_dirs(dep_root):
    return [p for p in (dep_root / "include",) if p.is_dir()]


def dep_hides(dep_root):
    """Packages whose modules we compile from source must be hidden, otherwise
    GHC prefers the installed interface and the plugin never sees them."""
    hides = []
    for include in dep_root.glob("*.cabal"):
        text = include.read_text(errors="ignore")
        if "name:" in text:
            name = text.split("name:", 1)[1].split("\n", 1)[0].strip()
            if name:
                hides.append(name)
    return hides


# ---------------------------------------------------------------------------
# case pipeline
# ---------------------------------------------------------------------------


class Case:
    def __init__(self, directory):
        self.dir = directory
        self.name = directory.name
        self.hs = directory / "case.hs"
        meta_path = directory / "case.json"
        self.meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        self.timeout = self.meta.get("timeout", 600)


def extract_core(case, deps, work, verbose):
    """Compile every module the case needs with the Core plugin, -O2."""
    core_dir = work / "core"
    build_dir = work / "build"
    if core_dir.exists():
        shutil.rmtree(core_dir)
    core_dir.mkdir(parents=True)
    build_dir.mkdir(parents=True, exist_ok=True)

    src_args, include_args, hide_args = [], [], []
    for dep in deps:
        for src in dep_src_dirs(dep):
            src_args.append("-i" + str(src))
        for inc in dep_include_dirs(dep):
            include_args.append("-I" + str(inc))
        for hide in dep_hides(dep):
            hide_args.append("-hide-package")
            hide_args.append(hide)

    # -M runs in --make mode, and --make cannot use a plugin whose source sits
    # on the -i path ("which is not loaded"). The module graph does not need the
    # plugin, so only the one-shot compile below carries it.
    src_only = [which("ghc"), "-O2"] + src_args + include_args + hide_args

    common = [
        which("ghc"),
        "-O2",
        # Coronet needs monomorphic Core: every class method left as a
        # dictionary-passing call becomes a reference to a module of `base`
        # that the project never compiles. Specialising aggressively is what
        # turns `$fOrdInt`/`$fFoldableList` references into code.
        "-fspecialise-aggressively",
        "-fexpose-all-unfoldings",
        "-funfolding-use-threshold=1000",
        "-package",
        "ghc",
        "-fplugin=CoronetPlugin",
        "-fplugin-opt=CoronetPlugin:dir=%s" % core_dir,
        "-i" + str(REPO_ROOT / "frontend"),
    ] + src_args + include_args + hide_args

    # 1. dependency graph without compiling
    dep_file = build_dir / "deps.mk"
    code, out, err, _ = run(
        src_only + ["-M", "-dep-makefile", str(dep_file), str(case.hs)],
        cwd=work,
        timeout=case.timeout,
    )
    if code != 0:
        return None, "ghc -M failed:\n" + (err or out)

    # 2. build in dependency order. GHC -M emits `foo.o : bar.hi` edges; the two
    # pattern rules below turn those into one-shot compiles, which is the only
    # ghc invocation shape the plugin survives next to -outputdir.
    makefile = build_dir / "Makefile"
    makefile.write_text(
        dep_file.read_text()
        + "\n%.o: %.hs\n\tghc -c "
        + " ".join(common[2:])
        + " $<\n\n%.hi: %.o\n\t@true\n"
    )
    obj = str(Path(str(case.hs)).with_suffix("")) + ".o"
    # -B: the dependency sources are a shared cache, so their .o/.hi files make
    # a plain make believe there is nothing to do and no Core would be emitted.
    code, out, err, elapsed = run(
        ["make", "-B", "-f", str(makefile), "-j1", obj], cwd=work, timeout=case.timeout
    )
    if code != 0:
        return None, "compiling modules failed:\n" + (err or out)

    cores = sorted(core_dir.glob("*.core"))
    cores = [c for c in cores if c.stat().st_size > 0]
    if not cores:
        return None, "no CoreLite was emitted (plugin did not run?)"
    return cores, None


def ghc_reference(case, deps, work, verbose):
    """Build and run the case with plain GHC: the number to match."""
    src_args, include_args, hide_args = [], [], []
    for dep in deps:
        for src in dep_src_dirs(dep):
            src_args.append("-i" + str(src))
        for inc in dep_include_dirs(dep):
            include_args.append("-I" + str(inc))
        for hide in dep_hides(dep):
            hide_args.extend(["-hide-package", hide])
    out_bin = work / "ghc_native"
    code, out, err, _ = run(
        [which("ghc"), "-O2", "-o", str(out_bin), "-outputdir", str(work / "native_obj")]
        + src_args
        + include_args
        + hide_args
        + [str(case.hs)],
        cwd=work,
        timeout=case.timeout,
    )
    if code != 0:
        return None, "ghc native build failed:\n" + (err or out)
    code, out, err, elapsed = run([str(out_bin)], timeout=case.timeout)
    if code != 0:
        return None, "ghc native run failed:\n" + (err or out)
    return out.strip(), None


def coronet_compile(cores, target, out_file, timeout):
    cmd = [
        which("moon"),
        "run",
        "cmd/main",
        "--",
    ] + [str(c) for c in cores] + ["--target", target, "-o", str(out_file)]
    code, out, err, elapsed = run(cmd, timeout=timeout)
    if code != 0:
        return None, (err or out).strip(), elapsed
    if not out_file.exists() or out_file.stat().st_size == 0:
        return None, "compiler produced no output", elapsed
    return out_file, None, elapsed


def run_target(target, hvm_file, timeout):
    runner = RUN_HVM2 if target == "hvm2" else RUN_HVM3
    code, out, err, elapsed = run([str(runner), str(hvm_file)], timeout=timeout)
    if code != 0:
        return None, (err or out).strip(), elapsed
    value = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Result:"):
            value = line[len("Result:") :].strip()
            break
    if value is None:
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        value = lines[-1] if lines else ""
    return value, None, elapsed


def run_case(case, targets, verbose, refresh):
    work = WORK_DIR / case.name
    if refresh and work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    result = {
        "case": case.name,
        "deps": case.meta.get("deps", []),
        "n_core_files": 0,
        "core_bytes": 0,
        "ghc": None,
        "targets": {},
        "note": case.meta.get("note", ""),
    }
    if not case.hs.exists():
        result["error"] = "missing case.hs"
        return result

    deps = [ensure_dep(d, verbose) for d in case.meta.get("deps", [])]

    reference, err = ghc_reference(case, deps, work, verbose)
    if reference is None:
        result["error"] = err
        return result
    result["ghc"] = reference
    log("  GHC: %s" % reference, verbose_only=True, verbose=verbose)

    cores, err = extract_core(case, deps, work, verbose)
    if cores is None:
        result["error"] = err
        return result
    result["n_core_files"] = len(cores)
    result["core_bytes"] = sum(c.stat().st_size for c in cores)
    log(
        "  Core: %d modules, %d bytes" % (len(cores), result["core_bytes"]),
        verbose_only=True,
        verbose=verbose,
    )

    for target in targets:
        entry = {}
        hvm_file = work / ("out." + target)
        _, err, compile_time = coronet_compile(cores, target, hvm_file, case.timeout)
        entry["compile_s"] = round(compile_time, 3)
        if err is not None:
            entry["status"] = "COMPILE-FAIL"
            entry["detail"] = err[-4000:]
            result["targets"][target] = entry
            continue
        entry["bytes"] = hvm_file.stat().st_size
        value, err, run_time = run_target(target, hvm_file, case.timeout)
        entry["run_s"] = round(run_time, 3)
        if err is not None:
            entry["status"] = "RUN-FAIL"
            entry["detail"] = err[-4000:]
            result["targets"][target] = entry
            continue
        entry["value"] = value
        entry["status"] = "PASS" if value == reference else "MISMATCH"
        result["targets"][target] = entry
        log(
            "  %s: %s (%s)" % (target, entry["status"], value),
            verbose_only=True,
            verbose=verbose,
        )
    return result


def write_report(results, targets, path):
    lines = ["# Coronet real-world run", ""]
    lines.append("| case | GHC -O2 | " + " | ".join(t.upper() for t in targets) + " | core |")
    lines.append("| --- | --- | " + " | ".join("---" for _ in targets) + " | --- |")
    for r in results:
        cells = []
        for t in targets:
            entry = r["targets"].get(t)
            if entry is None:
                cells.append("-")
            elif entry["status"] == "PASS":
                cells.append("✅ `%s`" % entry.get("value"))
            elif entry["status"] == "MISMATCH":
                cells.append("❌ `%s`" % entry.get("value"))
            else:
                cells.append("❌ %s" % entry["status"])
        core = "%d files / %.0f KB" % (r["n_core_files"], r["core_bytes"] / 1024) if r["n_core_files"] else "-"
        ghc = "`%s`" % r["ghc"] if r["ghc"] is not None else "❌"
        lines.append("| %s | %s | %s | %s |" % (r["case"], ghc, " | ".join(cells), core))
    lines.append("")
    for r in results:
        if r.get("error"):
            lines.append("## %s — error" % r["case"])
            lines.append("")
            lines.append("```")
            lines.append(r["error"][-3000:])
            lines.append("```")
            lines.append("")
        for t in targets:
            entry = r["targets"].get(t, {})
            if entry.get("detail"):
                lines.append("## %s — %s %s" % (r["case"], t, entry["status"]))
                lines.append("")
                lines.append("```")
                lines.append(entry["detail"][-3000:])
                lines.append("```")
                lines.append("")
    path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("filter", nargs="?", default=None, help="case name substring")
    parser.add_argument("--target", action="append", choices=["hvm2", "hvm3"], default=None)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--refresh", action="store_true", help="discard cached build output")
    args = parser.parse_args()

    if not CASES_DIR.is_dir():
        sys.exit("no cases directory: %s" % CASES_DIR)
    cases = [Case(d) for d in sorted(CASES_DIR.iterdir()) if d.is_dir() and (d / "case.hs").exists()]
    if args.filter:
        cases = [c for c in cases if args.filter in c.name]
    if not cases:
        sys.exit("no cases matched")
    targets = args.target or ["hvm2", "hvm3"]
    WORK_DIR.mkdir(parents=True, exist_ok=True)

    results = []
    for case in cases:
        print("--> %s" % case.name, flush=True)
        results.append(run_case(case, targets, args.verbose, args.refresh))

    report = WORK_DIR / "report.md"
    write_report(results, targets, report)
    (WORK_DIR / "results.json").write_text(json.dumps(results, indent=2))
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print()
        print(report.read_text())
    failed = [
        r
        for r in results
        if r.get("error")
        or any(r["targets"].get(t, {}).get("status") != "PASS" for t in targets)
    ]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
