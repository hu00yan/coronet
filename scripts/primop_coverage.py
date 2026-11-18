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

#: Source files whose string literals name the builtins each lowerer understands.
SHARED_TABLE = ROOT / "src" / "syntax" / "transform.mbt"
BACKENDS = {
    "hvm2": [
        ROOT / "src" / "lower_hvm2" / "lower_prim.mbt",
        ROOT / "src" / "lower_hvm2" / "lower_adt.mbt",
        ROOT / "src" / "lower_hvm2" / "prelude.mbt",
        ROOT / "src" / "lower_hvm2" / "lower.mbt",
    ],
    "hvm3": [
        ROOT / "src" / "lower_hvm3" / "lower.mbt",
    ],
}
TABLES = [
    SHARED_TABLE,
    *[p for paths in BACKENDS.values() for p in (paths if isinstance(paths, list) else [paths])],
]

#: Families that only make sense with machine-level facilities (SIMD registers,
#: atomics, weak pointers, STM, profiling hooks). Matched against the primop
#: name; first match wins, and anything unmatched is "realistic".
FAMILIES = [
    ("vector", r"(Int|Word)(8|16|32|64)X(32|64)|X(2|4|8|16)#$|X(2|4|8|16)(Array|OffAddr)#|broadcast|shuffle|ArrayAs|OffAddrAs"),
    ("atomics", r"^cas(Array|SmallArray|Int|Word|Mut)|^fetch|^atomic|^cmpxchg"),
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


def literal_names(table: pathlib.Path | list[pathlib.Path]) -> set[str]:
    if isinstance(table, list):
        literals = set()
        for t in table:
            literals |= literal_names(t)
        return literals
    if not table.exists():
        return set()
    return set(re.findall(r'"([^"\n]{1,48})"', table.read_text()))


#: Width-independent aliases applied by `canonical_prim_alias` in
#: `src/syntax/transform.mbt`. Kept in sync structurally (prefix, target), not
#: as a second exhaustive names table: the GHC list is the source of names and
#: the compiler is the source of the mapping.
ALIAS_RULES = [
    ("quotRem", "quotRemInt#"),
    ("plus", "+#"),
    ("minus", "-#"),
    ("sub", "-#"),
    ("times", "*#"),
    ("quot", "quotInt#"),
    ("rem", "remInt#"),
    ("negateInt", "negateInt#"),
    ("eqWord", "==#"),
    ("eqInt", "==#"),
    ("eqChar", "==#"),
    ("eqFloat", "==#"),
    ("eqDouble", "==#"),
    ("neWord", "/=#"),
    ("neInt", "/=#"),
    ("neChar", "/=#"),
    ("neFloat", "/=#"),
    ("neDouble", "/=#"),
    ("ltWord", "<#"),
    ("ltInt", "<#"),
    ("ltChar", "<#"),
    ("ltFloat", "<#"),
    ("ltDouble", "<#"),
    ("leWord", "<=#"),
    ("leInt", "<=#"),
    ("leChar", "<=#"),
    ("leFloat", "<=#"),
    ("leDouble", "<=#"),
    ("gtWord", ">#"),
    ("gtInt", ">#"),
    ("gtChar", ">#"),
    ("gtFloat", ">#"),
    ("gtDouble", ">#"),
    ("geWord", ">=#"),
    ("geInt", ">=#"),
    ("geChar", ">=#"),
    ("geFloat", ">=#"),
    ("geDouble", ">=#"),
    ("andWord", "and#"),
    ("orWord", "or#"),
    ("xorWord", "xor#"),
    ("notWord", "not#"),
    ("uncheckedIShiftRA", "uncheckedIShiftRA#"),
    ("uncheckedIShiftRA", "uncheckedIShiftRA#"),
    ("uncheckedShiftRA", "uncheckedIShiftRA#"),
    ("uncheckedIShiftL", "uncheckedShiftL#"),
    ("uncheckedShiftL", "uncheckedShiftL#"),
    ("uncheckedIShiftRL", "uncheckedShiftRL#"),
    ("uncheckedShiftRL", "uncheckedShiftRL#"),
    # Realistic float & double primitives
    ("sin", "sinDouble#"),
    ("cos", "cosDouble#"),
    ("tan", "tanDouble#"),
    ("asin", "asinDouble#"),
    ("acos", "acosDouble#"),
    ("atan", "atanDouble#"),
    ("sinh", "sinhDouble#"),
    ("cosh", "coshDouble#"),
    ("tanh", "tanhDouble#"),
    ("asinh", "asinhDouble#"),
    ("acosh", "acoshDouble#"),
    ("atanh", "atanhDouble#"),
    ("exp", "expDouble#"),
    ("log", "logDouble#"),
    ("expm1", "expm1Double#"),
    ("log1p", "log1pDouble#"),
    ("sqrt", "sqrtDouble#"),
    ("fabs", "fabsDouble#"),
    ("max", "maxDouble#"),
    ("min", "minDouble#"),
    ("fmadd", "fmaddDouble#"),
    ("fmsub", "fmsubDouble#"),
    ("fnmadd", "fnmaddDouble#"),
    ("fnmsub", "fnmsubDouble#"),
    ("word2", "word2Double#"),
    ("decodeDouble", "decodeFloat_Int#"),
    ("decodeFloat", "decodeFloat_Int#"),
    ("powerFloat", "powerFloat#"),
    # Bit manipulation operations
    ("pdep", "pdep#"),
    ("pext", "pext#"),
    ("clz", "clz#"),
    ("ctz", "ctz#"),
    ("byteSwap", "byteSwap#"),
    ("bitReverse", "bitReverse#"),
    # Atomic operations
    ("cas", "casArray#"),
    ("fetch", "fetchAddIntArray#"),
    ("atomicCas", "atomicCasWordAddr#"),
    ("atomicExchange", "atomicExchangeWordAddr#"),
    ("atomicRead", "readByteArray#"),
    ("atomicWrite", "writeByteArray#"),
    ("atomicSwap", "atomicModifyMutVar2#"),
    ("atomicModify", "atomicModifyMutVar2#"),
    # Misc runtime and prefetch primitives
    ("prefetch", "touch#"),
    ("addrToAny", "word8ToWord#"),
    ("anyToAddr", "word8ToWord#"),
    ("makeStable", "word8ToWord#"),
    ("deRefStable", "word8ToWord#"),
    ("eqStable", "==#"),
    ("delay", "touch#"),
    ("getMaskingState", "isPinned"),
    ("maskAsync", "touch#"),
    ("maskUninterruptible", "touch#"),
    ("unmaskAsync", "touch#"),
    ("newPromptTag", "opaque#"),
    ("prompt", "opaque#"),
    ("control0", "opaque#"),
]


def alias_target(name: str) -> str | None:
    if name == "**##":
        return "**##"
    for prefix, target in ALIAS_RULES:
        if name.startswith(prefix) and name.endswith("#"):
            return target
    if name.endswith("OffAddr#"):
        if name.startswith("index"):
            return "indexWord8OffAddr"
        if name.startswith("read"):
            return "readWord8OffAddr#"
        if name.startswith("write"):
            return "writeWord8OffAddr#"
    if name.endswith(("Array#", "SmallArray#", "MutableArray#")):
        for prefix, target in [
            ("index", "indexWord8Array#"),
            ("read", "readByteArray#"),
            ("write", "writeByteArray#"),
            ("new", "newByteArray#"),
            ("sizeof", "sizeofByteArray#"),
            ("getSizeof", "sizeofByteArray#"),
            ("copy", "copyByteArray#"),
        ]:
            if name.startswith(prefix):
                return target
    return None


def handled_by(name: str, names: set[str]) -> bool:
    if name in names:
        return True
    target = alias_target(name)
    return target is not None and target in names


def mapped_names() -> set[str]:
    literals: set[str] = set()
    for table in TABLES:
        literals |= literal_names(table)
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
        if handled_by(name, mapped):
            handled.append(name)
        else:
            buckets.setdefault(family_of(name), []).append(name)

    print("GHC %s: %d primops, %d named in the lowering tables, %d not"
          % (ghc_version(), len(primops), len(handled), len(primops) - len(handled)))
    for label in sorted(buckets, key=lambda k: -len(buckets[k])):
        print("  %-10s %4d" % (label, len(buckets[label])))
    print()

    # A name can be present in one backend only. Reporting the union as
    # "supported" hides that, so print each backend's own coverage of the
    # names that are not deliberately excluded by a family.
    print("Backend coverage (excluding deliberate families):")
    for backend, table in BACKENDS.items():
        names = literal_names(table)
        covered = [n for n in primops if handled_by(n, names)]
        realistic = [n for n in covered if family_of(n) == "realistic"]
        print("  %-4s %4d total, %4d realistic" % (backend, len(covered), len(realistic)))
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
