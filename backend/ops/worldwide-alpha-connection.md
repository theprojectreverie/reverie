# Reverie worldwide alpha connection template

Public origin: https://reverie.tailad29fa.ts.net:8443
Public health: /health
Co-op WebSocket: wss://reverie.tailad29fa.ts.net:8443/v1/realtime
Client source of truth: scripts/online/connection_profile.gd
Export feature: reverie_public_alpha (separate Windows and Android presets)

## Network boundaries
- PostgreSQL: localhost:5432 only; SCRAM authentication.
- Fastify: 127.0.0.1:8787; private Tailscale Serve port 443 only.
- Restricted gateway: 127.0.0.1:8791; Tailscale Funnel HTTPS port 8443.
- Status-only fallback: 127.0.0.1:8790. No database, admin, payment, or server-to-server routes on public gateway.
- No router forwarding. Keep the PC awake and connected. No secrets in exported clients.

## Startup and recovery
From backend/api, build with npm run build (or local tsc -p tsconfig.json). Start node --env-file=.env dist/server.js and node scripts/alpha-gameplay-gateway.mjs as separate local processes. Start node scripts/public-alpha-gateway.mjs for fallback. Check listeners before starting duplicate processes.
Verify /health on 8787, 8790, 8791, then tailscale funnel status. Only after tests pass: tailscale funnel --bg --https=8443 http://127.0.0.1:8791. Never point Funnel at 8787. Emergency closure: tailscale funnel --bg --https=8443 http://127.0.0.1:8790; verify gameplayOpen=false externally. Private port 443 remains unchanged.

## Release verification
Run node --env-file=.env --import tsx scripts/alpha-gameplay-gateway-e2e.mjs and node --env-file=.env scripts/alpha-live-tunnel-e2e.mjs. Tests create disposable users and remove them. Check public admin/payment/internal routes return 404, unauthenticated wallet 401, and health 200. Verify physical devices from different networks before claiming remote gameplay readiness.

## Enrollment and builds
Use node --env-file=.env scripts/issue-alpha-invite.mjs 1 to issue a private single-use invitation (seven days; initial total 20 enrollments, not a concurrency guarantee). Never publish invitation codes or signing secrets. Export using Reverie Alpha Windows or Reverie Alpha Android. Android release signing requires a permanent private key outside the repository. Debug APK is QA-only. Keep development presets local. Email ownership not verified; advise unique passwords. Persistent regional worlds and paid purchases are not exposed in this alpha. No automatic failover or uptime guarantee.

## Developer dashboard alpha monitoring
Enable PUBLIC_ALPHA_MONITOR_ENABLED=1 on this deployment only. The private /developer page shows Worldwide alpha gateway under Online gameplay infrastructure. Local and public health checks use fixed origins, a 3.5-second timeout, and 15-second cache. Public health is a host-origin observation; independent-device tests remain necessary. Counts include active public co-op sockets on this API process, distinct connected players, recently present enrolled accounts, and invitation allocation. Issuance limit is 20, not a tested concurrency limit. The dashboard remains private on tailnet Serve port 443; the public Funnel must return 404 for admin and payment routes. The UI is read-only; invitation issuance and emergency closure continue to use the existing documented operator procedures.