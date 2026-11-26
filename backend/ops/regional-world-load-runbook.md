# Regional world scalability QA

Use a disposable loopback PostgreSQL environment only. The runner creates unique
test accounts, a regional server, leases and movement records; it verifies
cleanup and rejects non-loopback database hosts. Do not use production database
credentials. Keep player saves isolated with a temporary APPDATA directory.
Run from `backend/api` in PowerShell.

## Five-minute movement endurance

```powershell
$env:REVERIE_E2E_DISABLE_LOCAL_SAVE='1'
$env:APPDATA=Join-Path $env:TEMP 'reverie-regional-load-qa'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:REVERIE_E2E_PLAYERS='100'
$env:REVERIE_E2E_MOVEMENT_ROUNDS='0'
$env:REVERIE_E2E_CLUSTER_MODE='interest'
$env:REVERIE_E2E_CLUSTER_SIZE='8'
$env:REVERIE_E2E_CLUSTER_SETUP_MS='150'
$env:REVERIE_E2E_CLUSTER_ROUNDS='1500'
$env:REVERIE_SERVER_INTEREST_RADIUS='150'
$env:REVERIE_SERVER_EVENT_BATCH_SIZE='128'
node --env-file=.env --import tsx scripts/eight-player-reconnect-e2e.mjs
```

The workload is five validated movement proposals/second/player. The initial
positioning ramp and reconnect/restart checks are additional to the measured
movement duration. The fixture uses bounded admissions and a synthetic regional
coordinate layout, not an authored gameplay map or physical phones.

## Mixed-traffic and checkpoint verification

For a separate one-minute run, set `REVERIE_E2E_CLUSTER_ROUNDS=300`,
`REVERIE_E2E_CLUSTER_MIXED=1` and `REVERIE_E2E_CHECKPOINT_VERIFY=1`.
The mixed probe adds staggered emotes and pings, verifies per-player durable emote
counts and per-recipient delivery, and checks pong counts and sequence ranges. Set REVERIE_E2E_REAL_RATE_LIMITS=1 to enable the production-style global body limit and route quotas in the isolated fixture.
The checkpoint probe requires at least two saved revisions and verifies
every saved position against the durable event cursor.

API-only checkpoint capacity/race regression:

```powershell
node --env-file=.env --import tsx scripts/world-checkpoint-capacity-e2e.mjs
```

The checkpoint route accepts up to 256 KiB state and uses atomic revision
compare-and-swap. The synthetic 1,000-player checkpoint test is not proof that
1,000 people can play simultaneously.

## Deployment considerations

- Client/server interest-window negotiation is opt-in. Server radius defaults
  to zero; 150 is a synthetic-test radius, not a recommendation for a real map
  or device viewport. Pick a real radius only after visual and gameplay QA.
- The 128-event setting is a local benchmark configuration. The server and API
  must support the same batch limit. Verify idempotent retries and API quotas.
- Movement payload bytes omit WebSocket framing, TLS, IP and TCP overhead.
  Event row bytes omit indexes, WAL, and database table overhead. At sustained
  500 movement events/second and 144 bytes/row, one region can generate about
  6.22 GB of row data per day, before overhead. Real activity varies.
- Automatic retention is disabled by default. Opt-in API configuration:
  `WORLD_EVENT_RETENTION_ENABLED=1`, optionally
  `WORLD_POSITION_RETENTION_HOURS=24` (default 720).
  Non-position events retain the existing 30-day age threshold, and the latest
  1,000 sequences per server are protected. Verify retention policy, recovery
  and deletion throughput on staging; never enable deletion blindly.
- The runner requires every measured proposal to be committed, every final
  nearby state to be delivered, and all cursors to agree with durable storage.
  Only a superseded intermediate sample with proof of a later sample in the
  same received sequence window is exempt from exact intermediate delivery.
- Production gates: real API middleware and reverse proxy, TLS, sustained WAN
  latency, slow mobile clients, clustered gameplay/combat, database outage
  recovery, disk/WAL monitoring, and prolonged multi-region load testing.
