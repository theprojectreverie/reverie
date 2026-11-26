extends SceneTree
var gs
var save
var cp
var failures=[]
func _initialize():call_deferred("_run")
func check(ok:bool,label:String):
 print("SAVE QA ",label," ",ok)
 if not ok:failures.append(label)
func frames(n:int):
 for i in range(n):await physics_frame
func finish_quest(id:String):
 gs.quest_domain.start_quest(id)
 var n=0
 while not gs.quest_domain.quest_ready(id) and n<12:
  gs.quest_domain.advance_quest(id)
  n+=1
 gs.quest_domain.complete_quest(id)
func mount(id:String):
 change_scene_to_file(cp.SCENES[id])
 await scene_changed
 await frames(8)
func disk_reload(id:String):
 var z=current_scene
 var p=z.checkpoint_player
 var pos=p.position
 cp.capture(z,p,true)
 gs.save_now()
 var data=save.load_save()
 check(not data.is_empty() and str(data.flags.get("six_zone_checkpoint",{}).get("zone",""))==id,id+" disk checkpoint")
 if data.is_empty():return
 var gold=int(gs.profile.gold)
 var quests=JSON.parse_string(JSON.stringify(gs.quests))
 var party=gs.party.duplicate()
 var roster_count=gs.roster.size()
 var flags=gs.flags.duplicate(true)
 z.queue_free()
 await process_frame
 await process_frame
 gs.new_game("Temporary QA reset")
 # Restore the independently parsed disk snapshot, not retained GameState dictionaries.
 gs._load_from_dict(data)
 check(gs.profile.name=="Story Save QA" and int(gs.profile.gold)==gold,id+" wallet and profile")
 check(gs.quests==quests,id+" quests")
 check(gs.party==party and gs.roster.size()==roster_count,id+" roster")
 check(gs.flags==flags,id+" story flags")
 check(cp.resume_scene()==cp.SCENES[id],id+" resume destination")
 await mount(id)
 check(current_scene.checkpoint_player.position.distance_to(pos)<3,id+" restored position")
 check(current_scene.checkpoint_player.has_node("FairyCompanion"),id+" companion")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1" or not OS.get_user_data_dir().to_lower().contains("reverie_save_qa_"):
  push_error("Unsafe test path")
  quit(2)
  return
 gs=root.get_node("GameState")
 save=root.get_node("SaveService")
 cp=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
 save.SAVE_PATH="user://story_milestone_qa.json"
 save.BACKUP_PATH="user://story_milestone_qa.corrupt.json"
 OS.set_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE","0")
 gs.new_game("Story Save QA")
 gs.flags["tutorial_complete"]=true
 await mount("StandaloneVillage")
 gs.flags["village_gerald_defeated"]=true
 gs.flags["village_gerald_backstory_pending"]=true
 await disk_reload("StandaloneVillage")
 await frames(20)
 check(current_scene.get_node("UI/Dialogue").visible and not current_scene.checkpoint_player.input_enabled,"Gerald pending story resumes")
 gs.flags["village_gerald_backstory_pending"]=false
 gs.flags["village_gerald_backstory_seen"]=true
 await mount("StandaloneZone01")
 gs.quest_domain.start_quest("elathra_first_audience")
 gs.quest_domain.advance_quest("elathra_first_audience")
 await disk_reload("StandaloneZone01")
 check(gs.quest_domain.quest_step_index("elathra_first_audience")==1,"Elathra partial quest")
 finish_quest("elathra_first_audience")
 await mount("StandaloneZone02")
 gs.quest_domain.advance_quest("royal_gate_patrol")
 gs.quest_domain.complete_quest("royal_gate_patrol")
 await disk_reload("StandaloneZone02")
 check(current_scene.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")._story_unlocked(),"Royal Gate remains open")
 await mount("StandaloneZone03")
 gs.quest_domain.advance_quest("willow_crossing")
 await disk_reload("StandaloneZone03")
 check(gs.quest_domain.quest_step_index("willow_crossing")==1,"Willow partial quest")
 finish_quest("willow_crossing")
 await mount("StandaloneZone04")
 gs.quest_domain.advance_quest("elderwood_relics")
 await disk_reload("StandaloneZone04")
 check(gs.quest_domain.quest_step_index("elderwood_relics")==1,"Elderwood partial quest")
 finish_quest("elderwood_relics")
 await mount("StandaloneZone05")
 gs.flags["cassien_defeated"]=true
 gs.quest_domain.advance_quest("cassien_resurrection")
 gs.quest_domain.start_quest("forsaken_braziers")
 gs.quest_domain.advance_quest("forsaken_braziers")
 await disk_reload("StandaloneZone05")
 var cassien=current_scene.get_node("CassienRitual")
 check(cassien.global_position==current_scene.get_node("CassienTombPosition").global_position,"Cassien restored at tomb")
 check(gs.quest_domain.quest_step_index("forsaken_braziers")==1 and not cassien.can_interact(),"Ritual preparation retained")
 finish_quest("forsaken_braziers")
 finish_quest("cassien_resurrection")
 gs.flags["ravienna_resurrected"]=true
 await disk_reload("StandaloneZone05")
 check(current_scene.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")._story_unlocked(),"Tower road remains open")
 await mount("StandaloneZone06")
 gs.flags["revienna_defeated"]=true
 gs.flags["ravienna_ending_pending"]=true
 await disk_reload("StandaloneZone06")
 var r=current_scene.get_node("ReviennaEncounter")
 check(r.can_interact() and r._ending_pending(),"Final dialogue remains available")
 gs.flags.erase("ravienna_ending_pending")
 gs.flags["ravienna_ending_seen"]=true
 await disk_reload("StandaloneZone06")
 check(not current_scene.get_node("ReviennaEncounter").can_interact(),"Final boss stays defeated")
 gs.save_now()
 print("STORY DISK MILESTONES RESULT ",failures)
 current_scene.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 OS.set_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE","1")
 quit(0 if failures.is_empty() else 1)
