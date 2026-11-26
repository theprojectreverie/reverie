# Regional scale-up and lifecycle pilot

Local development only. The one-shot operator command is a dry run; automatic
execution is intentionally confined to the isolated integration fixture.
Set REVERIE_SCALE_REGIONS to a comma-separated region allowlist and run
node --env-file=.env --import tsx scripts/regional-scale-once.mjs from backend/api.
The controller uses a PostgreSQL session advisory lock in the runner.
It counts reservations, not just currently connected sockets, as occupancy.

Defaults: 80% aggregate regional occupancy, 100 slots per additional process,
two additional registrations per region, four total, three-minute launch
cooldown, maximum four launch attempts per 15 minutes. Only compatible fresh
online regions qualify. The idle grace is ten minutes. These are provisional
policy values, not a production capacity claim.

A confirmed owned process exit triggers registry fencing (offline, credential
revoked, leases released; assignments and durable positions preserved). After
cooldown the same identity and port can be restarted at most twice. Live
processes with missing/stale heartbeat are reported unhealthy rather than
killed. Idle retirement requires another compatible available server and an
atomic occupancy recheck under the server row lock, including assignments,
unexpired tickets and live leases. Retired records continue to count toward
the cap pending explicit operator retirement review. No automatic deletion of
durable state. The heartbeat update rechecks the credential under its row update.

Test: REVERIE_GODOT_BIN must point to the direct engine, not the Windows
console launcher. Run node --env-file=.env --import tsx
scripts/regional-scale-e2e.mjs with a disposable loopback database. The test
uses a simulated policy clock to avoid waiting ten minutes; actual Godot
launch, forced process exit, reconnect and empty retirement are real.

Remaining release gates: durable supervisor ownership across controller
crashes, production process manager, registration quota across multiple
hosts, metrics/alerts, longer uptime and race testing, remote deployment and
a tested operator-approved policy for reuse or removal of retired slots.
Never run the local pilot against production credentials.

## Infrastructure visibility
Configured developers and staff owners can view regional server health at /developer after authentication. Activity-only staff cannot access the infrastructure endpoint. The dashboard refreshes with activity (normally 15 seconds), shows reserved slots separately from distinct connected players, warns at 80% occupancy and stale heartbeat after 60 seconds, and prioritizes warnings in the first 200 server rows. It does not disclose endpoints or credentials. Stale/offline registry status is not proof of a crash, and there is no external paging service yet. Run scripts/server-health-e2e.mjs against the local development database to verify authorization and state classification.

## Incident monitoring
Apply migration 053_regional_server_incidents.sql before enabling SERVER_INCIDENT_MONITOR_ENABLED=1 in the API environment and restarting it. Disabled by default. The monitor polls every 15 seconds, uses a transaction advisory lock and one open record per server/incident kind, and logs only opened/closed transitions. Capacity begins at 80%; full updates the same incident. Availability covers stale heartbeat, missing endpoint and offline servers with reserved players. Maintenance/offline closure is distinguished from condition cleared. Dashboard history shows open count and up to 50 records, with open incidents first. Records are retained while the server registry entry exists (deleting the registry cascades history). Logs and dashboard are the notification channels; no email, SMS or external paging is configured. Run scripts/server-incidents-e2e.mjs on the local database.
