#!/usr/bin/env bash
set -euo pipefail

# Coronet: Haskell to GHC CoreLite Extraction Script
# Usage: ./frontend/extract_core.sh [--plugin] <input.hs> [output.core]

USE_PLUGIN=0
if [ "${1:-}" = "--plugin" ]; then
    USE_PLUGIN=1
    shift
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 [--plugin] <input.hs> [output.core]" >&2
    exit 1
fi

INPUT_HS="$1"
if [ ! -f "$INPUT_HS" ]; then
    echo "Error: input file '$INPUT_HS' not found." >&2
    exit 1
fi

OUTPUT_CORE="${2:-}"

command -v ghc >/dev/null 2>&1 || {
    echo "Error: ghc is required but not found in PATH." >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d -t coronet_ghc_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLEAN_CORE="$TMP_DIR/clean.core"

if [ "$USE_PLUGIN" -eq 1 ]; then
    # Mode A: Native GHC Plugin extraction (CoronetPlugin)
    # Ensure plugin is built
    if [ ! -f "$SCRIPT_DIR/CoronetPlugin.o" ] || [ ! -f "$SCRIPT_DIR/CoronetPlugin.dyn_o" ]; then
        ghc -package ghc -dynamic-too -c "$SCRIPT_DIR/CoronetPlugin.hs" -outputdir "$TMP_DIR"
        cp "$TMP_DIR/CoronetPlugin.o" "$SCRIPT_DIR/CoronetPlugin.o" 2>/dev/null || true
        cp "$TMP_DIR/CoronetPlugin.dyn_o" "$SCRIPT_DIR/CoronetPlugin.dyn_o" 2>/dev/null || true
        cp "$TMP_DIR/CoronetPlugin.hi" "$SCRIPT_DIR/CoronetPlugin.hi" 2>/dev/null || true
        cp "$TMP_DIR/CoronetPlugin.dyn_hi" "$SCRIPT_DIR/CoronetPlugin.dyn_hi" 2>/dev/null || true
    fi

    ghc -c -O \
        -package ghc \
        -fplugin=CoronetPlugin \
        "-fplugin-opt=CoronetPlugin:out=$CLEAN_CORE" \
        -i"$SCRIPT_DIR" \
        -fforce-recomp \
        "$INPUT_HS" || {
        echo "Error: GHC compilation with CoronetPlugin failed for $INPUT_HS" >&2
        exit 1
    }
    # Clean up compilation artifacts in source directory
    IN_DIR="$(dirname "$INPUT_HS")"
    IN_BASE="$(basename "$INPUT_HS" .hs)"
    rm -f "$IN_DIR/$IN_BASE.o" "$IN_DIR/$IN_BASE.hi" "$IN_DIR/$IN_BASE.dyn_o" "$IN_DIR/$IN_BASE.dyn_hi" 2>/dev/null || true
else
    # Mode B: Standard GHC 9.14 dump simpl with post-processing filter
    RAW_DUMP="$TMP_DIR/raw.dump"
    ghc -c -O \
        -ddump-simpl \
        -dsuppress-all \
        -dsuppress-uniques \
        -dsuppress-module-prefixes \
        -dsuppress-idinfo \
        -dsuppress-type-signatures \
        -dsuppress-type-applications \
        -dsuppress-coercions \
        -dsuppress-var-kinds \
        -dno-typeable-binds \
        -outputdir "$TMP_DIR" \
        -fforce-recomp \
        "$INPUT_HS" > "$RAW_DUMP" 2>&1 || {
        echo "Error: GHC compilation failed for $INPUT_HS:" >&2
        cat "$RAW_DUMP" >&2
        exit 1
    }

    python3 - "$RAW_DUMP" "$CLEAN_CORE" << 'EOF'
import sys
import re

raw_file = sys.argv[1]
out_file = sys.argv[2]

with open(raw_file, "r", encoding="utf-8") as f:
    raw_text = f.read()

lines = raw_text.splitlines()

start_idx = 0
found_tidy = False
for i, line in enumerate(lines):
    if "==================== Tidy Core ====================" in line:
        start_idx = i + 1
        found_tidy = True
        break

if not found_tidy:
    start_idx = 0

lines = lines[start_idx:]

filtered = []
for line in lines:
    stripped = line.strip()
    if "Result size of Tidy Core" in line:
        continue
    if stripped.startswith("= {terms:") or (stripped.startswith("{terms:") and "types:" in stripped):
        continue
    filtered.append(line)

raw_lines = filtered
cleaned_lines = []
has_result = any(re.match(r'^result\s*=', l.strip()) for l in raw_lines)

i = 0
while i < len(raw_lines):
    line = raw_lines[i]
    stripped = line.strip()

    if re.match(r'^\$(trModule|tc|krep)', stripped):
        i += 1
        while i < len(raw_lines):
            nxt = raw_lines[i].strip()
            if nxt == "":
                break
            if re.match(r'^[a-zA-Z0-9_\$]+\s*=', nxt) or nxt.startswith("Rec {"):
                break
            i += 1
        continue

    if has_result and re.match(r'^main[0-9]*\s*=', stripped):
        i += 1
        while i < len(raw_lines):
            nxt = raw_lines[i].strip()
            if nxt == "":
                break
            if re.match(r'^[a-zA-Z0-9_\$]+\s*=', nxt) or nxt.startswith("Rec {"):
                break
            i += 1
        continue

    cleaned_lines.append(line)
    i += 1

text = "\n".join(cleaned_lines)

if has_result:
    text = text.rstrip() + "\n\nmain = result\n"

def clean_lambda(match):
    prefix = match.group(1)
    args_str = match.group(2)
    arrow = match.group(3)
    args = args_str.split()
    term_args = [a for a in args if not a.startswith('@')]
    if not term_args:
        return ""
    return f"{prefix}{' '.join(term_args)} {arrow}"

text = re.sub(r'(\\)\s+((?:@[a-zA-Z0-9_]+\s*)+[a-zA-Z0-9_\s]*)(->)', clean_lambda, text)
text = re.sub(r'\\\s*@[a-zA-Z0-9_]+\s*->\s*', '', text)
text = re.sub(r'\\([a-zA-Z0-9_])', r'\\ \1', text)

text = text.replace("$fNumInt_$c+", "+")
text = text.replace("$fNumInt_$c-", "-")
text = text.replace("$fNumInt_$c*", "*")

output_lines = []
for l in text.splitlines():
    output_lines.append(l.rstrip())

final_lines = []
blank_count = 0
for l in output_lines:
    if l == "":
        blank_count += 1
        if blank_count <= 1:
            final_lines.append(l)
    else:
        blank_count = 0
        final_lines.append(l)

final_text = "\n".join(final_lines).strip() + "\n"

with open(out_file, "w", encoding="utf-8") as f:
    f.write(final_text)
EOF
fi

if [ -n "$OUTPUT_CORE" ]; then
    mkdir -p "$(dirname "$OUTPUT_CORE")"
    cp "$CLEAN_CORE" "$OUTPUT_CORE"
else
    cat "$CLEAN_CORE"
fi
