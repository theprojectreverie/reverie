extends Node

var _travel_events: Array = []
var _toast_events: Array = []


func _ready() -> void:
	EventBus.region_change_requested.connect(_on_region_change)
	EventBus.toast_requested.connect(_on_toast)
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/world/region_portal.tscn")
	assert(packed != null)
	var portal := packed.instantiate() as RegionPortal
	assert(portal != null)
	portal.setup("willow_fields", {
		"id": "qa_unlocked_route",
		"to": "elderwood_grove",
		"entry": "from_willow_fields",
		"label": "Elderwood Grove"
	})
	add_child(portal)
	await get_tree().process_frame

	assert(portal.can_interact())
	portal.interact()
	assert(_travel_events.size() == 1, "unlocked portal did not request exactly one transition")
	assert(_travel_events[0][0] == "elderwood_grove")
	assert(_travel_events[0][1] == "from_willow_fields")
	assert(_toast_events.size() == 1)

	portal.setup("willow_fields", {
		"id": "qa_locked_route",
		"to": "forsaken_ruins",
		"entry": "from_elderwood",
		"label": "Forsaken Ruins",
		"requires_quest": "__qa_missing_quest__",
		"locked_message": "The seal holds."
	})
	portal._refresh_presentation()
	assert(not portal._requirement_met(), "missing quest unexpectedly unlocked portal")
	assert(portal.get_node("Label").text == "Sealed Road")
	portal.interact()
	assert(_travel_events.size() == 1, "locked portal emitted a transition")
	assert(_toast_events.size() == 2)
	assert(_toast_events[1] == "The seal holds.")

	portal.enabled = false
	assert(not portal.can_interact(), "disabled portal remained interactable")
	print("REGION PORTAL INTERACTION QA: PASS (unlocked transition payload, locked quest gate, authored label, disabled state)")
	get_tree().quit(0)


func _on_region_change(target: String, entry: String) -> void:
	_travel_events.append([target, entry])


func _on_toast(message: String) -> void:
	_toast_events.append(message)
