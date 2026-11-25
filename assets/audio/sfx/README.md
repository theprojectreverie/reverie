# Reverie sound effects

Ten mastered generated MP3 effects are installed in this folder and routed through the existing AudioDirector autoload.

| File | Runtime use |
|---|---|
| ui_crystal_click.mp3 | Default button press |
| ui_crystal_hover.mp3 | Button hover |
| ui_confirm_select.mp3 | Combat skill selection |
| ui_panel_open.mp3 | Shared overlay open |
| ui_panel_close.mp3 | Shared overlay close |
| inventory_equip.mp3 | Successful equipment change |
| summon_ritual_ambience.mp3 | Loop during the summon cinematic |
| summon_reveal.mp3 | Cue at the transition from the opening to the rarity reveal |
| spell_cast.mp3 | Magic, healing, guard and ultimate combat actions |
| frozen_hall_wind_loop.mp3 | Loop in the Gothic Castle region |

One-shots use an eight-player pool on the SFX bus. Ambience uses a dedicated looping player with fade transitions. The existing Master, Music and SFX volume controls remain in Settings.

The files were measured and level-adjusted with FFmpeg 9.0.2. UI/combat/reveal cues are approximately −18 LUFS; ambience is lower by design. Final true peaks measure between −9.9 and −1.2 dBTP. All MP3s are stereo 44.1 kHz.

See documentation/AUDIO_QA.md for individual loudness measurements, event mapping, smoke-test results and source-backup location. The original Reverie_Sound_Library.zip in Downloads was not modified.
