extends DialogueBox

const CHOICE_THEME = preload("res://resources/ui/elathra_choice_theme.tres")

func _ready() -> void:
	super._ready()
	_name_label.hide()
	_hint_label.hide()
	_portrait.hide()
	_continue_button.theme = CHOICE_THEME

func _build_choices() -> void:
	super._build_choices()
	for child in _choices_box.get_children():
		if child is Button:
			child.theme = CHOICE_THEME
			child.custom_minimum_size = Vector2(0, 40)
