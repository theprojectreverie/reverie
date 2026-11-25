extends Node

const PROP_SCENE: PackedScene = preload("res://scenes/environment/forest/forest_prop.tscn")
const SUPPORTED_KINDS := [
	"fern", "flower_cluster", "bush", "berry_bush", "moss_rock",
	"spirit_bloom", "moon_lantern", "willow_tree", "pine_tree",
	"birch_tree", "blossom_tree", "dead_tree"
]

func _ready() -> void:
	_run()

func _run() -> void:
	for kind in SUPPORTED_KINDS:
		var prop := PROP_SCENE.instantiate() as ModularForestProp
		add_child(prop)
		prop.configure(kind, 0, 1.0, false)
		await get_tree().process_frame
		var visual := prop.get_node("Visual") as Sprite2D
		assert(visual.texture != null, "Authored prop texture missing: " + kind)
		assert(visual.visible, "Authored prop should be visible: " + kind)
		assert(visual.texture.get_width() > 0 and visual.texture.get_height() > 0, "Invalid texture dimensions: " + kind)
		prop.queue_free()
		await get_tree().process_frame

	var unsupported := PROP_SCENE.instantiate() as ModularForestProp
	add_child(unsupported)
	unsupported.configure("unmapped_placeholder_kind", 0, 1.0, false)
	await get_tree().process_frame
	var unsupported_visual := unsupported.get_node("Visual") as Sprite2D
	var unsupported_shadow := unsupported.get_node("Shadow") as Sprite2D
	assert(unsupported_visual.texture == null and not unsupported_visual.visible, "Unsupported art must remain hidden")
	assert(unsupported_shadow.texture == null and not unsupported_shadow.visible, "Unsupported shadow must remain hidden")
	print("FOREST_AUTHORED_PROP_PASS mapped=%d unsupported_hidden=true" % SUPPORTED_KINDS.size())
	get_tree().quit()
