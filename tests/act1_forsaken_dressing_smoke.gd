extends SceneTree

const WORLD_PREVIEW: PackedScene = preload("res://scenes/world/act1_world_structure.tscn")

func _initialize() -> void:
	var world := WORLD_PREVIEW.instantiate() as Node2D
	assert(world != null, "Act I composition preview instantiates")
	var dressing := world.get_node_or_null("ForsakenDressing") as Node2D
	assert(dressing != null, "Forsaken Ruins dressing root exists")
	var required := [
		"ForsakenDeadTree",
		"ForsakenCorruptTree",
		"ForsakenPillarWest",
		"ForsakenPillarEast",
		"ForsakenCorruptionWest",
		"ForsakenCorruptionEast",
		"ForsakenDeadwoodNorth",
		"ForsakenDeadwoodSouth",
		"ForsakenCorruptGrowth",
		"ForsakenBrokenPillar"
	]
	for child_name in required:
		var sprite := dressing.get_node_or_null(child_name) as Sprite2D
		assert(sprite != null, "Authored Forsaken Ruins sprite exists: " + child_name)
		assert(sprite.texture != null, "Authored Forsaken Ruins texture loads: " + child_name)
		assert(sprite.visible, "Authored Forsaken Ruins sprite is visible: " + child_name)
	assert(dressing.get_child_count() == required.size(), "Forsaken Ruins dressing contains exactly the reviewed authored placements")
	print("ACT1_FORSAKEN_DRESSING_PASS placements=", required.size(), " corruption=true deadwood=true ruins=true")
	world.free()
	quit()
