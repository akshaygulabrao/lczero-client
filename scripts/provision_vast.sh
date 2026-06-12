#!/usr/bin/env bash
# Provision a FRESH vast.ai GPU box for chessckers self-play. One-time per box;
# after this, scripts/launch_vast1.sh (or launch_vast.sh) is a clean launch.
#
# It does three things, leaving the two binaries exactly where launch_vast.sh
# looks for them:
#   1. cross-compiles the Go client on THIS Mac  -> /workspace/lc0-client
#   2. rsyncs the lc0 fork's source to the box
#   3. apt-installs build deps + CUDA-builds the engine there
#        -> /workspace/akshay-chessckers-0/build/akshay-chessckers-0
#
# The client is cross-compiled on the Mac (CGO off) so the box needs no Go. The
# engine MUST build on the box (CUDA). Re-runnable: rsync --delete + rm -rf build.
#
# Usage:
#   VAST_HOST=<ip> VAST_PORT=<port> scripts/provision_vast.sh
#   (defaults match launch_vast1.sh; refresh conn via `vastai ssh-url <id>`)
#
# GPU/nvcc: this targets a CUDA `-auto` image (nvcc + cublas/cudart-dev + gcc +
# ninja + cmake + git + rsync already present; /usr/local/cuda set). The CUDA
# trunk compiles with -arch=native, so set NVCC per the GPU:
#   Turing/Ampere/Ada (RTX 20xx/30xx/40xx) -> NVCC=true  (GPU trunk)
#   Pascal (sm_61) under a CUDA-13 image    -> NVCC=false (CPU-only; nvcc 13 drops it)
set -euo pipefail
cd "$(dirname "$0")/.."
CLIENT_SRC="$(pwd)"
ENGINE_SRC="${ENGINE_SRC:-$(cd .. && pwd)/akshay-chessckers-0}"

VAST_HOST="${VAST_HOST:-76.65.105.169}"   # direct ip; refresh via `vastai ssh-url <id>`
VAST_PORT="${VAST_PORT:-26011}"
VAST_USER="${VAST_USER:-root}"
NVCC="${NVCC:-true}"                       # RTX 3060 = Ampere sm_86 -> CUDA GPU trunk

SSHO="-p $VAST_PORT -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"
SCPO="-P $VAST_PORT -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"  # scp wants -P (uppercase)
ssh_box() { ssh $SSHO "$VAST_USER@$VAST_HOST" "$@"; }

[ -d "$ENGINE_SRC" ] || { echo "[provision] engine source not found: $ENGINE_SRC" >&2; exit 1; }
echo "[provision] target $VAST_USER@$VAST_HOST:$VAST_PORT  nvcc=$NVCC"
echo "[provision] client=$CLIENT_SRC  engine=$ENGINE_SRC"

# 1. Cross-compile the Go client on the Mac, ship it to the box.
echo "[provision] (1/3) cross-compiling Go client (linux/amd64)..."
( cd "$CLIENT_SRC" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /tmp/lc0-client . )
ssh_box 'mkdir -p /workspace'
scp $SCPO /tmp/lc0-client "$VAST_USER@$VAST_HOST:/workspace/lc0-client"
ssh_box 'chmod +x /workspace/lc0-client'

# 2. rsync the engine source (skip build artifacts + .git).
echo "[provision] (2/3) rsyncing engine source to the box..."
ssh_box 'mkdir -p /workspace/akshay-chessckers-0'
rsync -az --delete -e "ssh $SSHO" \
  --exclude 'build/' --exclude 'build-*/' --exclude '.git/' \
  "$ENGINE_SRC/" "$VAST_USER@$VAST_HOST:/workspace/akshay-chessckers-0/"

# 3. Install deps + CUDA-build the engine on the box.
echo "[provision] (3/3) installing deps + building engine on the box..."
ssh_box "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# -auto image ships nvcc/cublas/cudart-dev + gcc + ninja + cmake + git; only these need apt.
apt-get update -qq
apt-get install -y -qq meson protobuf-compiler libprotobuf-dev libopenblas-dev zlib1g-dev
cd /workspace/akshay-chessckers-0
rm -rf build
meson setup build -Dbuildtype=release -Dbuild_backends=false -Dnvcc=$NVCC
ninja -C build akshay-chessckers-0
echo '[provision] engine built ->'; ls -la build/akshay-chessckers-0
echo '[provision] runtime backend banner:'; ./build/akshay-chessckers-0 --help >/dev/null 2>&1 || true
"

echo "[provision] DONE. Launch self-play with:"
echo "    VAST_HOST=$VAST_HOST VAST_PORT=$VAST_PORT scripts/launch_vast1.sh"
