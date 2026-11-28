extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1" or root.get_node("AuthGateway").is_authenticated():
		quit(2)
		return
	var gs = root.get_node("GameState")
	gs.quest_domain.flags["tutorial_complete"] = true
	gs.quest_domain.flags.erase("mirene_local_defeated")
	gs.quest_domain.flags.erase("chapter_tracking_paused")
	gs.quest_domain.flags.erase("chapter_manual_quest")
	gs.quest_domain.quests.erase("elathra_first_audience")
	change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
	await scene_changed
	await physics_frame
	var zone = current_scene
	var boss = zone.get_node("MireneEncounter")
	var exit = zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
	assert(boss.visible and not boss.can_interact() and not exit._story_unlocked())
	assert(boss.permits_local_story(true, true, false, false))
	assert(not boss.permits_local_story(true, false, false, false))
	assert(not boss.permits_local_story(true, true, true, false))
	assert(not boss.permits_local_story(true, true, false, true))
	print("PUBLIC ALPHA STORY POLICY PASS")
	var geo = load("res://scripts/online/story_opening_geometry.gd")
	assert(geo.contains(geo.load_region("story_royal_gardens"),boss.global_position))
	assert(boss.global_position.distance_to(Vector2(1240,1240))+boss.interaction_radius <= 120.0)
	assert(zone.get_node("MireneMoonroseSanctuary").global_position == boss.global_position)
	var space = zone.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 1
	for y in range(1290,1650,10):
		query.transform = Transform2D(0.0,Vector2(1240,y))
		assert(space.intersect_shape(query,1).is_empty(),"Circus approach obstructed at y="+str(y))
	print("CIRCUS APPROACH CLEAR PASS")
	gs.quest_domain.quests["elathra_first_audience"] = {"state":"complete","step":2}
	assert(boss.can_interact() and not exit._story_unlocked())
	var nav = load("res://scripts/world/six_zone_reverie/chapter_navigation.gd")
	assert(nav.resolve(zone).get("position") == boss.global_position)
	var player = zone.checkpoint_player
	player.global_position = boss.global_position + Vector2(0,40)
	player.input_enabled = true
	boss.interact()
	assert(zone.get_node("CombatRouter").active_combat != null)
	print("MIRENE LOCAL ENCOUNTER OPEN PASS")
	boss._on_local_battle_finished({"group_id":"mirene_encounter","victory":true})
	assert(boss.defeated and not boss.visible and exit._story_unlocked())
	print("MIRENE LOCAL PROGRESSION PASS")
	quit(0)
