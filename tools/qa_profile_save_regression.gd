extends Node
func _ready():
	call_deferred("run")
func fail(reason: String):
	print("FAIL ", reason)
	get_tree().quit(1)
func wait_until(check: Callable, seconds: float=10.0) -> bool:
	var deadline = Time.get_ticks_msec()+int(seconds*1000)
	while not check.call():
		if Time.get_ticks_msec()>deadline: return false
		await get_tree().process_frame
	return true
func run():
	GraphicsSettings._apply_quality(2)
	AuthGateway.api_base_url=OS.get_environment("QA_API")
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("login"); return
	var auth=await AuthGateway.auth_result
	if not auth[1]:
		fail("auth"); return
	var menu=load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var selector = menu.get_node("MenuCharacterSelector")
	if not await wait_until(func():return selector._loaded and not selector.disabled):
		fail("menu character choices"); return
	var menu_id := "kael_crouching" if OS.get_environment("QA_ROLE")=="A" else "kael_seated"
	selector.pressed.emit()
	if not selector.gallery.visible or selector.grid.get_child_count()!=7:
		fail("visual menu gallery"); return
	var preview_bytes := 0
	for card in selector.grid.get_children():
		var preview: Texture2D = card.get_node("Preview").texture
		if preview==null or preview.get_width()>256 or preview.get_height()>384:
			fail("gallery thumbnail resolution"); return
		preview_bytes += preview.get_width()*preview.get_height()*4
	if preview_bytes>7*256*384*4:
		fail("gallery memory budget"); return
	print("PASS gallery thumbnail RGBA budget bytes=",preview_bytes)
	var locked_menu: Button = selector.grid.get_node("elathra")
	if not locked_menu.disabled:
		fail("locked menu character selectable"); return
	var menu_tile: Button = selector.grid.get_node(menu_id)
	if menu_tile.disabled or menu_tile.get_node("Preview").texture==null:
		fail("owned menu art missing"); return
	menu_tile.pressed.emit()
	# Simulate roster change while the selection save is still in flight.
	selector._roster_changed()
	if not selector._refresh_requested:
		fail("roster update discarded during save"); return
	if not await wait_until(func():return selector._saved==menu_id and selector._pending.is_empty()):
		fail("menu character save"); return
	if not await wait_until(func():return selector._pending.is_empty() and not selector._refresh_requested and selector._loaded):
		fail("queued roster refresh"); return
	if selector.artwork.texture!=load(selector.ART[menu_id]):
		fail("menu character artwork"); return
	GraphicsSettings._apply_quality(0)
	await get_tree().process_frame
	if selector.artwork.texture.get_width()!=512 or selector.artwork.texture.get_height()!=768 or selector._saved!=menu_id:
		fail("battery saver artwork or saved selection"); return
	GraphicsSettings._apply_quality(1)
	await get_tree().process_frame
	if selector.artwork.texture!=load(selector.ART[menu_id]):
		fail("balanced full artwork"); return
	GraphicsSettings._apply_quality(2)
	print("PASS quality changes retain selection and swap correct texture")
	if menu._menu_dialogue_key!="kael":
		fail("dialogue character mapping"); return
	menu.get_node("MenuDialogueButton").pressed.emit()
	if not menu.get_node("RaviennaDialogue").visible:
		fail("dialogue toggle"); return
	var first_line: String = menu.ravienna_line.text
	menu._advance_ravienna_dialogue()
	if first_line==menu.ravienna_line.text:
		fail("dialogue cycle"); return
	selector.pressed.emit()
	if menu.get_node("RaviennaDialogue").visible:
		fail("gallery dialogue overlap"); return
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for viewport_size in [Vector2(1280,720),Vector2(960,540),Vector2(844,390),Vector2(640,360)]:
		menu.size=viewport_size
		await get_tree().process_frame
		await get_tree().process_frame
		selector._resize_grid()
		await get_tree().process_frame
		var panel: Control=selector.gallery.get_node("Panel")
		if not Rect2(Vector2.ZERO,menu.size).encloses(panel.get_rect()):
			fail("gallery outside viewport "+str(viewport_size)+" "+str(panel.get_rect())); return
		if selector.grid.get_combined_minimum_size().x>selector.scroll.size.x+1.0:
			fail("gallery grid horizontal overflow "+str(viewport_size)); return
		for id in selector.ART:
			selector._apply_art(id,false)
			await get_tree().process_frame
			if selector.artwork.texture==null or not Rect2(Vector2.ZERO,menu.size).encloses(selector.artwork.get_rect().grow(-1)):
				fail("artwork bounds "+str(id)+" "+str(viewport_size)); return
	selector._apply_art(menu_id,false)
	var cancel := InputEventAction.new()
	cancel.action="ui_cancel"
	cancel.pressed=true
	selector._unhandled_input(cancel)
	if selector.gallery.visible:
		fail("cancel did not close gallery"); return
	if not menu.get_node("RaviennaDialogue").visible:
		fail("dialogue not restored after gallery"); return
	menu.get_node("MenuDialogueButton").pressed.emit()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	print("PASS character dialogue and gallery bounds at four landscape sizes")
	menu._open_profile()
	var screen=menu.get_node("PlayerProfileOverlay")
	if not await wait_until(func():return screen._profile_loaded):
		fail("profile load"); return
	var options: OptionButton=screen._layout.get_node("Profile/Pictures")
	if options.item_count!=37 or options.disabled:
		fail("all choices or disabled"); return
	var selected="ravienna" if OS.get_environment("QA_ROLE")=="A" else "ravienna_mythic"
	screen._layout.get_node("Profile/Browse").pressed.emit()
	var gallery: Control = screen._layout.get_node("PortraitGallery")
	if not gallery.visible:
		fail("gallery not visible"); return
	var search: LineEdit = gallery.get_node("Toolbar/Search")
	search.text="Ravienna"
	search.text_changed.emit(search.text)
	var grid: GridContainer = gallery.get_node("Scroll/Grid")
	if grid.get_child_count()!=4:
		fail("Ravienna search count "+str(grid.get_child_count())); return
	var locked_id := "ravienna_mythic" if selected=="ravienna" else "ravienna"
	if screen._unlocked_portraits.size()!=4 or not screen._unlocked_portraits.has(selected):
		fail("unlocked count"); return
	var locked: Button = grid.get_node_or_null(locked_id)
	if locked==null or not locked.disabled:
		fail("locked variant selectable"); return
	var tile: Button = grid.get_node_or_null(selected)
	if tile==null or tile.icon==null:
		fail("Ravienna tile"); return
	tile.pressed.emit()
	if str(options.get_item_metadata(options.selected))!=selected:
		fail("gallery selection"); return
	gallery.get_node("Toolbar/Done").pressed.emit()
	if gallery.visible:
		fail("gallery close"); return
	var save: Button=screen._layout.get_node("Profile/Save")
	if save.disabled:
		fail("save disabled"); return
	if screen._operation.is_empty():
		screen._begin("friends","/friends")
	if options.disabled or save.disabled:
		fail("polling blocks portrait controls"); return
	save.pressed.emit()
	if not await wait_until(func():return screen._saved_avatar==selected and screen._operation.is_empty()):
		fail("picture save: "+str(screen._layout.get_node("Status").text)); return
	var avatar: TextureRect=menu.get_node("ReferenceInterface/TopProfile/ProfileRow/AvatarFrame/KaelAvatar")
	if avatar.texture==null or avatar.texture != preload("res://scripts/ui/social_portrait.gd").texture(selected):
		fail("live menu picture"); return
	screen.close_screen()
	await get_tree().process_frame
	menu._open_profile()
	screen=menu.get_node("PlayerProfileOverlay")
	if not await wait_until(func():return screen._profile_loaded and screen._saved_avatar==selected):
		fail("reopen persistence"); return
	screen.close_screen()
	await get_tree().process_frame
	AuthGateway.logout()
	var logged_out=await AuthGateway.auth_result
	if logged_out[0]!="logout" or not logged_out[1]:
		fail("logout server acknowledgment"); return
	if AuthGateway.is_authenticated():
		fail("logout"); return
	if AuthGateway.login(OS.get_environment("QA_NAME"),OS.get_environment("QA_PASSWORD"))!=OK:
		fail("relogin request"); return
	var relogin=await AuthGateway.auth_result
	if not relogin[1] or str(AuthGateway.current_player().get("avatar",""))!=selected:
		fail("relogin portrait: operation="+str(relogin[0])+" avatar="+str(AuthGateway.current_player().get("avatar",""))); return
	if not await wait_until(func():return selector._loaded and selector._saved==menu_id and selector.artwork.texture==load(selector.ART[menu_id])):
		fail("menu character relogin"); return
	if not await wait_until(func():return avatar.texture==preload("res://scripts/ui/social_portrait.gd").texture(selected)):
		fail("menu portrait on login"); return
	# Emulate a legacy auth response missing its avatar; summary must repair it.
	AuthGateway._social_request.cancel_request()
	AuthGateway._social_request_player=""
	AuthGateway._player.erase("avatar")
	AuthGateway.refresh_social_summary()
	if not await wait_until(func():return str(AuthGateway.current_player().get("avatar",""))==selected):
		fail("automatic portrait synchronization"); return
	if AuthGateway.refresh_session()!=OK:
		fail("refresh request"); return
	var refreshed=await AuthGateway.auth_result
	if not refreshed[1] or str(AuthGateway._refreshed_player(refreshed[2]).get("avatar",""))!=selected:
		fail("session restoration identity"); return
	var training = load("res://scenes/world/tutorial_prologue/training_ground_v02.tscn").instantiate()
	menu.hide()
	add_child(training)
	await get_tree().process_frame
	training._begin_companion_naming()
	if not await wait_until(func():return training.name_entry.visible and not training._name_busy):
		fail("training name prompt"); return
	var chosen := "Astra" if OS.get_environment("QA_ROLE")=="A" else "Luna"
	training.name_entry.text=chosen
	training._submit_companion_name()
	if not await wait_until(func():return training.dialogue_stage=="practice" and training.companion_name==chosen):
		fail("training name save"); return
	training._begin_companion_naming()
	if not await wait_until(func():return training.dialogue_stage=="practice" and not training._name_busy):
		fail("training existing name restoration"); return
	if training.name_entry.visible or training.companion_name!=chosen:
		fail("training name prompted again"); return
	training.queue_free()
	menu.show()
	selector._roster_changed()
	if not await wait_until(func():return selector._companion_name==chosen):
		fail("menu companion name sync"); return
	if selector._label_for("elathra")!=chosen:
		fail("menu personalized label"); return
	print("PASS training naming prompt, save, reload, account-specific gallery label")
	print("PASS portrait saved, reopened, logout/relogin, automatic summary recovery, refresh identity")
	get_tree().quit(0)
