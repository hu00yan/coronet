# Coronet End-to-End Verification Harness

This directory contains the independent end-to-end verification pipeline and benchmark suite for the **Coronet** compiler.

## Overview

The harness validates the full compilation and execution pipeline:
```
Haskell (.hs) ──> GHC Core (.core) ──> Coronet CLI ──> HVM2 / HVM3 / Colab GPU ──> Evaluated Output
```

It verifies:
1. **Compilation pipeline**: GHC 9.14 Core dump -> extraction/cleaning (`frontend/extract_core.sh` or `frontend/CoronetPlugin.hs`) -> Coronet CLI (`cmd/main/` / `bin/coronet`) -> HVM2 Book / HVM3 Interaction Calculus / CUDA code.
2. **Runtime execution**: HVM2 CPU (`scripts/run_hvm2.sh`), HVM3 CPU (`scripts/run_hvm3.sh`), and HVM2 Colab GPU (`scripts/run_colab_gpu.sh`).
3. **Semantic Equivalence**: 1-to-1 output matching against reference Haskell execution via `runghc`.
4. **Execution Performance**: High-resolution wall-clock execution time benchmarking across GHC, HVM2, HVM3, and Tesla T4 GPU.

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
./tests/e2e/run_all.sh --filter nqueens
```

### Machine-Readable JSON Output

```bash
./tests/e2e/run_all.sh --json
```

---

## Canonical Test Fixtures (8 Suites)

| Fixture | Description | Reference GHC Value |
|---|---|:---:|
| `01_arith` | Curried arithmetic (+, -, *), nested application, precedence | `48` |
| `02_fib` | Recursive Fibonacci (fib 10), unboxed worker-wrapper, numeric branch | `55` |
| `03_adt` | Bool, Maybe, List constructors & multi-branch pattern matching | `42` |
| `04_higher_order` | Higher-order `myMap` and `myFold` over lists with curried lambdas | `24` |
| `05_tree` | Recursive binary tree construction and parallel summation (`sumTree`) | `92` |
| `06_lazy_stream` | Infinite stream generator (`from 1`) with WHNF demand (`takeStream 10`) | `55` |
| `07_nqueens` | Full 8-Queens backtracking solver searching all valid non-attacking boards | `92` |
| `08_mergesort` | Divide-and-conquer parallel merge sort with polynomial checksum verification | `481054039` |

---

## Verification Matrix & Benchmarks

| Fixture | Status | GHC Native (`runghc`) | HVM2 (CPU) | HVM3 (CPU) | HVM2 (Colab GPU) | Semantic Equivalence | GHC Time | HVM2 CPU Time | HVM3 Time | GPU Kernel Time |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `01_arith` | ✅ PASS | `48` | `48` | `48` | `48` | ✅ Exact | 0.3990s | 0.0158s | 0.0505s | 0.01s |
| `02_fib` | ✅ PASS | `55` | `55` | `55` | `55` | ✅ Exact | 0.3930s | 0.0171s | 0.0624s | 0.01s |
| `03_adt` | ✅ PASS | `42` | `42` | `42` | `42` | ✅ Exact | 0.3771s | 0.0126s | 0.0475s | — |
| `04_higher_order` | ✅ PASS | `24` | `24` | `24` | `24` | ✅ Exact | 0.3769s | 0.0164s | 0.0534s | — |
| `05_tree` | ✅ PASS | `92` | `92` | `92` | `92` | ✅ Exact | 0.3843s | 0.0152s | 0.0626s | 0.01s |
| `06_lazy_stream` | ✅ PASS | `55` | `55` | `55` | `55` | ✅ Exact (Lazy WHNF) | 0.4061s | 0.0147s | 0.0486s | — |
| `07_nqueens` | ✅ PASS | `92` | `92` | `N/A*` | `92` | ✅ Exact (GHC & HVM2) | 0.4104s | 0.0965s | N/A* | — |
| `08_mergesort` | ✅ PASS | `481054039` | `11291991` | `481054039` | `11291991` | ✅ Exact (`u24` masked) | 0.3768s | 0.0154s | 0.0737s | — |
