#!/usr/bin/env bash
set -euo pipefail

# scripts/run_hvm2.sh - Helper script to run HVM2 programs
# Usage:
#   ./scripts/run_hvm2.sh <file.hvm> [options...]
#   ./scripts/run_hvm2.sh <mode> <file.hvm> [options...]
# Modes: run (default, Rust interpreter), run-c (C runtime), run-cu (CUDA runtime), gen-c, gen-cu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -z "${HVM2_BIN:-}" ]]; then
  if [[ -x "$REPO_ROOT/vendor/HVM2/target/release/hvm" ]]; then
    HVM2_BIN="$REPO_ROOT/vendor/HVM2/target/release/hvm"
  elif [[ -x "$REPO_ROOT/vendor/HVM2/hvm" ]]; then
    HVM2_BIN="$REPO_ROOT/vendor/HVM2/hvm"
  else
    HVM2_BIN="$REPO_ROOT/vendor/HVM2/target/release/hvm"
  fi
fi

if [[ ! -x "$HVM2_BIN" ]]; then
  echo "Error: HVM2 binary not found or not executable at: $HVM2_BIN" >&2
  echo "Please check vendor/HVM2/target/release/hvm or build HVM2 with cargo build --release." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [mode] <file.hvm> [args...]" >&2
  echo "Modes: run (default), run-c, run-cu, gen-c, gen-cu" >&2
  exit 1
fi

MODE="run"
case "$1" in
  run|run-c|run-cu|gen-c|gen-cu)
    MODE="$1"
    shift
    ;;
esac

"$HVM2_BIN" "$MODE" "$@" | python3 -c '
import sys, re
for line in sys.stdin:
    m = re.match(r"^Result: \((\d+) (\d+)\)$", line)
    if m:
        hi = int(m.group(1))
        lo = int(m.group(2))
        val = (hi << 24) + lo
        print(f"Result: {val}")
    else:
        sys.stdout.write(line)
'
