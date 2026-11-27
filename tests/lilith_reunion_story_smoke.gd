extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("CHECK ", message, " = ", ok)
	if not ok: failures.append(message)
func wait_dialogue(box: Control, id: String) -> bool:
	for i in range(4000):
		await process_frame
		if box.visible and box._dialogue_id == id: return true
	return false
func finish_dialogue(box: Control) -> void:
	for i in range(30):
		if not box.visible: return
		box._finish_typing()
		if box._node.has("choices"):
			box._choose(box._node.choices[0])
		else:
			box._on_continue()
		await process_frame
func run() -> void:
	if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		quit(2)
		return
	var gs = root.get_node("GameState")
	gs.quest_domain.flags["tutorial_complete"] = true
	gs.quest_domain.flags["village_gerald_defeated"] = true
	gs.quest_domain.flags["village_gerald_backstory_pending"] = true
	gs.quest_domain.flags["village_gerald_memories_complete"] = true
	gs.quest_domain.flags.erase("village_lilith_awakened")
	gs.quest_domain.flags.erase("village_gerald_backstory_seen")
	gs.quest_domain.flags["six_zone_checkpoint"] = {"zone":"StandaloneVillage","x":-2090.0,"y":112.0}
	var initial_roster: int = gs.roster_domain.roster.size()
	change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
	await scene_changed
	var zone = current_scene
	var box = zone.get_node("UI/Dialogue")
	var player = zone.get("checkpoint_player")
	var opened := await wait_dialogue(box,"gerald_lilith_help")
	check(opened,"resume after memories goes directly to Companion")
	if not opened:
		quit(1)
		return
	check(not player.input_enabled and zone.get_meta("gerald_backstory_active",false),"exploration locked")
	check(gs.roster_domain.story_solo_active(),"solo party before awakening")
	var exit_trigger = zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
	check(not exit_trigger._story_unlocked(),"exit remains locked")
	await finish_dialogue(box)
	Engine.time_scale = 8.0
	var reunion = await wait_dialogue(box,"gerald_lilith_reunion")
	check(reunion,"portal, transfer, vortex and awakening play automatically")
	if not reunion:
		quit(1)
		return
	var stage = zone.find_child("LilithReunionCinematic",true,false)
	check(is_instance_valid(stage) and stage.finished_once,"reunion stage completed")
	if is_instance_valid(stage):
		check(stage.transformation.get_node("AnimationPlayer").current_animation == "floating_idle","awakening automatically loops")
	check(not player.input_enabled,"movement still locked during reunion")
	await finish_dialogue(box)
	for i in range(10): await process_frame
	check(gs.quest_domain.flags.get("village_lilith_awakened",false),"awakening flag")
	check(gs.quest_domain.flags.get("village_gerald_backstory_seen",false),"story completed")
	check(not gs.quest_domain.flags.get("village_gerald_backstory_pending",true),"pending cleared")
	check(player.input_enabled and not gs.roster_domain.story_solo_active(),"deployment and movement restored")
	check(gs.roster_domain.roster.size() == initial_roster,"no duplicate grant")
	check(exit_trigger._story_unlocked(),"road opens")
	change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
	await scene_changed
	for i in range(20): await process_frame
	check(current_scene.find_child("LilithReunionCinematic",true,false) == null,"completed reunion not replayed")
	print("REUNION RESULTS ", failures)
	quit(0 if failures.is_empty() else 1)

