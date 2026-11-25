
class_name KaelAttackPresentationComponent
extends Control
## Owns Kael-specific attack choreography and transient visual effects.
## CombatEngine remains authoritative for all damage and turn resolution.

var battlefield: Battlefield

func bind(owner: Battlefield) -> void:
	battlefield = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
## Kael's moves each have a separate visual rhythm. All damage remains
## authoritative in CombatEngine; this choreography never applies gameplay hits.
func play_attack(attacker: BattlefieldActor, target: BattlefieldActor,
		skill_id: String, ultimate: bool) -> void:
	var origin := attacker.home_position
	var has_target := target != null and is_instance_valid(target)
	var direction := (target.home_position - origin).normalized() if has_target else Vector2.RIGHT
	attacker.face(direction)
	var target_home := target.home_position if has_target else origin + direction * 150.0
	var impact := target_home + Vector2(0, -34.0)
	var fire := Color("#ff563f")
	var gold := Color("#ffc16a")
	var pale := Color("#fff0d0")

	if skill_id == "rally_cry":
		# Plant the feet, draw the blade across the chest, then release a team-wide oath.
		attacker.visual.play_cast()
		_play_kael_pose(attacker, "kael_cast")
		var rally := create_tween()
		attacker.track_attack_motion(rally)
		rally.tween_callback(func() -> void:
			_spawn_kael_rally_ring(attacker, attacker.position, fire, gold)
			for entry in battlefield._actors:
				var ally: BattlefieldActor = entry
				if ally.is_player and not ally.dead:
					_spawn_kael_aura(attacker, ally)
		)
		return

	if skill_id == "ember_lance":
		# A compressed ember condenses at the sword hand, then pierces the arena.
		attacker.visual.play_cast()
		_play_kael_pose(attacker, "kael_cast")
		var cast := create_tween()
		attacker.track_attack_motion(cast)
		cast.tween_callback(func() -> void:
			_spawn_kael_lance(attacker, origin + Vector2(14, -58), impact, fire, gold, pale)
		)
		return

	if skill_id == "blazing_charge" or ultimate:
		# Ultimate: hold the arena for a heartbeat, then cross it in a blazing
		# three-beat cut. The final detonation is intentionally the largest beat.
		attacker.visual.play_cast()
		_play_kael_pose(attacker, "kael_ultimate")
		var ultimate_tween := create_tween()
		attacker.track_attack_motion(ultimate_tween)
		ultimate_tween.tween_callback(func() -> void:
			_spawn_kael_ground_seal(attacker, origin, fire, gold)
			battlefield.cinematic_impact.emit(0.22, 0.18)
		)
		ultimate_tween.tween_interval(0.16)
		var dash_end := target_home - direction * (105.0 if has_target and target.unit != null and target.unit.is_boss else 58.0)
		ultimate_tween.tween_property(attacker, "position", dash_end, 0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		ultimate_tween.tween_callback(func() -> void:
			for beat in 3:
				var offset := Vector2(0, -52.0 - float(beat) * 12.0)
				_spawn_kael_cross_slash(attacker, impact + offset, direction, fire if beat != 2 else pale, 1.0 + float(beat) * 0.24)
			_spawn_kael_impact(attacker, impact, fire, gold, 1.0)
			battlefield.cinematic_impact.emit(0.72, 0.30)
		)
		ultimate_tween.tween_interval(0.14)
		ultimate_tween.tween_callback(func() -> void:
			_spawn_kael_ultimate_burst(attacker, impact, fire, gold, pale)
			battlefield.cinematic_impact.emit(1.0, 0.48)
			if has_target and is_instance_valid(target):
				var recoil := create_tween()
				target.track_recoil_motion(recoil)
				recoil.tween_property(target, "position", target_home + direction * 30.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				recoil.tween_property(target, "position", target_home, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		)
		ultimate_tween.tween_property(attacker, "position", attacker.home_position, 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		return

	# Basic attack: a three-beat combo with varied arc, hit-stop and recovery.
	var reach := target_home - direction * (112.0 if has_target and target.unit != null and target.unit.is_boss else 52.0)
	attacker.visual.play_attack()
	_play_kael_pose(attacker, "kael_basic")
	var combo := create_tween()
	attacker.track_attack_motion(combo)
	combo.tween_property(attacker, "position", origin - direction * 15.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	combo.tween_property(attacker, "position", reach, 0.20).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	combo.tween_callback(func() -> void:
		if has_target and is_instance_valid(target):
			_spawn_kael_cross_slash(attacker, impact + Vector2(0, -8), direction, gold, 0.86)
			_spawn_kael_impact(attacker, impact, fire, gold, 0.46)
	)
	combo.tween_interval(0.07)
	combo.tween_callback(func() -> void:
		if has_target and is_instance_valid(target):
			_spawn_kael_cross_slash(attacker, impact + Vector2(4, 4), direction.rotated(0.42), fire, 1.0)
			_spawn_kael_impact(attacker, impact + Vector2(5, 0), fire, gold, 0.56)
	)
	combo.tween_interval(0.06)
	combo.tween_callback(func() -> void:
		if has_target and is_instance_valid(target):
			_spawn_kael_cross_slash(attacker, impact + Vector2(-4, -4), direction.rotated(-0.48), pale, 1.14)
			_spawn_kael_impact(attacker, impact, fire, gold, 0.72)
			var knock := create_tween()
			target.track_recoil_motion(knock)
			knock.tween_property(target, "position", target_home + direction * 22.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			knock.tween_property(target, "position", target_home, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	combo.tween_property(attacker, "position", attacker.home_position, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_kael_pose(attacker: BattlefieldActor, animation_name: String) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var player := attacker.get_node_or_null("KaelAnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(animation_name):
		push_warning("Kael actor is missing authored combat animation: " + animation_name)
		return
	player.play(animation_name)


func _spawn_kael_cross_slash(owner: BattlefieldActor, center: Vector2, direction: Vector2, color: Color, strength: float) -> void:
	var slash := preload("res://scenes/ui/combat/components/kael_cross_slash.tscn").instantiate() as Line2D
	slash.width = 10.0 * strength
	slash.default_color = Color(color.r, color.g, color.b, 0.94)
	slash.position = center
	slash.rotation = direction.angle()
	slash.z_index = 42
	add_child(slash)
	owner.track_attack_effect(slash)
	var player := slash.get_node("AnimationPlayer") as AnimationPlayer
	player.animation_finished.connect(func(animation_name: StringName) -> void:
		if animation_name == &"slash" and is_instance_valid(slash):
			slash.queue_free()
	)
	player.play("slash")
	owner.release_attack_effect(slash)


func _spawn_kael_impact(owner: BattlefieldActor, pos: Vector2, fire: Color, gold: Color, strength: float) -> void:
	var flash := preload("res://scenes/ui/combat/components/kael_impact_flash.tscn").instantiate() as Polygon2D
	flash.scale = Vector2.ONE * strength
	flash.color = Color(gold.r, gold.g, gold.b, 0.86)
	flash.position = pos
	flash.z_index = 48
	add_child(flash)
	owner.track_attack_effect(flash)
	var player := flash.get_node("AnimationPlayer") as AnimationPlayer
	player.animation_finished.connect(func(animation_name: StringName) -> void:
		if animation_name == &"flash" and is_instance_valid(flash):
			flash.queue_free()
	)
	player.play("flash")
	owner.release_attack_effect(flash)
	battlefield.spawn_attack_elemental_burst(owner, pos, "fire")


func _spawn_kael_lance(owner: BattlefieldActor, from: Vector2, to: Vector2, fire: Color, gold: Color, pale: Color) -> void:
	var spear := preload("res://scenes/ui/combat/components/kael_lance.tscn").instantiate() as Node2D
	spear.position = from
	spear.z_index = 50
	(spear.get_node("Shaft") as Line2D).default_color = fire
	(spear.get_node("Core") as Line2D).default_color = pale
	(spear.get_node("Glow") as PointLight2D).color = fire
	add_child(spear)
	owner.track_attack_effect(spear)
	var delta := to - from
	spear.rotation = delta.angle()
	var travel := spear.create_tween()
	travel.tween_property(spear, "position", to, 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	travel.parallel().tween_property(spear, "scale", Vector2(1.25, 0.8), 0.34)
	travel.tween_callback(func() -> void:
		_spawn_kael_impact(owner, to, fire, gold, 0.82)
		spear.queue_free()
	)
	owner.release_attack_effect(spear)


func _spawn_kael_rally_ring(owner: BattlefieldActor, center: Vector2, fire: Color, gold: Color) -> void:
	for ring_index in 3:
		var ring := preload("res://scenes/ui/combat/components/magic_effect_line.tscn").instantiate() as Line2D
		ring.width = 2.0 if ring_index == 0 else 1.2
		ring.default_color = Color(gold.r, gold.g, gold.b, 0.78 - float(ring_index) * 0.16)
		var radius := 24.0 + float(ring_index) * 12.0
		ring.scale = Vector2.ONE * radius
		ring.position = center + Vector2(0, 8)
		ring.z_index = 24
		add_child(ring)
		owner.track_attack_effect(ring)
		var tween := ring.create_tween()
		tween.tween_property(ring, "scale", Vector2.ONE * radius * 2.6, 0.48 + float(ring_index) * 0.08)
		tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.48 + float(ring_index) * 0.08)
		tween.tween_callback(ring.queue_free)
		owner.release_attack_effect(ring)
	battlefield.spawn_attack_elemental_burst(owner, center + Vector2(0, -32), "fire")


func _spawn_kael_aura(owner: BattlefieldActor, ally: BattlefieldActor) -> void:
	var aura := preload("res://scenes/ui/combat/components/kael_rally_aura.tscn").instantiate() as PointLight2D
	aura.color = Color("#ff9b50")
	ally.add_child(aura)
	owner.track_attack_effect(aura)
	var tween := aura.create_tween()
	tween.tween_property(aura, "energy", 1.15, 0.22)
	tween.tween_property(aura, "energy", 0.0, 1.0)
	tween.tween_callback(aura.queue_free)
	owner.release_attack_effect(aura)


func _spawn_kael_ground_seal(owner: BattlefieldActor, center: Vector2, fire: Color, gold: Color) -> void:
	for ring_index in 3:
		var ring := preload("res://scenes/ui/combat/components/magic_effect_line.tscn").instantiate() as Line2D
		ring.width = 2.6 - float(ring_index) * 0.55
		ring.default_color = Color(fire.r, fire.g, fire.b, 0.78 - float(ring_index) * 0.16)
		var radius := 20.0 + float(ring_index) * 13.0
		ring.scale = Vector2.ONE * radius
		ring.position = center + Vector2(0, 8)
		ring.z_index = 28
		add_child(ring)
		owner.track_attack_effect(ring)
		var tween := ring.create_tween()
		tween.tween_property(ring, "rotation", TAU * (1.0 if ring_index % 2 == 0 else -1.0), 0.9)
		tween.parallel().tween_property(ring, "scale", Vector2.ONE * radius * 2.3, 0.9)
		tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.9)
		tween.tween_callback(ring.queue_free)
		owner.release_attack_effect(ring)
	battlefield.spawn_attack_elemental_burst(owner, center, "fire")


func _spawn_kael_ultimate_burst(owner: BattlefieldActor, center: Vector2, fire: Color, gold: Color, pale: Color) -> void:
	var bloom := preload("res://scenes/ui/combat/components/effect_glow_light.tscn").instantiate() as PointLight2D
	bloom.color = fire
	bloom.texture_scale = 0.3
	bloom.position = center
	bloom.z_index = 54
	add_child(bloom)
	owner.track_attack_effect(bloom)
	var light := bloom.create_tween()
	light.tween_property(bloom, "energy", 3.4, 0.12)
	light.tween_property(bloom, "energy", 0.0, 0.62)
	light.tween_callback(bloom.queue_free)
	owner.release_attack_effect(bloom)
	var burst := preload("res://scenes/ui/combat/components/kael_ultimate_particles.tscn").instantiate() as CPUParticles2D
	burst.color = gold
	burst.position = center
	burst.z_index = 52
	add_child(burst)
	owner.track_attack_effect(burst)
	burst.finished.connect(burst.queue_free)
	burst.emitting = true
	owner.release_attack_effect(burst)
	_spawn_kael_cross_slash(owner, center, Vector2.RIGHT, pale, 2.1)
	_spawn_kael_cross_slash(owner, center, Vector2.RIGHT.rotated(PI * 0.5), fire, 1.8)
	var ring := preload("res://scenes/ui/combat/components/magic_effect_line.tscn").instantiate() as Line2D
	ring.width = 5.0
	ring.default_color = Color(fire.r, fire.g, fire.b, 0.9)
	ring.scale = Vector2.ONE * 42.0
	ring.position = center
	ring.z_index = 50
	add_child(ring)
	owner.track_attack_effect(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_property(ring, "scale", Vector2.ONE * 42.0 * 2.8, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.42)
	ring_tween.tween_callback(ring.queue_free)
	owner.release_attack_effect(ring)
