# SPDX-License-Identifier: GPL-2.0-or-later
# Licence of the program it tests (klick).
# A fake JackMoebius daemon for the tests: it listens on a Unix socket and answers the command "apps" with a list of applications
# (one JSON line in, one JSON line out, then it closes), as the real daemon does. The client "jack_capture" is made to stand for
# Terminal, so that a test can see an icon come from the daemon.
# Usage: python3 -I fake_moebius.py <socket path>
import json, os, socket, sys

path = sys.argv[1]
if os.path.exists(path):
    os.unlink(path)
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(8)
APPS = [
    {"key": "com.apple.Terminal", "name": "jack_capture", "pid": 1},
    {"key": "path:/opt/tool/bin/tool", "name": "tool", "pid": 2},
]
while True:
    connection, _ = server.accept()
    with connection:
        data = b""
        while not data.endswith(b"\n"):
            chunk = connection.recv(4096)
            if not chunk:
                break
            data += chunk
        try:
            command = json.loads(data.decode()).get("command")
        except ValueError:
            command = None
        reply = {"status": "ok", "data": APPS} if command == "apps" else {"status": "error"}
        connection.sendall((json.dumps(reply) + "\n").encode())
