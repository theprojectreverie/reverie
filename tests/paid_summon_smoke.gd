extends SceneTree
func _initialize():call_deferred("run")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState");gs.new_game("Paid summon QA")
 var db=root.get_node("ContentDB");var service=load("res://scripts/gacha/gacha_service.gd")
 var ids=db.banners.keys();assert(ids.size()>1)
 for id in ids:
  var rng=RandomNumberGenerator.new();rng.seed=42
  var outcome=service.pull(db.get_banner(id),rng,service.empty_pity(),10,90)
  assert(outcome.results.size()==10 and outcome.results[9].paid_guaranteed and outcome.results[9].rarity in ["legendary","mythic"] and not outcome.results[9].has("kind"))
  var crossed=service.pull(db.get_banner(id),rng,service.empty_pity(),10,97)
  assert(crossed.results[2].paid_guaranteed)
 print("LOCAL ALL BANNERS MILESTONE PASS")
 gs.profile["paid_moonstones"]=12000;gs.profile["crystals"]=2400
 for i in range(9):
  var result=gs.reward_domain.pull_banner(ids[i%ids.size()],10,true)
  assert(result.ok and gs.profile.paid_summon_progress==(i+1)*10)
  assert(result.results.filter(func(r):return r.get("paid_guaranteed",false)).is_empty())
 var normal=gs.reward_domain.pull_banner(ids[0],10)
 assert(normal.ok and gs.profile.paid_summon_progress==90)
 var snapshot=gs._to_dict().duplicate(true)
 gs.profile["paid_summon_progress"]=0;gs._load_from_dict(snapshot)
 assert(gs.profile.paid_summon_progress==90)
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate();root.add_child(gacha);await process_frame
 assert(gacha.paid_summon_progress()==90)
 var paid=gacha.find_child("PaidPull10",true,false);assert(paid!=null and not paid.disabled)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/paid_summon_preview.png")
 var final=gs.reward_domain.pull_banner(ids[1],10,true)
 assert(final.ok and final.results[9].paid_guaranteed and gs.profile.paid_summon_progress==0)
 assert(gs.currency("paid_moonstones")==0 and gs.currency("crystals")==1200)
 assert(not gs.reward_domain.pull_banner(ids[0],1,true).ok)
 gacha._refresh();await process_frame
 assert(gacha.find_child("PaidPull10",true,false).disabled)
 var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate();root.add_child(card);card.setup(final.results[9]);assert(card.get_node("Content/Status").text.contains("PAID MILESTONE"))
 card.queue_free();gacha.queue_free();await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout
 print("PAID LOCAL PASS: 100 pulls, save restore, free exclusion, exact balance, insufficient funds, UI controls and result label")
 quit(0)
