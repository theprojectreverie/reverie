from pathlib import Path
import re
import shutil

project = Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy")
target = project / "scripts/world/components/actor_character_effects_component.gd"
source = target.read_text(encoding="utf-8")
dispatch = '\telif visual.character_id == "lilith":\n\t\t_draw_lilith_spectral_fx()'
if dispatch not in source:
    raise SystemExit("Expected legacy Lilith dispatch not found; no changes made")
source = source.replace(dispatch, '\telif visual.character_id == "lilith":\n\t\treturn', 1)
source, removed = re.subn(
    r"(?ms)^func _draw_lilith_spectral_fx\(\) -> void:\n.*$",
    "",
    source,
)
if removed != 1:
    raise SystemExit(f"Expected to remove one trailing Lilith draw method; removed={removed}")
backup = Path(str(target) + ".pre_lilith_dead_code_cleanup_20261120.bak")
shutil.copy2(target, backup)
target.write_text(source, encoding="utf-8")
print(f"Removed obsolete Lilith drawing method. Backup: {backup}")
