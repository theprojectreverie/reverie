class_name TutorialCompanion
extends WorldNPC
## The tutorial's first ally. Uses the shared NPC presentation pipeline, but
## routes interaction into the prologue flow instead of opening generic dialogue.

signal tutorial_interacted


func _ready() -> void:
	npc_id = "tutorial_companion"
	display_name = "???"
	dialogue_id = ""
	role = "???"
	race = "Human"
	palette = {
		"hair": "#e7c6e4",
		"primary": "#17131f",
		"secondary": "#652047",
		"accent": "#d7b46b",
		"skin": "#f0d2c9",
	}
	super._ready()


func interact() -> void:
	if not can_interact():
		return
	if visual != null:
		visual.play_interact()
	tutorial_interacted.emit()
