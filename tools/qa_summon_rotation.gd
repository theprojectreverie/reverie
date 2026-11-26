extends Node

func _ready() -> void:
	call_deferred("run")

func fail(reason: String) -> void:
	printerr("FAIL ",reason)
	get_tree().quit(1)

func fits(node: Control, bounds: Rect2) -> bool:
	var r := node.get_global_rect()
	return r.position.x >= bounds.position.x-2 and r.position.y >= bounds.position.y-2 and r.end.x <= bounds.end.x+2 and r.end.y <= bounds.end.y+2

func settle() -> void:
	for i in 8: await get_tree().process_frame

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(844,390)
	add_child(viewport)
	var scene: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
	viewport.add_child(scene)
	await settle()
	var banner := scene._selected_banner
	var roll := {"character_id":"nyx","rarity":"legendary","featured":true,"paid_guaranteed":true,"is_new":true}
	var rolls: Array = []
	for i in 10: rolls.append(roll.duplicate())
	scene._summon_flow.show_results(rolls,"paid_moonstones",banner)
	await settle()
	var layer := scene._results_layer
	var grid: GridContainer = layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid")
	var original_cards := grid.get_children()
	var again: Button = layer.get_node("Center/Panel/Content/Footer/SummonAgainButton")
	for dimensions in [Vector2i(360,800),Vector2i(640,360),Vector2i(1280,720),Vector2i(360,800)]:
		viewport.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		if scene._results_layer != layer or grid.get_children() != original_cards or scene._selected_banner != banner:
			fail("rotation replaced result nodes or banner"); return
		var panel: Control = layer.get_node("Center/Panel")
		if not fits(panel,bounds):
			fail("rotated result panel %s viewport %s" % [panel.get_global_rect(),dimensions]); return
		for child in panel.get_node("Content/Footer").get_children():
			if child is Button and (not fits(child,bounds) or child.size.y<47):
				fail("rotated footer %s %s" % [child.name,child.get_global_rect()]); return
		if not again.disabled or again.text != "Paid x10 Again":
			fail("rotation changed paid action"); return
		if not grid.get_child(0).get_node("Content/Status").text.contains("PAID MILESTONE"):
			fail("rotation lost featured marker"); return
		if grid.size.x>grid.get_parent().size.x+2:
			fail("rotated grid overflow"); return
		print("PASS live reward rotation ",dimensions," columns=",grid.columns," original cards retained")
	layer.get_node("Center/Panel/Content/Footer/ContinueButton").pressed.emit()
	await settle()
	if is_instance_valid(scene._results_layer):
		fail("continue did not close rewards"); return
	var reveal: SummonRevealOverlay = load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
	scene.add_child(reveal)
	scene._results_layer=reveal
	scene._summon_busy=true
	# Exercise the actual card stage coroutine without waiting for a video decoder.
	reveal._show_character(roll,9,10)
	await settle()
	var art: TextureRect = reveal.get_node("CardStage/CharacterArtwork")
	var original_texture := art.texture
	for dimensions in [Vector2i(640,360),Vector2i(360,800),Vector2i(844,390)]:
		viewport.size=dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		for path in ["CloseSummonButton","CardStage/NextButton","CardStage/Intro"]:
			var node: Control = reveal.get_node(path)
			if not fits(node,bounds):
				fail("reveal control %s %s viewport %s" % [path,node.get_global_rect(),dimensions]); return
		if not reveal.waiting_for_card or reveal.reveal_count != 1 or art.texture != original_texture:
			fail("rotation interrupted reveal"); return
		print("PASS live reveal rotation ",dimensions," original reward retained")
	reveal.get_node("CardStage/NextButton").pressed.emit()
	await settle()
	if reveal.waiting_for_card or reveal.get_node("CardStage").visible:
		fail("advance after rotation"); return
	reveal.queue_free()
	scene._results_layer=null
	scene._summon_busy=false
	scene._refresh()
	await settle()
	viewport.size=Vector2i(360,800)
	await settle()
	if not fits(scene.get_node("OverlayShell/Margin/Panel"),Rect2(Vector2.ZERO,Vector2(360,800))):
		fail("shell rotation"); return
	if scene._main.find_child("CompactSummonScroll",true,false)==null:
		fail("compact shell not rebuilt"); return
	viewport.queue_free()
	await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
