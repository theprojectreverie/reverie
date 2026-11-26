# Same-host multi-instance deployment candidate

This is a deployment candidate, not an installed service. The development
PC does not have nginx installed. The nginx example requires operator
review, real certificate paths, hostname, nginx -t and a staged deployment.

## Preconditions
- Apply all required migrations, including 061_shared_rate_limits.sql.
- Use the same database, JWT signing secret and SHARED_RATE_LIMIT_NAMESPACE
  on both instances. Use distinct OPERATIONAL_HISTORY_INSTANCE_ID values.
- Bind both APIs to 127.0.0.1 (example ports 8787 and 8788). Do not expose
  these ports to the internet. Budget PostgreSQL connections: 12 per API
  pool, including its persistent-world listener.
- TRUST_LOCAL_REVERSE_PROXY=1 enables exactly one trusted loopback proxy
  hop. Default is off, including production; prior deployments relying on
  automatic trust must explicitly review and configure forwarding. Never
  enable it on a listener reachable by untrusted local forwarding services.
- The proxy must replace X-Forwarded-For/Proto/Host rather than append
  untrusted input. If a CDN or other proxy is added, review the trusted
  client identity chain separately.
- Run /ready directly from the local host, without forwarding headers;
  the public proxy blocks it. It checks database connectivity and the
  shared quota table when configured. It is not a full dependency probe.
- Use the existing regional Godot endpoints separately; do not send
  dedicated-server WebSockets to the HTTP API pool.

## Routing and failure behavior
Ordinary HTTP requests may use either API instance. The nginx example
pins both /v1/realtime and /v1/world/realtime to 8787 because expedition
room state, timers and some connection admission state remain process-local.
Do not automatically fail these paths over while the primary may still
be alive. A primary outage interrupts these socket services. Reconnect
behavior must be tested before an operator switches the designated primary.

No proxy retry of ambiguous mutations. nginx passive failure detection is
not a substitute for an active health-check service. The first HTTP request
to a failed upstream can receive an error; the client must handle it.
The local test harness models explicit worker health, not nginx passive
failure detection. The production example has not been executed.

## Validation
From backend/api:
  node --env-file=.env --import tsx scripts/proxy-deployment-e2e.mjs
  node --env-file=.env --import tsx scripts/shared-rate-limit-e2e.mjs
  node node_modules/typescript/bin/tsc --noEmit -p tsconfig.json

The first test uses two independent Fastify child processes, a loopback
reference HTTP proxy and a synthetic authenticated pinned WebSocket.
It tests real shared PostgreSQL quota persistence, forwarding spoof
rejection and survival of the second HTTP worker. It does not validate
nginx syntax, production TLS or live co-op room migration.

Release gates: actual nginx staging and TLS checks; readiness-aware
supervision; cross-instance room/admission review; full real client
reconnect and mutation/idempotency testing; sustained load and rollback
drill. Do not enable production traffic before these gates pass.
