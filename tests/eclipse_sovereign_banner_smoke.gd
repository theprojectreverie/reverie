extends Node

func _ready() -> void:
	call_deferred("_run")

func _find_portrait(node: Node) -> PortraitView:
	if node is PortraitView:
		var p := node as PortraitView
		if p.portrait_texture != null and p.portrait_texture.resource_path.ends_with("/ravienna_character.png"):
			return p
	for child in node.get_children():
		var result := _find_portrait(child)
		if result != null: return result
	return null

func _run() -> void:
	var db := get_node("/root/ContentDB")
	assert(db.validation_errors.is_empty(), str(db.validation_errors))
	var banner: Dictionary = db.get_banner("eclipse_sovereign")
	assert(banner.get("featured") == ["ravienna_mythic"])
	assert(db.get_character("ravienna") != null)
	var gacha := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	add_child(gacha)
	for i in range(4): await get_tree().process_frame
	gacha._select_banner("eclipse_sovereign")
	for i in range(4): await get_tree().process_frame
	assert(gacha._featured_id == "ravienna_mythic")
	var portrait := _find_portrait(gacha)
	assert(portrait != null)
	assert(portrait.portrait_texture.get_size() == (load("res://assets/portraits/banners/ravienna_character.png") as Texture2D).get_size())
	assert(gacha.get_node("SummoningChamberIllustration").texture.resource_path == "res://assets/portraits/banners/eclipse_sovereign_background.png")
	assert(gacha._tabs.get_child_count() == gacha.active_banner_catalog().size())
	print("ECLIPSE_SOVEREIGN_UI_PASS: five banners, independent Ravienna and chamber layers, native aspect ratio, featured definition")
	gacha.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
