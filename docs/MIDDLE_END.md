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

## Open issues

1. `06_lazy_stream` returns `0` on HVM2 instead of `55`. This predates the
   middle-end: commit `8934987` returns `55`, the working tree checkpoint
   `b0077f9` returns `0`, and `--no-prune` returns `0` too. Root cause is in
   the lowerer, not the middle-end. `register_known_constructors` pre-registers
   `Nil` in a `{Nil, Cons}` family, then `$wsumList` mixes `Nil` and `LCons`;
   `register_program_adts` skips the discovered `{Nil, LCons}` family because a
   constructor is already registered, so the `valid_alts` check rejects the case
   and lowering falls through to the `case_fallback` path, which erases the
   scrutinee and returns `0`. The same duplication emits two conflicting `@Nil`,
   `@Cons`, `@True`, `@False` definitions. Fixing it needs one authoritative ADT
   family analysis, target-neutral, owned by this stage.
2. Three alpha-duplicate definitions survive on `GhcCompiler` because they share
   a *name* (`Nil`, `Cons`, `False`, `True`), and the merge refuses to choose
   between same-named blocks. Same root cause as issue 1.
3. The CoreLite passes fire on hand-written Core but find nothing on GHC Core,
   which arrives already simplified. Their value is insurance for Core that has
   not been through GHC's simplifier, and they must stay cheap.
