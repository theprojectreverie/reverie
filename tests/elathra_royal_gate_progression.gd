extends SceneTree
var failures: Array[String] = []
func _initialize():
 call_deferred("_run")
func check(ok: bool, label: String):
 print("CHECK ",label," = ",ok)
 if not ok: failures.append(label)
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["village_gerald_defeated"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage"]
 gs.quest_domain.quests.erase("elathra_first_audience")
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_01_royal_gardens_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.get("checkpoint_player")
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var label=zone.get_node("TransferPoints/ToNextZone/ContinuationMarker/DestinationName")
 var npc=zone.get_node("Zone/RoyalGardenV3Decorations/Elathra")
 var dialogue=zone.get_node("NPCDialogueLayer/Dialogue")
 check(not exit._story_unlocked() and label.text=="Speak to Elathra first","initial quest gate locked")
 exit._on_body_entered(player)
 check(not exit.transferring,"cannot bypass by road")
 player.global_position=npc.global_position+Vector2(0,65)
 npc.interact()
 await process_frame
 check(dialogue.visible and not player.input_enabled,"Elathra dialogue locks movement")
 dialogue._choose({"next":""})
 await process_frame
 check(not dialogue.visible and player.input_enabled,"declining restores movement")
 check(not exit._story_unlocked(),"declining leaves route locked")
 npc.interact()
 await process_frame
 dialogue._choose(dialogue._node.choices[0])
 check(gs.quest_domain.quest_state("elathra_first_audience")=="active","quest accepted")
 check(not exit._story_unlocked(),"acceptance alone not enough")
 dialogue._choose(dialogue._node.choices[0])
 check(gs.quest_domain.quest_state("elathra_first_audience")=="complete","quest completed through dialogue")
 exit._on_body_entered(player)
 check(not exit.transferring,"no travel during dialogue")
 dialogue._choose(dialogue._node.choices[0])
 for i in range(5): await physics_frame
 check(player.input_enabled and exit._story_unlocked() and label.text=="Royal Gate","route unlocks after dialogue")
 exit._on_body_entered(player)
 await scene_changed
 for i in range(5): await physics_frame
 check(current_scene.name==&"StandaloneZone02","Royal Gate loaded")
 check(current_scene.get("checkpoint_player").has_node("FairyCompanion"),"companion retained")
 check(gs.quest_domain.quest_state("elathra_first_audience")=="complete","completed quest retained")
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
