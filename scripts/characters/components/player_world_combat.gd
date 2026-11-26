extends Node
## First real-time combat prototype; only explicitly supported world targets.
@export var attack_range := 80.0
@export var attack_damage := 25.0
@export var attack_cooldown := 0.55
var cooldown := 0.0
var attack_pending := false
var attack_facing := Vector2.DOWN
var attack_avatar := ""
var dodge_time := 0.0
var dodge_recovery := 0.0
var dodge_direction := Vector2.ZERO
var skill_cooldown := 0.0
@export var max_hp := 100.0
var hp := 100.0
var hurt_cooldown := 0.0
@onready var player: Player = get_parent()
func _physics_process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	dodge_time = maxf(0.0, dodge_time - delta)
	dodge_recovery = maxf(0.0, dodge_recovery - delta)
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	if attack_pending:
		if not player.input_enabled or player.network_recovery_paused or player.avatar_id != attack_avatar or player.visual.animator.state != 4:
			attack_pending = false
		elif player.visual.animator.frame >= 3:
			attack_pending = false
			_resolve_attack()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_attack") and not event.is_echo():
		if try_attack():
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("world_dodge") and not event.is_echo() and try_dodge():
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("world_skill") and not event.is_echo() and try_skill():
		get_viewport().set_input_as_handled()

func try_dodge() -> bool:
	if not player.input_enabled or player.network_recovery_paused or dodge_recovery > 0.0 or attack_pending:
		return false
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if TouchInput.move_vector.length_squared() > 0.01:
		direction = TouchInput.move_vector
	dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else player.facing_direction.normalized()
	dodge_time = 0.22
	dodge_recovery = 1.1
	return true

func try_skill() -> bool:
	if not MultiplayerGateway.standalone_expedition_id.is_empty():
		return false # Only server-validated basic attacks are enabled in this co-op prototype.
	if not player.input_enabled or player.network_recovery_paused or skill_cooldown > 0.0 or dodge_time > 0.0 or attack_pending:
		return false
	skill_cooldown = 4.0
	player.presentation_component.play_cast()
	for target in get_tree().get_nodes_in_group("world_action_targets"):
		if is_instance_valid(target) and not target.get("defeated") and target.has_method("receive_world_hit") and player.global_position.distance_to(target.global_position) <= 95.0:
			target.receive_world_hit(40.0)
	return true

func try_attack() -> bool:
	if not player.input_enabled or player.network_recovery_paused or cooldown > 0.0 or dodge_time > 0.0:
		return false
	if player.visual == null or player.visual.animator == null or (not player.visual.animator.is_looping() and not player.visual.animator.is_finished()):
		return false
	cooldown = attack_cooldown
	attack_facing = player.facing_direction
	attack_avatar = player.avatar_id
	player.visual.set_move_direction(attack_facing)
	player.presentation_component.play_attack()
	AudioDirector.play_variant("sword_swing")
	if player.avatar_id == "kael":
		attack_pending = true
	else:
		_resolve_attack()
	return true

func _resolve_attack() -> void:
	var target: Node2D = null
	var nearest := attack_range
	for candidate in get_tree().get_nodes_in_group("world_action_targets"):
		if not is_instance_valid(candidate) or not candidate.has_method("receive_world_hit") or candidate.get("defeated"):
			continue
		var offset: Vector2 = candidate.global_position - player.global_position
		var distance := offset.length()
		if distance <= nearest and (distance < 12.0 or attack_facing.dot(offset.normalized()) >= 0.25):
			target = candidate
			nearest = distance
	if target != null:
		AudioDirector.play_variant("sword_impact")
		target.receive_world_hit(attack_damage)

func receive_world_damage(amount: float) -> void:
	if not player.input_enabled or player.network_recovery_paused or hurt_cooldown > 0.0 or dodge_time > 0.0:
		return
	attack_pending = false
	hurt_cooldown = 0.8
	hp = maxf(0.0, hp - amount)
	player.play_damage()
	if str(player.avatar_id).begins_with("kael") or str(player.avatar_id).begins_with("gerald"):
		AudioDirector.play_variant("male_hurt")
	EventBus.toast_requested.emit("Health: %d / %d" % [hp, max_hp])
	if hp <= 0.0:
		player.play_defeat()
		AudioDirector.play_variant("defeat")
		hp = max_hp
		hurt_cooldown = 3.0
		EventBus.toast_requested.emit("You were knocked out. Health restored for this prototype.")
func apply_coop_health(authoritative_hp: float, knocked_out: bool = false, animate: bool = false) -> void:
	hp = clampf(authoritative_hp, 0.0, max_hp)
	if not animate:
		return
	attack_pending = false
	if knocked_out:
		player.play_defeat()
		EventBus.toast_requested.emit("Knocked out. Expedition health restored.")
	else:
		player.play_damage()
		EventBus.toast_requested.emit("Expedition health: %d / %d" % [hp,max_hp])