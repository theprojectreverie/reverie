extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
 var db=root.get_node("ContentDB")
 assert(db.validation_errors.is_empty(),str(db.validation_errors))
 var service=load("res://scripts/gacha/gacha_service.gd")
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 root.add_child(gacha)
 await process_frame
 var ids={"lily_of_shadows":"elathra_mythic","crimson_oath":"cassien_mythic","eclipse_sovereign":"ravienna_mythic","flamebound_guardian":"gerald_mythic","moonlit_requiem":"lilith_mythic"}
 for banner_id in ids:
  var id=ids[banner_id]
  var b=db.get_banner(banner_id)
  assert(b.featured==[id],str(banner_id))
  assert(db.get_character(id).rarity=="mythic")
  var rng=RandomNumberGenerator.new()
  rng.seed=42
  var outcome=service.pull(b,rng,{"legendary":0,"featured":159,"epic_streak":0},1)
  assert(outcome.results[0].character_id==id and outcome.results[0].rarity=="mythic")
  gacha._select_banner(banner_id)
  await process_frame
  assert(gacha._featured_id==id)
  var card=load("res://scenes/ui/components/summon_result_card.tscn").instantiate()
  card.setup({"character_id":id,"rarity":"mythic"})
  root.add_child(card)
  await process_frame
  assert(card._portrait.portrait_texture!=null)
  card.free()
  print("MYTHIC FEATURE UI AND PITY PASS ",banner_id)
 gacha.free()
 print("ALL FIVE MYTHIC FEATURE PASS")
 quit()
