extends Node
var passed := 0
var failed := 0
func check_ok(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		push_error("FAIL: " + label)
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	var def: CharacterDef = ContentDB.get_character("elathra")
	check_ok(def != null, "Élathra resolves from ContentDB")
	if def != null:
		check_ok(def.display_name == "Élathra" and def.title == "The Lily of Shadows", "name and title parse correctly")
		check_ok(def.rarity == "legendary" and def.element == "dark", "Legendary Shadow classification parses")
		check_ok(def.skills.size() == 2 and def.ultimate == "hollow_wail", "two active skills and ultimate resolve")
		check_ok(def.passive_id == "hollow_crown", "supported passive resolves")
	var banner: Dictionary = ContentDB.get_banner("lily_of_shadows")
	check_ok(not banner.is_empty(), "featured banner loads")
	check_ok((banner.get("featured", []) as Array).has("elathra_mythic"), "Élathra is featured on her banner")
	check_ok((banner.get("pool", {}).get("legendary", []) as Array).has("elathra"), "Élathra is in the Legendary summon pool")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var forced := GachaService.pull(banner, rng, {"legendary": 79, "featured": 159, "epic_streak": 0}, 1)
	var results: Array = forced.get("results", [])
	check_ok(results.size() == 1 and str(results[0].get("character_id", "")) == "elathra_mythic" and bool(results[0].get("featured", false)), "featured pity guarantees Élathra at the configured threshold")
	var saved_roster: Array = GameState.roster.duplicate(true)
	var grant := GameState.add_character("elathra")
	var owned: CharacterInstance = grant.get("instance", null)
	var uid := owned.uid if owned != null else ""
	check_ok(bool(grant.get("is_new", false)) or GameState.owns_character("elathra"), "character can be granted into the player roster")
	check_ok(GameState.owns_character("elathra"), "roster ownership lookup recognizes Élathra")
	var collection_scene := load("res://scenes/ui/collection_screen.tscn") as PackedScene
	var collection := collection_scene.instantiate() as CollectionScreen if collection_scene != null else null
	check_ok(collection != null, "collection screen instantiates")
	if collection != null:
		add_child(collection)
		await get_tree().process_frame
		check_ok(collection._cards.has(uid), "Élathra appears as a card in the live collection grid")
		check_ok(collection._find_instance(uid) != null, "collection detail can resolve Élathra's owned instance")
		collection.queue_free()
		await get_tree().process_frame
	GameState.roster = saved_roster
	var scene := load("res://scenes/ui/gacha_screen.tscn") as PackedScene
	var gacha := scene.instantiate() as GachaScreen if scene != null else null
	check_ok(gacha != null, "summon scene instantiates")
	if gacha != null:
		add_child(gacha)
		await get_tree().process_frame
		check_ok(gacha._tabs != null and gacha._tabs.get_child_count() == gacha.active_banner_catalog().size(), "return control and all three banner tabs render")
		gacha._select_banner("lily_of_shadows")
		await get_tree().process_frame
		check_ok(gacha._selected_banner == "lily_of_shadows" and gacha._featured_id == "elathra_mythic", "Élathra summon page selects and binds featured character")
		var hero := gacha.get_node("BannerHero") as PortraitView
		var backdrop := gacha.get_node("SummoningChamberIllustration") as TextureRect
		check_ok(hero.portrait_texture != null and hero.portrait_texture.resource_path == "res://assets/portraits/banners/elathra_character.png", "approved independent Elathra art is selected")
		check_ok(backdrop.texture != null and backdrop.texture.resource_path == "res://assets/portraits/banners/lily_of_shadows_background.png", "independent conservatory background is selected")
		check_ok(is_equal_approx(backdrop.anchor_left, 0.0) and is_equal_approx(backdrop.anchor_right, 1.0), "Cassien zoom does not affect Elathra")
		gacha.queue_free()
		await get_tree().process_frame
	print("ELATHRA SMOKE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
