extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/online/dedicated_world_server.tscn")
	if packed == null:
		push_error("Dedicated world server scene could not be loaded.")
		quit(1)
		return
	var server: Node = packed.instantiate()
	root.add_child(server)
