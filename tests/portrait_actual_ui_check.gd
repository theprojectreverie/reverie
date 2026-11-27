extends SceneTree
func _initialize():call_deferred("run")
func capture(name:String):
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/"+name+".png")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 var gs=root.get_node("GameState");gs.new_game("Portrait QA")
 var social=load("res://scripts/ui/social_portrait.gd")
 var screen=load("res://scenes/ui/social_screen.tscn").instantiate();root.add_child(screen);await process_frame
 var opts=screen._layout.get_node("Profile/Pictures")
 for id in social.PROFILE_IDS:
  var tex=social.texture(id);assert(tex!=null and tex.get_width()==tex.get_height(),id)
  opts.add_icon_item(tex,id);opts.set_item_metadata(opts.item_count-1,id)
  opts.get_popup().set_item_icon_max_width(opts.item_count-1,40)
 opts.select(0);screen._layout.get_node("Profile/Portrait").texture=opts.get_item_icon(0)
 screen._set_gallery_visible(true);await capture("portrait_actual_gallery")
 assert(screen._layout.get_node("PortraitGallery/Scroll/Grid").get_child_count()==opts.item_count)
 print("ACTUAL PROFILE GALLERY ",opts.item_count," SQUARE ICONS PASS")
 screen.queue_free();await process_frame
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate();root.add_child(gacha);await process_frame
 for banner in ["crimson_covenant","scarlet_requiem","lily_of_shadows"]:
  gacha._select_banner(banner);await capture("portrait_banner_"+banner)
 print("THREE ACTUAL BANNERS PASS")
 var results=[]
 for id in ["kael","gerald","lilith","cassien","ravienna","elathra","nyx","crimson_witch","mirene","caelith"]:
  results.append({"character_id":id,"rarity":"legendary","is_new":true})
 gacha._show_results(results);await create_timer(1.8).timeout
 await capture("portrait_actual_results")
 assert(gacha._result_cards==10)
 print("ACTUAL TEN RESULT CARDS PASS")
 gacha.queue_free();await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout;quit(0)
