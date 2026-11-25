# Reverie SFX Integration & QA

Date: 2026-11-20  
Project: project-fantasy (Godot 4.7.2)

## Integration

All ten generated MP3 files are installed in assets/audio/sfx/ and preloaded by the existing AudioDirector autoload. One-shot playback uses an eight-player pool on the existing SFX bus. Music and SFX remain independently controllable through Settings.

| Asset | Runtime event | Playback gain |
|---|---|---:|
| ui_crystal_click.mp3 | Default button press | −4 dB |
| ui_crystal_hover.mp3 | Button hover | −10 dB |
| ui_confirm_select.mp3 | Combat skill buttons | −3 dB |
| ui_panel_open.mp3 | Shared overlay opens | −3 dB |
| ui_panel_close.mp3 | Shared overlay closes | −4 dB |
| inventory_equip.mp3 | Successful equipment change | −1 dB |
| summon_ritual_ambience.mp3 | Summoning cinematic ambience | −10 dB |
| summon_reveal.mp3 | Transition from opening video to rarity reveal | −2 dB |
| spell_cast.mp3 | Magic, healing, guard and ultimate actions | −4 dB |
| frozen_hall_wind_loop.mp3 | Gothic Castle region ambience | −8 dB |

The two ambience cues use a separate looping player. Changing ambience fades the prior bed down, starts the new loop at silence and fades it in. Summon ambience fades out after the cinematic, then restores region ambience.

## Technical measurements

Measurements were made with FFmpeg 9.0.2 ebur128=peak=true. Files are stereo MP3 at 44.1 kHz. The mastering pass adjusted loudness and used a −1.5 dBTP limiter ceiling; the values below were measured again after MP3 encoding.

| Asset | Duration | Before (LUFS) | After (LUFS) | After true peak |
|---|---:|---:|---:|---:|
| ui_crystal_click | 0.48 s | −31.6 | −18.0 | −6.2 dBTP |
| ui_crystal_hover | 0.48 s | −31.5 | −17.9 | −3.1 dBTP |
| ui_confirm_select | 1.00 s | −16.3 | −17.9 | −9.1 dBTP |
| ui_panel_open | 1.00 s | −17.8 | −18.0 | −5.3 dBTP |
| ui_panel_close | 0.80 s | −21.8 | −19.9 | −1.2 dBTP |
| inventory_equip | 0.80 s | −29.1 | −22.0 | −1.4 dBTP |
| spell_cast | 1.20 s | −14.8 | −17.9 | −5.1 dBTP |
| summon_reveal | 2.00 s | −10.7 | −18.0 | −6.5 dBTP |
| summon_ritual_ambience | 8.00 s | −15.6 | −22.0 | −8.5 dBTP |
| frozen_hall_wind_loop | 10.00 s | −31.9 | −24.0 | −9.9 dBTP |

The initial loudness spread was 21.2 LU. The mastered files place the short UI/combat/reveal cues in a much narrower range; ambience remains intentionally lower. The reveal's initial +0.4 dBFS peak is now −6.5 dBTP. The final highest measured true peak is −1.2 dBTP.

All ten final files were checked for SHA-256 uniqueness; no exact duplicate files were found.

## Verification

- Godot 4.7.2 headless editor scan/import completed.
- Targeted Godot audio integration smoke test: 38 passed, 0 failed (re-run after the world-chunk parse cleanup). The permanent test scene covers all ten stream loads, the SFX bus and player pool, button hover/click routing, confirm-button routing, all one-shot routes, ambience loop flags and playback gains, summon ambience start/stop and Gothic Castle wind start/stop.
- Latest full project regression run: 2,806 passed, 9 failed. The outstanding failures concern the first chunk terrain type, region/map routing and portal expectations, live map-marker refresh, and gathering-node creation/persistence. The output also contains existing lambda-capture and ObjectDB cleanup warnings. These failures are outside the SFX integration.
- A stale unreachable prefetch block in scripts/world/components/world_chunk_streaming_component.gd referenced a renamed player_grid parameter and caused a parse error. That dead block was removed without changing the function's intentional early-return behaviour; the file backup is retained beside it.
- No subjective listening review in the running game has been completed yet; final volume balance should still be auditioned on target speakers/headphones.

## Source preservation

The pre-mastering MP3s are backed up outside the project at:

C:\Users\quoth\Downloads\Reverie_SFX_PreMastering_20261120\

The original Reverie_Sound_Library.zip was not modified. The repeatable audio test is kept in tests/audio_integration_smoke.tscn and is now included in the CI workflow after the main test suite. Run it locally with: godot --headless --path . res://tests/audio_integration_smoke.tscn
