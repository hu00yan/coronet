#!/usr/bin/env bash
set -euo pipefail

# scripts/run_metal.sh - Coronet Apple Silicon Metal GPU Runner
# Usage:
#   ./scripts/run_metal.sh [--workload <name>] [-r <resolution>] [--json]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$REPO_ROOT/bin"
METAL_SRC="$REPO_ROOT/runtime/metal/coronet_metal.m"
SHADER_SRC="$REPO_ROOT/runtime/metal/coronet_metal.metal"
BIN_TARGET="$BIN_DIR/coronet_metal"

mkdir -p "$BIN_DIR"

# Compile host harness if binary doesn't exist or source is newer
if [[ ! -x "$BIN_TARGET" ]] || [[ "$METAL_SRC" -nt "$BIN_TARGET" ]]; then
  echo "--> Compiling Coronet Metal GPU runtime for Apple Silicon..."
  clang -O3 -fobjc-arc \
    -framework Metal \
    -framework Foundation \
    "$METAL_SRC" \
    -o "$BIN_TARGET"
fi

# Execute on Apple Silicon GPU
exec "$BIN_TARGET" --shader "$SHADER_SRC" "$@"
