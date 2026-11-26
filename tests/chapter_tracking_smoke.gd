extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var nav=load("res://scripts/world/six_zone_reverie/chapter_navigation.gd")
 var gs=root.get_node("GameState")
 var d=gs.quest_domain
 d.flags["tutorial_complete"]=true
 var transfer=load("res://scripts/world/six_zone_reverie/zone_transfer_trigger.gd")
 var paths=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd").SCENES
 var zones=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04","StandaloneZone05","StandaloneZone06"]
 var ids=["gerald_story","elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics","cassien_resurrection","ravienna_finale"]
 for i in range(zones.size()):
  transfer.pending_arrival=&"ToPreviousZone" if i>=2 else &""
  change_scene_to_file(paths[zones[i]])
  await scene_changed
  for f in range(5): await physics_frame
  var zone=current_scene
  var player=zone.checkpoint_player
  var hud=zone.get_node("UI/HUD")
  hud.refresh_quest()
  var guide=zone.get_meta("chapter_navigation",{})
  print("GUIDE ",zone.name," ",guide)
  assert(guide.get("valid",false) and not guide.portal and guide.quest_id==ids[i])
  await process_frame
  var beacon=zone.get_node("ChapterQuestBeacon")
  beacon._process(0.0)
  print("BEACON ",beacon.visible," ",beacon.global_position," player_input=",player.input_enabled)
  assert(beacon.visible and beacon.global_position.is_equal_approx(guide.position))
  var pos:Vector2=guide.position
  player.position+=Vector2(40,0)
  hud.refresh_quest()
  var updated=zone.get_meta("chapter_navigation")
  assert(is_equal_approx(updated.distance,player.global_position.distance_to(updated.position)))
  if i==1:
   assert(not nav.can_track(zone,"glade_whisper"))
   assert(not nav.can_track(zone,"elderwood_relics"))
   var router=zone.get_node("OverlayRouter")
   assert(router.open_screen("quests"))
   await process_frame
   var journal=router.active_overlay
   assert(journal._cards.size()==8 and not journal._cards.has("glade_whisper"))
   router.active_overlay.queue_free()
   router.active_overlay=null
   await process_frame
   d.flags["chapter_tracking_paused"]=true
   hud.refresh_quest()
   assert(not hud._quest_label.visible and zone.get_meta("chapter_navigation").is_empty())
   d.flags.erase("chapter_tracking_paused")
  if i==2:
   var target=updated.position
   for n in get_nodes_in_group("world_minimap_monsters"):
    if n is Node2D and zone.is_ancestor_of(n) and n.global_position.is_equal_approx(target):
     n.defeated=true
     break
   hud.refresh_quest()
   assert(zone.get_meta("chapter_navigation").position!=target)
  if i==3 or i==4:
   d.advance_quest(ids[i])
   hud.refresh_quest()
   assert(zone.get_meta("chapter_navigation").position!=pos)
  if i==5:
   d.advance_quest("cassien_resurrection")
   d.start_quest("forsaken_braziers")
   hud.refresh_quest()
   assert(zone.get_meta("chapter_navigation").quest_id=="forsaken_braziers")
   for j in range(3):d.advance_quest("forsaken_braziers")
   assert(d.complete_quest("forsaken_braziers"))
   hud.refresh_quest()
   assert(zone.get_meta("chapter_navigation").quest_id=="cassien_resurrection")
  if i==0:
   d.flags["village_gerald_defeated"]=true
   assert(nav.journal_step_index("gerald_story")==1)
   d.flags["village_gerald_backstory_seen"]=true
   assert(nav.journal_state(zone,"gerald_story")=="complete")
  elif i==6:
   d.flags["revienna_defeated"]=true
   hud.refresh_quest()
   assert("finish the story" in zone.get_meta("chapter_navigation").text)
   d.flags["ravienna_ending_seen"]=true
   assert(nav.journal_state(zone,"ravienna_finale")=="complete")
  else:
   if d.quest_state(ids[i])=="not_started":d.start_quest(ids[i])
   for step in range(8):
    if d.quest_state(ids[i])!="active" or d.quest_ready(ids[i]):break
    d.advance_quest(ids[i])
   if d.quest_state(ids[i])!="complete":assert(d.complete_quest(ids[i]))
  hud.refresh_quest()
  var next=zone.get_meta("chapter_navigation")
  if i<6:
   assert(next.get("portal",false) and next.destination==i+1 and next.valid)
  else:
   assert(next.is_empty())
  print("GUIDE_STAGE_PASS ",zone.name)
 current_scene.queue_free()
 for f in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 print("CHAPTER_TRACKING PASS")
 quit(0)
