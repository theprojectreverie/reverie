extends CharacterBody2D

signal card_released(origin: Vector2, direction: Vector2)
signal ultimate_wave_impact(target: Vector2, wave: int)
signal royal_impact(target: Vector2)
const SPEED := 145.0
const RUN_SPEED := 235.0
var facing := "s"
var attacking := false
var ultimate_active := false
var royal_active := false
var royal_key_was_down := false
var royal_released := false
var royal_target := Vector2.ZERO
var royal_fx: Node2D
var royal_tween: Tween
const ROYAL_FAN = preload("res://assets/characters/harlequin/preview/royal_fan.png")
const ROYAL_SPIN = preload("res://assets/characters/harlequin/preview/royal_spin.png")
const ROYAL_STREAK = preload("res://assets/characters/harlequin/preview/royal_streak.png")
const ROYAL_IMPACT = preload("res://assets/characters/harlequin/preview/royal_impact.png")
var ultimate_key_was_down := false
var ultimate_target := Vector2.ZERO
var ultimate_fx: Node2D
var ultimate_gathered := false
var ultimate_raining := false
var ultimate_tweens: Array[Tween] = []
const GATHER = preload("res://assets/characters/harlequin/preview/ultimate_gather.png")
const FAN = preload("res://assets/characters/harlequin/preview/ultimate_fan.png")
const RAIN = preload("res://assets/characters/harlequin/preview/ultimate_rain.png")
const IMPACT = preload("res://assets/characters/harlequin/preview/ultimate_impact.png")
const CARD = preload("res://assets/characters/harlequin/preview/card_projectile.png")
var reacting := false
var defeated := false
var hit_key_was_down := false
var defeat_key_was_down := false
var reset_key_was_down := false
var combat_mode := false
var combat_key_was_down := false
var combat_direction := -1.0
var attack_direction := -1.0
var released := false
var attack_key_was_down := false
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	if not InputMap.has_action("harlequin_preview_sprint"):
		InputMap.add_action("harlequin_preview_sprint")
	sprite.frame_changed.connect(_on_attack_frame)
	sprite.frame_changed.connect(_on_ultimate_frame)
	sprite.frame_changed.connect(_on_royal_frame)
	sprite.animation_finished.connect(_on_attack_finished)
	sprite.play("idle_s")

func set_combat_mode(enabled: bool, direction: float = -1.0) -> void:
	if attacking or reacting or defeated or ultimate_active or royal_active:
		return
	combat_mode = enabled
	combat_direction = -1.0 if direction < 0.0 else 1.0
	velocity = Vector2.ZERO
	_play_ready()

func _play_ready() -> void:
	sprite.speed_scale = 1.0
	sprite.flip_h = combat_mode and combat_direction > 0.0
	sprite.play("combat_idle" if combat_mode else "idle_" + facing)

func start_attack(direction: float) -> void:
	if attacking or reacting or defeated or ultimate_active or royal_active:
		return
	attack_direction = -1.0 if direction < 0.0 else 1.0
	attacking = true
	combat_direction = attack_direction
	released = false
	velocity = Vector2.ZERO
	sprite.flip_h = attack_direction > 0.0
	sprite.speed_scale = 1.0
	sprite.play("attack_card")
	sprite.set_frame_and_progress(0, 0.0)

func _on_attack_frame() -> void:
	if not attacking or released or sprite.animation != &"attack_card" or sprite.frame < 3:
		return
	released = true
	var origin := global_position + Vector2(attack_direction * 39.0, -88.0)
	var direction := Vector2(attack_direction, 0.0)
	card_released.emit(origin, direction)
	var card := Sprite2D.new()
	card.texture = preload("res://assets/characters/harlequin/preview/card_projectile.png")
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.flip_h = attack_direction > 0.0
	get_parent().add_child(card)
	card.global_position = origin
	var tween := card.create_tween()
	tween.tween_property(card, "global_position", origin + direction * 220.0, 0.35)
	tween.tween_callback(card.queue_free)

func start_ultimate(direction: float, target: Vector2 = Vector2.INF) -> void:
	if attacking or reacting or defeated or ultimate_active or royal_active:
		return
	combat_mode = true
	combat_direction = -1.0 if direction < 0.0 else 1.0
	ultimate_target = global_position + Vector2(combat_direction * 220.0, -64.0) if target == Vector2.INF else target
	ultimate_active = true
	ultimate_gathered = false
	ultimate_raining = false
	attacking = true
	velocity = Vector2.ZERO
	sprite.flip_h = combat_direction > 0.0
	ultimate_fx = Node2D.new()
	ultimate_fx.name = "CardRainEffects"
	get_parent().add_child(ultimate_fx)
	sprite.speed_scale = 1.0
	sprite.play("ultimate_cast")
	sprite.set_frame_and_progress(0, 0.0)

func _fx_sprite(texture: Texture2D, pos: Vector2, factor: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.texture = texture
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.scale = Vector2.ONE * factor
	fx.z_index = 8
	ultimate_fx.add_child(fx)
	fx.global_position = pos
	return fx

func _fx_tween(node: Node) -> Tween:
	var t := node.create_tween()
	ultimate_tweens.append(t)
	return t

func _on_ultimate_frame() -> void:
	if not ultimate_active or sprite.animation != &"ultimate_cast":
		return
	if sprite.frame >= 5 and not ultimate_gathered:
		ultimate_gathered = true
		var gather := _fx_sprite(GATHER, ultimate_target + Vector2(0, -160), 0.45)
		var t := _fx_tween(gather)
		t.tween_property(gather, "scale", Vector2.ONE * 0.7, 0.26)
		t.tween_callback(gather.queue_free)
		var fan := _fx_sprite(FAN, ultimate_target + Vector2(0, -155), 0.7)
		fan.modulate.a = 0.0
		var ft := _fx_tween(fan)
		ft.tween_property(fan, "modulate:a", 1.0, 0.3)
		ft.tween_interval(0.24)
		ft.tween_property(fan, "modulate:a", 0.0, 0.22)
		ft.tween_callback(fan.queue_free)
	if sprite.frame >= 8 and not ultimate_raining:
		ultimate_raining = true
		for wave in range(3):
			var timer := _fx_tween(ultimate_fx)
			timer.tween_interval(0.22 * wave)
			timer.tween_callback(_rain_wave.bind(wave))
		var end := _fx_tween(ultimate_fx)
		end.tween_interval(1.25)
		end.tween_callback(_finish_ultimate_fx)

func _rain_wave(wave: int) -> void:
	if not ultimate_active or not is_instance_valid(ultimate_fx):
		return
	var streak := _fx_sprite(RAIN, ultimate_target + Vector2(0, -105), 0.65)
	var st := _fx_tween(streak)
	st.tween_property(streak, "global_position", ultimate_target + Vector2(0, -12), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_callback(streak.queue_free)
	for i in range(8):
		var offset := float(i) * 9.0 - 31.5
		var landing := ultimate_target + Vector2(offset, float((i + wave) % 3) * 6.0)
		var card := _fx_sprite(CARD, landing + Vector2(float((i * 13 + wave * 7) % 33) - 16.0, -170.0 - float(i % 3) * 15.0), 1.0)
		card.rotation = PI / 2.0 + float(i % 3 - 1) * 0.23
		card.modulate.a = 0.0
		var t := _fx_tween(card)
		t.tween_interval(float(i) * 0.018)
		t.tween_callback(func(): card.modulate.a = 1.0)
		t.tween_property(card, "global_position", landing, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(card.queue_free)
	var impact_timer := _fx_tween(ultimate_fx)
	impact_timer.tween_interval(0.46)
	impact_timer.tween_callback(_rain_impact.bind(wave))

func _rain_impact(wave: int) -> void:
	if not ultimate_active or not is_instance_valid(ultimate_fx):
		return
	var burst := _fx_sprite(IMPACT, ultimate_target, 0.45)
	var t := _fx_tween(burst)
	t.tween_property(burst, "scale", Vector2.ONE * 0.8, 0.12)
	t.tween_property(burst, "modulate:a", 0.0, 0.16)
	t.tween_callback(burst.queue_free)
	ultimate_wave_impact.emit(ultimate_target, wave)

func _finish_ultimate_fx() -> void:
	ultimate_active = false
	if is_instance_valid(ultimate_fx):
		ultimate_fx.queue_free()
	ultimate_fx = null
	ultimate_tweens.clear()

func _cancel_ultimate() -> void:
	for t in ultimate_tweens:
		if t.is_valid():
			t.kill()
	_finish_ultimate_fx()

func start_royal(direction: float, target: Vector2 = Vector2.INF) -> void:
	if attacking or reacting or defeated or ultimate_active or royal_active:
		return
	combat_mode = true
	combat_direction = -1.0 if direction < 0.0 else 1.0
	royal_target = global_position + Vector2(combat_direction * 220.0, -75.0) if target == Vector2.INF else target
	royal_active = true
	royal_released = false
	attacking = true
	velocity = Vector2.ZERO
	sprite.flip_h = combat_direction > 0.0
	royal_fx = Node2D.new()
	royal_fx.name = "RoyalFlushEffects"
	get_parent().add_child(royal_fx)
	sprite.speed_scale = 1.0
	sprite.play("royal_cast")
	sprite.set_frame_and_progress(0, 0.0)

func _royal_sprite(texture: Texture2D, pos: Vector2, factor: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.texture = texture
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.scale = Vector2.ONE * factor
	fx.z_index = 8
	royal_fx.add_child(fx)
	fx.global_position = pos
	return fx

func _on_royal_frame() -> void:
	if not royal_active or royal_released or sprite.animation != &"royal_cast" or sprite.frame < 3:
		return
	royal_released = true
	var origin := global_position + Vector2(combat_direction * 39.0, -88.0)
	var projectile := _royal_sprite(ROYAL_FAN, origin, 0.36)
	projectile.flip_h = combat_direction > 0.0
	royal_tween = royal_fx.create_tween()
	royal_tween.tween_callback(func(): projectile.texture = ROYAL_SPIN)
	royal_tween.tween_property(projectile, "global_position", origin.lerp(royal_target, 0.35), 0.10)
	royal_tween.tween_callback(func(): projectile.texture = ROYAL_STREAK)
	royal_tween.tween_property(projectile, "global_position", royal_target, 0.23).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	royal_tween.tween_callback(projectile.queue_free)
	royal_tween.tween_callback(_royal_hit)
	royal_tween.tween_interval(0.24)
	royal_tween.tween_callback(_finish_royal)

func _royal_hit() -> void:
	if not royal_active:
		return
	_royal_sprite(ROYAL_IMPACT, royal_target, 0.65)
	royal_impact.emit(royal_target)

func _finish_royal() -> void:
	royal_active = false
	if is_instance_valid(royal_fx):
		royal_fx.queue_free()
	royal_fx = null

func _cancel_royal() -> void:
	if royal_tween != null and royal_tween.is_valid():
		royal_tween.kill()
	_finish_royal()

func play_hit() -> void:
	if defeated or reacting:
		return
	_cancel_ultimate()
	_cancel_royal()
	attacking = false
	reacting = true
	combat_mode = true
	velocity = Vector2.ZERO
	sprite.flip_h = combat_direction > 0.0
	sprite.speed_scale = 1.0
	sprite.play("hit")
	sprite.set_frame_and_progress(0, 0.0)

func play_defeat() -> void:
	if defeated:
		return
	_cancel_ultimate()
	_cancel_royal()
	attacking = false
	reacting = false
	defeated = true
	combat_mode = true
	velocity = Vector2.ZERO
	sprite.flip_h = combat_direction > 0.0
	sprite.speed_scale = 1.0
	sprite.play("defeat")
	sprite.set_frame_and_progress(0, 0.0)

func reset_defeat() -> void:
	_cancel_ultimate()
	_cancel_royal()
	defeated = false
	reacting = false
	attacking = false
	_play_ready()

func _on_attack_finished() -> void:
	if sprite.animation == &"ultimate_cast" or sprite.animation == &"royal_cast":
		attacking = false
		_play_ready()
		return
	if sprite.animation == &"defeat":
		return
	if sprite.animation == &"hit" and reacting:
		reacting = false
		_play_ready()
		return
	if not attacking or sprite.animation != &"attack_card":
		return
	attacking = false
	_play_ready()

func _physics_process(_delta: float) -> void:
	var hit_pressed := Input.is_physical_key_pressed(KEY_H)
	var defeat_pressed := Input.is_physical_key_pressed(KEY_K)
	var reset_pressed := Input.is_physical_key_pressed(KEY_R)
	if reset_pressed and not reset_key_was_down:
		reset_defeat()
	if defeat_pressed and not defeat_key_was_down:
		play_defeat()
	elif hit_pressed and not hit_key_was_down:
		play_hit()
	hit_key_was_down = hit_pressed
	defeat_key_was_down = defeat_pressed
	reset_key_was_down = reset_pressed
	if defeated or reacting:
		return
	var combat_pressed := Input.is_physical_key_pressed(KEY_C)
	if combat_pressed and not combat_key_was_down and not attacking:
		set_combat_mode(not combat_mode, 1.0 if facing in ["e", "se", "ne"] else -1.0)
	combat_key_was_down = combat_pressed
	if combat_mode and not attacking:
		var horizontal := Input.get_axis("ui_left", "ui_right")
		if Input.is_physical_key_pressed(KEY_A):
			horizontal = -1.0
		elif Input.is_physical_key_pressed(KEY_D):
			horizontal = 1.0
		if horizontal != 0.0:
			combat_direction = signf(horizontal)
			sprite.flip_h = combat_direction > 0.0
	var royal_pressed := Input.is_physical_key_pressed(KEY_J)
	if royal_pressed and not royal_key_was_down:
		start_royal(combat_direction if combat_mode else (1.0 if facing in ["e", "se", "ne"] else -1.0))
	royal_key_was_down = royal_pressed
	var ultimate_pressed := Input.is_physical_key_pressed(KEY_U)
	if ultimate_pressed and not ultimate_key_was_down:
		start_ultimate(combat_direction if combat_mode else (1.0 if facing in ["e", "se", "ne"] else -1.0))
	ultimate_key_was_down = ultimate_pressed
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not attack_key_was_down and not attacking:
		start_attack(combat_direction if combat_mode else (1.0 if facing in ["e", "se", "ne"] else -1.0))
	attack_key_was_down = pressed
	if attacking or combat_mode:
		return
	var v := Vector2.ZERO
	v.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	v.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	if v == Vector2.ZERO:
		v = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if v != Vector2.ZERO:
		var names := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
		facing = names[posmod(roundi(v.angle() / (PI / 4.0)), 8)]
	var sprint := v != Vector2.ZERO and (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_action_pressed("harlequin_preview_sprint"))
	velocity = v.normalized() * (RUN_SPEED if sprint else SPEED)
	move_and_slide()
	position = position.clamp(Vector2(64, 140), get_viewport_rect().size - Vector2(64, 12))
	var next := ("walk_" if v != Vector2.ZERO else "idle_") + facing
	if sprint and sprite.sprite_frames.has_animation("run_" + facing):
		next = "run_" + facing
	sprite.speed_scale = 1.3 if sprint and next.begins_with("walk_") else 1.0
	if sprite.animation != next:
		sprite.play(next)

