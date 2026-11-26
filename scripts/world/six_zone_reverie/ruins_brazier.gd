extends Interactable
const QUEST := "forsaken_braziers"
@export var objective_id: String
@export var sequence_index: int
@onready var label: Label = $ObjectiveLabel
@onready var light: PointLight2D = $Brazier/Light
func _ready() -> void:
	super._ready()
	interaction_radius = 130.0
	prompt = "Purify brazier"
	add_to_group("quest_exploration_targets")
	EventBus.quest_updated.connect(_refresh)
	_refresh()
func refresh_shared_objective() -> void:
	var sync = get_parent().get_parent().get_node_or_null("CoopWorldSync")
	var purified: bool = sync != null and objective_id in sync.exploration_cleared
	enabled = sync != null and sync.next_exploration_objective() == objective_id
	label.visible = enabled
	light.color = Color(1.0, 0.82, 0.42) if purified else Color(0.77, 0.43, 0.94)
	light.energy = 0.6 if purified else 1.1

func _refresh(_id: String = "") -> void:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		refresh_shared_objective()
		return
	var state := GameState.quest_domain.quest_state(QUEST)
	var index := GameState.quest_domain.quest_step_index(QUEST)
	var purified := state == "complete" or (state == "active" and index > sequence_index)
	enabled = state == "active" and index == sequence_index and MultiplayerGateway.standalone_expedition_id.is_empty()
	label.visible = enabled
	light.color = Color(1.0, 0.82, 0.42) if purified else Color(0.77, 0.43, 0.94)
	light.energy = 0.6 if purified else 1.1
func interact() -> void:
	if not can_interact():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or not player.input_enabled or player.global_position.distance_to(global_position) > interaction_radius:
		return
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		if not player.network_recovery_paused:
			MultiplayerGateway.request_exploration_objective(objective_id)
		return
	GameState.quest_domain.advance_quest(QUEST)
	EventBus.toast_requested.emit("Brazier purified")
	if GameState.quest_domain.quest_ready(QUEST):
		GameState.quest_domain.complete_quest(QUEST)
