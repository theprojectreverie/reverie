class_name HUDPartyComponent
extends Node
## Owns the always-on party roster presentation.

var hud: HUD
var _party_signature: Array = []

func bind(owner: HUD) -> void:
	hud = owner

func refresh_party() -> void:
	if hud == null or hud._party_box == null:
		return
	var instances := GameState.roster_domain.party_instances()
	var signature: Array = [instances.size()]
	for instance in instances:
		signature.append([instance.uid, instance.char_id, instance.level])
	if signature == _party_signature:
		return
	_party_signature = signature
	for child in hud._party_box.get_children():
		if child != hud._party_empty_label:
			hud._party_box.remove_child(child)
			child.queue_free()
	hud._party_empty_label.visible = instances.is_empty()
	if instances.is_empty():
		return
	for instance in instances:
		var definition: CharacterDef = ContentDB.get_character(instance.char_id)
		if definition == null:
			continue
		var row := HUD.PARTY_ENTRY_SCENE.instantiate() as HBoxContainer
		var portrait := row.get_node("Portrait") as PortraitView
		portrait.setup_character(definition)
		(row.get_node("Details/CharacterName") as Label).text = definition.display_name
		(row.get_node("Details/CharacterMeta") as Label).text = "Lv %d  ·  %s" % [instance.level, definition.role]
		(row.get_node("ElementDot") as ColorRect).color = UITheme.element_color(definition.element)
		hud._party_box.add_child(row)
