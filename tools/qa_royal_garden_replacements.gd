extends SceneTree

const ROOT := "res://scenes/world/reverie_pack/Royal_Gardens/"
const CASES := [
	{"scene": "Decorations/lamp_post_gold.tscn", "size": Vector2i(64, 96), "offset": Vector2(32, 96)},
	{"scene": "Decorations/bench_stone_x.tscn", "size": Vector2i(96, 96), "offset": Vector2(48, 96)},
	{"scene": "Decorations/fountain_small_1x1.tscn", "size": Vector2i(96, 96), "offset": Vector2(48, 96)},
	{"scene": "Decorations/banner_royal_01.tscn", "size": Vector2i(64, 96), "offset": Vector2(32, 96)},
	{"scene": "Decorations/flower_pot_01.tscn", "size": Vector2i(64, 64), "offset": Vector2(32, 64)},
	{"scene": "Vegetation/rose_bush_01.tscn", "size": Vector2i(64, 64), "offset": Vector2(32, 64)},
	{"scene": "Vegetation/hedge_corner_1x1.tscn", "size": Vector2i(96, 96), "offset": Vector2(48, 96)},
	{"scene": "Vegetation/hedge_x_2x1.tscn", "size": Vector2i(96, 96), "offset": Vector2(48, 96)},
	{"scene": "Vegetation/tree_topiary_cone.tscn", "size": Vector2i(64, 96), "offset": Vector2(32, 96)}
]

func _initialize() -> void:
	var failures: Array[String] = []
	var checked := 0
	for item in CASES:
		var scene_path := ROOT + str(item.scene)
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed == null:
			failures.append("scene failed to load: " + scene_path)
			continue
		var instance := packed.instantiate()
		var sprite := instance.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			failures.append("missing Sprite2D texture: " + scene_path)
			instance.free()
			continue
		var image := sprite.texture.get_image()
		if image == null or image.is_empty():
			failures.append("texture image unavailable: " + scene_path)
		else:
			var expected: Vector2i = item.size
			var actual := Vector2i(image.get_width(), image.get_height())
			if actual != expected:
				failures.append("%s dimensions expected %s got %s" % [scene_path, str(expected), str(actual)])
			var alpha_visible := false
			var alpha_clear := false
			for y in image.get_height():
				for x in image.get_width():
					var a := image.get_pixel(x, y).a
					alpha_visible = alpha_visible or a > 0.01
					alpha_clear = alpha_clear or a < 0.99
			if not alpha_visible or not alpha_clear:
				failures.append("transparent sprite alpha validation failed: " + scene_path)
			if sprite.centered or sprite.offset != item.offset:
				failures.append("%s anchor expected %s got %s centered=%s" % [scene_path, str(item.offset), str(sprite.offset), str(sprite.centered)])
			if instance is ReveriePiece and (instance as ReveriePiece).footprint_cells.x < 1:
				failures.append("invalid footprint metadata: " + scene_path)
		instance.free()
		checked += 1
	if not failures.is_empty():
		for failure in failures:
			push_error("ROYAL_GARDEN_REPLACEMENT_QA: " + failure)
		print("ROYAL_GARDEN_REPLACEMENT_QA_FAILED=", failures.size())
		quit(1)
		return
	print("ROYAL_GARDEN_REPLACEMENT_QA_PASS")
	print("REPLACEMENT_SCENES=", checked)
	print("ALPHA_AND_ANCHOR_CHECKS=PASS")
	quit(0)
