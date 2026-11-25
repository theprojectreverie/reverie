extends Area2D

## Editor-authored transfer trigger; collision is a detection area, not a wall.
@export_file("*.tscn") var destination_scene: String
@export var arrival_marker: StringName = &"ToPreviousZone"
static var pending_arrival: StringName = &""
var transferring := false

func _ready() -> void:
    monitoring = true
    collision_layer = 0
    collision_mask = 2
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if transferring or not body.is_in_group("player") or destination_scene.is_empty():
        return
    transferring = true
    AudioDirector.play_variant("portal_transition")
    pending_arrival = arrival_marker
    get_tree().call_deferred("change_scene_to_file", destination_scene)
