extends Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := load("res://scenes/world/six_zone_reverie/drowned_orchid_ruins/elderwood_flooded_landscape.tscn").instantiate() as Node2D
	add_child(map)
	var player := load("res://scenes/characters/player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	player.get_node("LocomotionComponent").set_physics_process(false)
	player.set_avatar("kael")
	var pool := map.get_node("NorthernMirror") as Polygon2D
	player.global_position = pool.to_global(Vector2(-250, 600))
	var cam := player.get_node("Camera2D") as Camera2D
	cam.enabled = false
	var review_cam := Camera2D.new()
	review_cam.position = player.global_position + Vector2(0, -35)
	review_cam.zoom = Vector2(1.6, 1.6)
	add_child(review_cam)
	review_cam.make_current()
	var presentation := player.get_node("PresentationComponent")
	presentation.update_water_visual(true, 1.0)
	presentation.play_water_splash(true)
	await get_tree().create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/wading_polish_kael.png"
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("WADE_VISUAL_CAPTURE result=", result, " path=", path)
	get_tree().quit(result)
