from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
folder=p/'scripts/world/six_zone_reverie'
helper=folder/'six_zone_checkpoint.gd'
helper.write_text('''extends RefCounted

const SCENES = {
    "StandaloneZone01": "res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn",
    "StandaloneZone02": "res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn",
    "StandaloneZone03": "res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn",
    "StandaloneZone04": "res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn",
    "StandaloneZone05": "res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn",
    "StandaloneZone06": "res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn",
}

static func resume_scene() -> String:
    var checkpoint: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    return str(SCENES.get(str(checkpoint.get("zone", "")), SCENES["StandaloneZone01"]))

static func safe_position(zone: Node2D, point: Vector2) -> bool:
    if not point.is_finite():
        return false
    var transfers := zone.get_node_or_null("TransferPoints")
    if transfers != null:
        for marker in transfers.get_children():
            for child in marker.get_children():
                if child is Area2D and point.distance_to(zone.to_local(child.global_position)) < 150.0:
                    return false
    return true

static func restore(zone: Node2D, fallback: Vector2, arrival: StringName) -> Vector2:
    if arrival != &"":
        return fallback
    var data: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    if str(data.get("zone", "")) != str(zone.name):
        return fallback
    var point := Vector2(float(data.get("x", INF)), float(data.get("y", INF)))
    return point if safe_position(zone, point) else fallback

static func capture(zone: Node2D, player: CharacterBody2D, immediate: bool = false) -> void:
    if not is_instance_valid(player) or not SCENES.has(str(zone.name)):
        return
    if not bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
        return
    var point := player.position
    if not safe_position(zone, point):
        return
    var previous: Dictionary = GameState.quest_domain.flags.get("six_zone_checkpoint", {})
    var changed := str(previous.get("zone", "")) != str(zone.name) or Vector2(float(previous.get("x", INF)), float(previous.get("y", INF))).distance_to(point) > 0.5
    if changed:
        GameState.quest_domain.flags["six_zone_checkpoint"] = {"zone": str(zone.name), "x": point.x, "y": point.y}
        GameState.session_domain.set_player_position(point)
    if changed or immediate:
        GameState.save_now()
''',encoding='utf-8')
def backup(f):
 b=Path(str(f)+'.before_position_checkpoint')
 if not b.exists(): shutil.copy2(f,b)
for filename in ['standalone_zone_controller.gd','willow_fields_standalone_controller.gd']:
 f=folder/filename; backup(f); t=f.read_text(encoding='utf-8-sig')
 if 'const CHECKPOINT' in t: continue
 t=t.replace('func _ready() -> void:', '''const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
var checkpoint_player: CharacterBody2D
var checkpoint_elapsed := 0.0

func _ready() -> void:''',1)
 t=t.replace('    player.position = spawn_at','    player.position = CHECKPOINT.restore(self, spawn_at, arrival)',1)
 t=t.replace('    add_child(player)','    add_child(player)\n    checkpoint_player = player\n    CHECKPOINT.capture(self, player, true)',1)
 t+='''

func _process(delta: float) -> void:
    checkpoint_elapsed += delta
    if checkpoint_elapsed >= 2.0:
        checkpoint_elapsed = 0.0
        CHECKPOINT.capture(self, checkpoint_player)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        CHECKPOINT.capture(self, checkpoint_player, true)
'''
 f.write_text(t,encoding='utf-8')
f=p/'scripts/game/components/main_gameplay_flow_component.gd';backup(f);t=f.read_text(encoding='utf-8-sig')
t=t.replace('const INTRO_SCENE:', 'const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")\nconst INTRO_SCENE:',1)
t=t.replace('loading.target_scene_path = "res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn"','loading.target_scene_path = CHECKPOINT.resume_scene()')
t=t.replace('get_tree().change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")','get_tree().change_scene_to_file(CHECKPOINT.resume_scene())')
f.write_text(t,encoding='utf-8')
print('Installed checkpoint restore and 2-second autosave in all six zones.')
