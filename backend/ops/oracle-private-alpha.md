# Oracle Always Free private alpha — deployment checklist

Status: preparation only; no cloud instance created, no production traffic enabled.

## Provisioning
- Oracle Always Free: VM.Standard.A1.Flex, 2 OCPU, 12 GB memory, 50 GB boot disk (verify current free eligibility in console before creating).
- Ubuntu 24.04 LTS ARM64 if offered for the shape. Use the actual account home region; availability is not guaranteed. Do not upgrade to paid resources.
- Use a dedicated SSH key; keep the private key on the operator PC outside the repository. Restrict SSH ingress to authorized operator addresses; no public PostgreSQL, raw API port, or developer routes.
- Start with a private Tailscale test network, then review HTTPS/WSS and invite-only admission before any broader exposure. Keep Stripe test mode disabled for the alpha until reviewed.

## Application readiness
- Node.js 22+ and PostgreSQL 16+; install native dependencies on ARM64 with npm ci from backend/api, regenerate region bounds and build.
- Use a Linux ARM64 Godot executable matching project runtime version. Set REVERIE_STORY_GODOT to its absolute path. Verify headless story-combat worker and dedicated region runtime on the actual architecture; do not assume Windows binaries work.
- Create a separate database and run the base schema and migrations in filename order on disposable staging first. Check dependencies where migration numbers are reused. Restore an encrypted backup only after an explicit decision to carry over existing players; never run disposable QA against the live database.
- Generate fresh deployment JWT, database, and server-bootstrap secrets locally on the VM; never copy the development .env or expose credentials. Configure production mode, loopback API listener and appropriate rate-limit namespace.
- Current production registration requires email verification but lacks delivery. Implement and test controlled alpha enrollment or real email verification before players can register; do not bypass verification with development mode on a public endpoint.
- For a private alpha, keep administrative routes behind the private network. For any later public endpoint, configure a trusted reverse proxy, HTTPS/WSS, forward-header replacement, no retry of ambiguous writes, and explicit developer-route blocking; review existing reverie-nginx.conf.example rather than publishing it unchanged.
- Configure systemd supervision, backups and retention; verify restoration and readiness checks. Keep local PC and existing data untouched during staging.
- Configure player clients with the verified remote HTTPS endpoint (default currently points to loopback). Test two physical devices, auth, chat, co-op, progression, combat, disconnect/reconnect and restricted administrative routes before sharing the alpha.

## Release gate
No public exposure until staging passes and the owner approves the selected data migration/enrollment approach. Free-tier capacity and idle reclamation remain provider constraints. A private test using the existing Tailscale-connected PC is the fallback if provisioning is delayed.