extends SceneTree

const WORLD_PREVIEW: PackedScene = preload("res://scenes/world/act1_world_structure.tscn")

func _initialize() -> void:
	var world := WORLD_PREVIEW.instantiate() as Node2D
	assert(world != null, "Act I composition preview instantiates")
	var dressing := world.get_node_or_null("ElderwoodDressing") as Node2D
	assert(dressing != null, "Elderwood Grove dressing root exists")
	var required := [
		"ElderwoodTreeWest",
		"ElderwoodTreeEast",
		"ElderwoodBridge",
		"ElderwoodCanopyWest",
		"ElderwoodCanopyEast",
		"AncientOakSapling",
		"GroveBlossom",
		"RiverbankShrubWest",
		"RiverbankShrubEast"
	]
	for child_name in required:
		var sprite := dressing.get_node_or_null(child_name) as Sprite2D
		assert(sprite != null, "Authored Elderwood sprite exists: " + child_name)
		assert(sprite.texture != null, "Authored Elderwood texture loads: " + child_name)
		assert(sprite.visible, "Authored Elderwood sprite is visible: " + child_name)
	var landmark := world.get_node_or_null("LandmarkNodes/ElderwoodAncientTree") as Sprite2D
	assert(landmark != null and landmark.texture != null, "Ancient tree landmark remains loaded")
	assert(dressing.get_child_count() == required.size(), "Elderwood dressing contains exactly the reviewed authored placements")
	print("ACT1_ELDERWOOD_DRESSING_PASS placements=", required.size(), " ancient_tree=true bridge=true canopy=true riverbank=true")
	world.free()
	quit()
