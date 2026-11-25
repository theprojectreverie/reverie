extends Node

const FOLIAGE_SCENES := [
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/tree_oak_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/tree_oak_02.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/tree_oak_03_tall.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/tree_blossom_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/tree_blossom_02.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/bush_flowering_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/bush_round_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/flower_patch_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/grass_tuft_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/rose_bush_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/rose_bush_02.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/ivy_wall_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/ivy_wall_02.tscn"
]

func _ready() -> void:
	print("FOLIAGE WIND MATERIAL SMOKE: starting")
	var phases: Array[float] = []
	for path in FOLIAGE_SCENES:
		var packed := load(path) as PackedScene
		assert(packed != null, "Foliage scene failed to load: " + path)
		var foliage := packed.instantiate() as Node2D
		assert(foliage != null)
		add_child(foliage)
		var sprite := foliage.get_node("Sprite") as Sprite2D
		assert(sprite != null and sprite.texture != null, "Authored foliage sprite missing: " + path)
		var material := sprite.material as ShaderMaterial
		assert(material != null, "Canopy wind ShaderMaterial missing: " + path)
		assert(material.shader != null and material.shader.code.contains("canopy_weight"), "Wind shader missing canopy vertex deformation")
		var phase := float(material.get_shader_parameter("wind_phase"))
		assert(not phases.has(phase), "Foliage wind phases should be de-synchronized")
		phases.append(phase)
		if foliage.get_node_or_null("Body/Footprint") != null:
			print("FOLIAGE WIND RESULT: %s | texture=authored | phase=%.1f | collision=preserved" % [foliage.asset_id, phase])
		else:
			print("FOLIAGE WIND RESULT: %s | texture=authored | phase=%.1f | no collision node in source" % [foliage.asset_id, phase])
	var route_packed := load("res://scenes/world/road_transition/royal_road_to_baltoria.tscn") as PackedScene
	assert(route_packed != null, "Playable Royal Road scene failed to load")
	var route := route_packed.instantiate()
	add_child(route)
	var route_wind_count := 0
	for node in route.find_children("*", "Sprite2D", true, false):
		var route_sprite := node as Sprite2D
		var route_material := route_sprite.material as ShaderMaterial
		if route_material != null and route_material.shader != null and route_material.shader.code.contains("canopy_weight"):
			route_wind_count += 1
	assert(route_wind_count >= 3, "Active Royal Road must inherit wind materials on its authored roadside trees")
	print("FOLIAGE WIND ROUTE RESULT: active Royal Road contains %d wind-animated authored tree sprites" % route_wind_count)
	print("FOLIAGE WIND MATERIAL SMOKE: PASS (%d authored foliage scenes + playable route)" % FOLIAGE_SCENES.size())
	get_tree().quit(0)
