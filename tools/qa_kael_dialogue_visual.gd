extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 root.size = Vector2i(1280,720)
 var box = load("res://scenes/ui/dialogue_box.tscn").instantiate()
 root.add_child(box)
 await process_frame
 box.open("cassien_tomb_approach")
 box._finish_typing()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/qa/kael_dialogue_updated.png")
 print("KAEL DIALOGUE VISUAL CAPTURE")
 quit()