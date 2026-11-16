# Performance baseline: what limits ITRS and multi-core speedup

Reproduce every number here with:

```
python3 tests/e2e/perf/perf_baseline.py            # the full table
python3 tests/e2e/perf/perf_baseline.py --only map300 --json /tmp/m.json
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

The patch touches no behavior when the variable is unset, and the drain-steal
experiment below was reverted from the same file. Vendor changes stay in the
worktree by policy and are listed here for review.

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

For nqueens9 the net shape is wide (thousands of independent subtrees), so
its non-monotonic baseline curve (2t=1.24x, 4t=0.99x, 8t=4.05x) is pure
scheduler lottery: per-thread runs alternate between one thread taking
22.8M of 22.9M and near-even splits, and the min-of-5 protocol lands on
whichever distribution happened to occur. Same protocol, same binary,
8t runs observed at 0.08s and 0.29s.

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
