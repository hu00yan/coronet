Vendor worktree state on perf/track (17906ff) and perf/track2, relative to the
recorded submodule commits (HVM2 6542760, HVM3 fba2e9c). These directories
carry no .git in this checkout, so git status cannot show them; these files
are the auditable record. Each patch is a plain `diff -ruN` of the named
files against a pristine clone of the recorded submodule commit; review it
rather than blind-applying (the embedded paths name the clone and the vendor
tree, so `patch -p1` needs the right cwd per file).

- `vendor_worktree.patch` - state up to the CAF-sharing unit: hvm.c
  CORONET-DIAG counters + HVM_TPC_L2 override in build.rs (measurement only,
  inert without HVM_DIAG), and the hvm.rs def.safe guard restored to match
  the C runtime. Superseded by `steal_worktree.patch`, kept for history.
- `steal_worktree.patch` - perf/track2 state: everything above plus the
  CORONET-STEAL strategies in hvm.c (HVM_STEAL; unset ships `scancap`,
  `none` restores the pristine probe) and the HVM_DIAG=3 steal counters.
  Mechanism and measurements: docs/PERF_BASELINE.md scheduling section;
  raw A/B data in `steal_ab_matrix.json`, `steal_ab_confirm.json`,
  `steal_diag2_bimodal.json`.

HVM3: cabal dep relaxation for GHC 9.14 and the Runtime.c ref includes,
mirroring the main checkout worktree.
