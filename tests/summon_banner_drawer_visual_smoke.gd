extends SceneTree
func _initialize():
 call_deferred("run")
func shot(name):
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/reverie_drawer_"+name+".png")
func run():
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.size=Vector2i(1280,720)
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate()
 root.add_child(gacha)
 for i in range(8): await process_frame
 for resolution in [Vector2i(1280,720),Vector2i(960,540),Vector2i(540,960)]:
  root.size=resolution
  await create_timer(.35).timeout
  gacha._select_banner("eclipse_sovereign")
  await create_timer(.2).timeout
  var stage=gacha._banner_content._stage
  assert(stage!=null)
  assert(not stage.opened and not stage.drawer.visible)
  assert(gacha.get_node("BannerHero").portrait_texture!=null)
  assert(stage.actions.get_child_count()==2)
  await shot(str(resolution.x)+"_closed")
  stage.handle.pressed.emit()
  await create_timer(.35).timeout
  assert(stage.opened and stage.drawer.visible)
  assert(stage.drawer.position.y>=-1)
  assert(stage.drawer.position.y+stage.drawer.size.y<=stage.footer.position.y+1)
  assert(stage.footer.position.y+stage.footer.size.y<=stage.size.y+1)
  assert(stage.footer.position.x>=-1 and stage.footer.position.x+stage.footer.size.x<=stage.size.x+1)
  assert(stage.drawer.size.y<=gacha.get_viewport_rect().size.y*0.5)
  assert(stage.info.get_child_count()>8)
  await shot(str(resolution.x)+"_open")
  stage.handle.pressed.emit()
  await create_timer(.3).timeout
  assert(not stage.opened and not stage.drawer.visible)
  print("LAYOUT PASS physical=",root.size," viewport=",gacha.get_viewport_rect().size," stage=",stage.size," footer=",stage.footer.size)
 gacha.queue_free()
 await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately()
 await create_timer(.3).timeout
 quit()
