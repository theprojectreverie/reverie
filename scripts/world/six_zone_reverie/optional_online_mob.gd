extends "res://scripts/world/six_zone_reverie/rose_slime.gd"
## Optional mobs are server-authoritative in co-op; no local rewards or quest credit.
func _ready() -> void:
	super._ready()
	if not _is_coop():
		remove_from_group("world_action_targets")

func _is_coop() -> bool:
	if MultiplayerGateway.standalone_expedition_id.is_empty():
		return false
	return (group_id == "royal_gate_rainbow_1" and MultiplayerGateway.standalone_expedition_region == "six_zone_royal_gate") or (group_id == "forsaken_bird_1" and MultiplayerGateway.standalone_expedition_region == "six_zone_forsaken_ruins") or (group_id == "willow_mossling_1" and MultiplayerGateway.standalone_expedition_region == "six_zone_willow_fields")

func _restore_local_respawn() -> void:
	pass

func _physics_process(delta: float) -> void:
	if _is_coop():
		super._physics_process(delta)
	else:
		sprite.play("idle")

func receive_world_hit(amount: float) -> void:
	if _is_coop():
		super.receive_world_hit(amount)
