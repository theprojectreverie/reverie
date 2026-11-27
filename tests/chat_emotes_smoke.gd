extends Node

func _ready() -> void:
	var screen := preload("res://scenes/ui/chat_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	var layout: VBoxContainer = screen._layout
	var field: LineEdit = layout.get_node("Composer/Message")
	var history: RichTextLabel = layout.get_node("History")
	var errors: Array[String] = []
	if layout.get_node("EmotePicker/EmojiScroll/EmojiGrid").get_child_count()!=16:errors.append("emoji count")
	if layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_child_count()!=118:errors.append("sticker count")
	if not layout.get_node("Composer/Emotes").disabled:errors.append("anonymous picker enabled")
	screen._emote_tab(true)
	if not layout.get_node("EmotePicker/StickerScroll").visible:errors.append("sticker tab")
	field.editable=true
	field.text="Hi"
	field.caret_column=2
	screen._insert_emoji(String.chr(0x1F600))
	if field.text!="Hi"+String.chr(0x1F600):errors.append("emoji insertion")
	field.text="a".repeat(199)
	field.caret_column=199
	screen._insert_emoji(String.chr(0x1F600))
	if field.text.length()!=200:errors.append("Unicode length limit")
	screen._insert_emoji(String.chr(0x1F600))
	if field.text.length()!=200:errors.append("200 character limit")
	field.text="abc"
	field.select(1,2)
	screen._insert_emoji(String.chr(0x1F600))
	if field.text!="a"+String.chr(0x1F600)+"c":errors.append("selection insertion")
	history.clear()
	screen._render_message_body(history,"[sticker:gerald]")
	if history.get_parsed_text().contains("[sticker:gerald]"):errors.append("known sticker rendered as text")
	for id in ["lilith_ghost_plush","revienna_fallen_matron","red_cloak_character","lilith_playful","gerald_chibi"]:
		history.clear()
		var marker: String = "[sticker:"+str(id)+"]"
		screen._render_message_body(history,marker)
		if history.get_parsed_text().contains(marker):errors.append("artwork missing: "+id)
	var mob_art = load("res://scripts/ui/components/mob_chat_art.gd")
	for id in mob_art.IDS:
		var texture: Texture2D = screen._sticker_texture(id)
		var expected := 128 if str(id).begins_with("emotes_") else 256
		if texture == null or texture.get_size() != Vector2(expected,expected):errors.append("mob art size: "+id)
		if not screen._sticker_unlocked(id):errors.append("mob sticker locked: "+id)
		history.clear()
		var token: String = "[sticker:"+id+"]"
		screen._render_message_body(history,token)
		if history.get_parsed_text().contains(token):errors.append("mob art rendering: "+id)
	for filter in [2,3,4,5,6,7,8,9]:
		screen._filter_stickers(filter)
		var visible_count := 0
		for button in layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_children():
			if button.visible:visible_count+=1
		if visible_count != (54 if filter==2 else (48 if filter==3 else 17)):errors.append("filter count: "+str(filter))
	screen._filter_stickers(0)
	history.clear()
	screen._render_message_body(history,"[sticker:unknown]")
	if not history.get_parsed_text().contains("[sticker:unknown]"):errors.append("unknown sticker fallback")
	screen._identity="fixture-self"
	var sent := {"id":"fixture-msg","playerId":"fixture-self","channel":"world","name":"Fixture","text":"[sticker:gerald_chibi]"}
	screen._accept_sent_message({"message":sent})
	screen._accept_sent_message({"message":sent})
	if screen._last_messages.size()!=1:errors.append("acknowledgment duplicate")
	if history.get_parsed_text().contains("[sticker:"):errors.append("acknowledgment rendering")
	var wrong := sent.duplicate()
	wrong["id"]="wrong-channel"
	wrong["channel"]="private"
	screen._accept_sent_message({"message":wrong})
	if screen._last_messages.size()!=1:errors.append("wrong channel acknowledgment")
	screen._identity=""
	screen._identity="fixture-emotes"
	# Exercise local pin/order logic without the real authenticated UI gate.
	screen._set_pin_mode(true, false)
	screen._sticker_pressed("gerald_chibi")
	if not screen._favorite_stickers.has("gerald_chibi") or not screen._operation.is_empty():errors.append("pin sticker without sending")
	screen._set_pin_mode(false, false)
	var stickers: HBoxContainer=layout.get_node("EmotePicker/StickerScroll/StickerGrid")
	if stickers.get_child(0).get_meta("sticker_id")!="gerald_chibi":errors.append("pinned ordering")
	screen._set_pin_mode(true, false)
	screen._sticker_pressed("gerald_chibi")
	screen._set_pin_mode(false, false)
	if not screen._favorite_stickers.is_empty():errors.append("unpin")
	field.editable=true
	field.text=""
	var recent:=String.chr(0x1F525)
	screen._insert_emoji(recent)
	screen._apply_emote_order()
	if layout.get_node("EmotePicker/EmojiScroll/EmojiGrid").get_child(0).get_meta("emoji")!=recent:errors.append("recent emoji ordering")
	if screen._contact_preview({"preview":"[sticker:lilith_playful]","preview_sender":"fixture-emotes"})!="You: Sticker: Lilith - Playful":errors.append("sticker conversation preview")
	screen._identity=""
	screen._load_emote_preferences()
	if not screen._recent_emojis.is_empty() or not screen._favorite_stickers.is_empty():errors.append("account preference isolation")
	screen._identity="fixture-sticker-owner"
	screen._apply_sticker_unlocks([])
	if screen._sticker_unlocked("ravienna_mythic") or not screen._sticker_unlocked("gerald_chibi"):errors.append("initial unlock rules")
	screen._set_pin_mode(true, false)
	screen._sticker_pressed("ravienna_mythic")
	if screen._favorite_stickers.has("ravienna_mythic"):errors.append("locked sticker pinned")
	screen._apply_sticker_unlocks(["ravienna_mythic","fake","ravienna_mythic"])
	if screen._unlocked_stickers!=["ravienna_mythic"]:errors.append("unlock allowlist")
	screen._sticker_pressed("ravienna_mythic")
	screen._set_pin_mode(false, false)
	if not screen._favorite_stickers.has("ravienna_mythic"):errors.append("unlocked favorite")
	if layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_child(0).get_meta("sticker_id")!="ravienna_mythic":errors.append("unlocked favorite ordering")
	screen._apply_sticker_unlocks([])
	history.clear()
	screen._render_message_body(history,"[sticker:ravienna_mythic]")
	if history.get_parsed_text().contains("[sticker:ravienna_mythic]"):errors.append("locked recipient rendering")
	screen._identity=""
	screen._load_emote_preferences()
	screen._select("blocks")
	if layout.get_node("EmotePicker").visible or layout.get_node("Composer").visible:errors.append("blocked tab visibility")
	print("CHAT_EMOTES_SMOKE: "+("PASS" if errors.is_empty() else str(errors)))
	screen.queue_free()
	AudioDirector.stop_all_audio_immediately()
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	get_tree().quit(0 if errors.is_empty() else 1)