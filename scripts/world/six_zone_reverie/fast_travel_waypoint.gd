extends Interactable
const TRAVEL = preload("res://scripts/world/six_zone_reverie/fast_travel.gd")
var display_name := "Waystone"

func _ready() -> void:
	super._ready()
	prompt = "Use Waystone"
	interaction_radius = 125.0
	add_to_group("world_minimap_waypoints")

func can_interact() -> bool:
	return super.can_interact() and bool(GameState.quest_domain.flags.get("tutorial_complete", false)) and MultiplayerGateway.standalone_expedition_id.is_empty()

func interact() -> void:
	var zone := TRAVEL.find_zone(self)
	if zone == null or not can_interact():
		return
	var player := zone.get("checkpoint_player") as CharacterBody2D
	if not is_instance_valid(player) or not player.input_enabled or player.global_position.distance_to(global_position) > interaction_radius:
		return
	var binding := zone.get_node_or_null("ZoneUIBinding")
	if binding != null:
		binding._open_screen("map")
