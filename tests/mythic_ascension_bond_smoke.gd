extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState")
 var fusion=load("res://scripts/gacha/character_upgrade_card.gd")
 var factory=load("res://scripts/combat/combat_factory.gd")
 var uids=[]
 for id in ["gerald_mythic","lilith_mythic","ravienna_mythic","cassien_mythic"]:
  var created=gs.roster_domain.add_character(id)
  var instance=created.instance
  instance.level=15
  for i in range(6):
   if i>0:gs.roster_domain.add_character(id)
   assert(fusion.record_mythic(id).is_empty())
  assert(instance.ascension==0)
  gs.roster_domain.add_character(id)
  assert(fusion.record_mythic(id).size()==1)
  assert(instance.ascension==3 and instance.level==15 and instance.level_cap()==80)
  assert(fusion.record_mythic(id).is_empty())
  uids.append(instance.uid)
 assert(gs.roster_domain.set_party(uids))
 var party=gs.roster_domain.party_instances()
 assert(fusion.active_bonds(party).size()==2)
 var bonus=gs.roster_domain.collection_bonus()
 var units=factory.player_units()
 assert(units.size()==4)
 for instance in party:
  var baseline=factory.build_from_character(instance,bonus)
  for unit in units:
   if unit.def_id==instance.char_id:
    if unit.def_id in ["gerald_mythic","lilith_mythic"]:
     assert(is_equal_approx(unit.defense,baseline.defense*1.1) and is_equal_approx(unit.atk,baseline.atk))
    else:
     assert(is_equal_approx(unit.atk,baseline.atk*1.1) and is_equal_approx(unit.defense,baseline.defense))
 assert(gs.roster_domain.set_party([uids[0],uids[2]]))
 assert(fusion.active_bonds(gs.roster_domain.party_instances()).is_empty())
 var save=gs._to_dict().duplicate(true)
 gs._load_from_dict(save)
 for id in ["gerald_mythic","lilith_mythic","ravienna_mythic","cassien_mythic"]:
  assert(gs.inventory_domain.item_count(fusion.ascension_recipe(id).item)==7)
 print("SEVEN MYTHIC ASCENSION, LEVEL PRESERVATION, BOTH BONDS, PARTY REMOVAL AND SAVE PASS")
 quit(0)
