extends SceneTree


func _initialize() -> void:
	var packed := load("res://scenes/world/castle_gardens/components/castle_water_assembly.tscn") as PackedScene
	assert(packed != null, "Authored Royal Gardens water assembly must load")
	var water := packed.instantiate() as CastleWaterComponent
	assert(water != null, "Water assembly must use CastleWaterComponent")
	root.add_child(water)
	await process_frame

	var west := IsoMath.grid_to_world(24.0, 10.5)
	var east := IsoMath.grid_to_world(30.0, 3.5)
	assert(CastleLayout.is_pond(24, 10) and CastleLayout.is_pond(30, 3), "Pond samples must match authored layout water cells")
	assert(water.is_water_world(west), "West reflecting pond center must be classified as water")
	assert(water.is_water_world(east), "East reflecting pond center must be classified as water")
	# Verify the continuous zone boundary itself, not only integer tile centers.
	# The authored radius is 1.25 grid units and the predicate is strictly inside.
	for center in [Vector2(24.0, 10.5), Vector2(30.0, 3.5)]:
		for offset in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
			assert(water.is_water_world(IsoMath.grid_to_world(center.x + offset.x, center.y + offset.y)), "Samples inside the authored pond radius must be water")
			assert(not water.is_water_world(IsoMath.grid_to_world(center.x + offset.x * 1.5, center.y + offset.y * 1.5)), "Samples outside the authored pond radius must be dry")
		assert(not water.is_water_world(IsoMath.grid_to_world(center.x + 1.25, center.y)), "The exact pond radius boundary must remain outside the strict water zone")
	for cell in CastleLayout.POND_LEFT + CastleLayout.POND_RIGHT:
		assert(water.is_water_world(IsoMath.grid_to_world(float(cell.x), float(cell.y))), "Every authored pond cell must be classified as water: %s" % cell)
	for cell in CastleLayout.WEST_POND_BYPASS:
		assert(CastleLayout.is_path(cell.x, cell.y), "Pond bypass sample must remain an authored path cell")
		assert(not water.is_water_world(IsoMath.grid_to_world(float(cell.x), float(cell.y))), "Pond bypass must remain dry and traversable: %s" % cell)
	# Sample the immediate grid ring around both authored ponds. Every cell
	# outside the six-cell water footprint must remain dry; this catches zones
	# whose radius spills onto neighboring grass or shoreline paths.
	for y in range(9, 13):
		for x in range(22, 27):
			if not CastleLayout.is_pond(x, y):
				assert(not water.is_water_world(IsoMath.grid_to_world(float(x), float(y))), "West pond zone must not spill beyond its authored footprint: (%d, %d)" % [x, y])
	for y in range(2, 6):
		for x in range(28, 33):
			if not CastleLayout.is_pond(x, y):
				assert(not water.is_water_world(IsoMath.grid_to_world(float(x), float(y))), "East pond zone must not spill beyond its authored footprint: (%d, %d)" % [x, y])
	assert(not water.is_water_world(IsoMath.grid_to_world(18.0, 10.0)), "Nearby garden grass must not be classified as water")
	assert(not water.is_water_world(IsoMath.grid_to_world(27.0, 10.0)), "Promenade between ponds must remain dry")
	print("ROYAL GARDENS POND ZONES: PASS (all 12 pond cells water; authored bypass and promenade dry)")

	water.queue_free()
	await process_frame
	quit(0)
