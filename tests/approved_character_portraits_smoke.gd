extends SceneTree
const ART = preload("res://scripts/art/approved_character_portraits.gd")
const SOCIAL = preload("res://scripts/ui/social_portrait.gd")
const FRAMING = preload("res://scripts/ui/portrait_framing.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var count := 0
	var reveal = load("res://scripts/ui/components/summon_reveal_overlay.gd").new()
	for base in ART.CHARACTERS:
		for tier in ["legendary", "mythic", "ascended", "human"]:
			var id: String = base + "_" + tier
			var t := ART.texture(id)
			assert(t != null, id)
			assert(t.resource_path == ART.path_for(id), id)
			assert(t.get_width() > 512 and t.get_height() > 512, id)
			assert(SOCIAL.texture(id).get_size() == Vector2(512,512), id)
			assert(FRAMING.authored_texture(id) == t, id)
			assert(PortraitAssetSource.texture_for(id,"collection") == t,id)
			assert(reveal._character_art(id) == t,id)
			count += 1
		var legend: String = base if base == "ravienna" else base + "_legendary"
		var mythic: String = base + "_mythic"
		var view = load("res://scenes/ui/components/portrait_view.tscn").instantiate()
		root.add_child(view)
		var def = root.get_node("ContentDB").get_character(legend)
		assert(def != null,legend)
		view.setup_character(def)
		assert(view.portrait_texture == ART.texture(legend),legend)
		assert(view.portrait_art.texture == view.portrait_texture,legend)
		def = root.get_node("ContentDB").get_character(mythic)
		assert(def != null,mythic)
		view.setup_character(def,"",2)
		assert(view.portrait_texture == ART.texture(mythic),mythic)
		view.setup_character(def,"",3)
		assert(view.portrait_texture == ART.texture(base+"_ascended"),mythic)
		assert(view.portrait_art.texture == view.portrait_texture,mythic)
		view.free()
		for id in [legend,mythic]:
			var card = load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
			root.add_child(card)
			card.setup({"character_id":id,"rarity":"mythic" if id.ends_with("_mythic") else "legendary"})
			assert(card._portrait.portrait_texture == ART.texture(id),id)
			card.free()
	reveal.free()
	for path in ["res://scripts/ui/components/collection_detail_component.gd","res://scripts/ui/components/collection_roster_component.gd","res://scripts/ui/screens/gacha_screen.gd","res://scripts/ui/combat/combat_hud_component.gd","res://scripts/ui/combat/combat_turn_order_component.gd","res://scripts/ui/combat/unit_card.gd","res://scripts/ui/screens/pause_menu.gd","res://scripts/ui/screens/guild_screen.gd","res://scripts/ui/dialogue_box.gd"]:
		assert(load(path).can_instantiate(),path)
	print("APPROVED FULL ART PASS ",count," originals, rarity, ascension, reveal, result cards, PFP isolation")
	quit()
