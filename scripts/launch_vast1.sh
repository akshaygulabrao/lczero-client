#!/usr/bin/env bash
# Node 1 self-play client: RTX 3060 (vast.ai instance 40579128). Foreground tab — Ctrl-C ends it.
# Thin wrapper that pins this box's SSH connection + tailnet/server identity and
# delegates to launch_vast.sh (which does the tailscale join + runs the client).
set -euo pipefail
export VAST_HOST="${VAST_HOST:-76.65.105.169}"   # direct ip; refresh via `vastai ssh-url 40579128`
export VAST_PORT="${VAST_PORT:-26011}"
export CC_USER="${CC_USER:-vast}"          # server attributes this node's games to 'vast'
export TS_HOSTNAME="${TS_HOSTNAME:-vast}"  # tailnet node name
exec "$(dirname "$0")/launch_vast.sh" "$@"
