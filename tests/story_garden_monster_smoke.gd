extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	if AuthGateway.is_authenticated() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
		get_tree().quit(2)
		return
	var zone := (load("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn") as PackedScene).instantiate()
	add_child(zone)
	await get_tree().process_frame
	var sync := zone.get_node("StoryGardenCombatSync")
	assert(sync._monsters.size()==9)
	var slime = sync._monsters["rose_slime_garden_1"]
	var crown = zone.get_node("Crownling1")
	var player = zone.checkpoint_player
	assert(player.network_recovery_paused)
	slime.receive_world_hit(100000.0)
	crown.receive_world_hit(100000.0)
	assert(not slime.defeated and slime.world_hp==slime.max_world_hp and not crown.defeated)
	assert(not sync.request_encounter("rose_slime_garden_1"))
	print("PASS disconnected attacks cannot damage slimes or crownlings")
	var rows: Array = []
	for group in sync.GROUPS:rows.append({"groupId":group,"remainingMs":1000 if group==slime.group_id or group==crown.group_id else 0})
	var data := {"ok":true,"playerId":"qa","encounters":rows,"active":null}
	assert(not sync.apply_status(data,"other"))
	assert(sync.apply_status(data,"qa"))
	assert(slime.defeated and slime.world_hp==0.0 and slime.sprite.animation==&"defeat")
	assert(not sync._monsters["rose_slime_garden_2"].defeated)
	assert(crown.defeated and crown.sprite.animation==&"defeat")
	var bad := data.duplicate(true)
	bad.encounters[0].remainingMs=0
	bad.encounters[1].groupId=slime.group_id
	assert(not sync.apply_status(bad,"qa") and slime.defeated)
	slime._physics_process(100.0)
	assert(slime.defeated)
	rows[0].remainingMs=0
	assert(sync.apply_status(data,"qa"))
	assert(not slime.defeated and slime.world_hp==slime.max_world_hp and slime.visible and slime.sprite.animation==&"idle")
	assert(crown.defeated)
	rows[6].remainingMs=0
	assert(sync.apply_status(data,"qa"))
	assert(not crown.defeated and crown.world_hp==crown.max_world_hp and crown.sprite.animation==&"idle")
	print("PASS independent Crownling and Rose Slime server cooldowns and authored animations")
	zone.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	print("STORY_GARDEN_MONSTER_SMOKE_PASS")
	get_tree().quit(0)
