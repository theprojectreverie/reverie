extends Node

class NullFrameSource extends ActorFrameSource:
	func has_frames() -> bool:
		return true

	func validate_sheets() -> Array[String]:
		return []

	func frame(_state: int, _direction: int, _index: int) -> Texture2D:
		return null

const MONSTER_SCENE := preload("res://scenes/world/roaming_monster.tscn")
const BATTLEFIELD_ACTOR_SCENE := preload("res://scenes/ui/battlefield_actor.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _validate_editor_animation_targets():
		return
	var monster := MONSTER_SCENE.instantiate() as Node2D
	if monster == null:
		_fail("Could not instantiate roaming monster scene")
		return
	get_tree().root.add_child(monster)
	await get_tree().process_frame
	var visual_component := monster.get_node_or_null("Components/EnemyVisual") as EnemyVisualComponent
	var actor_visual := monster.get_node_or_null("ActorVisual") as ActorVisual
	if visual_component == null or actor_visual == null:
		_fail("Roaming monster scene is missing its authored enemy visual nodes")
		return
	# Generic actors must not keep a looping locomotion pose running under a
	# one-shot directional action; returning to idle must restore the authored loop.
	actor_visual.play(ActorVisual.S_ATTACK)
	var generic_player := actor_visual.animation_component.get_player()
	if generic_player.current_animation != "generic_attack_pose" or not generic_player.is_playing():
		_fail("Generic attack did not start its editor-authored one-shot pose clip")
		return
	# Let the real state machine finish its attack; its completion callback
	# should return to idle and restart the reusable locomotion clip.
	actor_visual.animator.tick(1.0)
	if actor_visual.animator.state != ActorVisual.S_IDLE:
		_fail("Generic attack did not return to idle after its authored frame duration")
		return
	if actor_visual.animation_component.get_player().current_animation != "idle_bob" or not actor_visual.animation_component.get_player().is_playing():
		_fail("Generic locomotion animation did not resume after the action state")
		return
	var definition := {
		"id": "mossling", "name": "Mossling", "element": "nature",
		"palette": {"skin": "#8ca66b", "primary": "#496d42", "secondary": "#c6a45a", "hair": "#315238", "accent": "#9bd67a"},
	}
	# Verify the dedicated enemy art report, not merely the generic actor source.
	var enemy_report := SpriteFramesActorSource.enemy_validation_report("mossling")
	if bool(enemy_report.get("registered", true)):
		_fail("Mossling must not register before all 72 authored animations exist")
		return
	if not bool(enemy_report.get("fallback_active", false)):
		_fail("Enemy art report must explicitly retain fallback while source art is incomplete")
		return
	if int(enemy_report.get("animation_count", -1)) != 0:
		_fail("Missing production enemy sheet should report zero registered animations")
		return
	if str(enemy_report.get("expected_tres", "")) != "res://assets/enemies/mossling/world_sheet.tres":
		_fail("Enemy art report resolved outside the dedicated Mossling folder")
		return

	# Seed a valid prior SpriteFrames source to catch stale-art leakage when
	# an actor is reconfigured to an enemy whose production sheet is missing.
	var mutable_probe := _make_valid_probe_source()
	actor_visual.set_frame_source(mutable_probe)
	if not actor_visual._sprite_active:
		_fail("Synthetic prior source did not activate the frame-backed presentation")
		return
	# Mutate the exact currently displayed slot without changing the animator
	# key. The runtime must inspect the slot before taking its same-frame fast path.
	var current_animation := StringName("%s_%d" % [CharacterAnimator.state_name(actor_visual.animator.state), actor_visual.animator.direction])
	var current_frame := actor_visual.animator.frame
	var mutable_sprite_source := mutable_probe as SpriteFramesActorSource
	if mutable_sprite_source == null or not mutable_sprite_source.sprite_frames.has_animation(current_animation):
		_fail("Synthetic source did not expose the current directional animation")
		return
	var replacement_image := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	replacement_image.fill(Color(0.8, 0.2, 0.2, 1.0))
	var replacement_texture := ImageTexture.create_from_image(replacement_image)
	mutable_sprite_source.sprite_frames.set_frame(current_animation, current_frame, replacement_texture)
	actor_visual._update_sprite_frame()
	if actor_visual._sprite.texture != replacement_texture or not actor_visual._sprite_active:
		_fail("A valid texture replacement at the same animation key was hidden by the frame cache")
		return
	mutable_sprite_source.sprite_frames.set_frame(current_animation, current_frame, null)
	actor_visual._update_sprite_frame()
	if actor_visual._sprite_active or actor_visual._custom_source or not (actor_visual.frame_source is ProceduralActorFrames):
		_fail("A null texture introduced into the currently displayed frame was not caught until an animation change")
		return
	# Restore a valid fixture so the following stale-source replacement check
	# remains independent of the runtime-mutation case above.
	actor_visual.set_frame_source(_make_valid_probe_source())
	if not actor_visual._sprite_active:
		_fail("Valid prior source did not reactivate after the mutation fallback test")
		return
	actor_visual.character_id = "mossling"
	actor_visual._sprite.position = Vector2(7.0, 8.0)
	actor_visual.pose_component.update_locomotion_pose(0.016)
	if actor_visual._sprite.position != Vector2(7.0, 8.0):
		_fail("Generic enemy pose runtime overwrote the editor-authored sprite transform")
		return
	actor_visual._sprite.position = Vector2.ZERO
	var configured := visual_component.configure_enemy(monster, definition, false, 17)
	if configured != actor_visual:
		_fail("Enemy visual setup did not return its ActorVisual")
		return
	if actor_visual.character_id != "mossling":
		_fail("Mossling enemy id was not passed into ActorVisual")
		return
	if actor_visual.def_id != "mossling":
		_fail("Mossling fallback silhouette was replaced by an unrelated random enemy species")
		return
	var report := actor_visual.character_art_report()
	if str(report.get("frame_source", "")).is_empty():
		_fail("ActorVisual did not retain a frame source for its fallback")
		return
	if not bool(report.get("using_temporary_art", true)):
		_fail("Mossling placeholder should remain temporary until complete art exists")
		return
	if actor_visual._sprite_active:
		_fail("Incomplete Mossling art unexpectedly activated the frame sprite")
		return
	if actor_visual._custom_source or not (actor_visual.frame_source is ProceduralActorFrames):
		_fail("Failed enemy registration did not replace the prior source with the procedural fallback")
		return
	# Also exercise a source that passes initial validation but returns a null
	# texture at runtime. It must transition atomically to the same fallback.
	actor_visual.set_frame_source(NullFrameSource.new())
	if actor_visual._custom_source or actor_visual._sprite_active or not (actor_visual.frame_source is ProceduralActorFrames):
		_fail("A null runtime frame did not restore the procedural fallback source")
		return
	if not actor_visual.using_temporary_art:
		_fail("Runtime null-frame fallback was not marked as temporary art")
		return
	if monster.get_node_or_null("NameLabel") == null or monster.get_node("NameLabel").text != "Mossling":
		_fail("Enemy name label was not configured")
		return

	# The combat actor must use the same enemy-only registration seam as roaming.
	var battle_actor := BATTLEFIELD_ACTOR_SCENE.instantiate() as BattlefieldActor
	if battle_actor == null:
		_fail("Could not instantiate authored battlefield actor scene")
		return
	get_tree().root.add_child(battle_actor)
	await get_tree().process_frame
	var battle_unit := Combatant.new()
	battle_unit.uid = "mossling_battle_visual_probe"
	battle_unit.def_id = "mossling"
	battle_unit.display_name = "Mossling"
	battle_unit.palette = definition.palette
	battle_unit.element = "nature"
	battle_unit.hp = 100.0
	battle_unit.max_hp = 100.0
	battle_actor.setup(battle_unit, false)
	if battle_actor.visual == null or battle_actor.visual.character_id != "mossling":
		_fail("Battlefield actor did not pass the Mossling enemy id into ActorVisual")
		return
	var battle_art_report := battle_actor.visual.character_art_report()
	if str(battle_art_report.get("frame_source", "")).is_empty() or not bool(battle_art_report.get("using_temporary_art", false)):
		_fail("Missing Mossling sheet did not preserve the combat procedural fallback")
		return
	if battle_actor.visual._sprite_active or battle_actor.visual._custom_source:
		_fail("Combat actor activated an incomplete or stale enemy sprite source")
		return
	battle_actor.play_attack()
	if battle_actor.visual.animator.state != ActorVisual.S_ATTACK:
		_fail("Mossling combat actor did not retain its shared attack animation state")
		return
	var pending_effect := Node2D.new()
	battle_actor.add_child(pending_effect)
	battle_actor.track_attack_effect(pending_effect)
	var launched_effect := Node2D.new()
	battle_actor.add_child(launched_effect)
	battle_actor.track_attack_effect(launched_effect)
	# The attack's pending effect is still owned by the windup; the launched
	# effect has crossed its launch boundary and must finish independently.
	battle_actor.release_attack_effect(launched_effect)
	battle_actor.take_hit()
	if battle_actor.visual.animator.state != ActorVisual.S_DAMAGE:
		_fail("An interrupted Mossling attack did not enter the shared damage animation state")
		return
	if not pending_effect.is_queued_for_deletion():
		_fail("An interrupted Mossling attack did not clear its pending attack-owned effect")
		return
	if launched_effect.is_queued_for_deletion() or not is_instance_valid(launched_effect):
		_fail("An interrupted attack incorrectly deleted an already-launched effect before its own animation completed")
		return
	launched_effect.queue_free()
	battle_actor.play_victory()
	if battle_actor.visual.animator.state != ActorVisual.S_VICTORY:
		_fail("Mossling combat actor did not route victory through the shared one-shot animation")
		return
	battle_actor.play_death()
	if battle_actor.visual.animator.state != ActorVisual.S_DEFEAT or not battle_actor.dead:
		_fail("Mossling combat actor did not route defeat through the shared one-shot animation")
		return
	battle_actor.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	print("PASS: Mossling enemy-only art lookup is shared by roaming and battlefield actors; missing art keeps both procedural fallbacks and combat animation routing")
	get_tree().quit(0)

func _validate_editor_animation_targets() -> bool:
	var library := load("res://resources/characters/animations/character_locomotion.tres") as AnimationLibrary
	if library == null:
		_fail("Could not load the editor-authored character locomotion library")
		return false
	for animation_name in [&"idle_bob", &"walk_bob", &"run_bob", &"generic_interact_pose", &"generic_attack_pose", &"generic_damage_pose", &"generic_victory_pose", &"generic_defeat_pose", &"generic_cast_pose"]:
		if not library.has_animation(animation_name):
			_fail("Missing reusable locomotion clip: %s" % animation_name)
			return false
		var animation := library.get_animation(animation_name)
		if String(animation_name).begins_with("generic_"):
			var state_name := String(animation_name).trim_prefix("generic_").trim_suffix("_pose")
			var state_id: Variant = CharacterAnimator.EXTENDED_STATE_NAMES.find_key(state_name)
			if state_id == null:
				_fail("Generic pose clip has no catalog state: %s" % animation_name)
				return false
			var expected_duration := float(CharacterAnimator.frame_count_for(int(state_id))) / CharacterAnimator.fps_for(int(state_id))
			if not is_equal_approx(animation.length, expected_duration) or animation.loop_mode != Animation.LOOP_NONE:
				_fail("Generic action clip timing/loop contract differs from CharacterAnimator: %s" % animation_name)
				return false
		for track_index in animation.get_track_count():
			var target := animation.track_get_path(track_index)
			if not str(target).begins_with("FrameSprite:"):
				_fail("Locomotion clip %s animates actor root instead of FrameSprite: %s" % [animation_name, target])
				return false
	print("PASS: reusable locomotion clips animate FrameSprite only; actor world transform is not animated")
	return true


func _make_valid_probe_source() -> ActorFrameSource:
	# In-memory test fixture only: repeated texture references exercise the
	# registration gate and are never saved or treated as production artwork.
	var image := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.2, 1.0))
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for raw_state in CharacterAnimator.EXTENDED_STATES:
		var state := int(raw_state)
		var animation := StringName("%s_0" % CharacterAnimator.state_name(state))
		# This fixture is intentionally not a valid full sheet; instead build
		# every direction and frame so the source passes the exact validator.
		for raw_direction in CharacterAnimator.ALL_DIRECTIONS:
			var direction := int(raw_direction)
			var name := StringName("%s_%d" % [CharacterAnimator.state_name(state), direction])
			frames.add_animation(name)
			frames.set_animation_speed(name, CharacterAnimator.fps_for(state))
			frames.set_animation_loop(name, CharacterAnimator.looping_for(state))
			for frame_index in CharacterAnimator.frame_count_for(state):
				frames.add_frame(name, texture)
	var source: ActorFrameSource = load("res://scripts/art/sprite_frames_actor_source.gd").new("prior_probe")
	source.sprite_frames = frames
	return source


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	get_tree().quit(1)
