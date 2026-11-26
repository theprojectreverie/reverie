extends SceneTree
const QA_ID="12345678-1234-4234-8234-123456789abc"
var gs
var svc
var cp
var mode:String
var scenario:String
var zone_id:String
var expected_region:String
var identity={"id":QA_ID,"name":"Restart QA"}
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1" or not OS.get_user_data_dir().to_lower().contains("reverie_restart_qa_"):
  push_error("Unsafe QA directory")
  quit(2)
  return
 gs=root.get_node("GameState")
 svc=root.get_node("SaveService")
 cp=load("res://scripts/world/six_zone_reverie/six_zone_checkpoint.gd")
 mode=OS.get_environment("REVERIE_QA_MODE")
 scenario=OS.get_environment("REVERIE_QA_SCENARIO")
 zone_id={"gerald":"StandaloneVillage","cassien":"StandaloneZone05","ravienna":"StandaloneZone06","finished":"StandaloneZone06"}[scenario]
 expected_region={"gerald":"greenward","cassien":"forsaken_ruins","ravienna":"gothic_castle_boss_zone","finished":"gothic_castle_boss_zone"}[scenario]
 if mode=="seed":
  gs.lifecycle_component.switch_player(true,identity)
  OS.set_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE","0")
  gs.new_game("Restart QA")
  gs.flags["tutorial_complete"]=true
  gs.flags["village_gerald_defeated"]=true
  gs.flags["village_gerald_backstory_pending"]=scenario=="gerald"
  gs.flags["village_gerald_backstory_seen"]=scenario!="gerald"
  if scenario!="gerald":
   for id in ["elathra_first_audience","royal_gate_patrol","willow_crossing","elderwood_relics"]:
    finish_quest(id)
   gs.flags["cassien_defeated"]=true
   gs.quest_domain.start_quest("cassien_resurrection")
   gs.quest_domain.advance_quest("cassien_resurrection")
   gs.quest_domain.start_quest("forsaken_braziers")
   gs.quest_domain.advance_quest("forsaken_braziers")
   if scenario!="cassien":
    finish_quest("forsaken_braziers")
    finish_quest("cassien_resurrection")
    gs.flags["ravienna_resurrected"]=true
    gs.flags["revienna_defeated"]=true
    gs.flags["ravienna_ending_pending"]=scenario=="ravienna"
    gs.flags["ravienna_ending_seen"]=scenario=="finished"
  change_scene_to_file(cp.SCENES[zone_id])
  await scene_changed
  for i in range(12):await physics_frame
  cp.capture(current_scene,current_scene.checkpoint_player,true)
  gs.save_now()
  assert(svc.has_save() and not svc.load_save().is_empty())
  print("RESTART SEED PASS ",scenario," ",OS.get_process_id()," ",svc.SAVE_PATH)
  OS.set_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE","1")
 else:
  # Simulate only the post-login identity in an isolated process. No remote login.
  var auth=root.get_node("AuthGateway")
  auth.api_base_url="http://127.0.0.1:1"
  auth.set_process(false)
  auth._access_token="local-qa-only"
  auth._access_token_expires_at=Time.get_unix_time_from_system()+3600
  auth._player=identity.duplicate(true)
  gs.lifecycle_component.switch_player(true,identity)
  assert(gs.loaded_from_save and gs.profile.name=="Restart QA")
  var stored=svc.load_save()
  assert(not stored.is_empty() and stored.flags.six_zone_checkpoint.zone==zone_id)
  assert(gs.player_region==expected_region)
  change_scene_to_file("res://scenes/main.tscn")
  await scene_changed
  var host=current_scene
  var title=host.get_node("TitleScreen")
  var button=title.get_node("ContinueButton")
  assert(not button.disabled)
  button.pressed.emit()
  var deadline=Time.get_ticks_msec()+20000
  while not host.has_node("MainMenu") and Time.get_ticks_msec()<deadline:await process_frame
  assert(host.has_node("MainMenu"),"Continue failed")
  var menu=host.get_node("MainMenu")
  menu.get_node("ReferenceInterface/BottomNavigation/StoryButton").pressed.emit()
  assert(gs.player_region==expected_region,"Story changed saved region before load")
  deadline=Time.get_ticks_msec()+20000
  while current_scene==host and Time.get_ticks_msec()<deadline:await process_frame
  assert(current_scene!=null and current_scene.name==zone_id)
  for i in range(30):await physics_frame
  var z=current_scene
  var checkpoint=stored.flags.six_zone_checkpoint
  assert(z.checkpoint_player.position.distance_to(Vector2(checkpoint.x,checkpoint.y))<3)
  assert(z.checkpoint_player.has_node("FairyCompanion"))
  assert(gs.player_region==expected_region and int(gs.profile.gold)==int(stored.profile.gold))
  if scenario=="gerald":
   assert(z.get_node("UI/Dialogue").visible and not z.checkpoint_player.input_enabled)
  elif scenario=="cassien":
   assert(gs.quest_domain.quest_step_index("forsaken_braziers")==1)
   assert(z.get_node("CassienRitual").global_position==z.get_node("CassienTombPosition").global_position)
  else:
   var boss=z.get_node("ReviennaEncounter")
   assert(boss.can_interact()==(scenario=="ravienna"))
   assert(boss._ending_pending()==(scenario=="ravienna"))
  print("REAL RESTART CONTINUE STORY PASS ",scenario," ",OS.get_process_id()," ",zone_id)
 if is_instance_valid(current_scene):current_scene.queue_free()
 for i in range(3):await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.35).timeout
 quit()
func finish_quest(id:String):
 gs.quest_domain.start_quest(id)
 for i in range(12):
  if gs.quest_domain.quest_ready(id):break
  gs.quest_domain.advance_quest(id)
 gs.quest_domain.complete_quest(id)
