extends Interactable
## One authored, non-respawning village story encounter. Rewards stay in the existing combat pipeline.
@export var group_id: String
@export var quest_id: String
@export var requires_quest: String
@export var recruit_id: String
@export var label_text: String
var engaged := false
var defeated := false
const FIRST_QUEST := "village_clear_approach"
const FIRST_RECRUIT := "village_crimson_duel"
const SECOND_QUEST := "village_clear_ruins"
const SECOND_RECRUIT := "village_nyx_duel"
const FINAL_QUEST := "village_gerald_trial"

func _ready() -> void:
	super._ready()
	prompt = "Challenge " + label_text
	interaction_radius = 95.0
	add_to_group("world_action_targets")
	EventBus.battle_finished.connect(_on_battle_finished)
	EventBus.quest_updated.connect(_on_quest_updated)
	_refresh.call_deferred()

static func local_story_available() -> bool:
	return permits_local_story(AuthGateway.is_authenticated(), OS.has_feature("reverie_public_alpha"), preload("res://scripts/online/story_opening_world_sync.gd").pilot_enabled(), not MultiplayerGateway.standalone_expedition_id.is_empty())

static func permits_local_story(authenticated: bool, public_alpha: bool, pilot: bool, expedition: bool) -> bool:
	return not pilot and not expedition and (not authenticated or public_alpha)

func _on_quest_updated(_id: String) -> void:
	_refresh()

func _online_sync() -> Node:
	var zone := get_tree().current_scene
	if zone == null:
		return null
	return zone.get_node_or_null("StoryVillageProgressionSync")

func _refresh() -> void:
	var online := _online_sync()
	if online != null:
		defeated = online.won(group_id)
		enabled = online.ready_for_group(group_id, quest_id)
		visible = enabled
		if enabled:
			add_to_group("world_minimap_monsters")
		else:
			remove_from_group("world_minimap_monsters")
		return
	var q := GameState.quest_domain
	if local_story_available() and not bool(q.flags.get("village_gerald_defeated", false)) and q.quest_state(FIRST_QUEST) == "not_started":
		q.start_quest(FIRST_QUEST)
	defeated = bool(q.flags.get("village_encounter_won_" + group_id, false))
	enabled = local_story_available() and not bool(q.flags.get("village_gerald_defeated", false)) and not defeated and q.quest_state(quest_id) == "active" and (requires_quest.is_empty() or q.quest_state(requires_quest) == "complete")
	visible = enabled
	if enabled:
		add_to_group("world_minimap_monsters")
	else:
		remove_from_group("world_minimap_monsters")

func can_interact() -> bool:
	return super.can_interact() and not engaged and (local_story_available() or _online_sync() != null)

func interact() -> void:
	if not can_interact():
		return
	var zone := get_tree().current_scene
	if zone == null or zone.name != &"StandaloneVillage":
		return
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if not is_instance_valid(player) or not bool(player.get("input_enabled")) or player.global_position.distance_to(global_position) > interaction_radius:
		return
	engaged = true
	EventBus.encounter_requested.emit(group_id, self)

func receive_world_hit(amount: float) -> void:
	if amount > 0:
		interact()

func _on_battle_finished(result: Dictionary) -> void:
	if not engaged or str(result.get("group_id", "")) != group_id:
		return
	engaged = false
	var q := GameState.quest_domain
	if _online_sync() != null or not local_story_available() or not bool(result.get("victory", false)) or bool(q.flags.get("village_encounter_won_" + group_id, false)):
		return
	q.flags["village_encounter_won_" + group_id] = true
	if not recruit_id.is_empty():
		if not AuthGateway.is_authenticated() and not GameState.roster_domain.owns_character(recruit_id):
			GameState.roster_domain.add_character(recruit_id)
		q.flags["village_recruited_" + recruit_id] = true
		GameState.roster_domain.deploy_village_recruits()
		if AuthGateway.is_authenticated():
			EventBus.party_changed.emit()
		EventBus.toast_requested.emit(label_text + " joined Kael's team.")
	if q.quest_ready(quest_id):
		q.complete_quest(quest_id)
		var next := str({FIRST_QUEST:FIRST_RECRUIT,FIRST_RECRUIT:SECOND_QUEST,SECOND_QUEST:SECOND_RECRUIT,SECOND_RECRUIT:FINAL_QUEST}.get(quest_id,""))
		if not next.is_empty():
			q.start_quest(next)
	GameState.save_now()
	_refresh()
