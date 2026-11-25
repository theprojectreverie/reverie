extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var packed := load("res://scenes/world/castle_gardens/components/reverie_royal_gardens_full_preview.tscn") as PackedScene
	if packed == null:
		push_error("Full Royal Gardens preview failed to load.")
		quit(1)
		return
	var scene := packed.instantiate() as Node2D
	var required := {
		"TerrainSystem/IsometricTerrainLayers": Node2D,
		"TerrainSystem/RoadEdgeTransitions": Node2D,
		"PathwaySystem/RoyalPathways/HandDesignedRoadSurfaces": Node2D,
		"CastleSystem/ModularCastleAssembly": Node2D,
		"GardenFloraSystem/Flora": Node2D,
		"FenceSystem/GardenFences": Node2D,
		"GardenPropsSystem/Props": Node2D,
		"GardenWaterSystem/Water": Node2D,
		"PreviewCamera": Camera2D,
		"AmbientColor": CanvasModulate
	}
	var errors: Array[String] = []
	for path in required:
		var node := scene.get_node_or_null(NodePath(path))
		if node == null:
			errors.append("Missing current preview component: " + path)
	var terrain := scene.get_node_or_null("TerrainSystem/IsometricTerrainLayers")
	if terrain != null:
		for layer_name in ["BaseGround", "GroundVariation", "Paths", "Water", "FlowerDetails", "Hedges", "Vegetation", "Foreground"]:
			if terrain.get_node_or_null(layer_name) == null:
				errors.append("Missing terrain layer: " + layer_name)
	var castle_collection := scene.get_node_or_null("CastleSystem/ModularCastleAssembly/CastleCollection")
	if castle_collection == null:
		errors.append("Missing current authored castle collection")
	else:
		var keep := castle_collection.get_node_or_null("CastleKeep")
		if keep == null:
			errors.append("Missing single palace keep")
		else:
			var artwork := keep.get_node_or_null("KeepArtwork") as Sprite2D
			if artwork == null or artwork.texture == null or artwork.texture.resource_path != "res://assets/reverie_custom/royal_gardens/production/grand_royal_palace.png":
				errors.append("Missing approved single-palace artwork")
			if keep.get_node_or_null("KeepWallSolid/KeepWallShape") == null:
				errors.append("Missing rear keep wall collision")
			if keep.get_node_or_null("CollisionBody/WestWing") == null or keep.get_node_or_null("CollisionBody/EastWing") == null:
				errors.append("Missing west/east keep wing collision shapes")
	if not errors.is_empty():
		for issue in errors:
			push_error(issue)
		scene.free()
		quit(1)
		return
	print("ROYAL_GARDEN_FULL_PREVIEW_STRUCTURE_OK systems=8 terrain_layers=8 single_palace_art=true keep_collision=true hand_designed_roads=true")
	scene.free()
	quit(0)
