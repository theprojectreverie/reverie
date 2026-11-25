extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/world/region_portal.tscn")
	assert(packed != null, "portal scene failed to load")
	var portal := packed.instantiate()
	assert(portal != null, "portal failed to instantiate")
	portal.setup("willow_fields", {
		"id": "qa_portal_route",
		"to": "elderwood_grove",
		"entry": "from_willow_fields",
		"label": "Elderwood Grove"
	})
	root.add_child(portal)
	await process_frame
	assert(portal.has_node("Label"), "authored destination Label node missing")
	assert(not portal.has_node("Sprite"), "legacy placeholder Sprite node still present")
	assert(not portal.has_node("Glow"), "legacy placeholder Glow node still present")
	var label := portal.get_node("Label") as Label
	assert(label.text == "Elderwood Grove", "destination label did not resolve from route data")
	assert(portal.target_region == "elderwood_grove", "route destination data changed")
	assert(portal.entry_point == "from_willow_fields", "entry point data changed")
	print("REGION PORTAL AUTHORED SCENE: PASS (scene loads, authored label resolves, placeholder nodes absent, route data preserved)")
	quit(0)
