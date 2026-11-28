extends "res://scripts/world/interactable.gd"
## Dedicated Zone 6 raven. Client never awards/damages during co-op.
@export var group_id := "tower_eclipse_raven_1"
@export var monster_name := "Eclipse Raven"
@export var max_world_hp := 150.0
@export var roam_radius := 24.0
@export var move_speed := 26.0
@export var respawn_seconds := 15.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $WorldHealth
var defeated := false
var is_boss := false
var world_hp := 150.0
var home := Vector2.ZERO
var phase := 0.0
var facing := "se"
var movement_ready := false
var motion_target := Vector2.ZERO
var dead_until := 0.0
var hit_flash := 0.0
var cooldown := 0.0
var attack_elapsed := -1.0
var attack_target := Vector2.ZERO
var swoop_offset := Vector2.ZERO
var attack_hit := false
const RESPAWN_FLAG := "local_mob_respawn_deadlines"

func _ready() -> void:
	super._ready()
	home = position
	# Different deterministic starting phases keep the population from moving in lockstep.
	phase = float(absi(group_id.hash()) % 700) / 100.0
	motion_target = global_position
	world_hp = max_world_hp
	health_bar.max_value = max_world_hp
	health_bar.value = world_hp
	health_bar.hide()
	sprite.position = Vector2(0, -47)
	prompt = ""
	add_to_group("world_action_targets")
	add_to_group("world_minimap_monsters")
	if not _is_coop():
		var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
		var remaining := float(deadlines.get(group_id, 0.0)) - Time.get_unix_time_from_system()
		if remaining > 0:
			_begin_defeat(Time.get_unix_time_from_system() * 1000.0 + remaining * 1000.0)

func _is_coop() -> bool:
	return not MultiplayerGateway.standalone_expedition_id.is_empty()

func can_interact() -> bool:
	return false

func _direction(v: Vector2) -> String:
	return ("n" if v.y < 0 else "s") + ("w" if v.x < 0 else "e")

func _clear_path(from: Vector2, to: Vector2) -> bool:
	if from.distance_squared_to(to) < 0.01:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
	if defeated:
		if Time.get_unix_time_from_system() * 1000.0 >= dead_until and (not _is_coop() or movement_ready):
			_respawn()
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	sprite.modulate = Color(1.45, 1.45, 1.45) if hit_flash > 0 else Color.WHITE
	cooldown = maxf(0.0, cooldown - delta)
	if attack_elapsed >= 0.0:
		_update_attack(delta)
		return
	if _is_coop():
		# Old server versions do not know this spawn. Do not invent combat authority.
		if not movement_ready:
			sprite.play("idle")
			return
		var displacement := motion_target - global_position
		if displacement.length() > 0.7:
			facing = _direction(displacement)
			global_position = global_position.lerp(motion_target, 1.0 - exp(-10.0 * delta))
			sprite.play("fly_" + facing)
		else:
			_play_idle()
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and world_hp < max_world_hp and cooldown <= 0.0 and global_position.distance_to(player.global_position) <= 70.0 and _clear_path(global_position, player.global_position):
		_start_attack(player.global_position)
		return
	phase += delta
	var target := home + Vector2(sin(phase * 0.9), cos(phase * 0.9) * 0.5) * roam_radius
	var next := position.move_toward(target, move_speed * delta)
	var displacement := next - position
	if fmod(phase, 7.0) < 5.2 and displacement.length() > 0.06 and _clear_path(global_position, get_parent().to_global(next)):
		facing = _direction(displacement)
		position = next
		sprite.play("fly_" + facing)
	else:
		_play_idle()

func _play_idle() -> void:
	sprite.play("idle_" + facing)

func _start_attack(target: Vector2) -> void:
	facing = _direction(target - global_position)
	attack_target = target
	attack_elapsed = 0.0
	attack_hit = false
	swoop_offset = (target - global_position).limit_length(42.0)
	sprite.play("attack_" + facing)
	sprite.position = Vector2(0, -47)

func _update_attack(delta: float) -> void:
	var previous := attack_elapsed
	attack_elapsed += delta
	var t := attack_elapsed
	var amount := 0.0
	if t < 0.18:
		amount = -0.15 * sin(t / 0.18 * PI * 0.5)
	elif t < 0.40:
		amount = lerpf(-0.15, 1.0, clampf((t - 0.18) / 0.22, 0.0, 1.0))
	else:
		amount = 1.0 - clampf((t - 0.40) / 0.40, 0.0, 1.0)
	sprite.position = Vector2(0, -47) + swoop_offset * amount + Vector2(0, maxf(0.0, amount) * 15.0)
	if previous < 0.40 and t >= 0.40 and not attack_hit:
		attack_hit = true
		if not _is_coop():
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player != null and player.global_position.distance_to(attack_target) <= 24.0 and global_position.distance_to(player.global_position) <= 70.0 and _clear_path(global_position, player.global_position):
				var combat := player.get_node_or_null("WorldCombatComponent")
				if combat != null:
					combat.receive_world_damage(12.0)
	if t >= 0.80:
		attack_elapsed = -1.0
		sprite.position = Vector2(0, -47)
		cooldown = 1.2
		_play_idle()

func receive_world_hit(amount: float) -> void:
	if defeated or amount <= 0.0:
		return
	if _is_coop():
		if movement_ready:
			MultiplayerGateway.request_monster_attack(group_id)
		return
	world_hp = maxf(0.0, world_hp - amount)
	health_bar.value = world_hp
	health_bar.show()
	hit_flash = 0.14
	if world_hp <= 0:
		_begin_defeat(Time.get_unix_time_from_system() * 1000.0 + respawn_seconds * 1000.0)
		var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
		deadlines[group_id] = dead_until / 1000.0
		GameState.quest_domain.flags[RESPAWN_FLAG] = deadlines
		GameState.reward_domain.apply_battle_result(group_id, true)

func _begin_defeat(deadline: float) -> void:
	defeated = true
	dead_until = deadline
	world_hp = 0
	attack_elapsed = -1.0
	sprite.position = Vector2(0, -47)
	health_bar.hide()
	sprite.stop()
	hide()

func _respawn() -> void:
	defeated = false
	dead_until = 0
	world_hp = max_world_hp
	health_bar.value = world_hp
	health_bar.hide()
	position = home
	sprite.modulate = Color.WHITE
	facing = "se"
	show()
	sprite.play("idle")
	if not _is_coop():
		var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
		deadlines.erase(group_id)
		if deadlines.is_empty():
			GameState.quest_domain.flags.erase(RESPAWN_FLAG)
		else:
			GameState.quest_domain.flags[RESPAWN_FLAG] = deadlines

func apply_coop_motion(next_position: Vector2, _mode: String = "patrol", _target_id: String = "") -> void:
	movement_ready = true
	motion_target = next_position

func apply_coop_monster_state(hp: float, deadline: float) -> void:
	var previous := world_hp
	world_hp = clampf(hp, 0.0, max_world_hp)
	if world_hp <= 0.0:
		_begin_defeat(deadline)
		return
	if defeated:
		var restored := world_hp
		_respawn()
		world_hp = restored
	health_bar.value = world_hp
	health_bar.visible = world_hp < max_world_hp
	if world_hp < previous:
		hit_flash = 0.14

func play_coop_counterattack(target_position: Vector2) -> void:
	if not defeated:
		_start_attack(target_position)
