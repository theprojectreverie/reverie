# Reverie Online API â€” Phase 1 foundation

A modular-monolith TypeScript/Fastify service. This is a local development foundation, not a public production service.

## Local development
1. Copy .env.example to .env and replace the database URL and JWT secret.
2. Provision PostgreSQL 16+.
3. Apply backend/schemas/schema.sql, then every migration in backend/migrations in numeric order: 002_online_multiplayer.sql, 003_auth_lifecycle.sql, 004_coop_lobby_access.sql, 005_pvp_friendly_queue.sql, 006_pvp_seed_storage.sql, 007_pvp_runtime_state.sql, 008_account_session_indexes.sql, 009_equipment_progression.sql, 010_account_token_version.sql, 011_pvp_queue_terminal_status.sql, 012_persistent_game_servers.sql, 013_game_server_join_tickets.sql, 014_persistent_world_player_state.sql, 015_persistent_world_state_retention.sql, 016_persistent_world_event_log.sql, 017_persistent_world_connection_leases.sql, and 018_persistent_world_event_idempotency.sql. Each filename has a unique sequence number.
4. Apply migrations 012–018 in order: 012 creates the persistent regional server directory and revisioned world-state storage; 013 adds single-use join tickets; 014 stores durable player positions; 015 retains those positions when a server assignment is released; 016 adds the shared durable world-event log and sequence counter; 017 adds cross-process connection leases; 018 adds event idempotency keys for safe retries.
5. Run npm.cmd install, npm.cmd run typecheck, npm.cmd run build, then npm.cmd run dev.
6. Health check: GET /health.

## Implemented
- Fastify bootstrap, security headers, global and route-level rate limits, PostgreSQL health check.
- Registration transaction with Argon2id password hashing, player creation and initial currency rows.
- One-time email-verification token hashes with 24-hour expiry and atomic consumption.
- Development-only verification token returned in the registration response when NODE_ENV=development. Production must use an email-delivery adapter; never expose verification tokens in production responses.
- Login with email-verification gate, short-lived signed access tokens and opaque refresh tokens.
- Refresh-token rotation with server-side SHA-256 hashes and revocation; logout revokes the supplied session. Login keeps at most five active sessions per account, and refresh updates session last-used timestamps.
- Private 2â€“4 player co-op lobby create/join/current/leave endpoints with hashed invite codes, capacity checks, block checks and leader handoff.
- Authenticated WebSocket event relay with persisted sequence numbers, bounded position proposals, emotes, acknowledgements and reconnect replay.
- Godot AuthGateway and MultiplayerGateway autoloads, reusable AccountScreen scene and title-screen Online entry point. Persistent-world client handshakes are bounded by a 12-second timeout; stalled peers are discarded, and exponential reconnect delays include capped jitter to spread simultaneous client retries after a regional restart.

## Local database integration status
- PostgreSQL 17 is installed as the Windows service `postgresql-x64-17`, bound to localhost only.
- Local database `reverie` and least-privilege application login `reverie_app` are provisioned; credentials and the development JWT secret are stored in the ignored local `backend/api/.env` file.
- The base schema and migrations 002–018 have been applied successfully. Migrations 016–018 add the durable shared world-event log, PostgreSQL connection leases, and idempotent event appends.
- API `/health` returned HTTP 200 with `database: ok`; backend unit tests pass (87), TypeScript typecheck passes, and migrations 016–018 are applied locally.
- Persistent-world integration passes 74/74 checks, including simultaneous single-use ticket redemption, stale-lease cleanup during server takeover, four-player Godot admission and movement, renewal of all four connection leases, ordered PostgreSQL replay, and two independent production Godot clients reconnecting together after a real regional process restart. The reconnect clients instantiate the actual authored `GameScreen` scene (player, collision world, HUD, remote-avatar layer and production co-op sync), not a miniature stub world. With two visible OpenGL game clients (`REVERIE_E2E_GUI_CLIENTS=1`), both recover after the same regional restart, then apply real rightward input through their `CharacterBody2D` locomotion and world collision shapes. Both hit world collision geometry (slide collisions recorded), then continue pushing into the obstacle for another 400 ms without crossing the contact point by more than 2 pixels. Each also sees the other player's authoritative moved position within 3 pixels. The final positions are confirmed in PostgreSQL with both leases live; duplicate/stale snapshot handling, party removal and cleanup are also verified. The E2E clients load the existing local profile read-only (`REVERIE_E2E_DISABLE_LOCAL_SAVE=1`) so concurrent graphical test windows cannot overwrite the user's single-player save. The default runner remains headless unless that flag is set.
- The actual playable `GameScreen` co-op scene smoke passes 19/19 checks: two remote avatars instantiate under the live world entity tree, names and character visuals initialize, movement targets trigger walk animation, remote presentation nodes add no physics blockers, duplicate snapshots do not duplicate nodes, recovery locks local locomotion, authoritative positions restore, and departed party members are removed without stale nodes. The smoke explicitly drains the global audio director before shutdown; a verbose run confirms no leaked audio playback instances or resources. Run with `Godot --headless --path <project> res://tests/online_coop_game_scene_smoke.tscn`.
- The dedicated eight-player reconnect E2E passes through a full regional process restart: eight concurrent admissions, eight durable leases and position writes, simultaneous disconnect/reconnect, same server-identity reclamation, eight new-process admissions, full party snapshot recovery, preserved positions, and verified cleanup. Run it with `npm.cmd run test:e2e:eight-player`.
- Replay recovery now detects missing sequence numbers inside an otherwise retained event window and falls back to the authoritative position snapshot instead of leaving a restarted region stuck before transport startup. Five unit tests cover contiguous and incomplete replay sequences.
- No production email provider, password-reset flow, account deletion/export, or device/session management UI.
- No player bootstrap/cloud-save migration, friend-request/block-management API, obstacle-level map collision/navigation validation or ranked matchmaking. Friendly PvP combat resolution is implemented server-side, but live two-client database-backed battles remain unverified.

## Auth-data retention maintenance
- `backend/ops/auth_retention_cleanup.sql` is a bounded, repeatable cleanup for revoked/expired refresh sessions and consumed/expired email-verification tokens after a 30-day grace period.
- Run it from an external deployment scheduler (for example, daily) until each batch affects zero rows. It is intentionally not started by every API process.
- Account-wide logout atomically increments the account token version and revokes refresh sessions. Co-op/PvP HTTP entry points and WebSocket handshakes compare the JWT version with the database; each WebSocket message rechecks it and closes revoked sessions. Each message also revalidates active lobby membership, so a socket left behind after a player leaves (or a lobby closes) cannot continue sending world events. These checks are fail-closed when the database query fails. Already-running HTTP requests are not cancelled mid-flight.

## Security gates before public testing
Before public testing: use HTTPS/WSS behind a trusted reverse proxy; set production secrets outside source control; add production email delivery, recovery and GDPR flows; complete live two-account auth/co-op/PvP integration plus load/abuse tests; consider short-lived WebSocket ticket exchange instead of JWT query parameters; add authoritative obstacle/navigation checks beyond current region rectangles; review privacy notice, retention policy, age rating and abuse reporting. Friendly-duel PvP resolution and coarse movement plausibility are implemented locally, not production-certified.


## Friendly PvP runtime endpoints (development milestone)
- Authenticated `POST /v1/pvp/queue/join`, `POST /v1/pvp/queue/leave`, and `GET /v1/pvp/queue/status` provide the unranked friendly-duel queue.
- A successful pair loads both server-owned party/equipment rosters, creates the deterministic battle state, stores the private skillbook and seed server-side, and appends the initial `match_started` event. The response includes `combatReady:true` only after the state is persisted.
- Authenticated `POST /v1/pvp/matches/:matchId/action` accepts an actor, skill, target list and expected action sequence. Player identity, roster, skillbook, stats and result are server-owned. Match-row locking, state transition and contiguous event inserts share one database transaction.
- Authenticated `GET /v1/pvp/matches/:matchId/events?after=0` returns up to 200 ordered events and a cursor for another page. `hasMoreEvents` indicates another page; continue with `nextCursor`. The response also includes the current sanitized state snapshot and `snapshotEventSequence`, the event sequence already represented by that snapshot. When consuming the snapshot, do not re-apply events at or below that sequence. Private seed, passive flags and skillbook are not exposed.
- These routes are implemented and unit/type/build checked. PostgreSQL 17 and migrations 002–012 are now installed locally; live SQL transaction and two-client battle flow still require integration verification. Do not enable public matchmaking until those tests pass.


- Queue status now expires stale waiting tickets and closes matched tickets when their match completes, expires or is cancelled. A player can queue again after a terminal match without manually clearing an old ticket. Migration 011 adds the explicit `completed` ticket state.


- Authenticated `POST /v1/pvp/matches/:matchId/surrender` lets a participant concede an active friendly duel. The server determines the opponent as winner, writes surrender/completion events, final state and result, and closes both matched queue tickets in one transaction. Surrender is rate-limited and cannot be submitted by a non-participant.
- Match timeout is enforced when a participant next submits an action: the match is atomically marked expired, a `match_expired` event and no-winner result are persisted, and its queue tickets are closed. There is not yet a deployment scheduler for unattended timeout sweeps.

## Persistent game-server architecture (migrations 012–018)
- Direction: multiple smaller persistent regional servers, not player-created co-op lobbies as the primary world model.
- `game_servers` is the directory/health registry for named server instances and their region, lifecycle status, endpoint, capacity, build version and heartbeat.
- `game_server_players` assigns each player to at most one persistent server at a time.
- `game_server_world_state` stores revisioned JSON world state so a server process can recover state after restart.
- `game_server_player_state` stores each player’s last known coordinates independently of their current assignment, allowing positions to survive disconnect and reassignment.
- Migrations 012–018 are applied locally. The standalone Godot regional process now owns player WebSocket sessions and authoritative movement validation while using the same PostgreSQL event sequence, `game_server_world_events` log, `game_server_player_state` snapshot source, and `game_server_player_connections` lease table as the API-hosted WebSocket path. Durable event appends are idempotent; replay and startup recovery use the shared event log, with position snapshots when the replay window has a gap. The old lobby endpoints remain separate and are not being represented as dedicated game servers.

### Game-server directory API
- `POST /v1/game-servers/register` provisions a server using the `x-server-bootstrap-secret` environment secret. The generated server bearer token is returned once; only its SHA-256 digest is stored.
- `POST /v1/game-servers/:serverId/heartbeat` authenticates with that server token and updates lifecycle status and heartbeat time. A server is discoverable only while online with a heartbeat newer than 60 seconds.
- `GET /v1/game-servers` requires a current player JWT and lists online servers with live player counts.
- `POST /v1/game-servers/:serverId/join` and `/leave` manage one-server-per-player assignments with capacity checks. Join now returns a random 60-second single-use ticket; only its SHA-256 digest is stored. New assignments and explicit leave revoke any outstanding ticket; redemption also requires the player still be assigned to that server.
- `POST /v1/game-servers/:serverId/consume-ticket` is server-token authenticated and atomically redeems a ticket once, returning the assigned player ID and optionally creating a 45-second connection lease in the same transaction. Replays and expired tickets are rejected. `PUT` and `DELETE /:serverId/connections/:connectionId` renew and release leases.
- Set `GAME_SERVER_BOOTSTRAP_SECRET` to a random secret of at least 32 characters before provisioning any server. It is intentionally optional in local config so ordinary API development can start, but registration fails closed when it is absent.
- `POST /v1/game-servers/:serverId/events` appends a server-authenticated, idempotent world event using the shared per-server sequence; position events also update durable player coordinates in the same transaction. `GET /v1/game-servers/:serverId/events?after=...` provides ordered replay and a recovery snapshot when the cursor is outside the retained event window.
- `PUT /:serverId/world-state` uses compare-and-swap revisions: the first save must start from revision 0, and each later save must submit the current revision. Stale or conflicting writes return 409 instead of overwriting newer state.
- Server registration can reclaim an offline or stale server key, reuses the persistent server ID, rotates the bearer token, and atomically clears connection leases owned by the previous process. Player assignments and durable positions remain available for reconnect and world recovery. The dedicated Godot process accepts an optional `REVERIE_SERVER_MAX_PLAYERS` environment override (clamped to 1–1000) for per-region capacity configuration.
- Server world-state recovery: authenticated `GET /v1/game-servers/:serverId/world-state` loads the last revision; `PUT` saves a JSON state document up to 12 KB using optimistic revision checks. Concurrent stale writes return HTTP 409 instead of overwriting newer world state.
- Run `npm.cmd run test:e2e:persistent-world` for API-hosted and standalone Godot integration, including four simultaneous players and production-client reconnect/recovery. Run `npm.cmd run test:e2e:eight-player` for eight concurrent clients, simultaneous disconnect/reconnect, and snapshot/position persistence. Run `npm.cmd run test:e2e:dedicated-world` for the focused standalone server test. These integration tests require the local Godot executable and PostgreSQL configuration in `.env`.
