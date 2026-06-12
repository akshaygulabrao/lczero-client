#!/usr/bin/env bash
# Foreground tab of the chessckers fleet: run a self-play CLIENT on a vast.ai GPU
# box over SSH, joined to the tailnet with an EPHEMERAL Tailscale auth key pulled
# from GCP Secret Manager.
#
# Secret handling (SSH-inject): the auth key is fetched on THIS Mac (gcloud is
# authenticated here) and piped to the box over stdin -> `read`. It never touches
# disk on vast, never appears in argv/`ps`, never in shell history. GCP stays the
# single source of truth; nothing is mirrored into vast's own env store.
#
# Userspace networking: vast containers have no /dev/net/tun, so tailscaled runs
# with --tun=userspace-networking and exposes a local HTTP proxy. The Go client
# reaches the tailnet server through that proxy via HTTP_PROXY (tailscale's proxy
# also resolves the MagicDNS name `macbookprom1pro`).
#
# Ephemeral node: `tailscale up --ephemeral` so the box auto-drops from the
# tailnet when it stops — no dead nodes pile up across throwaway instances.
#
# Env overrides: VAST_HOST, VAST_PORT, VAST_USER, SERVER, ENGINE, CLIENT,
#   CC_USER, CC_PASS, RUN, GCP_PROJECT, TS_SECRET, PROXY_PORT.
set -euo pipefail

# --- vast connection (from `vastai show instances`) ---
VAST_HOST="${VAST_HOST:-ssh8.vast.ai}"
VAST_PORT="${VAST_PORT:-35452}"
VAST_USER="${VAST_USER:-root}"

# --- fleet wiring ---
SERVER="${SERVER:-http://macbookprom1pro:9830}"               # server's tailnet URL
ENGINE="${ENGINE:-/workspace/akshay-chessckers-0/build/akshay-chessckers-0}"
CLIENT="${CLIENT:-/workspace/lc0-client}"                     # prebuilt Go client on the box
CC_USER="${CC_USER:-vast}"
CC_PASS="${CC_PASS:-chessckers}"
RUN="${RUN:-1}"
TS_HOSTNAME="${TS_HOSTNAME:-vast}"            # tailnet node name (distinct per box)

# --- secret + proxy ---
GCP_PROJECT="${GCP_PROJECT:-akshay-27mar25}"
TS_SECRET="${TS_SECRET:-ts-selfplay-authkey}"
PROXY_PORT="${PROXY_PORT:-1055}"

CLIENT_DIR="${CLIENT%/*}"   # client invokes ./akshay-chessckers-0 from its own dir

echo "[vast] fetching tailscale auth key from GCP secret '$TS_SECRET' (project $GCP_PROJECT)..."
echo "[vast] ssh $VAST_USER@$VAST_HOST:$VAST_PORT  ->  client $CLIENT  (server $SERVER)"

# Pipe the key into the remote `read`; the remote script lives in argv (stdin is
# the key). Only $TS_AUTHKEY is evaluated remotely (escaped \$); everything else
# is expanded locally.
gcloud secrets versions access latest --secret="$TS_SECRET" --project="$GCP_PROJECT" \
| ssh -p "$VAST_PORT" "$VAST_USER@$VAST_HOST" "
set -euo pipefail
read -r TS_AUTHKEY || true
[ -n \"\$TS_AUTHKEY\" ] || { echo '[vast] empty auth key from GCP'; exit 1; }

# 1. tailscale present?
if ! command -v tailscale >/dev/null 2>&1; then
  echo '[vast] installing tailscale...'
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# 2. tailscaled in userspace mode with a local HTTP proxy (idempotent).
if ! pgrep -x tailscaled >/dev/null 2>&1; then
  echo '[vast] starting tailscaled (userspace, http proxy :$PROXY_PORT)...'
  nohup tailscaled --tun=userspace-networking \
      --outbound-http-proxy-listen=localhost:$PROXY_PORT \
      --socks5-server=localhost:$((PROXY_PORT+1)) \
      >/var/log/tailscaled.log 2>&1 &
  sleep 3
fi

# 3. join the tailnet. Ephemerality is a property of the AUTH KEY (set when the
#    key is generated), not a flag on \`up\` — this tailscale build has no
#    --ephemeral flag, so we must not pass one.
tailscale up --authkey \"\$TS_AUTHKEY\" --hostname $TS_HOSTNAME
printf '[vast] tailnet ip: '; tailscale ip -4 2>/dev/null | head -1 || echo '?'

# 4. engine must be discoverable as 'akshay-chessckers-0' on PATH. Use a
#    DEDICATED bin dir: a symlink named akshay-chessckers-0 in \$CLIENT_DIR would
#    collide with the engine REPO dir of the same name (ln drops the link inside
#    it). \`ln -T\` forces link-not-into-dir even if the target name pre-exists.
mkdir -p '$CLIENT_DIR/.enginebin'
ln -sfT '$ENGINE' '$CLIENT_DIR/.enginebin/akshay-chessckers-0'
cd '$CLIENT_DIR'

# 4b. idempotent: kill any client + engine left over from a PREVIOUS launch so we
#     never stack duplicate self-play processes (each grabs the GPU). MUST exclude
#     THIS shell: ssh passes the whole script as one argv string, so the running
#     script's own command line literally contains 'lc0-client' and 'selfplay' — a
#     bare \`pkill -f\` matches and kills the script itself (it would exit silently
#     right here, before ever exec'ing the client). Exclude \$\$ (and its parent).
self=\$\$; par=\$PPID
for pid in \$(pgrep -f 'lc0-client|akshay-chessckers-0 selfplay' 2>/dev/null); do
  [ \"\$pid\" = \"\$self\" ] && continue
  [ \"\$pid\" = \"\$par\" ] && continue
  kill \"\$pid\" 2>/dev/null || true
done
sleep 1

# 5. run the client through tailscale's HTTP proxy (foreground; Ctrl-C ends it).
#    The client execs an engine named 'akshay-chessckers-0' via PATH lookup
#    (Go 1.19+ no longer searches CWD), so put the symlink's dir on PATH.
echo '[vast] -> $SERVER  user=$CC_USER  run=$RUN'
exec env PATH=\"$CLIENT_DIR/.enginebin:\$PATH\" \
     HTTP_PROXY=http://localhost:$PROXY_PORT HTTPS_PROXY=http://localhost:$PROXY_PORT \
     '$CLIENT' -hostname '$SERVER' -user '$CC_USER' -password '$CC_PASS' -run $RUN
"
