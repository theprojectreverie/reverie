extends Node

func _ready() -> void:
	call_deferred("run")

func fail(reason: String) -> void:
	printerr("FAIL ",reason)
	get_tree().quit(1)

func fits(node: Control, bounds: Rect2) -> bool:
	var r := node.get_global_rect()
	return r.position.x >= bounds.position.x - 2 and r.end.x <= bounds.end.x + 2 and r.position.y >= bounds.position.y - 2 and r.end.y <= bounds.end.y + 2

func run() -> void:
	for dimensions in [Vector2i(360,800),Vector2i(640,360),Vector2i(844,390),Vector2i(1280,720)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		add_child(viewport)
		var scene: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
		viewport.add_child(scene)
		for frame in 5: await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		var shell: Control = scene.get_node("OverlayShell/Margin/Panel")
		if not fits(shell,bounds):
			fail("shell %s viewport %s" % [shell.get_global_rect(),dimensions]); return
		for banner in ContentDB.banners.keys():
			scene._select_banner(str(banner))
			for frame in 5: await get_tree().process_frame
			if not fits(scene._tabs,bounds):
				fail("tabs %s viewport %s" % [scene._tabs.get_global_rect(),dimensions]); return
			var paid := scene._main.find_child("PaidPull10",true,false) as Button
			if paid == null or paid.size.y < 47:
				fail("paid control target"); return
			if paid.get_global_rect().end.x > bounds.end.x + 2:
				fail("paid control width %s viewport %s" % [paid.get_global_rect(),dimensions]); return
		var rolls: Array = []
		for i in 10:
			rolls.append({"character_id":"nyx","rarity":"legendary","featured":true,"paid_guaranteed":i==9,"is_new":i==0})
		scene._summon_flow.show_results(rolls,"paid_moonstones",scene._selected_banner)
		for frame in 8: await get_tree().process_frame
		var panel: Control = scene._results_layer.get_node("Center/Panel")
		var footer: Control = panel.get_node("Content/Footer")
		var grid: GridContainer = panel.get_node("Content/ResultsScroll/ResultGrid")
		if not fits(panel,bounds):
			fail("results panel %s viewport %s" % [panel.get_global_rect(),dimensions]); return
		for child in footer.get_children():
			if child is Button and (not fits(child,bounds) or child.size.y < 47):
				fail("result action %s rect %s viewport %s" % [child.name,child.get_global_rect(),dimensions]); return
		if grid.get_child_count()!=10:
			fail("result count"); return
		var scroll: ScrollContainer = grid.get_parent()
		if grid.size.x > scroll.size.x + 2:
			fail("result grid overflow %s vs %s viewport %s" % [grid.size,scroll.size,dimensions]); return
		print("PASS summon layout ",dimensions," results columns=",grid.columns," panel=",panel.size)
		viewport.queue_free()
		await get_tree().process_frame
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
