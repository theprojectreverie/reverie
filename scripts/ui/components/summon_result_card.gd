class_name SummonResultCard
extends PanelContainer

const UPGRADE := preload("res://scripts/gacha/character_upgrade_card.gd")
const MOB := preload("res://scripts/gacha/mob_summon_reward.gd")
var premium: bool = false
var _portrait: PortraitView
var _name_label: Label
var _rarity_label: Label
var _tier_label: Label
var _status_label: Label

func setup(roll: Dictionary) -> void:
	var character_id := str(roll.get("character_id", ""))
	var definition: CharacterDef = ContentDB.get_character(character_id)
	var rarity := str(roll.get("rarity", "common"))
	var color := UITheme.rarity_color(rarity)
	premium = UITheme.is_premium_rarity(rarity)
	var effect := UITheme.rarity_effect(rarity)
	var glow: Color = effect.get("glow", UITheme.GOLD_BRIGHT)
	var card_bg := Color("#0d1526")
	var card_border := color
	var border_width := 2
	if premium:
		card_bg = card_bg.lerp(Color(glow.r, glow.g, glow.b, 1.0), 0.10)
		card_border = Color(glow.r, glow.g, glow.b, 0.95)
		border_width = int(effect.get("border_width", 3))
	add_theme_stylebox_override("panel", UITheme.style(card_bg, card_border, 10, border_width, 8))
	_portrait = get_node("Content/Portrait") as PortraitView
	_name_label = get_node("Content/Name") as Label
	_rarity_label = get_node("Content/Rarity") as Label
	_tier_label = get_node("Content/Tier") as Label
	_status_label = get_node("Content/Status") as Label
	var upgrade := UPGRADE.definition(character_id)
	var mob := MOB.definition(character_id)
	var source_id := str(upgrade.get("portrait_id", character_id))
	var base := preload("res://scripts/ui/portrait_framing.gd").base_id(source_id)
	var authored: Texture2D = null
	if not mob.is_empty():
		authored = MOB.texture(mob)
	elif base in ["kael", "gerald", "lilith"]:
		authored = load("res://assets/portraits/summon/%s.png" % base) as Texture2D
	else:
		authored = preload("res://scripts/ui/portrait_framing.gd").authored_texture(source_id, "card")
	# Resolve the source once, before the portrait enters the scene tree.
	# Card-only IDs are not playable definitions and must not need one for art.
	if definition != null:
		_portrait.setup(definition.palette,definition.race,definition.element,rarity,definition.portrait_seed)
	_portrait.character_id = source_id
	_portrait.rarity = rarity
	_portrait.fit_mode = "art"
	_portrait.set_portrait_texture(authored)
	_portrait.visible = authored != null
	var result_name := str(mob.name) if not mob.is_empty() else (definition.display_name if definition != null else character_id)
	# Variant copies share the original character identity; rarity is already
	# shown on its own line, so remove the redundant aspect suffix here.
	for aspect in ["Common", "Rare", "Epic", "Legendary", "Mythic"]:
		result_name = result_name.trim_suffix(" (" + aspect + " Aspect)")
	_name_label.text = str(upgrade.name) if not upgrade.is_empty() else result_name
	_rarity_label.text = "Upgrade source" if not mob.is_empty() else rarity.capitalize()
	if not upgrade.is_empty():
		_rarity_label.text = rarity.capitalize() + " card"
	_rarity_label.add_theme_color_override("font_color", color)
	_tier_label.visible = premium
	if premium:
		_tier_label.text = "✦ " + UITheme.rarity_tier_label(rarity) + " ✦"
		_tier_label.add_theme_color_override("font_color", glow)
	# Keep every meaningful result tag visible. The old mutually-exclusive
	# chain hid NEW / awakening / guaranteed whenever a unit was featured.
	var tags: Array[String] = []
	if not mob.is_empty():
		tags.append(MOB.description(roll.get("items", mob.items)))
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not upgrade.is_empty():
		tags.append(UPGRADE.status(roll))
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if roll.has("mythic_count"):
		var evolved: Array = roll.get("fusions", [])
		tags.append("Fused: " + str(evolved.back().name) if not evolved.is_empty() else "Mythic %d/7" % int(roll.mythic_count))
	if roll.has("ascended_count"):
		tags.append("FULLY ASCENDED" if int(roll.ascended_count) >= 7 else "Ascension %d/7" % int(roll.ascended_count))
	var status_color := UITheme.TEXT_DIM
	if bool(roll.get("featured", false)):
		tags.append("FEATURED")
		status_color = UITheme.GOLD
	if bool(roll.get("is_new", false)):
		tags.append("NEW")
		if not bool(roll.get("featured", false)):
			status_color = UITheme.GREEN
	elif int(roll.get("awakening_gain", 0)) > 0:
		tags.append("AWAKENING +%d" % int(roll.get("awakening_gain", 0)))
		if not bool(roll.get("featured", false)):
			status_color = UITheme.TEAL
	if bool(roll.get("paid_guaranteed", false)):
		tags.append("PAID MILESTONE")
		status_color = UITheme.VIOLET
	if bool(roll.get("guaranteed", false)):
		tags.append("GUARANTEED")
		if tags.size() == 1:
			status_color = UITheme.VIOLET
	_status_label.text = " · ".join(tags)
	_status_label.visible = not tags.is_empty()
	_status_label.add_theme_color_override("font_color", status_color)
