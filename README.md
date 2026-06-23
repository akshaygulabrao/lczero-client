# lczero-client — Chessckers self-play client

Go client that connects to a `lczero-server`, downloads networks, and spawns the
`akshay-chessckers-0` engine to play self-play games. The engine must be on this
same machine — the client does **not** run the engine remotely.

## Quick start

```bash
# Build the Go client (needs Go ≥1.19)
go build -o lc0-client .

# Create the engine symlink (REQUIRED — no --engine flag exists)
mkdir -p .enginebin
ln -sfT /path/to/akshay-chessckers-0/build/release/akshay-chessckers-0 \
        .enginebin/akshay-chessckers-0

# Run (engine found via PATH → .enginebin/akshay-chessckers-0)
./lc0-client -hostname http://your-server:9830 -user vast -password chessckers -run 1
```

## Flag reference

| Flag | Default | Description |
|---|---|---|
| `-hostname` | `http://macbookprom1pro:9830` | Server URL (the only way to set it) |
| `-user` | (required) | Username for server auth |
| `-password` | (required) | Password for server auth |
| `-run` | `0` | Training run ID (0 = server decides) |
| `-parallelism` | `-1` | Games in flight (`-1` = server decides) |
| `-gpu` | `-1` | GPU index (`-1` = server decides) |
| `-config` | — | JSON config file (overrides flags) |
| `-cache` | `~/.cache/chessckers/client-cache/` | Downloaded nets cache |
| `-train-only` | `false` | Skip match games, self-play only |
| `-keep` | `false` | Don't delete old network files |
| `-report-gpu` | `false` | Send GPU info to server |
| `-report-host` | `false` | Send hostname to server |

**There is no `--server` or `--engine` flag.** The server URL is `-hostname`.
The engine is found by `PATH` lookup of `akshay-chessckers-0` — the standard
pattern is a `.enginebin/` symlink in the client's working directory.

## Directory layout on a GPU box

```
/workspace/
├── lczero-client/              # this repo
│   ├── lc0-client              # built Go binary
│   ├── .enginebin/
│   │   └── akshay-chessckers-0 → ../../akshay-chessckers-0/build/release/akshay-chessckers-0
│   └── scripts/
│       └── launch_vast_direct.sh  # launch in persistent tmux
├── akshay-chessckers-0/        # the engine fork
│   └── build/release/akshay-chessckers-0
├── lczero-server/              # server + trainer
│   └── cc-server
└── engine/                     # Python (trainer, rules, analysis)
    └── chessckers_engine/
```

## Launch scripts (for vast.ai boxes)

| Script | Where it runs | What it does |
|---|---|---|
| `scripts/launch_vast_direct.sh` | From your Mac → box | Launches client in a detached `tmux cc-client` session. Needs `VAST_HOST`, `VAST_PORT`, `SERVER` env vars. |
| `scripts/launch_client.sh` | On the box | Simple foreground launch (for tailnet setups) |
| `scripts/provision_vast.sh` | From your Mac → box | One-time: cross-compiles client, rsyncs engine source, builds engine with CUDA |

## Persistent launch (tmux, survives ssh drops)

```bash
# On the box:
CLIENT_DIR=/workspace/chessckers/lczero-client
tmux new-session -d -s cc-client -n selfplay -c "$CLIENT_DIR"
tmux send-keys -t cc-client \
  "export PATH=$CLIENT_DIR/.enginebin:\$PATH; cd $CLIENT_DIR; ./lc0-client -hostname http://localhost:10100 -user vast -password chessckers -run 1 -parallelism 32 2>&1 | tee -a client.log" C-m
```

## Troubleshooting

**Client shows `--help` output → flag rejected.** Check flag spelling:
`-hostname` (not `--server`), `-user` (not `--username`), `-parallelism` (not `--parallel`).

**Engine not found.** Verify `.enginebin/akshay-chessckers-0` is a symlink to
the actual binary. The client spawns `akshay-chessckers-0 selfplay --backend=chessckers ...`.

**Engine fails to load the net.** The server must have published at least one
network. Check `curl http://server:port/` — it should return the server's
JSON status. The client downloads nets to `~/.cache/chessckers/client-cache/`.
