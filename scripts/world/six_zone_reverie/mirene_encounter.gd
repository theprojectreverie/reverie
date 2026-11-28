extends Interactable
const group_id := "mirene_encounter"
var defeated := false
var is_boss := true
var _eligible := false
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	super._ready()
	prompt = "Challenge Mirène"
	interaction_radius = 90.0
	add_to_group("world_action_targets")
	add_to_group("world_minimap_monsters")
	sprite.play("idle_0")
	# Only the verified story transport can initiate or settle this boss.
	visible = OS.get_environment("REVERIE_STORY_WORLD_PILOT") == "1" and OS.get_environment("REVERIE_GARDENS_STORY_PILOT") == "1" and MultiplayerGateway.standalone_expedition_id.is_empty()

func apply_boss_status(audience: Dictionary) -> void:
	defeated = bool(audience.get("mireneDefeated", false))
	_eligible = audience.get("state") == "complete" and not defeated
	visible = not defeated

func can_interact() -> bool:
	return super.can_interact() and _eligible and not defeated

func interact() -> void:
	if not can_interact(): return
	var sync := get_parent().get_node_or_null("StoryGardenCombatSync")
	if sync != null: sync.request_encounter(group_id)

func receive_world_hit(amount: float) -> void:
	if amount > 0.0: interact()
