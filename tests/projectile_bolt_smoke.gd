extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/ui/combat/components/projectile_bolt.tscn") as PackedScene
	assert(packed != null, "Projectile bolt scene must load")
	var bolt := packed.instantiate() as Node2D
	assert(bolt != null, "Projectile bolt instance must be created")
	add_child(bolt)
	await get_tree().process_frame
	var player := bolt.get_node("AnimationPlayer") as AnimationPlayer
	assert(player != null and player.has_animation(&"flight"), "Projectile must own authored flight timeline")
	var start := Vector2(20, 40)
	var finish := Vector2(240, 130)
	bolt.call("launch", start, finish, Color("#79d9ff"), 0.26)
	assert(player.current_animation == "flight" and player.is_playing(), "Authored projectile flight must start")
	assert(bolt.rotation > 0.0, "Projectile must orient toward its target")
	player.advance(0.12)
	assert(bolt.position.distance_to(finish) < start.distance_to(finish), "Projectile root must travel toward target on its authored timeline")
	assert(bolt.get_node("Art/Trail") is Line2D, "Editor-authored trail must exist")
	assert(bolt.get_node("Art/Head") is Polygon2D, "Editor-authored projectile head must exist")
	player.advance(0.22)
	await get_tree().process_frame
	assert(not is_instance_valid(bolt), "Projectile should clean itself up after its authored flight")
	print("PROJECTILE BOLT SMOKE: PASS (authored nodes, oriented flight, timed cleanup)")
	get_tree().quit(0)
