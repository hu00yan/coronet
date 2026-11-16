# Coronet Target Execution Environments: HVM2 & HVM3

This document serves as the comprehensive specification for the two target execution environments utilized by **Coronet**: **HVM2** and **HVM3**. It details their execution architectures, CLI command invocations, concrete syntax, AST representations, and lowering patterns from CoreLite.

---

## 1. Overview & Architecture Comparison

| Feature | HVM2 (Higher-order Virtual Machine 2) | HVM3 (Interaction Calculus Runtime) |
|---|---|---|
| **Repository** | `vendor/HVM2` | `vendor/HVM3` |
| **Primary Language** | Rust (`cargo build --release`) | Haskell (GHC 9.14) + C runtime (`cabal build`) |
| **Execution Model** | Lafont's Interaction Combinators (symmetric net rewrite) | Interaction Calculus (optimal λ-calculus with native Ctr/Mat) |
| **Backends** | Rust interpreter, C runtime, CUDA GPU | Interpreted WHNF, native C compiler (`-c`) |
| **ADT Support** | Lowered via Scott / Church encodings | Native constructors (`#Ctr{...}`) and pattern matching (`~`) |
| **Duplication** | Symmetric net DUP nodes (`{x y}`) | Affine terms with explicit DUP (`! &L{x y} = v; body`) |
| **Data Types** | U24, I24, F24, Combinator nodes | U32, Char, Strings, ADTs, Lambdas, Nodes |
| **Helper Script** | `scripts/run_hvm2.sh` | `scripts/run_hvm3.sh` |

---

## 2. HVM2 Target Specification

### 2.1 Toolchain & CLI Usage

The HVM2 executable is located at `vendor/HVM2/target/release/hvm`.

```bash
# General invocation
./vendor/HVM2/target/release/hvm <SUBCOMMAND> <file.hvm>

# Subcommands:
#   run     - Interprets the net using the multi-threaded Rust evaluator
#   run-c   - Compiles and interprets via C runtime
#   run-cu  - Evaluates via CUDA (NVIDIA GPU required)
#   gen-c   - Emits standalone C code
#   gen-cu  - Emits standalone CUDA code
```

#### Helper Script: `scripts/run_hvm2.sh`

```bash
./scripts/run_hvm2.sh <file.hvm>          # Runs in default interpreted mode
./scripts/run_hvm2.sh run-c <file.hvm>    # Runs via C runtime
```

#### Remote Colab GPU Execution Bridge: `scripts/run_colab_gpu.sh`

For systems without local NVIDIA GPUs (e.g. macOS Apple Silicon), Coronet provides an automated Google Colab GPU bridge using the local `colab` CLI (`/Users/huyan00/.local/bin/colab`):

```bash
# Compiles and executes on remote Google Colab GPU (Tesla T4)
./scripts/run_colab_gpu.sh <file.hvm|file.cu> [--gpu T4|L4|A100] [--timeout 300] [--json]
```

How it works:
1. Translates `.hvm` to standalone `.cu` code via `hvm gen-cu`.
2. Automatically adapts shared memory buffers (`L_NODE_LEN = 0x1000` / 48 KB) to fit Tesla T4's 64 KB shared memory budget.
3. Provisions a Colab GPU instance via `colab run --gpu T4`.
4. Compiles remotely with `nvcc -O3 -w` and executes on the GPU.
5. Streams `Result`, `ITRS`, `TIME`, and `MIPS` back to local stdout.

#### Output Format
HVM2 outputs statistics and the normal form of the `@main` net root:
```text
Result: 55
- ITRS: 147
- TIME: 0.00s
- MIPS: 16.26
```

---

### 2.2 Concrete Syntax & AST Grammar

An HVM2 file consists of a **Book** containing top-level net definitions:

```hvm
@name = <root_tree>
  & <redex_fst_1> ~ <redex_snd_1>
  &! <redex_fst_2> ~ <redex_snd_2>
```

#### AST Node Types (`Tree` in `vendor/HVM2/src/ast.rs`)

1. **Variables (`Var`)**: Alphanumeric identifiers (e.g., `x`, `ret`, `a`). Variables must appear at most twice (one binder and one consumer, forming an edge).
2. **Global References (`Ref`)**: `@name` references another defined net.
3. **Erasure (`Era`)**: `*` represents an erased wire.
4. **Numbers (`Num`)**:
   - Numeric literals: Unsigned `123`, signed `+123`, `-123`, float `1.23`.
   - Numeric operations: `[+]`, `[-]`, `[*]`, `[/]`, `[%]`, `[=]`, `[!]`, `[<]`, `[>]`, `[&]`, `[|]`, `[^]`.
   - Partially applied operator literals: `[+1]`, `[*2]`.
5. **Constructor Nodes (`Con`)**: `(fst snd)` — 2-port constructor node. Used for lambda binding, function arguments, pairs, and closures.
6. **Duplication Nodes (`Dup`)**: `{fst snd}` — Duplication node. Used when a variable is consumed more than once.
7. **Operation Nodes (`Opr`)**: `$(fst snd)` — Binary arithmetic operation node. Interacts with a `NUM`.
8. **Switch Nodes (`Swi`)**: `?(fst snd)` — Numeric branch node. Interacts with a `NUM`.
   - If number is `0`: branches to `fst` as `(ret *)`.
   - If number is `> 0`: branches to `snd` as `(* ((n - 1) ret))`.

---

### 2.3 Lowering Patterns for HVM2

#### 1. Function Abstraction & Application
Functions and applications interact via Constructor pairs `(arg ret)`:
- Function `@id = (x x)`
- Call site: `& @id ~ (42 res)` links `res` to `42`.

#### 2. Arithmetic
Operation node `$(op $(operand2 result))` interacts with `operand1`:
```hvm
// Evaluates: res = 10 + 20
@main = res
  & $([+] $(20 res)) ~ 10

// Partially applied shortcut:
@main = res
  & $([+10] res) ~ 20
```

#### 3. Higher-Order Functions & Duplication
When a function argument (or closure) is used multiple times, it must be explicitly duplicated using `{f1 f2}`:
```hvm
// twice f x = f (f x)
@twice = ({f1 f2} (x ret))
  & f1 ~ (x temp)
  & f2 ~ (temp ret)
```

#### 4. Algebraic Data Types (Scott Encoding)
HVM2 does not have native nominal ADT tags; ADTs are Scott-encoded:
- `Pair a b = \k -> k a b` -> `(a (b (k ret))) & k ~ (a (b ret))`
- `fst p = p (\x \_ -> x)` -> `(p ret) & p ~ ((x (* x)) ret)`

#### 5. Numeric Recursion & Branching
```hvm
// Recursive sum 1..n:
@sum = (?(((acc acc) @sum_step) call) call)

@sum_step = ({p1 p2} (acc ret))
  & @sum ~ (p1 (new_acc ret))
  & $([+] $(acc new_acc)) ~ n
  & $([+1] n) ~ p2
```

---

## 3. HVM3 Target Specification

### 3.1 Toolchain & CLI Usage

The HVM3 executable is built in `vendor/HVM3` via Cabal and located at:
`vendor/HVM3/dist-newstyle/build/aarch64-osx/ghc-9.14.1/HVM-0.1.0.0/x/hvm/opt/build/hvm/hvm`

```bash
# Command line syntax
hvm run <file.hvm> [flags...] [args...]

# Flags:
#   -c   - Runs with compiled C mode (inlines AST into C and compiles with clang -O3 for native speed)
#   -C   - Collapses the normal form to pure λ-terms (hides intermediate DUP/LET nets)
#   -CN  - Same as -C, but limits collapse to first N results
#   -s   - Shows performance statistics (interactions, seconds, MIPS)
#   -d   - Debug mode (prints intermediate evaluation steps)
#   -Q   - Hides quotes around string outputs
```

#### Helper Script: `scripts/run_hvm3.sh`

`scripts/run_hvm3.sh` automatically locates the HVM3 executable and defaults to `-C` (collapse mode) so outputs are directly comparable with GHC reference outputs.

```bash
./scripts/run_hvm3.sh <file.hvm>       # Interpreted mode, normalized output
./scripts/run_hvm3.sh -c <file.hvm>    # High-performance compiled mode
```

#### Output Format
- Normalized (default collapse `-C`):
  ```text
  55
  ```
- With `-s` (statistics):
  ```text
  55
  WORK: 147 interactions
  TIME: 0.0000150 seconds
  SIZE: 3 nodes
  PERF: 9.800 MIPS
  ```

---

### 3.2 Concrete Syntax & AST Grammar

An HVM3 source file defines data types and top-level functions:

```hvm
data TypeName { #Constructor1{f1 f2} #Constructor2 }

@func_name(arg1 arg2 ...) = <core_expression>
```

#### AST Expressions (`Core` in `vendor/HVM3/src/HVM/Type.hs`)

1. **Variables (`Var`)**: `x`, `foo`. Affine: each variable appears at most once in its scope unless duplicated.
2. **References (`Ref`)**: `@fun(arg1 arg2 ...)`. Invokes a top-level function.
3. **Erasure (`Era`)**: `*`.
4. **Lambda Abstraction (`Lam`)**: `λx <body>`. Must use unicode `'λ'`.
5. **Application (`App`)**: `(fun arg1 arg2 ...)`. Curried function application.
6. **Constructors (`Ctr`)**: `#CtrName{field1 field2 ...}` or `#CtrName` (for nullary constructors).
7. **Pattern Matching (`Mat`)**:
   - ADT Matching: `~ val !mov1 !mov2 { #Ctr1{a b}: body1 #Ctr2: body2 }`
   - Numeric Switch (`SWI`): `~ n { 0: zero_case 1+p: succ_case }`
     - Note: `1+p` binds `p = n - 1`.
8. **Binary Operations (`Op2`)**:
   - `(+ a b)`, `(- a b)`, `(* a b)`, `(/ a b)`, `(% a b)`, `(== a b)`, `(! a b)`, `(< a b)`, `(> a b)`, `(<= a b)`, `(>= a b)`.
9. **Superposition & Duplication (`Sup` & `Dup`)**:
   - Duplication statement: `! &0{x1 x2} = expr; <body>`
   - Fresh duplication: `! &{x1 x2} = expr; <body>`
10. **Let Expressions**:
    - Lazy Let: `! x = expr; <body>`
    - Strict Let: `!! x = expr; <body>`
11. **Strict Function Arguments**: `@fun(!arg1 arg2) = ...` forces strict evaluation of `arg1` before rewriting.

---

### 3.3 Lowering Patterns for HVM3

#### 1. ADT Declaration & Constructor Matching
HVM3 supports native ADT declarations matching Haskell data types:
```hvm
data List { #Nil #Cons{head tail} }

@sum(!xs r) = ~xs !r {
  #Nil: r
  #Cons{head tail}: @sum(tail (+ head r))
}
```

#### 2. Numeric Recursion (Fibonacci)
In HVM3, numeric branches take `0:` and `1+p:`. Subtraction and secondary branching are handled sequentially:
```hvm
@fib(n) = ~ n {
  0: 0
  1+p: ~ p {
    0: 1
    1+p2:
      !&0{p2_a p2_b} = p2
      !p1 = (+ p2_a 1)
      (+ @fib(p1) @fib(p2_b))
  }
}
```

#### 3. Higher-Order Functions (Map & Lambdas)
```hvm
@map(f xs) = ~xs !f {
  #Nil: #Nil
  #Cons{h t}:
    !&0{f1 f2} = f
    #Cons{(f1 h) @map(f2 t)}
}

@main = @map(λx (* x 2) #Cons{1 #Cons{2 #Nil}})
```

---

## 4. Cross-Target Mapping Reference

| CoreLite Construct | HVM2 Translation Pattern | HVM3 Translation Pattern |
|---|---|---|
| **Int literal** `42` | `42` (24-bit integer) | `42` (32-bit unsigned integer) |
| **Addition** `x + y` | `& $([+] $(y res)) ~ x` | `(+ x y)` |
| **Lambda** `\x -> E` | Pair node `(x E)` | `λx E` |
| **Application** `f x` | Wire connection `& f ~ (x ret)` | `(f x)` |
| **Let binding** `let x = e in b` | Redex `& e ~ x` inside net | `! x = e; b` |
| **Duplication** (reuse `x`) | `{x1 x2} ~ x` | `! &0{x1 x2} = x; b` |
| **ADT Definition** | Higher-order Scott constructor | `data Type { #C1{f1} #C2 }` |
| **Constructor** `Cons h t` | Scott pair `(h (t (k ret))) & k ~ ...` | `#Cons{h t}` |
| **Case on ADT** | Calling Scott encoding with match branches | `~ expr !moves { #Nil: ... #Cons{h t}: ... }` |
| **Case on Int** | Switch node `?(case0 case_succ)` | `~ n { 0: zero_case 1+p: succ_case }` |

---

## 5. Verification Test Suite

The sample programs in `tests/samples/` verify all core semantics across both engines:

| Test Case | Feature Under Test | HVM2 File | HVM3 File | Expected Output |
|---|---|---|---|---|
| `01_arith` | Arithmetic operators & precedence | `tests/samples/hvm2/01_arith.hvm` | `tests/samples/hvm3/01_arith.hvm` | `90` |
| `02_fib` | Recursion, loop state, numeric switch | `tests/samples/hvm2/02_fib.hvm` | `tests/samples/hvm3/02_fib.hvm` | `55` |
| `03_adt` | Constructor packaging & projection | `tests/samples/hvm2/03_adt.hvm` | `tests/samples/hvm3/03_adt.hvm` | `123` / `60` |
| `04_higher_order` | Lambdas, closures, higher-order map | `tests/samples/hvm2/04_higher_order.hvm` | `tests/samples/hvm3/04_higher_order.hvm` | `42` / `12` |

Both runners are executable and ready for integration into the Coronet compiler driver and end-to-end test runner (`tests/e2e/run_all.sh`).

---

## 6. Native GPU Targets: Metal, CUDA & HIP

Coronet provides native GPU execution engines supporting zero-copy execution and massively parallel graph rewriting:

### 6.1 Apple Silicon Metal (`--target metal`)
- **Location**: `runtime/metal/coronet_metal.metal` (MSL Compute Shader) and `runtime/metal/coronet_metal.m` (Objective-C Host Harness with embedded MSL)
- **Standalone Toolchain**: `bin/coronet build <file.core> -o <binary> --target metal` compiles directly into an independent macOS executable without external scripts.
- **Features**:
  * **Zero-Copy Unified Memory (UMA)**: Uses `MTLResourceStorageModeShared` allowing host and GPU to share the same physical address space with zero PCIe copy overhead.
  * **SIMD-Group Warp Aggregation**: Eliminates global atomic serialization on work-queues using `simd_prefix_exclusive_sum`, `simd_sum`, and `simd_broadcast`. Warp leaders perform single aggregated atomics, cutting contention by 32x.
  * **Native 32-bit Graph Rewriting**: Implements lock-free atomic substitution (`atomic_uint`) for `APP-LAM`, `OPX/OPY`, `DUP-SUP`, `SWI`, and `VAR`.
  * **High-Throughput Vector Reduction**: Dedicated kernel `coronet_metal_vector_dot` with threadgroup shared-memory tree reduction for numerical workloads.
- **Workloads & Benchmarks (Apple M1 Pro GPU)**:
  * **Vector Inner Product ($N = 10^7$)**: Evaluated in **7.7 ms** at **2,607.15 MIPS** (2.6 GigaOPS throughput).
  * **Raytracer Scaling Benchmark**:
    - $16 \times 16$ (256 rays): 0.0038s, result `697580120`.
    - $64 \times 64$ (4,096 rays): 0.0069s, 8,192 itrs.
    - $128 \times 128$ (16,384 rays): 0.0066s, 31,768 itrs.
    - $256 \times 256$ (65,536 rays): 0.0087s, 127,072 itrs (14.57 MIPS).
  * Arithmetic & Tree Reduction: `./scripts/run_metal.sh --workload arith` / `--workload tree`.

### 6.2 Standalone Native C Target (`--target hvm2`)
- **Pipeline**: `bin/coronet build <file.core> -o <binary> --target hvm2` transforms Core into HVM2, compiles via `hvm gen-c`, and links with `clang -O3` into a self-contained native executable.
- **Performance**: Raytracer benchmark executes in **0.030s** at **90.85 MIPS**, producing bit-for-bit identical checksums.

### 6.3 NVIDIA CUDA (`--target cuda`)
- **Location**: `runtime/cuda/coronet_cuda.cu`
- **Features**: Hierarchical Redex Bag, warp ballot intrinsics, lock-free 64-bit atomic CAS substitutions, dynamic shared memory tuning.

### 6.4 AMD ROCm HIP (`--target hip`)
- **Location**: `runtime/hip/coronet_hip.cpp`
- **Features**: AMD Instinct and Radeon support via `hipLaunchKernelGGL`, wavefront-64 alignment, and lock-free interaction net reduction.

