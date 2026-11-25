# Battle Visual Integration QA

## Installed visual assets

The battle art under `assets/ui/battle` is now consumed by the playable combat screen. Background selection is centralized in `BattlefieldLayoutComponent.battle_background_path_for_group()` and shared by the screen backdrop and the battlefield stage.

| Encounter / region | Active background |
|---|---|
| Royal Gardens encounters | `moonlit_royal_garden.png` |
| Gothic Castle / Royal Road encounters | `frozen_castle_courtyard.png` |
| Forsaken Ruins / Ruined Tower encounters | `crimson_castle_ruins.png` |
| Hollowed Guardian encounter | `crimson_castle_ruins.png` |
| Baltoria encounter | `gothic_cathedral_hall.png` |
| Elder Hollow | Existing Greenward boss backdrop |
| Fallen Matron | Existing Withered Estate backdrop |
| Other Greenward encounters | Existing Greenward battle backdrop |

Both the full-screen backdrop and the arena's `ArenaArtBackdrop` use the same encounter selection. Existing Greenward and Fallen Matron scenes remain as fallbacks for their established encounters.

## Battle action controls

The six authored PNG button designs are referenced directly by `combat_bottom_hud.tscn`:

- **Attack** shows the character's damaging abilities.
- **Skill** shows support and utility abilities.
- **Ultimate** shows the character's ultimate and charging/availability state.
- **Defend** is a real combat action: it halves incoming damage until that character's next turn.
- **Item** is present, but reports that no usable battle consumables are currently available. It does not deduct inventory.
- **End Turn** advances the active character's turn.

The HUD applies disabled, active, hover and keyboard-focus feedback. An action lock blocks repeat skill, Defend and End Turn inputs while its event presentation resolves.

## Verification

Run the focused visual integration test:

```powershell
Godot --headless --path . res://tests/battle_visual_assets_smoke.tscn
```

Latest results:

- Battle visual integration: **79 passed, 0 failed**
- Combat screen runtime smoke: **PASS**
- Audio integration smoke: **38 passed, 0 failed**
- Content validator: **OK — 9 content files plus main characters**

The battle visual smoke test is also included in `.github/workflows/ci.yml` before the audio and automated test steps.

## Current scope note

The Item control is deliberately informational until a consumable-in-battle inventory flow exists. It should be connected to a real inventory transaction before battle item use is advertised as implemented.
