extends SceneTree
func _initialize():call_deferred("run")
func capture(name:String):
 await process_frame
 await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OS.get_environment("TEMP")+"/"+name+".png")
func run():
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":quit(2);return
 root.get_node("GameState").new_game("Portrait QA")
 var db=root.get_node("ContentDB");var fitting=load("res://scripts/ui/portrait_framing.gd");var social=load("res://scripts/ui/social_portrait.gd");var ids=db.characters.keys();var missing=[];var count=0
 for id in ids:
  var tex=fitting.authored_texture(id)
  if tex==null:missing.append(id);continue
  for aspect in [1.0,0.667,0.82,1.25]:
   var crop=fitting.fitted(tex,id,aspect,"icon" if aspect>.8 else "card")
   assert(crop is AtlasTexture)
   assert(crop.region.position.x>=0 and crop.region.position.y>=0 and crop.region.end.x<=tex.get_width() and crop.region.end.y<=tex.get_height(), str(id)+" bounds "+str(crop.region)+" "+str(tex.get_size()))
   assert(absf(crop.get_width()/float(crop.get_height())-aspect)<.02, str(id)+" "+str(aspect)+" "+str(crop.region)+" "+str(tex.get_size()))
   count+=1
 print("CROP CHECKS ",count," MISSING ",missing)
 var host=Control.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var grid=GridContainer.new();grid.columns=10;grid.position=Vector2(20,20);host.add_child(grid)
 var view_scene=load("res://scenes/ui/components/portrait_view.tscn")
 for id in ["kael","gerald","lilith","cassien","ravienna","elathra","nyx","crimson_witch","mirene","caelith"]:
  var column=VBoxContainer.new();grid.add_child(column)
  var label=Label.new();label.text=id;column.add_child(label)
  for spec in [[Vector2(108,108),"icon",""],[Vector2(108,162),"card",""],[Vector2(108,108),"icon","round"],[Vector2(108,116),"icon","tall"]]:
   var view=view_scene.instantiate();view.custom_minimum_size=spec[0];view.fit_mode=spec[1];view.battle_frame_style=spec[2];view.setup_character(db.get_character(id));column.add_child(view)
  var rect=TextureRect.new();rect.custom_minimum_size=Vector2(80,80);rect.expand_mode=1;rect.stretch_mode=5;rect.texture=social.texture("kael_avatar" if id=="kael" else id);column.add_child(rect)
  assert(rect.texture!=null and rect.texture.get_width()==rect.texture.get_height())
 await capture("portrait_framing_matrix")
 print("VISUAL MATRIX AND SOCIAL CROP PASS")
 host.queue_free();await process_frame
 var gacha=load("res://scenes/ui/gacha_screen.tscn").instantiate();root.add_child(gacha);await process_frame
 var banners=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/banners.json"));var banner_count=0
 for id in banners:
  gacha._selected_banner=id;gacha._banner_content.rebuild_main();await process_frame
  if gacha._featured_id!="":banner_count+=1
  if gacha._featured_id=="ravienna":await capture("portrait_ravienna_banner")
 print("BANNER SCENES ",banner_count)
 gacha.queue_free();await process_frame
 var battle=load("res://scenes/ui/combat_screen.tscn").instantiate();battle.group_id="cassien_encounter";root.add_child(battle);await create_timer(2.0).timeout
 await capture("portrait_battle_fit")
 print("BATTLE PORTRAITS PASS")
 battle.queue_free();await process_frame
 root.get_node("AudioDirector").stop_all_audio_immediately();await create_timer(.4).timeout;quit(0)
