# CoreLite — Coronet Frontend Specification & Extraction Pipeline

## 1. Overview & Purpose

**CoreLite** is the intermediate representation (IR) accepted by the **Coronet** compiler pipeline. It is a strictly pure, untyped subset of Glasgow Haskell Compiler (GHC) Core (as emitted by `ghc -ddump-simpl` or via the native GHC plugin `CoronetPlugin`), stripped of type annotations, coercions, dictionary-passing boilerplate, and IO runtime wrapping.

Coronet compiles Haskell programs into **HVM2** and **HVM3** interaction nets / interaction calculus runtimes to investigate implicit parallel execution. CoreLite serves as the clean contract between the Haskell frontend (GHC 9.14) and the MoonBit backends (`src/lower_hvm2` and `src/lower_hvm3`).

---

## 2. CoreLite Syntax (EBNF Grammar)

A CoreLite compilation unit consists of a sequence of top-level bindings.

```ebnf
Program        ::= Bind*

Bind           ::= NonRecBind | RecBind
NonRecBind     ::= Var "=" Expr
RecBind        ::= "Rec" "{" (Var "=" Expr ";"?)* "end" "Rec" "}"

Expr           ::= Var
                 | LitInt
                 | LitChar
                 | LitString
                 | Constr
                 | UnboxedTupleExpr
                 | AppExpr
                 | LamExpr
                 | LetExpr
                 | CaseExpr

AppExpr        ::= Expr AtomExpr
AtomExpr       ::= Var | LitInt | Constr | UnboxedTupleExpr | "(" Expr ")"
UnboxedTupleExpr ::= "(#" (Expr ("," Expr)*)? "#)"

LamExpr        ::= "\" Var+ "->" Expr

LetExpr        ::= "let" Bind "in" Expr

CaseExpr       ::= "case" Expr "of" Var? "{" (Alt (";" Alt)*)? "}"

Alt            ::= Pat "->" Expr

Pat            ::= "__DEFAULT"
                 | Var
                 | LitInt
                 | ConstrName Var*
                 | "(#" (Var ("," Var)*)? "#)"

Constr         ::= ConstrName AtomExpr*

ConstrName     ::= [A-Z][a-zA-Z0-9_]* | "I#"
Var            ::= [a-z_$][a-zA-Z0-9_$#]* | Operator
Operator       ::= "+" | "-" | "*" | "/=" | "<=" | ">=" | "<" | ">"
                 | "+#" | "-#" | "*#" | "<=#" | "==#" | "/=#" | ">#" | "<#"
LitInt         ::= [0-9]+ "#"?
LitChar        ::= "'" [^'\\] "'"
LitString      ::= "\"" [^"\\]* "\""
```

---

## 3. MoonBit AST Mapping (`src/syntax/ast.mbt`)

CoreLite text directly maps 1-to-1 to the MoonBit AST:

| CoreLite Construct | Concrete Text Syntax | MoonBit AST Variant (`@syntax.Expr` / `Bind`) |
| :--- | :--- | :--- |
| **Non-recursive Binding** | `foo = \ x -> + x 1` | `Bind::NonRec("foo", Expr)` |
| **Recursive Group** | `Rec { fib = ... end Rec }` | `Bind::Rec([(name, expr), ...])` |
| **Variable** | `x`, `wfib`, `+#` | `Expr::Var(String)` |
| **Unboxed / Boxed Int** | `42#`, `10` | `Expr::LitInt(Int)` |
| **Constructor** | `Leaf x`, `I# 48#`, `MyNil`, `Pair a b` | `Expr::Constr(String, Array[Expr])` |
| **Application** | `f x y` | `Expr::App(Expr, Expr)` |
| **Lambda** | `\ x y -> body` | `Expr::Lam(String, Expr)` |
| **Let Expression** | `let x = e1 in e2` | `Expr::Let(Bind, Expr)` |
| **Case Expression** | `case scrut of bndr { ... }` | `Expr::Case(Expr, binder, Array[Alt])` |
| **Default Pattern** | `__DEFAULT -> expr` | `Pat::Default(None)` |
| **Literal Pattern** | `1# -> expr` | `Pat::Lit(Int)` |
| **Data Pattern** | `Node l r -> expr` | `Pat::Data(String, Array[String])` |
| **Unboxed Tuple** | `(# a, b #)` | `Expr::Constr("(#,#)", [a, b])` |
| **Unboxed Tuple Pattern** | `(# x, y #) -> expr` | `Pat::Data("(#,#)", ["x", "y"])` |

---

## 4. Native GHC Core Plugin (`frontend/CoronetPlugin.hs`)

Coronet provides a native GHC 9.14 Core plugin that hooks into the GHC compiler pipeline directly, avoiding fragile regex text parsing by traversing GHC's internal `CoreProgram` AST.

### 4.1 Compilation

Compile the plugin with dynamic object generation enabled:
```bash
ghc -package ghc -dynamic-too -c frontend/CoronetPlugin.hs
```

### 4.2 Direct Plugin Usage

```bash
# Dump CoreLite directly to an output file
ghc -c -O -package ghc \
    -fplugin=CoronetPlugin \
    -fplugin-opt=CoronetPlugin:out=output.core \
    -ifrontend \
    MyProgram.hs

# Or print CoreLite directly to stdout
ghc -c -O -package ghc \
    -fplugin=CoronetPlugin \
    -ifrontend \
    MyProgram.hs
```

### 4.3 Plugin Capabilities
- **Post-Simplifier Hook**: Injected after GHC's simplifier pass (`installCoreToDos`) to benefit from full inlining, constant folding, and worker/wrapper transformations.
- **Type / Coercion Erasure**: Discards type abstractions (`isTyVar`), type arguments (`Type _`), and coercions (`Coercion _`).
- **Metadata Pruning**: Automatically filters out reflection bindings (`$trModule`, `$tc`, `$krep`).
- **Entrypoint Synthesizer**: Connects `result` bindings cleanly to `main = result`.

---

## 5. The Extraction CLI (`frontend/extract_core.sh`)

The extraction pipeline compiles standard Haskell source files (`.hs`) into clean CoreLite (`.core`).

### 5.1 CLI Usage

```bash
# Standard extraction mode (GHC simplifier dump + post-processing filter)
./frontend/extract_core.sh <input.hs> [output.core]

# Native Plugin extraction mode (invokes CoronetPlugin directly)
./frontend/extract_core.sh --plugin <input.hs> [output.core]
```

### 5.2 GHC 9.14 Options

When running in standard dump mode, `extract_core.sh` uses:
```bash
ghc -c -O \
    -ddump-simpl \
    -dsuppress-all \
    -dsuppress-uniques \
    -dsuppress-module-prefixes \
    -dsuppress-idinfo \
    -dsuppress-type-signatures \
    -dsuppress-type-applications \
    -dsuppress-coercions \
    -dsuppress-var-kinds \
    -dno-typeable-binds \
    -outputdir "$TMP_DIR" \
    -fforce-recomp \
    "$INPUT_HS"
```

---

## 6. Benchmark & Test Suite Fixtures

Coronet includes 8 canonical test fixtures spanning elementary constructs to massive parallel branching algorithms:

| # | Fixture Name | Category | Haskell Source | CoreLite File | Reference Result (`runghc`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `01_arith` | Basic Math & Function Calls | `tests/fixtures/hs/01_arith.hs` | `tests/fixtures/core/01_arith.core` | `48` |
| 2 | `02_fib` | Recursion & Branching | `tests/fixtures/hs/02_fib.hs` | `tests/fixtures/core/02_fib.core` | `55` |
| 3 | `03_adt` | ADTs, Pattern Matching | `tests/fixtures/hs/03_adt.hs` | `tests/fixtures/core/03_adt.core` | `42` |
| 4 | `04_higher_order` | Map, Fold, Currying | `tests/fixtures/hs/04_higher_order.hs` | `tests/fixtures/core/04_higher_order.core` | `24` |
| 5 | `05_tree` | Binary Tree Parallel Reduction | `tests/fixtures/hs/05_tree.hs` | `tests/fixtures/core/05_tree.core` | `92` |
| 6 | `06_lazy_stream` | Infinite Streams & WHNF Demand | `tests/fixtures/hs/06_lazy_stream.hs` | `tests/fixtures/core/06_lazy_stream.core` | `55` |
| 7 | `07_nqueens` | N-Queens Backtracking Search (N=8) | `tests/fixtures/hs/07_nqueens.hs` | `tests/fixtures/core/07_nqueens.core` | `92` |
| 8 | `08_mergesort` | Parallel Divide-and-Conquer Sort | `tests/fixtures/hs/08_mergesort.hs` | `tests/fixtures/core/08_mergesort.core` | `481054039` |

### 6.1 Description of Real-World Workloads

- **`06_lazy_stream`**:
  Generates an infinite stream of natural numbers `from n = Cons n (from (n + 1))` and strictly consumes `takeStream 10`, summing elements to yield `55`. Demonstrates lazy evaluation, demand-driven WHNF unrolling, and recursive data stream consumption.

- **`07_nqueens`**:
  Calculates all 92 valid arrangements of 8 queens on an 8x8 chessboard without mutual attacks. The solver employs monadic-style list backtracking (`concatMapL`) and non-linear recursive tree exploration, generating thousands of parallel reduction opportunities ideal for HVM interaction net graph rewrites.

- **`08_mergesort`**:
  Implements a classic divide-and-conquer merge sort over a list of 16 unsorted integers. Bisects the list recursively into balanced halves via `splitAtL`, recursively sorts sublists in parallel, and merges sorted sequences. Validates result order with a polynomial position-weighted checksum: `481054039`.

---

## 7. Verification

Verify all 8 test fixtures against GHC reference execution using `runghc`:

```bash
for f in tests/fixtures/hs/*.hs; do
  echo -n "$f: "
  runghc "$f"
done
```

Output:
```
tests/fixtures/hs/01_arith.hs: 48
tests/fixtures/hs/02_fib.hs: 55
tests/fixtures/hs/03_adt.hs: 42
tests/fixtures/hs/04_higher_order.hs: 24
tests/fixtures/hs/05_tree.hs: 92
tests/fixtures/hs/06_lazy_stream.hs: 55
tests/fixtures/hs/07_nqueens.hs: 92
tests/fixtures/hs/08_mergesort.hs: 481054039
```

---

## 8. Multi-Module Compilation Testbed (`tests/fixtures/multimodule/`)

Coronet supports multi-module Haskell projects compiled via `CoronetPlugin`.

### 8.1 Architecture & Layout

```
tests/fixtures/multimodule/
├── Math/
│   └── Fib.hs              # Module Math.Fib, exports fib
├── Data/
│   └── ListOps.hs          # Module Data.ListOps, exports List, myMap, mySum
├── Main.hs                 # Main module importing Math.Fib and Data.ListOps
└── core/
    ├── Math_Fib.core       # Qualified CoreLite for Math.Fib
    ├── Data_ListOps.core   # Qualified CoreLite for Data.ListOps
    ├── Main.core           # Qualified CoreLite for Main
    └── manifest.json       # Multi-module package manifest
```

### 8.2 Extraction via CoronetPlugin

When compiling a multi-module tree, supply `-fplugin-opt=CoronetPlugin:dir=<output_dir>`:

```bash
ghc -c -O -package ghc -fplugin=CoronetPlugin \
    "-fplugin-opt=CoronetPlugin:dir=tests/fixtures/multimodule/core" \
    -i. -ifrontend \
    Math/Fib.hs Data/ListOps.hs Main.hs
```

`CoronetPlugin`:
1. Discovers the current module name from GHC's `mg_module`.
2. Emits `<SafeModName>.core` with qualified top-level symbols (e.g. `Math_Fib_fib`, `Data_ListOps_myMap`, `Data_ListOps_mySum`).
3. Emits aliases (`fib = Math_Fib_fib`) to preserve backwards compatibility.
4. Generates and atomically updates `manifest.json` mapping each module to its CoreLite file and exported symbols.

### 8.3 Package Manifest (`manifest.json`)

```json
{
  "modules": [
    {
      "name": "Math.Fib",
      "file": "Math_Fib.core",
      "exports": ["Math_Fib_$wfib", "Math_Fib_fib"]
    },
    {
      "name": "Data.ListOps",
      "file": "Data_ListOps.core",
      "exports": ["Data_ListOps_myMap", "Data_ListOps_$wmySum", "Data_ListOps_mySum"]
    },
    {
      "name": "Main",
      "file": "Main.core",
      "exports": ["testList", "lvl", "result"],
      "entrypoint": "main"
    }
  ]
}
```

### 8.4 Verification

```bash
cd tests/fixtures/multimodule && runghc Main.hs
# Output: 12
```

---

## 9. Heavy Realistic Workload Suite (`tests/fixtures/heavy/`)

Coronet provides two realistic heavy computational workloads to benchmark parallel graph reduction speedups on multi-core CPUs and GPUs:

### 9.1 `Raytracer.hs` (3D Raytracer)

- **Description**: Pure functional raytracer in Haskell. Constructs 3D vectors (`Vec3`), primary rays (`Ray`), spherical geometries (`Sphere`), and a point light source (`Light`). Computes quadratic ray-sphere intersections, surface normal vectors, and ambient/diffuse Lambertian illumination using fixed-point integer mathematics (scale = 1000).
- **Workload**: Traces rays over a 16x16 grid (256 rays), accumulating pixel intensities into a polynomial checksum modulo $10^9 + 7$.
- **Outputs & Baseline**:
  * Reference (`runghc`): `697580120` (0.382s)
  * Compiled (`ghc -O2`): `697580120` (0.01s user)
- **Extracted Core**: `tests/fixtures/heavy/Raytracer.core` (20.6 KB)

### 9.2 `Sha256.hs` (SHA-256 Cryptographic Hash)

- **Description**: Full specification-compliant FIPS 180-4 SHA-256 cryptographic hash function in pure Haskell. Implements $\Sigma_0, \Sigma_1, \sigma_0, \sigma_1, Ch, Maj$ bitwise functions with 32-bit bitwise primitives (`and#`, `or#`, `xor#`, `rotr`, shifts).
- **Workload**: Processes a benchmark message block through 64-word schedule expansion and 64 compression rounds with standard round constants $K_0 .. K_{63}$, computing the cumulative state word checksum.
- **Outputs & Baseline**:
  * Reference (`runghc`): `336861353` (0.353s)
  * Compiled (`ghc -O2`): `336861353` (0.01s user)
- **Extracted Core**: `tests/fixtures/heavy/Sha256.core` (17.2 KB)

### 9.3 Extraction Command

```bash
ghc -c -O2 -package ghc -fplugin=CoronetPlugin \
    -fplugin-opt=CoronetPlugin:out=tests/fixtures/heavy/Raytracer.core \
    -ifrontend tests/fixtures/heavy/Raytracer.hs

ghc -c -O2 -package ghc -fplugin=CoronetPlugin \
    -fplugin-opt=CoronetPlugin:out=tests/fixtures/heavy/Sha256.core \
    -ifrontend tests/fixtures/heavy/Sha256.hs
```

---

## 10. Level 3 Primops & Unboxed Tuples (`tests/fixtures/primops/`)

Coronet supports GHC unboxed tuples (`(# ... #)`), unboxed sums (`(# | ... #)`), and low-level primops (`ByteArray#`, `State# RealWorld`, `runRW#`, `quotInt#`, `remInt#`, `newByteArray#`, `readIntArray#`, `writeIntArray#`).

### 10.1 Fixtures

1. **`01_unboxed_tuple.hs`**:
   - Tests unboxed pair construction `(# quotInt# a b, remInt# a b #)` and unboxed pattern matching `case divModPrim a b of (# q, r #) -> ...`.
   - Verified output: `123`
   - Core file: `tests/fixtures/primops/01_unboxed_tuple.core`

2. **`02_io_state.hs`**:
   - Tests `runRW#`, `State# RealWorld` threading, mutable byte arrays (`newByteArray#`), and array write/read primops (`writeIntArray#`, `readIntArray#`).
   - Verified output: `63`
   - Core file: `tests/fixtures/primops/02_io_state.core`

### 10.2 Extraction

```bash
./frontend/extract_core.sh --plugin tests/fixtures/primops/01_unboxed_tuple.hs tests/fixtures/primops/01_unboxed_tuple.core
./frontend/extract_core.sh --plugin tests/fixtures/primops/02_io_state.hs tests/fixtures/primops/02_io_state.core
```

---

## 11. Real Package Suites & Full GHC Primops (`tests/packages/`)

Coronet supports full GHC primops coverage and real package workloads from the Haskell ecosystem:

### 11.1 Primops Table

- **Arithmetic & Bitwise**: `+#`, `-#`, `*#`, `*H#`, `negateInt#`, `quotInt#`, `remInt#`, `quotRemInt#`, `==#`, `/=#`, `<#`, `<=#`, `>#`, `>=#`, `and#`, `or#`, `xor#`, `not#`, `uncheckedShiftL#`, `uncheckedShiftRL#`, `uncheckedIShiftL#`, `uncheckedIShiftRL#`, `uncheckedIShiftRA#`.
- **Word Operations**: `plusWord#`, `minusWord#`, `timesWord#`, `quotWord#`, `remWord#`, `eqWord#`, `neWord#`, `ltWord#`, `leWord#`, `gtWord#`, `geWord#`, `andWord#`, `orWord#`, `xorWord#`, `notWord#`.
- **Conversions**: `int2Word#`, `word2Int#`, `narrow8Int#`, `narrow16Int#`, `narrow32Int#`, `narrow8Word#`, `narrow16Word#`, `narrow32Word#`, `chr#`, `ord#`.
- **Addr# & Strings**: `unpackCString#`, `unpackCStringUtf8#`, `Addr#`, string literals `"..."#`, `plusAddr#`, `eqAddr#`, `readWord8OffAddr#`, `touch#`.
- **ByteArray# & MutableByteArray#**: `newByteArray#`, `sizeofByteArray#`, `indexWord8Array#`, `readWord8Array#`, `writeWord8Array#`, `indexIntArray#`, `readIntArray#`, `writeIntArray#`, `copyByteArray#`, `readByteArray#`, `writeByteArray#`.
- **MutVar# & State#**: `newMutVar#`, `readMutVar#`, `writeMutVar#`, `runRW#`, `realWorld#`, `State#`, `RealWorld`.
- **Error & Control**: `raise#`, `raiseIO#`, `patError#`.

### 11.2 Package Test Fixtures

1. **`tests/packages/bytestring_core.hs`**:
   - Uses `Data.ByteString` and `Data.ByteString.Char8` from Hackage `bytestring`.
   - Exercises `C.pack`, `Addr#`, `plusAddr#`, `readWord8OffAddr#`, `touch#`, `remInt#`, `word2Int#`, and `B.foldl'`.
   - Verified reference output (`runghc`): `960463596`
   - Core extraction: `tests/packages/bytestring_core.core`

2. **`tests/packages/map_core.hs`**:
   - Full implementation of Haskell `Data.Map` Size-Balanced Binary Search Tree (AVL / balanced bin tree) algorithm with `Bin`, `Tip`, `balanceL`, `balanceR` ($\delta=3, \gamma=2$).
   - Exercises 100 key-value insertions, tree rotations, recursive key lookups, and cumulative fold.
   - Verified reference output (`runghc`): `10570`
   - Core extraction: `tests/packages/map_core.core`
