extends Node2D
func _ready():
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var result = get_viewport().get_texture().get_image().save_png("C:/Users/quoth/Downloads/gothic_viewport_review.png")
	print("CAPTURE_RESULT=", result)
	get_tree().quit(result)