extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if AuthGateway.is_authenticated() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		get_tree().quit(2)
		return
	var before := GameState.quest_domain.quests.duplicate(true)
	var zone := (load("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(zone)
	get_tree().current_scene = zone
	await get_tree().process_frame
	var sync := zone.get_node("StoryGardenCombatSync")
	assert(sync._gate and sync._monsters.size()==2 and sync._route()=="/v1/royal-gate-story/")
	assert(zone.get_node("CombatRouter").combat_root!=null)
	assert(zone.checkpoint_player.network_recovery_paused)
	var a = sync._monsters["royal_gate_patrol_1"]
	var b = sync._monsters["royal_gate_patrol_2"]
	a.receive_world_hit(100000.0)
	assert(a.world_hp==120.0 and not a.defeated)
	assert(not sync.request_encounter(a.group_id))
	assert(not GameState.quest_domain.start_quest("royal_gate_patrol"))
	assert(not GameState.quest_domain.complete_quest("royal_gate_patrol"))
	GameState.quest_domain.record_kill("gate_crownling",2)
	assert(GameState.quest_domain.quests==before)
	print("PASS Royal Gate scene has correct combat router and cannot grant local quest rewards")
	var data := {"ok":true,"playerId":"qa","encounters":[{"groupId":a.group_id,"remainingMs":1000},{"groupId":b.group_id,"remainingMs":0}],"active":null,"patrol":{"questId":"royal_gate_patrol","state":"active","progress":1,"required":2,"defeated":[a.group_id],"willowFieldsUnlocked":false}}
	assert(sync.apply_status(data,"qa") and a.defeated and not b.defeated)
	assert(a.sprite.animation==&"defeat")
	var invalid := data.duplicate(true)
	invalid.patrol.defeated=[a.group_id,a.group_id]
	invalid.patrol.progress=2
	assert(not sync.apply_status(invalid,"qa") and sync._patrol.progress==1)
	data.encounters[0].remainingMs=0
	data.encounters[1].remainingMs=1000
	data.patrol={"questId":"royal_gate_patrol","state":"complete","progress":2,"required":2,"defeated":[a.group_id,b.group_id],"willowFieldsUnlocked":true}
	assert(sync.apply_status(data,"qa") and not a.defeated and b.defeated and sync._patrol.progress==2)
	assert(a.sprite.animation==&"idle" and b.sprite.animation==&"defeat")
	assert(GameState.quest_domain.quest_state("royal_gate_patrol")=="not_started") # disconnected proof not trusted
	assert(GameState.quest_domain.quests==before)
	print("PASS independent Crownling animation, cooldown and two-objective proof; duplicates rejected")
	get_tree().current_scene=self
	zone.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	print("STORY_ROYAL_GATE_MONSTER_SMOKE_PASS")
	get_tree().quit(0)
