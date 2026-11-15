#!/usr/bin/env bash
set -euo pipefail

# scripts/run_colab_gpu.sh - Execute HVM2 / CUDA programs on remote Google Colab GPU
# Usage:
#   ./scripts/run_colab_gpu.sh <file.hvm|file.cu> [options...]
# Options:
#   --gpu <T4|L4|A100>    (default: T4)
#   --timeout <seconds>   (default: 300)
#   --nvcc-opt <-O3>      (default: -O3)
#   --json                (output parsed metrics as JSON)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <file.hvm|file.cu> [--gpu T4] [--timeout 300] [--json]" >&2
  exit 1
fi

PYTHON_BIN="$(which python3)"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Error: python3 not found." >&2
  exit 1
fi

COLAB_CLI="${COLAB_CLI_PATH:-/Users/huyan00/.local/bin/colab}"
if [[ ! -x "$COLAB_CLI" ]]; then
  echo "Error: colab CLI not found at $COLAB_CLI" >&2
  exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/colab_runner.py" "$@"
