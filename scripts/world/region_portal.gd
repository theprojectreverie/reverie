class_name RegionPortal
extends Interactable
## Authored scene-based region gate. Route identity and transition behavior
## are inspector-configurable; the portal's visuals live in region_portal.tscn.

@export var region_id: String = ""
@export var connection_id: String = ""
@export var target_region: String = ""
@export var entry_point: String = ""
@export var portal_label: String = "Travel"
@export var required_quest: String = ""
@export_multiline var locked_message: String = "The way remains sealed."

var target_region_name: String = ""
@onready var _label: Label = get_node_or_null("Label") as Label

func setup(p_region_id: String, p_connection: Dictionary) -> void:
	region_id = p_region_id
	connection_id = str(p_connection.get("id", ""))
	target_region = str(p_connection.get("to", ""))
	entry_point = str(p_connection.get("entry", ""))
	portal_label = str(p_connection.get("label", "Travel"))
	required_quest = str(p_connection.get("requires_quest", ""))
	locked_message = str(p_connection.get("locked_message", "The way remains sealed."))
	_refresh_target_name()

func _ready() -> void:
	super._ready()
	interaction_radius = 110.0
	_refresh_target_name()
	_refresh_presentation()

func _refresh_target_name() -> void:
	if not target_region.is_empty():
		var definition: Dictionary = ContentDB.get_region(target_region)
		target_region_name = str(definition.get("name", target_region))

func _refresh_presentation() -> void:
	var unlocked := _requirement_met()
	prompt = ("Travel to " if unlocked else "Sealed: ") + portal_label
	if is_instance_valid(_label):
		_label.text = portal_label if unlocked else "Sealed Road"

func can_interact() -> bool:
	_refresh_presentation()
	return enabled and visible and not target_region.is_empty() and not entry_point.is_empty()

func _requirement_met() -> bool:
	return required_quest.is_empty() or GameState.quest_domain.quest_state(required_quest) == "complete"

func interact() -> void:
	if not can_interact():
		return
	if not _requirement_met():
		EventBus.toast_requested.emit(locked_message)
		return
	AudioDirector.play_variant("portal_transition")
	EventBus.region_change_requested.emit(target_region, entry_point)
	EventBus.toast_requested.emit("Travelling to " + target_region_name)
