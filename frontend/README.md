# CoreLite — Coronet Frontend Specification & Extraction Pipeline

## 1. Overview & Purpose

**CoreLite** is the intermediate representation (IR) accepted by the **Coronet** compiler pipeline. It is a strictly pure, untyped subset of Glasgow Haskell Compiler (GHC) Core (as emitted by `ghc -ddump-simpl`), stripped of type annotations, coercions, dictionary-passing boilerplate, and IO runtime wrapping.

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
                 | AppExpr
                 | LamExpr
                 | LetExpr
                 | CaseExpr

AppExpr        ::= Expr AtomExpr
AtomExpr       ::= Var | LitInt | Constr | "(" Expr ")"

LamExpr        ::= "\" Var+ "->" Expr

LetExpr        ::= "let" Bind "in" Expr

CaseExpr       ::= "case" Expr "of" Var? "{" (Alt (";" Alt)*)? "}"

Alt            ::= Pat "->" Expr

Pat            ::= "__DEFAULT"
                 | Var
                 | LitInt
                 | ConstrName Var*

Constr         ::= ConstrName AtomExpr*

ConstrName     ::= [A-Z][a-zA-Z0-9_]* | "I#"
Var            ::= [a-z_$][a-zA-Z0-9_$#]* | Operator
Operator       ::= "+" | "-" | "*" | "/=" | "<=" | ">=" | "<" | ">"
                 | "+#" | "-#" | "*#" | "<=#" | "==#" | "/=#"
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
| **Constructor** | `Leaf x`, `I# 48#`, `MyNil` | `Expr::Constr(String, Array[Expr])` |
| **Application** | `f x y` | `Expr::App(Expr, Expr)` |
| **Lambda** | `\ x y -> body` | `Expr::Lam(String, Expr)` |
| **Let Expression** | `let x = e1 in e2` | `Expr::Let(Bind, Expr)` |
| **Case Expression** | `case scrut of bndr { ... }` | `Expr::Case(Expr, binder, Array[Alt])` |
| **Default Pattern** | `__DEFAULT -> expr` | `Pat::Default(None)` |
| **Literal Pattern** | `1# -> expr` | `Pat::Lit(Int)` |
| **Data Pattern** | `Node l r -> expr` | `Pat::Data(String, Array[String])` |

---

## 4. The Extraction Pipeline (`frontend/extract_core.sh`)

The extraction pipeline compiles standard Haskell source files (`.hs`) into clean CoreLite (`.core`).

### 4.1 CLI Usage

```bash
# Compile Haskell to CoreLite
./frontend/extract_core.sh <input.hs> [output.core]

# Example
./frontend/extract_core.sh tests/fixtures/hs/01_arith.hs tests/fixtures/core/01_arith.core
```

### 4.2 GHC 9.14 Options

`frontend/extract_core.sh` invokes GHC with the following specialized flags:

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

Flag purposes:
- `-c`: Compile only, avoid linking and prevent `[2 of 2] Linking ...` output.
- `-O`: Runs the simplifier, inlines typeclasses, and performs worker-wrapper transformations.
- `-ddump-simpl`: Dumps Core after optimization.
- `-dsuppress-all`, `-dsuppress-uniques`, `-dsuppress-module-prefixes`: Strips compiler uniqueness tags and module paths.
- `-dsuppress-type-signatures`, `-dsuppress-type-applications`, `-dsuppress-coercions`: Strips types and casts.
- `-dno-typeable-binds`: Eliminates GHC Typeable reflection metadata (`$tc...`, `$trModule...`).
- `-outputdir "$TMP_DIR"`: Directs temporary compilation artifacts (`.hi`, `.o`) to a scratch directory to ensure the repository remains pristine.

### 4.3 Post-Processing Transformations

1. **Header Stripping**: Discards GHC compilation banners and `Result size of Tidy Core` metadata.
2. **Metadata Elimination**: Prunes leftover Typeable dictionary bindings (`$trModule`, `$tc`, `$krep`).
3. **Lambda Un-typing**: Erases type abstractions (`\ @a @b x ->` becomes `\ x ->`).
4. **Dictionary Operator Translation**: Rewrites `$fNumInt_$c+`, `$fNumInt_$c-`, `$fNumInt_$c*` to primitive operator symbols `+`, `-`, `*`.
5. **Entry Point Normalization**: In standard Haskell fixtures, the pure computation is bound to `result = ...` and printed via `main = print result` for reference execution. The pipeline strips the IO runtime harness (`hPutStr2`, `runMainIO`, etc.) and cleanly connects `main = result`.

---

## 5. Standard Test Fixtures

Coronet includes 5 canonical test fixtures covering essential functional programming paradigms.

| Fixture Name | Category | Haskell Source | CoreLite File | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| `01_arith` | Basic Math & Function Calls | `tests/fixtures/hs/01_arith.hs` | `tests/fixtures/core/01_arith.core` | `48` |
| `02_fib` | Recursion & Branching | `tests/fixtures/hs/02_fib.hs` | `tests/fixtures/core/02_fib.core` | `55` |
| `03_adt` | ADTs, Pattern Matching | `tests/fixtures/hs/03_adt.hs` | `tests/fixtures/core/03_adt.core` | `42` |
| `04_higher_order` | Map, Fold, First-Class Functions | `tests/fixtures/hs/04_higher_order.hs` | `tests/fixtures/core/04_higher_order.core` | `24` |
| `05_tree` | Binary Tree Parallel Reduction | `tests/fixtures/hs/05_tree.hs` | `tests/fixtures/core/05_tree.core` | `92` |

---

## 6. Sample Extracted CoreLite Outputs

### 6.1 `01_arith.core`
```haskell
mul = *

sub = -

add = +

calc
  = \ a b c ->
      case a of { I# x ->
      case b of { I# y ->
      case c of { I# y1 -> I# (-# (*# (+# x y) y1) 42#) }
      }
      }

result = I# 48#

main = result
```

### 6.2 `02_fib.core`
```haskell
Rec {
$wfib
  = \ ww ->
      case <=# ww 1# of {
        __DEFAULT ->
          case $wfib (-# ww 1#) of ww1 { __DEFAULT ->
          case $wfib (-# ww 2#) of ww2 { __DEFAULT -> +# ww1 ww2 }
          };
        1# -> ww
      }
end Rec }

fib
  = \ n ->
      case n of { I# ww -> case $wfib ww of ww1 { __DEFAULT -> I# ww1 } }

result = case $wfib 10# of ww { __DEFAULT -> I# ww }

main = result
```

### 6.3 `03_adt.core`
```haskell
safeHead
  = \ xs ->
      case xs of {
        MyNil -> MyNothing;
        MyCons h ds -> MyJust h
      }

fromMaybe
  = \ def m ->
      case m of {
        MyNothing -> def;
        MyJust x -> x
      }

isNil
  = \ xs ->
      case xs of {
        MyNil -> MyTrue;
        MyCons ds ds1 -> MyFalse
      }

process1 = I# 0#

process
  = \ xs ->
      case xs of {
        MyNil -> process1;
        MyCons ds ds1 -> ds
      }

result = I# 42#

testList2 = I# 10#

testList1 = MyCons testList2 MyNil

testList = MyCons result testList1

main = result
```

### 6.4 `04_higher_order.core`
```haskell
Rec {
myMap
  = \ f xs ->
      case xs of {
        MyNil -> MyNil;
        MyCons y ys -> MyCons (f y) (myMap f ys)
      }
end Rec }

Rec {
myFold
  = \ f acc xs ->
      case xs of {
        MyNil -> acc;
        MyCons y ys -> myFold f (f acc y) ys
      }
end Rec }

testList7 = I# 1#
testList6 = I# 2#
testList5 = I# 3#
testList4 = I# 4#
testList3 = MyCons testList4 MyNil
testList2 = MyCons testList5 testList3
testList1 = MyCons testList6 testList2
testList = MyCons testList7 testList1

double = \ x -> + x x

result3 = I# 0#

result2 = \ x -> case x of { I# x1 -> I# (+# (*# 2# x1) 1#) }

result1 = myMap result2 testList

result = myFold + result3 result1

main = result
```

### 6.5 `05_tree.core`
```haskell
Rec {
sumTree
  = \ t ->
      case t of {
        Leaf x -> x;
        Node l r ->
          case sumTree l of { I# x ->
          case sumTree r of { I# y -> I# (+# x y) }
          }
      }
end Rec }

Rec {
$wbuildTree
  = \ ww x ->
      case <=# ww 0# of {
        __DEFAULT ->
          Node
            ($wbuildTree (-# ww 1#) (case x of { I# x1 -> I# (*# x1 2#) }))
            ($wbuildTree
               (-# ww 1#) (case x of { I# x1 -> I# (+# (*# x1 2#) 1#) }));
        1# -> Leaf x
      }
end Rec }

buildTree = \ d x -> case d of { I# ww -> $wbuildTree ww x }

myTree1 = I# 1#

myTree = $wbuildTree 3# myTree1

result = sumTree myTree

main = result
```

---

## 7. Verification

Verify the entire test suite against GHC reference execution using `runghc`:

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
```
