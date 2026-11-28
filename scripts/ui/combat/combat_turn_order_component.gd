class_name CombatTurnOrderComponent
extends Node
## Renders the initiative strip from the combat engine's live turn queue.

const TURN_SLOT_SCENE: PackedScene = preload("res://scenes/ui/combat/components/turn_order_slot.tscn")

var screen: CombatScreen


func bind(owner_screen: CombatScreen) -> void:
	screen = owner_screen


func refresh() -> void:
	if screen == null or screen._turn_box == null or screen.engine == null:
		return
	var engine := screen.engine
	UIFactory.clear(screen._turn_box)
	var sequence: Array[int] = []
	var seen_indices: Dictionary = {}
	var living_count := engine.living(CombatEngine.PLAYER_TEAM).size() + engine.living(CombatEngine.ENEMY_TEAM).size()
	var active_index := engine.current_actor_index
	if active_index >= 0 and active_index < engine.combatants.size():
		var active_unit: Combatant = engine.combatants[active_index]
		if active_unit.is_alive():
			sequence.append(active_index)
			seen_indices[active_index] = true
	if not engine.order.is_empty() and engine.turn_pointer >= 0:
		for offset in range(1, engine.order.size() + 1):
			var order_position := (engine.turn_pointer + offset) % engine.order.size()
			var next_index := int(engine.order[order_position])
			if next_index < 0 or next_index >= engine.combatants.size() or seen_indices.has(next_index):
				continue
			var next_unit: Combatant = engine.combatants[next_index]
			if next_unit.is_alive():
				sequence.append(next_index)
				seen_indices[next_index] = true
	if sequence.size() < living_count:
		var remaining_indices := engine.living_indices(CombatEngine.PLAYER_TEAM) + engine.living_indices(CombatEngine.ENEMY_TEAM)
		remaining_indices.sort_custom(func(a: int, b: int) -> bool:
			return engine.unit_speed(engine.combatants[a]) > engine.unit_speed(engine.combatants[b])
		)
		for next_index in remaining_indices:
			if not seen_indices.has(next_index):
				sequence.append(next_index)
				seen_indices[next_index] = true

	if sequence.is_empty():
		_add_turn_slot(Control.new(), "PreviousTurnSlot")
		var empty_label := UIFactory.label("â€”", 10, UITheme.TEXT_FAINT)
		empty_label.custom_minimum_size = Vector2(44, 42)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_add_turn_slot(empty_label, "ActiveTurnSlot")
		for slot_index in range(2, 6):
			_add_turn_slot(null, "TurnSlot_%d" % (slot_index + 1))
		return

	# The authored strip has six diamond slots. Its second slot is the fixed
	# illuminated marker, so reserve slot one for the previous-turn spacer.
	_add_turn_slot(Control.new(), "PreviousTurnSlot")
	var display_count := mini(sequence.size(), 5)
	var overflow_count := 0
	if sequence.size() > 5:
		display_count = 4
		overflow_count = sequence.size() - display_count

	for index in range(display_count):
		var unit: Combatant = engine.combatants[sequence[index]]
		if unit == null:
			continue
		var portrait := CombatScreen.PORTRAIT_VIEW_SCENE.instantiate() as PortraitView
		portrait.show_frame = true
		portrait.battle_frame_style = "round"
		portrait.show_rarity_effect = false
		portrait.selected = index == 0
		portrait.dim = not unit.is_alive()
		var definition := ContentDB.get_character(unit.def_id) if unit.team == CombatEngine.PLAYER_TEAM else null
		if definition != null:
			portrait.setup_character(definition, "", unit.ascension)
		else:
			portrait.setup(unit.palette, "Monster" if unit.team == CombatEngine.ENEMY_TEAM else "Human", unit.element, unit.rarity, unit.def_id.hash())
			if unit.def_id == "gerald_boss":
				portrait.set_portrait_texture(preload("res://scripts/art/approved_character_portraits.gd").texture("gerald_mythic"))
			elif unit.def_id == "cassien_boss":
				portrait.set_portrait_texture(preload("res://scripts/art/approved_character_portraits.gd").texture("cassien_mythic"))
			elif unit.def_id in ["mirene_boss", "revienna_boss"]:
				var portrait_id := "mirene_base" if unit.def_id == "mirene_boss" else "ravienna_mythic"
				var art_path := "res://assets/portraits/profile/" + portrait_id + (".jpg" if unit.def_id == "mirene_boss" else ".png")
				portrait.set_portrait_texture(load(art_path) as Texture2D)
			elif unit.def_id == "fallen_matron":
				var matron_phase := 1
				if unit.hp_ratio() <= 0.33:
					matron_phase = 3
				elif unit.hp_ratio() <= 0.66:
					matron_phase = 2
				var matron_atlas := load("res://assets/enemies/fallen_matron/phase_%d.png" % matron_phase) as Texture2D
				if matron_atlas != null:
					var matron_portrait := AtlasTexture.new()
					matron_portrait.atlas = matron_atlas
					matron_portrait.region = Rect2(62, 0, 296, 250)
					portrait.set_portrait_texture(matron_portrait)
		portrait.tooltip_text = unit.display_name
		portrait.custom_minimum_size = Vector2(44, 44)
		portrait.size = Vector2(44, 44)
		var slot_name := "ActiveTurnSlot" if index == 0 else "TurnSlot_%d" % (index + 2)
		_add_turn_slot(portrait, slot_name)

	if overflow_count > 0:
		var overflow_label := UIFactory.label("+%d" % overflow_count, 12, UITheme.GOLD_BRIGHT)
		overflow_label.custom_minimum_size = Vector2(44, 44)
		overflow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overflow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		overflow_label.tooltip_text = "%d additional turns queued" % overflow_count
		_add_turn_slot(overflow_label, "TurnSlot_6")
	else:
		for slot_index in range(display_count + 1, 6):
			_add_turn_slot(null, "TurnSlot_%d" % (slot_index + 1))


func _add_turn_slot(content: Control, slot_name: String) -> void:
	var slot := TURN_SLOT_SCENE.instantiate() as CenterContainer
	slot.name = slot_name
	if content != null:
		slot.add_child(content)
	screen._turn_box.add_child(slot)
