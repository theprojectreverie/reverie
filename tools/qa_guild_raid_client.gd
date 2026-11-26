extends Node

func _ready():
	call_deferred("run")

func idle(screen:Control)->bool:
	var deadline:=Time.get_ticks_msec()+48000
	while not str(screen._operation).is_empty() or screen._body.get_node("Raid/Battle/Stage").playing:
		if Time.get_ticks_msec()>deadline:return false
		await get_tree().process_frame
	return true

func fail(reason:String):
	print("FAIL ",reason)
	get_tree().quit(1)

func run():
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:fail("login");return
	var auth=await AuthGateway.auth_result
	if not auth[1]:fail("auth");return
	var screen=preload("res://scenes/ui/guild_screen.tscn").instantiate()
	add_child(screen)
	if not await idle(screen) or screen._raid.is_empty():fail("raid load");return
	if not screen._body.get_node("Raid").visible:fail("raid invisible");return
	var start:Button=screen._body.get_node("Raid/Buttons/Start")
	if start.disabled:fail("start disabled");return
	start.pressed.emit()
	if not await idle(screen) or screen._raid_attempt.is_empty():fail("start "+str(screen._layout.get_node("Status").text));return
	var stage=screen._body.get_node("Raid/Battle/Stage")
	if not stage.visible or stage.get_node("Boss").sprite_frames.resource_path!="res://assets/characters/cassien/combat/combat_frames.tres":fail("approved boss art");return
	if stage.get_node("Backdrop").texture.resource_path!="res://assets/ui/battle/backgrounds/crimson_castle_ruins.png":fail("approved background");return
	if stage.get_node("Party").get_child_count()!=3:fail("party presentation");return
	print("PASS authored Cassien frames and approved battle background")
	var attempt_id:=str(screen._raid_attempt.attemptId)
	var actions=screen._body.get_node("Raid/Battle/Actions")
	var defend:Button=actions.get_child(actions.get_child_count()-2)
	if defend.text!="Defend" or defend.disabled:fail("defend control");return
	defend.pressed.emit()
	if not await idle(screen) or screen._raid_attempt.is_empty():fail("defend "+str(screen._layout.get_node("Status").text));return
	if int(screen._raid_attempt.view.sequence)!=1:fail("defend sequence");return
	screen.close_screen()
	await get_tree().process_frame
	screen=preload("res://scenes/ui/guild_screen.tscn").instantiate()
	add_child(screen)
	if not await idle(screen):fail("reload");return
	start=screen._body.get_node("Raid/Buttons/Start")
	if start.text!="Resume attempt" or start.disabled:fail("resume control");return
	start.pressed.emit()
	if not await idle(screen) or screen._raid_attempt.is_empty():fail("resume response");return
	if str(screen._raid_attempt.attemptId)!=attempt_id or int(screen._raid_attempt.view.sequence)!=1:fail("resume state");return
	print("PASS raid start, defend and reopen/resume")
	for step in range(30):
		if screen._raid_attempt.is_empty():break
		var view:Dictionary=screen._raid_attempt.view
		var actor:Dictionary={}
		for unit in view.units:
			if str(unit.uid)==str(view.actorUid):actor=unit
		if actor.is_empty():fail("no actor");return
		actions=screen._body.get_node("Raid/Battle/Actions")
		var selected:Button=null
		for id in actor.get("skills",[]):
			var skill:=ContentDB.get_skill(str(id))
			if skill==null or skill.kind!="damage":continue
			for button in actions.get_children():
				if button is Button and not button.disabled and button.text.begins_with(skill.display_name):
					selected=button
					break
			if selected!=null:break
		if selected==null:selected=actions.get_child(actions.get_child_count()-1)
		selected.pressed.emit()
		if not await idle(screen):fail("action timeout");return
		if not screen._raid_attempt.is_empty() and int(screen._raid_attempt.view.sequence)<=int(view.sequence):fail("action rejected");return
	if int(screen._raid.get("hp",-1))!=0 or int(screen._raid.get("damage",0))<100:fail("shared defeat "+str(screen._raid));return
	stage=screen._body.get_node("Raid/Battle/Stage")
	if not stage.visible or screen._raid_result.is_empty():fail("final scene persistence");return
	await get_tree().create_timer(1.5).timeout
	if stage.get_node("Boss").animation!="defeat":fail("boss defeat animation");return
	print("PASS confirmed final boss defeat animation")
	var claim:Button=screen._body.get_node("Raid/Buttons/Claim")
	if claim.disabled:fail("claim disabled");return
	claim.pressed.emit()
	if not await idle(screen) or not bool(screen._raid.get("claimed",false)):fail("claim result");return
	if claim.text!="Claimed" or not claim.disabled:fail("claim control");return
	print("PASS raid skills, shared defeat, ranking and reward claim")
	screen.close_screen()
	await get_tree().process_frame
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	print("GUILD_RAID_CLIENT_PASS")
	get_tree().quit(0)
