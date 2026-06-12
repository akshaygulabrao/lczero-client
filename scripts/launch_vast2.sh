#!/usr/bin/env bash
# Node 2 self-play client: RTX 3060 (vast.ai instance 40425814). Foreground tab — Ctrl-C ends it.
# Thin wrapper that pins this box's SSH connection + tailnet/server identity and
# delegates to launch_vast.sh (which does the tailscale join + runs the client).
#
# Note: vast's SSH proxy (ssh6.vast.ai) reset long streams during provisioning, so
# this uses the box's DIRECT ip:port. If the instance is recreated, refresh these
# from `vastai ssh-url 40425814`.
set -euo pipefail
export VAST_HOST="${VAST_HOST:-95.253.220.115}"
export VAST_PORT="${VAST_PORT:-42283}"
export CC_USER="${CC_USER:-vast2}"          # server attributes this node's games to 'vast2'
export TS_HOSTNAME="${TS_HOSTNAME:-vast2}"  # tailnet node name (distinct from node 1)
exec "$(dirname "$0")/launch_vast.sh" "$@"
