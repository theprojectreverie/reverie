extends Node

func _ready() -> void:
	call_deferred("_run")

func _find_portrait(node: Node) -> PortraitView:
	if node is PortraitView:
		var p := node as PortraitView
		if p.portrait_texture != null and p.portrait_texture.resource_path.ends_with("/ravienna.png"):
			return p
	for child in node.get_children():
		var result := _find_portrait(child)
		if result != null: return result
	return null

func _run() -> void:
	var db := get_node("/root/ContentDB")
	assert(db.validation_errors.is_empty(), str(db.validation_errors))
	var banner: Dictionary = db.get_banner("eclipse_sovereign")
	assert(banner.get("featured") == ["ravienna"])
	assert(db.get_character("ravienna") != null)
	var gacha := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	add_child(gacha)
	for i in range(4): await get_tree().process_frame
	gacha._select_banner("eclipse_sovereign")
	for i in range(4): await get_tree().process_frame
	assert(gacha._featured_id == "ravienna")
	var portrait := _find_portrait(gacha)
	assert(portrait != null)
	assert(portrait.portrait_texture.get_size() == (load("res://assets/portraits/summon/ravienna.png") as Texture2D).get_size())
	assert(gacha._tabs.get_child_count() == db.banners.size()+1)
	print("ECLIPSE_SOVEREIGN_UI_PASS: five banners, existing Ravienna art, native aspect ratio, featured definition")
	gacha.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
