#!/usr/bin/env bash
# Regression checks for the CoreLite semantic plugin (cmd/opt).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

opt_hvm3() { # extra flags...
  moon run cmd/opt -- "$tmp/in.core" -o "$tmp/opt.core" --target hvm3 "$@" >/dev/null
  moon run cmd/main -- "$tmp/opt.core" --target hvm3 -o "$tmp/out.hvm3" >/dev/null
}

expect() { # label, expected
  got=$(./scripts/run_hvm3.sh "$tmp/out.hvm3" 2>&1 | head -1)
  if [ "$got" != "$2" ]; then
    echo "FAIL: expected '$2', got '$got' ($1)" >&2
    exit 1
  fi
  echo "ok: $1 -> $got"
}

run_hvm3() { opt_hvm3; expect "$1" "$2"; }

cat > "$tmp/in.core" <<'CORE'
result = Coronet_f2i (plusFloat# 1.5## 2.25##)
main = result
CORE
run_hvm3 "float add" "3"

cat > "$tmp/in.core" <<'CORE'
result = Coronet_f2i (sqrtFloat# 16.0##)
main = result
CORE
run_hvm3 "float sqrt" "4"

cat > "$tmp/in.core" <<'CORE'
result = Coronet_f2i (timesFloat# 1.5## 2.25##)
main = result
CORE
run_hvm3 "float mul" "3"

cat > "$tmp/in.core" <<'CORE'
result = Coronet_f2i (expFloat# 0.0##)
main = result
CORE
run_hvm3 "float exp" "1"

cat > "$tmp/in.core" <<'CORE'
result = gtFloat# (logFloat# 2.0##) 0.69##
main = result
CORE
run_hvm3 "float log" "1"

cat > "$tmp/in.core" <<'CORE'
result = ltFloat# (sinFloat# 1.0##) 0.85##
main = result
CORE
run_hvm3 "float sin" "1"

cat > "$tmp/in.core" <<'CORE'
result = gtFloat# (cosFloat# 1.0##) 0.54##
main = result
CORE
run_hvm3 "float cos" "1"

cat > "$tmp/in.core" <<'CORE'
result = float2Int# (powerFloat# 2.0## 3.0##)
main = result
CORE
run_hvm3 "float pow" "8"

cat > "$tmp/in.core" <<'CORE'
result = btoint (bmul (bfromint 12345#) (bfromint 6789#))
main = result
CORE
moon run cmd/opt -- "$tmp/in.core" --bigint -o "$tmp/opt.core" --target hvm3 >/dev/null
moon run cmd/main -- "$tmp/opt.core" --target hvm3 -o "$tmp/out.hvm3" >/dev/null
expect "bigint mul" "83810205"

cat > "$tmp/in.core" <<'CORE'
result = frobnicateFloat# 1.0##
main = result
CORE
if moon run cmd/opt -- "$tmp/in.core" -o "$tmp/opt.core" --target hvm3 2>&1 | grep -q "unsupported float primops"; then
  echo "ok: unsupported float is loud"
else
  echo "FAIL: unsupported float was not rejected" >&2
  exit 1
fi

run_bigrat() {
  moon run cmd/opt -- "$tmp/in.core" --bigrat -o "$tmp/opt.core" --target hvm3 >/dev/null
  moon run cmd/main -- "$tmp/opt.core" --target hvm3 -o "$tmp/out.hvm3" >/dev/null
  expect "bigrat $1" "$2"
}

cat > "$tmp/in.core" <<'CORE'
result = float2Int# (plusFloat# 1.5## 2.25##)
main = result
CORE
run_bigrat "exact add" "3"

cat > "$tmp/in.core" <<'CORE'
result = float2Int# (timesFloat# 1.5## 2.25##)
main = result
CORE
run_bigrat "exact mul" "3"

cat > "$tmp/in.core" <<'CORE'
result = eqFloat# (plusFloat# 1.5## 2.25##) 3.75##
main = result
CORE
run_bigrat "exact compare" "1"

cat > "$tmp/in.core" <<'CORE'
result = eqFloat# (plusFloat# 0.1234## 0.0001##) 0.1235##
main = result
CORE
run_bigrat "decimal literal precision" "1"

cat > "$tmp/in.core" <<'CORE'
result = float2Int# (sqrtFloat# 2.25##)
main = result
CORE
run_bigrat "sqrt" "1"

cat > "$tmp/in.core" <<'CORE'
result = float2Int# (powerFloat# 2.0## 3.0##)
main = result
CORE
run_bigrat "pow" "8"

# Exceptions: catch# is routed through the HVM3 catchSTM state machine.
cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case catch# (\ s -> raiseIO# 42# s) (\ e -> \ s -> (# s, 99# #)) s0 of { (# s1, v #) -> v })
main = result
CORE
run_hvm3 "catch# / raiseIO#" "99"

# --mid: the same CAF/rebuild optimizer as the compiler, as an external pass.
cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case newArray# 3# 0# s0 of { (# s1, a #) -> case writeArray# a 1# 42# s1 of { s2 -> case readArray# a 1# s2 of { (# s3, v #) -> v } } })
main = result
CORE
run_hvm3 "array new/write/read" "42"

cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case newArray# 3# 0# s0 of { (# s1, a #) -> case setArray# a 0# 3# 7# s1 of { s2 -> case readArray# a 2# s2 of { (# s3, v #) -> v } } })
main = result
CORE
run_hvm3 "array set" "7"

cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case newArray# 4# 0# s0 of { (# s1, a #) -> case writeArray# a 0# 5# s1 of { s2 -> case writeArray# a 1# 6# s2 of { s3 -> case copyArray# a 0# a 2# 2# s3 of { s4 -> case readArray# a 3# s4 of { (# s5, v #) -> v } } } } })
main = result
CORE
run_hvm3 "array copy" "6"

cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case fork# (\ s -> (# s, 7# #)) s0 of { (# s1, tid #) -> tid })
main = result
CORE
opt_hvm3 --sched
expect "cooperative fork" "0"

cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case newMVar# 0# s0 of { (# s1, mv #) -> case fork# (\ s -> case putMVar# mv 42# s of { s2 -> case readMVar# mv s2 of { (# s3, v #) -> (# s3, v #) } }) s1 of { (# s2, tid #) -> case takeMVar# mv s2 of { (# s3, v #) -> v } } })
main = result
CORE
opt_hvm3 --sched
expect "cooperative fork + MVar" "42"

cat > "$tmp/in.core" <<'CORE'
result = runRW# (\ s0 -> case Coronet_actor_spawn (\ box s -> case takeMVar# box s of { (# s1, msg #) -> case putMVar# box (+# msg 1#) s1 of { s2 -> (# s2, 0# #) } }) 41# s0 of { (# s1, addr #) -> case Coronet_actor_take addr s1 of { (# s2, v #) -> v } })
main = result
CORE
opt_hvm3 --sched
expect "cooperative actor" "42"

cat > "$tmp/in.core" <<'CORE'
result = mkWeak# 1# 2# 3#
main = result
CORE
if moon run cmd/opt -- "$tmp/in.core" -o "$tmp/opt.core" --target hvm3 2>&1 | grep -q "GC/weak/compact"; then
  echo "ok: GC/weak is loud"
else
  echo "FAIL: GC/weak primop was not rejected" >&2
  exit 1
fi

moon run cmd/opt -- tests/packages/map_core.core --mid -o "$tmp/map.mid.core" --target hvm3 >/dev/null
moon run cmd/main -- "$tmp/map.mid.core" --target hvm3 -o "$tmp/out.hvm3" >/dev/null
expect "mid CAF on map_core" "10570"

echo "core plugin: all checks passed"
