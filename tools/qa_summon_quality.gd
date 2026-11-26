extends Node

func _ready() -> void:
	call_deferred("run")

func fail(reason: String) -> void:
	printerr("FAIL ",reason)
	get_tree().quit(1)

func run() -> void:
	var saved_quality: int = GraphicsSettings.requested_quality
	var saved_fps: int = GraphicsSettings.frame_limit
	var saved_adaptive: bool = GraphicsSettings.adaptive_enabled
	var saved_monitor: bool = GraphicsSettings.monitor_enabled
	var rolls: Array = [{"character_id":"nyx","rarity":"legendary","featured":true,"paid_guaranteed":true},{"character_id":"elathra","rarity":"legendary","featured":true}]
	for mode in [0,1,2]:
		GraphicsSettings.apply_preferences(mode,-1,false,false)
		var reveal: SummonRevealOverlay = load("res://scenes/ui/components/summon_reveal_overlay.tscn").instantiate()
		add_child(reveal)
		if reveal.cinematic_player.stream != null:
			fail("video preloaded"); return
		var finished := [false]
		reveal.reveal_finished.connect(func(): finished[0]=true)
		reveal.play_batch(rolls)
		var seen := 0
		var deadline := Time.get_ticks_msec()+10000
		while not finished[0] and Time.get_ticks_msec()<deadline:
			if reveal.cinematic_player.stream != null:
				# Finish the decoder wait deterministically; no GPU benchmark claimed.
				reveal.stream_completed.emit()
			if reveal.waiting_for_card and reveal.reveal_count>seen:
				seen=reveal.reveal_count
				if mode==0 and (reveal.get_node("CardStage/CharacterArtwork").modulate.a!=1.0 or reveal.get_node("CardStage/AnimationPlayer").is_playing()):
					fail("low mode animation still active"); return
				if seen==1 and not reveal.get_node("CardStage/Intro").text.contains("PAID MILESTONE"):
					fail("milestone label lost"); return
				reveal.get_node("CardStage/NextButton").pressed.emit()
			await get_tree().process_frame
		var expected := [0,2,3][mode] as int
		if not finished[0] or seen!=2 or reveal.cinematic_count!=expected or reveal.cinematic_player.stream!=null:
			fail("quality %d reveal count %d cinematic count %d expected %d" % [mode,seen,reveal.cinematic_count,expected]); return
		print("PASS graphics quality ",mode," reveals=",seen," videos=",reveal.cinematic_count," decoder released")
		reveal.queue_free()
		await get_tree().process_frame
	GraphicsSettings.apply_preferences(0,-1,false,false)
	var scene: GachaScreen = load("res://scenes/ui/gacha_screen.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var batch: Array = []
	for i in 10: batch.append(rolls[0].duplicate())
	scene._summon_flow.show_results(batch,"paid_moonstones",scene._selected_banner)
	await get_tree().process_frame
	var grid: GridContainer = scene._results_layer.get_node("Center/Panel/Content/ResultsScroll/ResultGrid")
	var shared: Texture2D
	for card in grid.get_children():
		var portrait: PortraitView = card.get_node("Content/Portrait")
		if portrait.is_processing() or card.modulate.a!=1.0 or card.scale!=Vector2.ONE or portrait.portrait_texture==null:
			fail("low mode static card"); return
		if shared==null: shared=portrait.portrait_texture
		elif portrait.portrait_texture!=shared:
			fail("repeated portrait does not share texture"); return
	if scene._reveal_animations!=0 or grid.get_child_count()!=10 or scene.get_node("SummoningChamberAtmosphere").visible:
		fail("low mode result overhead"); return
	print("PASS ten static result cards share authored texture; chamber atmosphere hidden behind overlay")
	scene.queue_free()
	await get_tree().process_frame
	GraphicsSettings.apply_preferences(saved_quality,saved_fps,saved_adaptive,saved_monitor)
	await AudioDirector.drain_for_shutdown()
	get_tree().quit(0)
