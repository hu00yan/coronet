# Coronet End-to-End Verification Harness

This directory contains the independent end-to-end verification pipeline and benchmark suite for the **Coronet** compiler.

## Overview

The harness validates the full compilation and execution pipeline:
```
Haskell (.hs) ──> GHC Core (.core) ──> Coronet CLI ──> HVM2 / HVM3 ──> Evaluated Output
```

It verifies:
1. **Compilation pipeline**: GHC 9.14 Core dump -> extraction/cleaning (`frontend/extract_core.sh`) -> Coronet CLI (`cmd/main/`) -> HVM2 Book / HVM3 Interaction Calculus files.
2. **Runtime execution**: HVM2 (`scripts/run_hvm2.sh` / `vendor/HVM2/target/release/hvm`) and HVM3 (`scripts/run_hvm3.sh` / `vendor/HVM3/dist-newstyle/**/hvm`).
3. **Semantic Equivalence**: 1-to-1 output matching against reference Haskell execution via `runghc`.
4. **Execution Performance**: Wall-clock execution time benchmarking across GHC, HVM2, and HVM3.

---

## Usage

### Run All Fixtures (Default)

```bash
./tests/e2e/run_all.sh
```

### Verbose Mode with Detailed Timing

```bash
./tests/e2e/run_all.sh --verbose
```

### Run Single Target Backend

```bash
./tests/e2e/run_all.sh --target hvm2
./tests/e2e/run_all.sh --target hvm3
```

### Filter Specific Test Fixtures

```bash
./tests/e2e/run_all.sh --filter 02_fib
./tests/e2e/run_all.sh --filter tree
```

### Machine-Readable JSON Output

```bash
./tests/e2e/run_all.sh --json
```

---

## Canonical Test Fixtures

| Fixture | Description | Expected Value |
|---|---|:---:|
| `01_arith` | Curried arithmetic (+, -, *), nested application, precedence | `48` |
| `02_fib` | Recursive Fibonacci (fib 10), unboxed worker-wrapper, numeric branch | `55` |
| `03_adt` | Bool, Maybe, List constructors & multi-branch pattern matching | `42` |
| `04_higher_order` | Higher-order `myMap` and `myFold` over lists with curried lambdas | `24` |
| `05_tree` | Recursive binary tree construction and parallel summation (`sumTree`) | `92` |

---

## Latest Verification Matrix

All 5 canonical fixtures pass with **100% semantic equivalence** across both HVM2 and HVM3 targets.

| Fixture | Status | GHC (runghc) | HVM2 Out | HVM2 Equiv | HVM2 Time | HVM3 Out | HVM3 Equiv | HVM3 Time | GHC Time |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `01_arith` | ✅ PASS | `48` | `48` | ✅ YES | ~0.016s | `48` | ✅ YES | ~0.067s | ~0.413s |
| `02_fib` | ✅ PASS | `55` | `55` | ✅ YES | ~0.015s | `55` | ✅ YES | ~0.050s | ~0.371s |
| `03_adt` | ✅ PASS | `42` | `42` | ✅ YES | ~0.015s | `42` | ✅ YES | ~0.052s | ~0.359s |
| `04_higher_order` | ✅ PASS | `24` | `24` | ✅ YES | ~0.016s | `24` | ✅ YES | ~0.050s | ~0.378s |
| `05_tree` | ✅ PASS | `92` | `92` | ✅ YES | ~0.017s | `92` | ✅ YES | ~0.052s | ~0.390s |
