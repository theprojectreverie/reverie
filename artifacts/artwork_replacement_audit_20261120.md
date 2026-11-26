# Reverie artwork integration audit
Date: 2026-11-20
Project: `project-fantasy`
Purpose: identify remaining code-drawn substitutes and protect already-integrated authored art.

## Confirmed authored artwork already integrated

### Royal Gardens — live playable scene
- `scenes/world/castle_royal_gardens.tscn` uses the bespoke palace asset from `assets/reverie_custom/royal_gardens/production/grand_royal_palace.png`.
- The active terrain renderer is the serialized `TileMapLayer` assembly in `scenes/world/castle_gardens/components/royal_garden_isometric_layers_baked.tscn`.
- `castle_terrain_configuration.tscn` already sets `metadata/use_baked_tilemap = true`. The geometric runtime ground and detail layers are disabled by `CastleTerrainComponent`. This is already integrated; do not redo it.
- The active terrain is composed from 32x32 atlas art on 64x32 isometric cells, with separate ground, path/water and vegetation tilesets.
- The clean layout has 34 authored Sprite2D placements, ten textured cobblestone road modules, and the approved palace sprite.
- 45 imported grass-to-cobble edge sprites exist but are intentionally hidden pending a proper continuous border layout.

### Battle HUD — live playable scene
- `combat_bottom_hud.tscn` already uses six authored TextureButton assets: attack, skill, ultimate, defend, item and end turn.
- `combat_layout_component.gd` applies authored StyleBoxTexture panels for active-character info, party roster, skills and battle log.
- Authored HP/energy meter fills, meter tracks, turn-order track, status icons, skill icons and boss status artwork are already referenced by the live HUD.
- `combat_screen_backdrop.tscn` uses the authored moonlit royal garden background; encounter layout switches the selected backdrop by enemy group.
- Do not replace these working authored UI elements with new code-drawn alternatives.

### Playable character sheets
- Exactly three `world_sheet.tres` resources were found under `assets/characters`: Gerald, Lilith and Kael Avatar.
- `MainCharacterRoster` routes Gerald/Lilith and Kael to their playable world-sheet paths.
- Player avatar selection and battlefield player rendering both use `SpriteFramesActorSource.register_playable()`; preserve this pipeline.
- Kael's existing integration is covered by the test runner and exposes 72 animations.

### Other authored environment assets
- Act I landmark artwork exists for the royal palace, royal gate, willow windmill, ancient tree, forsaken arch and ruined tower.
- Royal Gardens has bespoke architecture, foliage, props, fences, cobblestone ribbons and terrain atlas art.

## Confirmed remaining art gaps

1. **Generic NPCs** — `WorldNPC` calls `visual.configure_character(npc_id)`. Named NPC IDs such as `elder_maelin`, `merchant_sera`, `wanderer_pip`, `castle_guard_left`, `castle_guard_right` and `garden_visitor` do not have matching world-sheet resources. They fall back to procedural actor rendering.
2. **Ordinary enemies** — `BattlefieldActor` currently leaves non-player combatants on the procedural monster renderer. The enemy art folder contains the Fallen Matron's three phase illustrations, but not a full matching SpriteFrames set for the ordinary enemy roster.
3. **Generic character visual effects** — some actor VFX and secondary effects remain code-composed. Replace their visual shapes with authored sprite/particle resources where they are visible; keep animation timing and gameplay signals.
4. **Act I macro-world structure** — `scenes/world/act1_world_structure.tscn` contains Polygon2D/Line2D continent silhouettes, biome ground, coastline, rivers and road shapes alongside authored landmark sprites. A project-wide reference search found no scene/script reference to this file, so it is not confirmed to be part of the live playable route. Treat it as an unreferenced composition/preview asset until its intended use is established; do not alter it as if it were the active game world.

## Verified checks on 2026-11-20

- `tests/castle_garden_clean_layout_smoke.gd`: PASS — one authored palace, 34 garden sprites, ten authored road modules; exit code 0.
- `tests/castle_garden_component_smoke.gd`: PASS — 194 connected route cells; player spawn clearance in 4/4 directions; four clear promenade samples; three solid fountain bases; camera offset/zoom/world limits; baked terrain coverage; terrain draw order; eight fence collision segments; clean NPC roster; open Royal Gate road; 34 authored garden sprites and ten authored road modules; exit code 0.
- Logs are stored alongside this audit in `artifacts/castle_garden_clean_layout_smoke_20261120.log` and `artifacts/castle_garden_component_smoke_20261120.log`.

## Implementation order

1. Create and integrate authored pixel-art SpriteFrames for ordinary enemies, beginning with one representative enemy and validating its appearance before expanding to the roster.
2. Create matching authored SpriteFrames for named NPCs; do not map unrelated existing playable characters onto NPC identities merely to suppress the procedural fallback.
3. Replace remaining visible code-drawn character/VFX shapes with actual imported artwork and Godot animation/particle resources.
4. Revisit Act I macro-world structure only after confirming whether it belongs in the live playable scene; if used, replace its flat polygon/line art with a coherent authored 32x32 terrain/tilemap and retain navigation/collision separately.
5. Keep battle HUD and Royal Gardens authored-art integration intact.

## Hard constraints

- No new GDScript-drawn characters, creatures, buildings, terrain, UI skins or decorative artwork.
- GDScript may manage resource loading, SpriteFrames, AnimationPlayer, particles, collision, depth sorting, navigation, input, networking and gameplay.
- Never substitute an unrelated character sprite merely to hide a procedural fallback.
- Preserve imported source art, backups, save data, combat math and multiplayer logic.
- Back up scene/resource files before modifications; run focused Godot smoke tests after each integration.
- Do not claim an asset is integrated until the live scene references it and a test or rendered capture verifies it.

## 2026-11-20 — Mossling Walk Preview Pass 04 (Desktop Commander)

- Extracted `Reverie_Mossling_Walk_Preview_Pass_04.zip` from Downloads into `assets/enemies/mossling/walk_pass_04/`; earlier source and idle passes were preserved.
- Verified sprite PNG: 576×1024 RGBA, alpha range 0–255, arranged as 6 columns × 8 direction rows of 96×128 cells.
- Corrected malformed AtlasTexture subresource IDs in the supplied Godot SpriteFrames resource and corrected its staged-folder resource paths.
- Godot 4.7.2 headless editor import completed the first filesystem scan.
- Godot 4.7.2 headless preview-scene load completed with exit code 0 and no resource parse/texture-loader errors:
  `res://assets/enemies/mossling/walk_pass_04/mossling_walk_preview.tscn`
- Preview contains 8 looping directional walk animations (`walk_0`–`walk_7`) at 12 FPS, 6 frames each.
- STATUS: staged preview successfully loads in Godot; NOT registered as a production enemy source. Production WALK requires 16 frames per direction and the complete 9-state × 8-direction animation contract remains outstanding. Live enemy renderer unchanged.


## 2026-11-20 — Mossling production contract and renderer trace (Desktop Commander)

### Authoritative animation contract confirmed
`CharacterAnimationSpecCatalog` is the source of truth. Direction order is down, down-right, right, up-right, up, up-left, left, down-left. Production requires 9 states × 8 directions (72 animations):

| State | Frames | FPS | Loop |
|---|---:|---:|---|
| idle | 5 | 9 | yes |
| walk | 16 | 12 | yes |
| run | 16 | 16 | yes |
| interact | 6 | 12 | no |
| attack | 6 | 15 | no |
| damage | 2 | 12 | no |
| victory | 8 | 12 | no |
| defeat | 6 | 10 | no |
| cast | 7 | 12 | no |

Each frame must be a non-null 96×128 texture. `SpriteFramesActorSource.validate_sheets()` checks all 72 animations, frame counts, loop flags and frame dimensions. Incomplete sheets must remain unregistered.

### Live renderer trace
`EnemyVisualComponent.configure_enemy()` creates/configures the shared `ActorVisual` and calls `configure_character(enemy_id)`. `ActorSpriteComponent.configure_character()` currently asks `SpriteFramesActorSource.register_playable(character_id)` for a complete source; if it cannot validate a complete sheet, the procedural fallback stays active. The current production lookup is character-roster/world-sheet oriented, while Mossling art is staged under `assets/enemies/mossling/`.

### Current Mossling status
- Pass 01: 8-direction static concept atlas only.
- Pass 02: 4 idle frames per direction; production requires 5.
- Pass 04: 6 walk frames per direction; production requires 16.
- No complete 72-animation SpriteFrames source exists in the staged Mossling folder.
- No renderer registration, live enemy replacement, or combat integration was performed. This is intentional: the current previews fail the authoritative contract.

### Integration requirements before production switch
1. Create genuinely authored frames for all 72 animation/direction combinations using the original Mossling design and palette.
2. Slice each frame to 96×128, build a Godot SpriteFrames resource with exact state names (`<state>_<direction-index>`), FPS and loop settings.
3. Add an explicit enemy-art registration path (or extend the existing registry without changing playable-character lookup semantics) so `mossling` resolves to its enemy art folder.
4. Run `validate_sheets()` and require zero errors; then run a live enemy spawn/combat visual test to confirm fallback is disabled only for Mossling and remains intact for all other enemies.

No production code or live renderer behavior was changed in this audit pass.


## 2026-11-20 — Enemy-specific SpriteFrames registration seam added (Desktop Commander)

### Changes made
- `scripts/art/sprite_frames_actor_source.gd`: added `from_enemy()` and `register_enemy()` using `res://assets/enemies/<id>/world_sheet.tres` (or `.png` detection). This is separate from the playable-character roster path.
- `scripts/world/components/actor_sprite_component.gd`: added `configure_enemy_character()` and shared strict validation helper. The helper only calls `set_frame_source()` when the source has frames and `validate_sheets()` returns no errors.
- `scripts/world/actor_visual.gd`: exposed `configure_enemy_art()` as the enemy-specific API.
- `scripts/enemies/components/enemy_visual.gd`: enemy spawning now calls `configure_enemy_art(enemy_id)` rather than `configure_character(enemy_id)`.

### Safety behavior
- Missing/incomplete enemy art leaves the existing procedural fallback active.
- Playable-character registration remains on its existing `configure_character()` path.
- Existing enemy palette, scale, accents, naming and spawn setup were not intentionally changed.
- No live Mossling sheet was installed and no enemy art was falsely marked complete.

### Verification status
- All four targeted file edits returned successful Desktop Commander edit results.
- A fresh headless Godot project boot could not be verified in this pass: the PowerShell launch returned a parser error unrelated to the edited GDScript, and the alternate `cmd` launch failed before Godot started due to command-path quoting. Do not mark this change runtime-tested until a clean Godot launch is run.


### Enemy art registration smoke test — PASS
- Added `tests/enemy_art_registration_smoke.gd`.
- Ran Godot 4.7.2 headless with `--script res://tests/enemy_art_registration_smoke.gd`.
- Result: exit 0. Verified enemy lookup isolation, missing Mossling art rejection, fallback retention, and no accidental enemy-folder resolution through the playable registration path.
- Log: `artifacts/enemy_art_registration_smoke_20261120.log`.
- This validates the registration seam and safety behavior only; it does not claim that the full game boot or a production Mossling art sheet has been validated.


### Enemy art reporting API extended — PASS
- Added `SpriteFramesActorSource.enemy_validation_report(enemy_id)` to report the dedicated enemy `world_sheet.tres` / `.png` paths, disk presence, frame validation, animation count, registration and fallback status without consulting playable-character registries.
- Extended `tests/enemy_art_registration_smoke.gd` to assert the exact Mossling enemy resource path.
- Re-ran Godot 4.7.2 headless smoke test: PASS, exit 0. Log refreshed at `artifacts/enemy_art_registration_smoke_20261120.log`.


### Existing enemy lifecycle regression — PASS
- Ran `res://tests/region_monster_battle_lifecycle_smoke.tscn` in Godot 4.7.2 headless after switching EnemyVisualComponent to `configure_enemy_art()`.
- Result: exit 0. Existing battle retreat/cooldown, victory/defeat/respawn, and unrelated battle-event isolation checks all passed.
- Log: `artifacts/enemy_visual_lifecycle_smoke_20261120.log`.
- This confirms the enemy visual registration change did not break the tested region-monster battle lifecycle. It is not a complete visual art acceptance test.


### Live Mossling enemy-visual integration smoke — PASS
- Added `tests/mossling_enemy_visual_integration_smoke.gd` and `.tscn` using the actual `scenes/world/roaming_monster.tscn` and its authored EnemyVisual / ActorVisual nodes.
- Configured a Mossling definition through `EnemyVisualComponent.configure_enemy()` and verified the enemy ID reaches ActorVisual, fallback remains temporary and active, no incomplete frame sprite is activated, and the authored name label is configured.
- Godot 4.7.2 headless result: PASS, exit 0.
- Log: `artifacts/mossling_enemy_visual_integration_retry_20261120.log`.
- Note: an initial direct-script attempt was invalid because the monster script references project autoloads; the corrected scene-based test loads project autoloads and passed. An earlier abandoned test process was terminated by exact PID before retry.
