extends Interactable
## Authored sprite animations; passive wandering stays close to the placed spawn.
@export var group_id: String = "rose_slime_garden"
@export var monster_name := "Rose Slime"
@export var roam_radius := 28.0
@export var move_speed := 15.0
@export var respawn_seconds := 15.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var home: Vector2
var elapsed := 0.0
var engaged := false
var defeated := false
var is_boss := false
@export var max_world_hp := 100.0
var world_hp := 100.0
var hit_lock := 0.0
var attack_timer := 0.0
var windup := false
var coop_dead_until := 0.0
var coop_counterattack_remaining := 0.0
var coop_motion_target := Vector2.ZERO
var coop_motion_ready := false
var coop_motion_samples := 0
var coop_motion_mode := "patrol"
var coop_aggro_target := ""
var respawn_remaining := 0.0
const RESPAWN_FLAG := "local_mob_respawn_deadlines"
@onready var health_bar: ProgressBar = $WorldHealth

func _ready() -> void:
    super._ready()
    home = position
    elapsed = float(get_index()) * 1.7
    prompt = ""
    world_hp = max_world_hp
    health_bar.max_value = max_world_hp
    health_bar.value = world_hp
    health_bar.hide()
    add_to_group("world_action_targets")
    interaction_radius = 85.0
    add_to_group("world_minimap_monsters")
    EventBus.battle_finished.connect(_on_battle_finished)
    if not _is_coop() and _story_garden_zone() == null:
        _restore_local_respawn()

func _physics_process(delta: float) -> void:
    if defeated and sprite.animation == "defeat" and not sprite.is_playing():
        hide()
    if _is_coop():
        if defeated and coop_dead_until > 0.0 and Time.get_unix_time_from_system() * 1000.0 >= coop_dead_until:
            apply_coop_monster_state(max_world_hp, 0.0)
        elif not defeated:
            hit_lock = maxf(0.0, hit_lock - delta)
            coop_counterattack_remaining = maxf(0.0, coop_counterattack_remaining - delta)
            var moving := false
            if coop_motion_ready:
                var displacement := coop_motion_target - global_position
                moving = displacement.length() > 0.1
                if moving:
                    global_position = global_position.lerp(coop_motion_target, 1.0-exp(-10.0*delta))
                    if hit_lock <= 0.0 and coop_counterattack_remaining <= 0.0 and absf(displacement.x) > 0.05:
                        sprite.flip_h = displacement.x < 0.0
            if hit_lock <= 0.0 and coop_counterattack_remaining <= 0.0:
                sprite.play("walk" if moving else "idle")
        return
    if _story_garden_zone() != null and defeated:
        return # Only a fresh server status can respawn a story monster.
    if defeated:
        respawn_remaining = maxf(0.0, respawn_remaining - delta)
        if respawn_remaining <= 0.0:
            _reset_after_respawn()
        return
    if engaged:
        return
    if hit_lock > 0.0:
        hit_lock -= delta
        return
    attack_timer = maxf(0.0, attack_timer - delta)
    var player := get_tree().get_first_node_in_group("player") as Player
    if player != null and player.input_enabled:
        var distance := global_position.distance_to(player.global_position)
        if windup:
            if attack_timer <= 0.0:
                windup = false
                attack_timer = 1.2
                if distance <= 45.0:
                    player.get_node("WorldCombatComponent").receive_world_damage(12.0)
            return
        if world_hp < max_world_hp and distance <= 45.0 and attack_timer <= 0.0:
            windup = true
            attack_timer = 0.4
            sprite.play("attack")
            return
    else:
        windup = false
    elapsed += delta
    var phase := fmod(elapsed, 8.0)
    var target := home + Vector2(sin(elapsed * 0.55), cos(elapsed * 0.55) * 0.5) * roam_radius if phase < 4.0 else position
    var next := position.move_toward(target, move_speed * delta)
    if next.distance_to(position) > 0.01:
        var query := PhysicsPointQueryParameters2D.new()
        query.position = get_parent().to_global(next)
        query.collision_mask = 1
        if get_world_2d().direct_space_state.intersect_point(query, 1).is_empty():
            sprite.flip_h = next.x < position.x
            position = next
            sprite.play("walk")
            return
    sprite.play("idle")

func can_interact() -> bool:
    return false

func interact() -> void:
    pass

func receive_world_hit(amount: float) -> void:
    if defeated or amount <= 0.0:
        return
    if _is_coop():
        MultiplayerGateway.request_monster_attack(group_id)
        return
    var story_zone := _story_garden_zone()
    if story_zone != null:
        var sync := story_zone.get_node_or_null("StoryGardenCombatSync")
        if sync != null: sync.request_encounter(group_id)
        return # Never calculate world damage or grant local loot in story mode.
    AudioDirector.play_variant("slime_hurt")
    windup = false
    attack_timer = 0.6
    world_hp = maxf(0.0, world_hp - amount)
    health_bar.value = world_hp
    health_bar.show()
    if world_hp > 0.0:
        hit_lock = 0.6
        sprite.play("hit")
        return
    _begin_defeat()
    _remember_local_respawn()
    GameState.reward_domain.apply_battle_result(group_id, true)

func _begin_defeat() -> void:
    defeated = true
    engaged = false
    world_hp = 0.0
    health_bar.value = 0.0
    health_bar.hide()
    windup = false
    coop_counterattack_remaining = 0.0
    respawn_remaining = maxf(1.0, respawn_seconds)
    sprite.play("defeat")

func _reset_after_respawn() -> void:
    if not _is_coop() and _story_garden_zone() == null and coop_dead_until <= 0.0:
        _forget_local_respawn()
    position = home
    coop_motion_target = global_position
    coop_motion_ready = false
    world_hp = max_world_hp
    health_bar.max_value = max_world_hp
    health_bar.value = world_hp
    health_bar.hide()
    defeated = false
    engaged = false
    windup = false
    hit_lock = 0.0
    attack_timer = 0.0
    coop_counterattack_remaining = 0.0
    respawn_remaining = 0.0
    coop_dead_until = 0.0
    show()
    sprite.play("idle")
func _on_battle_finished(_result: Dictionary) -> void:
    pass
func apply_coop_monster_state(hp: float, dead_until: float) -> void:
    var previous := world_hp
    coop_dead_until = dead_until
    if hp <= 0.0 and dead_until <= Time.get_unix_time_from_system() * 1000.0:
        hp = max_world_hp
    world_hp = clampf(hp, 0.0, max_world_hp)
    health_bar.value = world_hp
    if world_hp <= 0.0:
        if not defeated:
            _begin_defeat()
        return
    if defeated:
        var restored_hp := world_hp
        _reset_after_respawn()
        world_hp = restored_hp
        health_bar.value = world_hp
    show()
    if world_hp >= max_world_hp:
        health_bar.hide()
        sprite.play("idle")
    else:
        health_bar.show()
        if world_hp < previous:
            hit_lock = 0.6
            sprite.play("hit")
func play_coop_counterattack(target_position: Vector2) -> void:
    if defeated:
        return
    sprite.flip_h = target_position.x < global_position.x
    coop_counterattack_remaining = 0.8
    sprite.play("attack")
func _is_coop() -> bool:
    return not MultiplayerGateway.standalone_expedition_id.is_empty() and MultiplayerGateway.standalone_expedition_region in ["six_zone_royal_gardens", "six_zone_royal_gate", "six_zone_willow_fields"]

func _remember_local_respawn() -> void:
    if _is_coop():
        return
    var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
    deadlines[group_id] = Time.get_unix_time_from_system() + respawn_remaining
    GameState.quest_domain.flags[RESPAWN_FLAG] = deadlines

func _forget_local_respawn() -> void:
    var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
    deadlines.erase(group_id)
    if deadlines.is_empty():
        GameState.quest_domain.flags.erase(RESPAWN_FLAG)
    else:
        GameState.quest_domain.flags[RESPAWN_FLAG] = deadlines

func _restore_local_respawn() -> void:
    var deadlines: Dictionary = GameState.quest_domain.flags.get(RESPAWN_FLAG, {})
    var remaining := float(deadlines.get(group_id, 0.0)) - Time.get_unix_time_from_system()
    if remaining <= 0.0:
        _forget_local_respawn()
        return
    _begin_defeat()
    respawn_remaining = minf(remaining, maxf(1.0, respawn_seconds))
    sprite.stop()
    hide()
func apply_coop_motion(next_position: Vector2, mode: String = "patrol", target_id: String = "") -> void:
    coop_motion_mode = mode
    coop_aggro_target = target_id
    coop_motion_target = next_position
    coop_motion_ready = true
    coop_motion_samples += 1
func _story_garden_zone() -> Node:
    if OS.get_environment("REVERIE_STORY_WORLD_PILOT") != "1" or OS.get_environment("REVERIE_GARDENS_STORY_PILOT") != "1" or not MultiplayerGateway.standalone_expedition_id.is_empty():
        return null
    var node := get_parent()
    while node != null:
        if node.name in [&"StandaloneZone01", &"StandaloneZone02"]: return node
        node = node.get_parent()
    return null

func apply_story_respawn_ms(remaining_ms: int) -> void:
    if _story_garden_zone() == null: return
    if remaining_ms > 0:
        if not defeated: _begin_defeat()
        respawn_remaining = float(remaining_ms) / 1000.0
    elif defeated:
        _reset_after_respawn()
