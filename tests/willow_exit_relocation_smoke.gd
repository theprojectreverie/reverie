extends Node
const TR = preload("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
func _ready():
 call_deferred("run")
func run():
 var t=get_tree()
 if not OS.get_user_data_dir().to_lower().contains("reverie_travel_test"):
  t.quit(1)
  return
 var k=Node.new()
 t.root.add_child(k)
 reparent(k)
 GameState.quest_domain.flags["tutorial_complete"]=true
 TR.pending_arrival=&"ToNextZone"
 t.change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_03_willow_fields_standalone.tscn")
 await t.scene_changed
 for i in range(10):
  await t.physics_frame
 var z=t.current_scene
 var p=z.get("checkpoint_player") as CharacterBody2D
 var m=z.get_node("TransferPoints/ToNextZone") as Marker2D
 print("EXIT ",m.position," ARRIVAL ",p.position," clear=",not p.test_move(p.global_transform,Vector2(0.1,0)))
 var cam=p.get_node("Camera2D") as Camera2D
 cam.reset_smoothing()
 for i in range(8):
  await t.physics_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  t.root.get_texture().get_image().save_png("user://willow_exit_relocated.png")
 p.global_position=m.global_position
 for i in range(120):
  await t.physics_frame
  if t.current_scene!=z:
   break
 var ok=t.current_scene!=null and t.current_scene.name==&"StandaloneZone04"
 print("WILLOW_EXIT_TRANSFER=",ok," scene=",t.current_scene.name if t.current_scene else "none")
 t.quit(0 if ok else 1)
