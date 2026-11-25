extends Area2D

@export_file("*.tscn") var destination_scene: String = "res://scenes/world/tutorial_prologue/training_ground_v02.tscn"
var transitioning := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if transitioning or not body.is_in_group("player"):
		return
	transitioning = true
	get_tree().call_deferred("change_scene_to_file", destination_scene)
