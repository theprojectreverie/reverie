extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(ContentDB.validation_errors.is_empty(), str(ContentDB.validation_errors))
	var banner: Dictionary = ContentDB.get_banner("crimson_fool")
	assert(banner.featured == ["mirene_mythic"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := GachaService.pull(banner, rng, {"legendary": 0, "featured": 159, "epic_streak": 0}, 1)
	assert(result.results[0].character_id == "mirene_mythic" and result.results[0].rarity == "mythic" and result.results[0].featured)
	var paid := GachaService.pull(banner, rng, GachaService.empty_pity(), 1, 99)
	assert(paid.results[0].character_id == "mirene_mythic" and paid.results[0].paid_guaranteed)
	var gacha := (load("res://scenes/ui/gacha_screen.tscn") as PackedScene).instantiate() as GachaScreen
	add_child(gacha)
	for i in range(5): await get_tree().process_frame
	gacha._select_banner("crimson_fool")
	for i in range(5): await get_tree().process_frame
	assert(gacha._featured_id == "mirene_mythic")
	var hero := gacha.get_node("BannerHero") as PortraitView
	var bg := gacha.get_node("SummoningChamberIllustration") as TextureRect
	assert(not hero.visible and hero.portrait_texture == null)
	assert(bg.texture.resource_path == "res://assets/portraits/banners/mirene_background.png")
	assert(is_equal_approx(bg.anchor_right, 1.0))
	assert(gacha._tabs.get_child_count() == gacha.active_banner_catalog().size())
	assert(gacha.active_banner_catalog().size() == 6)
	assert(not gacha.active_banner_catalog().has("scarlet_requiem") and not gacha.active_banner_catalog().has("crimson_covenant"))
	var stage = gacha._banner_content._stage
	assert(not stage.opened and stage.actions.get_child_count() == 2)
	stage.set_open(true, false)
	await get_tree().process_frame
	assert(stage.opened and stage.drawer.visible)
	gacha._select_banner("crimson_oath")
	for i in range(5): await get_tree().process_frame
	assert(is_equal_approx(hero.anchor_right, 1.0) and is_equal_approx(hero.offset_top, 55.0))
	assert(is_equal_approx(bg.anchor_right, 1.2))
	print("CRIMSON_FOOL_PASS: independent art, Mythic reward, guarantees, drawer and banner reset")
	gacha.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
