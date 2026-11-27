extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://assets/characters/harlequin/movement_preview.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	var sprite = player.get_node("AnimatedSprite2D")
	var origin: Vector2 = player.position
	Input.action_press("ui_right")
	for i in range(30):
		await physics_frame
	var moved: bool = player.position.x > origin.x + 20.0
	var walking: bool = sprite.animation == &"walk_e" and sprite.is_playing()
	var count: int = sprite.sprite_frames.get_frame_count(&"walk_e")
	print("HARLEQUIN movement=", moved, " walk_animation=", walking, " frames=", count, " displacement=", player.position.x-origin.x)
	Input.action_release("ui_right")
	for i in range(3):
		await physics_frame
	var idle: bool = sprite.animation == &"idle_e"
	print("HARLEQUIN returns_idle=", idle)
	quit(0 if moved and walking and count == 8 and idle else 1)
