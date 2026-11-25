class_name TutorialPrologueWorld
extends Node2D
## Compact, self-contained first-meeting and real-time combat-controls tutorial.
## This scene is independent from the streamed overworld and hands off to
## the main gameplay scene only after Kael completes the opening lesson.

enum Stage {
	FIND_COMPANION,
	NAME_COMPANION,
	INTRODUCTION,
	REACH_TRAINING_RING,
	LIGHT_ATTACK,
	HEAVY_ATTACK,
	DODGE,
	VICTORY,
}

const DESTINATION_REGION := "castle_royal_gardens"
const REQUIRED_LIGHT_HITS := 2

var player: Player
var companion: TutorialCompanion
var training_dummy: TutorialTrainingDummy
var stage: Stage = Stage.FIND_COMPANION
var companion_name: String = ""
var _light_hits := 0
var _heavy_hits := 0
var _dodge_done := false
var _tutorial_finished := false

@onready var _title: Label = $TutorialHUD/Panel/VBox/Title
@onready var _body: Label = $TutorialHUD/Panel/VBox/Body
@onready var _name_entry: LineEdit = $TutorialHUD/Panel/VBox/NameEntry
@onready var _continue_button: Button = $TutorialHUD/Panel/VBox/ContinueButton
@onready var _ring_marker: Node2D = $Map/TrainingRing


func _ready() -> void:
	player = get_node_or_null("Entities/Player") as Player
	companion = get_node_or_null("Entities/Companion") as TutorialCompanion
	training_dummy = get_node_or_null("Entities/TrainingDummy") as TutorialTrainingDummy
	if player == null or companion == null or training_dummy == null:
		push_error("[TutorialPrologue] Missing player, companion, or training dummy.")
		return

	player.set_avatar("kael")
	companion.tutorial_interacted.connect(_on_companion_interacted)
	_continue_button.pressed.connect(_on_continue_pressed)
	_name_entry.text_submitted.connect(_on_name_submitted)

	companion_name = str(GameState.quest_domain.flags.get("tutorial_companion_name", ""))
	if not companion_name.is_empty():
		_apply_companion_name(companion_name)
	_set_stage(Stage.FIND_COMPANION)


func _process(_delta: float) -> void:
	if player == null:
		return
	if stage == Stage.REACH_TRAINING_RING and _ring_marker != null:
		if player.global_position.distance_to(_ring_marker.global_position) <= 118.0:
			_set_stage(Stage.LIGHT_ATTACK)
	if companion != null and companion.visual != null:
		var direction := Vector2.LEFT if player.global_position.x > companion.global_position.x else Vector2.RIGHT
		companion.visual.set_move_direction(direction)


func _unhandled_input(event: InputEvent) -> void:
	if _tutorial_finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_J and stage == Stage.LIGHT_ATTACK:
			_register_light_attack()
		elif key == KEY_K and stage == Stage.HEAVY_ATTACK:
			_register_heavy_attack()
		elif (key == KEY_SHIFT or key == KEY_SPACE) and stage == Stage.DODGE:
			_register_dodge()
	elif event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and stage == Stage.LIGHT_ATTACK:
			_register_light_attack()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and stage == Stage.HEAVY_ATTACK:
			_register_heavy_attack()


func _set_stage(next_stage: Stage) -> void:
	stage = next_stage
	_name_entry.visible = false
	_continue_button.visible = false
	match stage:
		Stage.FIND_COMPANION:
			_show_tutorial(
				"The First Encounter",
				"Kael awakens in a quiet sanctuary, far from the world he will soon enter. A mysterious woman waits nearby. Approach her and press E to speak."
			)
		Stage.NAME_COMPANION:
			_show_tutorial(
				"A Name to Remember",
				"She remembers ancient wars, lost kingdoms and countless faces — but not her own name. What should Kael call her?"
			)
			_name_entry.visible = true
			_name_entry.placeholder_text = "Choose her name..."
			_name_entry.grab_focus()
			_set_button("Give her a name")
		Stage.INTRODUCTION:
			_show_tutorial(
				companion_name,
				'She considers the name with a small smile. "Then that is who I shall be, at least until my memories return. Come, Kael. Let me see how well you can defend yourself."'
			)
			_set_button("Let's train")
		Stage.REACH_TRAINING_RING:
			_show_tutorial(
				"Movement",
				"Use WASD or the arrow keys to move. On touch devices, use the movement joystick. Walk into the marked stone circle to begin."
			)
		Stage.LIGHT_ATTACK:
			_show_tutorial(
				"Light Attack",
				"Approach the practice dummy and land two light attacks. Press J or click the left mouse button. You need to be close enough to strike."
			)
			_update_attack_progress()
		Stage.HEAVY_ATTACK:
			_show_tutorial(
				"Heavy Attack",
				"Good. Now try a heavier strike. Press K or click the right mouse button once while close to the dummy."
			)
		Stage.DODGE:
			_show_tutorial(
				"Dodge",
				"Never stand still when an enemy prepares to strike. Press Shift or Space to dodge out of danger."
			)
		Stage.VICTORY:
			_tutorial_finished = true
			GameState.quest_domain.flags["tutorial_complete"] = true
			GameState.save_now()
			_show_tutorial(
				"Your First Lesson",
				"Well done, Kael. You can move, strike and evade. Stay close — I have a feeling our paths are not meeting by chance. The road into Reverie awaits."
			)
			_set_button("Enter Reverie")


func _show_tutorial(heading: String, message: String) -> void:
	_title.text = heading
	_body.text = message


func _set_button(caption: String) -> void:
	_continue_button.text = caption
	_continue_button.visible = true


func _on_companion_interacted() -> void:
	if stage == Stage.FIND_COMPANION:
		if not companion_name.is_empty():
			_set_stage(Stage.INTRODUCTION)
		else:
			_set_stage(Stage.NAME_COMPANION)


func _on_name_submitted(_submitted: String) -> void:
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	match stage:
		Stage.NAME_COMPANION:
			var chosen_name := _name_entry.text.strip_edges()
			if chosen_name.is_empty():
				_name_entry.placeholder_text = "She needs a name first..."
				return
			companion_name = chosen_name
			_apply_companion_name(companion_name)
			GameState.quest_domain.flags["tutorial_companion_name"] = companion_name
			GameState.queue_save()
			_set_stage(Stage.INTRODUCTION)
		Stage.INTRODUCTION:
			_set_stage(Stage.REACH_TRAINING_RING)
		Stage.LIGHT_ATTACK:
			if _light_hits >= REQUIRED_LIGHT_HITS:
				_set_stage(Stage.HEAVY_ATTACK)
		Stage.HEAVY_ATTACK:
			if _heavy_hits >= 1:
				_set_stage(Stage.DODGE)
		Stage.DODGE:
			if _dodge_done:
				_set_stage(Stage.VICTORY)
		Stage.VICTORY:
			GameState.session_domain.set_player_region(DESTINATION_REGION)
			GameState.session_domain.set_active_world(DESTINATION_REGION)
			GameState.queue_save()
			var scene_error := get_tree().change_scene_to_file("res://scenes/game.tscn")
			if scene_error != OK:
				push_error("[TutorialPrologue] Could not enter the main world (error %d)." % scene_error)


func _apply_companion_name(chosen_name: String) -> void:
	companion.display_name = chosen_name
	var name_label := companion.get_node_or_null("NameLabel") as Label
	if name_label != null:
		name_label.text = chosen_name
	var subtitle := companion.get_node_or_null("SubtitleLabel") as Label
	if subtitle != null:
		subtitle.text = "Kael's First Ally"


func _register_light_attack() -> void:
	if player == null or training_dummy == null:
		return
	if player.global_position.distance_to(training_dummy.global_position) > 210.0:
		_body.text = "Move closer to the practice dummy before striking."
		return
	player.play_attack()
	training_dummy.play_light_hit(_light_hits)
	_light_hits += 1
	_update_attack_progress()


func _register_heavy_attack() -> void:
	if player == null or training_dummy == null:
		return
	if player.global_position.distance_to(training_dummy.global_position) > 210.0:
		_body.text = "Move closer to the practice dummy before striking."
		return
	player.play_attack()
	training_dummy.play_heavy_hit()
	_heavy_hits += 1
	_continue_button.visible = _heavy_hits >= 1


func _register_dodge() -> void:
	if _dodge_done:
		return
	_dodge_done = true
	var dodge_tween := create_tween()
	dodge_tween.tween_property(
		player,
		"position",
		player.position + Vector2(125.0, -34.0),
		0.22
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_continue_button.visible = true


func _update_attack_progress() -> void:
	_body.text = "Approach the practice dummy and land two light attacks. Press J or click the left mouse button. Progress: %d/%d" % [mini(_light_hits, REQUIRED_LIGHT_HITS), REQUIRED_LIGHT_HITS]
	_continue_button.visible = _light_hits >= REQUIRED_LIGHT_HITS
