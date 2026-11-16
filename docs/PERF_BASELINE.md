# Performance baseline: what limits ITRS and multi-core speedup

Reproduce every number here with:

```
python3 tests/e2e/perf/perf_baseline.py            # the full table
python3 tests/e2e/perf/perf_baseline.py --only map300 --json /tmp/m.json
python3 tests/e2e/perf/ab_steal.py                 # the scheduling A/B matrix
```

Machine: Apple M1 Pro, 8 logical cores (6 performance + 2 efficiency),
macOS 27.2, clang -O3 for the compiled C runtime, MoonBit release build
(debug is ~2.6x slower and says nothing about the shipped tool). Wall
clock is min-of-5; ITRS is scheduler-invariant (confluence), so ITRS
comparisons never need repetitions but wall clock always does. First runs
of a binary pay a warm-up cost of up to 2x; a single run is not a
measurement.

## The diagnostic instrument

`vendor/HVM2/src/hvm.c` carries a worktree-only, env-gated diagnostic patch
(`CORONET-DIAG` comments). It is inert unless `HVM_DIAG` is set:

- `HVM_DIAG=1` — per-rule, per-definition and per-thread interaction counts.
  The per-interaction atomics serialize the threads, so timings under mode 1
  are meaningless; counts are exact (atomic).
- `HVM_DIAG=2` — per-thread interaction totals only, recorded once per thread
  at evaluator exit. No per-interaction cost; timings are clean.
- `HVM_DIAG=3` — per-thread steal probes/hits/bulk-taken, bag-depth maxima,
  and hole-stuck miss counts (misses where the victim's `rput` sat far above
  the thief's cursor). Updated on the idle path only, so timings stay clean.

The scheduling patch (`CORONET-STEAL`, see the scheduling section) changes
the shipped default steal behavior: `HVM_STEAL` unset ships `scancap` and
`HVM_STEAL=none` restores the pristine one-slot probe. Vendor changes stay
in the worktree by policy and are listed here for review:

- `src/hvm.c`: the `CORONET-DIAG` counters (modes 1-3), the `CORONET-STEAL`
  strategies (default `scancap`), and the `HVM_TPC_L2` build override in
  `build.rs` (measurement only).
- `src/hvm.rs`: the DUP~REF interaction carries the C runtime's
  `def.safe` guard again. The worktree it was cloned from had erased
  DUP~REF unconditionally, which is sound but defeats the
  expand-once-then-clone path: on the post-CAF-pass `map300` book the Rust
  interpreter performed 135,290,287 interactions where the C runtime performs
  2,134,946. With the guard restored both report 2,134,946.
- The drain-steal steal-loop experiment was applied, measured, and reverted
  (see the scheduling section); its successor strategies live behind
  `HVM_STEAL` with `scancap` shipped as the default.

## map300: where 450k interactions per element went

`map300.core` is GHC-compiled `Data.Map`: build a 300-entry map by repeated
`insert`, then `findWithDefault` each key and sum. The committed baseline
measured 135,290,287 ITRS (~450k per element).

Attribution with `HVM_DIAG=1` on the pre-pass book:

```
RULE_ITRS: total=135290287 LINK=0 CALL=12019726 VOID=10148454 ERAS=12638963
           ANNI=72517487 COMM=1617000 OPER=22773761 SWIT=3574896
DEF_ITRS:  go_s3t0 90300, _sinsert 781800, Bin 2157300,
           slt/slt_same 1440943 each, balanceR 691800, ...
```

The tell is `go_s3t0` (the build fold) being called 90,300 times: 300 inserts
x 301 finds. The map was rebuilt from scratch for every one of the 301 lookups.
`m_a10c = go_s3t0 lvl Tip` is a computed top-level binding (a CAF); lowering
emits one REF per textual use, and the loop's activation re-expands that REF
each iteration. HVM2 has no memoization of REF expansions, so a CAF read by a
recursive loop recomputes per iteration. GHC never shows this shape because
its evaluator shares CAFs.

The fix is a middle-end pass, `thread_caf_sharing` (see
`docs/MIDDLE_END.md`): the CAF becomes a leading parameter of every
definition on the loop's call cycle, internal recursive calls pass it on,
external callers supply it once. The lowerer's linearize step then inserts
the DUP nodes that share one evaluation:

```
@branch_else__C73 = (_u189 (_u190 (_u187 (_u191 ret_331))))
  & @_sfindWithDefault_s3nN ~ (0 (_u190 (_u187_d1 app_ret_332)))
  ...
  & @_wgo_s3t2 ~ (_u187_d2 (add_res_333 (add_res_334 app_ret_335)))
  & {_u187_d1 _u187_d2} ~ _u187
```

Results (HVM2 C runtime, 1 thread):

| input | before | after | |
| --- | ---: | ---: | --- |
| `map300` | 135,290,287 | 2,134,946 | 63x, result 91400 unchanged |
| `map_core` | 10,999,753 | 317,025 | 35x, result 10570 unchanged |

The residual 2.13M is close to the floor this runtime model allows: each of
the 301 readers needs its own copy of every node it touches, because CON-CON
annihilation destroys the cell it reads. The post-pass rule mix (COMM 20%,
ERAS 33%) is clone-and-discard traffic of exactly that kind. Cutting it
further needs a read-only traversal encoding in the lowerer, not a tree pass.

nqueens9 (22,884,287) and bytestring_core (33,229) are untouched by the pass:
their data already flows through explicit recursion arguments. nqueens9's cost
is `safe` checks (215k calls) plus board-list cloning for the 9 candidate
reads per board; that is the same destructive-read floor, not lost sharing.

## Why 8 threads reached only ~3x (pre-pass map300)

The C runtime's threading model (`vendor/HVM2/src/hvm.c`):

- `TPC = 1 << TPC_L2` threads; the book's redex bag is one global array cut
  into `TPC` private segments; a thread pushes its new redexes to its own
  segment and pops LIFO.
- When a thread's segment is empty it steals: exactly one slot from its left
  neighbor (`sid = (tid-1) % TPC`), probing slot 0 of that segment; a failed
  probe resets the probe index to slot 0 and calls `sched_yield`; the global
  halt check runs every 256 idle ticks when `idle == TPC`.
- There is no work splitting: one stolen redex can be an entire search
  subtree.

Per-thread ITRS (`HVM_DIAG=2`), pre-pass map300, 135,290,287 total:

```
TPC=8, three runs:  3.2M,  2.4M, 40.4M, 40.8M, 22.7M, 15.3M,  7.0M,  3.6M
                    3.2M, 41.5M, 41.1M, 21.9M, 14.6M,  8.2M,  2.7M,  2.1M
                    0.8M, 42.0M, 41.4M, 21.8M, 16.4M,  8.2M,  2.9M,  1.7M
```

Two threads hold ~60% of the work in every run, and the wall clock tracks the
heaviest thread: 41M ITRS at ~85 MIPS is ~0.5s, which is the measured 8t time.
A perfect 8-way split would be ~17M per thread and ~0.2s. The 2.9x speedup is
the load imbalance, not contention or barriers: ITRS is identical at every
thread count, and the barrier/idle protocol costs nothing at these sizes.

Classification:

- **Net shape (dominant for map300).** The dependency chain is one sequential
  loop of 301 iterations, each iteration itself a sequential 300-insert
  rebuild. At any instant the bag holds only the current iteration's pending
  redexes, so parallelism is thin and the thief's one-slot probe usually
  finds an empty slot. The bimodal per-thread runs (a run where one thread
  takes all 135M) show the thinness directly.
- **Scheduling (amplifier).** Steal granularity is one redex, the probe index
  only advances on success, and each failed probe costs a `sched_yield`. Even
  the parallelism that exists is captured unevenly (two threads at 40M while
  six share 40M).

A drain-steal experiment (thief takes up to 64 redexes per idle event) was
tried and reverted: interleaved A/B showed map300 8t median 0.55s -> 0.37s
but nqueens9 4t median 0.29s -> 0.46s. A mixed result is not a runtime patch.
The principled fix is real work splitting (steal by depth, or halve the
victim's bag), which is a vendor-line change beyond this branch's scope.
(The scheduling section below supersedes this paragraph: the shipped fix is
work-splitting with bounded bulk, gated and enabled by default.)

For nqueens9 the net shape is wide (thousands of independent subtrees), so
its non-monotonic baseline curve (2t=1.24x, 4t=0.99x, 8t=4.05x) is pure
scheduler lottery: per-thread runs alternate between one thread taking
22.8M of 22.9M and near-even splits, and the min-of-5 protocol lands on
whichever distribution happened to occur. Same protocol, same binary,
8t runs observed at 0.08s and 0.29s. The scheduling section below explains
the lottery mechanically and removes it.

## Scheduling: the steal lottery and the work-splitting fix

The evaluator's steal loop (`vendor/HVM2/src/hvm.c`) had three compounding
defects, all measured with the `HVM_DIAG=3` counters (per-thread steal
probes/hits, bag-depth maxima; idle-path only, timings stay clean):

1. **The boot redex is invisible to its own thread.** `boot_redex` stores
   into `rbag_buf[0]` without touching thread 0's `rput`, so at TPC >= 2
   thread 0 can never pop the root and the whole program always enters
   through a single-redex steal by the left neighbor. (TPC = 1 only works
   because a thread steals from itself.)
2. **The cursor parks in stolen holes.** A thief probes the victim's segment
   at its own cursor and resets the cursor to 0 on every miss. Stolen slots
   become permanent holes: the victim pops LIFO from the top, so a stack that
   never fully drains never re-arms its bottom slots. Once one thief carves a
   hole at slot 0, every other thief resets into the hole zone and probes a
   dead slot forever. `HVM_DIAG=3` shows runs with 11002 such misses against
   a victim whose `rput` sat up to 890 above the thief's cursor: hundreds of
   live redexes, unreachable.
3. **The stealable frontier is thin even when the net is wide.** At 99.9%+ of
   miss moments the victim's global rbag held <= 8 redexes; the steady-state
   work sits in the thread-local, non-atomic hbag (high-priority LINK/COMM/
   ERAS redexes, never deeper than ~20), which no thief can see. Only brief
   bursts (a 2299-deep stack draining in ~27 us) offer bulk.

The lottery follows: in migration-type runs ~47 steals distribute all 22.9M
interactions (one hit can carry an entire subtree), in wide runs ~4500 do.
Wall clock tracks whichever happened; the same binary alternates between
0.08s and 0.29s at 8 threads.

### The strategies (HVM_STEAL, all A/B'd interleaved, 15 rounds)

Every mode keeps results and ITRS bit-identical (confluence): 352 / 92 /
91400 and 22884287 / 4478739 / 2134946 at every thread count in every mode.

- `half` - a hit takes half of the victim's live run. Rejected: bulk
  exchanges serialize with the victim's own pops, several thieves at once
  spike contention on the victim's segment (4t median 0.17s, still 2x worse
  than the walk modes; the drain-steal precedent repeated).
- `boot` - makes the boot redex poppable by thread 0. Rejected: mixed (2t
  never reaches the fast path, 8t slightly better, no cell beats both base
  and the walk modes).
- `scan` - sweeps every victim per idle tick with reset cursors. No effect
  on its own (4t median 0.31s vs base 0.29s): the sweep still probes slot 0
  of hole-parked segments. This isolated the defect: victim selection was
  never the problem, the cursor policy was.
- `walk` - on a miss, read the victim's `rput` racily as a hint: if the stack
  top sits above the cursor, walk the cursor up (over the holes); reset only
  when the stack receded below the cursor. Wrong guesses self-correct on a
  later tick. This alone fixes 2t/4t/8t.
- `scancap` (shipped default) - walk + ring sweep + a bounded bulk take of
  up to 16 slots from the hit victim. Best or tied in every cell, and the
  only mode that collapses the variance at 8t.

Wall-clock medians (min..max) from the interleaved matrix
(`python3 tests/e2e/perf/ab_steal.py`, 15 rounds; raw data in
`docs/experiments/steal_ab_matrix.json`; machine load 2-6 during the run,
ghc jobs from the real-world line pass through intermittently - the rotation
gives every mode equal exposure):

nqueens9 (22,884,287 ITRS):

| thr | base | half | walk | scanwalk | scancap | boot |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | 0.298 | 0.304 | 0.312 | 0.313 | 0.311 | 0.304 |
| 2 | 0.344 (0.205..0.493) | 0.268 | **0.157** (0.150..0.178) | 0.154 | **0.155** (0.148..0.179) | 0.373 |
| 4 | 0.294 (0.094..0.470) | 0.174 | 0.090 (0.082..0.296) | 0.088 (0.083..0.121) | **0.082** (0.080..0.121) | 0.297 |
| 8 | 0.276 (0.113..0.322) | 0.269 | 0.089 (0.072..0.147) | 0.084 (0.064..0.112) | **0.066** (0.059..0.101) | 0.198 |

07_nqueens (4,478,739 ITRS, medium):

| thr | base | walk | scancap |
| ---: | --- | --- | --- |
| 1 | 0.061 | 0.061 | 0.060 |
| 2 | 0.072 | **0.034** | **0.034** |
| 4 | 0.063 | 0.022 | **0.021** (0.019..0.031) |
| 8 | 0.040 | 0.027 | **0.021** |

map300 (2,134,946 ITRS, spawn-dominated control):

| thr | base | walk | scancap |
| ---: | --- | --- | --- |
| 1 | 0.034 | 0.034 | 0.035 |
| 2 | 0.031 | **0.028** | 0.029 |
| 4 | 0.031 | **0.028** | 0.029 |
| 8 | 0.034 | **0.023** | 0.028 |

Nothing regresses. The confirmed runs (raw data in
`docs/experiments/steal_ab_confirm.json`, machine load 5-10, ghc -j8 from the
real-world line hammering cores throughout) compare the shipped default
against `HVM_STEAL=none`: nqueens9 8t 0.219s -> 0.099s median, 4t 0.304s ->
0.095s, 2t 0.309s -> 0.165s; every control cell flat or better.

### Defaults and what still limits the ceiling

`HVM_STEAL` unset ships `scancap`; `HVM_STEAL=none` restores the pristine
probe. 1t cost is within noise: min-of-15 at 1t is 0.285s (base) vs 0.283s
(walk) vs 0.285s (scancap) on nqueens9, and 0.0335 vs 0.0340 vs 0.0347 on
map300; the medians differ only by machine drift, the mins do not. The
steal path only runs when a thread's own bag is empty, so single-thread
evaluations pay one extra branch per idle event.

With the fix, nqueens9 reaches 4.7x at 8t (eval median 0.0598s vs the 1t
floor 0.281s; quiet-machine spot runs measured 0.062s wall, max = median over
6 runs) and 3.6x at 4t. The remaining gap to the 6P+2E hardware is bounded by
what the runtime cannot steal: the hbag-resident high-priority work. Making
the hbag stealable (atomic head/tail protocol) is the next structural step
and needs its own correctness review; everything cheap has been taken.
map300 stays spawn-bound (~3ms of thread setup against 25ms of evaluation)
and only gains from the fix incidentally.

## Physical ceiling on this machine

8 logical cores = 6 performance + 2 efficiency. Nothing in the measured runs
approached a hardware limit: the evaluator is single-socket memory-bound at
worst, and the pre-pass map300 8t run left six cores idle 60% of the time.
The honest statement is that the current ceiling is set by the runtime's
scheduler and the net's sequential spine, not by the chip. With the CAF pass
in place map300 is 2.1M ITRS / ~50ms single-thread, where thread spawn and
teardown (~3ms) dominate; meaningful parallel scaling on this input would
need a larger workload built the same way.

## GhcCompiler on HVM2: graph exhaustion, not slowness

`tests/packages/ghc/GhcCompiler.core` (54 KB Core, 1127 definitions) times
out on both HVM2 backends (Rust interpreter and compiled C) at 120s, while
the HVM3 interpreter finishes it in 0.23s / 970,205 interactions. This is
confirmed current on this branch (not a stale row), and predates the
middle-end changes: with the compiler at 9b08bbc the run behaves identically.

The compiled C run floods stdout with `OOM` —
`node_alloc` wrapped its whole segment (`G_NODE_LEN/TPC` = 67M node slots per
thread at 8 threads) and retries forever. The net for this program exceeds
the 536M-node global buffer: HVM2's demand-blind expansion materializes the
whole intermediate graph, while HVM3's demand-driven evaluation only builds
what the result needs. This is a lowering-encoding/runtime problem owned by
another line; recording it here so no one re-bisects it against the
middle-end passes.

## Real-world suite status on this branch

`python3 tests/e2e/real_world/run.py` is red on `perf/track` at 9b08bbc and
on this branch's HEAD, in the same places and for the same reasons:

- `bytestring_core`: GHC 9.14 cannot parse bytestring-0.12.2.0's FFI section
  (native build fails before Coronet runs).
- `containers_map_fold`, `map_core`, `ghc_compiler`, `raytracer`: the linked
  Core needs definitions no module defines (`$fOrdInt`, `div`, `mod`,
  `negate`, ...), i.e. the plugin/linker gap, then RUN-FAIL.

Verified not caused by the middle-end: re-running the `map_core` case with
the 9b08bbc compiler fails identically. These belong to the real-world line
(`tests/e2e/real_world/**`, `frontend/**` are outside this branch's write
scope).
