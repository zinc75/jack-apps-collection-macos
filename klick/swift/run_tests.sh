#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program it tests (klick).
# Runs the tests of the JACK module, those that need a server included, on a JACK server of its own ("kltest", dummy driver, 48000 Hz,
# blocks of 512): the server in use is never touched. Build klick/engine/build_jack.sh first.
# Usage: run_tests.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
server=kltest
log=$(mktemp -t kltest_jackd)
sock=$(mktemp -u -t kltest_moebius).sock
trap 'pkill -f "jackd -n $server " 2>/dev/null; pkill -f "fake_moebius.py $sock" 2>/dev/null; pkill -9 -f "jack_capture -c 2 -d 60" 2>/dev/null; rm -f "$log" "$sock"' EXIT
for tool in jackd jack_lsp; do command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 2; }; done
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
JACK_DEFAULT_SERVER=$server jackd -n $server -d dummy -r 48000 -p 512 >"$log" 2>&1 &
sleep 3
export JACK_DEFAULT_SERVER=$server KLICK_TEST_JACK=1
jack_lsp >/dev/null 2>&1 || { echo "error: the test server did not start"; cat "$log"; exit 2; }
# Another client with input ports (jack_capture), and a fake JackMoebius daemon that says it stands for an application.
capture=${JACK_CAPTURE:-$(command -v jack_capture || true)}
if [ -n "$capture" ]; then
  "$capture" -c 2 -d 60 "$(mktemp -u -t kltest_capture).wav" >/dev/null 2>&1 &
  export KLICK_TEST_JACK_OTHER=jack_capture
fi
python3 -I "$here/tests/fake_moebius.py" "$sock" &
export JACKAPPS_MOEBIUS_SOCKET=$sock
sleep 1
cd "$here" && swift test
