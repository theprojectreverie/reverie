extends RefCounted
## Read-only presentation of server-confirmed expedition progress.
const NAMES = ["Village","Royal Gardens","Royal Gate","Willow Fields","Elderwood Grove","Forsaken Ruins","Ruined Tower"]
const OBJECTIVES = {
	"willow_bridge":"Reach the river crossing",
	"willow_ruins":"Investigate the eastern ruins",
	"elderwood_memorial":"Examine the broken memorial",
	"elderwood_pillar":"Examine the weathered pillar",
	"ruins_western_brazier":"Purify the western brazier",
	"ruins_central_brazier":"Purify the central brazier",
	"ruins_eastern_brazier":"Purify the eastern brazier",
	"cassien_resurrection":"Return to Cassien at the tomb",
}
static func _row(text: String, done: bool, active: bool) -> Dictionary:
	return {"text":text,"done":done,"active":active}

static func _nearest(zone: Node2D, ids: Array, excluded: Dictionary = {}) -> Node2D:
	var player := zone.get("checkpoint_player") as Node2D
	var result: Node2D
	var best := INF
	if not is_instance_valid(player):
		return null
	for node in zone.get_tree().get_nodes_in_group("world_action_targets"):
		if not node is Node2D or not zone.is_ancestor_of(node) or not node.visible or not "group_id" in node or bool(node.get("defeated")):
			continue
		var id := str(node.group_id)
		if (not ids.is_empty() and not ids.has(id)) or excluded.has(id):
			continue
		var distance := player.global_position.distance_to(node.global_position)
		if distance < best:
			best = distance
			result = node
	return result

static func _objective(zone: Node2D, id: String) -> Node2D:
	if id == "cassien_resurrection":
		return zone.get_node_or_null("CassienRitual") as Node2D
	for node in zone.get_tree().get_nodes_in_group("quest_exploration_targets"):
		if node is Node2D and zone.is_ancestor_of(node) and str(node.get("objective_id")) == id:
			return node
	return null

static func resolve(zone: Node2D) -> Dictionary:
	if not is_instance_valid(zone) or MultiplayerGateway.standalone_expedition_id.is_empty():
		return {}
	var i := int(str(zone.name).right(2))
	if i<1 or i>6:
		return {}
	var result := {"title":"Party expedition","text":"Synchronizing shared objectives...","region":NAMES[i],"rows":[],"valid":false,"ready":false,"complete":false,"portal":false,"destination":-1,"quest_id":"shared_expedition","repeatable":false}
	var sync = zone.get_node_or_null("CoopWorldSync")
	var player := zone.get("checkpoint_player") as Node2D
	if sync == null or not sync._snapshot_ready or not is_instance_valid(player) or bool(player.get("network_recovery_paused")):
		return result
	result.ready = true
	var rows: Array = []
	var target: Node2D
	var complete := false
	var detail := ""
	match i:
		1:
			result.repeatable = true
			detail = "Hunt Rose Slimes together"
			rows.append(_row("Repeatable shared combat — no required kill count",false,true))
			target = _nearest(zone,[])
		2:
			var cleared: Dictionary = sync.patrol_cleared
			var ids := ["royal_gate_patrol_1","royal_gate_patrol_2"]
			complete = cleared.size()>=2
			detail = "Clear the shared patrol (%d/2)" % cleared.size()
			target = _nearest(zone,ids,cleared)
			for j in range(ids.size()):
				var done := cleared.has(ids[j])
				rows.append(_row("Defeat Crownling %d" % (j+1),done,not done))
		3,4,5:
			var next: String = sync.next_exploration_objective()
			var completed: Array = sync.exploration_cleared
			var ordered: Array = sync.SHARED_OBJECTIVES.get(sync.active_region_id,[])
			complete = not ordered.is_empty() and completed.size()==ordered.size()
			if i==5:
				var cassien = zone.get_node_or_null("CassienRitual")
				var boss_done: bool = cassien != null and cassien.coop_defeated
				rows.append(_row("Defeat Cassien",boss_done,not boss_done))
				if not boss_done:
					detail = "Challenge Cassien"
					target = cassien as Node2D
					complete = false
			for id in ordered:
				rows.append(_row(str(OBJECTIVES.get(id,id)),completed.has(id),id==next))
			if not next.is_empty():
				detail = str(OBJECTIVES.get(next,next))
				target = _objective(zone,next)
		6:
			var boss = zone.get_node_or_null("ReviennaEncounter")
			complete = boss != null and boss.defeated
			detail = "Defeat Ravienna together"
			rows.append(_row(detail,complete,not complete))
			target = boss as Node2D
	result.rows = rows
	result.complete = complete
	if complete:
		detail = "Shared objectives complete"
		target = null
		if i<6:
			var marker := zone.get_node_or_null("TransferPoints/ToNextZone")
			if marker != null:
				for child in marker.get_children():
					if child is Area2D and child.has_method("_story_unlocked") and child._story_unlocked():
						target = child
						result.portal = true
						result.destination = i+1
						detail = "Complete — travel to " + NAMES[i+1]
						break
	result.text = detail
	if is_instance_valid(target):
		result.valid = true
		result.position = target.global_position
		var delta := target.global_position-player.global_position
		result.distance = delta.length()
		result.direction = delta.normalized()
	return result
