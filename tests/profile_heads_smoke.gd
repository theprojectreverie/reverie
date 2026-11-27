extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var p = load("res://scripts/ui/social_portrait.gd")
	var f = FileAccess.open("res://backend/api/src/routes/social.ts",FileAccess.READ)
	var ids = JSON.parse_string(f.get_as_text().split("export const PROFILE_PICTURES=")[1].split(" as const;")[0])
	var checked := 0
	for id in ids:
		var t: Texture2D = p.texture(id)
		assert(t != null, id)
		assert(t.get_size() == Vector2(512,512), id)
		assert(t.resource_path == p.PROFILE_HEAD_DIR+id+".png", id)
		assert(not t is AtlasTexture, id)
		assert(p.texture(id) == t, id)
		checked += 1
	assert(checked == 17)
	assert(p.PROFILE_IDS.size() == checked)
	assert(p.texture("gerald") == p.texture("kael_avatar"))
	assert(not p.has_profile_art("nyx"))
	assert(load("res://scripts/ui/screens/social_screen.gd") != null)
	assert(p.legacy_texture("gerald_mythic") != null)
	var tile = load("res://scenes/ui/components/portrait_gallery_tile.tscn").instantiate()
	assert(tile.get_theme_constant("icon_max_width") == 80)
	tile.free()
	print("PASS: ",checked," PFPs, identical 512x512 source size, shared tile width, no runtime atlas crops")
	quit()
