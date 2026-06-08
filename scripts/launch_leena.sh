#!/usr/bin/env bash
# Foreground tab of the chessckers fleet: run a self-play CLIENT on leena over
# TAILSCALE. Uses `ssh -t` so the remote client is session-attached, but it
# reaches the server over the tailnet (a utun WireGuard interface), NOT the LAN.
# Because tailnet traffic is not "local network", macOS Local Network privacy
# (TCC) never gates it — the block that hit the LAN fleet does not apply here.
#
# Assumes leena has this repo checked out (CLIENT_DIR) with the engine binary,
# and is reachable as the tailnet host $LEENA. Ctrl-C tears down the ssh session.
set -euo pipefail

LEENA="${LEENA:-leena}"                            # tailnet MagicDNS name / ssh alias
SERVER="${SERVER:-http://macbookprom1pro:9830}"    # server's tailnet URL
CLIENT_DIR="${CLIENT_DIR:-lczero-client}"          # path to this repo on leena
CC_USER="${CC_USER:-leena}"

echo "[leena] ssh -t $LEENA  ->  $CLIENT_DIR  (server $SERVER)"
exec ssh -t "$LEENA" \
    "cd '$CLIENT_DIR' && SERVER='$SERVER' CC_USER='$CC_USER' scripts/launch_client.sh"
