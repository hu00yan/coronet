#!/usr/bin/env bash
set -euo pipefail

# scripts/run_hvm3.sh - Helper script to run HVM3 programs
# Usage:
#   ./scripts/run_hvm3.sh <file.hvm> [flags...]
#   ./scripts/run_hvm3.sh <subcommand> <file.hvm> [flags...]
# Subcommands: run (default), serve, help
# Flags:
#   -c   Run with compiled C mode (fast)
#   -C   Collapse result to a lambda-term / value (enabled by default)
#   -CN  Collapse and show first N results
#   -s   Show execution statistics
#   -d   Debug mode (print evaluation steps)
#   -Q   Hide quotes in output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve HVM3 binary
HVM3_BIN="${HVM3_BIN:-}"
if [[ -z "$HVM3_BIN" || ! -x "$HVM3_BIN" ]]; then
  COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  PARENT_REPO="$(cd "$COMMON_DIR/.." 2>/dev/null && pwd || true)"
  SEARCH_DIRS=()
  if [[ -d "$REPO_ROOT/vendor/HVM3/dist-newstyle" ]]; then
    SEARCH_DIRS+=("$REPO_ROOT/vendor/HVM3/dist-newstyle")
  fi
  if [[ -n "$PARENT_REPO" && -d "$PARENT_REPO/vendor/HVM3/dist-newstyle" ]]; then
    SEARCH_DIRS+=("$PARENT_REPO/vendor/HVM3/dist-newstyle")
  fi
  if [[ ${#SEARCH_DIRS[@]} -gt 0 ]]; then
    CANDIDATE="$(find "${SEARCH_DIRS[@]}" -type f -name "hvm" -perm +111 2>/dev/null | head -n 1 || true)"
    if [[ -n "$CANDIDATE" && -x "$CANDIDATE" ]]; then
      HVM3_BIN="$CANDIDATE"
    fi
  fi
fi

if [[ -z "$HVM3_BIN" || ! -x "$HVM3_BIN" ]]; then
  echo "Error: HVM3 binary not found. Build it with: (cd vendor/HVM3 && cabal build)" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [run|serve|help] <file.hvm> [flags...]" >&2
  echo "Flags: -c (compiled mode), -C (collapse), -s (statistics), -d (debug), -Q" >&2
  exit 1
fi

SUBCOMMAND="run"
case "$1" in
  run|serve|help)
    SUBCOMMAND="$1"
    shift
    ;;
esac

if [[ "$SUBCOMMAND" == "help" ]]; then
  exec "$HVM3_BIN" help
fi

# Separate file path and flags/options
FILE=""
FLAGS=()
HAS_COLLAPSE_FLAG=false

for arg in "$@"; do
  if [[ "$arg" =~ ^-C ]]; then
    HAS_COLLAPSE_FLAG=true
    FLAGS+=("$arg")
  elif [[ "$arg" =~ ^- ]]; then
    FLAGS+=("$arg")
  elif [[ -z "$FILE" ]]; then
    FILE="$arg"
  else
    FLAGS+=("$arg")
  fi
done

if [[ -z "$FILE" ]]; then
  echo "Error: No file specified." >&2
  echo "Usage: $0 [run|serve|help] <file.hvm> [flags...]" >&2
  exit 1
fi

# Default to collapse mode (-C) for clean normal form output unless caller explicitly opted out
if [[ "$HAS_COLLAPSE_FLAG" == false ]]; then
  FLAGS+=("-C")
fi

# HVM3 expects: <binary> <subcommand> <file> [flags...]
exec "$HVM3_BIN" "$SUBCOMMAND" "$FILE" "${FLAGS[@]}"
