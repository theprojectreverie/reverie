extends Node2D

func _ready() -> void:
 call_deferred("_build_preview")

func _build_preview() -> void:
 var packed := load("res://scenes/world/castle_royal_gardens.tscn") as PackedScene
 var world := packed.instantiate()
 add_child(world)
 await get_tree().process_frame
 await get_tree().process_frame
 await get_tree().process_frame
 var camera := Camera2D.new()
 camera.name = "FullMapCamera"
 camera.position = Vector2(640, 600)
 camera.zoom = Vector2(0.18, 0.18)
 camera.position_smoothing_enabled = false
 add_child(camera)
 camera.make_current()
 await get_tree().process_frame
 camera.make_current()
 print("STATIC_GARDEN_PREVIEW world=", world.name, " camera=", camera.global_position, " zoom=", camera.zoom, " current=", camera.is_current())
 print("FLORA_VISIBLE=", world.get_node("Flora").visible, " PROPS_VISIBLE=", world.get_node("Props").visible)
 print("LAYOUT_VISIBLE=", world.get_node("SymmetricalGardenLayout").visible)
