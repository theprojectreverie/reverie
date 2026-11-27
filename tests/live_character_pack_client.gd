extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))==OK)
	var auth=await AuthGateway.auth_result
	assert(auth[1])
	var deadline:=Time.get_ticks_msec()+20000
	while LiveCharacterContent.frames_for("cassien_legendary")==null and Time.get_ticks_msec()<deadline:
		if not LiveCharacterContent._busy: await LiveCharacterContent.refresh(true)
		await get_tree().process_frame
	var frames:=LiveCharacterContent.frames_for("cassien_legendary")
	assert(frames!=null and frames.get_animation_names().size()==7)
	for slot in LiveCharacterContent.SLOTS:
		assert(frames.get_frame_count(slot)==8)
		assert(frames.get_frame_texture(slot,0).get_size()==Vector2(128,128))
		assert(frames.get_animation_loop(slot)==(slot=="idle"))
	var def:=ContentDB.get_character("cassien_legendary")
	var instance:=CharacterInstance.from_dict({"char_id":"cassien_legendary","uid":"qa_cassien","level":1})
	var unit:=CombatFactory.build_from_character(instance,1.0)
	var actor: BattlefieldActor=load("res://scenes/ui/battlefield_actor.tscn").instantiate()
	add_child(actor)
	actor.setup(unit,true)
	assert(actor.live_art!=null and actor.live_art.visible and not actor.visual.visible)
	assert(actor.live_art.flip_h and actor.live_art.animation==&"idle")
	actor.play_attack()
	assert(actor.live_art.animation==&"basic_attack")
	actor.play_live_action(str(def.skills[0]),false)
	assert(actor.live_art.animation==&"skill_1")
	actor.play_live_action(str(def.skills[1]),false)
	assert(actor.live_art.animation==&"skill_2")
	actor.play_live_action(def.ultimate,true)
	assert(actor.live_art.animation==&"ultimate")
	actor.take_hit()
	assert(actor.live_art.animation==&"hit")
	actor.play_death()
	assert(actor.live_art.animation==&"defeat" and actor.dead)
	assert(LiveCharacterContent.decode_png(PackedByteArray([1,2,3]),"a".repeat(64))==null)
	print("LIVE_CHARACTER_PACK_CLIENT_PASS: authenticated downloaded original PNGs, seven real animation clips and right-facing combat")
	actor.queue_free()
	AudioDirector.stop_all_audio_immediately()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
