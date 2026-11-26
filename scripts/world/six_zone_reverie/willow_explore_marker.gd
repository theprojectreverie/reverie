extends Marker2D
@export var objective_id: String
@export var objective_radius := 100.0
const QUEST := "willow_crossing"
var shared_retry := 0.0
@onready var label: Label = $ObjectiveLabel
func _ready() -> void:
	add_to_group("quest_exploration_targets")
func _physics_process(delta: float) -> void:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		var sync = get_tree().current_scene.get_node_or_null("CoopWorldSync") if get_tree().current_scene != null else null
		if sync == null:
			sync = get_parent().get_parent().get_node_or_null("CoopWorldSync")
		var active_shared: bool = sync != null and sync._snapshot_ready and sync.next_exploration_objective() == objective_id
		label.visible = active_shared
		shared_retry = maxf(0.0, shared_retry - delta)
		if active_shared and shared_retry <= 0.0:
			var shared_player := get_tree().get_first_node_in_group("player") as Player
			if shared_player != null and shared_player.input_enabled and not shared_player.network_recovery_paused and shared_player.global_position.distance_to(global_position) <= objective_radius:
				shared_retry = 0.8
				MultiplayerGateway.request_exploration_objective(objective_id)
		return
	var active := GameState.quest_domain.quest_state(QUEST) == "active" and str(GameState.quest_domain.quest_step(QUEST).get("target", "")) == objective_id and MultiplayerGateway.standalone_expedition_id.is_empty()
	label.visible = active
	if not active:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or not player.input_enabled or player.global_position.distance_to(global_position) > objective_radius:
		return
	GameState.quest_domain.advance_quest(QUEST)
	AudioDirector.play_variant("quest_complete")
	if GameState.quest_domain.quest_ready(QUEST):
		GameState.quest_domain.complete_quest(QUEST)
