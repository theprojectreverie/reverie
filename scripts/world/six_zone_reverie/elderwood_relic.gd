extends Interactable
const QUEST := "elderwood_relics"
@export var objective_id: String
@export var relic_name: String
@export_multiline var inscription: String
@onready var label: Label = $ObjectiveLabel
func _ready() -> void:
	super._ready()
	interaction_radius = 125.0
	prompt = "Examine " + relic_name
	add_to_group("quest_exploration_targets")
	EventBus.quest_updated.connect(_refresh)
	_refresh()
func refresh_shared_objective() -> void:
	var sync = get_parent().get_parent().get_node_or_null("CoopWorldSync")
	enabled = sync != null and sync.next_exploration_objective() == objective_id
	label.visible = enabled

func _refresh(_id: String = "") -> void:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		refresh_shared_objective()
		return
	enabled = GameState.quest_domain.quest_state(QUEST) == "active" and str(GameState.quest_domain.quest_step(QUEST).get("target", "")) == objective_id and MultiplayerGateway.standalone_expedition_id.is_empty()
	label.visible = enabled
func interact() -> void:
	if not can_interact():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or not player.input_enabled or player.global_position.distance_to(global_position) > interaction_radius:
		return
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		var sync = get_parent().get_parent().get_node_or_null("CoopWorldSync")
		if sync != null and sync._snapshot_ready and not player.network_recovery_paused:
			if MultiplayerGateway.request_exploration_objective(objective_id) == OK:
				EventBus.toast_requested.emit(inscription)
		return
	EventBus.toast_requested.emit(inscription)
	GameState.quest_domain.advance_quest(QUEST)
	if GameState.quest_domain.quest_ready(QUEST):
		GameState.quest_domain.complete_quest(QUEST)
