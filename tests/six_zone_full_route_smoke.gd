extends SceneTree
var failures: Array[String] = []
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  printerr("Set REVERIE_E2E_DISABLE_LOCAL_SAVE=1 before running this test.")
  quit(2)
  return
 var gs = root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=false
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage","x":-2090.0,"y":112.0}
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(5):await physics_frame
 var route = ["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04","StandaloneZone05","StandaloneZone06","StandaloneZone05","StandaloneZone04","StandaloneZone03","StandaloneZone02","StandaloneZone01"]
 for i in range(route.size()-1):
  var zone=current_scene
  if zone.name!=route[i]:
   failures.append("Unexpected current scene "+str(zone.name))
   break
  var player=zone.get("checkpoint_player")
  var marker_name="ToNextZone" if i<6 else "ToPreviousZone"
  var marker=zone.get_node_or_null("TransferPoints/"+marker_name)
  if marker==null:
   failures.append("Missing marker "+str(zone.name))
   break
  var visual=marker.get_node_or_null("SoutheastRoadContinuation") as Sprite2D
  if visual==null:
   visual=marker.get_node_or_null("CustomRoadContinuation") as Sprite2D
  if visual==null:
   visual=marker.get_node_or_null("ContinuationMarker/DirectionArrow") as Sprite2D
  if visual==null or visual.texture==null or not visual.is_visible_in_tree():
   failures.append("Missing visible continuation arrow "+route[i])
   break
  if route[i]!="StandaloneVillage":
   var label=marker.get_node_or_null("ContinuationMarker/DestinationName") as Label
   if label==null or label.text.is_empty() or not label.is_visible_in_tree():
    failures.append("Missing destination label "+route[i])
    break
  var trigger: Area2D
  for child in marker.get_children():
   if child is Area2D and "destination_scene" in child:
    trigger=child
    break
  if trigger==null:
   failures.append("Missing trigger "+str(zone.name))
   break
  player.input_enabled=false
  var offset := Vector2.ZERO
  if route[i]=="StandaloneVillage":offset=Vector2(-60,0)
  if route[i]=="StandaloneZone02" and marker_name=="ToNextZone":offset=Vector2(-90,-50)
  var walk_exit = (marker_name=="ToNextZone" and route[i] != "StandaloneVillage") or route[i]=="StandaloneZone06"
  if walk_exit:
   offset=Vector2(-240,0) if route[i]=="StandaloneZone03" else Vector2(-230,-115)
   if route[i]=="StandaloneZone06":offset=Vector2(0,-590)
  player.global_position=trigger.global_position+offset
  player.velocity=Vector2.ZERO
  if walk_exit:
   player.input_enabled=true
   root.get_node("TouchInput").set_move_vector(-offset.normalized()*0.8)
   print("Walking into exit from ",player.global_position," toward ",trigger.global_position)
  if route[i]=="StandaloneVillage":
   for frame in range(10):await physics_frame
   if current_scene!=zone:
    failures.append("Village exit unlocked before victory")
    break
   gs.quest_domain.flags["village_gerald_defeated"]=true
   for frame in range(5):await physics_frame
   if current_scene!=zone:
    failures.append("Village exit interrupted battle input lock")
    break
   player.input_enabled=true
   print("Village locked before victory and while input disabled; checking unlock in place")
  var arrived=false
  for frame in range(300):
   await physics_frame
   if current_scene!=null and current_scene!=zone:
    arrived=true
    break
  root.get_node("TouchInput").release()
  if not arrived:
   failures.append("No transition from "+route[i])
   break
  for frame in range(8):await physics_frame
  if current_scene==null or current_scene.name!=route[i+1]:
   failures.append("Wrong destination "+route[i+1])
   break
  var arrival_player=current_scene.get("checkpoint_player")
  print(route[i]," -> ",route[i+1]," spawn=",arrival_player.position," checkpoint=",gs.quest_domain.flags.get("six_zone_checkpoint",{}).get("zone",""))
 print("ROUTE TEST failures=",failures)
 quit(0 if failures.is_empty() else 1)