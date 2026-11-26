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

## API performance and incident acknowledgment
Migration 054_regional_incident_acknowledgment.sql adds write-once acknowledgment timestamp, account reference and note. Acknowledgment never resolves an incident. Configured developers and owners only. Performance snapshots cover the individual API process, HTTP requests in an approximately 60-second rolling window, histogram latency bounds, 5xx and 429 counts, database probe round trip and pool pressure, process RAM and event loop delay. The probe runs every 15 seconds; database outage may also prevent dashboard authentication or retrieval. No cluster-wide aggregation or external alerting. Run test/operational-metrics.test.ts and scripts/server-incidents-e2e.mjs with the local development environment.

## Persistent history and encrypted backups
Apply 059_operational_history.sql and set OPERATIONAL_HISTORY_INSTANCE_ID to a unique stable name per API instance to retain the last hour of graph data across restarts. Samples older than 24 hours are pruned in bounded batches for the configured instance; database outages may create gaps, and history remains local to each instance. Keep this unset until migration is applied.
The local operator backup command is node --env-file=.env scripts/encrypted-backup-once.mjs --execute from backend/api. Requires REVERIE_BACKUP_DIR (private absolute directory outside repo), REVERIE_BACKUP_KEY_HEX (32 cryptographically random bytes as hex, stored separately in a secret manager), and optional REVERIE_PG_BIN. Dumps stream directly into AES-256-GCM encryption, authenticate before atomic publication, never overwrite existing files, and list retention candidates only (keep at least seven and 30 days). No rotation deletions or unattended schedule are installed. Never commit archives or keys; verify filesystem ACLs, offsite copies, key recovery and independent restore drills before production use. The synthetic backup-restore-drill.mjs verifies encryption and authenticated restoration in an isolated PostgreSQL instance. The operator runner is local-only and has not been executed against actual player data.

## Backup scheduling readiness
The local operator runner accepts --execute --scheduled for a due-checked invocation. Use an external service/task scheduler to invoke periodically only after verifying private directory ACLs, separate key custody, recovery access and explicit authorization. Successful backups suppress subsequent scheduled runs for 24 hours; failures or missing archives are retried no sooner than one hour after the last attempt. A manual --execute without --scheduled bypasses time gates but not the exclusive directory lock. The state file contains only status, timestamps and archive basename; corrupt state or backward clock stops execution. A stale lock after abrupt termination requires operator review, not automatic removal. A scheduled skip checks archive existence, not cryptographic integrity; use a separate verification drill. pg_dump has a two-hour process timeout. Retention candidates remain review-only. No unattended operating system task or production backup is installed. Run scripts/backup-cycle-test.mjs and scripts/backup-restore-drill.mjs for the synthetic tests.

## Independent archive verification and replica readiness
Set REVERIE_BACKUP_DIR and optionally REVERIE_BACKUP_REPLICA_DIR to existing private absolute directories outside the repository. Supply the encryption key only to the separate operator verifier process. From backend/api, run node --env-file=.env scripts/backup-verify-once.mjs --execute to verify the most recent recorded archive; add --copy to publish an authenticated byte-identical encrypted replica without overwriting any existing file. The directories must be distinct and non-nested. This is a filesystem copy, not a cloud upload; a second directory on the same disk is not offsite redundancy. Verify ACLs, storage fault domains and hard-link support before selecting a destination. Corrupt or conflicting copies require operator review. The verifier writes a bounded status-only .reverie-backup-verification.json report under the primary directory; configure BACKUP_HEALTH_REPORT_PATH as its absolute path in the API environment. The developer console receives no archive filenames, paths or keys. It flags missing/failed verification, missing replica, backup age over 26 hours and verification reports over 26 hours old. The independent verifier needs external scheduling; no jobs or real-player backups are activated. Run scripts/backup-verification-test.mjs with tsx and scripts/backup-restore-drill.mjs for the synthetic replica restore.

The replica recovery drill removes the disposable primary archive before restoring the replica, and verifies the independent health report flags the missing primary. Failed or interrupted first attempts are distinguished from a never-run schedule.

## Recovery candidate selection
Run node --env-file=.env scripts/backup-recovery-plan-once.mjs --execute with the private primary/replica paths and backup key. The planner examines up to seven recent distinct archive names across both directories, ignores future timestamps, authenticates each existing copy, and rejects same-name authenticated copies with conflicting ciphertext. It reports the newest available authenticated candidate and whether it came from primary or replica, including skipped newer generations. It never decrypts to disk, changes a backup, selects a database target, or restores production data. Authentication is not proof of a successful database restore: verify the selected archive again before an isolated restore. The expanded synthetic backup-restore-drill.mjs demonstrates an older replica restoring all nine data categories after primary loss and corruption of a newer generation.

## Shared API quotas
Apply 061_shared_rate_limits.sql and configure the same SHARED_RATE_LIMIT_NAMESPACE and JWT secret on all participating API instances. Unset by default. The PostgreSQL store atomically increments fixed-window buckets using the database clock and HMAC-hashed route/principal identities; global and route-specific quotas preserve existing middleware semantics. On store failure requests are rejected with 503 rather than bypassing protection. Bounded expired-bucket cleanup is enabled with the store. Rotate secrets and coordinate API rollout deliberately: changing the secret or namespace resets effective counters. This adds a database write per limited HTTP request, so benchmark under sustained load before enabling in production; use a dedicated distributed cache if DB contention becomes significant. No changes to existing trusted proxy settings, deployment, or WebSocket message quotas. Run scripts/shared-rate-limit-e2e.mjs and REVERIE_E2E_SHARED_QUOTAS=1 with scripts/multi-region-load-e2e.mjs against local development only.
