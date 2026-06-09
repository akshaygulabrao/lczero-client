# Porting lczero-client → chessckers (akshay-chessckers-0 fleet)

This is the LeelaChessZero self-play **client** converted to run the
`akshay-chessckers-0` engine and contribute games to the chessckers training
server. Same principle as the rest of the port: keep lc0's well-tested client
machinery (server handshake, network cache + flock, match/train orchestration,
retry/backoff) and change only what is chess- or lc0-specific.

## Decisions (locked)

1. **Drive `akshay-chessckers-0`, not `lc0`.** Same `selfplay` stdout contract
   (`gameready trainingfile … gameid … player1 … result … moves …`), so the
   train/match plumbing is reused verbatim.
2. **No chess library.** Chessckers moves (diagonal hops, capture chains, deploys,
   charges) aren't chess SAN/UCI, so the `Tilps/chess` Go dependency is gone; the
   "pgn" we upload is a plain movelog the server stores opaquely.
3. **Tailscale for orchestration.** The client's default `--hostname` is the
   server's tailnet MagicDNS name (`http://macbookprom1pro:9830`).

## What changed (and why)

- **Engine binary**: `lc0Exe` → `akshay-chessckers-0` (and `.exe` on Windows);
  the UCI id parse is `id name akshay-chessckers-0 v…`; config/cache dirs renamed
  to `chessckers`.
- **`convertMovesToPGN` → chessckers movelog**: drops `Tilps/chess`; emits the
  engine's own move tokens space-joined + a result tag + the lc0-style
  `{OL: N}` marker. (`from_fen <fen>` on the tail is split off, not parsed.)
- **Backend selection simplified**: the engine has one native NN backend (Metal
  GPU / CPU BLAS, chosen internally), so `launch()` just passes
  `--backend=chessckers`. Removed lc0's GPU autodetect (cudnn/cuda/dx12/opencl),
  the dx12 self-check, `--backend-opts` juggling, and the "no-GPU ⇒ train-only"
  forcing. Self-play options the engine *does* expose are reused as-is:
  `--training`, `--visits`, `--parallelism`, `--player1/2.weights`,
  `--no-share-trees`.
- **Network decompress for the engine** (`checkValidNetwork`): the wire/cache
  format is a **gzipped** net (so the server can sha256 the decompressed bytes and
  do delta updates), but `akshay-chessckers-0` loads a **raw** `.bin` via a plain
  `ifstream`. The client already decompresses the download to verify its sha; it
  now also materializes a `<sha>.bin` sibling and hands THAT path to `--weights`.
- **Tailnet default + cleanup**: `--hostname` defaults to the tailnet server;
  removed the `-use-test-server` (lczero.org) override and the `Tilps/chess`
  version check.

## The engine contract this relies on

`akshay-chessckers-0 selfplay` prints, per finished game (see the engine's
`src/selfplay/loop.cc`):

```
gameready trainingfile <path> gameid <id> play_start_ply <n> player1 <white|black> \
          result <whitewon|blackwon|draw> moves <m1> <m2> … [from_fen <fen>]
```

`<path>` is a gzipped-JSON `ccz1` training chunk (trainer-readable). The client
uploads that file + the movelog and deletes it, exactly as lc0 did with V6 chunks.

## Build & run (Tailscale fleet)

```
# local self-play client (needs the akshay-chessckers-0 binary)
SERVER=http://macbookprom1pro:9830 scripts/launch_client.sh

# a client on leena, over Tailscale (ssh -t; talks to the server on the tailnet,
# so macOS Local-Network TCC never applies)
scripts/launch_leena.sh
```

`launch_client.sh` builds the client, symlinks the engine binary as
`akshay-chessckers-0` in CWD (the client looks for it there, then PATH), and runs
against the tailnet server. Built binaries + the symlink + `client-cache/` are
git-ignored.

## Verified

`go build` + `go vet` clean. The decompress-to-`.bin` path is covered by the
server-side fetch test (downloaded net bytes identical to the upload). The
move→movelog conversion and `--backend=chessckers` launch are exercised by the
server's `next_game`/`upload_game` handshake test.
