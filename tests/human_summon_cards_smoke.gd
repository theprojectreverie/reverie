extends SceneTree
const ART = preload("res://scripts/art/approved_character_portraits.gd")

func _initialize(): call_deferred("_run")
func _run():
 var UPGRADE = load("res://scripts/gacha/character_upgrade_card.gd")
 var reveal=load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
 root.add_child(reveal)
 for base in ART.CHARACTERS:
  for rarity in ["rare","epic"]:
   var id="upgrade_%s_%s_v1" % [base,rarity]
   var expected=ART.texture(base+"_human")
   assert(expected!=null)
   assert(UPGRADE.portrait_id(id)==base+"_human")
   assert(reveal._character_art(UPGRADE.portrait_id(id))==expected)
   var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
   card.setup({"character_id":id,"rarity":rarity,"kind":"upgrade_card","card_count":1})
   root.add_child(card)
   await process_frame
   assert(card._portrait.portrait_texture==expected,str(id))
   assert(card._rarity_label.text==rarity.capitalize()+" card",str(id))
   card.free()
   print("HUMAN CARD PASS ",str(id))
  for rarity in ["legendary","mythic"]:
   var id=base if base=="ravienna" and rarity=="legendary" else base+"_"+rarity
   assert(UPGRADE.portrait_id(id)==id)
   var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
   card.setup({"character_id":id,"rarity":rarity})
   root.add_child(card)
   await process_frame
   assert(card._portrait.portrait_texture==ART.texture(id),str(id))
   card.free()
 for rarity in ["rare","epic"]:
  var id="upgrade_kael_%s_v1" % rarity
  assert(UPGRADE.portrait_id(id)==str(UPGRADE.definition(id).portrait_id))
 reveal.free()
 print("PASS: eight human cards, eight premium portraits unchanged, other cards unchanged")
 quit()
