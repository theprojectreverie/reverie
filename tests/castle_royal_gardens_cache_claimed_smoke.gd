extends SceneTree
const SCENE := "res://scenes/world/castle_gardens/components/castle_expansion_component.tscn"
const FLAG := "collectible:castle_royal_seal_cache"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var quest_domain: Object = game_state.get("quest_domain")
	var flags: Dictionary = quest_domain.get("flags")
	var had_previous: bool = flags.has(FLAG)
	var previous: Variant = flags.get(FLAG, null)
	flags[FLAG] = true
	var packed := load(SCENE) as PackedScene
	assert(packed != null, "Castle expansion scene failed to load")
	var expansion := packed.instantiate() as Node2D
	root.add_child(expansion)
	await process_frame
	await process_frame
	var interactables := expansion.get_node_or_null("ExpansionInteractables") as Node2D
	assert(interactables != null, "ExpansionInteractables missing")
	var cache: Node = null
	for child in interactables.get_children():
		if child.get("collectible_id") == "castle_royal_seal_cache":
			cache = child
			break
	assert(cache != null, "Claimed cache should retain its authored scene node for stable hierarchy")
	assert(not cache.is_visible_in_tree(), "Claimed cache must be hidden")
	assert(not bool(cache.get("enabled")), "Claimed cache must be disabled")
	print("CASTLE CLAIMED CACHE RESULT: exists=%s | visible=%s | enabled=%s" % [str(cache != null), str(cache.is_visible_in_tree()), str(cache.get("enabled"))])
	if had_previous:
		flags[FLAG] = previous
	else:
		flags.erase(FLAG)
	print("CASTLE ROYAL GARDENS CLAIMED CACHE: PASS (claimed reward stays hidden and disabled; save not written)")
	quit(0)
