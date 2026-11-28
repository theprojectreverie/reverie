extends Node
func _ready():
	call_deferred("run")
func run():
	var t=get_tree()
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		t.quit(2)
		return
	var keep=Node.new()
	t.root.add_child(keep)
	reparent(keep)
	GameState.quest_domain.flags["tutorial_complete"]=true
	GameState.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneZone04"]
	t.change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
	await t.scene_changed
	for i in range(8):await t.physics_frame
	var z=t.current_scene
	var p=z.get("checkpoint_player") as CharacterBody2D
	var marker=z.get_node("TransferPoints/ToNextZone")
	var gate=marker.get_node("WillowExitGateFootprints") as StaticBody2D
	var start=Vector2(2600,1542)
	p.global_position=start
	p.velocity=Vector2.ZERO
	var center=gate.global_position
	var xf=p.global_transform
	xf.origin=start
	var clear=not p.test_move(xf,center-start)
	var checks=true
	print("GATE CENTER ROUTE CLEAR ",clear)
	checks=checks and clear
	var query=PhysicsPointQueryParameters2D.new()
	query.collision_mask=1
	for foot in gate.get_children():
		var poly=foot as CollisionPolygon2D
		var mid=Vector2.ZERO
		for q in poly.polygon:mid+=q
		mid/=float(poly.polygon.size())
		query.position=poly.to_global(mid)
		var hits=p.get_world_2d().direct_space_state.intersect_point(query)
		var solid=false
		for hit in hits:
			if hit.collider==gate:solid=true
		print("FOOTPRINT ",foot.name," ",solid)
		checks=checks and solid
	p.input_enabled=true
	TouchInput.set_move_vector(Vector2(1,0.5).normalized()*0.8)
	for i in range(320):
		await t.physics_frame
		if t.current_scene!=z:break
	TouchInput.release()
	var transferred=t.current_scene!=null and t.current_scene.name==&"StandaloneZone04"
	print("GATE WALK TRANSFER ",transferred)
	t.quit(0 if transferred and checks else 1)
