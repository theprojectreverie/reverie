class_name CollectibleObject
extends Interactable
## Reusable collectible/environmental pickup component.

signal collected(collectible_id: StringName, rewards: Dictionary)

@export var collectible_id: StringName = &""
@export var rewards: Dictionary = {}
@export var flag_key: String = ""
@export var collect_prompt: String = "Collect"
@export var collect_message: String = "Collected"


func _ready() -> void:
	super._ready()
	prompt = collect_prompt
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and not player.animation_finished.is_connected(_on_animation_finished):
		player.animation_finished.connect(_on_animation_finished)
	var key := _key()
	if not key.is_empty() and bool(GameState.quest_domain.flags.get(key, false)):
		enabled = false
		visible = false


func interact() -> void:
	if not can_interact():
		return
	var key := _key()
	if not key.is_empty():
		GameState.quest_domain.flags[key] = true
	if not rewards.is_empty():
		GameState.inventory_domain.grant_reward_items(rewards)
	GameState.queue_save()
	AudioDirector.play_variant("item_pickup")
	collected.emit(collectible_id, rewards.duplicate(true))
	EventBus.toast_requested.emit(collect_message)
	enabled = false
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation("collect"):
		player.play("collect")
	else:
		visible = false


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"collect":
		visible = false


func _key() -> String:
	if not flag_key.is_empty():
		return flag_key
	return "collectible:%s" % String(collectible_id) if collectible_id != &"" else ""
