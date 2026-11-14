#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program it tests (klick).
# Runs the test of the JACK backend on a JACK server of its own ("kltest", dummy driver: it never touches the server in use, which has
# another name), on each architecture, then records the clicks of the engine with jack_capture and checks their spacing.
# Needs JACK installed (jackd, jack_lsp) and a jack_capture. Run build_jack.sh first.
# Usage: run_jack_tests.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
build=$here/../../build
samples=$here/../../klick-tempo/klick/build/samples
capture=${JACK_CAPTURE:-$(command -v jack_capture || true)}
server=kltest
rate=48000
block=512
fail=0

for tool in jackd jack_lsp; do command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 2; }; done
[ -n "$capture" ] || { echo "error: jack_capture not found" >&2; exit 2; }
[ -d "$samples" ] || { echo "error: $samples is missing (klick-tempo/klick/build_universal.sh)" >&2; exit 2; }

log=$(mktemp -t kltest_jackd)
trap 'pkill -f "jackd -n $server " 2>/dev/null; rm -f "$log"' EXIT

echo "== without a server: the backend refuses and no server is started"
for arch in arm64 x86_64; do
  JACK_DEFAULT_SERVER=kltest_absent "$build/tests/jack_backend_test_$arch" --no-server || fail=1
done
if pgrep -f "jackd.*kltest_absent" >/dev/null; then echo "FAIL: a server was started"; fail=1; pkill -f "jackd.*kltest_absent"; fi

echo "== with a server ($server, dummy driver, $rate Hz, blocks of $block)"
JACK_DEFAULT_SERVER=$server jackd -n $server -d dummy -r $rate -p $block >"$log" 2>&1 &
sleep 3
export JACK_DEFAULT_SERVER=$server
jack_lsp >/dev/null 2>&1 || { echo "error: the test server did not start"; cat "$log"; exit 2; }
for arch in arm64 x86_64; do
  echo "-- $arch"
  "$build/tests/jack_backend_test_$arch" "$samples" $rate $block || fail=1
  if jack_lsp | grep -q "Klick-test"; then echo "FAIL: the client is still in the server"; fail=1; fi
done

echo "== the clicks, recorded"
wav=$(mktemp -t kltest_capture).wav
# (the test checks the transport first, then says "playing on" and plays for 14 more seconds: the recording is made in that part)
out=$(mktemp -t kltest_out)
"$build/tests/jack_backend_test_arm64" "$samples" $rate $block --play 14 >"$out" &
test_pid=$!
for _ in $(seq 1 120); do grep -q "playing on" "$out" && break; sleep 0.5; done
sleep 2
"$capture" -c 1 -p "Klick-test:out" -d 3 --bitdepth 24 "$wav" >/dev/null 2>&1
wait $test_pid || { fail=1; cat "$out"; }
rm -f "$out"
python3 -I - "$wav" <<'PY' || fail=1
import sys, wave
import numpy as np
w = wave.open(sys.argv[1]); n = w.getnframes(); sw = w.getsampwidth(); sr = w.getframerate()
b = np.frombuffer(w.readframes(n), dtype=np.uint8).reshape(-1, sw)
x = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
x = np.where(x >= 1 << 23, x - (1 << 24), x) / float(1 << 23)
idx = np.where(np.abs(x) > 0.02)[0]
starts = [idx[0]] + [idx[i] for i in range(1, len(idx)) if idx[i] - idx[i - 1] > sr // 10] if len(idx) else []
gaps = sorted(set(np.diff(starts).tolist()))
print("recorded %.1f s: %d clicks, spacings %s frames (expected %d)" % (n / sr, len(starts), gaps, sr // 2))
ok = len(starts) >= 5 and gaps == [sr // 2]
print("clicks ok" if ok else "FAIL: the clicks are not regular")
sys.exit(0 if ok else 1)
PY
rm -f "$wav"

if [ $fail -eq 0 ]; then echo "ALL PASSED"; else echo "SOME FAILED"; fi
exit $fail
