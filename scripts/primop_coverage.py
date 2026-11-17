#!/usr/bin/env python3
"""Report which GHC primops Coronet's lowering tables know about.

GHC ships the authoritative list (`GHC.Builtin.PrimOps.allThePrimOps`), so the
question "which primitive does the compiler not support yet" has a mechanical
answer instead of waiting for a real project to trip over one:

    scripts/primop_coverage.py            # summary and every unhandled name
    scripts/primop_coverage.py --strict   # exit 1 if a primop is unclassified

A primop counts as handled when its name appears in one of the lowering tables
(they are the single source of truth for what becomes a net definition). The
remaining ones are bucketed into families that a pure interaction-net runtime
does not offer at all, so the interesting output is the `realistic` bucket.
"""

import argparse
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "_build" / "primops.txt"

#: Source files whose string literals name the builtins the lowerers understand.
TABLES = [
    ROOT / "src" / "syntax" / "transform.mbt",
    ROOT / "src" / "lower_hvm2" / "lower.mbt",
    ROOT / "src" / "lower_hvm3" / "lower.mbt",
]

#: Families that only make sense with machine-level facilities (SIMD registers,
#: atomics, weak pointers, STM, profiling hooks). Matched against the primop
#: name; first match wins, and anything unmatched is "realistic".
FAMILIES = [
    ("vector", r"X(2|4|8|16)#$|X(2|4|8|16)(Array|OffAddr)#|broadcast|shuffle|ArrayAs|OffAddrAs"),
    ("atomics", r"^(cas|fetch|atomic|atomicCas|atomicExchange|atomicRead|atomicWrite)|^cmpxchg"),
    ("weak", r"Weak#|mkWeak|deRefWeak|finalizeWeak|addCFinalizer|weaklyPinned"),
    ("stm", r"TVar|STM|^retry$|^atomically$|catchRetry"),
    ("compact", r"^compact"),
    ("profiling", r"CCS|^trace|annotateStack|closureSize|unpackClosure|whereFrom|getApStackVal"),
    ("threads", r"Thread|^fork|^yield|^par#|^spark|MVar|^noDuplicate$|^performGC|^setOther|^listThreads"),
    ("misc", r"^prefetch|^delay|^prompt|^newPromptTag|^control0|^mask|^unmask|^getMaskingState|StablePtr|StableName|^anyToAddr|^addrToAny|^byteArrayContents|^bitReverse|^byteSwap|^clz|^ctz|^pdep|^pext|^bswap"),
]

HASKELL = """\
import GHC.Builtin.PrimOps (allThePrimOps, primOpOcc)
import GHC.Types.Name.Occurrence (occNameString)

main :: IO ()
main = mapM_ (putStrLn . occNameString . primOpOcc) allThePrimOps
"""


def ghc_primops() -> list[str]:
    """Every primop name GHC's own library knows, compiled once and cached."""
    if CACHE.exists():
        return [l.strip() for l in CACHE.read_text().splitlines() if l.strip()]
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "primops.hs"
        exe = pathlib.Path(tmp) / "primops"
        src.write_text(HASKELL)
        built = subprocess.run(
            ["ghc", "-package", "ghc", "-O0", str(src), "-o", str(exe)],
            capture_output=True,
            text=True,
        )
        if built.returncode != 0:
            sys.exit("error: could not build the primop enumerator:\n%s" % built.stderr[-2000:])
        names = subprocess.run([str(exe)], capture_output=True, text=True, check=True).stdout
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(names)
    return [l.strip() for l in names.splitlines() if l.strip()]


def mapped_names() -> set[str]:
    literals: set[str] = set()
    for table in TABLES:
        if not table.exists():
            continue
        for match in re.finditer(r'"([^"\n]{1,48})"', table.read_text()):
            literals.add(match.group(1))
    return literals


def family_of(name: str) -> str:
    for label, pattern in FAMILIES:
        if re.search(pattern, name):
            return label
    return "realistic"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="fail on unhandled realistic primops")
    parser.add_argument("--family", help="only list this bucket")
    args = parser.parse_args()

    primops = ghc_primops()
    mapped = mapped_names()
    buckets: dict[str, list[str]] = {}
    handled = []
    for name in primops:
        if name in mapped:
            handled.append(name)
        else:
            buckets.setdefault(family_of(name), []).append(name)

    print("GHC %s: %d primops, %d named in the lowering tables, %d not"
          % (ghc_version(), len(primops), len(handled), len(primops) - len(handled)))
    for label in sorted(buckets, key=lambda k: -len(buckets[k])):
        print("  %-10s %4d" % (label, len(buckets[label])))
    print()
    for label in sorted(buckets):
        if args.family and label != args.family:
            continue
        print("## %s (%d)" % (label, len(buckets[label])))
        print("  " + " ".join(sorted(buckets[label])))
        print()

    realistic = buckets.get("realistic", [])
    if args.strict and realistic:
        print("error: %d primop(s) a real project can reach are not handled" % len(realistic))
        return 1
    return 0


def ghc_version() -> str:
    out = subprocess.run(["ghc", "--numeric-version"], capture_output=True, text=True)
    return out.stdout.strip() or "?"


if __name__ == "__main__":
    sys.exit(main())
