class_name WorldGreenwardBuilderComponent
extends Node
## Spawns authored village NPCs. Environmental geometry and dressing are scene assets.

var world: GreenwardWorld
@export var composition_data: GreenwardCompositionData


func configure(owner_world: GreenwardWorld) -> void:
	world = owner_world
	if composition_data == null:
		push_error("WorldGreenwardBuilderComponent requires GreenwardCompositionData")
		return
	var errors := composition_data.validate()
	if not errors.is_empty():
		push_error("Invalid Greenward composition data: " + "; ".join(errors))


func build_village() -> void:
	if world == null or composition_data == null:
		return
	for npc in composition_data.village_npcs:
		world.spawn_npc(
			str(npc.get("npc_id", "")),
			str(npc.get("display_name", "")),
			str(npc.get("dialogue_id", "")),
			npc.get("grid", Vector2.ZERO),
			npc.get("palette", {}),
			str(npc.get("race", "Human")),
			str(npc.get("role", ""))
		)
