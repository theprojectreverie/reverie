extends Node
func _ready() -> void:
	call_deferred("run")
func fail(reason: String) -> void:
	push_error("FAIL "+reason)
	get_tree().quit(1)
func run() -> void:
	var screen: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen._summon_flow.online_state = {"roster":[{"char_id":"kael","level":1},{"char_id":"gerald","level":2},{"char_id":"lilith","level":3}],"party":["kael","gerald"],"currencies":{},"inventory":{}}
	screen._show_online_roster()
	var dialog: AcceptDialog = screen.get_node("OnlineRosterDialog")
	var root: VBoxContainer = dialog.get_node("BodyScroll/Collection")
	for row in screen._summon_flow.online_state.get("roster",[]):
		if row.char_id=="gerald": screen._online_character_details(row,ContentDB.get_character("gerald"))
	for i in range(6): await get_tree().process_frame
	for width in [960,640,420,360,320]:
		dialog.size = Vector2i(width,440)
		for tab in ["Roster","Progression","Equipment","Party"]:
			screen._set_collection_section(tab)
			for i in range(4): await get_tree().process_frame
			dialog.size = Vector2i(width,440)
			for i in range(4): await get_tree().process_frame
			if dialog.size.x > width+2:
				fail("%s width %d actual %d" % [tab,width,dialog.size.x]); return
			print("LAYOUT ",width," ",tab," dialog ",dialog.size," root ",root.size," min ",root.get_combined_minimum_size())
			if dialog.size.y>442:
				fail("%s height %d" % [tab,dialog.size.y]); return
			if root.get_node("SectionTabs/"+tab).button_pressed != true:
				fail("tab state"); return
			if root.get_node("Scroll").visible != (tab=="Roster") or root.get_node("GearRow").visible != (tab=="Equipment"):
				fail("tab visibility"); return
		screen._set_collection_section("Roster")
		for i in range(4): await get_tree().process_frame
		var scroll: ScrollContainer = root.get_node("Scroll")
		var grid: GridContainer = scroll.get_node("Grid")
		if grid.columns<1 or grid.get_combined_minimum_size().x>scroll.size.x+1:
			fail("grid overflow at %d: %s vs %s" % [width,grid.get_combined_minimum_size(),scroll.size]); return
		print("PASS responsive width ",width," columns ",grid.columns)
	var grid: GridContainer = root.get_node("Scroll/Grid")
	var card: RosterCharacterCard = grid.get_child(0)
	card.selected.emit("gerald")
	if screen._collection_section != "Progression" or screen._online_selected.get("char_id")!="gerald":
		fail("card selection"); return
	screen._set_collection_section("Equipment")
	if screen._online_selected.get("char_id")!="gerald":
		fail("selected character lost"); return
	print("PASS card selection and tab navigation")
	dialog.size = Vector2i(320,280)
	screen._set_collection_section("Progression")
	for i in range(6): await get_tree().process_frame
	var body: ScrollContainer = dialog.get_node("BodyScroll")
	var scrollbar: VScrollBar = body.get_v_scroll_bar()
	if dialog.size.y>282 or scrollbar.max_value<=scrollbar.page:
		fail("short landscape scroll"); return
	body.scroll_vertical = int(scrollbar.max_value)
	await get_tree().process_frame
	if body.scroll_vertical<=0:
		fail("short landscape cannot scroll"); return
	screen._set_collection_section("Equipment")
	await get_tree().process_frame
	if body.scroll_vertical!=0:
		fail("tab scroll reset"); return
	print("PASS 320x280 compact layout with scrollable controls")
	var atmosphere = screen.get_node("SummoningChamberAtmosphere")
	var original_quality: int = GraphicsSettings.requested_quality
	var original_fps: int = GraphicsSettings.frame_limit
	var adaptive: bool = GraphicsSettings.adaptive_enabled
	var monitor: bool = GraphicsSettings.monitor_enabled
	GraphicsSettings.apply_preferences(0,60)
	await get_tree().process_frame
	if atmosphere.is_processing() or atmosphere.motes_layer.visible or atmosphere.petals_layer.visible:
		fail("battery saver atmosphere"); return
	GraphicsSettings.apply_preferences(1,60)
	await get_tree().process_frame
	if not atmosphere.is_processing() or not atmosphere.motes_layer.visible or atmosphere.petals_layer.visible:
		fail("balanced atmosphere"); return
	var visible_motes := 0
	for mote in atmosphere.motes_layer.get_children():
		if mote.visible: visible_motes += 1
	if visible_motes != ceili(atmosphere.motes_layer.get_child_count()/2.0):
		fail("balanced mote count"); return
	var ticks: int = atmosphere._animation_ticks
	atmosphere._accumulated_delta = 0.0
	atmosphere._process(0.005)
	if atmosphere._animation_ticks != ticks:
		fail("balanced throttling"); return
	atmosphere._process(0.04)
	if atmosphere._animation_ticks != ticks+1:
		fail("balanced animation tick"); return
	GraphicsSettings.apply_preferences(2,60)
	await get_tree().process_frame
	if not atmosphere.is_processing() or not atmosphere.petals_layer.visible:
		fail("high quality atmosphere"); return
	atmosphere.hide()
	if atmosphere.is_processing():
		fail("hidden atmosphere processing"); return
	atmosphere.show()
	GraphicsSettings.apply_preferences(original_quality,original_fps,adaptive,monitor)
	print("PASS battery saver, balanced effect reduction and animation throttling, high quality, hidden effect suspension")


	dialog.hide()
	screen.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
