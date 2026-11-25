extends SceneTree

const WORLD_PATH := "res://scenes/world/castle_royal_gardens.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _check_uniform_parent_space(node: Sprite2D, expected: float, label: String) -> bool:
	if node == null:
		push_error("%s sprite is missing" % label)
		return false
	var parent_space: Transform2D = node.get_parent().transform * node.transform
	var x_scale: float = parent_space.x.length()
	var y_scale: float = parent_space.y.length()
	if absf(x_scale - y_scale) > 0.02 or absf(x_scale - expected) > 0.03 or absf(y_scale - expected) > 0.03:
		push_error("%s is stretched in the fence assembly: basis %.3f / %.3f (expected %.3f)" % [label, x_scale, y_scale, expected])
		return false
	print("FENCE ASPECT: PASS (%s, assembly scale %.3f x %.3f)" % [label, x_scale, y_scale])
	return true

func _run() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	if packed == null:
		push_error("Playable Royal Gardens scene must load")
		quit(1)
		return
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	await process_frame

	var fences := world.get_node("GardenFences")
	var checks := [
		_check_uniform_parent_space(fences.get_node("NorthPerimeterFence/NorthWestRail01") as Sprite2D, 1.9, "north rail"),
		_check_uniform_parent_space(fences.get_node("OuterSideFenceRuns/OuterWestRail01") as Sprite2D, 1.9, "outer side rail"),
		_check_uniform_parent_space(fences.get_node("OuterSideFenceRuns/OuterWestExtendedRail01") as Sprite2D, 1.9, "outer side extended rail"),
		_check_uniform_parent_space(fences.get_node("OuterSideFenceRuns/OuterEastExtendedRail01") as Sprite2D, 1.9, "outer east extended rail"),
		_check_uniform_parent_space(fences.get_node("FrontPerimeterFence/FrontWestRail01") as Sprite2D, 1.55, "front rail"),
		_check_uniform_parent_space(fences.get_node("NorthPerimeterFence/NorthWestOuterPillar") as Sprite2D, 1.55, "north pillar"),
		_check_uniform_parent_space(fences.get_node("OuterSideFenceRuns/OuterWestNorthPillar") as Sprite2D, 1.55, "side pillar"),
	]
	for passed in checks:
		if not passed:
			world.queue_free()
			quit(1)
			return
	print("ROYAL GARDEN FENCE ASPECT QA: PASS (north, side, front rails and posts retain proportional artwork)")
	world.queue_free()
	quit(0)
