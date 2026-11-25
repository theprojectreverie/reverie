from pathlib import Path
import re
import shutil

root = Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy")
scene = root / "scenes/characters/actor_visual.tscn"
component = root / "scripts/world/components/actor_character_effects_component.gd"
text = scene.read_text(encoding="utf-8")
anchor = '[ext_resource type="PackedScene" path="res://scenes/characters/components/lilith_spectral_effects.tscn" id="16_lilith_fx"]'
assert anchor in text and "shared_character_effects.tscn" not in text
text = text.replace(anchor, anchor + '\n[ext_resource type="PackedScene" path="res://scenes/characters/components/shared_character_effects.tscn" id="17_shared_fx"]', 1)
text = text.replace('[node name="LilithSpectralEffects" parent="." instance=ExtResource("16_lilith_fx")]', '[node name="LilithSpectralEffects" parent="." instance=ExtResource("16_lilith_fx")]\n[node name="SharedCharacterEffects" parent="." instance=ExtResource("17_shared_fx")]', 1)
text = text.replace("[gd_scene load_steps=16 format=3]", "[gd_scene load_steps=17 format=3]", 1)
shutil.copy2(scene, str(scene) + ".pre_shared_fx_20261120.bak")
scene.write_text(text, encoding="utf-8")

source = component.read_text(encoding="utf-8")
source, count = re.subn(r"(?ms)^func _draw_shared_character_fx\(\) -> void:\n.*?(?=^func |\Z)", "", source)
if count != 1:
    raise SystemExit(f"Expected one shared procedural renderer, removed={count}")
source = source.replace('\telse:\n\t\t_draw_shared_character_fx()', '\telse:\n\t\treturn', 1)
shutil.copy2(component, str(component) + ".pre_shared_fx_20261120.bak")
component.write_text(source, encoding="utf-8")
print("Integrated reusable SharedCharacterEffects scene and removed shared procedural draw routine.")
