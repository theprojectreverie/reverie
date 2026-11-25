# Reverie Online Architecture

## Product direction
Primary mode: **co-op exploration**. Secondary mode: **optional PvP**. Story progression remains solo-compatible; friends can join a shared expedition without forcing multiplayer.

## Initial limits
- Co-op party/lobby: 2–4 players.
- One authoritative region instance per lobby.
- Client-predicted movement, server-validated and broadcast to peers.
- Story flags, loot, currency, character ownership and quest rewards remain server-authoritative.
- PvP starts as opt-in friendly duels; ranked is deferred.

## Runtime topology
Godot client → HTTPS API (Fastify) → PostgreSQL.
Godot client → authenticated WSS gateway → lobby/region session coordinator → PostgreSQL event log.

Start as a modular monolith. Add Redis for ephemeral presence, matchmaking and distributed room ownership only when multi-instance load requires it. PostgreSQL remains durable source of truth.

## Modules
- auth: registration, email verification, login, rotating refresh sessions, recovery and revocation.
- players: profile, bootstrap snapshot and cloud-save migration.
- social: friend requests, blocks, invitations and presence.
- world: lobby lifecycle, region instance, authoritative sequence numbers and reconnect snapshots.
- pvp: friendly/ranked queue, deterministic battle events and validated results.
- economy: currency/inventory ledgers; no client-authored grants.
- moderation: block/report/mute and rate limits before public chat.

## Co-op exploration protocol
1. Leader creates a lobby for a supported region; server checks region unlocks and party cap.
2. Friend accepts invite; server verifies friendship, block state and capacity.
3. Server creates a region instance and sends a session-bound snapshot.
4. Clients send input intent/position proposals, not authoritative transforms or reward claims.
5. Server checks movement speed, world bounds, collision/teleport plausibility, region transitions and interaction range.
6. Server assigns monotonically increasing event sequence numbers and broadcasts accepted events.
7. Reconnect uses the last acknowledged sequence; server replays events or sends a fresh snapshot.
8. Quest/reward credit is calculated by server rules and written idempotently.

## PvP protocol
- Explicit queue/duel mode, never a surprise encounter during exploration.
- Server validates roster ownership, equipment, skills, turn order, energy, cooldowns, targets and action sequence.
- Server resolves actions and stores event stream/result hash.
- Client renders the returned event stream; it cannot report its own win or mint rewards/rating.
- First milestone: unranked friendly 1v1. Ranked, teams and rewards wait for balance, anti-cheat and load testing.

## Database additions
backend/migrations/002_online_multiplayer.sql adds presence, 2–4 player co-op lobbies, membership, replayable world events and PvP match records. 003 adds one-time email-verification token storage; 004 adds hashed private invite codes and per-lobby event sequence allocation. The local API now includes lobby create/join/current/leave endpoints and an authenticated WSS relay for position proposals, emotes, acknowledgements and reconnect replay. Godot’s `CoopGateway` autoload now exposes authenticated create/join/current/leave HTTP calls. A node-authored co-op lobby screen is linked after successful sign-in; it supports creating a private four-player expedition, joining by invite code, refreshing membership, viewing party roles/levels, and leaving. It opens the authenticated WebSocket session after lobby creation or joining. Presence heartbeats refresh on client ping; disconnect cleanup waits for the player’s final active socket and then returns presence to `in_lobby` or `online` based on persisted membership. The local PostgreSQL 17 service is now configured and migrations 002–012 have been applied to the development database. The API health check and backend unit/type/build checks pass. Live two-account authentication, co-op transport and PvP transaction flows remain unverified; do not treat the current relay as a production-ready persistent game-server runtime. Movement proposals now pass a dedicated server validation helper: the client includes its active region ID and the server rejects proposals unless it exactly matches the lobby's persisted region; it also checks finite coordinates, a ±100,000-unit safety envelope, and a 650-unit/second speed cap. Previous accepted positions and the 25 ms position throttle are shared across all sockets for the same player/lobby, and the last accepted position is restored from the persisted event snapshot after reconnect. These checks close the easy multi-socket speed-reset path, but the coordinate envelope is only a defensive limit—not the actual region polygon—and map collision, walkability, teleport/region-transition validation still require server-side region geometry. The first gameplay presentation bridge is now in `CoopWorldSyncComponent`: it binds to the active world, proposes the local player position at 10 Hz, consumes connected/snapshot/position/replay events, acknowledges monotonically increasing sequences, and creates/removes presentation-only remote avatars under the world's Entities layer. Remote avatars reuse the existing authored ActorVisual scene and have no collision or camera. This is client presentation plumbing only; it does not make the relay authoritative, provide remote collision, synchronize region changes/interactions/emotes visually, or prove two-client play. The co-op join/leave HTTP routes now broadcast sequenced `player_joined` and `player_left` events to connected lobby peers after the membership transaction commits; the client creates/removes remote avatars immediately and also applies these events during replay. Realtime snapshots now include each member's last persisted position and the lobby's latest event sequence. Overflow resync adopts that snapshot sequence and acknowledges it instead of restarting replay from sequence zero. The WebSocket client now emits a disconnect notification when an established socket closes unexpectedly and attempts up to five reconnects with exponential backoff (1, 2, 4, 8, then 15 seconds). On reconnect it re-sends the local position and resumes from the last acknowledged event sequence; explicit lobby leave disables retries. The lobby UI reports connection loss and returns to its connected state if transport recovers.

## Delivery phases
1. API/auth foundation and migration discipline.
2. Verified account lifecycle, player bootstrap and cloud-save migration.
3. Friends, blocks, presence and invitations.
4. Co-op lobby and region session with movement validation/reconnect.
5. Shared interactions and server-granted quest/reward events.
6. Friendly PvP duel and deterministic server-side combat.
7. Ranked PvP only after abuse, load, privacy and balance gates.

## First-release non-goals
No MMO-scale population, global chat, trading, marketplace, guild wars or ranked PvP at initial launch.


## Authored region envelope validation
The realtime position handler now applies coarse rectangular bounds for the two static regions whose `map_bounds` are explicitly authored in `resources/data/regions.json`: Royal Gardens (`castle_royal_gardens`) and the Gothic Castle boss zone (`gothic_castle_boss_zone`). Proposals outside those rectangles are rejected with `region_bounds`. This is only an envelope check; it does not validate water cells, castle walls, prop footprints, dynamic chunk collision, or navigation connectivity. Other regions without authored map bounds continue to use the global coordinate safety envelope until their geometry is represented in a server-consumable manifest. The bounds are duplicated in the backend movement module for now, so a future content-manifest pipeline should replace this temporary duplication and add parity tests against the source JSON.

## PvP combat-core implementation (development milestone)

A first server-side, scene-independent PvP action resolver now exists at `backend/api/src/world/pvp.ts`. It accepts an already-authoritative match state, an authenticated player action, and a server-owned skillbook, then returns a copied next state plus an ordered event list. It validates active match state, current player turn, monotonic action sequence, actor ownership, equipped skill/ultimate, cooldown, ultimate energy, and ally/enemy target selection. Damage uses deterministic per-match-seed/per-sequence randomness, the same elemental wheel as the Godot combat engine, critical hits, shields, energy gain, status application, healing and shield effects. It never trusts client-submitted stats or result claims.

Unit tests cover turn ownership, actor/skill forgery, stale sequence, invalid targets, ultimate readiness, deterministic replay, healing and elemental advantage. The resolver is now connected to authenticated queue, action, replay and surrender/timeout HTTP routes. Queue pairing loads server-owned party/equipment data and persists the initial battle state and private skillbook; actions lock the match row and persist state plus contiguous events in one transaction. The Godot PvP panel can queue, view the current state, submit actions and surrender. The supported development mode remains unranked friendly 1v1; team skirmish and ranked modes are not enabled. The API and client pass automated checks, but PostgreSQL transaction behavior and two-client battles remain unverified. Do not claim PvP is playable until those gates are complete.

## Co-op synchronization hardening (development milestone)

- Event acknowledgements are now capped by the latest sequence actually allocated by the lobby database. A client cannot pre-acknowledge future events, and acknowledgements remain monotonic.
- Replay cursors are checked against the lobby's latest server sequence and unsafe integer values are rejected before replay queries.
- Lobby creation and movement now require a region ID present in the canonical region manifest; syntactically valid but unknown region IDs cannot create unusable lobbies.
- The backend build step generates isometric spawn positions from each region's `spawn_grid`, using the same 64x32 projection as `IsoMath.grid_to_world`.
- The WebSocket snapshot seeds movement validation from each member's last persisted lobby position, or the canonical region spawn when no lobby position exists. This closes the unvalidated first-packet teleport window.
- The Godot co-op sync component waits for the authoritative snapshot, places the local avatar at the server-provided position, and only then begins sending movement proposals. Large-replay resync snapshots use the same spawn fallback.

Validation: backend typecheck, all unit tests and production TypeScript build pass. Godot 4.7.2 headless editor scan and all six online client smoke tests have since passed on the development machine.


## PvP resolver validation follow-up
The combat core now explicitly classifies `single_ally` and `all_allies` as allied target modes (and `single_enemy` / `all_enemies` as enemy modes). This avoids accidental enemy selection for party-wide support actions. Skill definitions are also checked against their intended target side: healing, shields and buffs require ally targets; damage and debuffs require enemy targets; buffs/debuffs must carry at least one authored status effect. Unit validation now checks equipped skill IDs are non-empty strings. Regression coverage verifies party-wide buffs affect allies and malformed buff/debuff definitions are rejected. Current verification: 22/22 backend unit tests pass and TypeScript typecheck passes; production build passed immediately before this test-only follow-up. These checks strengthen the pure resolver only and do not change the integration gates above.


## Friendly PvP matchmaking reservation (development milestone)
Migration `005_pvp_friendly_queue.sql` adds expiring per-player friendly-duel queue tickets, with a partial unique index preventing multiple waiting tickets for one player. The Fastify API registers `/v1/pvp` routes: authenticated `POST /queue/join`, `POST /queue/leave`, and `GET /queue/status`. Queue pairing is serialized with a PostgreSQL transaction-scoped advisory lock, expires stale waiting tickets, excludes reciprocal block relationships, checks both players for existing queued/active matches, and creates the match plus both team memberships atomically. The server stores a SHA-256 commitment to a random seed; the raw seed is not returned to clients.

Important boundary: a successful pair remains in `pvp_matches.status='queued'`; the API reports `combatReady:false`. There is not yet a server-owned roster loader, persisted battle-state column, action endpoint, event-sequence allocator for PvP, WebSocket delivery/replay, seed reveal lifecycle, timeout/surrender flow, or database integration test. Therefore this milestone implements matchmaking reservations only—not playable PvP. Migration 005 is written but unapplied because PostgreSQL is not configured on the development PC. Verification after this change: 33/33 backend unit tests pass, TypeScript typecheck passes, and production build passes. Queue SQL and transaction behavior still require execution against PostgreSQL before deployment.

## PvP deterministic seed retention follow-up
Migration `006_pvp_seed_storage.sql` adds a server-only 32-byte `server_seed` column with a length constraint. Friendly queue pairing now stores the generated seed alongside its SHA-256 commitment; only the commitment is returned by the queue API. This preserves the material needed for later deterministic battle resolution without exposing the seed to either client. Migration 006 is not applied yet; verify the SQL against PostgreSQL before enabling matchmaking in a deployed environment.

## PvP runtime persistence schema (development milestone)
Migration `007_pvp_runtime_state.sql` adds the durable JSONB combat state, committed state sequence, next event sequence, current turn owner, and optional expiry timestamp to `pvp_matches`. It adds an object-shape constraint and an index for active/queued expiry sweeps. This is schema groundwork only: no API action route writes these fields yet, and no database integration test has run. Before enabling it, migration execution should be validated against PostgreSQL and the runtime state/event writes must be performed in one row-locked transaction with append-only `pvp_events` inserts.


## PvP state/event sequencing primitives
Added `backend/api/src/world/pvp-runtime.ts` with validation that a persisted active state matches its match row ID and committed sequence, plus a contiguous event-batch sequencer that rejects unsafe integer overflow and malformed event payloads. Added focused tests for row/state mismatch, sequence mismatch, completed-state rejection, empty batches, contiguous event IDs and overflow. Verification after these additions: 39/39 backend tests pass, TypeScript typecheck passes, and production build passes. These are tested pure primitives; transactional persistence and replay endpoints are still not implemented.


## Friendly PvP runtime API (development milestone)
The friendly queue now builds both combatants from persisted party/equipment/progression data and stores a server-owned deterministic battle state plus its private skillbook. The initial `match_started` event is persisted before the queue response reports `combatReady:true`. Authenticated `POST /v1/pvp/matches/:matchId/action` locks the match row, validates the JWT player as a participant, resolves the submitted action against the stored skillbook, and commits the next state and contiguous event rows in one transaction. The client cannot submit stats, roster data, skill definitions or a claimed result.

Authenticated `GET /v1/pvp/matches/:matchId/events?after=N` returns an ordered page of at most 200 events, a continuation cursor when `hasMoreEvents` is true, and a sanitized current-state snapshot. `snapshotEventSequence` identifies the last event represented by that snapshot; clients that adopt the snapshot must not replay events at or below that sequence. The seed, skillbook and passive runtime flags remain private. Action and replay endpoints are implemented, but their SQL behavior has not been exercised against PostgreSQL and there has been no two-client end-to-end battle test. Friendly PvP is therefore an API implementation milestone, not a verified playable release. Queue ticket cleanup and terminal status presentation still need follow-up.


## PvP queue terminal lifecycle
Migration `011_pvp_queue_terminal_status.sql` adds a terminal `completed` state to queue tickets. Queue status expires timed-out waiting tickets and marks matched tickets completed or expired when their underlying match reaches a terminal state. Queue join also retires a stale matched ticket before creating a fresh ticket, while preserving active matches and the existing one-waiting-ticket uniqueness rule. This avoids a completed duel leaving a player stuck in a stale `matched` response. The cleanup is request-driven; no per-process background timer is introduced.


## PvP surrender and timeout lifecycle
Participants can concede through the authenticated, rate-limited `POST /v1/pvp/matches/:matchId/surrender` endpoint. The server derives the opposing participant, then transactionally appends surrender and completion events, stores the terminal state/result, clears expiry and closes both queue tickets. Non-participants cannot surrender a match. Action submissions also enforce the match deadline: an overdue match becomes expired with a persisted `match_expired` event, no winner, and terminal queue tickets. This timeout is lazy/request-driven; an external scheduled sweep is still needed to expire abandoned matches when neither player reconnects. PostgreSQL integration and race testing remain outstanding.


## Persistent regional game servers (migration 012)

The intended primary multiplayer topology is persistent regional game servers, not player-created lobbies as the world-hosting model. Migration `012_persistent_game_servers.sql` is applied to the local PostgreSQL database and adds:

- `game_servers`: server identity, region, lifecycle status, optional WSS endpoint, capacity, build version and heartbeat metadata. Server credentials are represented by a unique secret hash, never a plaintext secret.
- `game_server_players`: a durable player-to-server assignment with a unique constraint preventing a player from occupying two persistent servers simultaneously.
- `game_server_world_state`: one revisioned JSONB world-state record per server for crash recovery.

The database foundation and local API directory layer are now implemented. Authenticated registration uses a bootstrap secret and stores only a hash of the generated server token; server heartbeat updates lifecycle state; player discovery lists fresh online servers; player assignments enforce one server per player and capacity under a server-row lock. Server-authenticated world-state load/save is implemented with compare-and-swap revisions (initial save requires revision 0; stale writes return 409). `ServerDirectoryGateway` now exists as a Godot autoload and exposes discovery, join and leave requests; a dedicated smoke test verifies it initializes after authentication. The server directory UI, dedicated world process/host executable, WSS world protocol, live transfer/reconnect orchestration, stale-assignment cleanup and real PostgreSQL-backed server/client integration tests remain outstanding. The existing lobby/WSS relay is still the development co-op transport and is not the persistent game-server runtime. Keep the API bound to localhost until secrets, endpoint ownership, deployment security and integration testing are complete.

## Persistent world cross-process delivery and recovery

Migration `017_persistent_world_connection_leases.sql` adds durable per-socket connection leases referencing the player's server assignment. The WebSocket admission path creates a lease transactionally with single-use ticket redemption; active sockets renew leases every 15 seconds with a 45-second expiry. The database, rather than an individual API process's `rooms` map, is now authoritative for the two-connection limit and delayed disconnect cleanup. Disconnect cleanup locks the assignment, checks active leases and unredeemed tickets, then removes the assignment and appends `player_left` in one transaction to prevent duplicate or missing terminal events.

Persistent-world API processes now maintain a dedicated PostgreSQL `LISTEN reverie_world_events` connection. Committed world events are delivered locally and published with `pg_notify`; other API processes relay notifications to their local sockets. A listener failure causes the API instance to shut down rather than silently continue without cross-process delivery. Since PostgreSQL notifications are transient, clients include their last applied event sequence in periodic heartbeat pings. The server compares it with the durable event cursor and sends `world_sync_hint` when the client is behind; the client then requests bounded replay or reconnects for an authoritative snapshot if history has expired.

Verification on the development machine: migration 017 applied and schema verified; separate Node-process PostgreSQL LISTEN/NOTIFY smoke test passed; backend typecheck passed; all 82 backend tests passed (including five new cursor-reconciliation tests); production build passed; Godot 4.7.2 persistent-world heartbeat/cursor smoke test passed. The same run exposed two stale movement-test expectations after the canonical Royal Gardens map bounds had expanded; those assertions now match the current authored `regions.json` bounds and correctly test the new edge. These checks verify the PostgreSQL notification primitive and client cursor-recovery wiring, not a full two-process/two-client world session. Notifications can still be missed during listener downtime; cursor reconciliation and durable replay are the recovery path. The dedicated regional server executable, actual endpoint deployment, and end-to-end multi-process gameplay test remain outstanding.


## Local persistent-world join-ticket and two-player movement E2E (2026-11-19)

Ran `npm run test:e2e:persistent-world` against the local PostgreSQL 17 database (`127.0.0.1:5432`, database `reverie`) and an ephemeral Fastify/WebSocket listener bound to `127.0.0.1` on an OS-assigned port. No public endpoint or deployment was used.

Result: **25 assertions passed, 0 failed.** The test created two isolated temporary accounts/players, registered a local game server through the bootstrap-authenticated registration route, marked it online through server-token heartbeat, obtained distinct short-lived join tickets for both players, redeemed player A's ticket through the server REST admission route, rejected REST ticket replay, issued a fresh reconnect ticket, and admitted both players through the actual persistent-world WebSocket ticket handshake. Both authoritative snapshots contained both players. Each player moved and the other received the sequenced position event; both positions were confirmed in PostgreSQL. An implausible movement jump was rejected without changing persisted position. The durable event log was replayed in sequence order, and reuse of player B's already-redeemed WebSocket ticket was rejected.

Cleanup was verified separately against PostgreSQL: `test_servers=0`, `test_accounts=0`. The test harness closed both sockets and its ephemeral local API listener. This validates local API/WebSocket ticket admission and two-player position relay against PostgreSQL; it does **not** validate a standalone regional Godot server executable, separate API process fanout during gameplay, visual in-game movement, or public deployment. No public deployment was performed.


## Two-process persistent-world gameplay verification (2026-11-19)

Extended `backend/api/scripts/persistent-world-e2e.mjs` to launch a second, independent Node.js API process (`persistent-world-e2e-worker.mjs`) on a separate ephemeral localhost port. Each player connects to a different process, with each process maintaining its own WebSocket peer map and its own dedicated PostgreSQL LISTEN connection. This makes the movement assertions exercise actual PostgreSQL NOTIFY cross-process fanout rather than two sockets in one process.

Latest run: **26 assertions passed, 0 failed; E2E_EXIT=0.** The full join-ticket lifecycle, replay rejection, reconnect ticket, simultaneous two-player snapshots, bidirectional movement delivery across the two API processes, PostgreSQL position persistence, movement validation, durable event replay and consumed-ticket reuse rejection all passed. The test runner now forcibly terminates its disposable worker after closing test sockets, then removes its temporary server and test accounts. A separate PostgreSQL cleanup verification returned `test_servers=0`, `test_accounts=0`.

All listeners bind only to `127.0.0.1` on ephemeral ports. No public deployment was performed. This is a two-process API relay test, not a standalone regional Godot dedicated-server test or an in-game visual movement test.


## Dedicated Godot regional transport bind smoke (2026-11-20)

Strengthened `tests/online_dedicated_server_smoke.gd` so it no longer only inspects method names: it instantiates the dedicated-server scene in an isolated transport-test mode, starts the real `TCPServer` listener on `127.0.0.1:19087`, asserts the socket is listening, then stops it and asserts clean closure. Test mode deliberately skips registration/heartbeat HTTP calls, so no server record or secret is needed. `_start_transport()` now avoids heartbeat/save timers in this isolated mode.

Godot 4.7.2 headless run result: `[online_dedicated_server_smoke] PASS`. The run also printed existing missing `.godot/imported` audio-cache/preload errors from the project's `AudioDirector` autoload; these did not prevent the dedicated transport smoke from passing, but the import-cache issue should be cleaned up separately. This verifies actual local TCP bind/close only; full WebSocket ticket admission, authenticated production startup, TLS termination, authoritative gameplay, and standalone process deployment are still unverified. No server was registered or exposed publicly.


## Dedicated server event sequencing and bounded replay (2026-11-20)

The standalone Godot regional server now speaks the persistent-world client's ordered-event contract: it allocates monotonically increasing sequence numbers for player join/leave, position and emote events; includes the current cursor in `world_joined`; reports `world_sync_hint` when a heartbeat cursor is behind; and handles bounded `replay_request` messages with `replay_complete` or `world_resync_required` when the cursor is ahead/outside the retained window. The most recent 200 events are retained in the server process memory. The current sequence number is included in periodic world-state saves so a fresh authoritative snapshot after restart can resume a monotonic cursor. The event history itself is intentionally not written into the 12 KB world-state document; replay history is therefore process-local and clients must accept a fresh snapshot after restart or replay-window loss.

`online_dedicated_server_smoke.gd` now asserts the event allocator/history and sync-hint wiring in addition to opening and closing the real localhost TCP listener. Godot 4.7.2 headless run: `[online_dedicated_server_smoke] PASS`. Existing missing imported audio cache warnings appeared again because `.godot/imported` assets were not yet regenerated; an editor import/scan was started separately. This is not yet a full standalone-server/client E2E test: TLS, real join-ticket admission against this Godot process, persistence restart, and visual gameplay remain unverified.


Follow-up in the same session: Godot's editor import scan regenerated the missing `.godot/imported` audio caches. The dedicated-server smoke was rerun and passed without the previous AudioDirector preload errors. That clean run exposed a real content-data issue: Greenward contained two identical `greenward_to_royal_gardens` connections. Removed the duplicate entry from `resources/data/regions.json`; ContentDB then loaded all 45 characters, 46 skills, 11 enemies and 17 items without the duplicate-connection error, and the dedicated-server transport smoke passed again.

## Dedicated Godot WebSocket interoperability smoke (2026-11-20)

- Expanded `tests/online_dedicated_server_smoke.gd` from a TCP bind-only check to a real loopback WebSocket client/server exchange.
- The Godot 4.7.2 test now starts the dedicated listener, completes a WebSocket handshake, receives the `ticket_required` challenge, submits a malformed ticket, and confirms the server closes that admission attempt.
- The same test checks the monotonic event cursor and retained replay event, then closes the listener cleanly.
- Result: `[online_dedicated_server_smoke] PASS — live WebSocket handshake, challenge, and invalid-ticket close`.
- ContentDB loaded 45 characters, 46 skills, 11 enemies, and 17 items during the run. This is a local transport smoke only: it does not prove real ticket redemption, authenticated two-player movement, or deployment.

### Dedicated-runtime integration gap still open

- The standalone Godot dedicated process currently maintains its own in-memory 200-event replay buffer and periodically persists only the world-state cursor/positions through the game-server REST API.
- The PostgreSQL durable event log, connection leases, and cross-process LISTEN/NOTIFY path currently belong to the separate API-hosted `/v1/world/realtime` WebSocket implementation. The standalone Godot socket does not yet append/replay through that durable event path or renew connection leases.
- Therefore the earlier API-hosted two-player E2E does not prove the standalone Godot dedicated runtime has equivalent crash recovery or multi-process event delivery. Do not describe those guarantees as active on the standalone server until the two paths are unified and tested.
- Next integration target: make the standalone server's admission, lease renewal/release, event append/replay, and disconnect cleanup use the same durable PostgreSQL lifecycle before running a full two-client Godot E2E.


## Unified dedicated Godot server persistence (2026-11-20)

**The standalone Godot runtime gap described above is now closed in the local development build.** The dedicated process uses the same PostgreSQL event log and connection-lease lifecycle as the API-hosted world transport; it no longer treats its in-memory 200-event buffer as the source of replay truth.

- Ticket redemption now supplies a UUID connection ID to the server-authenticated `consume-ticket` endpoint. The API creates the lease in the same transaction that consumes the one-time ticket. Godot renews each live lease every 15 seconds and releases it on socket close; failed renewals close the peer. Orphaned admission responses release their lease as well.
- Dedicated-server join, position and emote events are sent through the existing idempotent `POST /v1/game-servers/:serverId/events` endpoint. Each event has a stable UUID idempotency key; a retry returns the original committed sequence instead of adding a duplicate. Position state and the event row are committed together. PostgreSQL `NOTIFY reverie_world_events` fans the committed event out to API-hosted WebSocket peers in other API processes.
- Startup recovery reads the durable event cursor and event page from PostgreSQL. If the retained page cannot cover the requested cursor, the API returns an authoritative position snapshot. Client replay requests also read the durable event endpoint; the process-local history is now only a bounded convenience cache/test-mode buffer, not the replay authority. The replay API reads cursor, event page and fallback positions in one repeatable-read transaction so concurrent appends cannot create a false sequence gap.
- Player disconnect cleanup is lease-aware. It refuses to remove an assignment while a live connection lease or unredeemed ticket exists; after those are gone, it removes the player assignment and saved position and appends `player_left` atomically. The API-hosted WebSocket cleanup uses the same position-row removal so departed players do not reappear in fallback recovery snapshots.

**End-to-end verification:** the local PostgreSQL 17 E2E suite now reports **57 passed, 0 failed**. It launches the actual Godot 4.7.2 headless dedicated-server executable, registers it against the local API, admits two real WebSocket clients with one-time tickets, verifies durable leases, exchanges bidirectional movement, checks PostgreSQL event rows and cross-process notification delivery, requests replay, stops the Godot process, starts it again under the same server identity, reconnects both players, and verifies that their positions and original event sequence are reconstructed from PostgreSQL. It also checks that disconnect is blocked while a lease is active and that disconnected positions are removed from recovery snapshots. The E2E cleanup verification reports zero temporary servers, accounts, tickets, positions, events and connections.

Latest backend regression verification: **82/82 unit tests passed**, TypeScript typecheck and production build were run after the API changes. Godot 4.7.2 editor validation was clean, and `online_dedicated_server_smoke.gd` passed with live local WebSocket handshake, ticket challenge, malformed-ticket rejection, UUID event-ID checks, and durable replay/lease source assertions.

**Scope still limited:** this is verified on the local Windows development PC and local PostgreSQL database only. No public deployment, production TLS/WSS termination, multi-region failover, or two independent Godot dedicated-server processes sharing one region was performed. The API-hosted WebSocket cross-process fanout is covered by the E2E test; the dedicated Godot server remains one process per registered server identity. The older “Dedicated-runtime integration gap still open” section above records the earlier state and is superseded by this milestone.


### Unified dedicated runtime — final lifecycle and overflow regression (2026-11-20)

The final rerun supersedes the earlier 57-check count above: **65/65 end-to-end assertions passed** with exit code 0 and verified cleanup. The real Godot server remained connected long enough for its 15-second lease-renewal timer to fire; the test confirmed lease expiry moved forward, then closed both player sockets and confirmed both lease rows were released before restarting the process. The test also appended 205 additional durable events, forced the replay cursor beyond the 200-event page, verified the server returned a bounded replay response plus an authoritative position snapshot, restarted Godot, and confirmed both players' positions were restored from PostgreSQL. A later replay from the recovered cursor returned the latest committed sequence. Event-ID retries with identical content return the original sequence; reusing an ID with different content is rejected.

The final code also normalizes transaction lock order across server ticket admission, position writes, event appends, and disconnect cleanup to reduce deadlock risk. Latest backend verification: **82/82 unit tests passed**, TypeScript typecheck exit code 0, production build exit code 0. The Godot dedicated-server smoke remains passing. Everything was exercised against the local PostgreSQL database and localhost-only processes; no public deployment was performed.
