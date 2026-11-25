class_name MatronAttackPresentationComponent
extends Control
## Owns Fallen Matron-specific attack and phase-transition choreography.
## Visual only: CombatEngine remains authoritative for damage and turn resolution.

var battlefield: Battlefield


func bind(owner: Battlefield) -> void:
	battlefield = owner
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play_attack(boss: BattlefieldActor, target: BattlefieldActor, skill_id: String, ultimate: bool) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	_play_matron_attack(boss, target, skill_id, ultimate)


## Fallen Matron's four attacks have separate silhouettes and timing. Visual-only:
## damage and turn resolution remain owned by CombatEngine.
func _play_matron_attack(boss: BattlefieldActor, target: BattlefieldActor,
		skill_id: String, ultimate: bool) -> void:
	boss.play_attack()
	var origin := boss.home_position
	var target_pos := target.home_position if target != null and is_instance_valid(target) else origin + Vector2(-180, 0)
	# A readable danger marker appears before the Matron's attack resolves.
	if skill_id in ["corruption_bolt", "soul_drain"]:
		_spawn_matron_telegraph(boss, target_pos, 0.38 if not ultimate else 0.55)
	elif skill_id == "shadow_lash":
		for entry in battlefield._actors:
			var marked: BattlefieldActor = entry
			if marked.is_player and not marked.dead and marked.unit != null and marked.unit.is_alive():
				_spawn_matron_telegraph(boss, marked.home_position, 0.42)
	match skill_id:
		"corruption_bolt":
			var windup := create_tween()
			boss.track_attack_sequence(windup)
			windup.tween_interval(0.38)
			windup.tween_callback(func() -> void: _spawn_matron_orb(boss, origin + Vector2(-22, -78), target_pos))
		"shadow_lash":
			var windup := create_tween()
			boss.track_attack_motion(windup)
			windup.tween_property(boss, "position", origin + Vector2(0, -12), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			windup.tween_callback(func() -> void:
				for entry in battlefield._actors:
					var victim: BattlefieldActor = entry
					if victim.is_player and not victim.dead and victim.unit != null and victim.unit.is_alive():
						_spawn_shadow_lash(boss, victim.home_position))
			windup.tween_property(boss, "position", boss.home_position, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"soul_drain":
			var drain := create_tween()
			boss.track_attack_sequence(drain)
			drain.tween_interval(0.38)
			drain.tween_callback(func() -> void: _spawn_soul_drain(boss, target_pos, origin + Vector2(-20, -76)))
		"matron_verdict":
			_play_matron_verdict(boss, target_pos)
		_:
			_spawn_shadow_lash(boss, target_pos)


func _spawn_matron_telegraph(owner: BattlefieldActor, at: Vector2, duration: float) -> void:
	var marker := preload("res://scenes/ui/combat/components/ground_telegraph.tscn").instantiate() as Node2D
	marker.position = at + Vector2(0, 8)
	marker.z_index = 34
	var ring := marker.get_node("Ring") as Line2D
	ring.width = 3.0
	ring.default_color = Color(0.92, 0.24, 0.62, 0.88)
	var cross := marker.get_node("Cross") as Line2D
	cross.width = 1.5
	cross.default_color = Color(1.0, 0.62, 0.83, 0.72)
	add_child(marker)
	owner.track_attack_effect(marker)
	marker.scale = Vector2(0.45, 0.45)
	var warning_player := marker.get_node("AnimationPlayer") as AnimationPlayer
	if warning_player != null and warning_player.has_animation("warning"):
		warning_player.speed_scale = 0.7 / maxf(0.12, duration)
		warning_player.animation_finished.connect(func(_name: StringName) -> void:
			if is_instance_valid(marker):
				marker.queue_free()
		)
		warning_player.play("warning")
	else:
		marker.queue_free()


func _spawn_matron_orb(owner: BattlefieldActor, from: Vector2, to: Vector2) -> void:
	var orb := preload("res://scenes/ui/combat/components/matron_orb.tscn").instantiate() as Polygon2D
	orb.color = Color("#bd65f5")
	orb.position = from
	orb.z_index = 42
	add_child(orb)
	owner.track_attack_effect(orb)
	var player := orb.get_node("AnimationPlayer") as AnimationPlayer
	player.play("travel")
	var travel := orb.create_tween()
	travel.tween_property(orb, "position", to + Vector2(0, -22), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	travel.tween_callback(func() -> void:
		if is_instance_valid(orb):
			_spawn_matron_burst(owner, orb.position)
			orb.queue_free())
	# Once in flight, the projectile owns its travel and impact even if its caster is interrupted.
	owner.release_attack_effect(orb)


func _spawn_shadow_lash(owner: BattlefieldActor, target_pos: Vector2) -> void:
	for i in range(3):
		var lash := preload("res://scenes/ui/combat/components/shadow_lash.tscn").instantiate() as Node2D
		var start := Vector2(battlefield.size.x * 0.82, battlefield.size.y * 0.76 + float(i - 1) * 18.0)
		var endpoint := target_pos + Vector2(0, -24)
		var direction := endpoint - start
		lash.position = start
		lash.rotation = direction.angle()
		lash.scale = Vector2(direction.length() / 180.0, 1.0)
		lash.z_index = 40 + i
		var stroke := lash.get_node("Stroke") as Line2D
		stroke.width = 8.0 - float(i) * 1.5
		stroke.default_color = Color(0.34, 0.08, 0.48, 0.92 - float(i) * 0.18)
		add_child(lash)
		owner.track_attack_effect(lash)
		var lash_player := lash.get_node("AnimationPlayer") as AnimationPlayer
		lash_player.animation_finished.connect(func(_name: StringName) -> void:
			if is_instance_valid(lash):
				lash.queue_free()
		)
		lash_player.play("fade", -1, 1.0, false)
		lash_player.seek(0.08 * float(i), true)
		# The launched strike completes its authored fade after caster interruption.
		owner.release_attack_effect(lash)


func _spawn_soul_drain(owner: BattlefieldActor, from: Vector2, to: Vector2) -> void:
	var beam := preload("res://scenes/ui/combat/components/soul_drain_beam.tscn").instantiate() as Node2D
	var direction := to - from
	beam.position = from
	beam.rotation = direction.angle()
	beam.scale = Vector2(direction.length() / 160.0, 1.0)
	beam.z_index = 38
	add_child(beam)
	owner.track_attack_effect(beam)
	var beam_player := beam.get_node("AnimationPlayer") as AnimationPlayer
	beam_player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(beam):
			beam.queue_free()
	)
	beam_player.play("drain")
	# The drain beam is now playing its authored one-shot and finishes independently.
	owner.release_attack_effect(beam)
	_spawn_matron_burst(owner, to)


func _play_matron_verdict(boss: BattlefieldActor, target_pos: Vector2) -> void:
	# Stage timing remains orchestrated here; the overlay owns its visual fades.
	var overlay := preload("res://scenes/ui/combat/components/matron_verdict_overlay.tscn").instantiate() as Control
	add_child(overlay)
	# The full-screen verdict title is part of this attack, not a persistent HUD layer.
	# Register it with the boss so hit/death interruption removes it with the other FX.
	boss.track_attack_effect(overlay)
	var title := overlay.get_node("Title") as Label
	var overlay_player := overlay.get_node("AnimationPlayer") as AnimationPlayer
	overlay_player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
	)
	overlay_player.play("verdict")
	# Keep the overlay attack-owned until its animation ends so an interruption can dismiss it.
	var seal_center := boss.home_position + Vector2(0, -72)
	_spawn_verdict_seal(boss, seal_center)
	var intro := boss.create_tween()
	# Register the multi-stage timeline so hit/death interruption cancels pending stage callbacks.
	boss.track_attack_sequence(intro)
	var levitation := boss.create_tween()
	boss.track_attack_motion(levitation)
	levitation.tween_property(boss, "position:y", boss.home_position.y - 42.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	levitation.tween_interval(1.34)
	levitation.tween_property(boss, "position", boss.home_position, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_interval(0.28)
	# Stage 2 — every living ally receives a growing floor sigil and a warning.
	intro.tween_callback(func() -> void:
		for entry in battlefield._actors:
			var victim: BattlefieldActor = entry
			if victim.is_player and not victim.dead and victim.unit != null and victim.unit.is_alive():
				_spawn_ritual_rings(boss, victim.home_position + Vector2(0, 4))
				_spawn_verdict_warning(boss, victim.home_position)
	)
	intro.tween_interval(0.72)
	# Stage 3 — vertical corruption pillars strike together; this is the damage beat.
	intro.tween_callback(func() -> void:
		title.text = "BLOOM. WITHER. RETURN."
		battlefield.cinematic_impact.emit(13.0, 0.48)
		for entry in battlefield._actors:
			var victim: BattlefieldActor = entry
			if victim.is_player and not victim.dead and victim.unit != null and victim.unit.is_alive():
				_spawn_verdict_column(boss, victim.home_position)
				_spawn_matron_burst(boss, victim.home_position + Vector2(0, -30))
				_spawn_matron_burst(boss, victim.home_position + Vector2(-28, -12))
				_spawn_matron_burst(boss, victim.home_position + Vector2(28, -12))
	)
	intro.tween_interval(0.84)

func _spawn_verdict_seal(owner: BattlefieldActor, center: Vector2) -> void:
	var seal := preload("res://scenes/ui/combat/components/matron_verdict_seal.tscn").instantiate() as Node2D
	seal.position = center
	seal.z_index = 24
	# Ring and spoke paths are authored in the reusable seal scene.
	# Runtime only applies placement; geometry and line styling stay editor-owned.
	add_child(seal)
	owner.track_attack_effect(seal)
	var seal_player := seal.get_node("AnimationPlayer") as AnimationPlayer
	seal_player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(seal):
			seal.queue_free()
	)
	seal_player.play("seal")
	owner.release_attack_effect(seal)


func _spawn_verdict_warning(owner: BattlefieldActor, center: Vector2) -> void:
	# Reuse the same authored warning rig as ordinary Matron telegraphs.
	# Only its palette, footprint and timing differ for the arena-wide verdict.
	var warning := preload("res://scenes/ui/combat/components/ground_telegraph.tscn").instantiate() as Node2D
	warning.position = center + Vector2(0, 8)
	warning.z_index = 37
	var ring := warning.get_node("Ring") as Line2D
	ring.width = 4.0
	ring.default_color = Color("#ff5ac8")
	var cross := warning.get_node("Cross") as Line2D
	cross.width = 2.0
	cross.default_color = Color(1.0, 0.72, 0.92, 0.9)
	add_child(warning)
	owner.track_attack_effect(warning)
	var player := warning.get_node("AnimationPlayer") as AnimationPlayer
	player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(warning):
			warning.queue_free()
	)
	player.play("verdict_warning")
	owner.release_attack_effect(warning)

func _spawn_verdict_column(owner: BattlefieldActor, center: Vector2) -> void:
	var column := preload("res://scenes/ui/combat/components/verdict_column.tscn").instantiate() as Polygon2D
	column.name = "MatronVerdictColumn"
	column.position = center + Vector2(0, -185)
	column.z_index = 43
	add_child(column)
	owner.track_attack_effect(column)
	var player := column.get_node("AnimationPlayer") as AnimationPlayer
	player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(column):
			column.queue_free()
	)
	player.play("strike")
	owner.release_attack_effect(column)

func _spawn_ritual_rings(owner: BattlefieldActor, center: Vector2) -> void:
	for ring_index in range(3):
		var ring := preload("res://scenes/ui/combat/components/matron_ritual_ring.tscn").instantiate() as Line2D
		ring.position = center
		var radius := 18.0 + float(ring_index) * 15.0
		ring.scale = Vector2.ONE * (radius / 18.0)
		ring.width = 3.0 - float(ring_index) * 0.5
		ring.default_color = Color(0.78, 0.34, 0.98, 0.85 - float(ring_index) * 0.18)
		ring.z_index = 36 + ring_index
		add_child(ring)
		owner.track_attack_effect(ring)
		var player := ring.get_node("AnimationPlayer") as AnimationPlayer
		player.animation_finished.connect(func(_name: StringName) -> void:
			if is_instance_valid(ring):
				ring.queue_free()
		)
		player.play("ritual")
		owner.release_attack_effect(ring)


func _spawn_matron_burst(owner: BattlefieldActor, pos: Vector2) -> void:
	var particles := preload("res://scenes/ui/combat/components/matron_burst.tscn").instantiate() as CPUParticles2D
	particles.z_index = 44
	particles.position = pos
	add_child(particles)
	owner.track_attack_effect(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true
	owner.release_attack_effect(particles)


## Phase transition flourish for the Fallen Matron: a visible corruption surge.
func play_matron_phase(phase_number: int) -> void:
	var boss: BattlefieldActor = null
	for entry in battlefield._actors:
		var candidate: BattlefieldActor = entry
		if candidate.unit != null and candidate.unit.def_id == "fallen_matron":
			boss = candidate
			break
	if boss == null:
		return
	var center := boss.home_position + Vector2(0, -48)
	_spawn_matron_burst(boss, center)
	_spawn_matron_burst(boss, center + Vector2(-42, 12))
	_spawn_matron_burst(boss, center + Vector2(42, 12))
	_spawn_ritual_rings(boss, boss.home_position)
	var aura := preload("res://scenes/ui/combat/components/effect_glow_light.tscn").instantiate() as PointLight2D
	aura.color = Color("#a23fe0") if phase_number <= 2 else Color("#d34cff")
	aura.texture_scale = 2.4
	aura.position = Vector2(0, -50)
	boss.add_child(aura)
	boss.track_attack_effect(aura)
	var aura_player := aura.get_node("AnimationPlayer") as AnimationPlayer
	aura_player.animation_finished.connect(func(_name: StringName) -> void:
		if is_instance_valid(aura):
			aura.queue_free()
	)
	aura_player.play("pulse")
	boss.release_attack_effect(aura)
