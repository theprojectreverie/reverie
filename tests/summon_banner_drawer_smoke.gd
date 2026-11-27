extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 root.add_child(gacha)
 for i in range(5): await process_frame
 var stage=gacha._banner_content._stage
 assert(stage!=null)
 assert(not stage.opened and not stage.drawer.visible)
 assert(gacha.get_node("BannerHero").portrait_texture!=null)
 assert(stage.actions.get_child_count()==2)
 for id in gacha.active_banner_catalog():
  gacha._select_banner(id)
  for i in range(4): await process_frame
  stage=gacha._banner_content._stage
  assert(not stage.opened)
  stage.handle.pressed.emit()
  await create_timer(0.3).timeout
  assert(stage.opened and stage.drawer.visible)
  assert(stage.drawer.position.y>=-1)
  assert(stage.drawer.position.y+stage.drawer.size.y<=stage.footer.position.y+1)
  assert(stage.footer.position.y+stage.footer.size.y<=stage.size.y+1)
  assert(stage.drawer.size.y<=gacha.get_viewport_rect().size.y*0.5)
  assert(stage.info.get_child_count()>8)
  assert(gacha.find_child("PaidPull10",true,false)!=null)
  gacha._refresh()
  for i in range(4): await process_frame
  stage=gacha._banner_content._stage
  assert(stage.opened)
  gacha._banner_content.close_drawer()
  assert(not stage.drawer.visible)
  print("BANNER PASS ",id," stage=",stage.size," footer=",stage.footer.size," viewport=",gacha.get_viewport_rect().size)
 gacha.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 quit()
