extends SceneTree

const WORLD_PREVIEW: PackedScene = preload("res://scenes/world/act1_world_structure.tscn")

func _initialize() -> void:
	var world := WORLD_PREVIEW.instantiate() as Node2D
	assert(world != null, "Act I composition preview instantiates")
	var dressing := world.get_node_or_null("WillowFieldsDressing") as Node2D
	assert(dressing != null, "Willow Fields dressing root exists")
	var required := [
		"FarmsteadCottage",
		"WestWillow",
		"EastWillow",
		"OrchardBlossom",
		"SouthBlossom",
		"NorthWildflowers",
		"SouthWildflowers",
		"FieldFernWest",
		"FieldFernEast",
		"MossyFieldStone"
	]
	for child_name in required:
		var sprite := dressing.get_node_or_null(child_name) as Sprite2D
		assert(sprite != null, "Authored Willow Fields sprite exists: " + child_name)
		assert(sprite.texture != null, "Authored Willow Fields texture loads: " + child_name)
		assert(sprite.visible, "Authored Willow Fields sprite is visible: " + child_name)
	var windmill := world.get_node_or_null("LandmarkNodes/WillowWindmill") as Sprite2D
	assert(windmill != null and windmill.texture != null, "PixelPen windmill landmark remains")
	assert(dressing.get_child_count() == required.size(), "Willow Fields dressing contains exactly the reviewed authored placements")
	print("ACT1_WILLOW_DRESSING_PASS placements=", required.size(), " windmill=true cottage=true orchard=true wildflowers=true")
	world.free()
	quit()
