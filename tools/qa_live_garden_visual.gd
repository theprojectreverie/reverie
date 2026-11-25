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
 game.name = "VisualReviewGame"
 add_child(game)
 await get_tree().process_frame
 await get_tree().process_frame
 var host := game.get_node_or_null("WorldHost")
 if host != null:
  print("LIVE_VISUAL_WORLD_CHILDREN=", host.get_child_count())
  for child in host.get_children():
   print("LIVE_VISUAL_WORLD=", child.name)
