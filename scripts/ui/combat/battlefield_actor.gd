class_name BattlefieldActor
extends Node2D
## One combatant standing on the battlefield.
##
## PRESENTATION ONLY. It owns the figure (an ActorVisual, so real sprite sheets
## and the procedural placeholder creatures share one code path), the ground
## shadow, the HP plate and the reactive hooks (idle, hit, lunge, death).
## It never touches combat maths: the engine owns HP, damage and turns.

signal clicked(actor: BattlefieldActor)

## Scale for a real painted sprite sheet (the 96x128 world frames).
const SPRITE_SCALE := 1.35
## Scale for the procedural placeholder creature (roughly half the height of a
## painted sprite, so it needs a bigger multiplier to read the same).
const PLACEOLDER_SCALE := 2.0
## Bosses are visibly larger than ordinary combatants.
const BOSS_MULTIPLIER := 1.55

const PLATE_WIDTH := 72.0
const PLATE_HEIGHT := 6.0
const PLATE_OFFSET := 14.0


var live_art: AnimatedSprite2D
var _live_facing_right := true
var _live_facings: Dictionary = {}
var rose_art: AnimatedSprite2D
var fairy_art: AnimatedSprite2D
var _fairy_facing_right := false
var gerald_art: AnimatedSprite2D
var gerald_walk_sequence_active := false
var _gerald_walk_progress := 0.0
var _gerald_walk_target: WeakRef
const GERALD_WALK_TIME := 1.2
const GERALD_STRIKE_TIME := 1.74
var cassien_art: AnimatedSprite2D
var elathra_art: AnimatedSprite2D
var ravienna_art: Node2D
var kael_boss_art_enabled := false
var kael_boss_sequence_active := false
@onready var kael_boss_art: AnimatedSprite2D = $KaelBossCombatArt
var unit: Combatant = null
var visual: ActorVisual = null
var _matron_presentation: FallenMatronPresentationComponent
var is_player: bool = false
var home_position: Vector2 = Vector2.ZERO
var targetable: bool = false
var active: bool = false
var dead: bool = false
var interruption_serial: int = 0

var _hp_ratio: float = 1.0
var _hp_color: Color = Color(0.4, 0.9, 0.5)
var _name_label: Label = null
var _intent_label: Label = null
var _hp_plate: ProgressBar = null
var _pulse: float = 0.0
var _hit_shake: float = 0.0
var _base_scale: float = 1.0
var _ground_fx: BattlefieldActorGroundFX = null
var _hit_flash_tween: Tween = null
@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_animation_player.animation_finished.connect(_on_authored_animation_finished)


func setup(p_unit: Combatant, p_is_player: bool) -> void:
	unit = p_unit
	is_player = p_is_player
	_ground_fx = get_node_or_null("GroundFX") as BattlefieldActorGroundFX
	_matron_presentation = get_node_or_null("MatronPresentation") as FallenMatronPresentationComponent
	var hit := get_node_or_null("Hitbox") as Control
	_name_label = get_node_or_null("NameLabel") as Label
	_intent_label = get_node_or_null("EnemyIntent") as Label
	_hp_plate = get_node_or_null("HPPlate") as ProgressBar
	visual = get_node_or_null("ActorVisual") as ActorVisual
	if _ground_fx == null or _matron_presentation == null or hit == null or _name_label == null or _intent_label == null or _hp_plate == null or visual == null:
		push_error("BattlefieldActor is missing an authored visual, hitbox, label, HP plate, or GroundFX child.")
		return
	hit.custom_minimum_size = Vector2(72, 110)
	hit.position = Vector2(-36, -96)
	hit.size = Vector2(72, 110)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	if not hit.gui_input.is_connected(_on_hit_input):
		hit.gui_input.connect(_on_hit_input)
	_name_label.text = unit.display_name
	_name_label.add_theme_color_override("font_color", UITheme.TEXT)
	_intent_label.visible = false

	# Meter geometry and frame are authored in combatant_hp_plate.tscn.
	_hp_color = UITheme.GREEN if is_player else UITheme.DANGER
	if _hp_plate != null:
		_hp_plate.min_value = 0.0
		_hp_plate.max_value = 1.0
		_hp_plate.show_percentage = false
		_hp_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate_fill := _hp_plate.get_theme_stylebox("fill") as StyleBoxFlat
		if plate_fill != null:
			plate_fill.bg_color = _hp_color

	# The shared world idle clip writes an absolute FrameSprite scale of 1.0.
	# Remove that track only from this combat instance; keep all world clips intact.
	var locomotion_player := visual.animation_component.get_player()
	if locomotion_player != null:
		for library_name in locomotion_player.get_animation_library_list():
			var library := locomotion_player.get_animation_library(library_name)
			var local := AnimationLibrary.new()
			for clip in library.get_animation_list():
				var anim := library.get_animation(clip)
				var has_scale := false
				for i in anim.get_track_count():
					if str(anim.track_get_path(i)) == "FrameSprite:scale": has_scale = true
				if has_scale:
					anim = anim.duplicate() as Animation
					for i in range(anim.get_track_count()-1,-1,-1):
						if str(anim.track_get_path(i)) == "FrameSprite:scale": anim.remove_track(i)
				local.add_animation(clip,anim)
			locomotion_player.remove_animation_library(library_name)
			locomotion_player.add_animation_library(library_name,local)
	visual.is_boss = unit.is_boss
	if is_player:
		var definition := ContentDB.get_character(unit.def_id)
		var race := "Human"
		var kind := ActorVisual.Kind.HUMAN
		if definition != null:
			race = definition.race
			if definition.race == "Spirit":
				kind = ActorVisual.Kind.SPIRIT
			elif definition.race == "Monster":
				kind = ActorVisual.Kind.MONSTER
			visual.setup(definition.palette, kind, unit.def_id, race, unit.element)
			# Real sprite sheets plug in here (Gerald / Lilith / Kael); everyone
			# else keeps the procedural placeholder creature.
			visual.configure_character(unit.def_id)
		else:
			visual.setup(unit.palette, kind, unit.def_id, race, unit.element)
	else:
		# Enemy sheets use the dedicated enemy-only registry path. Until a complete
		# validated 72-animation SpriteFrames resource exists, ActorVisual keeps
		# its species-specific procedural placeholder without borrowing playable art.
		visual.setup(unit.palette, ActorVisual.Kind.MONSTER, unit.def_id, "Monster", unit.element)
		visual.configure_enemy_art(unit.def_id)
		if unit.def_id in ["rose_slime", "crownling"]:
			rose_art = load("res://scenes/world/six_zone_reverie/%s_art.tscn" % unit.def_id).instantiate() as AnimatedSprite2D
			add_child(rose_art)
			rose_art.scale = Vector2(1.4, 1.4)
			rose_art.position.y = -44.0
			visual.hide()
			rose_art.animation_finished.connect(_rose_animation_finished)
			rose_art.animation_changed.connect(_sync_monster_body_scale)
			_sync_monster_body_scale()
	if (is_player or unit.def_id.begins_with("livechar_")) and LiveCharacterContent.frames_for(unit.def_id) != null:
		live_art = $LiveCombatArt
		live_art.sprite_frames = LiveCharacterContent.frames_for(unit.def_id)
		var pack: Dictionary=LiveCharacterContent.installed.get(unit.def_id,{})
		_live_facings=pack.get("facings",{}).duplicate()
		live_art.offset.y=64.0-float(pack.get("bottom",128.0))
		live_art.animation_changed.connect(_sync_live_facing)
		live_art.show()
		live_art.play(&"idle")
		live_art.animation_finished.connect(_live_return_idle)
		visual.hide()
	if live_art == null and is_player and unit.def_id.begins_with("mirene_"):
		live_art = $LiveCombatArt
		live_art.sprite_frames = preload("res://assets/characters/harlequin/combat_frames.tres")
		_live_facings = {"idle":"left","basic_attack":"left","skill_1":"left","skill_2":"left","ultimate":"left","hit":"left","defeat":"left"}
		live_art.offset.y = -64.0
		live_art.animation_changed.connect(_sync_live_facing)
		live_art.show()
		live_art.play(&"idle")
		live_art.animation_finished.connect(_live_return_idle)
		visual.hide()
	if live_art == null and is_player and unit.def_id in ["elathra", "elathra_mythic"]:
		elathra_art = $ElathraArt
		elathra_art.show()
		elathra_art.play(&"idle")
		visual.hide()
	if unit.def_id == "gerald_boss":
		gerald_art = get_node("GeraldFallenArt") as AnimatedSprite2D
		gerald_art.show()
		gerald_art.play("idle")
		gerald_art.animation_finished.connect(_gerald_return_idle)
		gerald_art.animation_changed.connect(_sync_gerald_body_scale)
		gerald_art.get_node("WalkArt").frame_changed.connect(_on_gerald_walk_frame_changed)
		visual.hide()
	if live_art == null and (unit.def_id == "cassien_boss" or (is_player and (unit.def_id == "cassien" or unit.def_id.begins_with("cassien_")))):
		cassien_art = $CassienArt
		cassien_art.show()
		cassien_art.play("idle")
		cassien_art.animation_finished.connect(_cassien_return_idle)
		visual.hide()
	if live_art == null and (unit.def_id == "revienna_boss" or (is_player and (unit.def_id == "ravienna" or unit.def_id.begins_with("ravienna_")))):
		ravienna_art = $ReviennaArt
		if is_player:
			var playable_sprite := ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
			playable_sprite.sprite_frames = preload("res://assets/characters/ravienna/playable_combat/combat_frames.tres")
			playable_sprite.play(&"idle")
		ravienna_art.show()
		ravienna_art.get_node("AnimatedSprite2D").animation_finished.connect(_revienna_return_idle)
		visual.hide()
	# The bespoke boss presentation is a scene-owned child component.
	_matron_presentation.configure(unit, visual)
	_base_scale = SPRITE_SCALE if not visual.using_temporary_art else PLACEOLDER_SCALE
	if unit.is_boss:
		# These hand-drawn silhouettes have different authored heights. Give
		# each a stage-fit scale instead of multiplying every boss equally and
		# clipping the tallest crowns against the top of the battlefield.
		match unit.def_id:
			"corrupted_treant":
				_base_scale = 1.35
			"elder_hollow":
				_base_scale = 1.15
			"fallen_matron":
				_base_scale = 1.35
			_:
				_base_scale *= BOSS_MULTIPLIER
	visual.set_body_scale(_base_scale)
	if unit.def_id == "fairy_spar":
		fairy_art = visual.get_node("FairySparArt") as AnimatedSprite2D
		fairy_art.reparent(self, false)
		fairy_art.show()
		fairy_art.animation_finished.connect(_fairy_return_idle)
		visual.hide()
	if unit.is_boss and unit.def_id not in ["fallen_matron", "gerald_boss", "revienna_boss", "cassien_boss"]:
		_animation_player.play("boss_idle")
	var element_color := UITheme.element_color(unit.element)
	if element_color == UITheme.TEXT_DIM:
		element_color = Color("#c6cad6")
	_ground_fx.configure(is_player, unit.is_boss, unit.def_id == "fallen_matron", element_color)
	_sync_ground_fx()
	if is_instance_valid(live_art) or is_instance_valid(cassien_art) or is_instance_valid(ravienna_art):
		face(Vector2.RIGHT if is_player else Vector2.LEFT)
	else:
		face(Vector2(-1.0, 0.0) if is_player else Vector2(1.0, 0.0))
	refresh()


## Direction the figure looks in (screen space).
func face(direction: Vector2) -> void:
	if visual == null:
		return
	if direction.length_squared() < 0.001:
		return
	visual.set_move_direction(direction.normalized())
	visual.facing = 1.0 if direction.x >= 0.0 else -1.0
	if is_instance_valid(live_art):
		_live_facing_right=direction.x>=0.0
		_sync_live_facing()
	if is_instance_valid(fairy_art) and not dead:
		_fairy_facing_right = direction.x > 0.0
		if fairy_art.animation in [&"front", &"left", &"right"]:
			_fairy_return_idle()
		else:
			fairy_art.flip_h = _fairy_facing_right
	if is_instance_valid(cassien_art):
		cassien_art.flip_h = direction.x > 0.0
	if is_instance_valid(elathra_art):
		elathra_art.flip_h = direction.x < 0.0
	if is_instance_valid(ravienna_art):
		ravienna_art.get_node("AnimatedSprite2D").flip_h = direction.x > 0.0


func enable_kael_boss_art() -> void:
	if is_instance_valid(live_art): return
	kael_boss_art_enabled = true
	_sync_kael_boss_art()

func play_kael_boss_clip(clip: StringName) -> void:
	kael_boss_sequence_active = clip != &"idle"
	kael_boss_art.play(clip)
	kael_boss_art.set_frame_and_progress(0, 0.0)
	_sync_kael_boss_art()

func _sync_kael_boss_art() -> void:
	if not kael_boss_art_enabled or visual == null:
		return
	var show_art := not dead
	if show_art and not kael_boss_sequence_active and kael_boss_art.animation != &"idle":
		kael_boss_art.play(&"idle")
	elif show_art and not kael_boss_art.is_playing() and not kael_boss_sequence_active:
		kael_boss_art.play(&"idle")
	kael_boss_art.visible = show_art
	visual.visible = not show_art
	kael_boss_art.flip_h = visual.facing < 0.0
	var attack := kael_boss_art.animation == &"attack"
	# Scale the entire clip uniformly. The original attack standing poses are
	# smaller than idle; the larger-headed travel drawings need a modest reduction.
	var correction := 1.0
	match kael_boss_art.animation:
		&"attack": correction = 1.12
		&"approach", &"retreat": correction = 0.96
	kael_boss_art.scale = Vector2.ONE * visual.visual_scale * (108.0 / 110.0) * correction
	# Keep the original lift during approach/withdrawal and the blade pivot at contact.
	kael_boss_art.offset = Vector2(10.0 * (-1.0 if kael_boss_art.flip_h else 1.0) if attack else 0.0, -58.0 if attack else -57.0)

func refresh() -> void:
	if unit == null:
		return
	_hp_ratio = unit.hp_ratio()
	if _hp_plate != null:
		_hp_plate.value = _hp_ratio
		var plate_fill := _hp_plate.get_theme_stylebox("fill") as StyleBoxFlat
		if plate_fill != null:
			plate_fill.bg_color = _hp_color
	_matron_presentation.refresh_phase(_hp_ratio)
	_name_label.text = ("◆  " if targetable else "") + unit.display_name
	_name_label.add_theme_color_override("font_color",
		UITheme.GOLD_BRIGHT if targetable else UITheme.TEXT if unit.is_alive() else UITheme.TEXT_DIM)
	if not unit.is_alive() and not is_instance_valid(rose_art) and not is_instance_valid(fairy_art) and not is_instance_valid(gerald_art) and not is_instance_valid(cassien_art) and not is_instance_valid(ravienna_art) and not is_instance_valid(live_art):
		modulate = Color(1, 1, 1, 0.38)
	queue_redraw()


func set_intent(skill_name: String) -> void:
	if _intent_label == null:
		return
	_intent_label.visible = not skill_name.is_empty() and not is_player and not dead
	_intent_label.text = "!  %s" % skill_name.to_upper() if _intent_label.visible else ""
	_intent_label.position = Vector2(-78, -124 if unit != null and unit.is_boss else -104)
	if is_instance_valid(gerald_art):
		_intent_label.position.y = maxf(-position.y + 2.0, -114.0 * gerald_art.scale.y - 18.0)
	if is_instance_valid(cassien_art):
		_intent_label.position.y = maxf(-position.y + 2.0, -106.0 * cassien_art.scale.y - 18.0)
	_intent_label.size = Vector2(156, 20)
	queue_redraw()


func set_targetable(value: bool) -> void:
	if targetable == value:
		return
	targetable = value
	queue_redraw()


func set_active(value: bool) -> void:
	active = value
	queue_redraw()


## The ground position this actor returns to after an attack.
func set_home(position: Vector2) -> void:
	home_position = position


func _process(delta: float) -> void:
	if is_instance_valid(ravienna_art):
		position = home_position
	_pulse += delta
	_sync_kael_boss_art()
	_sync_ground_fx()
	if _matron_presentation != null:
		_matron_presentation.refresh_phase(_hp_ratio)
	if _hit_shake > 0.0:
		_hit_shake = maxf(0.0, _hit_shake - delta * 4.0)
	if visual == null:
		return
	# A subtle breathing bob keeps the idle loop alive without extra nodes.
	var bob := sin(_pulse * 1.7) * 1.6
	if _matron_presentation != null and _matron_presentation.active:
		_matron_presentation.update_idle(_pulse, _hit_shake, bob, dead)
	elif not dead and (unit == null or not unit.is_boss):
		visual.position = Vector2(_hit_shake * 6.0, bob)


func track_attack_motion(motion: Tween) -> void:
	if motion == null or not motion.is_valid():
		return
	if has_meta("attack_motion_tween"):
		var previous = get_meta("attack_motion_tween")
		if previous is Tween and previous.is_valid() and previous.is_running():
			previous.kill()
	set_meta("attack_motion_tween", motion)
	var motion_ref: WeakRef = weakref(motion)
	motion.finished.connect(func() -> void:
		var tracked_motion := motion_ref.get_ref() as Tween
		if tracked_motion != null and has_meta("attack_motion_tween") and get_meta("attack_motion_tween") == tracked_motion:
			remove_meta("attack_motion_tween")
	)


## A second cancellable channel for timed stage callbacks that must coexist
## with the actor's spatial attack motion.
func track_attack_sequence(motion: Tween) -> void:
	if motion == null or not motion.is_valid():
		return
	if has_meta("attack_sequence_tween"):
		var previous = get_meta("attack_sequence_tween")
		if previous is Tween and previous.is_valid() and previous.is_running():
			previous.kill()
	set_meta("attack_sequence_tween", motion)
	var motion_ref: WeakRef = weakref(motion)
	motion.finished.connect(func() -> void:
		var tracked_motion := motion_ref.get_ref() as Tween
		if tracked_motion != null and has_meta("attack_sequence_tween") and get_meta("attack_sequence_tween") == tracked_motion:
			remove_meta("attack_sequence_tween")
	)


## Pending telegraphs and pre-launch effects remain owned by the current attack
## so interruption can remove them. Release a committed projectile or started
## one-shot with release_attack_effect() so it can finish independently.
var _attack_effects: Array[Node] = []


func track_attack_effect(effect: Node) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	if not _attack_effects.has(effect):
		_attack_effects.append(effect)
		effect.tree_exited.connect(_on_attack_effect_tree_exited.bind(effect), CONNECT_ONE_SHOT)


func _on_attack_effect_tree_exited(effect: Node) -> void:
	_attack_effects.erase(effect)


## Once an effect has launched or its authored one-shot has begun, it owns its
## own completion. Attacker interruption may cancel pending windups/telegraphs,
## but must not erase a projectile already in flight or an impact already playing.
func release_attack_effect(effect: Node) -> void:
	if effect == null:
		return
	_attack_effects.erase(effect)


func cancel_attack_effects() -> void:
	for effect in _attack_effects:
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			effect.queue_free()
	_attack_effects.clear()


func cancel_attack_motion(restore_formation: bool = true) -> void:
	interruption_serial += 1
	for key in ["attack_motion_tween", "attack_sequence_tween"]:
		if has_meta(key):
			var motion = get_meta(key)
			if motion is Tween and motion.is_valid() and motion.is_running():
				motion.kill()
			remove_meta(key)
	cancel_attack_effects()
	if gerald_walk_sequence_active:
		_end_gerald_walk()
	if kael_boss_art_enabled and kael_boss_sequence_active:
		play_kael_boss_clip(&"idle")
	if is_instance_valid(cassien_art) and not dead:
		cassien_art.play(&"idle")
	if is_instance_valid(fairy_art) and not dead:
		_fairy_return_idle()
	if restore_formation:
		position = home_position

func track_recoil_motion(motion: Tween) -> void:
	if motion == null or not motion.is_valid():
		return
	if has_meta("battle_recoil_tween"):
		var previous = get_meta("battle_recoil_tween")
		if previous is Tween and previous.is_valid() and previous.is_running():
			previous.kill()
	set_meta("battle_recoil_tween", motion)
	var motion_ref: WeakRef = weakref(motion)
	motion.finished.connect(func() -> void:
		var tracked_motion := motion_ref.get_ref() as Tween
		if tracked_motion != null and has_meta("battle_recoil_tween") and get_meta("battle_recoil_tween") == tracked_motion:
			remove_meta("battle_recoil_tween")
	)


func cancel_recoil_motion(restore_formation: bool = true) -> void:
	if has_meta("battle_recoil_tween"):
		var motion = get_meta("battle_recoil_tween")
		if motion is Tween and motion.is_valid() and motion.is_running():
			motion.kill()
		remove_meta("battle_recoil_tween")
	if restore_formation:
		position = home_position


func _cancel_hit_flash(restore_tint: bool = true) -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid() and _hit_flash_tween.is_running():
		_hit_flash_tween.kill()
	_hit_flash_tween = null
	if restore_tint and visual != null and is_instance_valid(visual):
		visual.modulate = Color.WHITE
	if restore_tint and is_instance_valid(kael_boss_art): kael_boss_art.modulate = Color.WHITE


func _recover_combat_pose() -> void:
	var battle_player := get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
	if battle_player != null and battle_player.has_animation("battle_recover"):
		battle_player.play("battle_recover")
	var kael_player := get_node_or_null("KaelAnimationPlayer") as AnimationPlayer
	if kael_player != null and kael_player.has_animation("kael_recover"):
		kael_player.play("kael_recover")

## Damage reaction: white flash + a short shake + the damage animation.
func take_hit() -> void:
	if is_instance_valid(live_art):
		if not dead: live_art.play(&"hit")
		return
	if kael_boss_art_enabled and not dead:
		if not kael_boss_sequence_active:
			cancel_attack_motion()
			cancel_recoil_motion()
			_recover_combat_pose()
			visual.hit()
		# The server has already resolved damage; do not abort an active authored
		# approach/strike/withdrawal because an earlier delayed visual lands.
		_cancel_hit_flash()
		kael_boss_art.modulate = Color(1.65, 0.75, 0.75)
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_property(kael_boss_art, "modulate", Color.WHITE, 0.28)
		return
	if is_instance_valid(elathra_art):
		if not dead:
			elathra_art.get_node("PoseAnimation").play("hit")
		return
	if is_instance_valid(ravienna_art):
		if not dead:
			var sprite := ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
			if sprite.animation in [&"idle", &"hit"]:
				sprite.play(&"hit")
				sprite.set_frame_and_progress(0, 0.0)
				ravienna_art.get_node("PoseAnimation").play("hit")
		return
	if is_instance_valid(cassien_art):
		if not dead:
			_cancel_hit_flash()
			# Delayed hit reactions must not replace an active authored strike.
			if not (cassien_art.is_playing() and cassien_art.animation in [&"attack", &"heavy_attack", &"crimson_crescent", &"crimson_requiem"]):
				cancel_attack_motion()
				cassien_art.play(&"hit")
				cassien_art.set_frame_and_progress(0, 0.0)
			cassien_art.modulate = Color(1.8,0.65,0.65)
			_hit_flash_tween = create_tween()
			_hit_flash_tween.tween_property(cassien_art,"modulate",Color.WHITE,0.28)
		return
	if is_instance_valid(gerald_art):
		if not dead and not gerald_walk_sequence_active and gerald_art.animation not in [&"attack", &"earthquake"]:
			gerald_art.position.y = -57.0 * gerald_art.scale.y
			gerald_art.modulate = Color.WHITE
			gerald_art.play("hit")
			gerald_art.set_frame_and_progress(0, 0.0)
		return
	if is_instance_valid(fairy_art):
		if not dead and fairy_art.animation not in [&"crystal_bolt", &"crystal_veil", &"crystal_bloom"]:
			_play_fairy_clip(&"hit")
		return
	if is_instance_valid(rose_art) and not dead:
		rose_art.play("hit")
		return
	_cancel_hit_flash()
	cancel_attack_motion()
	cancel_recoil_motion()
	_recover_combat_pose()
	if visual == null:
		return
	_hit_shake = 1.0
	if _matron_presentation != null and _matron_presentation.active:
		_matron_presentation.take_hit()
		return
	if unit != null and unit.is_boss:
		_animation_player.play("boss_hit")
		return
	visual.hit()
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(visual, "modulate", Color(2.2, 2.2, 2.4, 1.0), 0.05)
	_hit_flash_tween.tween_property(visual, "modulate", Color.WHITE, 0.28)
	_hit_flash_tween.tween_callback(func() -> void:
		_hit_flash_tween = null
	)


## The attack lunge is driven by the battlefield (it knows the target).
# Existing painted walk frames; only the presentation moves, never the combat rules.
func _on_gerald_walk_frame_changed() -> void:
	if not gerald_walk_sequence_active or dead or not is_instance_valid(gerald_art):
		return
	var walk := gerald_art.get_node("WalkArt") as AnimatedSprite2D
	if walk.visible and walk.is_playing() and walk.frame in [3, 11]:
		AudioDirector.play_variant("dirt_step", -5.0, 0.72)

func _show_gerald_walk(direction: Vector2) -> void:
	var walk := gerald_art.get_node("WalkArt") as AnimatedSprite2D
	var names := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
	var index := posmod(roundi(direction.angle() / (PI / 4.0)), 8)
	gerald_art.position.y = -57.0 * gerald_art.scale.y
	walk.position.y = -3.0
	gerald_art.pause()
	gerald_art.self_modulate.a = 0.0
	walk.show()
	_sync_gerald_body_scale()
	walk.play(StringName("walk_" + names[index]), 16.0 / (9.0 * GERALD_WALK_TIME))
	walk.set_frame_and_progress(0, 0.0)

func _hide_gerald_walk() -> void:
	var walk := gerald_art.get_node("WalkArt") as AnimatedSprite2D
	walk.stop()
	walk.hide()
	_sync_gerald_body_scale()
	gerald_art.self_modulate.a = 1.0
	gerald_art.position.y = -57.0 * gerald_art.scale.y

func _end_gerald_walk() -> void:
	gerald_walk_sequence_active = false
	_gerald_walk_progress = 0.0
	_gerald_walk_target = null
	position = home_position
	_hide_gerald_walk()
	if not dead:
		gerald_art.play("idle")

# Keep the walk path relative to the current responsive formation, not old screen coordinates.
func refresh_gerald_walk_position() -> void:
	if not gerald_walk_sequence_active or _gerald_walk_target == null:
		return
	var target := _gerald_walk_target.get_ref() as BattlefieldActor
	if not is_instance_valid(target):
		position = home_position
		return
	var delta := target.home_position - home_position
	var reach := clampf(delta.length() - 140.0, 0.0, 120.0)
	position = home_position + delta.normalized() * reach * _gerald_walk_progress

func _set_gerald_walk_progress(progress: float) -> void:
	_gerald_walk_progress = progress
	refresh_gerald_walk_position()

func play_gerald_flame_approach(target: BattlefieldActor) -> bool:
	if not is_instance_valid(gerald_art) or dead or not is_instance_valid(target) or target == self:
		return false
	var displacement := target.home_position - home_position
	var distance := minf(120.0, displacement.length() - 140.0)
	if distance < 8.0:
		return false
	cancel_attack_motion()
	gerald_walk_sequence_active = true
	_gerald_walk_target = weakref(target)
	_gerald_walk_progress = 0.0
	var direction := displacement.normalized()
	var motion := create_tween()
	track_attack_motion(motion)
	_show_gerald_walk(direction)
	motion.tween_method(_set_gerald_walk_progress, 0.0, 1.0, GERALD_WALK_TIME)
	motion.tween_callback(func() -> void:
		_hide_gerald_walk()
		play_gerald_action(false)
	)
	motion.tween_interval(GERALD_STRIKE_TIME)
	motion.tween_callback(func() -> void:
		_show_gerald_walk(-direction)
	)
	motion.tween_method(_set_gerald_walk_progress, 1.0, 0.0, GERALD_WALK_TIME)
	motion.tween_callback(_end_gerald_walk)
	return true

func _sync_gerald_body_scale() -> void:
	if not is_instance_valid(gerald_art): return
	var walk := gerald_art.get_node("WalkArt") as AnimatedSprite2D
	var correction := 1.0 if walk.visible else (1.06 if gerald_art.animation in [&"attack",&"hit"] else 1.0)
	gerald_art.scale = Vector2.ONE * _base_scale * correction
	gerald_art.position.y = (-50.0 if gerald_art.animation==&"earthquake" and not walk.visible else -57.0)*gerald_art.scale.y


func play_gerald_action(ultimate: bool) -> void:
	if not is_instance_valid(gerald_art) or dead:
		return
	gerald_art.play("earthquake" if ultimate else "attack")
	gerald_art.set_frame_and_progress(0, 0.0)

func _gerald_return_idle() -> void:
	if is_instance_valid(gerald_art) and not dead and not gerald_art.get_node("WalkArt").visible:
		gerald_art.position.y = -57.0 * gerald_art.scale.y
		gerald_art.play("idle")


# Presentation mapping retains the existing boss skill IDs and combat balance.
static func fairy_clip(skill_id: String, ultimate: bool = false) -> StringName:
	if ultimate or skill_id == "spar_crystal_bloom":
		return &"crystal_bloom"
	return &"crystal_veil" if skill_id == "spar_crystal_veil" else &"crystal_bolt"

static func fairy_impact_time(skill_id: String, ultimate: bool = false) -> float:
	match fairy_clip(skill_id, ultimate):
		&"crystal_bloom": return 0.76
		&"crystal_veil": return 0.42
		_: return 0.47

func fairy_action_duration(skill_id: String, ultimate: bool = false) -> float:
	if not is_instance_valid(fairy_art):
		return 0.0
	var clip := fairy_clip(skill_id, ultimate)
	var frames := fairy_art.sprite_frames
	var duration := 0.0
	for i in range(frames.get_frame_count(clip)):
		duration += frames.get_frame_duration(clip, i)
	return duration / frames.get_animation_speed(clip)

func _play_fairy_clip(clip: StringName) -> void:
	fairy_art.flip_h = _fairy_facing_right
	fairy_art.play(clip)
	fairy_art.set_frame_and_progress(0, 0.0)

func play_fairy_action(skill_id: String = "", ultimate: bool = false) -> void:
	if not is_instance_valid(fairy_art) or dead:
		return
	cancel_attack_motion()
	cancel_recoil_motion()
	_play_fairy_clip(fairy_clip(skill_id, ultimate))

func _fairy_return_idle() -> void:
	if is_instance_valid(fairy_art) and not dead:
		fairy_art.flip_h = false
		fairy_art.play(&"right" if _fairy_facing_right else &"left")

static func cassien_clip(skill_id: String, ultimate: bool = false) -> StringName:
	if ultimate or skill_id in ["soul_drain", "cassien_crimson_requiem"]:
		return &"crimson_requiem"
	match skill_id:
		"umbral_rend", "cassien_heavy_cleave": return &"heavy_attack"
		"blood_waltz", "cassien_crimson_crescent": return &"crimson_crescent"
		_: return &"attack"

static func cassien_impact_time(skill_id: String, ultimate: bool = false) -> float:
	match cassien_clip(skill_id, ultimate):
		&"crimson_requiem": return 0.9
		&"heavy_attack": return 0.75
		&"crimson_crescent": return 0.39
		_: return 0.36

func cassien_action_duration(skill_id: String, ultimate: bool = false) -> float:
	if not is_instance_valid(cassien_art):
		return 0.0
	var clip := cassien_clip(skill_id, ultimate)
	var frames := cassien_art.sprite_frames
	var duration := 0.0
	for i in range(frames.get_frame_count(clip)):
		duration += frames.get_frame_duration(clip, i)
	return duration / frames.get_animation_speed(clip)

func play_cassien_action(skill_id: String = "", ultimate: bool = false) -> void:
	if not is_instance_valid(cassien_art) or dead:
		return
	cancel_attack_motion()
	cancel_recoil_motion()
	cassien_art.play(cassien_clip(skill_id, ultimate))
	cassien_art.set_frame_and_progress(0, 0.0)

func _cassien_return_idle() -> void:
	if is_instance_valid(cassien_art) and not dead:
		cassien_art.play(&"idle")

static func ravienna_visual_skill(skill_id: String) -> String:
	match skill_id:
		"lunar_wisp": return "corruption_bolt"
		"velvet_hex": return "shadow_lash"
		"hollow_moon_eclipse": return "ravienna_eclipse"
		"": return "corruption_bolt"
		_: return skill_id

func play_revienna_action(skill_id: String) -> bool:
	skill_id = ravienna_visual_skill(skill_id)
	if not is_instance_valid(ravienna_art) or dead:
		return false
	var sprite := ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if skill_id not in ["shadow_lash", "corruption_bolt", "soul_drain", "hollow_wail", "ravienna_eclipse"] or not sprite.sprite_frames.has_animation(skill_id):
		return false
	var pose := ravienna_art.get_node("PoseAnimation") as AnimationPlayer
	pose.stop()
	sprite.modulate = Color.WHITE
	sprite.play(skill_id)
	sprite.set_frame_and_progress(0, 0.0)
	return true


func _revienna_return_idle() -> void:
	if is_instance_valid(ravienna_art) and not dead:
		ravienna_art.get_node("AnimatedSprite2D").play("idle")


func _sync_live_facing() -> void:
	if is_instance_valid(live_art): live_art.flip_h = _live_facing_right != (str(_live_facings.get(str(live_art.animation),"right"))=="right")

func _live_return_idle() -> void:
	if is_instance_valid(live_art) and not dead: live_art.play(&"idle")

func play_live_action(skill_id: String, ultimate: bool) -> void:
	if not is_instance_valid(live_art) or dead: return
	var def := ContentDB.get_character(unit.def_id)
	var clip := &"basic_attack"
	if ultimate or (def != null and skill_id==def.ultimate): clip=&"ultimate"
	elif def != null and def.skills.size()>0 and skill_id==str(def.skills[0]): clip=&"skill_1"
	elif def != null and def.skills.size()>1 and skill_id==str(def.skills[1]): clip=&"skill_2"
	live_art.play(clip)
	live_art.set_frame_and_progress(0,0.0)

func play_attack() -> void:
	if is_instance_valid(live_art):
		play_live_action("",false)
		return
	if is_instance_valid(elathra_art):
		elathra_art.get_node("PoseAnimation").play("cast")
		return
	if is_instance_valid(ravienna_art):
		ravienna_art.get_node("PoseAnimation").play("cast")
		return
	if is_instance_valid(cassien_art):
		play_cassien_action()
		return
	if is_instance_valid(gerald_art):
		play_gerald_action(false)
		return
	if is_instance_valid(fairy_art):
		play_fairy_action()
		return
	if is_instance_valid(rose_art):
		rose_art.play("attack")
		return
	if visual == null:
		return
	if _matron_presentation != null and _matron_presentation.active:
		_matron_presentation.play_attack()
		return
	if unit != null and unit.is_boss:
		_animation_player.play("boss_attack")
		return
	visual.play_attack()


func play_victory() -> void:
	if is_instance_valid(live_art):
		_live_return_idle()
		return
	if is_instance_valid(elathra_art):
		if not dead:
			elathra_art.get_node("PoseAnimation").stop()
			elathra_art.modulate = Color.WHITE
			elathra_art.play(&"idle")
		return
	if is_instance_valid(cassien_art) or is_instance_valid(ravienna_art):
		if dead:
			return
		cancel_attack_motion()
		cancel_recoil_motion()
		if is_instance_valid(cassien_art):
			cassien_art.play(&"idle")
		else:
			ravienna_art.get_node("PoseAnimation").stop()
			var sprite := ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
			sprite.modulate = Color.WHITE
			sprite.play(&"idle")
		return
	_cancel_hit_flash()
	cancel_attack_motion()
	cancel_recoil_motion()
	_recover_combat_pose()
	if visual == null:
		return
	visual.play_victory()


func play_death() -> void:
	if is_instance_valid(live_art):
		if not dead:
			dead=true
			cancel_attack_motion()
			cancel_recoil_motion()
			live_art.play(&"defeat")
			set_intent("")
		return
	if is_instance_valid(elathra_art):
		if dead:
			return
		dead = true
		cancel_attack_motion()
		cancel_recoil_motion()
		elathra_art.stop()
		elathra_art.get_node("PoseAnimation").play("defeat")
		return
	if is_instance_valid(ravienna_art):
		if dead:
			return
		dead = true
		cancel_attack_motion()
		cancel_recoil_motion()
		modulate = Color.WHITE
		var sprite := ravienna_art.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var pose := ravienna_art.get_node("PoseAnimation") as AnimationPlayer
		pose.stop()
		sprite.modulate = Color.WHITE
		sprite.play(&"defeat")
		sprite.set_frame_and_progress(0, 0.0)
		pose.play("surrender")
		set_intent("")
		return
	if is_instance_valid(cassien_art):
		if dead:
			return
		dead = true
		cancel_attack_motion()
		cancel_recoil_motion()
		_cancel_hit_flash()
		modulate = Color.WHITE
		cassien_art.modulate = Color.WHITE
		cassien_art.play(&"defeat")
		cassien_art.set_frame_and_progress(0, 0.0)
		set_intent("")
		return
	if is_instance_valid(gerald_art):
		if dead:
			return
		dead = true
		cancel_attack_motion()
		cancel_recoil_motion()
		modulate = Color.WHITE
		gerald_art.modulate = Color.WHITE
		gerald_art.position.y = -57.0 * gerald_art.scale.y
		gerald_art.play("defeat")
		gerald_art.set_frame_and_progress(0, 0.0)
		set_intent("")
		return
	if is_instance_valid(fairy_art):
		if dead:
			return
		dead = true
		cancel_attack_motion()
		cancel_recoil_motion()
		modulate = Color.WHITE
		_play_fairy_clip(&"surrender")
		set_intent("")
		return
	if is_instance_valid(rose_art):
		dead = true
		modulate = Color.WHITE
		rose_art.play("defeat")
		return
	_cancel_hit_flash()
	cancel_attack_motion()
	cancel_recoil_motion()
	_recover_combat_pose()
	if visual == null:
		return
	dead = true
	if _matron_presentation != null and _matron_presentation.active:
		_matron_presentation.play_death()
		return
	if unit != null and unit.is_boss:
		_animation_player.play("boss_death")
		_name_label.modulate = Color(1, 1, 1, 0.0)
		return
	visual.play_defeat()
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0.0), 0.68)
	_name_label.modulate = Color(1, 1, 1, 0.0)


func _on_authored_animation_finished(animation_name: StringName) -> void:
	if unit != null and unit.is_boss and unit.def_id != "fallen_matron" and not dead and animation_name != &"boss_idle":
		_animation_player.play("boss_idle")


func _sync_ground_fx() -> void:
	if _ground_fx == null or not is_instance_valid(_ground_fx) or unit == null:
		return
	_ground_fx.update_state(_pulse, targetable, active, dead, _base_scale, _matron_presentation.get_phase())


func _on_hit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(self)

func _sync_monster_body_scale() -> void:
	if not is_instance_valid(rose_art): return
	# Crownling attack cells use a smaller standing drawing; retain its crouch
	# and crown motion using one uniform correction per authored clip.
	var correction := 1.0
	if unit.def_id == "crownling":
		if rose_art.animation==&"attack": correction=1.20
		elif rose_art.animation==&"hit": correction=1.08
	rose_art.scale=Vector2.ONE*1.4*correction
	# Keep the base center constant while adjusting the uniformly scaled cell.
	rose_art.position.y=-44.0*correction


func _rose_animation_finished() -> void:
	if dead:
		rose_art.hide()
	else:
		rose_art.play("idle")
