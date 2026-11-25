# Local backend test evidence

- `persistent-world-e2e.log` is the two-player local PostgreSQL + two-independent-API-process join-ticket/WebSocket movement run.
- `unit-tests.log` records the API unit suite.
- `typecheck.log` and `build.log` record the TypeScript verification steps.
- Run the full persistent-world integration test locally with `npm run test:e2e:persistent-world`. The script refuses non-loopback PostgreSQL targets and removes its temporary test server and player accounts.
