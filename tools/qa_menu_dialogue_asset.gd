extends Node
func _ready() -> void:
	var main: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(main)
	main.size = Vector2(1280,720)
	await get_tree().process_frame
	var panel: TextureRect = main.get_node("RaviennaDialogue")
	assert(panel.texture.resource_path == "res://assets/ui/dialogue/gothic_rose_dialogue_box.png")
	assert(panel.flip_h and panel.flip_v)
	assert(not panel.visible)
	main._toggle_menu_dialogue()
	for id in ["ravienna","kael_standing","mirene","crimson_witch","elathra"]:
		main._on_menu_character_changed(id)
		for i in range(main._menu_dialogue_lines().size()):
			main._show_menu_dialogue_line()
			await get_tree().process_frame
			assert(main.ravienna_line.get_combined_minimum_size().y <= main.ravienna_line.size.y + 1)
			assert(panel.get_global_rect().encloses(main.ravienna_line.get_global_rect()))
			main._advance_ravienna_dialogue()
	assert(panel.visible)
	main._on_menu_gallery_visibility(true)
	assert(not panel.visible)
	main._on_menu_gallery_visibility(false)
	assert(panel.visible)
	main._toggle_menu_dialogue()
	assert(not panel.visible)
	print("PASS replacement dialogue artwork, all menu dialogue lines, hide/show and gallery behavior")
	main.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
