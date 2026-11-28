extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var gs=root.get_node("GameState")
 gs.new_game("Cassien QA")
 gs.quest_domain.flags["tutorial_complete"]=true
 gs.quest_domain.flags["discovered_fast_travel_zones"]=["StandaloneVillage","StandaloneZone01","StandaloneZone02","StandaloneZone03","StandaloneZone04"]
 change_scene_to_file("res://scenes/world/six_zone_reverie/individual_zones/zone_05_forsaken_ruins_standalone.tscn")
 await scene_changed
 for i in range(5): await physics_frame
 var zone=current_scene
 var player=zone.checkpoint_player
 var exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 var cassien=zone.get_node("CassienRitual")
 var dialog=zone.get_node("UI/Dialogue")
 var braziers=zone.get_node("RuinsBraziers").get_children()
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="active")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 assert(not exit._story_unlocked())
 for b in braziers: assert(not b.can_interact())
 player.global_position=cassien.global_position+Vector2(0,90)
 var visual=cassien.get_node("CassienVisual") as AnimatedSprite2D
 assert(visual.sprite_frames.get_frame_count(&"kneeling_idle")==8)
 assert(visual.sprite_frames.get_frame_count(&"awakening")==16)
 assert(visual.sprite_frames.get_animation_loop(&"kneeling_idle"))
 assert(not visual.sprite_frames.get_animation_loop(&"awakening"))
 assert(visual.animation==&"kneeling_idle" and visual.is_playing())
 cassien.interact()
 assert(visual.animation==&"awakening" and not player.input_enabled and not dialog.visible)
 assert(zone.get_node("ZoneUIBinding")._travel_or_combat_busy())
 assert(zone.get_meta("cassien_ritual_active",false))
 await visual.animation_finished
 await process_frame
 assert(visual.frame==15 and not visual.is_playing())
 assert(dialog.visible and not player.input_enabled)
 print("CASSIEN 8-FRAME IDLE AND 16-FRAME AWAKENING PASS")
 dialog.close()
 assert(player.input_enabled and gs.quest_domain.quest_step_index("cassien_resurrection")==0)
 assert(not zone.get_meta("cassien_ritual_active",false))
 cassien.interact()
 assert(dialog.visible and dialog._dialogue_id=="cassien_meeting")
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 for i in range(120):
  if zone.get_node_or_null("UI/Overlays/CrimsonOathMemory")!=null: break
  await process_frame
 var memory=zone.get_node_or_null("UI/Overlays/CrimsonOathMemory")
 assert(memory!=null and not player.input_enabled)
 memory.get_node("SkipButton").pressed.emit()
 for i in range(600):
  if dialog.visible and dialog._dialogue_id=="cassien_tomb_approach": break
  await process_frame
 assert(dialog.visible and dialog._dialogue_id=="cassien_tomb_approach")
 assert(gs.quest_domain.flags.get("cassien_crimson_oath_part_1_seen",false))
 dialog._choose(dialog._node.choices[0])
 assert(dialog.visible)
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 var cassien_battle=zone.get_node("CombatRouter").active_combat
 assert(cassien_battle!=null and cassien_battle.group_id=="cassien_encounter")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 cassien_battle._claim(true)
 for i in range(120):
  if dialog.visible and dialog._dialogue_id=="cassien_after_victory": break
  await process_frame
 assert(dialog.visible and dialog._dialogue_id=="cassien_after_victory")
 assert(gs.quest_domain.flags.get("cassien_crimson_oath_part_2_pending",false))
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 dialog._show_node("oath")
 dialog.close()
 for i in range(120):
  if zone.get_node_or_null("UI/Overlays/CrimsonOathMemory")!=null: break
  await process_frame
 var second_memory=zone.get_node_or_null("UI/Overlays/CrimsonOathMemory")
 assert(second_memory!=null and not player.input_enabled)
 second_memory.get_node("SkipButton").pressed.emit()
 for i in range(600):
  if gs.quest_domain.quest_state("forsaken_braziers")=="active" and player.input_enabled: break
  await process_frame
 assert(gs.quest_domain.flags.get("cassien_crimson_oath_part_2_seen",false))
 assert(not gs.quest_domain.flags.get("cassien_crimson_oath_part_2_pending",false))
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="active")
 assert(not cassien.can_interact())
 for b in braziers:
  player.global_position=b.global_position+Vector2(0,65)
  b.interact()
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="complete")
 assert(cassien.can_interact() and not exit._story_unlocked())
 player.global_position=cassien.global_position+Vector2(0,90)
 cassien.interact()
 assert(dialog._dialogue_id=="cassien_ritual")
 dialog._show_node("awakening")
 dialog.close()
 assert(not gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not exit._story_unlocked())
 cassien.interact()
 dialog._show_node("awakening")
 assert(dialog._node.speaker=="Ravienna")
 dialog._show_node("fracture")
 dialog._show_node("departure")
 dialog._choose(dialog._node.choices[0])
 await zone.get_node("CassienRitual").departure_finished
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="complete")
 assert(gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(exit._story_unlocked())
 print("CASSIEN MEETING, BRAZIER PREPARATION, CANCELLATION, RESURRECTION, ROAD PASS")
 change_scene_to_file(zone.scene_file_path)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 exit=zone.get_node("TransferPoints/ToNextZone/ToNextZoneTrigger")
 assert(exit._story_unlocked() and not zone.get_node("CassienRitual").can_interact())
 exit._on_body_entered(zone.checkpoint_player)
 await scene_changed
 for i in range(5): await physics_frame
 zone=current_scene
 assert(zone.name==&"StandaloneZone06")
 var ravienna=zone.get_node("ReviennaEncounter")
 player=zone.checkpoint_player
 player.global_position=ravienna.global_position+Vector2(0,120)
 ravienna.interact()
 dialog=zone.get_node("UI/Dialogue")
 assert(dialog.visible and dialog._dialogue_id=="revienna_challenge")
 dialog._show_node("reply")
 assert("Cassien and I brought you back" in dialog._node.text)
 dialog._show_node("warning")
 dialog._choose(dialog._node.choices[0])
 for i in range(20): await process_frame
 assert(zone.get_node("CombatRouter").active_combat!=null)
 print("PERSISTENT RITUAL, RAVIENNA DIALOGUE AND BOSS LAUNCH PASS")
 zone.get_node("CombatRouter").active_combat._claim(false)
 await process_frame
 current_scene.queue_free()
 for i in range(3): await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(0.35).timeout
 quit()
