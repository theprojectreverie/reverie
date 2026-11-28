extends Node
func _ready():
	call_deferred("run")
func run():
	GameState.quest_domain.flags["tutorial_complete"]=true
	var zone=load("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn").instantiate()
	add_child(zone)
	for i in range(5): await get_tree().physics_frame
	var p=zone.get("checkpoint_player")
	p.input_enabled=false
	p.get_node("Camera2D").enabled=false
	p.global_position=Vector2(2776,1630)
	var cam=Camera2D.new()
	cam.position=Vector2(2800,1540)
	cam.zoom=Vector2(1,1)
	add_child(cam)
	cam.make_current()
	for i in range(5):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result=get_viewport().get_texture().get_image().save_png("res://artifacts/willow_exit_gate_review/reimport_after.png")
	print("CAPTURE ",result)
	get_tree().quit(result)
