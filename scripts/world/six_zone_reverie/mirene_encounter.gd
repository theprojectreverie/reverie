extends Interactable
const group_id := "mirene_encounter"
var defeated := false
var is_boss := true
var _eligible := false
var _local_battle := false
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	super._ready()
	prompt = "Challenge Mirène"
	interaction_radius = 60.0
	add_to_group("world_action_targets")
	add_to_group("world_minimap_monsters")
	sprite.play("idle_0")
	# Use the verified transport in the pilot, and the existing local story in public alpha.
	visible = MultiplayerGateway.standalone_expedition_id.is_empty()
	if _local_mode():
		defeated = bool(GameState.quest_domain.flags.get("mirene_local_defeated", false))
		visible = not defeated
		EventBus.battle_finished.connect(_on_local_battle_finished)

func _local_mode() -> bool:
	return permits_local_story(AuthGateway.is_authenticated(), OS.has_feature("reverie_public_alpha"), not MultiplayerGateway.standalone_expedition_id.is_empty(), OS.get_environment("REVERIE_STORY_WORLD_PILOT") == "1" and OS.get_environment("REVERIE_GARDENS_STORY_PILOT") == "1")

static func permits_local_story(authenticated: bool, public_alpha: bool, expedition: bool, pilot: bool) -> bool:
	# Public alpha uses account-specific local story saves, just like Gerald.
	# Never fall back to local settlement in the verified pilot or shared expedition.
	return not expedition and not pilot and (not authenticated or public_alpha)

func apply_boss_status(audience: Dictionary) -> void:
	defeated = bool(audience.get("mireneDefeated", false))
	_eligible = audience.get("state") == "complete" and not defeated
	visible = not defeated

func can_interact() -> bool:
	if _local_mode():
		return super.can_interact() and not defeated and not _local_battle and GameState.quest_domain.quest_state("elathra_first_audience") == "complete"
	return super.can_interact() and _eligible and not defeated

func interact() -> void:
	if not can_interact(): return
	var sync := get_parent().get_node_or_null("StoryGardenCombatSync")
	if sync != null:
		sync.request_encounter(group_id)
	elif _local_mode():
		var router := get_parent().get_node_or_null("CombatRouter") as GameCombatRouterComponent
		var player = get_parent().get("checkpoint_player")
		if router == null or not is_instance_valid(player) or not player.input_enabled or player.global_position.distance_to(global_position) > interaction_radius: return
		_local_battle = true
		player.input_enabled = false
		player.velocity = Vector2.ZERO
		TouchInput.release()
		if not router.start_encounter(group_id):
			_local_battle = false
			player.input_enabled = true
			return
		router.combat_closed.connect(func():
			_local_battle = false
			if is_instance_valid(player): player.input_enabled = true
		, CONNECT_ONE_SHOT)

func _on_local_battle_finished(result: Dictionary) -> void:
	if not _local_battle or not _local_mode() or str(result.get("group_id", "")) != group_id or not bool(result.get("victory", false)): return
	defeated = true
	hide()
	GameState.quest_domain.flags["mirene_local_defeated"] = true
	GameState.queue_save()
	EventBus.quest_updated.emit("elathra_first_audience")

func receive_world_hit(amount: float) -> void:
	if amount > 0.0: interact()
