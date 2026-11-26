extends SceneTree
func _initialize():call_deferred("run")
func fail(message:String):
 push_error("DAILY QUEST FAIL "+message)
 quit(1)
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 var reward=gs.reward_domain
 gs.daily_quests={}
 gs.daily_rewards={}
 gs.quest_domain.flags["tutorial_complete"]=false
 if reward.daily_quest_status().enabled or reward.claim_daily_quest("blessing"):fail("tutorial lock");return
 gs.quest_domain.flags["tutorial_complete"]=true
 var menu=load("res://scenes/ui/main_menu.tscn").instantiate()
 root.add_child(menu)
 await process_frame
 var button=menu.get_node("ReferenceInterface/LeftRail/EventsButton")
 if button.get_node("Notification").visible:fail("early badge");return
 var result=gs.claim_daily_reward()
 if not result.ok:fail("daily blessing");return
 menu._refresh_menu_notifications()
 if not button.get_node("Notification").visible:fail("ready badge");return
 button.pressed.emit()
 await process_frame
 var journal=menu.get_node_or_null("DailyQuestsOverlay")
 if journal==null:fail("journal route");return
 if DisplayServer.get_name()!="headless":
  for i in range(5):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_daily_quests_preview.png")
 var gold=gs.currency("gold")
 var crystals=gs.currency("crystals")
 journal._layout.get_node("Scroll/Rows/Blessing/Row/Reward/Claim").pressed.emit()
 if gs.currency("gold")!=gold+150 or reward.claim_daily_quest("blessing"):fail("one-time claim");return
 for i in range(3):
  reward.apply_battle_result("rose_slime_garden_1",true)
 reward.record_daily_victory("rose_slime_garden_1")
 reward.record_daily_visit("StandaloneZone01")
 reward.record_daily_visit("StandaloneZone01")
 var status=reward.daily_quest_status()
 if status.rows[1].progress!=3 or status.rows[2].progress!=1:fail("progress cap or unique area");return
 reward.record_daily_visit("StandaloneZone02")
 if reward.claim_daily_quest("bonus"):fail("premature bonus");return
 var snapshot=gs._to_dict()
 if snapshot.daily_quests.regions.size()!=2 or not "blessing" in snapshot.daily_quests.claimed:fail("serialization");return
 gs.daily_quests={}
 gs._load_from_dict(snapshot)
 if reward.daily_quest_status().rows[2].progress!=2:fail("restore");return
 gold=gs.currency("gold")
 crystals=gs.currency("crystals")
 if not reward.claim_daily_quest("victories") or not reward.claim_daily_quest("explore") or not reward.claim_daily_quest("bonus"):fail("all claims");return
 if reward.claim_daily_quest("bonus") or gs.currency("gold")!=gold+1050 or gs.currency("crystals")!=crystals+140:fail("bonus payout");return
 menu._refresh_menu_notifications()
 if button.get_node("Notification").visible:fail("badge clear");return
 var gateway=root.get_node("MultiplayerGateway")
 gateway.standalone_expedition_id="qa"
 if reward.daily_quest_status().enabled:fail("online lock");return
 gateway.standalone_expedition_id=""
 gs.daily_quests.date="2000-01-01"
 gs.daily_rewards.last_claim_date="2000-01-01"
 var tomorrow=reward.daily_quest_status()
 if tomorrow.rows[0].progress!=0 or tomorrow.rows[1].progress!=0 or tomorrow.rows[2].progress!=0 or tomorrow.rows[3].claimed:fail("reset");return
 journal.close_screen()
 await process_frame
 var quest=load("res://scenes/ui/quest_screen.tscn").instantiate()
 root.add_child(quest)
 await process_frame
 quest._open_daily_quests()
 await process_frame
 if not quest.has_node("DailyQuestsOverlay"):fail("quest journal route");return
 print("DAILY_QUESTS_PASS tutorial gate, real reward hooks, distinct visits, caps, save restore, claim once, exact rewards, bonus, daily reset, menu badge, both routes and co-op isolation")
 menu.queue_free();quest.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.4).timeout
 quit(0)