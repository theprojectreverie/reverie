extends Node2D
func _ready() -> void:
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn").instantiate()
	add_child(zone)
	await get_tree().process_frame
	var player = zone.checkpoint_player
	player.global_position = Vector2(0,1170)
	player.set("input_enabled",false)
	player.velocity = Vector2.ZERO
	var cam := Camera2D.new()
	add_child(cam)
	cam.global_position = Vector2(0,990)
	cam.zoom = Vector2(1.3,1.3)
	cam.make_current()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://artifacts/qa_ravienna_throne.png")
	print("THRONE_CAPTURE=",err," camera=",cam.global_position," sprite=",zone.get_node("Zone/Revienna/AnimatedSprite2D").frame)
	get_tree().quit(err)
