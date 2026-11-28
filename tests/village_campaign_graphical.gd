extends SceneTree
var output_dir := ""
var navigation: AStarGrid2D
var travel_distance := 0.0
func _initialize(): call_deferred("_run")
func capture(name: String):
 await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 if im!=null and not im.is_empty():
  im.save_jpg(output_dir.path_join(name+".jpg"),0.88)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 output_dir=OS.get_environment("TEMP").path_join("reverie_village_graphical_final")
 DirAccess.make_dir_recursive_absolute(output_dir)
 Engine.time_scale=3.0
 var gs=root.get_node("GameState")
 for id in ["village_clear_approach","village_crimson_duel","village_clear_ruins","village_nyx_duel","village_gerald_trial"]:gs.quest_domain.quests.erase(id)
 for flag in gs.quest_domain.flags.keys():
  if str(flag).begins_with("village_encounter_won_") or str(flag).begins_with("village_recruited_") or flag in ["village_gerald_defeated","village_lilith_awakened","village_gerald_backstory_pending","village_gerald_backstory_seen","village_gerald_memories_complete"]:
   gs.quest_domain.flags.erase(flag)
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["six_zone_checkpoint"]={"zone":"StandaloneVillage","x":-2090.0,"y":112.0}
 change_scene_to_file("res://scenes/world/village/imported_village/village_playable.tscn")
 await scene_changed
 for i in range(8):await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var router=zone.get_node("CombatRouter")
 var map=zone.get_node("VillageMap")
 var ai=load("res://scripts/combat/combat_ai.gd")
 build_navigation(zone)
 var stages=["VillageSlime1","VillageSlime2","CrimsonEncounter","VillageCrownling1","VillageCrownling2","VillageCrownling3","NyxEncounter","GeraldBossSpawn/GeraldChallenge"]
 for index in range(stages.size()):
  var node=map.get_node(stages[index])
  if not await walk_to(player,node.global_position+Vector2(0,52)):
   printerr("PATH FAILURE ",stages[index]," pos=",player.global_position)
   quit(1)
   return
  print("WALKED TO ",stages[index]," pos=",player.global_position)
  player.get_node("Camera2D").reset_smoothing()
  await create_timer(0.35).timeout
  assert(node.can_interact())
  await capture(str(index)+"_world")
  node.interact()
  if index==7:
   var dialogue=zone.get_node("UI/Dialogue")
   for j in range(5):
    dialogue._finish_typing()
    dialogue._on_continue()
   dialogue._finish_typing()
   dialogue._choose(dialogue._node.choices[0])
  var deadline=Time.get_ticks_msec()+45000
  while (router.active_combat==null or router.active_combat.engine==null) and Time.get_ticks_msec()<deadline:
   await process_frame
  var battle=router.active_combat
  assert(battle!=null and battle.engine!=null)
  await create_timer(0.3).timeout
  await capture(str(index)+"_battle")
  var actions=0
  var team=[]
  for u in battle.engine.combatants:
   if u.team==0:team.append(u.def_id)
  while not battle._resolved and Time.get_ticks_msec()<deadline:
   if not battle._animating and not battle.engine.finished:
    var actor=battle.engine.current_actor()
    if actor!=null and actor.team==0:
     var choice=ai.choose(battle.engine,battle.engine.current_actor_index)
     if not str(choice.get("skill_id","")).is_empty():
      await battle._session_component.execute_action(str(choice.skill_id),choice.targets)
      actions+=1
   await process_frame
  assert(battle._resolved and battle.engine.winner_team==0)
  await capture(str(index)+"_victory")
  print("GRAPHICAL LIVE VICTORY ",battle.group_id," team=",team," player actions=",actions)
  battle._claim(true)
  for j in range(5):await process_frame
  if index<7:
   assert(router.active_combat==null and not node.visible)
   await capture(str(index)+"_after")
  else:
   await create_timer(0.5).timeout
   await capture("8_gerald_after_dialogue")
   assert(gs.quest_domain.flags.get("village_gerald_defeated",false))
 print("GRAPHICAL ALL EIGHT COMBAT ENCOUNTERS COMPLETE, walk_distance=",travel_distance)
 var deadline=Time.get_ticks_msec()+90000
 var dialogue=zone.get_node("UI/Dialogue")
 var last_dialogue=""
 var seen_shots={}
 var saw_reunion=false
 while not bool(gs.quest_domain.flags.get("village_gerald_backstory_seen",false)) and Time.get_ticks_msec()<deadline:
  if dialogue.visible:
   if dialogue._dialogue_id!=last_dialogue:
    last_dialogue=dialogue._dialogue_id
    dialogue._finish_typing()
    await capture("story_"+last_dialogue)
   dialogue._finish_typing()
   if not dialogue._node.get("choices",[]).is_empty(): dialogue._choose(dialogue._node.choices[0])
   else: dialogue._on_continue()
   await create_timer(0.22).timeout
  else:
   var story=zone.find_child("GeraldPostVictoryStory",true,false)
   if is_instance_valid(story) and not story._done and not story._transitioning:
    story.input_component.set_auto_play(false)
    var key=story.scene_file_path.get_file().get_basename()+"_"+str(story.playback_component.shot_index)
    if not seen_shots.has(key):
     await create_timer(0.45).timeout
     await capture("memory_"+key)
     seen_shots[key]=true
     story.playback_component.request_advance()
   var reunion=zone.find_child("LilithReunionCinematic",true,false)
   if is_instance_valid(reunion) and not saw_reunion:
    saw_reunion=true
    await create_timer(1.5).timeout
    await capture("story_lilith_awakening")
  await process_frame
 if not bool(gs.quest_domain.flags.get("village_gerald_backstory_seen",false)):
  printerr("STORY COMPLETION TIMEOUT")
  quit(1)
  return
 print("MEMORIES AND LILITH COMPLETE shots=",seen_shots.size()," reunion=",saw_reunion)
 await capture("story_village_completed")
 assert(player.input_enabled)
 assert(zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")._story_unlocked())
 print("VILLAGE EXIT UNLOCKED")
 quit()


func build_navigation(zone:Node2D):
 navigation=AStarGrid2D.new()
 navigation.region=Rect2i(-54,-20,112,112)
 navigation.cell_size=Vector2(40,40)
 navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 navigation.update()
 var space=zone.get_world_2d().direct_space_state
 var shape=CircleShape2D.new()
 shape.radius=18
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=shape
 q.collision_mask=1
 for y in range(navigation.region.position.y,navigation.region.end.y):
  for x in range(navigation.region.position.x,navigation.region.end.x):
   var id=Vector2i(x,y)
   q.transform=Transform2D(0,Vector2(id)*40.0)
   if not space.intersect_shape(q,1).is_empty():navigation.set_point_solid(id)
func near_grid(pos:Vector2)->Vector2i:
 var center=Vector2i((pos/40.0).round())
 var best=center
 var dist=INF
 for x in range(center.x-3,center.x+4):
  for y in range(center.y-3,center.y+4):
   var id=Vector2i(x,y)
   if not navigation.is_in_boundsv(id) or navigation.is_point_solid(id):continue
   var d=pos.distance_to(Vector2(id)*40.0)
   if d<dist:dist=d;best=id
 return best
func clear_segment(space:PhysicsDirectSpaceState2D,a:Vector2,b:Vector2)->bool:
 var shape=CircleShape2D.new()
 shape.radius=18
 var q=PhysicsShapeQueryParameters2D.new()
 q.shape=shape
 q.collision_mask=1
 q.transform=Transform2D(0,a)
 q.motion=b-a
 var f=space.cast_motion(q)
 return f.size()>=2 and f[0]>0.99
func walk_to(player:CharacterBody2D,target:Vector2)->bool:
 var path=navigation.get_point_path(near_grid(player.global_position),near_grid(target))
 if path.is_empty():return false
 var points:Array[Vector2]=[]
 var space=player.get_world_2d().direct_space_state
 var origin=player.global_position
 var k=0
 while k<path.size():
  var j=k
  for n in range(k,path.size()):
   if clear_segment(space,origin,path[n]):j=n
   else:break
  points.append(path[j])
  origin=path[j]
  k=j+1
 if clear_segment(space,origin,target):points.append(target)
 var touch=root.get_node("TouchInput")
 for point in points:
  var deadline=Time.get_ticks_msec()+12000
  while player.global_position.distance_to(point)>12 and Time.get_ticks_msec()<deadline:
   var delta=point-player.global_position
   var old=player.global_position
   touch.set_move_vector(delta.normalized()*clampf(delta.length()/70.0,0.45,1.0))
   await physics_frame
   travel_distance+=old.distance_to(player.global_position)
  touch.release()
  if player.global_position.distance_to(point)>18:return false
 await create_timer(0.15).timeout
 return player.global_position.distance_to(target)<35
