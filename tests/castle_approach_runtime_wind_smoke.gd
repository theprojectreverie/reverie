extends SceneTree
const SCENE := "res://scenes/world/castle_gardens/components/castle_expansion_component.tscn"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load(SCENE) as PackedScene
	assert(packed != null, "Castle expansion composition failed to load")
	var castle := packed.instantiate() as Node2D
	root.add_child(castle)
	await process_frame
	var flora := castle.get_node_or_null("ExpansionFlora") as Node2D
	assert(flora != null, "ExpansionFlora layer missing")
	var placed := flora.get_children()
	var wind_count := 0
	for piece in placed:
		var sprite := piece.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null and sprite.material is ShaderMaterial:
			var shader_material := sprite.material as ShaderMaterial
			if shader_material.shader != null and shader_material.shader.code.contains("canopy_weight"):
				wind_count += 1
		print("CASTLE RUNTIME FLORA: %s | sprite=%s | visible=%s" % [piece.name, str(sprite != null and sprite.texture != null), str(piece.is_visible_in_tree())])
	print("CASTLE RUNTIME RESULT: placed=%d wind=%d layer_visible=%s" % [placed.size(), wind_count, str(flora.visible)])
	assert(placed.size() >= 11, "Expected at least 11 runtime flora placements; got %d" % placed.size())
	assert(wind_count == 11, "Expected 11 runtime wind-enabled sprites; got %d" % wind_count)
	assert(flora.visible, "ExpansionFlora is instantiated but hidden in the composed scene")
	print("CASTLE APPROACH RUNTIME WIND: PASS (%d live flora placements; %d wind-enabled and visible)" % [placed.size(), wind_count])
	quit(0)
