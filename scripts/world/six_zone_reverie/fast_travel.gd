extends RefCounted
const CHECKPOINT = preload("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
const TRANSFER = preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
const NAMES := {
	"StandaloneVillage": "Village",
	"StandaloneZone01": "Royal Gardens",
	"StandaloneZone02": "Royal Gate",
	"StandaloneZone03": "Willow Fields",
	"StandaloneZone04": "Elderwood Grove",
	"StandaloneZone05": "Forsaken Ruins",
	"StandaloneZone06": "Ruined Tower",
}
const FLAG := "discovered_fast_travel_zones"

static func find_zone(node: Node) -> Node2D:
	var cursor := node
	while cursor != null:
		if cursor is Node2D and CHECKPOINT.SCENES.has(str(cursor.name)):
			return cursor as Node2D
		cursor = cursor.get_parent()
	return null

static func discovered() -> Array:
	var saved: Variant = GameState.quest_domain.flags.get(FLAG, [])
	var visited: Array = saved.duplicate() if saved is Array else []
	# The numbered maps form a linear route. Older saves may omit earlier visits.
	var furthest := 0
	for id in visited:
		if str(id).begins_with("StandaloneZone") and CHECKPOINT.SCENES.has(str(id)):
			furthest = maxi(furthest, int(str(id).right(2)))
	for index in range(1, furthest + 1):
		var id := "StandaloneZone%02d" % index
		if id not in visited:
			visited.append(id)
	if (furthest > 0 or bool(GameState.quest_domain.flags.get("village_gerald_defeated", false))) and "StandaloneVillage" not in visited:
		visited.append("StandaloneVillage")
	return visited

static func record_visit(zone: Node2D) -> void:
	if not bool(GameState.quest_domain.flags.get("tutorial_complete", false)) or not MultiplayerGateway.standalone_expedition_id.is_empty():
		return
	var id := str(zone.name)
	if not CHECKPOINT.SCENES.has(id):
		return
	GameState.reward_domain.record_daily_visit(id)
	var visited := discovered()
	if id not in visited:
		visited.append(id)

	if GameState.quest_domain.flags.get(FLAG, []) != visited:
		GameState.quest_domain.flags[FLAG] = visited
		GameState.queue_save()

static func unavailable_reason(zone: Node2D, id: String) -> String:
	if zone == null or not CHECKPOINT.SCENES.has(id):
		return "Unknown destination"
	if not bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
		return "Complete the tutorial first"
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		return "Fast travel unavailable during co-op"
	if bool(zone.get_meta("cassien_ritual_active", false)):
		return "Finish Cassien's ritual first"
	if bool(zone.get_meta("gerald_backstory_active", false)):
		return "Finish Gerald's memories first"
	if str(zone.name) == id:
		return "Current location"
	if str(zone.name) == "StandaloneVillage" and not bool(GameState.quest_domain.flags.get("village_gerald_defeated", false)) and id not in discovered():
		return "Defeat Gerald first"
	if id not in discovered():
		return "Visit this area to unlock"
	var battle := zone.get_node_or_null("CombatRouter")
	if battle != null and battle.active_combat != null:
		return "Unavailable during combat"
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if is_instance_valid(player):
		var world_combat := player.get_node_or_null("WorldCombatComponent")
		if world_combat != null and (world_combat.attack_pending or world_combat.hurt_cooldown > 0.0 or world_combat.dodge_time > 0.0 or world_combat.cooldown > 0.0):
			return "Unavailable during combat"
		for enemy in zone.get_tree().get_nodes_in_group("world_action_targets"):
			if enemy is Node2D and zone.is_ancestor_of(enemy) and not enemy.get("defeated") and player.global_position.distance_to(enemy.global_position) <= 95.0:
				if ("windup" in enemy and enemy.windup) or ("world_hp" in enemy and "max_world_hp" in enemy and enemy.world_hp < enemy.max_world_hp):
					return "Move away from combat first"
	for path in ["UI/Dialogue", "NPCDialogueLayer/Dialogue"]:
		var dialogue := zone.get_node_or_null(path) as Control
		if dialogue != null and dialogue.visible:
			return "Finish the conversation first"
	if bool(zone.get_meta("portal_load_pending", false)) or bool(zone.get_meta("fast_travel_pending", false)) or bool(zone.get_meta("fast_travel_visual_pending", false)):
		return "Travel already in progress"
	return ""

static func travel(zone: Node2D, id: String, packed: PackedScene = null) -> bool:
	if not unavailable_reason(zone, id).is_empty():
		return false
	var path: String = CHECKPOINT.SCENES[id]
	if not ResourceLoader.exists(path):
		return false
	if packed != null and (packed.resource_path != path or not packed.can_instantiate()):
		return false
	var tree := zone.get_tree()
	if tree == null or tree.current_scene != zone:
		return false
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if not is_instance_valid(player):
		return false
	zone.set_meta("fast_travel_pending", true)
	CHECKPOINT.capture(zone, player, true)
	player.set("input_enabled", false)
	player.velocity = Vector2.ZERO
	TouchInput.release()
	TRANSFER.pending_arrival = &"FastTravel"
	var error := tree.change_scene_to_packed(packed) if packed != null else tree.change_scene_to_file(path)
	if error != OK:
		TRANSFER.pending_arrival = &""
		zone.set_meta("fast_travel_pending", false)
		player.set("input_enabled", true)
		return false
	StoryMilestoneTelemetry.record_scene_transition(path)
	AudioDirector.play_variant("portal_transition")
	return true
