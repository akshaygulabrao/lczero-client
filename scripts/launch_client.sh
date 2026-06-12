#!/usr/bin/env bash
# Foreground tab of the chessckers fleet: build + run a self-play CLIENT against
# the tailnet server. Ctrl-C stops it; logs stream in-tab. Needs the
# akshay-chessckers-0 engine binary (built from the engine repo).
#
# Env overrides: SERVER, ENGINE, CC_USER, CC_PASS, RUN.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVER="${SERVER:-http://localhost:9830}"
ENGINE="${ENGINE:-/Users/ox/AAworkspace/chessckers/akshay-chessckers-0/build/release/akshay-chessckers-0}"
CC_USER="${CC_USER:-$(whoami)}"
CC_PASS="${CC_PASS:-chessckers}"
RUN="${RUN:-1}"

echo "[client] building..."
go build -o akshay-chessckers-client .
# The client invokes an engine named "akshay-chessckers-0" found in CWD (then
# PATH); symlink the real binary here so it is picked up.
if [ -x "$ENGINE" ]; then ln -sf "$ENGINE" ./akshay-chessckers-0; fi
echo "[client] -> $SERVER  user=$CC_USER  run=$RUN  engine=$ENGINE"
exec ./akshay-chessckers-client \
    --hostname "$SERVER" --user "$CC_USER" --password "$CC_PASS" --run "$RUN"
