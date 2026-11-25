extends SceneTree
const PLACEMENT_SCENE := "res://scenes/world/castle_gardens/components/castle_expansion_approach_placements.tscn"
const FOLIAGE_ROOT := "res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load(PLACEMENT_SCENE) as PackedScene
	assert(packed != null, "Approach placement markers failed to load")
	var markers := packed.instantiate()
	root.add_child(markers)
	var flora_count := 0
	var wind_count := 0
	var static_hedge_count := 0
	for marker in markers.get_children():
		if not marker.has_meta("placement_type") or str(marker.get_meta("placement_type")) != "asset":
			continue
		if str(marker.get_meta("target_layer", "")) != "ExpansionFlora":
			continue
		flora_count += 1
		var asset_id := str(marker.get_meta("asset_id", ""))
		var asset := load(FOLIAGE_ROOT + asset_id + ".tscn") as PackedScene
		assert(asset != null, "Placed flora asset scene missing: " + asset_id)
		var instance := asset.instantiate()
		var sprite := instance.get_node_or_null("Sprite") as Sprite2D
		assert(sprite != null and sprite.texture != null, "Placed flora has no authored Sprite: " + asset_id)
		var material := sprite.material as ShaderMaterial
		if asset_id.begins_with("hedge_"):
			assert(material == null, "Architectural hedge should remain static: " + asset_id)
			static_hedge_count += 1
			print("CASTLE APPROACH PLACEMENT: %s | static=architectural | grid=%s" % [asset_id, str(marker.get_meta("grid_position"))])
		else:
			assert(material != null and material.shader != null and material.shader.code.contains("canopy_weight"), "Placed foliage has no wind material: " + asset_id)
			wind_count += 1
			print("CASTLE APPROACH PLACEMENT: %s | wind=enabled | grid=%s" % [asset_id, str(marker.get_meta("grid_position"))])
		instance.free()
	assert(flora_count > 0 and wind_count + static_hedge_count == flora_count, "Approach flora placements do not match their authored motion categories")
	assert(wind_count > 0 and static_hedge_count > 0, "Expected both wind-driven planting and static architectural hedges")
	print("CASTLE APPROACH PLACEMENT WIND: PASS (%d wind foliage, %d static architectural hedges, %d total)" % [wind_count, static_hedge_count, flora_count])
	quit(0)
