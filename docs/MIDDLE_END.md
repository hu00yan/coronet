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
| `thread_caf_sharing` | re-expansion of a computed top-level binding once per iteration of the recursive loop that reads it |
| `rebuild_shared_reads` | per-read copying of a threaded CAF's nodes: the reader returns the node it rebuilt, so the loop threads a fresh one |
| `prune_dead_lets` | `let` bindings their body never reads |
| `inline_trivial_lets` | `let x = y` / `let x = lit` wires, refusing when substitution would capture |
| `reduce_known_cases` | `case` on a constructor or literal, plus the alternatives that cannot be taken |
| `merge_alt_bodies` | one copy of a body several alternatives share, hoisted to a `let` |
| `merge_top_bindings` | alphabetic duplicates, replaced by an alias |

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
| `GhcCompiler` | 163 383 → **108 841** | 1 127 → **667** | 386 → **0** |

Runtime results and interaction counts are unchanged on every fixture and
package: HVM2 `ITRS` for `map_core` is 10 999 753 both ways, for `GhcCompiler`
11 044 486 both ways. What shrank is the artifact and the work needed to build
and load it, not the reduction a program performs. Cutting runtime interactions
needs a different encoding, not a smaller book.

`thread_caf_sharing` and `rebuild_shared_reads` are the passes that cut runtime
interactions rather than artifact size. A
computed top-level binding (a CAF) lowers to a REF that re-expands on every
activation of the net containing it; when that net is a recursive loop, the
computation reruns per iteration. Threading the CAF as an explicit parameter
through the loop's call cycle makes the lowerer insert DUP nodes that share
one evaluation. Measured on the HVM2 C runtime: `map300` 135 290 287 →
2 134 946 ITRS (63x), `map_core` 10 999 753 → 317 025 (35x), same results,
every other input unchanged.

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

## Open issues

1. Fixed by `b7678cc` ("let the program own its ADT families"): the program's
   discovered ADT families are authoritative, `06_lazy_stream` returns `55` on
   both backends, and the conflicting same-named constructor definitions are
   gone (`GhcCompiler` carries 0 alpha-duplicate definitions as of
   `measure_mid.py --raw`).
2. The tree-shaped passes (`prune_dead_lets`, `inline_trivial_lets`,
   `reduce_known_cases`, `merge_alt_bodies`) still find nothing on GHC Core,
   which arrives already simplified. Their value is insurance for Core that
   has not been through GHC's simplifier, and they must stay cheap. The pass
   that does fire on GHC Core is `thread_caf_sharing` (1 threading on the map
   family, 6 on `GhcCompiler`).
3. `thread_caf_sharing` threads a CAF only through the cycle that reads it,
   with up to three fixpoint rounds. A CAF read by two independent loops gets
   two threads (one per loop), which is right; a CAF read by a cycle nested
   more than three loops deep keeps re-expanding in the innermost ones.
4. The trace instrument (`src/mid/trace/main`) emits a book that differs from
   the CLI's on `GhcCompiler` (the perf harness records
   `trace_matches_cli: false` for that input only). Timing numbers for
   `GhcCompiler` are therefore suspect; its ITRS row is a timeout either way.
