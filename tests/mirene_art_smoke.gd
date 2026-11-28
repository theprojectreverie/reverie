extends SceneTree

func _initialize() -> void:
	var resolver = load("res://scripts/art/approved_character_portraits.gd")
	var cases = [
		["mirene", 0, "mirene_base.jpg"],
		["mirene_common", 0, "mirene_base.jpg"],
		["mirene_epic", 0, "mirene_base.jpg"],
		["mirene_legendary", 0, "mirene_legendary.png"],
		["mirene_mythic", 0, "mirene_mythic.png"],
		["mirene_mythic", 3, "mirene_ascended.png"]
	]
	for entry in cases:
		var tex: Texture2D = resolver.texture(entry[0], entry[1])
		if tex == null or not tex.resource_path.ends_with(entry[2]):
			printerr("FAIL ", entry)
			quit(1)
			return
		print("PASS ", entry[0], " / ", entry[1], " ", tex.resource_path, " ", tex.get_size())
	var banner = load("res://assets/portraits/banners/mirene_background.png") as Texture2D
	if banner == null:
		printerr("FAIL banner")
		quit(1)
		return
	print("PASS banner ", banner.get_size())
	quit(0)
