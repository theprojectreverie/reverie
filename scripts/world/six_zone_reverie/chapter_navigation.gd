extends RefCounted
## Navigation for the authored, standalone chapter. No quest or save mutation.
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
const SHARED_NAV = preload("res://scripts/world/six_zone_reverie/expedition_navigation.gd")
const IDS = ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","cassien_resurrection","forsaken_braziers"]
const STORY_ENTRIES = {
	"gerald_story": {"name":"The Fallen Guardian","region":"Village","summary":"Confront Gerald and discover the memories behind his fall.","steps":[{"text":"Defeat Gerald"},{"text":"Witness Gerald's memories and Lilith's awakening"}]},
	"ravienna_finale": {"name":"The Eclipse Sovereign","region":"Ruined Tower","summary":"Face Ravienna and witness the end of the chapter.","steps":[{"text":"Defeat Ravienna"},{"text":"Witness the ending"}]},
}
const VILLAGE_QUESTS = ["village_clear_approach","village_crimson_duel","village_clear_ruins","village_nyx_duel","village_gerald_trial"]
const JOURNAL_IDS = ["village_clear_approach","village_crimson_duel","village_clear_ruins","village_nyx_duel","village_gerald_trial","gerald_story","elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","cassien_resurrection","forsaken_braziers","ravienna_finale"]

static func journal_definition(id: String) -> Dictionary:
	return STORY_ENTRIES[id] if STORY_ENTRIES.has(id) else ContentDB.get_quest(id)

static func journal_step_index(id: String) -> int:
	var flags = GameState.quest_domain.flags
	if id == "gerald_story":
		return 2 if flags.get("village_gerald_backstory_seen",false) else (1 if flags.get("village_gerald_defeated",false) else 0)
	if id == "ravienna_finale":
		return 2 if flags.get("ravienna_ending_seen",false) else (1 if flags.get("revienna_defeated",false) else 0)
	return GameState.quest_domain.quest_step_index(id)

static func journal_state(zone: Node2D, id: String) -> String:
	if not STORY_ENTRIES.has(id):
		return GameState.quest_domain.quest_state(id)
	var step := journal_step_index(id)
	if step == 2:
		return "complete"
	if step == 1 or (id == "gerald_story" and index(zone)==0 and (GameState.quest_domain.quest_state("village_clear_approach")=="not_started" or GameState.quest_domain.quest_state("village_nyx_duel")=="complete")) or (id=="ravienna_finale" and (index(zone)==6 or GameState.quest_domain.flags.get("ravienna_resurrected",false))):
		return "active"
	return "not_started"

static func journal_step(id: String) -> Dictionary:
	var steps: Array = journal_definition(id).get("steps",[])
	var current := journal_step_index(id)
	return steps[current] if current < steps.size() else {}

const NAMES = ["Village","Royal Gardens","Royal Gate","Willow Fields","Elderwood Grove","Forsaken Ruins","Ruined Tower"]
const QUEST_ZONES = {"elathra_first_audience":1,"royal_gate_patrol":2,"willow_crossing":3,"elderwood_relics":4,"cassien_resurrection":5,"forsaken_braziers":5}

static func find_zone(node: Node) -> Node2D:
	return TRAVEL.find_zone(node)

static func index(zone: Node2D) -> int:
	return 0 if zone.name == "StandaloneVillage" else int(str(zone.name).right(2))

static func can_track(zone: Node2D, id: String) -> bool:
	var domain = GameState.quest_domain
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		return false
	if STORY_ENTRIES.has(id):
		return journal_state(zone,id)=="active"
	if id in VILLAGE_QUESTS:
		return index(zone)==0 and domain.quest_state(id)=="active"
	if not IDS.has(id) or domain.quest_state(id) == "complete":
		return false
	if domain.quest_state(id) == "active":
		return true
	return id == "elathra_first_audience" and index(zone) == 1

static func _target(zone: Node2D, node: Node2D, title: String, detail: String, quest_id: String = "", destination: int = -1) -> Dictionary:
	var result := {"title":title,"text":detail,"quest_id":quest_id,"valid":is_instance_valid(node),"destination":destination,"portal":destination>=0}
	if is_instance_valid(node):
		result["position"] = node.global_position
		var player := zone.get("checkpoint_player") as Node2D
		if is_instance_valid(player):
			var delta := node.global_position - player.global_position
			result["distance"] = delta.length()
			result["direction"] = delta.normalized()
	return result

static func _portal(zone: Node2D, toward: int) -> Dictionary:
	var current := index(zone)
	var next := current + (1 if toward > current else -1)
	if next < 0 or next >= NAMES.size():
		return {}
	var marker := zone.get_node_or_null("TransferPoints/" + ("ToNextZone" if next > current else "ToPreviousZone"))
	if marker != null:
		for child in marker.get_children():
			if child is Area2D and child.has_method("_story_unlocked"):
				if child._story_unlocked():
					return _target(zone,child,"Main story","Travel to " + NAMES[next],"",next)
				return {}
	return {}

static func _quest_target(zone: Node2D, id: String) -> Dictionary:
	var domain = GameState.quest_domain
	var def := ContentDB.get_quest(id)
	var step := domain.quest_step(id)
	var title := str(def.get("name",id))
	var detail := str(step.get("text",""))
	var target := str(step.get("target",""))
	var node: Node2D
	if id == "elathra_first_audience":
		node = zone.get_node_or_null("Zone/RoyalGardenV3Decorations/Elathra") as Node2D
	elif id == "cassien_resurrection":
		node = zone.get_node_or_null("CassienRitual") as Node2D
		detail = "Speak to Cassien and defeat him" if domain.quest_step_index(id)==0 else "Return to Cassien at the tomb"
	elif str(step.get("type","")) == "explore":
		for candidate in zone.get_tree().get_nodes_in_group("quest_exploration_targets"):
			if candidate is Node2D and zone.is_ancestor_of(candidate) and str(candidate.get("objective_id")) == target:
				node = candidate
				break
	elif str(step.get("type","")) == "kill":
		var player := zone.get("checkpoint_player") as Node2D
		var nearest := INF
		for candidate in zone.get_tree().get_nodes_in_group("world_minimap_monsters"):
			if not candidate is Node2D or not zone.is_ancestor_of(candidate) or not candidate.visible or not "group_id" in candidate or bool(candidate.get("defeated")):
				continue
			var group := ContentDB.get_enemy_group(str(candidate.group_id))
			if not group.get("quest_kills",{}).has(target):
				continue
			var distance: float = player.global_position.distance_to(candidate.global_position) if player != null else 0.0
			if distance < nearest:
				nearest = distance
				node = candidate
		detail += " (%d/%d)" % [domain.quest_progress(id),int(step.get("count",1))]
	return _target(zone,node,title,detail,id)

static func _local(zone: Node2D) -> Dictionary:
	var domain = GameState.quest_domain
	var i := index(zone)
	if i == 0:
		if not bool(domain.flags.get("village_gerald_defeated",false)):
			for quest in VILLAGE_QUESTS:
				if domain.quest_state(quest) != "active":
					continue
				if quest == "village_gerald_trial":
					return _target(zone,zone.get_node_or_null("VillageMap/GeraldBossSpawn/GeraldChallenge") as Node2D,"The Fallen Guardian","Challenge Gerald with your allies",quest)
				return _quest_target(zone,quest)
			var sync := zone.get_node_or_null("StoryVillageProgressionSync")
			if sync != null and not bool(sync.get("_fresh")):
				return _target(zone,null,"Village","Connecting to verified story progress")
			return _target(zone,zone.get_node_or_null("VillageMap/GeraldBossSpawn/GeraldChallenge") as Node2D,"The Fallen Guardian","Speak to Gerald and defeat him","gerald_story")
		if bool(domain.flags.get("village_gerald_backstory_pending",false)):
			return _target(zone,null,"The Fallen Guardian","Witness Gerald's memories","gerald_story")
	elif i == 1 and zone.has_node("StoryGardenCombatSync"):
		var sync = zone.get_node("StoryGardenCombatSync")
		if sync.audience_state() != "complete":
			return _target(zone,zone.get_node_or_null("Zone/RoyalGardenV3Decorations/Elathra") as Node2D,"Royal Gardens","Speak to Elathra","elathra_first_audience")
		if not sync.royal_gate_unlocked():
			return _target(zone,zone.get_node_or_null("MireneEncounter") as Node2D,"The Crimson Fool","Defeat Mirène")
	elif i == 6:
		if not bool(domain.flags.get("ravienna_ending_seen",false)):
			var text := "Speak to Ravienna and defeat her" if not bool(domain.flags.get("revienna_defeated",false)) else "Speak to Ravienna to finish the story"
			return _target(zone,zone.get_node_or_null("ReviennaEncounter") as Node2D,"The Eclipse Sovereign",text,"ravienna_finale")
	else:
		var id: String = IDS[i-1]
		if i == 5 and domain.quest_step_index(id)>0 and domain.quest_state(id)!="complete" and domain.quest_state("forsaken_braziers")!="complete":
			id = "forsaken_braziers"
		if domain.quest_state(id)!="complete":
			return _quest_target(zone,id)
	return {}

static func resolve(zone: Node2D) -> Dictionary:
	if zone != null and not MultiplayerGateway.standalone_expedition_id.is_empty():
		return SHARED_NAV.resolve(zone)
	if zone == null or not bool(GameState.quest_domain.flags.get("tutorial_complete",false)):
		return {}
	var domain = GameState.quest_domain
	if bool(domain.flags.get("chapter_tracking_paused",false)):
		return {}
	var current := index(zone)
	var manual := str(domain.flags.get("chapter_manual_quest",""))
	if can_track(zone,manual):
		var destination := 0 if manual=="gerald_story" or manual in VILLAGE_QUESTS else (6 if manual=="ravienna_finale" else int(QUEST_ZONES[manual]))
		if destination != current:
			var route := _portal(zone,destination)
			if not route.is_empty():
				route["quest_id"]=manual
				return route
		elif STORY_ENTRIES.has(manual) or manual == "village_gerald_trial":
			return _local(zone)
		elif manual != "cassien_resurrection" or domain.quest_step_index(manual)==0 or domain.quest_state("forsaken_braziers")=="complete":
			return _quest_target(zone,manual)
	var local := _local(zone)
	if not local.is_empty():
		return local
	if bool(domain.flags.get("ravienna_ending_seen",false)):
		return {}
	if current<6:
		return _portal(zone,current+1)
	return {}
