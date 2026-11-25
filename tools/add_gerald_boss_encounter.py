import json
import shutil
from pathlib import Path

root = Path(__file__).resolve().parents[1]
enemy_path = root / "resources" / "data" / "enemies.json"
group_path = root / "resources" / "data" / "enemy_groups.json"

gerald = {
    "name": "Gerald, the Fallen Guardian",
    "element": "fire",
    "rarity": "mythic",
    "role": "Boss",
    "base": {"hp": 1200, "atk": 30, "def": 19, "spd": 14, "crit": 0.14, "crit_dmg": 1.8},
    "skills": ["ember_lance", "cinder_veil"],
    "ultimate": "inferno_crown",
    "phases": [
        {
            "hp_below": 0.6,
            "message": "The orange Titan emblem burns brighter. Gerald's restraint begins to fracture.",
            "status": {"id": "atk_up", "turns": 99, "potency": 0.22}
        },
        {
            "hp_below": 0.3,
            "message": "The last restraint breaks. The Fallen Guardian enters his berserk state.",
            "status": {"id": "atk_up", "turns": 99, "potency": 0.3}
        }
    ],
    "lore": "Once the village's half-Titan guardian, Gerald returned from war to find his mother and little sister murdered by the people he had protected. He shed one final tear, then answered the betrayal with terrible fury.",
    "palette": {
        "hair": "#e5e0e8",
        "skin": "#b9a0a0",
        "primary": "#211b2b",
        "secondary": "#d8c9bd",
        "accent": "#ff6a24"
    }
}

group = {
    "name": "Gerald, the Fallen Guardian",
    "boss": True,
    "level": 8,
    "region": "gothic_castle_boss_zone",
    "enemies": ["gerald_boss"],
    "rewards": {
        "gold": 1000,
        "xp": 1500,
        "crystals": 200,
        "ancient_coins": 3,
        "items": {}
    },
    "quest_kills": {"gerald_boss": 1}
}

for file_path, key, value in [
    (enemy_path, "gerald_boss", gerald),
    (group_path, "gerald_boss_encounter", group),
]:
    data = json.loads(file_path.read_text(encoding="utf-8"))
    if key in data:
        if data[key] != value:
            raise SystemExit(f"Refusing to overwrite existing entry: {key}")
        print(f"Already present and matches: {key}")
        continue
    backup = file_path.with_suffix(file_path.suffix + ".pre_gerald_boss_20261121.bak")
    shutil.copy2(file_path, backup)
    data[key] = value
    file_path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Added {key}; backup: {backup.name}")
