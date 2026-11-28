extends Interactable
## Dialogue, battle, and post-victory memories are mutually exclusive stages.
const GROUP_ID = "gerald_boss_encounter"
const FLAG = "village_gerald_defeated"
const DIALOGUE_ID = "gerald_kael_confrontation"
const AFTER_BATTLE_DIALOGUE = "gerald_kael_after_battle"
const BEFORE_TRAGEDY_DIALOGUE = "gerald_kael_after_the_fall"
const FINAL_DIALOGUE = "gerald_kael_farewell"
const STORY_PENDING = "village_gerald_backstory_pending"
const STORY_SEEN = "village_gerald_backstory_seen"
const MEMORIES_COMPLETE = "village_gerald_memories_complete"
const LILITH_AWAKENED = "village_lilith_awakened"
const REUNION_SCENE = preload("res://assets/characters/lilith/summoning/lilith_reunion_cinematic.tscn")
var engaged := false
var _fight_confirmed := false
var _story_running := false
var _home_position := Vector2.ZERO
const APPROACH_LIMIT := 32.0

func _ready() -> void:
 super._ready()
 _home_position = global_position
 $FallenWalk.frame_changed.connect(_on_walk_frame_changed)
 prompt = "Speak to Gerald"
 interaction_radius = 100.0
 add_to_group("world_minimap_monsters")
 EventBus.battle_finished.connect(_on_battle_finished)
 _refresh()
 if bool(GameState.quest_domain.flags.get(STORY_PENDING, false)):
  _resume_saved_backstory.call_deferred()

func _refresh() -> void:
 enabled = not bool(GameState.quest_domain.flags.get(FLAG, false))
 visible = true
 var sprite := $FallenIdle as AnimatedSprite2D
 if not enabled:
  remove_from_group("world_minimap_monsters")
  sprite.sprite_frames = load("res://assets/enemies/gerald_fallen/combat_frames.tres") as SpriteFrames
  sprite.stop()
  sprite.animation = &"defeat"
  sprite.set_frame_and_progress(sprite.sprite_frames.get_frame_count(&"defeat") - 1, 1.0)
  $NameLabel.offset_top = -64.0
  $NameLabel.offset_bottom = -42.0
  $NameLabel.text = "Gerald"
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  zone = get_parent().get_parent().get_parent()
 var exit_label := zone.get_node_or_null("TransferPoints/ToNextZone/ExitLabel") as Label
 if exit_label != null:
  exit_label.text = "Defeat Gerald first" if enabled else ("Finish Gerald?s story" if GameState.quest_domain.flags.get(STORY_PENDING, false) else "Royal Gardens")

func can_interact() -> bool:
 return super.can_interact() and not engaged and not _story_running and not bool(GameState.quest_domain.flags.get(FLAG, false)) and _village_recruits_ready()

func _village_recruits_ready() -> bool:
 # Existing online pilot remains server-authoritative; this local questline is not deployed there yet.
 var current := get_tree().current_scene
 if current != null:
  var sync := current.get_node_or_null("StoryVillageProgressionSync")
  if sync != null:
   return sync.ready_for_group(GROUP_ID, "village_gerald_trial") or sync.won(GROUP_ID)
 if not preload("res://scripts/world/six_zone_reverie/village_witch_duo_encounter.gd").local_story_available():
  return true
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  return true
 return GameState.quest_domain.quest_state("village_nyx_duel") == "complete"

func interact() -> void:
 if not can_interact(): return
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage": return
 var story_sync := zone.get_node_or_null("StoryOpeningWorldSync")
 if story_sync != null:
  if (OS.get_environment("REVERIE_GERALD_STORY_PILOT") != "1" and OS.get_environment("REVERIE_VILLAGE_PROGRESSION_PILOT") != "1") or not story_sync.is_story_ready():
   EventBus.toast_requested.emit("Online Gerald combat is unavailable. Reconnect and try again.")
   return
 var player := zone.get("checkpoint_player") as CharacterBody2D
 if not is_instance_valid(player) or not player.input_enabled or player.global_position.distance_to(global_position) > interaction_radius: return
 var dialogue := zone.get_node_or_null("UI/Dialogue") as DialogueBox
 if dialogue == null or dialogue.visible:
  return
 engaged = true
 _fight_confirmed = false
 player.input_enabled = false
 player.velocity = Vector2.ZERO
 TouchInput.release()
 dialogue.choice_selected.connect(_on_dialogue_choice)
 dialogue.closed.connect(_on_dialogue_closed, CONNECT_ONE_SHOT)
 dialogue.open(DIALOGUE_ID)

func _on_dialogue_choice(id: String, choice: Dictionary) -> void:
 if id == DIALOGUE_ID and str(choice.get("text", "")) == "Stand your ground":
  _fight_confirmed = true

func _on_dialogue_closed(id: String) -> void:
 if id != DIALOGUE_ID:
  return
 var zone := get_tree().current_scene
 var dialogue := zone.get_node_or_null("UI/Dialogue") as DialogueBox
 if dialogue != null and dialogue.choice_selected.is_connected(_on_dialogue_choice):
  dialogue.choice_selected.disconnect(_on_dialogue_choice)
 if _fight_confirmed:
  _start_fight.call_deferred()
 else:
  engaged = false
  var player := zone.get("checkpoint_player") as CharacterBody2D
  if is_instance_valid(player):
   player.input_enabled = true

func _start_fight() -> void:
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  return
 var target := zone.get("checkpoint_player") as CharacterBody2D
 if is_instance_valid(target):
  await _walk_toward_player(target.global_position)
 if not is_instance_valid(zone) or not is_inside_tree() or not engaged:
  return
 EventBus.encounter_requested.emit(GROUP_ID, self)
 if not engaged:
  var player := zone.get("checkpoint_player") as CharacterBody2D
  if is_instance_valid(player):
   player.input_enabled = true

# A short authored-sprite approach; the collision query keeps the original map clear.
func walk_clip_for_direction(direction: Vector2) -> StringName:
 var names := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
 var index := posmod(roundi(direction.angle() / (PI / 4.0)), 8)
 return StringName("walk_" + names[index])

# Two footsteps per 16-frame cycle, only during visible movement.
func _on_walk_frame_changed() -> void:
 var walk := $FallenWalk as AnimatedSprite2D
 if walk.visible and walk.is_playing() and walk.frame in [3, 11]:
  AudioDirector.play_variant("dirt_step", -7.0, 0.72)

func _walk_toward_player(target: Vector2) -> void:
 var delta := target - global_position
 var distance := minf(APPROACH_LIMIT, delta.length() - 56.0)
 if distance < 8.0:
  return
 var direction := delta.normalized()
 var destination := global_position + direction * distance
 # Stay within the authored boss clearing even across repeated challenges.
 destination = _home_position + (destination - _home_position).limit_length(APPROACH_LIMIT)
 distance = destination.distance_to(global_position)
 if distance < 8.0:
  return
 direction = (destination - global_position).normalized()
 var shape := CircleShape2D.new()
 shape.radius = 26.0
 var query := PhysicsShapeQueryParameters2D.new()
 query.shape = shape
 query.collision_mask = 1
 # Ignore the moving Guardian's own solid footprint during the clearance sweep.
 query.exclude = [$Footprint.get_rid()]
 query.transform = Transform2D(0.0, $Footprint/CollisionShape2D.global_position)
 query.motion = destination - global_position
 var space := get_world_2d().direct_space_state
 if not space.intersect_shape(query, 1).is_empty():
  return
 var sweep := space.cast_motion(query)
 if sweep.size() < 2 or sweep[0] < 0.99:
  return
 var walk := $FallenWalk as AnimatedSprite2D
 var idle := $FallenIdle as AnimatedSprite2D
 idle.hide()
 walk.show()
 walk.play(walk_clip_for_direction(direction))
 walk.set_frame_and_progress(0, 0.0)
 var duration := float(walk.sprite_frames.get_frame_count(walk.animation)) / walk.sprite_frames.get_animation_speed(walk.animation)
 var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
 tween.tween_property(self, "global_position", destination, duration)
 await tween.finished
 if not is_inside_tree():
  return
 walk.stop()
 walk.hide()
 idle.play(_idle_clip_for_direction(target - global_position))
 idle.show()

func _on_battle_finished(result: Dictionary) -> void:
 if not engaged or str(result.get("group_id", "")) != GROUP_ID:
  return
 engaged = false
 if not bool(result.get("victory", false)):
  return
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  return
 zone.set_meta("gerald_backstory_active", true)
 if GameState.quest_domain.quest_ready("village_gerald_trial"):
  GameState.quest_domain.complete_quest("village_gerald_trial")
 GameState.quest_domain.flags[FLAG] = true
 GameState.quest_domain.flags[STORY_PENDING] = true
 _refresh()
 GameState.save_now()
 # battle_finished precedes CombatScreen.closed and queue_free.
 # Defer mounting the story until the combat screen is actually removed.
 _play_backstory.call_deferred()

func _resume_saved_backstory() -> void:
 await get_tree().process_frame
 if is_inside_tree() and bool(GameState.quest_domain.flags.get(STORY_PENDING, false)):
  _play_backstory()

func _play_backstory() -> void:
 if _story_running or not is_inside_tree():
  return
 _story_running = true
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  _story_running = false
  return
 zone.set_meta("gerald_backstory_active", true)
 await get_tree().process_frame
 if not is_instance_valid(zone) or not is_inside_tree():
  return
 var player := zone.get("checkpoint_player") as CharacterBody2D
 if is_instance_valid(player):
  player.input_enabled = false
  player.velocity = Vector2.ZERO
 TouchInput.release()
 var dialogue := zone.get_node_or_null("UI/Dialogue") as DialogueBox
 var layer := zone.get_node("UI/Overlays")
 var previous_music: String = AudioDirector.requested_music_track()
 if not bool(GameState.quest_domain.flags.get(MEMORIES_COMPLETE, false)):
  # The world dialogue is shown only after combat has closed, while Gerald
  # remains kneeling. Memories cannot start until the dialogue is dismissed.
  if dialogue != null:
   dialogue.open(AFTER_BATTLE_DIALOGUE)
   if dialogue.visible:
    await dialogue.closed
  if not is_instance_valid(zone) or not is_inside_tree():
   return
  var memory_track := ""
  for path in ["res://scenes/enemies/boss/gerald_before_the_fall.tscn", "res://scenes/enemies/boss/gerald_boss_intro.tscn"]:
   var packed := load(path) as PackedScene
   if packed == null or not packed.can_instantiate():
    push_warning("[Gerald] Backstory scene unavailable: " + path)
    continue
   var story := packed.instantiate() as Control
   story.name = "GeraldPostVictoryStory"
   story.z_index = 100
   var childhood: bool = str(path).contains("before_the_fall")
   memory_track = "gerald_childhood" if childhood else "gerald_tragedy"
   if AudioDirector.play_track(memory_track, 1.4):
    story.set("music_track_id", memory_track)
   layer.add_child(story)
   await story.finished
   story.queue_free()
   await get_tree().process_frame
   if childhood:
    # Let the first chapter end completely before returning to the conversation.
    # Neither soundtrack should advance while the player reads the dialogue.
    AudioDirector.stop_music(0.8)
    if dialogue != null:
     dialogue.open(BEFORE_TRAGEDY_DIALOGUE)
     if dialogue.visible:
      await dialogue.closed
    if not is_instance_valid(zone) or not is_inside_tree():
     return
  # Return from the last memory to the kneeling guardian. Keep movement and
  # travel locked until the farewell is finished; restore exploration afterward.
  AudioDirector.stop_music(0.8)
  if dialogue != null:
   dialogue.open(FINAL_DIALOGUE)
   if dialogue.visible:
    await dialogue.closed
  if not is_instance_valid(zone) or not is_inside_tree():
   return
  GameState.quest_domain.flags[MEMORIES_COMPLETE] = true
  GameState.save_now()
 if not bool(GameState.quest_domain.flags.get(LILITH_AWAKENED, false)):
  if dialogue != null:
   dialogue.open("gerald_lilith_help")
   if dialogue.visible:
    await dialogue.closed
  if not is_instance_valid(zone) or not is_inside_tree():
   return
  var reunion := REUNION_SCENE.instantiate() as Control
  layer.add_child(reunion)
  await reunion.finished
  if not is_instance_valid(zone) or not is_inside_tree():
   return
  reunion.z_index = 0
  var previous_dialogue_z := dialogue.z_index if dialogue != null else 0
  if dialogue != null:
   dialogue.z_index = 101
  reunion.mouse_filter = Control.MOUSE_FILTER_IGNORE
  if dialogue != null:
   dialogue.open("gerald_lilith_reunion")
   if dialogue.visible:
    await dialogue.closed
  if not is_instance_valid(zone) or not is_inside_tree():
   return
  if dialogue != null:
   dialogue.z_index = previous_dialogue_z
  reunion.queue_free()
  # Existing starter roster owns Lilith; do not grant duplicates or mutate online inventory.
  GameState.quest_domain.flags[LILITH_AWAKENED] = true
  EventBus.party_changed.emit()
  EventBus.toast_requested.emit("Lilith awakened. Party deployment unlocked.")
 if AudioDirector.requested_music_track().is_empty() and not previous_music.is_empty():
  AudioDirector.play_track(previous_music, 1.2)
 GameState.quest_domain.flags[STORY_PENDING] = false
 GameState.quest_domain.flags[STORY_SEEN] = true
 GameState.save_now()
 _refresh()
 zone.set_meta("gerald_backstory_active", false)
 _story_running = false
 if is_instance_valid(player):
  player.input_enabled = true

func _idle_clip_for_direction(displacement: Vector2) -> StringName:
 var direction := "front"
 if absf(displacement.x) > absf(displacement.y):
  direction = "right" if displacement.x > 0.0 else "left"
 elif displacement.y < 0.0:
  direction = "back"
 return StringName("idle_" + direction)

# Only change facing when the player approaches; the authored frames supply motion.
func _process(_delta: float) -> void:
 if not enabled or engaged:
  return
 var zone := get_tree().current_scene
 if zone == null or zone.name != &"StandaloneVillage":
  return
 var player := zone.get("checkpoint_player") as Node2D
 if not is_instance_valid(player):
  return
 var displacement := player.global_position - global_position
 if displacement.length() > 240.0 or displacement.length() < 12.0:
  return
 var sprite := $FallenIdle as AnimatedSprite2D
 var clip := _idle_clip_for_direction(displacement)
 if sprite.animation != clip:
  sprite.play(clip)

