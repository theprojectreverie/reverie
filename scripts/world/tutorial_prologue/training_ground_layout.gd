extends Node2D

const REQUIRED_LIGHT_HITS := 2
const VILLAGE := "res://scenes/world/village/imported_village/village_playable.tscn"
const FAIRY_SCENE := preload("res://scenes/characters/components/fairy_companion.tscn")
const COMPANION := "Mysterious Companion"
const DIALOGUES := {
 "arrival": [[COMPANION, "You are finally awake, Kael. I was beginning to wonder whether your dreams would ever release you."], ["Kael", "Those voices... they felt so real. Where am I?"], [COMPANION, "You are safe here, for now. Come to the tent. We should talk before you venture beyond these walls."]],
 "practice": [["Kael", "Who are you? And how do you know my name?"], [COMPANION, "There is much I cannot explain yet. But I can teach you to survive what lies ahead."], [COMPANION, "See that practice dummy? Approach it and face it. Strike twice with your basic attack (F), then use your skill (R)."], ["Kael", "Very well. Show me what I need to learn."]],
 "challenge": [[COMPANION, "Good. Your strikes are steady, but a wooden dummy will never strike back."], ["Kael", "Then what do you suggest?"], [COMPANION, "A friendly duel. Watch your opponent, choose your attacks wisely, and guard when danger approaches. Shall we begin?"]],
 "retry": [[COMPANION, "Do not let one defeat discourage you. Take a moment, then try again."], ["Kael", "I am ready."]],
 "farewell": [[COMPANION, "Enough, Kael. You have proven that you can defend yourself."], ["Kael", "And now? Where am I supposed to go?"], [COMPANION, "There is a village beyond these grounds. Perhaps its people can help you find answers."], ["Kael", "Will you come with me?"], [COMPANION, "Of course. Though my magic has a rather unusual way of making travel easier. Watch closely."]],
 "travel": [["Kael", "A fairy? I did not expect that."], [COMPANION, "This form is easier to maintain while we travel. I will stay beside you. Ready? Let us go to the village."]],
}

@onready var player: Player = $Kael
@onready var dummy: TutorialTrainingDummy = $TutorialProps/PracticeDummy
@onready var objective: Label = $TutorialHUD/TutorialObjective
@onready var dialogue: PanelContainer = $TutorialHUD/SparDialogue
@onready var speaker: Label = $TutorialHUD/SparDialogue/Content/Speaker
@onready var line: Label = $TutorialHUD/SparDialogue/Content/Line
@onready var next_button: Button = $TutorialHUD/SparDialogue/Content/Continue
@onready var dialogue_camera: Camera2D = $DialogueCamera
@onready var dialogue_progress: Label = $TutorialHUD/SparDialogue/Content/DialogueProgress
var light_hits := 0
var finishing := false
var sparring := false
var spar_won := false
var dummy_complete := false
var farewell_pending := false
var transformed := false
var practice_ready := false
var attempted_duel := false
var dialogue_stage := ""
var dialogue_index := 0
var companion_name := ""
var _name_busy := false
var _name_http: HTTPRequest
var _name_owner := ""
@onready var name_entry: LineEdit = $TutorialHUD/SparDialogue/Content/CompanionNameEntry

func _ready() -> void:
 AudioDirector.sync_region_ambience("training_ground")
 player.set_avatar("kael")
 dummy.world_struck.connect(_on_practice_hit)
 $CompanionNPC.challenge_requested.connect(_open_challenge)
 next_button.pressed.connect(_accept_challenge)
 name_entry.text_submitted.connect(func(_value: String):_accept_challenge())
 _name_http = HTTPRequest.new()
 _name_http.timeout = 10.0
 add_child(_name_http)
 EventBus.battle_finished.connect(_on_spar_result)
 var camera := player.get_node("Camera2D") as PlayerCameraRig
 camera.offset = Vector2(0,65)
 camera.set_base_zoom(1.55)
 get_viewport().size_changed.connect(_refresh_tutorial_layout)
 _refresh_tutorial_layout()
 _show_dialogue("arrival")
 var story_sync = preload("res://scripts/online/story_opening_world_sync.gd")
 if story_sync.pilot_enabled():
  var sync = story_sync.new()
  sync.name = "StoryOpeningWorldSync"
  add_child(sync)
  sync.bind_player(player, "story_training_ground")

func _show_dialogue(stage: String) -> void:
 name_entry.hide()
 dialogue_stage = stage
 dialogue_index = 0
 player.input_enabled = false
 player.velocity = Vector2.ZERO
 objective.hide()
 dialogue.show()
 _show_line()
 next_button.grab_focus()
 _refresh_dialogue_framing()

func _show_line() -> void:
 var lines: Array = DIALOGUES[dialogue_stage]
 var entry: Array = lines[dialogue_index]
 dialogue_progress.text = "%d / %d" % [dialogue_index + 1, lines.size()]
 speaker.text = companion_name if str(entry[0])==COMPANION and not companion_name.is_empty() else str(entry[0])
 line.text = str(entry[1])
 speaker.add_theme_color_override("font_color", Color("#b5dcff") if speaker.text == "Kael" else Color("#ffc1e0"))
 next_button.text = "Continue"
 if dialogue_index == lines.size()-1:
  match dialogue_stage:
   "arrival": next_button.text = "Approach the tent"
   "practice": next_button.text = "Begin training"
   "challenge", "retry": next_button.text = "Accept challenge"
   "farewell": next_button.text = "Watch her magic"
   "travel": next_button.text = "Travel to the village"

# Frame both speakers above the authored bottom panel without moving the player.
# A separate scene camera prevents the locomotion rig from undoing the framing.
func _refresh_tutorial_layout() -> void:
 var viewport := get_viewport_rect().size
 var portrait := viewport.y > 0.0 and viewport.x / viewport.y < 0.85
 dialogue.offset_left = 32.0
 dialogue.offset_right = -32.0
 dialogue.offset_bottom = -48.0 if portrait else -24.0
 dialogue.offset_top = -450.0 if portrait else -230.0
 speaker.add_theme_font_size_override("font_size", 40 if portrait else 21)
 line.add_theme_font_size_override("font_size", 36 if portrait else 19)
 dialogue_progress.add_theme_font_size_override("font_size", 28 if portrait else 13)
 next_button.add_theme_font_size_override("font_size", 36 if portrait else 18)
 next_button.custom_minimum_size = Vector2(420,104) if portrait else Vector2(240,44)
 name_entry.custom_minimum_size.y = 76.0 if portrait else 44.0
 name_entry.add_theme_font_size_override("font_size",32 if portrait else 19)
 next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_END
 objective.add_theme_font_size_override("font_size", 34 if portrait else 19)
 objective.offset_left = 36.0 if portrait else 12.0
 objective.offset_right = -36.0 if portrait else -12.0
 objective.offset_bottom = 150.0 if portrait else 48.0
 objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _refresh_dialogue_framing.call_deferred()

func _refresh_dialogue_framing() -> void:
 if dialogue_stage.is_empty() and not finishing:
  return
 var a := player.global_position + Vector2(0,-32)
 var b: Vector2 = a + Vector2(28,-22) if transformed and player.has_node("FairyCompanion") else $CompanionNPC.global_position + Vector2(0,-42)
 var span := (a-b).abs() + Vector2(124,112)
 var viewport := get_viewport_rect().size
 var panel_height := maxf(dialogue.size.y, -dialogue.offset_top) if dialogue.visible else 72.0
 var available := Vector2(maxf(120.0,viewport.x-56.0),maxf(150.0,viewport.y-panel_height-40.0))
 var portrait := viewport.y > 0.0 and viewport.x / viewport.y < 0.85
 var fit := clampf(minf(available.x/span.x,available.y/span.y),0.45,2.5 if portrait else 1.55)
 dialogue_camera.zoom = Vector2.ONE * fit
 dialogue_camera.global_position = (a+b)*0.5 + Vector2(0,panel_height*0.5/fit)
 dialogue_camera.enabled = true
 dialogue_camera.make_current()
 dialogue_camera.force_update_scroll()

func _restore_player_camera() -> void:
 player.camera.make_current()
 dialogue_camera.enabled = false
 player.camera.force_update_scroll()

func _resume_movement(text: String) -> void:
 _restore_player_camera()
 player.input_enabled = true
 objective.text = text
 objective.show()

func _on_practice_hit(heavy: bool) -> void:
 if not practice_ready or finishing or sparring or dummy_complete or not dialogue_stage.is_empty():
  return
 if heavy:
  if light_hits >= REQUIRED_LIGHT_HITS:
   dummy_complete = true
   $CompanionNPC.unlock()
   objective.text = "Return to your companion and press E to talk."
  else:
   objective.text = "Face the dummy and press F twice for basic attacks."
  return
 light_hits = mini(light_hits + 1, REQUIRED_LIGHT_HITS)
 objective.text = "Press R near the dummy to practice your skill." if light_hits >= REQUIRED_LIGHT_HITS else "Press F for another basic attack."

func _finish_training() -> void:
 if finishing or transformed:
  return
 finishing = true
 player.input_enabled = false
 player.velocity = Vector2.ZERO
 objective.show()
 objective.text = "Your companion joins you..."
 _refresh_dialogue_framing()
 await $CompanionNPC.walk_for_farewell(player.global_position)
 $CompanionNPC/Transformation.play("transform")
 await $CompanionNPC/Transformation.animation_finished
 $CompanionNPC/AnimatedSprite2D.hide()
 $CompanionNPC/AnimatedSprite2D.stop()
 transformed = true
 # Bring the existing tiny sprite to the player's shoulder before handing it
 # off to the shared follower scene. No duplicate fairy or early quest flag.
 var tiny: AnimatedSprite2D = $CompanionNPC/TinyForm
 var follower := FAIRY_SCENE.instantiate() as Node2D
 var destination := player.to_global(follower.position)
 var flight := create_tween().set_parallel(true)
 flight.tween_property(tiny,"global_position",destination,0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
 flight.tween_property(tiny,"scale",Vector2.ONE * 0.8 * player.scale.x,0.85)
 await flight.finished
 player.add_child(follower)
 tiny.hide()
 tiny.stop()
 await get_tree().create_timer(0.65).timeout
 _show_dialogue("travel")

func _transport_to_village() -> void:
 var story_sync := get_node_or_null("StoryOpeningWorldSync")
 if story_sync != null:
  if not await story_sync.can_travel_to_village():
   EventBus.toast_requested.emit("The village is not available yet. Reconnect and try again.")
   _show_dialogue("travel")
   return
 objective.show()
 objective.text = "Travelling to the village..."
 var fade := $TutorialHUD/TravelFade as ColorRect
 fade.show()
 var transition := create_tween()
 transition.tween_property(fade,"color:a",1.0,0.65)
 await transition.finished
 if story_sync != null and not story_sync.is_story_ready():
  fade.hide()
  fade.color.a = 0.0
  _show_dialogue("travel")
  return
 GameState.quest_domain.flags["tutorial_complete"] = true
 GameState.session_domain.set_player_region("greenward")
 GameState.session_domain.set_active_world("greenward")
 GameState.quest_domain.flags["six_zone_checkpoint"] = {"zone": "StandaloneVillage", "x": -2090.0, "y": 112.0}
 GameState.session_domain.loaded_from_save = true
 GameState.save_now()
 var error := get_tree().change_scene_to_file(VILLAGE)
 if error != OK:
  fade.hide()
  fade.color.a = 0.0
  _show_dialogue("travel")
  return
 StoryMilestoneTelemetry.record_scene_transition(VILLAGE)
 AudioDirector.sync_region_ambience("greenward")

func _start_spar() -> void:
 if sparring or finishing or not dummy_complete:
  return
 _restore_player_camera()
 sparring = true
 attempted_duel = true
 spar_won = false
 $CompanionNPC.enabled = false
 $CompanionNPC/Marker.hide()
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
  farewell_pending = true
  $CompanionNPC.enabled = false
  $CompanionNPC/Marker.hide()
  _show_dialogue("farewell")
 else:
  $CompanionNPC.unlock()
  _resume_movement("Talk to your companion again to retry the challenge.")

func _unhandled_input(event: InputEvent) -> void:
 if not sparring and not finishing and player.input_enabled and event.is_action_pressed("interact") and not event.is_echo():
  player.interaction_component.refresh_nearest()
  player.try_interact()
  get_viewport().set_input_as_handled()

func _open_challenge() -> void:
 if sparring or finishing or not dialogue_stage.is_empty():
  return
 if not practice_ready:
  $CompanionNPC.enabled = false
  $CompanionNPC/Marker.hide()
  _begin_companion_naming()
 elif dummy_complete:
  _show_dialogue("retry" if attempted_duel else "challenge")

func _accept_challenge() -> void:
 var story_sync := get_node_or_null("StoryOpeningWorldSync")
 if story_sync != null and not story_sync.is_story_ready():
  EventBus.toast_requested.emit("Wait for the story connection to recover.")
  return
 if dialogue_stage == "name_companion":
  _submit_companion_name()
  return
 if dialogue_stage.is_empty():
  return
 if dialogue_index + 1 < DIALOGUES[dialogue_stage].size():
  dialogue_index += 1
  _show_line()
  return
 var completed := dialogue_stage
 dialogue_stage = ""
 dialogue.hide()
 match completed:
  "arrival":
   $CompanionNPC.unlock()
   _resume_movement("Approach your companion in front of the tent and press E.")
  "practice":
   practice_ready = true
   _resume_movement("Face the practice dummy and press F twice for basic attacks.")
  "challenge", "retry": _start_spar()
  "farewell":
   farewell_pending = false
   _finish_training()
  "travel": _transport_to_village()

func _begin_companion_naming() -> void:
 if _name_busy:return
 dialogue_stage = "name_companion"
 player.input_enabled = false
 player.velocity = Vector2.ZERO
 objective.hide()
 dialogue.show()
 name_entry.hide()
 speaker.text = COMPANION
 dialogue_progress.text = ""
 line.text = "She remembers much of this world, but not her own name."
 next_button.text = "Loading..."
 next_button.disabled = true
 _refresh_dialogue_framing()
 if not AuthGateway.is_authenticated():
  _show_name_error("Sign in to choose a name for your companion.")
  return
 var result := await _companion_name_request("")
 if not is_inside_tree():return
 if not result.get("ok",false):
  _show_name_error("Could not load her name. Reconnect and try again.")
  return
 companion_name = str(result.get("name",""))
 if not companion_name.is_empty():
  _finish_companion_naming()
  return
 name_entry.show()
 name_entry.grab_focus()
 next_button.disabled = false
 next_button.text = "Give her a name"

func _show_name_error(message: String) -> void:
 line.text = message
 next_button.disabled = false
 next_button.text = "Retry"

func _submit_companion_name() -> void:
 if _name_busy:return
 if not name_entry.visible:
  _begin_companion_naming()
  return
 var chosen := name_entry.text.strip_edges()
 if chosen.is_empty():
  line.text = "Choose a name first."
  return
 next_button.disabled = true
 next_button.text = "Saving..."
 name_entry.editable = false
 var result := await _companion_name_request(chosen)
 if not is_inside_tree():return
 name_entry.editable = true
 next_button.disabled = false
 if not result.get("ok",false):
  line.text = "Use 1-24 letters, numbers, spaces, apostrophes or hyphens." if int(result.get("code",0))==400 else "Could not save her name. Reconnect and try again."
  next_button.text = "Give her a name"
  return
 companion_name = str(result.get("name",""))
 if companion_name.is_empty():
  _show_name_error("Could not save her name. Try again.")
  return
 _finish_companion_naming()

func _companion_name_request(chosen: String) -> Dictionary:
 if _name_busy or not AuthGateway.access_token_ready_for_connection():return {"ok":false}
 _name_busy = true
 var owner := str(AuthGateway.current_player().get("id",""))
 _name_owner = owner
 var headers := PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
 var error := _name_http.request(AuthGateway.api_base_url+"/v1/social/companion-name",headers,HTTPClient.METHOD_GET if chosen.is_empty() else HTTPClient.METHOD_POST,"" if chosen.is_empty() else JSON.stringify({"name":chosen}))
 if error!=OK:
  _name_busy = false
  return {"ok":false}
 var response: Array = await _name_http.request_completed
 _name_busy = false
 if owner.is_empty() or owner != str(AuthGateway.current_player().get("id","")):return {"ok":false}
 var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
 if response[0]!=HTTPRequest.RESULT_SUCCESS or response[1]!=200 or not data is Dictionary or str(data.get("playerId",""))!=owner:
  return {"ok":false,"code":response[1]}
 return {"ok":true,"name":str(data.get("name",""))}

func _finish_companion_naming() -> void:
 name_entry.hide()
 next_button.disabled = false
 GameState.quest_domain.flags["tutorial_companion_name"] = companion_name
 GameState.queue_save()
 _show_dialogue("practice")