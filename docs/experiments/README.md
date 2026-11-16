Vendor worktree state on perf/track, relative to the recorded submodule commits
(HVM2 6542760, HVM3 fba2e9c). These directories carry no .git in this
checkout, so git status cannot show them; this file is the auditable record.
Apply with: cd vendor/HVM2 && patch -p1 < ../../docs/experiments/vendor_worktree.patch
(after stripping the HVM3 half; the HVM3 half applies from vendor/HVM3).

HVM2: hvm.c CORONET-DIAG counters + HVM_TPC_L2 override in build.rs
(measurement only, inert without HVM_DIAG), and hvm.rs def.safe guard
restored to match the C runtime. HVM3: cabal dep relaxation for GHC 9.14 and
the Runtime.c ref includes, mirroring the main checkout worktree.
