extends Node
# Offline visual-only QA fixture. No player settings or account writes.
func _ready() -> void:
 call_deferred("_capture")

func _capture() -> void:
 var root := get_tree().root
 var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
 add_child(menu)
 var selector = menu.get_node("MenuCharacterSelector")
 selector._loaded = true
 selector.disabled = false
 selector._choices = ["default","kael_crouching","kael_seated","kael_standing","mirene"]
 selector._saved = "kael_standing"
 var dir := OS.get_environment("QA_CAPTURE_DIR")
 for dimensions in [Vector2i(1280,720),Vector2i(844,390)]:
  root.size = dimensions
  await get_tree().process_frame
  await get_tree().process_frame
  selector._apply_art("kael_standing",false)
  await get_tree().process_frame
  await RenderingServer.frame_post_draw
  var name := str(dimensions.x)+"x"+str(dimensions.y)
  var image := root.get_texture().get_image()
  if image==null or image.is_empty():
   push_error("No rendered frame")
   get_tree().quit(1)
   return
  var err := image.save_png(dir.path_join("menu_"+name+".png"))
  if err!=OK:
   get_tree().quit(1)
   return
  selector._open_gallery()
  await get_tree().process_frame
  await get_tree().process_frame
  await RenderingServer.frame_post_draw
  var gallery_image := root.get_texture().get_image()
  err=gallery_image.save_png(dir.path_join("gallery_"+name+".png"))
  if err!=OK:
   get_tree().quit(1)
   return
  selector._close_gallery()
  print("Rendered menu and gallery at ", image.get_size())
 get_tree().quit(0)