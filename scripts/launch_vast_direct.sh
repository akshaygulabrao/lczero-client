#!/usr/bin/env bash
# Launch a self-play CLIENT on a vast.ai box against a PUBLIC-IP server (NO
# tailscale) -- used when the chessckers server runs on a vast box with an open
# port (see lczero-server/scripts/run_server_vast.sh). The client reaches the
# server directly over its public ip:port, so none of launch_vast.sh's tailscale
# /userspace-proxy machinery is needed. Runs in a detached tmux 'cc-client'
# session so it survives ssh drops. Run FROM the Mac after provision_vast.sh has
# built /workspace/lc0-client + the engine on the box.
#
# Usage:
#   VAST_HOST=ssh2.vast.ai VAST_PORT=15804 \
#   SERVER=http://58.8.189.254:27007 scripts/launch_vast_direct.sh
#
# Env overrides: VAST_USER, ENGINE, CLIENT, CC_USER, CC_PASS, RUN, PARALLELISM.
set -euo pipefail
VAST_HOST="${VAST_HOST:?set VAST_HOST (ssh host)}"
VAST_PORT="${VAST_PORT:?set VAST_PORT (ssh port)}"
VAST_USER="${VAST_USER:-root}"
SERVER="${SERVER:?set SERVER, e.g. http://<public-ip>:<external-port>}"
ENGINE="${ENGINE:-/workspace/akshay-chessckers-0/build/akshay-chessckers-0}"
CLIENT="${CLIENT:-/workspace/lc0-client}"
CC_USER="${CC_USER:-vast}"
CC_PASS="${CC_PASS:-chessckers}"
RUN="${RUN:-1}"
PARALLELISM="${PARALLELISM:-96}"   # games in flight -> fills the GPU eval batch (tune for util)
SSHO="-p $VAST_PORT -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"

echo "[client] launch on $VAST_USER@$VAST_HOST:$VAST_PORT -> $SERVER (parallelism=$PARALLELISM)"
ssh $SSHO "$VAST_USER@$VAST_HOST" \
  "ENGINE='$ENGINE' CLIENT='$CLIENT' SERVER='$SERVER' CC_USER='$CC_USER' CC_PASS='$CC_PASS' RUN='$RUN' PARALLELISM='$PARALLELISM' bash -s" <<'REMOTE'
set -euo pipefail
CLIENT_DIR="${CLIENT%/*}"
[ -x "$CLIENT" ] || { echo "[client] $CLIENT not found -- run provision_vast.sh first" >&2; exit 1; }
[ -x "$ENGINE" ] || { echo "[client] $ENGINE not found -- run provision_vast.sh first" >&2; exit 1; }
# engine must be discoverable as 'akshay-chessckers-0' on PATH (Go 1.19+ won't search CWD).
# -T forces link-not-into-dir so it never lands inside a pre-existing same-named dir.
mkdir -p "$CLIENT_DIR/.enginebin"
ln -sfT "$ENGINE" "$CLIENT_DIR/.enginebin/akshay-chessckers-0"
# idempotent: kill any prior client/engine (each grabs the GPU) but NOT this shell.
self=$$; par=$PPID
for pid in $(pgrep -f 'lc0-client|akshay-chessckers-0 selfplay' 2>/dev/null); do
  [ "$pid" = "$self" ] && continue; [ "$pid" = "$par" ] && continue
  kill "$pid" 2>/dev/null || true
done
sleep 1
tmux kill-session -t cc-client 2>/dev/null || true
tmux new-session -d -s cc-client -c "$CLIENT_DIR"
tmux send-keys -t cc-client "PATH=\"$CLIENT_DIR/.enginebin:\$PATH\" '$CLIENT' -hostname '$SERVER' -user '$CC_USER' -password '$CC_PASS' -run $RUN -parallelism $PARALLELISM 2>&1 | tee -a client.log" C-m
echo "[client] tmux 'cc-client' started -> $SERVER  (engine=$ENGINE)"
REMOTE
echo "[client] watch:  ssh -p $VAST_PORT $VAST_USER@$VAST_HOST -t tmux attach -t cc-client   (Ctrl-b d to detach)"
echo "[client] stop :  ssh -p $VAST_PORT $VAST_USER@$VAST_HOST tmux kill-session -t cc-client"
