extends Node

func _ready() -> void:
 call_deferred("_launch")

func _launch() -> void:
 var session = GameState.session_domain
 session.set_player_region("castle_royal_gardens")
 session.set_active_world("castle_royal_gardens")
 session.has_player_position = false
 session.region_positions.clear()
 var packed := load("res://scenes/game.tscn") as PackedScene
 if packed == null:
  push_error("GAME_SCENE_MISSING")
  return
 var game := packed.instantiate()
 game.name = "SymmetricGardenPreviewGame"
 add_child(game)
 await get_tree().process_frame
 await get_tree().process_frame
 await get_tree().process_frame
 var camera := get_viewport().get_camera_2d()
 if camera == null:
  push_error("PREVIEW_CAMERA_MISSING")
  return
 camera.global_position = Vector2(640, 600)
 camera.zoom = Vector2(0.33, 0.33)
 camera.position_smoothing_enabled = false
 camera.offset = Vector2.ZERO
 print("SYMMETRIC_PREVIEW_CAMERA=", camera.get_path(), " POS=", camera.global_position, " ZOOM=", camera.zoom)
 var host := game.get_node_or_null("WorldHost")
 if host != null and host.get_child_count() == 1:
  var world := host.get_child(0)
  print("SYMMETRIC_PREVIEW_WORLD=", world.name)
  print("FLORA_VISIBLE=", world.get_node("Flora").visible, " PROPS_VISIBLE=", world.get_node("Props").visible)
  print("LAYOUT_VISIBLE=", world.get_node("SymmetricalGardenLayout").visible)
  print("EXPANSION_FLORA_VISIBLE=", world.get_node("ExpansionBuilder/ExpansionFlora").visible)
 else:
  push_error("WORLD_HOST_NOT_SINGLE")
