extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 var z=current_scene.get_node("Zone")
 var merchant=z.get_node("CityLifePreview/Merchant/MerchantAction") as AnimatedSprite2D
 var butterflies=z.find_children("Flutter","AnimationPlayer",true,false)
 var canopies=z.find_children("AwningBreeze","AnimationPlayer",true,false)
 var start={}
 for a in butterflies:start[a]=a.get_parent().position
 var frames={}
 for i in range(9):
  await create_timer(0.15).timeout
  frames[merchant.frame]=true
 var flight=0
 for a in butterflies:
  if a.is_playing() and a.get_parent().position.distance_to(start[a])>5:flight+=1
 var active=0
 for a in canopies:
  if a.is_playing() and a.current_animation_position>0:active+=1
 print("MARKET LIFE: merchant frames=",frames.size()," butterflies moving=",flight,"/",butterflies.size()," active canopies=",active,"/",canopies.size())
 if is_instance_valid(current_scene): current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if frames.size()>=3 and flight==5 and canopies.size()>=8 and active==canopies.size() else 1)

