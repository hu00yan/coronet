# Concurrency, MVars, actors, and GC

Coronet lowers GHC's concurrency primops to HVM nets. HVM is a graph-rewriting
runtime with immutable state snapshots; it is not a GHC RTS replacement.

## What is real

- `fork#` on the default path starts an independent redex. Pure work runs on the
  HVM scheduler in parallel. There is no shared mutable heap across the fork
  boundary.
- Pure `par#`/`spark#` are routed through `Coronet_par`, which preserves the
  `par#` result while leaving the spark as ordinary lazy work.

## Cooperative mode (`coronet-opt --sched`)

`--sched` replaces `fork#`/`forkOn#` with `Coronet_fork`, which runs the child
action eagerly and commits the child's state pair. This gives a deterministic
single-thread scheduler for `fork#`, `yield#`, `myThreadId#`, and the MVar
protocol. It is what makes `fork#` + `putMVar#` visible to the parent in one
thread.

Actors are a thin layer over that protocol:

```
Coronet_actor_spawn body init
Coronet_actor_take addr
Coronet_actor_put addr value
```

They are cooperative, not preemptive, and do not provide a shared mailbox
across HVM's native snapshot forks.

## What is not supported

- A transparent shared `MVar` across native `fork#`: parent and child have
  independent persistent `entries` maps. Exact shared mutation needs a runtime
  shared cell with atomic operations and wait/notify.
- GHC's lightweight-thread RTS: timer/`threadDelay`, preemption, async
  exceptions, masking, bound threads, and a global run queue are absent.
- Tracing GC: HVM reclaims unreachable net nodes, but there is no heap root set
  for weak pointers, finalizers, stable names, or compact regions.
  `mkWeak#`, `deRefWeak#`, `finalizeWeak#`, stable pointers, compact primops,
  and thread allocation counters are rejected by `coronet-opt` rather than
  silently emulated.
