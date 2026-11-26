extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
  quit(2)
  return
 var mobile=OS.get_environment("REVERIE_RITUAL_MOBILE")=="1"
 if mobile: root.size=Vector2i(390,844)
 var suffix="mobile" if mobile else "desktop"
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
 dialog._show_node("oath")
 dialog._choose(dialog._node.choices[0])
 await process_frame
 await process_frame
 var cassien_battle=zone.get_node("CombatRouter").active_combat
 assert(cassien_battle!=null and cassien_battle.group_id=="cassien_encounter")
 assert(gs.quest_domain.quest_state("forsaken_braziers")=="not_started")
 cassien_battle._claim(true)
 await process_frame
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
 var ritual_sprite=zone.get_node("RaviennaCourtyard/RaviennaStoneTomb/ReviennaRitualVisual")
 var continue_button=dialog.get_node("DialoguePanel/ContentRow/TextColumn/Footer/ContinueButton")
 assert(ritual_sprite.visible and ritual_sprite.animation==&"resurrection" and ritual_sprite.frame==0)
 assert(ritual_sprite.sprite_frames.get_frame_count(&"resurrection")==12)
 assert(ritual_sprite.sprite_frames.get_frame_count(&"possession")==12)
 dialog._show_node("awakening")
 assert(continue_button.disabled and ritual_sprite.is_playing())
 await create_timer(0.45).timeout
 dialog._on_continue()
 assert(dialog._node_id=="awakening" and continue_button.disabled)
 dialog.close()
 assert(not ritual_sprite.visible and not continue_button.disabled)
 assert(not gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(not exit._story_unlocked())
 cassien.interact()
 dialog._show_node("awakening")
 await ritual_sprite.animation_finished
 dialog._show_node("fracture")
 await create_timer(0.6).timeout
 assert(ritual_sprite.is_playing() and continue_button.disabled)
 dialog.close()
 assert(not ritual_sprite.visible and not continue_button.disabled and player.input_enabled)
 assert(not gs.quest_domain.flags.get("ravienna_resurrected",false) and not exit._story_unlocked())
 cassien.interact()
 dialog._finish_typing()
 continue_button.pressed.emit()
 assert(dialog._node.speaker=="Ravienna")
 assert(continue_button.disabled)
 await ritual_sprite.animation_finished
 await process_frame
 assert(ritual_sprite.visible and ritual_sprite.frame==11 and not continue_button.disabled)
 await RenderingServer.frame_post_draw
 print("HUMAN RESURRECTION CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_revienna_resurrection_"+suffix+".png"))
 dialog._finish_typing()
 continue_button.pressed.emit()
 assert(continue_button.disabled and ritual_sprite.animation==&"possession")
 var original_size=root.size
 if mobile: root.size=Vector2i(844,390)
 else: root.size=Vector2i(390,844)
 for i in range(4): await process_frame
 assert(dialog.ritual_portrait_layout!=mobile and ritual_sprite.is_playing())
 root.size=original_size
 for i in range(4): await process_frame
 assert(dialog.ritual_portrait_layout==mobile and continue_button.disabled)
 await create_timer(1.0).timeout
 await RenderingServer.frame_post_draw
 print("POSSESSION CAPTURE ",root.get_texture().get_image().save_png("C:/Users/quoth/Downloads/reverie_revienna_possession_"+suffix+".png"))
 await ritual_sprite.animation_finished
 await process_frame
 assert(ritual_sprite.frame==11 and not continue_button.disabled and not player.input_enabled)
 dialog._finish_typing()
 continue_button.pressed.emit()
 assert(dialog._node_id=="departure")
 await create_timer(0.8).timeout
 assert(ritual_sprite.visible and ritual_sprite.frame==11)
 print("RESURRECTION 12 FRAMES, POSSESSION 12 FRAMES, TWO CANCELLATIONS, ROTATION AND DEPARTURE PASS")
 dialog._finish_typing()
 await process_frame
 var choice=dialog.get_node("DialoguePanel/ContentRow/TextColumn/ChoicesBox").get_child(0)
 var panel=dialog.get_node("DialoguePanel")
 assert(choice.get_global_rect().end.x<=panel.get_global_rect().end.x+1)
 assert(choice.get_global_rect().end.y<=root.get_visible_rect().end.y+1)
 assert(dialog.ritual_portrait_layout==mobile)
 choice.pressed.emit()
 await cassien.departure_finished
 assert(player.input_enabled and not ritual_sprite.visible and not continue_button.disabled)
 assert(root.get_camera_2d()==player.get_node("Camera2D") and zone.get_node("UI/HUD").visible)
 assert(gs.quest_domain.quest_state("cassien_resurrection")=="complete")
 assert(gs.quest_domain.flags.get("ravienna_resurrected",false))
 assert(exit._story_unlocked())
 print("CASSIEN MEETING, BRAZIER PREPARATION, CANCELLATION, RESURRECTION, ROAD PASS")

 var ritual_ref=weakref(cassien)
 var visual_ref=weakref(ritual_sprite)
 var zone_ref=weakref(zone)
 current_scene.queue_free()
 for i in range(12):await process_frame
 assert(ritual_ref.get_ref()==null and visual_ref.get_ref()==null and zone_ref.get_ref()==null)
 print("RITUAL SCENE AND VISUAL RELEASE PASS")
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(1.5).timeout
 quit()
