# Coronet middle-end

The middle-end is the target-neutral stage between linked CoreLite and either
backend. Its job is to remove work before lowering expands it.

## Why it exists

Lowering is an expansion. Every `case` alternative and every lambda becomes its
own top-level net, with captured free variables threaded through a call spine.
Anything that reaches lowering therefore becomes a net, a definition, and a
call spine. Both backends also emitted their whole runtime prelude on every
compile.

A one-line CoreLite program used to compile to 20 798 bytes and 280 HVM2
definitions, 279 of which `@main` could not reach. On `GhcCompiler.core`, 386
of the 1127 emitted definitions were alphabetic copies of another definition
under a different wire naming.

## Data shape

The stage deliberately reuses `@syntax.Program`. The domain is a binding graph,
not a tree: definitions reference each other by name, and a case alternative is
a branch of one scrutinee. Two representations carry that shape:

- **Reachability** (`src/mid/book.mbt`): a definition graph keyed by name, edges
  from `@name` references, roots from `@main`. Used on the emitted book by both
  backends.
- **Canonical form** (`src/mid/core_pass.mbt`): a de Bruijn-style key for an
  expression and for an emitted net body. Local binders become `#depth` /
  `vN`; free names keep their spelling, so recursion does not collapse with its
  copy. Equality of keys is what "merge" means.

## Pipeline

`@mid.optimize(program, stats)` runs before lowering, in `cmd/main`:

| Pass | What it removes |
| --- | --- |
| `prune_top_bindings` | top-level bindings no entry point reaches |
| `prune_dead_lets` | `let` bindings their body never reads |
| `fold_constants` | arithmetic and bitwise primop calls on literals at compile time |
| `inline_trivial_lets` | `let x = y` / `let x = lit` wires, refusing when substitution would capture |
| `inline_known_calls` | single-use small `let` expressions and immediate beta redexes (`(\x -> body) arg`) |
| `simplify_unboxed` | redundant unboxed constructor wrapping/unwrapping, let-scrutinee floating, and identity cases |
| `prune_dead_alts` | alternatives that provably cannot match when scrutinee constructor or literal is known |
| `reduce_known_cases` | `case` on a constructor or literal, substituting matching fields |
| `deforest_streams` | intermediate constructor nets across producer-consumer case chains and stream pipelines (`map f (map g xs)`) |
| `sink_dominator_dups` | pushes let bindings / DUPs into the specific branch dominating all their uses |
| `symbolic_supercompile` | drives case expressions via pattern constraint propagation and flattens nested calls |
| `push_let_into_case` | pushes compound `let` into the single alternative that demands it (DUP minimisation) |
| `merge_alt_bodies` | one copy of a body several alternatives share, hoisted to a `let` |
| `merge_top_bindings` | alphabetic duplicates, replaced by an alias |
| `eta_reduce` | `\x -> f x` wrappers where `x` is not free in `f` |

`eta_reduce` is insurance for Core that has not been through GHC's simplifier;
GHC Core is already eta-normal, so it currently reports zero on all fixtures.

The loop runs to a fixpoint (bounded at three rounds) so a reduction that
exposes a dead binding is picked up in the same compile. `--mid-stats` prints
what each pass removed.

After lowering, `cmd/main` prunes and merges the emitted book:
`prune_book_text` then `merge_alpha_duplicate_defs`. Both backends share this,
so HVM2, HVM3, and the GPU targets that consume HVM2 text all benefit.
`--no-prune` skips both for debugging.

## Measured effect

`python3 tests/e2e/measure_mid.py --raw` on this repo's own inputs. Raw is
`--no-prune`, i.e. the book as lowering produced it.

| input | bytes | defs | alpha-dup defs |
| --- | ---: | ---: | ---: |
| `01_arith` | 20 798 → **11** | 280 → **1** | 113 → **0** |
| `05_tree` | 22 207 → **1 933** | 288 → **14** | 114 → **0** |
| `08_mergesort` | 27 447 → **8 071** | 341 → **52** | 119 → **0** |
| `map_core` | 46 670 → **25 871** | 363 → **83** | 122 → **0** |
| `bytestring_core` | 22 307 → **3 796** | 284 → **24** | 114 → **0** |
| `GhcCompiler` | 163 383 → **112 483** | 1 127 → **692** | 386 → **3** |

Runtime results and interaction counts are unchanged on every fixture and
package: HVM2 `ITRS` for `map_core` is 10 999 753 both ways, for `GhcCompiler`
11 044 486 both ways. What shrank is the artifact and the work needed to build
and load it, not the reduction a program performs. Cutting runtime interactions
needs a different encoding, not a smaller book.

## Invariants a pass must preserve

- Lowering decides top-level vs local by membership in `top_names`. A pass must
  not turn a local name into a top-level one or the reverse.
- `sanitize_name` is applied at emission; passes work on raw names and must keep
  them distinct.
- Unboxed constructors are unwrapped by the lowerer (`I#`, `W32#`, tuples). A
  pass may substitute into them but must not drop the wrapper.
- Case alternatives are ordered by the ADT family in the current lowerer.
  Removing an alternative is sound only when the scrutinee's constructor is
  known; reordering is not.
- A substitution is only allowed when no binder in the target would capture a
  free name of the value. `substitute_without_capture` refuses instead of
  renaming, so a missed optimisation is the only possible outcome.
- Push-down of `let` bindings into `case` branches is only allowed when the
  binding is referenced in at most one alternative and not in the scrutinee.
  This guarantees evaluation order is preserved and avoids duplicating work.
- Inlining known calls is restricted to single-use small expressions or
  immediate beta redexes (`App(Lam(x, body), arg)`), preventing code bloat.

## Runtime Interaction (ITRS) and Node Allocation Reductions

The following middle-end passes directly reduce HVM interaction counts and net node allocations:

1. **Constant Folding (`fold_constants`)**:
   Evaluates known arithmetic (`+`, `-`, `*`, `/`, `%`), comparison (`==`, `/=`, `<`, `<=`, `>`, `>=`), and bitwise operators (`&`, `|`, `^`, `<<`, `>>`) on integer literals at compile time, eliminating runtime arithmetic interaction nodes.

2. **Dead Constructor Branch Pruning (`prune_dead_alts`)**:
   When a `case` matches on a known constructor or literal, non-matching alternative branches are dropped before lowering. This prevents the lowerer from emitting branch nets for unreachable paths.

3. **Worker-Wrapper & Unboxed Constructor Simplification (`simplify_unboxed`)**:
   Unwraps redundant unboxed constructor wrappers `case (I# x) of { I# y -> body }` to `body[y := x]`, eliminates identity case evaluations `case x of { I# y -> I# y }` to `x`, collapses redundant re-boxing `I# (case e of { I# y -> y })` to `e`, and floats let-bindings out of case scrutinees to expose constructors to case matching.

4. **Core Inlining and Known-Call Specialization (`inline_known_calls`)**:
   Eliminates direct beta redexes `(\x -> body) arg` at compile time and inlines small single-use let-bound functions, bypassing HVM lambda and application node interaction cycles.

5. **DUP Minimization / Push-Down (`push_let_into_case` and `sink_dominator_dups`)**:
   Pushes compound let-bindings into the single `case` branch that consumes them. Because the binding is not kept outside the case, the lowerer avoids emitting DUP fan-out nodes across all case alternatives. Dominator DUP sinking (`sink_dominator_dups`) handles multi-use bindings by pushing them into their strict dominator branch.

6. **Stream Fusion / Deforestation (`deforest_streams`)**:
   Fuses producer-consumer chains on intermediate data structures (e.g. `case (case scrut of alts1) of alts2`), completely bypassing intermediate constructor allocations (`Cons`/`Nil`, etc.). Also fuses stream pipelines such as `map f (map g xs)` into `map (\x -> f (g x)) xs` and `map f (Cons x xs)` into `Cons (f x) (map f xs)`.

7. **Supercompilation / Symbolic Driving (`symbolic_supercompile`)**:
   Applies symbolic driving with pattern constraint propagation. Inside a case branch `Data(c, vars)`, the scrutinee is known to equal `Constr(c, vars)`, so nested cases inspecting the same variable are resolved at compile time without a second runtime dispatch. Flattens nested function applications on known constructors into single-step rules.

## Open issues

1. **Fixed.** `06_lazy_stream` returns `55` on both HVM2 and HVM3. The
   duplicate-family check in `merge_alpha_duplicate_defs` used to refuse to
   merge same-named blocks, leaving two conflicting `@Cons` definitions; the
   merge now picks a canonical body and the `{Nil, LCons}` case lowers normally.
2. **Fixed.** `GhcCompiler` alpha duplicates (`Nil`, `Cons`, `False`, `True`)
   go through the same merge, so they are emitted once.
3. The CoreLite passes fire on hand-written Core but find nothing on GHC Core,
   which arrives already simplified. Their value is insurance for Core that has
   not been through GHC's simplifier, and they must stay cheap.

## CAF threading and shared-read rebuilding

`thread_caf_sharing` runs before the fixed-point passes. It finds computed
top-level bindings (CAFs) referenced from a recursive SCC, discovers the SCCs
with Tarjan, and prepends the CAF as a parameter to every member. Internal calls
pass the formal parameter; external callers pass the CAF once. It refuses
aliases and cycles with non-saturated uses, so partial applications are left
alone.

`rebuild_shared_reads` then redirects a member's reader call to a
pair-returning twin. The reader returns `(result, rebuilt-node)` and the loop
threads the freshly rebuilt node instead of the shared wire, so a destructive
`case` read no longer forces a DUP of the whole subtree on every iteration. It
only fires when the reader feeds a `case`, recursive reads sit in tail position,
and no path reads two children.

Measured on HVM2 C, one thread:

| input | before | after CAF | after rebuild |
| --- | ---: | ---: | ---: |
| `map_core` | 10,999,753 | — | **154,766** |
| `map300` (documented baseline) | 135,290,287 | 2,134,946 | 621,416 |

`map_core` still returns `10570`; `nqueens9` and `bytestring_core` are
untouched.
