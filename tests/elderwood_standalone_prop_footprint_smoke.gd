extends SceneTree

const SCENE := "res://scenes/world/six_zone_reverie/individual_zones/zone_04_elderwood_grove_standalone.tscn"
const PROPS := {
	"GroveDecorations/StoneRubbleFootprint": "GroveDecorations/StoneRubble",
	"GroveDecorations/MossyRockClusterFootprint": "GroveDecorations/MossyRockCluster",
	"ElderwoodRelics/BrokenMemorial/Body": "ElderwoodRelics/BrokenMemorial/Artwork",
	"ElderwoodRelics/WeatheredPillar/Body": "ElderwoodRelics/WeatheredPillar/Artwork",
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("Could not load Zone 4 standalone scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await physics_frame
	var errors: Array[String] = []
	var collision_count := 0
	var anchor_count := 0
	for body_path in PROPS:
		var body := scene.get_node_or_null(body_path) as StaticBody2D
		if body == null:
			errors.append("missing static footprint: " + body_path)
			continue
		var polygon := body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if body_path.ends_with("/Body"):
			polygon = body.get_node_or_null("Footprint") as CollisionPolygon2D
		if polygon == null or polygon.polygon.size() < 4:
			errors.append("missing authored ground footprint polygon: " + body_path)
			continue
		collision_count += 1
		var artwork := scene.get_node_or_null(PROPS[body_path]) as Sprite2D
		if artwork == null or artwork.texture == null:
			errors.append("missing artwork for " + body_path)
			continue
		var ground_contact := artwork.to_global(artwork.get_rect().end)
		if absf(ground_contact.y - body.global_position.y) > 4.0:
			errors.append("sorting anchor misses visible ground contact: " + body_path + " delta=" + str(ground_contact.y - body.global_position.y))
		else:
			anchor_count += 1
		var query := PhysicsPointQueryParameters2D.new()
		query.position = body.global_position
		query.collision_mask = 1
		query.collide_with_areas = false
		var hits := root.world_2d.direct_space_state.intersect_point(query, 16)
		if not hits.any(func(hit: Dictionary) -> bool: return hit.collider == body):
			errors.append("footprint is not physically queryable at ground anchor: " + body_path)
	print("STANDALONE PROP FOOTPRINTS bodies=%d anchored=%d errors=%d" % [collision_count, anchor_count, errors.size()])
	for error in errors:
		push_error(error)
	scene.queue_free()
	await process_frame
	quit(0 if errors.is_empty() and collision_count == PROPS.size() and anchor_count == PROPS.size() else 1)
