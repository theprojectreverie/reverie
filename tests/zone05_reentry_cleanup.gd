extends SceneTree
const FIVE="res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn"
const SIX="res://scenes/world/six_zone_reverie/individual_zones/zone_06_ruined_tower_standalone.tscn"
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["ravienna_resurrected"]=true
 var failures:Array[String]=[]
 for cycle in range(4):
  change_scene_to_file(FIVE)
  await scene_changed
  for f in range(8): await process_frame
  var zone=current_scene
  var zone_ref=weakref(zone)
  var player_ref=weakref(zone.checkpoint_player)
  var decoration=zone.get_node("RuinsDecoration")
  var count=decoration.get_child_count()
  if not decoration.has_node("FarRubble") or not decoration.has_node("FarArchRubble"):
   failures.append("Missing rubble nodes")
  if not zone.checkpoint_player.has_node("FairyCompanion"):
   failures.append("Missing companion")
  if get_nodes_in_group("player").size()!=1:
   failures.append("Duplicate player")
  change_scene_to_file(SIX)
  await scene_changed
  for f in range(12): await process_frame
  if zone_ref.get_ref()!=null or player_ref.get_ref()!=null:
   failures.append("Zone 5/player retained after exit")
  if get_nodes_in_group("player").size()!=1:
   failures.append("Duplicate player in Zone 6")
  print("TRANSITION CYCLE ",cycle+1," decoration count ",count," orphans ",Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
 print("REPEATED TRANSITIONS ", "PASS" if failures.is_empty() else str(failures))
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit(0 if failures.is_empty() else 1)
