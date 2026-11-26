extends Node
var ok := true
func check(value: bool, label: String) -> void:
	print("KAEL_COMBAT ",label,"=",value)
	ok = ok and value
func _ready() -> void:
	var field := preload("res://scenes/ui/battlefield.tscn").instantiate() as Battlefield
	field.arena_id = "revienna_encounter"
	field.size = Vector2(1000,450)
	add_child(field)
	field.setup(CombatFactory.player_units(), CombatFactory.enemy_units("revienna_encounter"))
	await get_tree().process_frame
	var kael: BattlefieldActor
	var boss: BattlefieldActor
	for actor in field.actors():
		if actor.unit.def_id == "kael": kael = actor
		if actor.unit.is_boss: boss = actor
	if kael == null or boss == null:
		print("MISSING ACTORS")
		get_tree().quit(1)
		return
	var art := kael.kael_boss_art
	check(kael.kael_boss_art_enabled and art.visible and not kael.visual.visible and art.animation == &"idle","idle")
	for clip in [&"idle",&"approach",&"attack",&"retreat"]:
		var expected: int = {"idle":5,"approach":8,"attack":16,"retreat":6}[String(clip)]
		check(art.sprite_frames.get_frame_count(clip)==expected,"frames_"+String(clip))
	var home := kael.home_position
	field.play_attack(kael,boss,"fire","",false)
	check(art.animation == &"approach","approach_start")
	await get_tree().create_timer(0.4).timeout
	check(kael.position.distance_to(home)>10 and art.animation == &"approach","moves_before_attack")
	await get_tree().create_timer(0.48).timeout
	var reach := kael.position
	check(art.animation == &"attack","attack_at_reach")
	await get_tree().create_timer(0.8).timeout
	check(art.animation == &"attack" and kael.position.distance_to(reach)<2,"attack_stationary")
	await get_tree().create_timer(0.58).timeout
	check(art.animation == &"retreat" and kael.position.distance_to(reach)>1,"backward_dodge")
	await get_tree().create_timer(0.65).timeout
	check(art.animation == &"idle" and kael.position.distance_to(home)<1,"idle_at_home")
	field.play_attack(kael,boss,"fire","",false)
	await get_tree().create_timer(0.2).timeout
	kael.cancel_attack_motion()
	check(art.animation == &"idle" and kael.position.distance_to(home)<1,"cancel_safe")
	await get_tree().create_timer(0.7).timeout
	check(art.animation == &"idle" and kael.position.distance_to(home)<1,"no_stale_callback")
	print("KAEL_COMBAT_PASS=",ok)
	field.queue_free()
	for _frame in range(3):
		await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.35).timeout
	get_tree().quit(0 if ok else 1)
