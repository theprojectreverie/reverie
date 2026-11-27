# Live content phase 1: scheduled summon banners

Status: local implementation. Deploy the API and one compatible signed client before relying on this feature in the public alpha.

The authenticated summon state includes `bannerCatalog`. The Godot summon screen refreshes it when opened and while visible. New scheduled banners use existing bundled character IDs, portraits and a validated existing banner template. The server selects the active catalog using its UTC clock, never the device clock. A new `live_` banner requires the exact catalog revision in a pull; a changed or expired banner cannot debit currency. Existing committed requests replay before the schedule check. Historical live pulls record their banner definition. All old bundled banners, fusion recipes, and guarantees remain unchanged.

## Operator workflow (local server)

Save a draft JSON outside the source tree. Example (replace UTC dates for the intended event):

```json
{"schema":1,"banners":[{"id":"live_cassien_weekend_01","name":"Crimson Weekend","subtitle":"Limited event summon","template":"crimson_oath","featured":"cassien_legendary","startsAt":"2026-12-04T00:00:00Z","endsAt":"2026-12-07T00:00:00Z"}]}
```

From `backend/api`:

```sh
node --import tsx scripts/publish-live-banners.mjs draft.json --preview
node --import tsx scripts/publish-live-banners.mjs draft.json --publish
```

Preview validates without writing. Publish atomically replaces the server-local manifest at `backend/api/live-content/banners.json` (or `REVERIE_LIVE_BANNERS_FILE`). Keep every existing row unchanged when appending a new unique ID; the tool refuses to reuse or remove historical IDs. At most two live banners can overlap. One operator must publish at a time. For multiple API processes, use a shared manifest path and synchronized UTC clocks. Back up this manifest with operational configuration. Invalid manifests fail closed. No server restart is necessary for subsequent valid publications.

Phase 1 uses ordinary crystals only for live banners; public paid summons remain disabled. Paid live-banner support requires historical compensation verification first. No custom rates, prices, arbitrary resources, executable code, new character IDs or new asset download endpoints are accepted. The Live Content Manager is now integrated into the existing owner dashboard. Emergency cancellation, rollback, arbitrary gameplay events, new character definitions and animation downloads remain later phases. No new public banner is published by this change.

## QA

- `node --import tsx --test test/live-banners.test.ts`
- `node --env-file=.env --import tsx scripts/live-banners-e2e.mjs`
- Set `QA_GODOT` to the local Godot executable, then `node --env-file=.env --import tsx scripts/live-banner-client-e2e.mjs`.

The E2E tests use disposable local accounts and isolated temporary manifest files. They do not publish live content or debit real player accounts.

## Live Content Manager

The existing `/developer` dashboard exposes the owner-only panel after sign-in. The admin access gate and bearer-token checks remain required; activity-only staff cannot publish. Load the catalog, select an existing rules template and featured Legendary, enter UTC start/end dates, optionally upload artwork, preview the exact draft, then explicitly confirm publication. Published IDs and schedules are immutable; owner identity and publication time are stored server-side. No automatic currency grants occur at publication.

Artwork upload accepts PNG/JPEG through the browser, scales to at most 768 px, and sends a bounded PNG. The server validates PNG framing, CRC, pixel format, decompression bounds and SHA-256, strips ancillary metadata, and stores an immutable digest-addressed PNG. Only artwork referenced by an active published banner is served by the player API. Godot verifies bytes against the catalog hash, decodes only bounded PNGs, and caches a limited number of textures plus one verified local file. Existing bundled art remains the fallback. No remote code, scenes, scripts or executable resource packs are loaded.

The initial live event type is a one-time login reward (gold up to 10,000 or crystals up to 500; at most three overlapping events). Events appear in the summon screen, with a claim button. A claim is authenticated and serialized in the player transaction; currency ledger entry is the receipt, and a retry cannot credit twice. Expired events cannot create new claims. An already committed claim can be replayed. Paid currency, character grants, custom combat quests and event shops are not supported by this event type.

Storage: `backend/api/live-content/` or `REVERIE_LIVE_CONTENT_DIR`, with `banners.json`, `events.json`, and `artwork/`. The optional `REVERIE_LIVE_BANNERS_FILE` overrides banner location. Keep all content and audit metadata in backups; don't commit live manifests or artwork uploads. A shared filesystem lock coordinates CLI and dashboard publication; resolve stale locks only after verifying no active writer. Configure shared storage before running multiple API instances. This is an alpha filesystem-based publisher; disaster recovery and operational rollback tooling still need development.

Deployment requires updated API, admin gateway, gameplay gateway and one compatible signed Android client. No real event/banner was published during QA. The test is `node --env-file=.env --import tsx scripts/live-content-manager-e2e.mjs` (set QA_GODOT to exercise Godot). The test isolates manifests and uses disposable accounts.

## Revision controls and seasonal quests

The owner dashboard now exposes emergency cancellation, prior-revision rollback and crystal-only rate/price edits for scheduled live banners (not bundled banners). Every change appends a timestamped owner/reason record. Changes use expected revision numbers to prevent lost updates. Rollback copies an earlier state into a new revision; it does not delete history, change schedule/ID, or undo completed player transactions. A cancellation stops new admissions after the server reads the new manifest; already admitted operations may finish. Existing committed request IDs replay normally. Expired content is not reopened. Reinstating cancelled content revalidates simultaneous-event limits. Max 50 revisions per entry; manifest size is bounded before writes.

Economics use integer basis points totaling 10,000. Legendary 1–15%, Mythic 0.1–5%, featured 10–100%; crystal single 1–1,200, ten-pull cost at least a single and at most 10 singles. No paid currency changes, guarantee changes, fusion changes or arbitrary pools. Client displays two decimal places and submits the catalog revision. New requests with stale revisions are rejected without spending.

Seasonal quests can now require 1–30 verified story victories from a selected repeatable Royal Gardens/Royal Gate encounter or all supported encounters. Only completed, settled, server-produced terminal victory records with actions, started and finished within the event window count. Existing login reward events remain compatible. No client-reported win counters, new battle instances, event shops or custom enemies yet. The QA checks isolated proof fixtures and the reward endpoint, not a live seasonal battle playthrough. New downloadable character definitions and animation delivery remain separate work. Deployment still pending.

The first event shop supports one immutable material offer per event, up to 10 units, priced in ordinary gold/crystals. Eligible material IDs are Moonpetal, Glade Sap, Dew of Awakening, Hollow Heart, Gothic Shard, Blight Resin and Royal Seal. Battle objectives must be completed before purchase; login events are eligible while active. Each player can purchase once. Wallet debit, inventory grant and receipt are committed in one transaction. Existing purchases survive cancellation/rollback, while new purchases are denied during cancellation/expiry. The Godot purchase confirmation uses the exact immutable offer. No event-specific currency or multiple offers yet.

Character asset staging accepts original, unscaled authored PNGs (RGBA 128 px grid, bounded dimensions, up to 64 frames, 1–24 FPS) through the existing owner artwork upload. A draft can describe an animation update to an existing character or a new candidate based on a known legendary/mythic template. The validator checks identity, unique slots, frame count, atlas dimensions, hashes and required portrait for new candidates. Staging is private and immutable; missing slots are reported. It does not grant a character, add it to summon pools, or replace any world/combat resources. Next: authenticated runtime sprite atlas delivery, per-character resource binding, complete server combat/progression/fusion definitions and compatible client capability gating before activation. Never download executable scripts or arbitrary Godot resource packs.

## Downloadable playable character packs (alpha pilot)

Compatible clients poll the authenticated character-content catalog during normal account roster refresh (30-second throttle). The owner stages a JSON draft with seven animation slots (`idle`, `basic_attack`, `skill_1`, `skill_2`, `ultimate`, `hit`, `defeat`), original 128×128 RGBA cell atlases (up to 8×8 cells, 1 MB per PNG, total 3 million animation pixels per pack), frame counts, FPS and source facing direction (`left` or `right`). Existing original left-facing artwork is mirrored by the authored combat sprite node when deployed on the left. Optional `heightCm` sets non-canonical character proportions; canonical character heights are preserved. The client verifies every digest and atlas dimension, assembles SpriteFrames from original pixels, and atomically installs the complete catalog; failed downloads retain prior validated art. No remote code executes. Existing battles retain their selected SpriteFrames instance. A compatible client can update artwork on a later catalog refresh without APK changes. Replacements require the expected previous revision; prior published draft records are retained. Definitions of an acquired character are immutable.

New-character publication is disabled by default (`REVERIE_LIVE_NEW_CHARACTERS_PILOT=1` explicitly enables the pilot). A complete new draft requires a unique `livechar_` identity, portrait, seven clips and an existing Legendary template with a matching Mythic variant. The server creates an immutable pair with the supplied name/title/lore and existing supported skills, stats and passives; both aspects share the approved artwork for now. It creates unique Rare/Epic upgrade cards (20 and 10), Legendary-to-Mythic fusion (7), and Mythic ascension progress (7). Publish a separate scheduled live banner featuring the new Legendary. Compatible clients advertise support; older clients cannot see the new banner or initiate new pulls from it. Owned definitions are downloaded before roster use. Server-side summon, skill upgrade, party selection, story reward settlement, story/guild worker replay, and PvP roster construction resolve published definitions. The worker receives trusted server-sourced definitions, not client stats. Never delete a published character definition or its asset files from storage while players can own it.

Current pilot limits: four concurrently published character packs, twenty pack publication records, shared art across the two rarities, existing skill templates, and combat animations only (no downloadable world movement sets or new executable mechanics). New public activation requires updated API/gateways, a compatible signed APK, physical mobile QA and a compatible-client rollout for multiplayer; full mixed-version PvP/co-op matches were not tested. Do not set the pilot flag on the public server yet. The test creates disposable accounts and uses an isolated content directory; no real character is published. Existing known Godot shutdown resource warnings can appear in headless QA.
