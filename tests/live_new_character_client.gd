extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	assert(AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))==OK)
	var auth=await AuthGateway.auth_result
	assert(auth[1])
	var id:=OS.get_environment("QA_CHARACTER")
	var deadline:=Time.get_ticks_msec()+20000
	while ContentDB.get_character(id)==null and Time.get_ticks_msec()<deadline:
		if not LiveCharacterContent._busy: await LiveCharacterContent.refresh(true)
		await get_tree().process_frame
	assert(ContentDB.get_character(id)!=null and ContentDB.get_character(id+"_mythic")!=null)
	assert(LiveCharacterContent.frames_for(id)!=null and LiveCharacterContent.portrait_for(id)!=null)
	var screen:=load("res://scenes/ui/gacha_screen.tscn").instantiate() as GachaScreen
	add_child(screen)
	while not screen._account_state_ready() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	assert(screen._account_state_ready())
	var bid:=OS.get_environment("QA_BANNER")
	assert(screen.active_banner_catalog().has(bid))
	screen._select_banner(bid)
	assert(screen._featured_id==id)
	assert(screen._summon_flow.online_state.party==[id,id+"_mythic"])
	var def:=ContentDB.get_character(id)
	var instance:=CharacterInstance.from_dict({"char_id":id,"uid":"qa_live","level":2})
	var unit:=CombatFactory.build_from_character(instance,1.0)
	assert(unit.def_id==id and unit.skills.size()>0)
	var actor:=load("res://scenes/ui/battlefield_actor.tscn").instantiate() as BattlefieldActor
	add_child(actor)
	actor.setup(unit,true)
	assert(actor.live_art!=null and not actor.visual.visible)
	actor.play_live_action(str(def.skills[0]),false)
	assert(actor.live_art.animation==&"skill_1")
	assert(preload("res://scripts/gacha/character_upgrade_card.gd").mythic_recipe(id).target==id+"_mythic")
	print("LIVE_NEW_CHARACTER_CLIENT_PASS: new definitions, artwork, banner, owned party and combat actor loaded at runtime")
	actor.queue_free()
	screen.queue_free()
	AudioDirector.stop_all_audio_immediately()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
