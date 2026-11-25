class_name TutorialPrologue
extends Node2D
## Coordinates the prologue chapter. Characters, environment, target and UI
## are authored PackedScenes placed in the editor, not instantiated here.

const WORLD_SCENE := "res://scenes/game.tscn"

@onready var player: Player = $Actors/Kael
@onready var companion: Node2D = $Actors/Lilith
@onready var training_construct: Node2D = $TrainingConstruct
@onready var dialogue_panel: PanelContainer = $UI/DialoguePanel
@onready var speaker_label: Label = $UI/DialoguePanel/DialogueMargin/DialogueStack/Speaker
@onready var dialogue_label: Label = $UI/DialoguePanel/DialogueMargin/DialogueStack/Line
@onready var continue_button: Button = $UI/DialoguePanel/DialogueMargin/DialogueStack/Continue
@onready var objective_label: Label = $UI/Objective
@onready var controls_label: Label = $UI/Controls

var phase := 0
var move_start := Vector2.ZERO
var move_done := false
var light_hits := 0
var heavy_hits := 0
var dodge_done := false
var tutorial_finished := false

const LINES := [
	["???", "Easy. You're safe... for the moment. Can you hear me?"],
	["Lilith", "I'm Lilith. You collapsed just beyond the old stones. Try standing up. I'll stay close."],
	["Lilith", "Good. Move around a little. Don't fight your own balance—let your feet find the rhythm."],
	["Lilith", "There. Now approach the training construct. Get within reach, then give it a light attack."],
	["Lilith", "Good. A stronger blow takes commitment. Stay close and use a heavy attack."],
	["Lilith", "And never stand still when something swings at you. Dodge through the opening."],
	["Lilith", "That's enough for today. You learn quickly, Kael. Stay near me until we understand where you are."]
]

func _ready() -> void:
	move_start = player.global_position
	continue_button.pressed.connect(_advance_story)
	_show_phase()

func _show_phase() -> void:
	if phase >= LINES.size():
		_finish_tutorial()
		return
	speaker_label.text = LINES[phase][0]
	dialogue_label.text = LINES[phase][1]
	continue_button.visible = phase < 2 or (phase == 2 and move_done) or (phase == 3 and light_hits >= 2) or (phase == 4 and heavy_hits >= 1) or (phase == 5 and dodge_done) or phase == 6
	objective_label.text = _objective_text()
	controls_label.text = "WASD  Move     J / Left Click  Light     K / Right Click  Heavy     Shift / Space  Dodge"

func _objective_text() -> String:
	match phase:
		0, 1: return "PROLOGUE  •  FIRST ENCOUNTER\nSpeak with the stranger"
		2: return "TRAINING  •  MOVEMENT\nMove at least a short distance"
		3: return "TRAINING  •  LIGHT ATTACK\nStrike the construct twice  (%d/2)" % mini(light_hits, 2)
		4: return "TRAINING  •  HEAVY ATTACK\nLand one heavy strike  (%d/1)" % mini(heavy_hits, 1)
		5: return "TRAINING  •  DODGE\nPerform a dodge"
		_: return "PROLOGUE  •  COMPLETE\nReady to enter the wider world"

func _advance_story() -> void:
	if phase == 2 and not move_done:
		return
	if phase == 3 and light_hits < 2:
		return
	if phase == 4 and heavy_hits < 1:
		return
	if phase == 5 and not dodge_done:
		return
	phase += 1
	_show_phase()

func _process(_delta: float) -> void:
	if phase == 2 and not move_done:
		move_done = player.global_position.distance_to(move_start) >= 90.0
		if move_done:
			_show_phase()
	companion.call("face_toward", player.global_position)

func _unhandled_input(event: InputEvent) -> void:
	if tutorial_finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_J and phase == 3:
			_register_light_attack()
		elif key == KEY_K and phase == 4:
			_register_heavy_attack()
		elif (key == KEY_SHIFT or key == KEY_SPACE) and phase == 5:
			_register_dodge()
	elif event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and phase == 3:
			_register_light_attack()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and phase == 4:
			_register_heavy_attack()

func _register_light_attack() -> void:
	if player.global_position.distance_to(training_construct.global_position) > 210.0:
		return
	player.play_attack()
	training_construct.call("receive_tutorial_hit", &"light")
	light_hits += 1
	_show_phase()

func _register_heavy_attack() -> void:
	if player.global_position.distance_to(training_construct.global_position) > 210.0:
		return
	player.play_attack()
	training_construct.call("receive_tutorial_hit", &"heavy")
	heavy_hits += 1
	_show_phase()

func _register_dodge() -> void:
	dodge_done = true
	var dodge_tween := create_tween()
	dodge_tween.tween_property(player, "position", player.position + Vector2(125.0, -34.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_show_phase()

func _finish_tutorial() -> void:
	if tutorial_finished:
		return
	tutorial_finished = true
	dialogue_panel.visible = true
	speaker_label.text = "Lilith"
	dialogue_label.text = "Come on, Kael. Let's find out what lies beyond these stones."
	continue_button.text = "Enter Reverie"
	objective_label.text = "PROLOGUE COMPLETE"
	controls_label.text = "Your journey begins..."
	continue_button.pressed.disconnect(_advance_story)
	continue_button.pressed.connect(_enter_world)

func _enter_world() -> void:
	GameState.session_domain.set_player_region("castle_royal_gardens")
	GameState.session_domain.set_active_world("castle_royal_gardens")
	get_tree().change_scene_to_file(WORLD_SCENE)
