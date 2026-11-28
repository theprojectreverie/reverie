extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_02_royal_gate_standalone.tscn")
 await scene_changed
 var z=current_scene.get_node("Zone")
 var water=z.get_node("CentralPark/Fountain/DraftAsset/AnimatedWaterSpray") as AnimatedSprite2D
 var walkers=z.find_children("Stroll","AnimationPlayer",true,false)
 var lights=z.find_children("LanternShimmer","AnimationPlayer",true,false)
 var petals=z.find_children("DriftingPetals","CPUParticles2D",true,false)
 var initial={}
 for p in walkers:initial[p]=p.get_parent().position
 var frames={}
 var water_frames={}
 for i in range(7):
  await create_timer(0.13).timeout
  water_frames[water.frame]=true
  for p in walkers:
   var sprite=p.get_parent().get_node("Walk")
   if not frames.has(p):frames[p]={}
   frames[p][sprite.frame]=true
 var moving=0
 for p in walkers:
  if p.get_parent().position.distance_to(initial[p])>10 and frames[p].size()>1:moving+=1
 var active_lights=0
 for p in lights:
  if p.is_playing() and p.current_animation_position>0:active_lights+=1
 var active_petals=0
 for p in petals:
  if p.emitting:active_petals+=1
 print("AMBIENT water unique frames=",water_frames.size()," moving walkers=",moving,"/",walkers.size()," active lamps=",active_lights,"/",lights.size()," emitting petals=",active_petals,"/",petals.size())
 var ok=water_frames.size()>2 and walkers.size()==7 and moving==7 and lights.size()==11 and active_lights==lights.size() and petals.size()==10
 if is_instance_valid(current_scene): current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if ok else 1)

