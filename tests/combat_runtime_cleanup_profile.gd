extends SceneTree
var errors=[]
func _initialize():call_deferred("_run")
func check(ok:bool,label:String):
 if not ok:
  errors.append(label)
  push_error(label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.flags["tutorial_complete"]=true
 gs.flags["village_gerald_defeated"]=true
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(12):await process_frame
 var router=current_scene.get_node("CombatRouter")
 var initial_nodes=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
 var initial_orphans=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
 var groups=["gerald_boss_encounter","cassien_encounter","revienna_encounter","fallen_matron_encounter","elder_hollow"]
 for cycle in range(2):
  for group in groups:
   check(router.start_encounter(group),"start "+group)
   var battle=router.active_combat
   for i in range(12):await process_frame
   check(battle.engine!=null,"engine "+group)
   var field=battle._battlefield
   for name in ["GreenwardForestBackdrop","GreenwardRootArenaBackdrop","WitheredEstateBackdrop"]:
    var backdrop=field.get_node(name)
    check(backdrop.is_processing()==backdrop.visible,"backdrop "+group+" "+name)
   var actor=field.actors()[0]
   var fx=actor.get_node("GroundFX")
   fx.update_state(0.0,false,false,false,1.0,0)
   var before=fx.target_outer.scale
   fx.update_state(.4,false,false,false,1.0,0)
   check(fx.target_outer.scale==before and not fx.target_ring.visible,"hidden ring unchanged")
   fx.update_state(.4,true,true,false,1.0,0)
   check(fx.target_ring.visible and fx.active_ring.visible,"visible selection")
   var scale=fx.target_outer.scale
   fx.update_state(1.1,true,true,false,1.0,0)
   check(fx.target_outer.scale!=scale,"pulse retained")
   fx.update_state(1.1,false,false,false,2.0,0)
   check(is_equal_approx(fx._last_shadow_radius,32.0),"resize updates radius")
   var engine_ref=weakref(battle.engine)
   var screen_ref=weakref(battle)
   var actor_ref=weakref(actor)
   battle._claim(false)
   for i in range(12):await process_frame
   check(router.active_combat==null and screen_ref.get_ref()==null and actor_ref.get_ref()==null,"screen released "+group)
   await create_timer(.9).timeout
   check(engine_ref.get_ref()==null,"engine released "+group)
   print("COMBAT PROFILE ",cycle+1," ",group," nodes=",int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))," orphans=",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
 check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))<=initial_nodes+2,"node count stable")
 check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==initial_orphans,"orphan count stable")
 current_scene.queue_free()
 for i in range(6):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.5).timeout
 print("COMBAT PROFILE RESULT ",errors)
 quit(0 if errors.is_empty() else 1)
