extends SceneTree

const MANIFEST_PATH := "res://assets/incoming/royal_garden_assets_v1/manifest.json"
const SPRITE_ROOT := "res://assets/incoming/royal_garden_assets_v1/"

func _initialize() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("ROYAL_GARDEN_ASSET_QA: manifest missing")
		quit(1)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("ROYAL_GARDEN_ASSET_QA: invalid manifest JSON")
		quit(1)
		return
	var assets: Array = parsed.get("assets", [])
	if assets.size() != 59:
		push_error("ROYAL_GARDEN_ASSET_QA: expected 59 assets, found %d" % assets.size())
		quit(1)
		return

	var failures: Array[String] = []
	var transparent_count := 0
	var total_pixels := 0
	var project_file := FileAccess.open("res://project.godot", FileAccess.READ)
	var nearest_filter_ok := false
	if project_file != null:
		nearest_filter_ok = project_file.get_as_text().contains("textures/canvas_textures/default_texture_filter=0")
	if not nearest_filter_ok:
		failures.append("project default texture filter is not nearest-neighbor")

	for record in assets:
		if not record is Dictionary:
			failures.append("manifest record is not a dictionary")
			continue
		var relative_path := str(record.get("file", ""))
		var resource_path := SPRITE_ROOT + relative_path
		if not FileAccess.file_exists(resource_path):
			failures.append("missing file: " + resource_path)
			continue
		var import_file := FileAccess.open(resource_path + ".import", FileAccess.READ)
		if import_file == null:
			failures.append("missing Godot import settings: " + relative_path)
			continue
		var import_text := import_file.get_as_text()
		if not import_text.contains("mipmaps/generate=false") or not import_text.contains("compress/mode=0"):
			failures.append("pixel-art import settings are not lossless/no-mipmap: " + relative_path)
			continue
		var texture := ResourceLoader.load(resource_path) as Texture2D
		if texture == null:
			failures.append("Godot could not import: " + resource_path)
			continue
		var image := texture.get_image()
		if image == null or image.is_empty():
			failures.append("empty image: " + resource_path)
			continue
		var expected := str(record.get("png_size", ""))
		var expected_parts := expected.split("x")
		if expected_parts.size() != 2 or image.get_width() != int(expected_parts[0]) or image.get_height() != int(expected_parts[1]):
			failures.append("dimension mismatch: %s expected=%s actual=%dx%d" % [relative_path, expected, image.get_width(), image.get_height()])
			continue

		var has_transparent := false
		var has_visible := false
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				has_transparent = has_transparent or alpha < 0.99
				has_visible = has_visible or alpha > 0.01
		total_pixels += image.get_width() * image.get_height()
		if not has_transparent:
			failures.append("background is not transparent: " + relative_path)
		if not has_visible:
			failures.append("sprite is fully transparent: " + relative_path)
		if has_transparent and has_visible:
			transparent_count += 1

	if not failures.is_empty():
		for failure in failures:
			push_error("ROYAL_GARDEN_ASSET_QA: " + failure)
		print("ROYAL_GARDEN_ASSET_QA_FAILED=", failures.size())
		quit(1)
		return

	print("ROYAL_GARDEN_ASSET_QA_PASS")
	print("ASSETS_IMPORTED=", assets.size())
	print("TRANSPARENT_SPRITES=", transparent_count)
	print("PIXELS_CHECKED=", total_pixels)
	print("GRID_UNIT=", parsed.get("grid_unit", "unknown"))
	print("NEAREST_FILTER=", nearest_filter_ok)
	print("LOSSLESS_NO_MIPMAP_IMPORTS=", assets.size())
	quit(0)
