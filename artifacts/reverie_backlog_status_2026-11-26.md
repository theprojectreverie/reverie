# Reverie backlog status — 26 November 2026

This report records work completed in this pass, evidence available in the workspace, and tasks that still need devices, live account access, production infrastructure, or approved artwork. The original Nov 26 integration changes were already present and uncommitted when this pass began; they were preserved. No commit or release was created for the fixes below.

## Completed or verified in this pass

- Fixed the west pond water zone in Royal Gardens. It now matches the pond tiles, blocks water cells, and leaves the authored bypass dry. The physics test traversed both pond routes in both directions; water slowdown, dry-ground recovery, diagonal speed normalization (226.7 px/s for cardinal and diagonal), and camera follow all passed.
- Fixed the ordinary HUD quest tracker fallback when a six-zone navigation resolver has no chapter objective. Repaired stale opening-cinematic and quest-flow QA fixtures so they load authored scenes and wait for async completion. Added orderly audio/world cleanup to the pond, touch-control, quest-flow, and opening QA checks.
- Fresh Godot regression suite: **2,754 passed, 0 failed**. Log: `artifacts/qa/current-local-regression-2026-11-26.log`.
- Content validation passed. Backend suite passed **154/154**; TypeScript typecheck and production build passed.
- Focused opening replay, quest progression, quest navigation, Royal Gate collision, touch-control, audio (38 checks), and battle visual-asset (327 checks) QA passed. These are automated/headless checks and do not replace rendered or device QA.
- The local Android resource audit passed on APK 0.2.5. The Kael sequence is packaged with all 12 approved shots; Nov 26 Android screenshots show it playing. `jarsigner` verified the APK signature.
- Exported a fresh debug QA APK from this worktree to [the temporary QA build](<C:/Users/quoth/AppData/Local/Temp/Reverie-local-QA-d98a3d46af744eeb9ac0ac5f5338415b.apk>); it includes these local fixes, signs and verifies successfully, and passes the same APK resource audit. It is 382,087,945 bytes. No tablet was attached, so it could not be installed or run on hardware. The Godot exporter also emitted object/resource cleanup warnings at shutdown.
- GitHub published prerelease [v0.2.5-online-alpha.20261126](https://github.com/theprojectreverie/reverie/releases/tag/v0.2.5-online-alpha.20261126), with a 380,268,842-byte APK. Its published SHA-256 matches the local APK: `68e73e0c32858f5b894c471600f86b76f888353c3ff7c7fb044e30afe74d495d`. This is a prerelease publication, not proof of Play Store publication or permanent key custody.
- GitHub Actions CI passed on committed revision `efc69f7c163bd2f6922ee18f25c5635d4963f50e` ([run](https://github.com/theprojectreverie/reverie/actions/runs/45797174246)). The local fixes and other uncommitted changes are not included in that CI run.
- Current public HTTPS `/health` and the local API/database health checks responded successfully. Existing Nov 26 local E2E logs also report successful gameplay-gateway, chat, guild, summon, daily-claim, story-combat, and co-op flows. They do not establish geographically independent or production-scale service.

## Unfinished work

### 🔴 Release blockers

- **Mobile release acceptance:** install and play on Galaxy Tab S6 and Tab A8; verify touchscreen movement/combat, readable scaling, friend acceptance, login, update installation, and retained accounts/progress on the devices. `adb` is installed, but `adb devices -l` found no attached devices. Full Android-to-Godot feature parity also remains a release-level review; the APK audit checks package resources, not every feature end to end.
- **Permanent multiplayer service:** move from the current workstation/Tailscale alpha to durable hosting; production API/database, HTTPS/WSS and reviewed proxy/load balancing; persistent process supervision, regional ownership/state, safe WebSocket failover, shared production rate limits and regional scaling; verify residential IP remains private. Runbook: `backend/ops/oracle-private-alpha.md` says no cloud VM or production traffic has been provisioned. The live alpha gateway is not permanent hosting.
- **Worldwide multiplayer acceptance:** test from separate geographic networks, keep a long-duration multi-region load run, and test reconnect, cross-instance chat/moderation, larger combat parties, and server recovery. A local 100-player regional test does not cover these checks. The Nov 26 mobile friend E2E artifact failed to connect from this environment; therefore physical-device acceptance remains open.
- **Chapter 1 completion:** complete a beginning-to-end playthrough and verify tutorial → village → Royal Gardens, Gerald/Lilith unlocks, all story-boss authoritative battles/rewards, Gerald’s cinematics, Cassien’s ritual and Ravienna’s resurrection/transformation, travel to Zone 6, ending, and persistence. Current focused tests cover selected quest flows and story pilots, not the full chapter.
- **Live purchases:** perform an actual Stripe test-mode Checkout and verify signed webhook delivery, Moonstone grant, cancellation/failure, duplicate protection, refund/dispute handling. The existing `stripe-sandbox-e2e.mjs` uses a mocked provider and cannot count as a genuine Stripe payment. The local test webhook secret is blank and Stripe CLI reported unauthenticated. An automatic command review rejected an attempt to start a temporary local webhook listener/API; its response gave no more specific reason. I stopped there and did not create a checkout session.
- **Production backup and recovery:** install unattended encrypted backups, independent offsite copies, separately retained permanent encryption keys and production retention; perform a production-sized isolated restore and full-host failure drill. Synthetic restore evidence exists, but no production backup schedule/storage/key custody is in place.
- **Public release requirements:** confirm permanent signing-key custody, update delivery, closed-alpha distribution, privacy policy and terms on a public site, support/bug-report intake, final acceptance testing, and paid-purchase disclosures. Company/contact details and legal review are needed before publishing policy documents.
- **Android billing policy:** no Play Billing integration was verified. For Play distribution, virtual currency and digital goods generally require Google Play Billing unless Reverie qualifies for and enrolls in an applicable alternative-billing program. Paid randomized items need odds shown before and near the purchase. [Google Play payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en).
- **Rating review:** paid random items may affect the age rating. PEGI announced rating changes for some games with paid random items beginning October 2026; review Reverie’s actual mechanics and markets with the rating authority before release. [PEGI notice](https://pegi.info/index.php/uk/node/103).

### 🟠 Important integration and operations work

- Complete map collision/boundary, transitions/spawns, and visual/gameplay inspection across Training Grounds, Village, Royal Gardens, Royal Gate, Willow Fields, Elderwood Grove, Forsaken Ruins, and Ruined Tower. The west pond and Royal Gate collision checks passed; this is not a full map audit. Zone 6 castle interior/exterior, roads/corners, terrain conversion, Cassien access, occlusion, backgrounds, minimaps, and environmental performance need review.
- Verify secure progression on separate devices: paid-pull guarantee and counter, wallet/ownership synchronization, offline bypass protection, every upgrade/ascension recipe, banner persistence, historical summon compensation, and Mythic couple perks. Existing local tests cover several of these, not release/device acceptance.
- Complete the remaining chapter journal/navigation checks; test daily notification/reset once in production, weekly/monthly boundaries, season settlement, reward persistence, and Hall of Fame pagination under live conditions.
- Complete production/social acceptance for private-message notifications, pagination/offline delivery, portraits matching ownership, Android stickers/emoji, chat load and cross-instance moderation. Local chat/social tests pass but do not replace independent-device tests.
- Consolidate release-level guild/PvP coverage: leadership and permissions, treasury/raid security and rewards, league settlement, competition balance, independent matchmaking, disconnect/reconnect, abuse checks and heavy-load sessions.
- Activate real monitoring across API instances, external outage/uptime alerts, production moderation/suspension/appeals, financial audit/refund workflows, and finish the admin dashboard layout.
- Profile real mobile FPS/RAM/battery, long-session memory, loading/transition times, texture size and installation size; inspect audio on actual gameplay/Android and balance soundtrack/effects. The current APK is about 380 MB (down from the earlier 613 MB build), but remains large. Automated audio smoke passed; listening QA remains open.
- Reconcile `README.md` and operational docs with the current online-alpha architecture and current feature state. The current full CI run belongs to the committed revision, not the uncommitted working tree.

## Unavailable checks for a later device/account session

- Physical S6/A8 input, readability, update/account retention, real performance, and friend acceptance.
- Hands-on, start-to-finish story playthrough and visual/cinematic inspection; listening to all music/SFX during gameplay.
- A genuine Stripe Checkout plus webhook forwarding. Current CLI is unauthenticated, webhook secret is not configured, and the local attempt to start a listener was automatically rejected.
- The headless `qa_village_gameplay.tscn` runner did not exit within its 60-second guard, so it provided no village gameplay result. Village flow still needs a valid focused run or manual playthrough.
- Independent geographic player testing, real production load, cross-instance failure/recovery, and external uptime monitoring.
- Production database restore/failure exercise and backup-key custody.
- Business/legal publication details, Play Console access, Android billing product setup, policy declarations, and final PEGI rating decision.

## Image-generation / approved-artwork tasks for the separate art pass

Use the approved character designs and supplied references; do not replace these with generic code-generated art.

- Cassien and Ravienna eight-direction overworld animation sets.
- Elathra dedicated attack, ultimate, defeat, and reaction animations.
- Ravienna dedicated casting and surrender animations.
- Remaining full-body character-selector art and summon-card illustrations, including approved Mirène, Crimson Witch, and other roster designs.
- Remove backgrounds from approved JPEG character illustrations and prepare the remaining approved art for integration.
- Additional character-specific combat effects and consistency review for sprite proportions/animation.

These artwork tasks need their approved source designs and a separate image/animation production pass; they were not generated here.
