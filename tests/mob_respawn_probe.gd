extends Node2D
func _ready() -> void:
	for path in ["res://scenes/world/six_zone_reverie/rose_slime.tscn", "res://scenes/world/six_zone_reverie/crownling.tscn"]:
		var mob = load(path).instantiate()
		mob.group_id = "qa_respawn_" + str(path.get_file())
		mob.position = Vector2(40, 50)
		add_child(mob)
		mob.set_physics_process(false)
		for cycle in range(3):
			mob.position += Vector2(20, 0)
			mob._begin_defeat()
			assert(mob.defeated and mob.world_hp == 0.0)
			var remaining: float = mob.respawn_remaining
			var flags_before: Dictionary = GameState.quest_domain.flags.duplicate(true)
			mob.receive_world_hit(999.0)
			mob.receive_world_hit(999.0)
			assert(mob.world_hp == 0.0 and mob.defeated and mob.respawn_remaining == remaining)
			assert(GameState.quest_domain.flags == flags_before)
			mob._physics_process(14.0)
			assert(mob.defeated)
			mob._physics_process(1.1)
			assert(not mob.defeated and mob.visible and mob.position == mob.home and mob.world_hp == mob.max_world_hp)
		mob.respawn_seconds = 1.2
		mob.set_physics_process(true)
		mob._begin_defeat()
		await get_tree().create_timer(0.95).timeout
		assert(mob.defeated and not mob.visible)
		await get_tree().create_timer(0.5).timeout
		assert(not mob.defeated and mob.visible and mob.world_hp == mob.max_world_hp)
		mob.set_physics_process(false)
		mob.apply_coop_monster_state(0.0, Time.get_unix_time_from_system() * 1000.0 + 15000.0)
		assert(mob.defeated)
		mob.apply_coop_monster_state(0.0, Time.get_unix_time_from_system() * 1000.0 - 1.0)
		assert(not mob.defeated and mob.visible and mob.world_hp == mob.max_world_hp)
		mob.apply_coop_monster_state(75.0, 0.0)
		assert(mob.world_hp == 75.0 and not mob.defeated)
		mob._begin_defeat()
		mob._remember_local_respawn()
		var test_id: String = mob.group_id
		mob.queue_free()
		await get_tree().process_frame
		mob = load(path).instantiate()
		mob.group_id = test_id
		add_child(mob)
		mob.set_physics_process(false)
		assert(mob.defeated and not mob.visible and mob.respawn_remaining > 0.0)
		mob._physics_process(16.0)
		assert(not mob.defeated and mob.visible and mob.world_hp == mob.max_world_hp)
		assert(not GameState.quest_domain.flags.get("local_mob_respawn_deadlines", {}).has(test_id))
		print("REPEATED RESPAWN, ANIMATION AND MAP REENTRY PASS: ", path)
		mob.queue_free()
		await get_tree().process_frame
	var zone = load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn").instantiate()
	var mobs: Array = []
	var ids: Dictionary = {}
	for child in zone.get_children().duplicate():
		if child.has_method("_begin_defeat"):
			var id: String = child.group_id
			assert(not ids.has(id))
			ids[id] = child.position
			child.owner = null
			zone.remove_child(child)
			child.group_id = "qa_independent_" + id
			add_child(child)
			child.set_physics_process(false)
			mobs.append(child)
	zone.free()
	assert(mobs.size() == 9)
	for i in range(9):
		var mob = mobs[i]
		mob._begin_defeat()
		mob._remember_local_respawn()
		mob._physics_process(float(i))
		assert(mob.defeated)
	for i in range(9):
		var mob = mobs[i]
		mob._physics_process(15.1 - float(i))
		assert(not mob.defeated and mob.position == mob.home)
		for j in range(i + 1, 9):
			assert(mobs[j].defeated)
		mob.queue_free()
	print("ALL 9 AUTHORED SPAWNS INDEPENDENT RESPAWN PASS")
	get_tree().quit()
