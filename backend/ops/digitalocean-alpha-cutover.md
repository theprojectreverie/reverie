# Reverie DigitalOcean alpha cutover

Status: cloud staging is online; full production-like alpha cutover is not complete.

## Target
- Existing Frankfurt DigitalOcean Droplet, 512 MB tier. Do not purchase or resize before the two-account acceptance gate.
- Public client origin: https://reverie-staging-fra1.tailad29fa.ts.net:8443
- Public co-op: wss://reverie-staging-fra1.tailad29fa.ts.net:8443/v1/realtime
- Main project public connection profile and alpha dashboard target this origin.
- Local developer presets are isolated development tools, not public hosting or fallback.
- Tailscale Funnel runs on the Droplet, not on player devices or the developer PC.
- Keep the API, PostgreSQL, admin/payment routes and internal server APIs private.

## Release gates (not yet completed)
1. Prepare an immutable Linux release from the latest reviewed source, including runtime game content and schema migrations. Preserve the existing web-static gateway wrapper; the generic gameplay gateway alone does not serve the web build. Check dependency vulnerabilities and preserve patched cloud dependencies.
2. Verify disk capacity, compatible Linux headless Godot runtime, project imports, and actual worker preflight. Start with REVERIE_STORY_WORKER_CONCURRENCY=1 and test batching against latency, RSS and swap usage. Never substitute a client-authored combat outcome if the worker fails.
3. Use explicit open registration configuration consistently on API and gateway: REVERIE_ALPHA_REGISTRATION_MODE=open, REVERIE_ALPHA_SIGNUPS_ENABLED=1. Keep password protection and quota limits. Review production authentication, email ownership verification/recovery and trusted-proxy configuration; do not claim unverified email addresses are verified. Existing invite-mode defaults are intentional fail-closed behavior until coordinated deployment.
4. Back up the existing cloud DB and verify restore to an isolated database. Owner authorized a fresh start, not deletion of game content. Initialize a clean schema and required reference data; do not copy local player rows. Validate starting wallet and character grants.
5. Stage cloud API and game worker, run two distinct synthetic accounts through real registration, login/refresh, tutorial, summons, battles, account isolation, persistent rewards, friend requests, chat, co-op movement/combat and disconnect/reconnect. Verify no payment/admin exposure.
6. Dedicated persistent world remains a separate gated integration: verify regional process, join ticket/admission, movement validation, progression, reconnect and safe TLS routing. Do not flip public feature flags or expose server registration/bootstrap routes simply to make the button appear.
7. Deploy matching Android, Windows and web releases only after validation. Check the built endpoints, signing identity, compatibility and download sizes. Retain a recoverable prior deployment and do not replace the current public release with a broken candidate.
8. Verify externally with two actual devices while the developer PC and its old hosting services are offline. Confirm both accounts progress and retain data, and measure CPU, RAM, disk and response time. Only then consider the 2 GB plan.

## Current evidence
- Existing cloud API, PostgreSQL, gateway and public health/browser routes were verified online.
- The main public connection profile is cloud-only; Godot smoke test tests/cloud_connection_profile_smoke.gd.
- Local API baseline: 193 tests passing before latest changes.
- Local open-registration gateway E2E and one-worker combat preflight passed.
- Linux runtime, latest cloud deployment, clean database cutover, dedicated world and full physical two-account test are not verified. No live reset or subscription change performed.