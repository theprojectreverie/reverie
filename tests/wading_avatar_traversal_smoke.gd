extends Node
var failures := 0
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	GameState.quest_domain.flags["tutorial_complete"] = true
	GameState.quest_domain.flags["village_gerald_defeated"] = true
	GameState.quest_domain.flags["village_lilith_awakened"] = true
	GameState.quest_domain.flags["six_zone_checkpoint"] = {"zone":"StandaloneZone04"}
	var zone := load("res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn").instantiate() as Node2D
	add_child(zone)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player := zone.get("checkpoint_player") as Player
	var loc := player.locomotion_component
	loc.set_physics_process(false)
	var map := zone.get_node("Zone/FloodedLandscape")
	var routes := {}
	for pool_name in ["NorthernMirror","WestFloodplain","EasternLake","SouthernLagoon"]:
		var pool := map.get_node(pool_name) as Polygon2D
		var found := false
		var points := pool.polygon
		for i in range(points.size()):
			if found: break
			var a := pool.to_global(points[i])
			var b := pool.to_global(points[(i+1)%points.size()])
			var center := (a+b)*0.5
			var normal := (b-a).orthogonal().normalized()
			for sign_value in [-1.0,1.0]:
				var n: Vector2 = normal * sign_value
				var start := center - n*40.0
				var end := center + n*65.0
				if loc._water_at(start) or not loc._water_at(end): continue
				var xf := player.global_transform
				xf.origin = start
				if player.test_move(xf, Vector2.ZERO) or player.test_move(xf,end-start): continue
				routes[pool_name] = [start,end]
				found = true
				break
		print("ROUTE ",pool_name,": ",routes.get(pool_name,[]))
	if routes.size() != 4:
		failures += 4 - routes.size()
	var ids := ["kael","gerald","lilith","mirene_mythic","cassien_mythic","ravienna","elathra"]
	for id in ids:
		var instance = null
		for owned in GameState.roster_domain.roster:
			if owned.char_id == id:
				instance = owned
				break
		if instance == null:
			instance = GameState.add_character(id).get("instance")
		if instance == null:
			print("UNAVAILABLE ",id)
			failures += 1
			continue
		GameState.set_party([instance.uid])
		player.set_avatar(id)
		if player.avatar_id != id:
			print("AVATAR REJECTED ",id)
			failures += 1
			continue
		for pool_name in routes:
			var route: Array = routes[pool_name]
			player.global_position = route[0]
			player.velocity = Vector2.ZERO
			loc._sync_water_state(0.0,false)
			player.input_enabled = true
			var direction: Vector2 = (route[1]-route[0]).normalized()
			var entered := false
			var exited := false
			for j in range(100):
				await get_tree().physics_frame
				TouchInput.move_vector = direction
				loc.physics_step(1.0/60.0)
				if loc._in_water and loc._water_depth_at(player.global_position) > 0.65:
					entered = true
					break
			var wet_sprite := player.visual._sprite
			var visual_ok := wet_sprite != null and wet_sprite.material is ShaderMaterial
			for j in range(100):
				await get_tree().physics_frame
				TouchInput.move_vector = -direction
				loc.physics_step(1.0/60.0)
				if not loc._in_water:
					exited = true
					break
			TouchInput.release()
			print("TRAVERSE ",id," ",pool_name," entry=",entered," visual=",visual_ok," exit=",exited)
			if not (entered and visual_ok and exited): failures+=1
	print("LIVE_WADE routes=",routes.size()," failures=",failures)
	TouchInput.release()
	zone.queue_free()
	await get_tree().process_frame
	get_tree().quit(failures)
