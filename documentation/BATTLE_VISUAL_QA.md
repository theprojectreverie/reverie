# Reverie — Battle Visual Integration & QA

## Integrated assets

The authored battle art pack is installed under `res://assets/ui/battle/`.

### Encounter backgrounds

`BattlefieldLayoutComponent.battle_background_path_for_group()` selects the battle image from the encounter group. The selected texture is applied to both `CombatScreenBackdrop/BattleArt` and `Battlefield/ArenaArtBackdrop`, so the full battle UI and the actor stage share one scene.

| Encounter group | Background |
|---|---|
| `castle_garden_sentinels` | `moonlit_royal_garden.png` |
| `royal_road_ambush`, `withered_grove_pack`, `fallen_aqueduct_sentinels` | `frozen_castle_courtyard.png` |
| `baltoria_encounter` | `gothic_cathedral_hall.png` |
| `corrupted_treant` | `crimson_castle_ruins.png` |
| `glade_mossling_pack`, `thornhound_hunt`, `fae_ambush`, `elder_hollow`, `moonpetal_sprite_pack`, `moonpetal_echoes_pack` | Existing `greenward_battle.svg` |
| `fallen_matron_encounter` | Existing `withered_estate_battle.svg` |

### Action buttons

All six cropped button assets are assigned as textures in `scenes/ui/combat/components/combat_bottom_hud.tscn`. The action selector uses a three-column grid and keeps the source image aspect ratios.

- **Attack** filters the current character's abilities to damage skills.
- **Skill** filters to non-damage support and utility skills.
- **Ultimate** opens the character's ultimate ability entry; the skill itself remains disabled until its energy requirement is met.
- **Defend** is a real combat action. It halves incoming direct damage until the character's next turn begins, then advances initiative.
- **Item** is visibly present but currently reports that no usable battle consumables are available. There is no battle-item use system to call yet, so it does not consume a turn or inventory.
- **End Turn** advances initiative without using a skill.

Selected categories are shown at full brightness, inactive categories are muted, hover/focus is tinted gold, and unavailable buttons are dimmed. The six controls receive confirm/hover audio through `AudioDirector`.

### Layout

The battle bottom HUD was checked in a 1280×720 SubViewport. The Active Info, Party Roster, Skills and Battle Log panels fit horizontally; the bottom HUD stays inside the authored 16px safe margin, including a four-row party roster.
### Meter, portrait and initiative art

The combined meter and turn-order sheets were split into independent imported textures, with the original sheets preserved:

- `meters/sliced/hp_red_fill.png`
- `meters/sliced/energy_violet_fill.png`
- `meters/sliced/meter_empty_track.png`
- `icons/sliced/turn_order_track.png`

Player HP uses the red meter, energy uses the violet meter, and the boss health bar uses the red meter over the shared empty track. The initiative panel uses the 533×57 authored six-diamond strip. Six fixed slot containers keep the active portrait centered over the highlighted second diamond; excess turns are summarized in the last slot.

The original round and tall portrait frames had opaque centers that obscured the character art. Transparent-center overlays were created from those frames, preserving the roses and metallic edges:

- `panels/sliced/portrait_frame_round_overlay.png`
- `panels/sliced/portrait_frame_tall_overlay.png`

The initiative strip uses the round overlay; the party roster uses the tall overlay. The roster thumbnails and panel padding were compacted so a four-member party fits the fixed 180px bottom HUD at 1280×720.
### Combat-event and result panels

The timed combat-event banner is now an authored `PanelContainer` using `panels/battle_dialogue_panel.png` as a nine-slice frame. Boss-phase announcements use centered title text over that frame and retain the existing fade-in / hold / fade-out timing.

The Victory and Defeat result overlay panels use the same dialogue artwork for visual consistency. Victory retains its gold title and reward/claim layout; Defeat retains its red title and Retry/Retreat layout. This changes presentation only: reward calculation, result claiming and combat state are not modified. A transparent gold crown flourish, cropped from the supplied ornate divider sheet, sits above both result titles as a small accent.
### Dedicated boss encounter opener

Boss enemies now use an authored `boss_intro_banner.tscn` instead of the standard short text banner. The composition combines:

- `panels/sliced/boss_emblem_crest.png`, cropped from the glowing ornate emblem frame
- `banners/royal_banner.png`, displayed as a narrow side standard
- `panels/battle_dialogue_panel.png`, used as the nine-slice backing panel

The boss name is bound from the active `Combatant.display_name`; the opener is shown only when the enemy group contains a boss. It fades and scales in, holds briefly, fades out, and queues itself for deletion. Non-boss encounters continue to use their ordinary title flow; the smoke test explicitly checks this for Royal Road Ambush. The boss HP/phase UI and combat rules are unchanged.

### Boss-specific phase transitions

The live combat screen now mounts the existing `BossPresentationRig` and routes boss HP-threshold phase events through it. The event payload includes the boss ID/name, zero-based phase index and the displayed phase number. The battle begins at Phase 1; the first and second thresholds enter Phase 2 and Phase 3 respectively.

The rig selects the presentation profile by boss identity:

- `elder_hollow` and `corrupted_treant`: roots treatment, using the transparent illustrated asset `assets/ui/battle/boss/elder_hollow_root_crest.png` (384×192) and a green accent. The same image is used in the phase panel, boss telegraph and impact. The former geometric Elder sigil nodes have been removed from the telegraph and impact scenes.
- `fallen_matron`: bloom/corruption treatment, using the supplied rose-and-crest artwork from `panels/sliced/boss_emblem_crest.png` and a violet-magenta accent.

Both transitions use the battle dialogue nine-slice frame, the actual message from the combat event, a boss/phase identifier line, and a short fade/scale transition. Phase identity labels are specific to the encounter: Elder Hollow Awakening/Fury, Hollowed Guardian Heartwood Break/Roots Unbound, and Fallen Matron Corruption/Descent. A FIFO phase-cue queue preserves every transition when one hit crosses multiple HP thresholds; event processing waits for each cue before advancing. Non-boss phase messages retain the ordinary banner fallback. No HP thresholds, phase statuses, damage, turn order or other combat rules were changed.

### Skill-family icon crops

The five framed cells in `skills/skill_icons_row.png` were separated into standalone 104×128 textures under `skills/sliced/`:

- `general_strike.png`
- `support_bloom.png`
- `control_chain.png`
- `dark_arcane.png`
- `fire_burst.png`

Combat skill cards show one of these icons beside their existing skill name, element, kind, power and energy/cooldown text. Selection uses `SkillDef` metadata in this order:

1. A control/debuff effect (`poison`, `blind`, `def_down`, `spd_down`, `stun`, `atk_down`) selects the chain.
2. Healing, buff and shield skills select the bloom, including fire- or dark-element support skills.
3. Remaining Fire damage selects the fire burst.
4. Remaining Dark damage selects the arcane orb.
5. Other damage skills use the general strike.

The icons are decorative identifiers only; they do not change targeting, damage, status application or skill availability.
### Status-effect icon crops

The eight symbols in `icons/status_effect_icons.png` were cropped into individual 62×44 (final radiant crop 65×44) PNGs under `icons/status/`. The active-character panel uses the exact symbol matches supported by current combat status IDs:

| Status ID | Cropped symbol |
|---|---|
| `atk_up`, `atk_down` | Crossed swords / attack modifier |
| `def_up`, `def_down`, `shield` | Shield |
| `regen` | Healing cross |
| `poison` | Droplet |
| `stun` | Lightning |
| `spd_down` | Hourglass / slow |

Down-effects are tinted red; each icon tooltip includes the status name and remaining turns. A separate shield icon shows remaining shield HP. `blind`, `burn` and `spd_up` have no unambiguous matching symbol in the supplied sheet, so they remain in the existing text status line. The snowflake and radiant crops remain available as unused source art rather than being assigned to unrelated effects.

## Verification

Run from the project root with Godot 4.7.2:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/battle_visual_assets_smoke.tscn
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/combat_screen_runtime_smoke.tscn
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/audio_integration_smoke.tscn
```

Latest local results:

- Battle visual integration: **174 passed, 0 failed**
- Combat screen runtime: **PASS**
- Audio integration: **38 passed, 0 failed**
- Main game scene smoke: **exit code 0** (shutdown logs 2 ObjectDB instances / 1 resource still in use)

The battle visual smoke is also included in `.github/workflows/ci.yml` before the audio and main regression suites.

The latest editor import scan reports zero GDScript parse errors and no Pixel Pen extension errors. The main game scene smoke exits with code 0, although Godot still reports 2 ObjectDB instances / 1 resource in use during headless shutdown.

## Remaining limitation

The Item button is intentionally a non-consuming informational state until battle consumables are implemented. The decorative source sheet and unassigned supporting crops are retained as source material; they are not treated as live combat controls.
