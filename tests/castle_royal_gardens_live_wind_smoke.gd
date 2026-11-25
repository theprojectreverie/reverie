extends SceneTree
const SCENE := "res://scenes/world/castle_royal_gardens.tscn"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load(SCENE) as PackedScene
	assert(packed != null, "Royal Gardens world scene failed to load")
	var world := packed.instantiate() as Node2D
	root.add_child(world)
	await process_frame
	await process_frame
	var expansion := world.get_node_or_null("ExpansionBuilder") as Node2D
	assert(expansion != null, "Live world is missing ExpansionBuilder")
	var flora := expansion.get_node_or_null("ExpansionFlora") as Node2D
	assert(flora != null, "Live expansion is missing ExpansionFlora")
	var live_count := 0
	var wind_count := 0
	for piece in flora.get_children():
		var sprite := piece.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		live_count += 1
		var material := sprite.material as ShaderMaterial
		if material != null and material.shader != null and material.shader.code.contains("canopy_weight"):
			wind_count += 1
		print("LIVE ROYAL GARDENS FLORA: %s | world_visible=%s | wind=%s" % [piece.name, str(piece.is_visible_in_tree()), str(material != null and material.shader != null and material.shader.code.contains("canopy_weight"))])
	print("LIVE ROYAL GARDENS RESULT: placed=%d wind=%d layer_visible=%s expansion_visible=%s" % [live_count, wind_count, str(flora.is_visible_in_tree()), str(expansion.is_visible_in_tree())])
	assert(live_count == 15, "Expected 15 placed flora/hedge nodes in live world; got %d" % live_count)
	assert(wind_count == 11, "Expected 11 wind-enabled tree/shrub sprites in live world; got %d" % wind_count)
	assert(flora.is_visible_in_tree(), "Live Royal Gardens flora is hidden by an ancestor")
	print("LIVE ROYAL GARDENS WIND: PASS")
	quit(0)
