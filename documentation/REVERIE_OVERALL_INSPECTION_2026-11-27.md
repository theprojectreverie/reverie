# Reverie Online — Overall Inspection

Date: 2026-11-27  
Scope: local project, Godot 4.7.2, backend API and available local multiplayer tooling. This report records verified checks and explicit release blockers; it is not a claim of physical-device or public-service certification.

## Result

**Not release-certified.** The local automated suite, backend checks, selected gameplay regressions, and local eight-player reconnect E2E passed. Mobile performance on device, public/live multiplayer, full interactive gameplay walkthrough, complete manual whole-map visual inspection, and clean resource-lifecycle certification remain unverified or blocked as detailed below.

## Verified checks

- Godot project test runner: **2,807 passed, 0 failed**. Runner snapshots/restores local game state and save data.
- Backend API suite: **184 passed, 0 failed**; TypeScript typecheck passed; production build passed.
- Content validation: **9 content files plus main characters validated**.
- Focused regressions: battle visual assets **345 passed, 0 failed**; audio integration **38 passed, 0 failed**; chat emotes/layout passed; mobile graphics settings passed; mobile touch smoke passed its headless input checks.
- Story combat regressions passed: Cassien art, co-op art, HUD, retry, resurrection/progression; balance sample **96/100 wins, mean 15.02 actions**.
- Local online E2E: eight concurrent players joined through the local API/WebSocket and dedicated Godot server, persisted positions, disconnected, reconnected with exact positions, and recovered after regional server restart. Transport retries: **0**. Cleanup verified zero test servers, accounts, tickets, positions, events, and connections.
- Royal Gate patrol local E2E: both patrol objectives progressed, duplicate reward claim was rejected, and Willow Fields completion proof persisted.
- Pearl City route regression: **10,007 tiles**, **8/8 routes**, **874 navigation samples**, **0 blocked/missing route samples**, **8 stalls**, **11 shops**, safe arrival. Gate threshold alignment smoke: **18/18**.
- Export smoke completed and generated a **654,459,324-byte (~624 MiB)** PCK. The temporary PCK was removed after inspection. Backup folders are excluded from export, and `.gdignore` markers stop the editor from indexing copied backup scenes and creating duplicate UID warnings.
- A verbose standalone game-scene shutdown rerun exited successfully with no leak diagnostic in captured output; a prior non-verbose `--quit-after` run emitted **4 ObjectDB instances / 1 resource still in use**. That discrepancy leaves runtime shutdown clean-up inconclusive.

## Defects and corrections made during this audit

- Updated the Royal Gate backend test fixture to include the Mirène encounter proof required by current encounter-admission logic; added a negative assertion that missing proof is rejected. Backend suite now passes without weakening progression rules.
- Updated stale published test counts in `README.md`, `documentation/TESTING.md`, and `backend/api/README.md`.
- Added empty `.gdignore` markers for `artifacts/` and `backups/`, and added `backups/**` to all five export preset exclusion filters. The follow-up export scan no longer reported duplicate scene UID warnings.
- Pearl City gate/floor alignment is preserved at the approved landing position and covered by its focused threshold test.

## BlueStacks Android smoke inspection (2026-11-27)

- A fresh QA-only APK (unique package `com.projectfantasy.qa.audit20261127`) installed and launched in BlueStacks. The installed image is Android 9, x86_64, reported as device model SM-G998B; configured display 1920×1080 at 240 dpi. The visible app ran in landscape and reached the title screen/settings.
- The in-game graphics menu exposed three quality choices; Balanced was selected in the QA-only app. Starting a new journey opened sign-in. A one-off direct Zone 2 launch build also returned to the title menu after a clean force-stop, so it did not bypass startup. No account was created and no credentials were entered; a map walkthrough, touch movement, combat or zone transitions could not be exercised in this session.
- Android `dumpsys meminfo` reported app-process PSS totals between **121,472 and 133,079 KiB** across title-screen observations (about 118.6–130.0 MiB). These are emulator process figures, not physical-device memory measurements and not GPU texture memory.
- `dumpsys gfxinfo` did not expose the Godot surface's rendered-frame stream; SurfaceFlinger latency output returned only a vsync interval. No valid game FPS or frame-time percentile was therefore obtained. BlueStacks is an emulator and cannot substitute for physical Android measurements.
- A distinct x86_64+ARM64 debug APK was used for installation; project settings and export presets were restored after each temporary build. The temporary QA package and APK artifacts were removed after inspection.
## Outstanding findings and blockers

- **Editor export lifecycle:** verbose export shutdown reports **6 ObjectDB instances and 3 resources still in use**, naming `pixelpen_state.gd`, the bundled GIF `exporter.gd` and `median_cut.gd`, with orphan StringNames `last_color_table`, `current_project`, and `load_project`. These trace into the enabled third-party PixelPen editor plugin. No addon changes were made because safe ownership/cleanup behavior has not been established. Fix and rerun export before treating clean shutdown as certified.
- **Mobile:** no `adb` device or emulator is available. Touch and graphics settings received headless logic checks only. No honest FPS, frame-time percentile, memory, texture-memory, load-time, background/resume, or physical-device result is available.
- **Online:** the local API/Postgres/dedicated-server E2E passed, but no public/live production server or real remote client accounts were available. Obstacle collision authority, latency behavior on an actual connection, and production reconnect/zone-transfer synchronization are not certified by local simulation.
- **Visual/gameplay walkthrough:** automated checks cover portions of scene rendering, movement, quest progression, and transitions. A human-style full-map review of every district at gameplay and overview zoom, animation-state occlusion review, input-device walkthrough, save/logout/reconnect walkthrough in the game client, and visual before/after capture set were not completed in this audit. The gate alignment has a regression assertion but no new in-engine before/after evidence attached.
- **Packaging:** the PCK is approximately 624 MiB. This is a substantial mobile download/storage risk. No asset was removed or newly excluded based only on size; a reference-aware asset audit and target platform packaging review are needed.
- **Release scope:** tests report the baseline totals, but not every original RV-Z02-FINAL acceptance check (for example all 281 anchors / 544 movement checks / 610 render checks / 31 gateways) was rerun as a single certified matrix during this overall audit. Treat those historical baseline counts as context, not new evidence.

## Files changed by this audit

- `backend/api/test/story-royal-gate.test.ts`
- `README.md`
- `documentation/TESTING.md`
- `backend/api/README.md`
- `export_presets.cfg`
- `artifacts/.gdignore`
- `backups/.gdignore`
- This report

The repository already had a broad dirty working tree before these audit changes. No reset, stash, or whole-tree replacement was performed. Other modified files remain outside this report's audit-specific change list.

## Release-readiness verdict

**Hold for further verification.** Local correctness evidence is strong, including backend progression and local eight-player reconnect. Do not mark the overall game or Pearl City milestone release-ready until the PixelPen export leak is resolved or isolated, mobile performance is measured on a target, online behavior is checked against the supported live environment, and the remaining visual/gameplay walkthrough is recorded.
