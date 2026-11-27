extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var db=root.get_node("ContentDB")
 var upgrade=load("res://scripts/gacha/character_upgrade_card.gd")
 var correct="Mir\u00e9ne"
 for banner in db.banners.values():
  for rarity in ["rare","epic"]:
   var id="upgrade_mirene_%s_v1" % rarity
   assert(banner.upgrade_cards[id].name==correct)
 for rarity in ["rare","epic","legendary","mythic"]:
  var id="upgrade_mirene_%s_v1" % rarity if rarity in ["rare","epic"] else "mirene_"+rarity
  var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
  card.setup({"character_id":id,"rarity":rarity})
  root.add_child(card)
  await process_frame
  assert(card._name_label.text==correct,str(card._name_label.text))
  card.free()
  print("MIRENE NAME PASS ",rarity)
 for id in ["upgrade_mirene_rare_v1","upgrade_mirene_epic_v1","legendary_progress_mirene_legendary","mythic_ascension_mirene_mythic"]:
  assert(str(db.get_item(id).get("name","")).begins_with(correct),id)
 assert(load("res://scripts/ui/components/menu_character_selector.gd").LABELS["mirene"]==correct)
 print("MIRENE ALL NAME CHECKS PASS")
 quit()
