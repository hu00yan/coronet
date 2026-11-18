# Coronet: GHC Core to Higher-Order Virtual Machine Compiler

**Coronet** is an experimental compiler backend bridging Glasgow Haskell Compiler (**GHC 9.14**) CoreLite to interaction-net and interaction-calculus virtual machines (**HVM2** and **HVM3**).

The overarching goal is to explore whether Haskell programs can achieve implicit, lock-free parallel execution on interaction combinators without modifying upstream Haskell source code.

---

## 1. Design Principles

1. **Semantic Correctness First**:
   All constructs not natively supported by the underlying target virtual machine default to **semantically consistent emulation** (even if slower), rather than silent truncation or unsound shortcuts. Aggressive native hardware performance (e.g. 24-bit raw floats, unchecked arithmetic) is strictly **opt-in via explicit compiler flags**.
2. **Zero Vendor Mutation**:
   Coronet does not maintain a bespoke fork of the HVM2 or HVM3 C/Rust engines. The virtual machines are treated as immutable upstream execution targets. All optimizations live strictly within the Coronet middle-end, lowerers, and runtime preludes.
3. **Principled Middle-End Optimization**:
   Rather than attempting foreign C JITs that suffer from severe impedance mismatch with graph-rewriting interaction combinators, Coronet relies on formal functional compiler passes: Deforestation, Stream Fusion, Worker-Wrapper unboxing, Dominator-based DUP Sinking, and Symbolic Supercompilation.

---

## 2. GHC Ecosystem Integration

Coronet provides a native GHC Core plugin (`frontend/CoronetPlugin.hs`) that extracts CoreLite directly during compilation.

### Setting Up with Cabal

To dump CoreLite from any standard Cabal project, add `CoronetPlugin` to your `cabal.project.local`:

```cabal
-- cabal.project.local
package *
  ghc-options: -fplugin=CoronetPlugin
```

Or pass it directly via CLI:

```bash
cabal build --ghc-options="-fplugin=CoronetPlugin"
```

The plugin dumps `.core` files for each compiled module without altering GHC's normal object code emission.

### Compiling and Running with Coronet

```bash
# 1. Compile CoreLite to HVM3 (default demand-driven WHNF)
coronet input.core --target hvm3 -o output.hvm3

# 2. Compile CoreLite to HVM2 (parallel interaction nets)
coronet input.core --target hvm2 -o output.hvm2

# 3. Execute via HVM3 runner
./scripts/run_hvm3.sh output.hvm3

# 4. Execute via HVM2 parallel C runtime
./scripts/run_hvm2.sh run-c output.hvm2
```

---

## 3. Installation & Distribution

### One-line Installation
```bash
./install.sh
```
Or via `make`:
```bash
make install  # Installs native release binary to ~/.local/bin/coronet
```

### Mooncake Package Registry (MoonBit)
Coronet can be published to and consumed from the MoonBit package registry [mooncakes.io](https://mooncakes.io):
```bash
# 1. Login to Mooncake
moon login

# 2. Validate publication package
moon publish --dry-run

# 3. Publish release
moon publish
```
Downstream MoonBit projects can include Coronet via:
```bash
moon add hu00yan/coronet
```

---

## 4. Supported Primops & Feature Matrix

Coronet covers **1034 / 1491 GHC 9.14 primops** (100% of non-vector realistic float, integer, bit manipulation, and atomic state primops):

```
GHC 9.14.1: 1491 primops, 1034 named in lowering tables
  hvm2 coverage: 990 total, 452 realistic
  hvm3 coverage: 954 total, 416 realistic
```

### Middle-End Optimizations (`src/mid/`)

| Pass | What It Eliminates |
|---|---|
| `fold_constants` | Evaluates arithmetic, comparison, and bitwise operations on literal constants at compile time. |
| `prune_dead_alts` | Drops non-matching case branches when the constructor or literal is statically known. |
| `simplify_unboxed` | Eliminates redundant unboxed wrappers (`case (I# x) of I# y -> ...`), identity unboxing, and re-boxing. |
| `inline_known_calls` | Beta-reduces applied lambdas and inlines single-use small definitions. |
| `deforest_streams` | Stream fusion / Deforestation eliminating intermediate constructor nets across producer-consumer chains. |
| `sink_dominator_dups` | Sinks DUP duplication nodes into the dominating case alternative, preventing premature fan-out copies. |
| `symbolic_supercompile` | Propagates pattern constraints and drives nested cases into single-step rules. |
| `thread_caf_sharing` | Threads top-level CAFs through loop parameters to prevent exponential re-expansion. |
| `rebuild_shared_reads` | Replaces spine-copying readers with pair-returning reconstructors. |

---

## 4. Honest Limitations & Known Reality

*We state what is verified, admit what is unknown, and report where performance or compatibility is currently limited.*

### 1. Concurrency & Lightweight Threads
- **Cooperative Simulation**: In `--sched` mode, `fork#` executes the child action strictly within a single-threaded state-monad sequence. It is **cooperative and deterministic**, not a preemptive GHC RTS.
- **Disjoint State Snapshots**: In native HVM parallel reduction, `fork#` passes independent persistent copies of the state map. Mutations across threads (e.g. `putMVar#`) are not visible across fork boundaries without dedicated channel wires or atomic exchange primops.
- **Unsupported**: Async exceptions, masking, `threadDelay`, and bound OS threads are not supported.

### 2. Floating-Point Precision
- **HVM2 (Native F24)**: HVM2 supports 24-bit floats (`F24`: 1 sign, 7 exponent, 16 mantissa). Precision is limited to ~4.8 decimal digits. Values exceeding $2^{63}$ or requiring $>16$ mantissa bits will truncate or overflow in raw F24 mode.
- **HVM3 (Software Fixed-Point & BigRat)**: HVM3 has no float opcode. Coronet provides Q4.12 biased fixed-point software arithmetic by default, and `--bigrat` exact rational fractions (`Pair numerator denominator`) for 100% loss-free precision.

### 3. Memory Model & Node Allocator
- **HVM2 Allocator**: HVM2 allocates from a 536M bump buffer without slot recycling (no free-list). While pure recursive functions with high locality run well, massive breadth-first intermediate graphs (such as whole-compiler AST passes) can exhaust the buffer and trigger `OOM`.
- **HVM3 WHNF**: HVM3 reduces on the spine in demand-driven WHNF, handling large compiler ASTs without materializing unreachable subgraphs (e.g. `GhcCompiler.core` runs in 0.28s / 1M interactions).

### 4. Garbage Collection & Foreign Primops
- **Tracing GC**: Interaction nets rely on graph rewriting and erasure (`ERA`), not tracing GC. Weak pointers (`mkWeak#`, `deRefWeak#`), stable pointers (`makeStablePtr#`), and compact regions are **explicitly rejected** by the compiler.
- **SIMD / Vector**: 426 vector primops (`broadcast*`, `insert*`, `pack*`) are unhandled.
- **POSIX IO**: Full real-world CLI IO (file handles, network sockets) is modeled via pure state tokens; complete standalone execution of full CLI suites currently requires external runtime driver shims.

---

## 5. Benchmarks & Testing

Verify the test suite locally:

```bash
# 1. Run full MoonBit test suite (123 unit tests)
moon test

# 2. Strict primop coverage check in native MoonBit (exits 0)
moon run cmd/coverage -- --strict

# 3. Core plugin end-to-end regression (25 checks)
./scripts/test_core_plugin.sh

# 4. Interaction profile on mini-GHC compiler
./scripts/run_hvm3.sh -s tests/packages/ghc/GhcCompiler.core
```

---

## License

Apache-2.0 / MIT.
