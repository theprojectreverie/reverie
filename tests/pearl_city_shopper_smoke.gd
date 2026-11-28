extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 var city=current_scene.get_node("Zone")
 var people=city.get_node("CityLifePreview")
 var actors=[]
 var initial=[]
 for name in ["BakeryShopper","TextileShopper","SweetShopWalker"]:
  var a=people.get_node(name)
  actors.append(a)
  initial.append(a.position)
 await create_timer(1.2).timeout
 var ok=true
 for i in range(actors.size()):
  var a=actors[i]
  var p=a.get_node("Stroll")
  var active=p.is_playing() and a.position.distance_to(initial[i])>10
  print(a.name," moving=",active," distance=",a.position.distance_to(initial[i])," animation=",p.current_animation)
  ok=ok and active
 if is_instance_valid(current_scene): current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if ok else 1)

