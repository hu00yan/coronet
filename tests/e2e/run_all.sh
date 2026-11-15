#!/usr/bin/env bash
set -euo pipefail

# Coronet End-to-End Test Suite Runner
# Usage: ./tests/e2e/run_all.sh [--target hvm2|hvm3|all] [--fixtures <dir>] [--filter <pattern>] [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Coronet End-to-End Verification Pipeline ==="
echo "Repo root: $REPO_ROOT"

# Check required toolchains
command -v moon >/dev/null 2>&1 || { echo >&2 "Error: 'moon' is not installed or not in PATH"; exit 1; }
command -v runghc >/dev/null 2>&1 || { echo >&2 "Error: 'runghc' is not installed or not in PATH"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo >&2 "Error: 'python3' is not installed or not in PATH"; exit 1; }

# Make scripts executable if present
chmod +x "$SCRIPT_DIR/verify.py" 2>/dev/null || true
if [[ -f "$REPO_ROOT/frontend/extract_core.sh" ]]; then
    chmod +x "$REPO_ROOT/frontend/extract_core.sh" 2>/dev/null || true
fi
if [[ -f "$REPO_ROOT/scripts/run_hvm2.sh" ]]; then
    chmod +x "$REPO_ROOT/scripts/run_hvm2.sh" 2>/dev/null || true
fi
if [[ -f "$REPO_ROOT/scripts/run_hvm3.sh" ]]; then
    chmod +x "$REPO_ROOT/scripts/run_hvm3.sh" 2>/dev/null || true
fi

# Run python harness
python3 "$SCRIPT_DIR/verify.py" "$@"
