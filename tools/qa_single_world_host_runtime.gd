extends Node

func _ready() -> void:
 call_deferred("_run")

func _run() -> void:
 var session = GameState.session_domain
 session.set_player_region("castle_royal_gardens")
 session.set_active_world("castle_royal_gardens")
 session.has_player_position = false
 session.region_positions.clear()
 var packed := load("res://scenes/game.tscn") as PackedScene
 if packed == null:
  push_error("GAME_SCENE_MISSING")
  get_tree().quit(1)
  return
 var game := packed.instantiate()
 add_child(game)
 for i in range(12): await get_tree().process_frame
 var host := game.get_node_or_null("WorldHost") as Node2D
 if host == null:
  push_error("WORLD_HOST_MISSING")
  get_tree().quit(1)
  return
 _report(host, "INITIAL")
 var world_session := game.get_node("WorldSession") as GameWorldSessionComponent
 world_session.build_world("greenward")
 for i in range(4): await get_tree().process_frame
 _report(host, "AFTER_GREENWARD")
 world_session.build_world("castle_royal_gardens")
 for i in range(8): await get_tree().process_frame
 _report(host, "AFTER_GARDENS")
 var worlds := get_tree().get_nodes_in_group("world")
 print("WORLD_GROUP_COUNT=", worlds.size())
 var ok := host.get_child_count() == 1 and worlds.size() == 1 and host.get_child(0).name == "World_castle_royal_gardens"
 if not ok:
  push_error("SINGLE_WORLD_HOST_FAILED host_children=%d world_group=%d" % [host.get_child_count(), worlds.size()])
 else:
  print("SINGLE_WORLD_HOST_OK")
 game.queue_free()
 await get_tree().process_frame
 get_tree().quit(0 if ok else 1)

func _report(host: Node, label: String) -> void:
 var names: Array[String] = []
 for child in host.get_children():
  names.append("%s:%s" % [child.name, child.get_class()])
 print(label, " WORLDHOST_CHILDREN=", names)
