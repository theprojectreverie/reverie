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


var rose_art: AnimatedSprite2D
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
	visual.visual_scale = _base_scale
	if unit.def_id == "fairy_spar":
		var spar_art := visual.get_node("FairySparArt") as AnimatedSprite2D
		spar_art.reparent(self, false)
		spar_art.show()
		visual.hide()
	if unit.is_boss and unit.def_id != "fallen_matron":
		_animation_player.play("boss_idle")
	var element_color := UITheme.element_color(unit.element)
	if element_color == UITheme.TEXT_DIM:
		element_color = Color("#c6cad6")
	_ground_fx.configure(is_player, unit.is_boss, unit.def_id == "fallen_matron", element_color)
	_sync_ground_fx()
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
	if not unit.is_alive() and not is_instance_valid(rose_art):
		modulate = Color(1, 1, 1, 0.38)
	queue_redraw()


func set_intent(skill_name: String) -> void:
	if _intent_label == null:
		return
	_intent_label.visible = not skill_name.is_empty() and not is_player and not dead
	_intent_label.text = "!  %s" % skill_name.to_upper() if _intent_label.visible else ""
	_intent_label.position = Vector2(-78, -124 if unit != null and unit.is_boss else -104)
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
	_pulse += delta
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


func _recover_combat_pose() -> void:
	var battle_player := get_node_or_null("BattlePoseAnimationPlayer") as AnimationPlayer
	if battle_player != null and battle_player.has_animation("battle_recover"):
		battle_player.play("battle_recover")
	var kael_player := get_node_or_null("KaelAnimationPlayer") as AnimationPlayer
	if kael_player != null and kael_player.has_animation("kael_recover"):
		kael_player.play("kael_recover")

## Damage reaction: white flash + a short shake + the damage animation.
func take_hit() -> void:
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
func play_attack() -> void:
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
	_cancel_hit_flash()
	cancel_attack_motion()
	cancel_recoil_motion()
	_recover_combat_pose()
	if visual == null:
		return
	visual.play_victory()


func play_death() -> void:
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

func _rose_animation_finished() -> void:
	if dead:
		rose_art.hide()
	else:
		rose_art.play("idle")
