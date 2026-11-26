extends Node

func _ready() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error("MOBILE HUD/BOSS QA: " + message)
	get_tree().quit(1)

func run() -> void:
	TouchInput.using_touch = true
	var village: Node2D = load("res://scenes/world/village/imported_village/village_playable.tscn").instantiate()
	add_child(village)
	await get_tree().process_frame
	await get_tree().physics_frame
	var hud: HUD = village.get_node("UI/HUD")
	var player: Player = village.get("checkpoint_player")
	var gerald: Node2D = village.get_node("VillageMap/GeraldBossSpawn/GeraldChallenge")
	if player == null or gerald == null: fail("village actors");return
	var toggle: Button = hud.get_node("MobileMenuToggle")
	var stack: GridContainer = hud.get_node("ActionStack")
	await get_tree().create_timer(0.2).timeout
	if not toggle.visible or stack.visible:fail("mobile menu not collapsed");return
	for dimensions in [Vector2(1280,720), Vector2(1280,800), Vector2(960,600), Vector2(640,360)]:
		hud.size = dimensions
		hud._apply_responsive_layout(dimensions)
		hud._navigation_component.set_mobile_menu_open(true)
		await get_tree().process_frame
		await get_tree().process_frame
		if not stack.visible or hud._minimap.visible:fail("menu visibility");return
		if stack.get_rect().position.y < 0 or stack.get_rect().end.y > dimensions.y:fail("menu clipped %s %s" % [dimensions,stack.get_rect()]);return
		if stack.get_rect().intersects(toggle.get_rect()):fail("menu overlaps toggle");return
		if toggle.get_rect().intersects(hud._touch_combat.get_rect()):fail("menu overlaps combat");return
		if stack.get_child_count()!=8:fail("lost navigation action");return
		hud._navigation_component.set_mobile_menu_open(false)
		print("PASS mobile navigation ",dimensions)
	# A physical collision query must hit the actual authored guardian footprint.
	var footprint: StaticBody2D = gerald.get_node("Footprint")
	var feet: CollisionShape2D = footprint.get_node("CollisionShape2D")
	var shape := CircleShape2D.new()
	shape.radius = 3.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = player.collision_mask
	query.transform = Transform2D(0, feet.global_position)
	var hits := gerald.get_world_2d().direct_space_state.intersect_shape(query, 20)
	if not hits.any(func(h):return h.collider == footprint):fail("Gerald footprint does not block player mask");return
	print("PASS Gerald solid world footprint")
	village.queue_free()
	await get_tree().process_frame
	# Actual battlefield actor and SpriteFrames, no placeholder assets.
	var field: Battlefield = load("res://scenes/ui/battlefield.tscn").instantiate()
	field.arena_id = "gerald_boss_encounter"
	add_child(field)
	field.size = Vector2(1024,480)
	var players := CombatFactory.player_units().filter(func(u):return u.def_id=="kael")
	var enemies := CombatFactory.enemy_units("gerald_boss_encounter","village_solo")
	if players.is_empty() or enemies.is_empty():fail("combat fixtures");return
	field.setup(players,enemies)
	await get_tree().process_frame
	await get_tree().process_frame
	var kael: BattlefieldActor = field.actor_for_uid(players[0].uid)
	var boss: BattlefieldActor = field.actor_for_uid(enemies[0].uid)
	if not kael.kael_boss_art_enabled:fail("Kael authored boss mode");return
	var frames := kael.kael_boss_art.sprite_frames
	for clip in [&"approach",&"attack",&"retreat"]:
		var expected := 8 if clip==&"approach" else (16 if clip==&"attack" else 6)
		if frames.get_frame_count(clip)!=expected:fail("frame count "+str(clip));return
		for i in expected:
			if frames.get_frame_texture(clip,i)==null:fail("missing frame");return
	var clips := {}
	kael.kael_boss_art.animation_changed.connect(func():clips[str(kael.kael_boss_art.animation)]=true)
	field.play_attack(kael,boss,"fire","basic_attack",false)
	await get_tree().create_timer(0.35).timeout
	if kael.kael_boss_art.animation!=&"approach" or not kael.kael_boss_art.visible or kael.position.distance_to(kael.home_position)<5:fail("approach");return
	field.size = Vector2(960,440)
	field._layout()
	kael.take_hit()
	await get_tree().create_timer(0.6).timeout
	if kael.kael_boss_art.animation!=&"attack":fail("strike interrupted");return
	await get_tree().create_timer(1.4).timeout
	if kael.kael_boss_art.animation!=&"retreat":fail("withdrawal missing");return
	await get_tree().create_timer(0.8).timeout
	if kael.kael_boss_art.animation!=&"idle" or kael.position.distance_to(kael.home_position)>1:fail("return formation");return
	for clip in ["approach","attack","retreat","idle"]:
		if not clips.has(clip):fail("missing clip "+clip);return
	print("PASS all authored Kael boss clips, resize, delayed hit, return to formation")
	get_tree().quit()