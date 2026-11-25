extends Node2D

const PRACTICE_REACH := 115.0
const REQUIRED_LIGHT_HITS := 2
const ROYAL_GARDENS := "res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn"

@onready var player: Player = $Kael
@onready var dummy: TutorialTrainingDummy = $TutorialProps/PracticeDummy
@onready var objective: Label = $TutorialHUD/TutorialObjective

var light_hits := 0
var finishing := false
var sparring := false
var spar_won := false
var dummy_complete := false


func _ready() -> void:
	AudioDirector.sync_region_ambience("training_ground")
	player.set_avatar("kael")
	dummy.world_struck.connect(_on_practice_hit)
	$CompanionNPC.challenge_requested.connect(_open_challenge)
	$TutorialHUD/SparDialogue/Content/Continue.pressed.connect(_accept_challenge)
	EventBus.battle_finished.connect(_on_spar_result)
	var camera := player.get_node("Camera2D") as PlayerCameraRig
	camera.offset = Vector2(0, 65)
	camera.set_base_zoom(1.55)


func _on_practice_hit(heavy: bool) -> void:
	if finishing or sparring or dummy_complete:
		return
	if heavy:
		if light_hits >= REQUIRED_LIGHT_HITS:
			dummy_complete = true
			$CompanionNPC.unlock()
			objective.text = "Approach your companion and press E to talk."
		else:
			objective.text = "Face the dummy and press F twice for basic attacks."
		return
	light_hits += 1
	if light_hits >= REQUIRED_LIGHT_HITS:
		objective.text = "Press R near the dummy to practice your skill."
	else:
		objective.text = "Press F for another basic attack."

func _finish_training() -> void:
	finishing = true
	objective.show()
	objective.text = "Training complete. Entering Royal Gardens..."
	await get_tree().create_timer(0.55).timeout
	GameState.quest_domain.flags["tutorial_complete"] = true
	GameState.session_domain.set_player_region("castle_royal_gardens")
	GameState.session_domain.loaded_from_save = true
	GameState.save_now()
	var error := get_tree().change_scene_to_file(ROYAL_GARDENS)
	if error != OK:
		finishing = false
		objective.text = "Could not open Royal Gardens. Press R to try again."
		return
	AudioDirector.sync_region_ambience("castle_royal_gardens")
	# Completion checkpoint was saved before changing scenes.

func _start_spar() -> void:
	if sparring or finishing:
		return
	sparring = true
	spar_won = false
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	objective.hide()
	var combat := preload("res://scenes/ui/combat_screen.tscn").instantiate() as CombatScreen
	combat.group_id = "tutorial_fairy_spar"
	combat.closed.connect(_on_spar_closed)
	$TutorialHUD/SparringRoot.add_child(combat)

func _on_spar_result(result: Dictionary) -> void:
	if result.get("group_id") == "tutorial_fairy_spar":
		spar_won = bool(result.get("victory", false))

func _on_spar_closed() -> void:
	sparring = false
	if spar_won:
		_finish_training()
	else:
		player.input_enabled = true
		objective.show()
		objective.text = "Talk to your companion again to retry the challenge."
func _unhandled_input(event: InputEvent) -> void:
	if dummy_complete and not sparring and player.input_enabled and event.is_action_pressed("interact") and not event.is_echo():
		player.interaction_component.refresh_nearest()
		player.try_interact()
		get_viewport().set_input_as_handled()

func _open_challenge() -> void:
	if not dummy_complete or sparring or finishing:
		return
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	$TutorialHUD/SparDialogue.show()

func _accept_challenge() -> void:
	$TutorialHUD/SparDialogue.hide()
	_start_spar()