extends Interactable
## Authored sprite animations; passive wandering stays close to the placed spawn.
@export var group_id: String = "rose_slime_garden"
@export var monster_name := "Rose Slime"
@export var roam_radius := 28.0
@export var move_speed := 15.0
@export var respawn_seconds := 75.0
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

func _physics_process(delta: float) -> void:
    if engaged or defeated:
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
    defeated = true
    health_bar.hide()
    GameState.reward_domain.apply_battle_result(group_id, true)
    sprite.play("defeat")
    await sprite.animation_finished
    hide()
    await get_tree().create_timer(respawn_seconds).timeout
    position = home
    world_hp = max_world_hp
    health_bar.max_value = max_world_hp
    health_bar.value = world_hp
    health_bar.hide()
    defeated = false
    show()
    sprite.play("idle")

func _on_battle_finished(_result: Dictionary) -> void:
    pass