class_name CharacterInteractionComponent
extends Node
## Reusable interaction helper for characters/world actors.
## Can scan nearby Interactable nodes and emit prompts/requests without owning movement.

signal interactable_changed(interactable: Node)
signal interaction_prompt_changed(prompt: String)
signal interaction_requested(interactable: Node)

@export var scan_enabled: bool = true
@export var scan_interval: float = 0.12
@export var interaction_group: StringName = &"interactables"

var _owner_node: Node2D
var _scan_timer: Timer
var _current: Interactable
var _current_prompt: String = ""


func _ready() -> void:
	_owner_node = get_parent() as Node2D
	_scan_timer = get_node_or_null("ScanTimer") as Timer
	if _scan_timer != null:
		_scan_timer.wait_time = maxf(0.02, scan_interval)
		_scan_timer.timeout.connect(_on_scan_timeout)
		if scan_enabled:
			_scan_timer.start()


func _on_scan_timeout() -> void:
	if scan_enabled:
		refresh_nearest()


func refresh_nearest() -> Interactable:
	if _owner_node == null or not _owner_node.is_inside_tree():
		return null
	var best: Interactable = null
	var best_distance := INF
	for node in _owner_node.get_tree().get_nodes_in_group(interaction_group):
		if not (node is Interactable):
			continue
		var candidate := node as Interactable
		if not candidate.can_interact():
			continue
		var distance := _owner_node.global_position.distance_to(candidate.global_position)
		if distance <= candidate.interaction_radius and distance < best_distance:
			best = candidate
			best_distance = distance
	_set_current(best)
	return _current


func get_current() -> Interactable:
	return _current


func try_interact() -> bool:
	if _owner_node == null or not is_instance_valid(_owner_node) or _current == null or not is_instance_valid(_current):
		_set_current(null)
		return false
	if not _current.can_interact() or _owner_node.global_position.distance_to(_current.global_position) > _current.interaction_radius:
		_set_current(null)
		return false
	var target := _current
	interaction_requested.emit(target)
	target.interact()
	return true


func current_prompt() -> String:
	return _current.prompt if _current != null and is_instance_valid(_current) else ""


func _set_current(value: Interactable) -> void:
	var next_prompt := value.prompt if value != null and is_instance_valid(value) else ""
	if _current == value:
		if _current_prompt != next_prompt:
			_current_prompt = next_prompt
			interaction_prompt_changed.emit(_current_prompt)
		return
	if is_instance_valid(_current) and _current.tree_exiting.is_connected(_on_current_tree_exiting):
		_current.tree_exiting.disconnect(_on_current_tree_exiting)
	_current = value
	_current_prompt = next_prompt
	if is_instance_valid(_current) and _current.is_inside_tree():
		_current.tree_exiting.connect(_on_current_tree_exiting, CONNECT_ONE_SHOT)
	interactable_changed.emit(_current)
	interaction_prompt_changed.emit(_current_prompt)


func _on_current_tree_exiting() -> void:
	_set_current(null)
