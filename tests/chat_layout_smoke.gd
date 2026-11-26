extends Node

func _ready() -> void:
	var errors: Array[String] = []
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		var view := SubViewport.new()
		view.size = dimensions
		add_child(view)
		var screen := preload("res://scenes/ui/chat_screen.tscn").instantiate()
		view.add_child(screen)
		var layout: VBoxContainer = screen._layout
		layout.get_node("Contacts").show()
		layout.get_node("EmotePicker").show()
		screen._emote_tab(true)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var history: Control = layout.get_node("History")
		var composer: Control = layout.get_node("Composer")
		var scroll: ScrollContainer = layout.get_node("EmotePicker/StickerScroll")
		print("CHAT_LAYOUT ",dimensions," history=",history.size," composer=",composer.get_global_rect()," scroll=",scroll.size," layout=",layout.get_global_rect())
		if composer.get_global_rect().end.y>dimensions.y or composer.get_global_rect().end.x>dimensions.x:
			errors.append("composer overflow "+str(dimensions))
		if history.size.y<70:errors.append("history too small "+str(dimensions))
		if scroll.size.x>dimensions.x:errors.append("picker overflow "+str(dimensions))
		if layout.get_global_rect().end.y>dimensions.y or layout.get_global_rect().position.y<0:errors.append("layout overflow "+str(dimensions))
		if screen._shell.get_node("Margin/Panel/Root/Header").get_global_rect().position.y<0:errors.append("header overflow "+str(dimensions))
		screen._profile_target="fixture-profile"
		screen._profile_card.show()
		screen._complete_profile_action("inspect_profile",HTTPRequest.RESULT_SUCCESS,200,{"id":"fixture-profile","name":"Fixture Friend","avatar":"kael_avatar","title":"Dawn Wanderer","online":true,"stats":{"level":20,"xp":"10000","victories":10,"landmarks":7},"achievementCount":5,"achievementTotal":15,"badges":[{"name":"Dawn Wanderer"},{"name":"Expedition Veteran"},{"name":"United Front"}]})
		await get_tree().process_frame
		await get_tree().process_frame
		var panel: PanelContainer=screen._profile_card.get_node("Center/Panel")
		var rect:=panel.get_global_rect()
		print("CHAT_PROFILE_LAYOUT ",dimensions," panel=",rect)
		if rect.position.x<0 or rect.position.y<0 or rect.end.x>dimensions.x or rect.end.y>dimensions.y:errors.append("profile card overflow "+str(dimensions))
		screen._complete_profile_action("inspect_profile",HTTPRequest.RESULT_SUCCESS,404,{"error":"friend_profile_unavailable"})
		if screen._profile_access or screen._profile_content().get_node("Stats").text!="" or screen._profile_content().get_node("Identity/Portrait").texture!=null:errors.append("profile access revocation")
		screen._close_chat_profile()
		screen.queue_free()
		view.queue_free()
		await get_tree().process_frame
	print("CHAT_LAYOUT_SMOKE: ", "PASS" if errors.is_empty() else str(errors))
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if errors.is_empty() else 1)