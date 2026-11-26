extends Node2D
const QUEST := "royal_gate_patrol"
func _ready() -> void:
	if OS.get_environment("REVERIE_STORY_WORLD_PILOT")=="1" and OS.get_environment("REVERIE_GARDENS_STORY_PILOT")=="1" and MultiplayerGateway.standalone_expedition_id.is_empty():return
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		# Keep authored Crownlings in co-op; server owns their combat and rewards.
		return
	EventBus.quest_updated.connect(_on_quest_updated)
	if bool(GameState.quest_domain.flags.get("tutorial_complete", false)):
		GameState.quest_domain.start_quest(QUEST)
		_on_quest_updated(QUEST)
func _on_quest_updated(id: String) -> void:
	if id == QUEST and GameState.quest_domain.quest_ready(QUEST):
		GameState.quest_domain.complete_quest(QUEST)
