extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var db=root.get_node("ContentDB")
 var gs=root.get_node("GameState")
 assert(db.validation_errors.is_empty())
 for id in db.characters:
  assert(db.characters[id].rarity!="common")
 var banner=db.get_banner("crimson_covenant")
 var old_rates=banner.rates.duplicate()
 banner.rates={"common":1.0,"rare":0.0,"epic":0.0,"legendary":0.0,"mythic":0.0}
 var old_roster=gs.roster.size()
 var materials={}
 for id in ["moonpetal","dew_of_awakening","gothic_shard"]:materials[id]=gs.inventory_domain.item_count(id)
 var result=gs.reward_domain.pull_banner("crimson_covenant",10)
 banner.rates=old_rates
 assert(result.ok and result.results.size()==10 and result.results[9].rarity=="epic")
 for i in range(9):
  var roll=result.results[i]
  assert(roll.kind=="mob_reward" and db.get_character(roll.character_id)==null)
  assert(not gs.roster_domain.add_character(roll.character_id).has("instance"))
  for id in roll.items:materials[id]+=int(roll.items[id])
  var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
  card.setup(roll)
  root.add_child(card)
  await process_frame
  assert(card._portrait.portrait_texture!=null and card._rarity_label.text=="Upgrade source")
  assert(not card._status_label.text.is_empty())
  card.queue_free()
  await process_frame
 for id in materials:assert(gs.inventory_domain.item_count(id)==materials[id])
 assert(gs.roster.size()==old_roster+1)
 print("LOCAL MOB REWARDS, EPIC GUARANTEE, NO PLAYABLE MOB, AUTHORED CARD ART PASS")
 var save=gs._to_dict().duplicate(true)
 save.roster.append({"uid":"legacy_common","char_id":"kael_common","level":12,"equipment":{"weapon":"gladewood_bow"}})
 save.party.append("legacy_common")
 save.gear_levels["legacy_common|weapon"]=3
 var before=int(save.inventory.get("gladewood_bow",0))
 gs._load_from_dict(save)
 assert(not gs.roster_domain.owns_character("kael_common"))
 assert(not gs.party.has("legacy_common"))
 assert(gs.flags.retired_common_archive.legacy_common.level==12)
 assert(gs.inventory_domain.item_count("gladewood_bow")==before+1)
 assert(gs.roster_domain.stored_copies("gladewood_bow").any(func(g):return g.level==3))
 gs._load_from_dict(gs._to_dict().duplicate(true))
 assert(gs.inventory_domain.item_count("gladewood_bow")==before+1)
 print("LEGACY COMMON ARCHIVE AND ENHANCED GEAR REFUND PASS")
 quit(0)
