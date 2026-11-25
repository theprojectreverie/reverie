extends SceneTree

const AREA_DATA := {
	"royal_gate":{"landmark":"res://scenes/world/act1_areas/royal_gate_landmark.tscn","asset":"royal_gate","npc":"road_warden_elowen"},
	"willow_fields":{"landmark":"res://scenes/world/act1_areas/willow_fields_landmark.tscn","asset":"willow_windmill","npc":"miller_ada"},
	"elderwood_grove":{"landmark":"res://scenes/world/act1_areas/elderwood_grove_landmark.tscn","asset":"elderwood_ancient_tree","npc":"grove_keeper_thalen"},
	"forsaken_ruins":{"landmark":"res://scenes/world/act1_areas/forsaken_ruins_landmark.tscn","asset":"forsaken_ruins_arch","npc":"scout_merrow"},
	"ruined_tower":{"landmark":"res://scenes/world/act1_areas/ruined_tower_landmark.tscn","asset":"ruined_tower","npc":"tower_sentinel"}
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var regions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/regions.json"))
	var dialogues: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/dialogue.json"))
	assert(typeof(regions) == TYPE_DICTIONARY, "regions.json parses")
	assert(typeof(dialogues) == TYPE_DICTIONARY, "dialogue.json parses")
	var graph := RegionGraph.new(regions)
	var errors := graph.validate()
	for error in errors:
		push_error("Act I graph validation: " + error)
	assert(errors.is_empty(), "RegionGraph validation")
	var chain := ["castle_royal_gardens","royal_gate","willow_fields","elderwood_grove","forsaken_ruins","ruined_tower","gothic_castle_boss_zone"]
	for i in range(chain.size()-1):
		assert(graph.can_travel(chain[i],chain[i+1]), "Connected route " + chain[i] + " -> " + chain[i+1])
	for region_id in AREA_DATA:
		var spec: Dictionary = AREA_DATA[region_id]
		var scene := load(str(spec.landmark)) as PackedScene
		assert(scene != null, "Landmark scene loads: " + region_id)
		var instance := scene.instantiate() as Node2D
		assert(instance != null, "Landmark scene instantiates: " + region_id)
		var sprite := instance.get_node_or_null("LandmarkSprite") as Sprite2D
		assert(sprite != null and sprite.texture != null, "PixelPen sprite texture is present: " + region_id)
		instance.free()
		var source_path := "res://assets/pixelpen_act1/" + str(spec.asset) + ".pxpen"
		var zip := ZIPReader.new()
		assert(zip.open(source_path) == OK, "Editable PixelPen source opens as an archive: " + region_id)
		var metadata_bytes := zip.read_file("config.json")
		var metadata: Variant = JSON.parse_string(metadata_bytes.get_string_from_utf8())
		assert(typeof(metadata) == TYPE_DICTIONARY, "PixelPen source metadata parses: " + region_id)
		assert(str(metadata.get("canvas_size", "")) == "Vector2i(64, 64)", "PixelPen source canvas is 64x64: " + region_id)
		var frames: Array = metadata.get("pool_frames", [])
		assert(frames.size() == 1, "PixelPen source has one frame: " + region_id)
		var layers: Array = frames[0].get("layers", []) if not frames.is_empty() else []
		assert(layers.size() == 1, "PixelPen source has one editable layer: " + region_id)
		var frame_uid := str_to_var(str(frames[0].get("frame_uid", "Vector3i.ZERO"))) as Vector3i
		var layer_path := "pool_frames/%d_%d_%d.0.bin" % [frame_uid.x, frame_uid.y, frame_uid.z]
		assert(zip.file_exists(layer_path), "PixelPen source contains the layer pixel data: " + region_id)
		var pixel_bytes := zip.read_file(layer_path)
		assert(pixel_bytes.size() == 64 * 64, "PixelPen source stores the complete indexed layer: " + region_id)
		zip.close()
		var region_def: Dictionary = regions[region_id]
		var npc_found := false
		for poi in region_def.get("pois", []):
			if str(poi.get("npc_id","")) == str(spec.npc):
				npc_found = true
				assert(dialogues.has(str(poi.get("dialogue_id",""))), "NPC dialogue exists: " + region_id)
		assert(npc_found, "NPC POI exists: " + region_id)
		print("ACT1_AREA_PASS ", region_id, " | landmark + editable PixelPen archive + NPC dialogue")
		metadata = {}
		metadata_bytes = PackedByteArray()
		pixel_bytes = PackedByteArray()
		zip = null
		scene = null
		instance = null
		sprite = null
		await process_frame
	print("ACT1_AREA_CONTENT_PASS areas=", AREA_DATA.size(), " chain=", chain)
	graph = null
	regions = {}
	dialogues = {}
	await process_frame
	await process_frame
	quit(0)
