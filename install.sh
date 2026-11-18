#!/usr/bin/env bash
set -euo pipefail

# Installer for Coronet
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"

echo "==> Building Coronet native release binary..."
moon build --target native --release

mkdir -p "$BINDIR"
cp _build/native/release/build/cmd/main/main.exe "$BINDIR/coronet"
chmod +x "$BINDIR/coronet"

echo "==> Installed Coronet to $BINDIR/coronet"
if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
  echo "==> Note: Please add $BINDIR to your PATH in ~/.zshrc or ~/.bashrc:"
  echo "    export PATH=\"$BINDIR:\$PATH\""
fi
