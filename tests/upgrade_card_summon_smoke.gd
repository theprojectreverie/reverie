extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 var db=root.get_node("ContentDB")
 var cards=load("res://scripts/gacha/character_upgrade_card.gd")
 assert(db.validation_errors.is_empty())
 for id in db.characters:
  assert(db.characters[id].rarity in ["legendary","mythic"] or id in ["kael","lilith","gerald"])
 var rare="upgrade_kael_rare_v1"
 var epic="upgrade_kael_epic_v1"
 for i in range(19):assert(cards.grant(rare).is_empty())
 assert(gs.inventory_domain.item_count(rare)==19 and gs.inventory_domain.item_count(epic)==0)
 assert(cards.grant(rare).size()==1)
 assert(gs.inventory_domain.item_count(rare)==0 and gs.inventory_domain.item_count(epic)==1)
 for i in range(8):assert(cards.grant(epic).is_empty())
 assert(not gs.roster_domain.owns_character("kael_legendary"))
 assert(cards.grant(epic).size()==1)
 assert(gs.inventory_domain.item_count(epic)==0 and gs.roster_domain.owns_character("kael_legendary"))
 assert(not gs.roster_domain.add_character(epic).has("instance"))
 var recipe=cards.mythic_recipe("kael_legendary")
 assert(recipe.cost==7 and gs.inventory_domain.item_count(recipe.item)==1)
 for i in range(5):
  gs.roster_domain.add_character("kael_legendary")
  assert(cards.record_legendary("kael_legendary").is_empty())
 assert(gs.inventory_domain.item_count(recipe.item)==6)
 assert(not gs.roster_domain.owns_character("kael_mythic"))
 gs.roster_domain.add_character("kael_legendary")
 assert(cards.record_legendary("kael_legendary").size()==1)
 assert(gs.inventory_domain.item_count(recipe.item)==0)
 assert(gs.roster_domain.owns_character("kael_legendary") and gs.roster_domain.owns_character("kael_mythic"))
 print("20 RARE, 10 EPIC, 7 LEGENDARY ACQUISITIONS PASS")

 var banner=db.get_banner("crimson_covenant")
 var rates=banner.rates.duplicate()
 banner.rates={"common":1.0,"rare":0.0,"epic":0.0,"legendary":0.0,"mythic":0.0}
 var result=gs.reward_domain.pull_banner("crimson_covenant",10)
 banner.rates=rates
 assert(result.ok and result.results[9].kind=="upgrade_card" and result.results[9].rarity=="epic")
 var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
 card.setup(result.results[9])
 root.add_child(card)
 await process_frame
 assert(card._rarity_label.text=="Epic card")
 card.queue_free()
 await process_frame
 var save=gs._to_dict().duplicate(true)
 save.roster.append({"uid":"legacy_epic","char_id":"gerald_epic","level":10,"dupes":2,"awakening":1})
 gs._load_from_dict(save)
 assert(not gs.roster_domain.owns_character("gerald_epic"))
 assert(gs.inventory_domain.item_count("upgrade_gerald_epic_v1")==5)
 gs._load_from_dict(gs._to_dict().duplicate(true))
 assert(gs.inventory_domain.item_count("upgrade_gerald_epic_v1")==5)
 print("CARD CHAIN, EPIC FLOOR, CARD UI, NO PLAYABLE CARDS, LEGACY REFUND PASS")
 quit(0)
