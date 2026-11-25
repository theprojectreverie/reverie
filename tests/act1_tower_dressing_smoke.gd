extends SceneTree

const WORLD_PREVIEW: PackedScene = preload("res://scenes/world/act1_world_structure.tscn")

func _initialize() -> void:
	var world := WORLD_PREVIEW.instantiate() as Node2D
	assert(world != null, "Act I composition preview instantiates")
	var dressing := world.get_node_or_null("RuinedTowerDressing") as Node2D
	assert(dressing != null, "Ruined Tower dressing root exists")
	var required := [
		"TowerDeadTree",
		"TowerCorruptionWest",
		"TowerCorruptionEast",
		"TowerCorruptionNorth",
		"TowerCorruptionSouth",
		"TowerDeadwoodWest",
		"TowerDeadwoodEast",
		"TowerPillarWest",
		"TowerPillarEast",
		"TowerCorruptTree"
	]
	for child_name in required:
		var sprite := dressing.get_node_or_null(child_name) as Sprite2D
		assert(sprite != null, "Authored tower sprite exists: " + child_name)
		assert(sprite.texture != null, "Authored tower texture loads: " + child_name)
		assert(sprite.visible, "Authored tower sprite is visible: " + child_name)
	assert(dressing.get_child_count() == required.size(), "Tower dressing contains exactly the reviewed authored placements")
	print("ACT1_TOWER_DRESSING_PASS placements=", required.size(), " corruption=true deadwood=true pillars=true")
	world.free()
	quit()
