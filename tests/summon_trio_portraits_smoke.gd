extends SceneTree
func _initialize():call_deferred("_run")
func _run():
 var overlay=load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
 root.add_child(overlay)
 for id in ["gerald","lilith","kael"]:
  var path="res://assets/portraits/summon/"+id+".png"
  for suffix in ["","_rare","_epic","_legendary","_mythic"]:
   assert(overlay._character_art(id+suffix).resource_path==path)
  for rarity in ["rare","epic"]:
   var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
   card.setup({"character_id":"upgrade_"+id+"_"+rarity+"_v1","rarity":rarity,"kind":"upgrade_card","card_count":1})
   root.add_child(card)
   await process_frame
   assert(card._portrait.portrait_texture.resource_path==path)
   card.queue_free()
   await process_frame
 print("PASS all trio reveal aspects and six upgrade result cards use existing authored portraits")
 overlay.queue_free()
 await process_frame
 quit(0)
