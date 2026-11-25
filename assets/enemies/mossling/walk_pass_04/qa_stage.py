from pathlib import Path
from PIL import Image
import re

root = Path(__file__).parent
image_path = root / "mossling_walk_8dir_6f_96x128.png"
image = Image.open(image_path)
print("PNG size:", image.size)
print("PNG mode:", image.mode)
print("Alpha range:", image.getchannel("A").getextrema() if image.mode == "RGBA" else "MISSING")
assert image.size == (576, 1024)
assert image.mode == "RGBA"

tres = root / "mossling_walk_preview.tres"
text = tres.read_text(encoding="utf-8-sig")
text = re.sub(r'(id="AtlasTexture_\d+)(\])', r'\1"\2', text)
text = text.replace(
    "res://assets/enemies/mossling/mossling_walk_8dir_6f_96x128.png",
    "res://assets/enemies/mossling/walk_pass_04/mossling_walk_8dir_6f_96x128.png",
)
tres.write_text(text, encoding="utf-8")

scene = root / "mossling_walk_preview.tscn"
text = scene.read_text(encoding="utf-8-sig")
text = text.replace(
    "res://assets/enemies/mossling/mossling_walk_preview.tres",
    "res://assets/enemies/mossling/walk_pass_04/mossling_walk_preview.tres",
)
scene.write_text(text, encoding="utf-8")

resource_text = tres.read_text(encoding="utf-8")
assert '[sub_resource type="AtlasTexture" id="AtlasTexture_1"]' in resource_text
assert resource_text.count('"name": &"walk_') == 8
assert resource_text.count('"texture": SubResource(') == 48
print("SpriteFrames structural checks: 48 atlas frames, 8 directional animations.")
print("Staged Godot resource paths corrected.")
