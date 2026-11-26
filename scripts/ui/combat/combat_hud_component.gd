class_name CombatHudComponent
extends Node
## Owns battle HUD refresh, party roster presentation, skill buttons and auto/speed controls.

var screen: CombatScreen
var _action_categories: GridContainer
var _category_buttons: Dictionary = {}
var _active_action_category: String = "attack"
var _status_icons: HBoxContainer
var _mobile_hud := false
var _mobile_log_open := false

const STATUS_ICON_SCENE: PackedScene = preload("res://scenes/ui/combat/components/battle_status_icon.tscn")
const SKILL_CARD_SCENE: PackedScene = preload("res://scenes/ui/combat/components/battle_skill_card.tscn")

const STATUS_ICON_PATHS: Dictionary = {
	"atk_up": "res://assets/ui/battle/icons/status/attack_modifier.png",
	"atk_down": "res://assets/ui/battle/icons/status/attack_modifier.png",
	"def_up": "res://assets/ui/battle/icons/status/defense_shield.png",
	"def_down": "res://assets/ui/battle/icons/status/defense_shield.png",
	"shield": "res://assets/ui/battle/icons/status/defense_shield.png",
	"regen": "res://assets/ui/battle/icons/status/regeneration.png",
	"poison": "res://assets/ui/battle/icons/status/poison.png",
	"stun": "res://assets/ui/battle/icons/status/stun.png",
	"spd_down": "res://assets/ui/battle/icons/status/slow.png",
}


func bind(owner_screen: CombatScreen) -> void:
	screen = owner_screen
	_status_icons = screen.get_node_or_null("CombatScreenLayout/Root/CombatBottomHUD/ActiveInfoPanel/InfoContent/StatusIcons") as HBoxContainer
	_action_categories = screen.get_node_or_null("CombatScreenLayout/Root/CombatBottomHUD/SkillsPanel/SkillsContent/ActionCategories") as GridContainer
	if _action_categories == null:
		push_error("Combat HUD is missing its authored action-category buttons.")
		return
	_category_buttons = {
		"attack": _action_categories.get_node("AttackButton") as TextureButton,
		"skill": _action_categories.get_node("SkillButton") as TextureButton,
		"ultimate": _action_categories.get_node("UltimateButton") as TextureButton,
		"defend": _action_categories.get_node("DefendButton") as TextureButton,
		"item": _action_categories.get_node("ItemButton") as TextureButton,
		"end_turn": _action_categories.get_node("EndTurnButton") as TextureButton,
	}
	for category in _category_buttons:
		var category_button := _category_buttons[category] as TextureButton
		category_button.pressed.connect(_on_action_category_pressed.bind(str(category)))
		category_button.mouse_entered.connect(_on_category_hover.bind(str(category), true))
		category_button.mouse_exited.connect(_on_category_hover.bind(str(category), false))
		category_button.focus_entered.connect(_on_category_hover.bind(str(category), true))
		category_button.focus_exited.connect(_on_category_hover.bind(str(category), false))
		category_button.focus_mode = Control.FOCUS_ALL
		AudioDirector.set_button_feedback(category_button, "confirm")
	_configure_mobile_hud()


func _on_action_category_pressed(category: String) -> void:
	if screen == null or screen._resolved or screen._animating:
		return
	match category:
		"defend":
			screen._defend()
		"end_turn":
			screen._end_turn()
		"item":
			screen._hint_label.text = "No usable battle items are available in the current inventory."
			screen._log("[color=#9aa8c2]No usable battle items are available.[/color]")
		_:
			_active_action_category = category
			refresh_skills()


func _update_category_buttons(actor: Combatant) -> void:
	for category in _category_buttons:
		var category_button := _category_buttons[category] as TextureButton
		category_button.visible = true
		category_button.disabled = screen._animating
	_category_buttons["ultimate"].disabled = screen._animating or actor.ultimate.is_empty()
	_category_buttons["defend"].disabled = screen._animating
	_category_buttons["item"].disabled = screen._animating
	_category_buttons["end_turn"].disabled = screen._animating
	for category in _category_buttons:
		_apply_category_button_visual(str(category), false)


func _on_category_hover(category: String, hovered: bool) -> void:
	_apply_category_button_visual(category, hovered)


func _apply_category_button_visual(category: String, hovered: bool) -> void:
	var category_button := _category_buttons.get(category) as TextureButton
	if category_button == null:
		return
	if category_button.disabled:
		category_button.modulate = Color(0.58, 0.60, 0.68, 0.66)
	elif hovered:
		category_button.modulate = Color(1.0, 0.91, 0.68, 1.0)
	elif category == _active_action_category:
		category_button.modulate = Color.WHITE
	else:
		category_button.modulate = Color(0.78, 0.78, 0.86, 0.94)


func _skill_matches_category(skill: SkillDef, category: String) -> bool:
	if skill.ultimate:
		return category == "ultimate"
	match category:
		"attack":
			return skill.kind == "damage"
		"skill":
			return skill.kind != "damage"
		"ultimate":
			return false
	return false


static func skill_icon_path(skill: SkillDef) -> String:
	if skill == null:
		return ""
	var control_effects := ["poison", "blind", "def_down", "spd_down", "stun", "atk_down"]
	for status in skill.statuses:
		if str(status.get("id", "")) in control_effects:
			return "res://assets/ui/battle/skills/sliced/control_chain.png"
	if skill.kind in ["heal", "buff", "shield"]:
		return "res://assets/ui/battle/skills/sliced/support_bloom.png"
	if skill.element == "fire":
		return "res://assets/ui/battle/skills/sliced/fire_burst.png"
	if skill.element == "dark":
		return "res://assets/ui/battle/skills/sliced/dark_arcane.png"
	return "res://assets/ui/battle/skills/sliced/general_strike.png"

static func status_icon_path(status_id: String) -> String:
	return str(STATUS_ICON_PATHS.get(status_id, ""))


func refresh_status_icons(actor: Combatant) -> void:
	if _status_icons == null:
		return
	for child in _status_icons.get_children():
		_status_icons.remove_child(child)
		child.queue_free()
	if actor == null:
		return
	for status in actor.statuses:
		var status_id := str(status.get("id", ""))
		var icon_path := status_icon_path(status_id)
		if icon_path.is_empty():
			continue
		var turns := int(status.get("turns", 0))
		var status_name := status_id.replace("_", " ").capitalize()
		var tooltip := status_name
		if turns > 0:
			tooltip += " · %d turns" % turns
		_add_status_icon(icon_path, tooltip, status_id.ends_with("_down"))
	if actor.shield > 0.0:
		_add_status_icon(status_icon_path("shield"), "Shield · %d HP" % int(ceil(actor.shield)), false)


func _add_status_icon(icon_path: String, tooltip: String, is_weakened: bool) -> void:
	var texture := load(icon_path) as Texture2D
	if texture == null:
		push_warning("Battle status icon could not be loaded: " + icon_path)
		return
	var icon := STATUS_ICON_SCENE.instantiate() as TextureRect
	icon.texture = texture
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1.0, 0.68, 0.68, 1.0) if is_weakened else Color.WHITE
	icon.tooltip_text = tooltip
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_icons.add_child(icon)

func _empty_category_hint(category: String) -> String:
	match category:
		"attack": return "No attack abilities are available for this character."
		"skill": return "No support or utility skills are available for this character."
		"ultimate": return "Ultimate is not ready yet. Build energy by taking and dealing damage."
	return "Choose an action."


func build_roster(units: Array) -> void:
	if screen._roster_box == null:
		return
	UIFactory.clear(screen._roster_box)
	screen._roster_rows.clear()
	for unit in units:
		var row := preload("res://scenes/ui/combat/components/party_roster_entry.tscn").instantiate() as HBoxContainer
		var portrait := CombatScreen.PORTRAIT_VIEW_SCENE.instantiate() as PortraitView
		portrait.custom_minimum_size = Vector2(42, 48) if _mobile_hud else Vector2(28, 30)
		portrait.battle_frame_style = "tall"
		var definition := ContentDB.get_character(unit.def_id)
		if definition != null:
			portrait.setup_character(definition)
		else:
			portrait.setup(unit.palette, "Human", unit.element, unit.rarity, unit.def_id.hash())
		row.get_node("PortraitSlot").add_child(portrait)
		var name_label := row.get_node("Info/Name") as Label
		name_label.text = unit.display_name
		if _mobile_hud:
			row.custom_minimum_size.y = 74
			row.get_node("PortraitSlot").custom_minimum_size = Vector2(42, 48)
			name_label.add_theme_font_size_override("font_size", 17)
			row.get_node("Info/HPLabel").add_theme_font_size_override("font_size", 16)
		var hp_bar := row.get_node("Info/HPBar") as ProgressBar
		hp_bar.max_value = maxf(1.0, unit.max_hp)
		hp_bar.value = clampf(unit.hp, 0.0, unit.max_hp)
		var hp_label := row.get_node("Info/HPLabel") as Label
		screen._roster_rows[unit.uid] = { "bar": hp_bar, "label": hp_label, "row": row }
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				screen._on_roster_clicked(unit))
		screen._roster_box.add_child(row)



func refresh_skills() -> void:
	UIFactory.clear(screen._skills_box)
	screen._targeting_component.reset()
	var actor: Combatant = screen.engine.current_actor() if screen.engine != null else null
	if actor == null or screen._resolved:
		if _action_categories != null:
			_action_categories.visible = false
		screen._actor_label.text = "Battle resolved."
		screen._hint_label.text = ""
		return
	if actor.team != CombatEngine.PLAYER_TEAM:
		if _action_categories != null:
			_action_categories.visible = true
			for category in _category_buttons:
				_category_buttons[category].disabled = true
				_apply_category_button_visual(str(category), false)
		if screen.group_id != "gerald_boss_encounter":
			screen._actor_label.text = "Enemy turn"
		# Unlocking the preceding animation refreshes this panel while an enemy
		# is already preparing. Preserve that warning until the queued action.
		var telegraph := screen._actor_for_uid(actor.uid)
		if telegraph == null or telegraph._intent_label == null or not telegraph._intent_label.visible:
			screen._hint_label.text = "Watch enemy intent markers. Gold rings show the threatened party."
		return
	if _action_categories != null:
		_action_categories.visible = true
	_update_category_buttons(actor)
	screen._actor_label.text = actor.display_name
	var shown := 0
	for skill_id in actor.skills:
		var skill: SkillDef = ContentDB.get_skill(str(skill_id))
		if skill != null and not skill.ultimate and _skill_matches_category(skill, _active_action_category):
			add_skill_button(skill, actor)
			shown += 1
	if _active_action_category == "ultimate" and not actor.ultimate.is_empty():
		var ultimate: SkillDef = ContentDB.get_skill(actor.ultimate)
		if ultimate != null:
			add_skill_button(ultimate, actor)
			shown += 1
	if shown == 0:
		screen._hint_label.text = _empty_category_hint(_active_action_category)
	elif _active_action_category == "ultimate" and not actor.ultimate_ready():
		screen._hint_label.text = "Ultimate energy is charging. The ability will activate when the meter is full."
	else:
		screen._hint_label.text = "Select an ability, then tap a gold-ringed foe. Esc cancels targeting."
	for boss in screen.engine.living(CombatEngine.ENEMY_TEAM):
		if boss.def_id == "cassien_boss" and boss.energy >= boss.max_energy - 8.0:
			screen._hint_label.text = "Crimson Requiem ready. Defend to reduce damage." if boss.ultimate_ready() else "One hit may ready Crimson Requiem. Consider Defend."
			break
		if boss.def_id == "gerald_boss" and boss.energy >= 92.0:
			screen._hint_label.text = "Earthquake ready. Defend to reduce damage." if boss.ultimate_ready() else "One hit may ready Earthquake. Consider Defend."
			break

func add_skill_button(skill: SkillDef, actor: Combatant) -> void:
	# The card hierarchy and visual states are authored in its reusable scene.
	var energy_text := "No energy gain" if skill.energy_gain <= 0 else "+%d energy" % int(skill.energy_gain)
	if skill.ultimate:
		energy_text = "%d energy needed" % ceili(actor.max_energy)
	var cooldown := actor.cooldown_remaining(skill.id)
	var cooldown_text := " · CD %d" % cooldown if cooldown > 0 else ""
	var kind_label := "Power" if skill.kind == "damage" else skill.kind.capitalize()
	var detail := "%s · %s · %d" % [skill.element.capitalize(), kind_label, roundi(skill.power * actor.skill_power_multiplier(skill.id))]
	var cost := energy_text + cooldown_text
	var card := SKILL_CARD_SCENE.instantiate() as Button
	if _mobile_hud:
		card.custom_minimum_size = Vector2(242, 94)
		for name in ["SkillName", "SkillDetail", "SkillCost"]:
			card.get_node("CardContent/TextStack/" + name).add_theme_font_size_override("font_size", 20 if name == "SkillName" else 16)
	card.tooltip_text = skill.description
	card.get_node("CardContent/TextStack/SkillName").text = ("ULT · " if skill.ultimate else "") + skill.display_name + "  Lv %d" % actor.skill_level(skill.id)
	card.get_node("CardContent/TextStack/SkillDetail").text = detail
	card.get_node("CardContent/TextStack/SkillCost").text = cost
	var skill_icon := load(skill_icon_path(skill)) as Texture2D
	if skill_icon != null:
		(card.get_node("CardContent/SkillIcon") as TextureRect).texture = skill_icon
	if skill.ultimate:
		card.self_modulate = Color(1.0, 0.90, 0.66, 1.0)
	card.set_meta("element", skill.element)
	card.set_meta("ultimate", skill.ultimate)
	card.disabled = screen._animating or actor.is_skill_on_cooldown(skill.id) or (skill.ultimate and not actor.ultimate_ready())
	card.pressed.connect(func() -> void: screen._select_skill(skill))
	AudioDirector.set_button_feedback(card, "confirm")
	screen._skills_box.add_child(card)
	if screen._targeting_component.is_targeting():
		var cancel := UIFactory.small_button("Cancel", UITheme.TEXT_DIM)
		cancel.pressed.connect(screen._cancel_targeting)
		screen._skills_box.add_child(cancel)

func on_auto_toggled(value: bool) -> void:
	screen._auto = value
	# Auto controls player decisions only. Do not cancel an enemy telegraph.
	var current: Combatant = screen.engine.current_actor() if screen.engine != null else null
	if current != null and current.team == CombatEngine.PLAYER_TEAM:
		screen._turn_token += 1
	screen._auto_button.text = "ON" if value else "OFF"
	screen._auto_button.add_theme_color_override("font_color", UITheme.GOLD if value else UITheme.TEXT_DIM)
	if value and screen.engine != null and not screen._resolved:
		# Auto owns targeting as well as skill choice; clear any half-selected
		# manual action before handing the turn to the decision system.
		if screen._targeting_component.is_targeting():
			screen._targeting_component.cancel_targeting()
		var actor: Combatant = screen.engine.current_actor()
		if actor != null and actor.team == CombatEngine.PLAYER_TEAM:
			screen._schedule_auto_player()



func cycle_speed() -> void:
	if is_equal_approx(screen._speed, 1.0):
		screen._speed = 1.6
	elif is_equal_approx(screen._speed, 1.6):
		screen._speed = 2.4
	else:
		screen._speed = 1.0
	screen._speed_button.text = ("%.1f×" % screen._speed).replace(".0×", "×")


# ------------------------------------------------------------------ visuals


func refresh_cards() -> void:
	refresh_mobile_utility()
	if screen.engine == null:
		return
	refresh_boss_header()
	# Update active character info panel.
	if screen.engine.current_actor() != null and screen._hp_bar != null:
		var active: Combatant = screen.engine.current_actor()
		if active.team == CombatEngine.ENEMY_TEAM and screen.group_id == "gerald_boss_encounter":
			var living_party := screen.engine.living(CombatEngine.PLAYER_TEAM)
			if not living_party.is_empty():
				active = living_party[0]
		screen._hp_bar.max_value = maxf(1.0, active.max_hp)
		screen._hp_bar.value = clampf(active.hp, 0.0, active.max_hp)
		screen._energy_bar.max_value = maxf(1.0, active.max_energy)
		screen._energy_bar.value = clampf(active.energy, 0.0, active.max_energy)
		var info := screen._hp_bar.get_parent()
		info.get_node("HPReadout").text = "HP  %d / %d" % [ceili(active.hp), ceili(active.max_hp)]
		info.get_node("EnergyReadout").text = "Energy  %d / %d" % [floori(active.energy), ceili(active.max_energy)]
		screen._actor_label.text = active.display_name
		screen._status_label.text = UIFactory.status_text(active)
		refresh_status_icons(active)
	# Refresh the battlefield: HP plates, the active marker and the roster.
	if screen._battlefield != null:
		screen._battlefield.refresh_actors()
		screen._battlefield.set_active(screen.engine.current_actor().uid if screen.engine.current_actor() != null else "")
	refresh_roster()


func refresh_roster() -> void:
	if screen.engine == null:
		return
	for unit in screen.engine.combatants:
		if unit.team != CombatEngine.PLAYER_TEAM:
			continue
		var entry: Dictionary = screen._roster_rows.get(unit.uid, {})
		if entry.is_empty():
			continue
		var bar: ProgressBar = entry.get("bar")
		var label: Label = entry.get("label")
		if bar != null:
			bar.max_value = maxf(1.0, unit.max_hp)
			bar.value = clampf(unit.hp, 0.0, unit.max_hp)
		if label != null:
			label.text = "%d/%d" % [ceili(unit.hp), ceili(unit.max_hp)]




func refresh_boss_header(phase_override: int = 0) -> void:
	if screen.engine == null:
		return
	if screen._boss_hp_bar != null and screen._boss_hp_bar.visible:
		for unit in screen.engine.combatants:
			var boss: Combatant = unit
			if boss.is_boss:
				screen._boss_hp_bar.value = boss.hp
				if screen._boss_phase_label != null:
					var phase_text := "Phase %d   |   HP %d / %d" % [(phase_override if phase_override > 0 else boss.triggered_phases.size() + 1), ceili(boss.hp), ceili(boss.max_hp)]
					if boss.def_id == "gerald_boss":
						phase_text += "   |   Earthquake READY" if boss.ultimate_ready() else "   |   Earthquake charge %d%%" % floori(boss.energy)
					if boss.def_id == "revienna_boss":
						phase_text += "  |  Eclipse %s" % ["READY" if boss.ultimate_ready() else "%d%%" % floori(100.0 * boss.energy / maxf(1.0, boss.max_energy))]
					if boss.def_id == "cassien_boss":
						phase_text = "HP %d / %d  |  Requiem %s" % [ceili(boss.hp), ceili(boss.max_hp), "READY" if boss.ultimate_ready() else "%d%%" % floori(100.0 * boss.energy / maxf(1.0, boss.max_energy))]
					screen._boss_phase_label.text = phase_text
					var warning_color := UITheme.TEXT_DIM
					if boss.def_id == "gerald_boss" and boss.energy >= 92.0:
						warning_color = Color(1.0, 0.67, 0.28)
					elif boss.def_id == "revienna_boss" and boss.ultimate_ready():
						warning_color = Color(0.9, 0.63, 1.0)
					elif boss.def_id == "cassien_boss" and boss.energy >= boss.max_energy - 8.0:
						warning_color = Color(1.0, 0.48, 0.46)
					screen._boss_phase_label.add_theme_color_override("font_color", warning_color)



func _configure_mobile_hud() -> void:
	var bottom := screen.get_node("CombatScreenLayout/Root/CombatBottomHUD") as HBoxContainer
	var mobile_button := bottom.get_node("ActiveInfoPanel/InfoContent/MobileUtility") as Button
	_mobile_hud = screen.get_window().size.x < 1000 and screen.get_window().size.x > screen.get_window().size.y
	mobile_button.visible = _mobile_hud
	if not _mobile_hud:
		return
	mobile_button.pressed.connect(_on_mobile_utility)
	AudioDirector.set_button_feedback(mobile_button, "confirm")
	bottom.custom_minimum_size.y = 280
	bottom.get_node("RosterPanel").custom_minimum_size.x = 204
	var info := bottom.get_node("ActiveInfoPanel/InfoContent")
	for name in ["ActorLabel", "HPReadout", "EnergyReadout", "StatusLabel"]:
		info.get_node(name).add_theme_font_size_override("font_size", 19 if name == "ActorLabel" else 17)
	for button in _category_buttons.values():
		button.custom_minimum_size = Vector2(140, 78)
	_action_categories.add_theme_constant_override("v_separation", 4)
	screen._hint_label.add_theme_font_size_override("font_size", 17)
	screen._log_label.add_theme_font_size_override("normal_font_size", 22)
	bottom.get_node("LogPanel/LogContent/LogCaption").add_theme_font_size_override("font_size", 20)
	bottom.get_node("LogPanel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.get_node("LogPanel").hide()
	screen._battlefield.custom_minimum_size.y = 174
	screen._boss_phase_label.add_theme_font_size_override("font_size", 18)
	var header := screen.get_node("CombatScreenLayout/Root/CombatHeader")
	for name in ["AutoButton", "SpeedButton", "RetreatButton"]:
		var control := header.get_node(name) as Button
		control.custom_minimum_size = Vector2(112, 54)
		control.add_theme_font_size_override("font_size", 20)

func _on_mobile_utility() -> void:
	if not _mobile_hud or screen._resolved:
		return
	if screen._targeting_component.is_targeting():
		screen._cancel_targeting()
		refresh_mobile_utility()
		return
	_mobile_log_open = not _mobile_log_open
	var bottom := screen.get_node("CombatScreenLayout/Root/CombatBottomHUD")
	bottom.get_node("SkillsPanel").visible = not _mobile_log_open
	bottom.get_node("LogPanel").visible = _mobile_log_open
	refresh_mobile_utility()

func refresh_mobile_utility() -> void:
	if not _mobile_hud:
		return
	var button := screen.get_node("CombatScreenLayout/Root/CombatBottomHUD/ActiveInfoPanel/InfoContent/MobileUtility") as Button
	button.text = "Cancel target" if screen._targeting_component.is_targeting() else ("Actions" if _mobile_log_open else "Battle log")
	button.disabled = screen._resolved
