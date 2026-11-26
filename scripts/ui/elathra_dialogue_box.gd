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

var _story_sync: Node
var _story_choice_pending := false

func open_story(sync: Node) -> void:
	_story_sync = sync
	open("elathra")

func _resolve_start() -> String:
	if is_instance_valid(_story_sync):
		return {"not_started":"greet","active":"accepted","complete":"complete"}.get(_story_sync.audience_state(),"greet")
	return super._resolve_start()

func _choose(choice: Dictionary) -> void:
	if not is_instance_valid(_story_sync):
		super._choose(choice)
		return
	if _story_choice_pending or not visible:return
	var action := str(choice.get("action",""))
	if action.is_empty():
		super._choose(choice)
		return
	var operation := "hear" if action=="start_quest:elathra_first_audience" else "accept" if action=="complete_quest:elathra_first_audience" else ""
	if operation.is_empty():return
	_story_choice_pending = true
	for child in _choices_box.get_children():
		if child is Button:child.disabled = true
	var result: Dictionary = await _story_sync.submit_audience(operation)
	_story_choice_pending = false
	if not is_inside_tree() or not visible:return
	if result.is_empty():
		EventBus.toast_requested.emit("Could not confirm Elathra's reply. Reconnect and try again.")
		_build_choices()
		return
	choice_selected.emit(_dialogue_id,choice)
	_show_node("complete" if result.audience.state=="complete" else "accepted")

func close() -> void:
	if _story_choice_pending:return
	_story_sync = null
	super.close()
