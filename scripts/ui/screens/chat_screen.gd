extends OverlayScreen
const LAYOUT = preload("res://scenes/ui/components/chat_layout.tscn")
var _layout: VBoxContainer
var _request: HTTPRequest
var _channel := "world"
var _operation := ""
var _requested_channel := ""
var _identity := ""
var _elapsed := 3.0
var _last_messages: Array = []
var _draft := ""
var _party_id := ""
var _guild_id := ""
var _blocked_mode := false
var _recipient := ""
var _requested_recipient := ""
var _contacts_elapsed := 10.0
var _contacts_loaded := false
var _next_send_at := 0
var _recent_sends: Array[int] = []
var _initial_recipient := ""
var _initial_channel := "world"
var _clear_draft_on_send := true
var _reply_to := ""
var _sent_reply_to := ""
var _report_dialog: ConfirmationDialog
var _report_id := ""
var _report_owner := ""
var _notice_http: HTTPRequest
var _notice_dialog: ConfirmationDialog
var _notice_owner := ""
var _notice_op := ""
var _notice_next := 0
var _notice_rows: Array = []
var _notice_shown_ids: Array[String] = []
var _notice_unread := 0
var _mute_deadline := 0
var _notice_alerted := {}
const EMOJI_CODES = [0x1F600,0x1F602,0x1F60D,0x1F60E,0x1F62D,0x1F621,0x1F631,0x1F914,0x1F44D,0x1F44B,0x1F64F,0x1F525,0x2728,0x2764,0x1F480,0x1F389]
const STICKERS = {
	"kael": preload("res://assets/characters/kael_avatar/combat_sprite.png"),
	"gerald": preload("res://assets/characters/gerald/combat_sprite.png"),
	"lilith": preload("res://assets/characters/lilith/combat_sprite.png"),
	"elathra": preload("res://resources/ui/chat_stickers/elathra.tres"),
	"rose_slime": preload("res://resources/ui/chat_stickers/rose_slime.tres"),
	"lilith_ghost_plush": preload("res://assets/ui/chat_stickers/lilith_ghost_plush.jpg"),
	"revienna_fallen_matron": preload("res://assets/ui/chat_stickers/revienna_fallen_matron.jpg"),
	"red_cloak_character": preload("res://assets/ui/chat_stickers/red_cloak_character.jpg"),
	"lilith_playful": preload("res://assets/ui/chat_stickers/lilith_playful.jpg"),
	"gerald_chibi": preload("res://assets/ui/chat_stickers/gerald.jpg"),
	"kael_mythic": preload("res://assets/characters/kael_mythic/portrait_512.png"),
	"lilith_mythic": preload("res://assets/characters/lilith_mythic/portrait_512.png"),
	"gerald_mythic": preload("res://assets/characters/gerald_mythic/portrait_512.png"),
	"ravienna_mythic": preload("res://assets/characters/ravienna_mythic/portrait_512.png"),
	"cassien_mythic": preload("res://assets/characters/cassien/portrait_512.png"),
	"nyx_mythic": preload("res://assets/characters/nyx_mythic/portrait_512.png"),
	"crimson_witch_mythic": preload("res://assets/characters/crimson_witch_mythic/portrait_512.png"),
	"mirene_mythic": preload("res://assets/characters/mirene/portrait_512.png"),
	"caelith_mythic": preload("res://assets/characters/caelith_mythic/portrait_512.png")
}
const FREE_STICKER_IDS = ["lilith_ghost_plush","revienna_fallen_matron","red_cloak_character","lilith_playful","gerald_chibi","elathra","rose_slime"]
const CHARACTER_STICKER_IDS = ["kael_mythic","lilith_mythic","gerald_mythic","ravienna_mythic","cassien_mythic","nyx_mythic","crimson_witch_mythic","mirene_mythic","caelith_mythic"]
const STICKER_PICKER_IDS = FREE_STICKER_IDS + CHARACTER_STICKER_IDS
const STICKER_LABELS = {
	"lilith_ghost_plush": "Lilith - Ghost plush",
	"revienna_fallen_matron": "Revienna - Fallen Matron",
	"red_cloak_character": "Red cloak - Unimpressed",
	"lilith_playful": "Lilith - Playful",
	"gerald_chibi": "Gerald - Guardian",
	"elathra": "Elathra",
	"rose_slime": "Rose Slime",
	"kael_mythic": "Kael - Mythic Aspect",
	"lilith_mythic": "Lilith - Mythic Aspect",
	"gerald_mythic": "Gerald - Mythic Aspect",
	"ravienna_mythic": "Ravienna - Mythic Aspect",
	"cassien_mythic": "Cassien - Mythic Aspect",
	"nyx_mythic": "Nyx - Mythic Aspect",
	"crimson_witch_mythic": "Crimson Witch - Mythic Aspect",
	"mirene_mythic": "Mirene - Mythic Aspect",
	"caelith_mythic": "Caelith - Mythic Aspect"
}
var _emoji_font: FontVariation
var _recent_emojis: Array[String] = []
var _favorite_stickers: Array[String] = []
var _pin_mode := false
var _unlocked_stickers: Array[String] = []
var _sticker_request: HTTPRequest
var _sticker_request_player := ""
var _sticker_refresh_at := 0
var _profile_card: Control
var _profile_target := ""
var _profile_access := false
var _profile_elapsed := 0.0
var _profile_notice := ""

func _init() -> void:
	screen_title = "World Chat"
	screen_subtitle = "Talk to players across Reverie"

func set_initial_channel(channel: String) -> void:
	if channel in ["world","party","private","guild"]:
		_initial_channel=channel

func set_initial_recipient(player_id: String) -> void:
	_initial_recipient=player_id

func _build_content() -> void:
	_layout = LAYOUT.instantiate() as VBoxContainer
	content.add_child(_layout)
	_setup_emotes()
	_profile_card = preload("res://scenes/ui/components/chat_profile_card.tscn").instantiate()
	add_child(_profile_card)
	_profile_content().get_node("Header/Close").pressed.connect(_close_chat_profile)
	_profile_content().get_node("Invite").pressed.connect(_invite_from_chat)
	_layout.get_node("PlayerActions/Profile").pressed.connect(_inspect_selected_player)
	_layout.get_node("History").meta_clicked.connect(_reply_clicked)
	_report_dialog = preload("res://scenes/ui/components/chat_report_dialog.tscn").instantiate() as ConfirmationDialog
	add_child(_report_dialog)
	_report_dialog.confirmed.connect(_submit_report)
	_notice_dialog = preload("res://scenes/ui/components/chat_moderation_notice.tscn").instantiate() as ConfirmationDialog
	add_child(_notice_dialog)
	_notice_dialog.confirmed.connect(_ack_notices)
	_notice_http = HTTPRequest.new()
	_notice_http.timeout = 8.0
	add_child(_notice_http)
	_notice_http.request_completed.connect(_notice_completed)
	_layout.get_node("Moderation/Notices").pressed.connect(_open_notices)
	_layout.get_node("ReplyBar/Cancel").pressed.connect(_cancel_reply)
	resized.connect(_fit_chat_layout)
	_fit_chat_layout()
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	add_child(_request)
	_request.request_completed.connect(_completed)
	_sticker_request=HTTPRequest.new()
	_sticker_request.timeout=8.0
	add_child(_sticker_request)
	_sticker_request.request_completed.connect(_sticker_unlocks_completed)
	_layout.get_node("Channels/World").pressed.connect(_select.bind("world"))
	_layout.get_node("Channels/Party").pressed.connect(_select.bind("party"))
	_layout.get_node("Channels/Guild").pressed.connect(_select.bind("guild"))
	_layout.get_node("Channels/Private").pressed.connect(_select.bind("private"))
	_layout.get_node("Contacts").item_selected.connect(_contact_selected)
	_layout.get_node("Channels/Blocks").pressed.connect(_select.bind("blocks"))
	_layout.get_node("Composer/Send").pressed.connect(_send)
	_layout.get_node("Composer/Message").text_submitted.connect(func(_value):_send())
	_layout.get_node("PlayerActions/Block").pressed.connect(_block)
	_layout.get_node("PlayerActions/Players").item_selected.connect(func(_index):_update_controls())
	AuthGateway.authentication_changed.connect(_auth_changed)
	_identity = str(AuthGateway.current_player().get("id",""))
	_load_emote_preferences()
	var options: OptionButton = _layout.get_node("Contacts")
	options.add_theme_constant_override("icon_max_width",32)
	options.get_popup().add_theme_constant_override("icon_max_width",32)
	if not _initial_recipient.is_empty():
		_select("private")
		_recipient=_initial_recipient
		_initial_recipient=""
	elif _initial_channel!="world":
		_select(_initial_channel)
	_update_controls()

func _auth_changed(authenticated: bool, player: Dictionary) -> void:
	var id := str(player.get("id","")) if authenticated else ""
	if id != _identity:
		_notice_http.cancel_request()
		_notice_op=""
		_notice_owner=""
		_notice_next=0
		_notice_rows.clear()
		_notice_shown_ids.clear()
		_notice_unread=0
		_mute_deadline=0
		_notice_alerted.clear()
		_notice_dialog.hide()
		_refresh_notice_bar()
		_report_id = ""
		_report_owner = ""
		if _report_dialog != null:_report_dialog.hide()
		_close_chat_profile()
		_hide_emotes()
		_request.cancel_request()
		_operation = ""
		_sticker_request.cancel_request()
		_sticker_request_player=""
		_unlocked_stickers.clear()
		_sticker_refresh_at=0
		_identity = id
		_load_emote_preferences()
		_next_send_at=0
		_recent_sends.clear()
		_recipient=""
		_contacts_loaded=false
		_contacts_elapsed=10.0
		_layout.get_node("Contacts").clear()
		_layout.get_node("Composer/Message").clear()
		_clear_messages()
		_elapsed = 3.0
	_update_controls()

func _clear_messages() -> void:
	_cancel_reply()
	_last_messages.clear()
	_party_id = ""
	_guild_id = ""
	_layout.get_node("History").text = ""
	_layout.get_node("PlayerActions/Players").clear()

func _select(channel: String) -> void:
	_close_chat_profile()
	_hide_emotes()
	if _channel != channel:
		_request.cancel_request()
		_operation = ""
		_channel = channel
		_recipient=""
		_contacts_loaded=false
		_contacts_elapsed=10.0
		_layout.get_node("Contacts").clear()
		_layout.get_node("Composer/Message").clear()
		_clear_messages()
		_elapsed = 3.0
	_blocked_mode = _channel == "blocks"
	for button in ["World","Party","Guild","Private","Blocks"]:
		_layout.get_node("Channels/"+button).set_pressed_no_signal(button.to_lower()==_channel)
	_layout.get_node("PlayerActions/Block").text = "Unblock" if _blocked_mode else "Block player"
	_layout.get_node("Composer").visible = not _blocked_mode
	_layout.get_node("Contacts").visible = _channel=="private"
	_update_controls()

func _contact_selected(index: int) -> void:
	_close_chat_profile()
	_hide_emotes()
	var options: OptionButton = _layout.get_node("Contacts")
	var id:=str(options.get_item_metadata(index))
	if id==_recipient:return
	_request.cancel_request()
	_operation=""
	_recipient=id
	_layout.get_node("Composer/Message").clear()
	_clear_messages()
	_elapsed=3.0
	_update_controls()

func _render_contacts(entries: Array) -> void:
	var options: OptionButton = _layout.get_node("Contacts")
	options.clear()
	options.add_item("Select a friend")
	options.set_item_metadata(0,"")
	var found:=false
	for entry in entries:
		var avatar:=preload("res://scripts/ui/social_portrait.gd").texture(str(entry.avatar))
		var unread:=int(entry.get("unread",0))
		var label:=str(entry.name)+(" - Online" if bool(entry.get("online",false)) else " - Offline")+(" (%d)" % unread if unread>0 else "")
		var preview := _contact_preview(entry)
		if not preview.is_empty():label+=" | "+preview
		options.add_icon_item(avatar,label)
		options.set_item_metadata(options.item_count-1,str(entry.id))
		if str(entry.id)==_recipient:
			options.select(options.item_count-1)
			found=true
	if not found:
		options.select(0)
		if not _recipient.is_empty():
			_recipient=""
			_layout.get_node("Composer/Message").clear()
			_clear_messages()
		_layout.get_node("Status").text="Select an accepted friend." if not entries.is_empty() else "Add a friend to start private chat."
	_contacts_loaded=true

func _process(delta: float) -> void:
	if _layout == null:
		return
	if not AuthGateway.is_authenticated():
		_layout.get_node("Status").text = "Sign in to use chat."
		return
	if _layout.get_node("EmotePicker").visible and _layout.get_node("EmotePicker/StickerScroll").visible and Time.get_ticks_msec()>=_sticker_refresh_at:_refresh_sticker_unlocks()
	if Time.get_ticks_msec()>=_notice_next and _notice_op.is_empty():
		_request_notices()
	if _mute_deadline>0:
		if Time.get_ticks_msec()>=_mute_deadline:
			_mute_deadline=0
			_notice_next=0
			_update_controls()
		_refresh_notice_bar()
	_elapsed += delta
	if _next_send_at>0 and Time.get_ticks_msec()>=_next_send_at:
		_next_send_at=0
		_update_controls()
	_contacts_elapsed+=delta
	if _profile_card.visible:
		_profile_elapsed+=delta
		if _profile_elapsed>=5.0 and _operation.is_empty() and _profile_access:
			_profile_elapsed=0.0
			_begin("inspect_profile","/friend-profile?playerId="+_profile_target.uri_encode(),HTTPClient.METHOD_GET)
		return
	if _channel=="private" and _operation.is_empty():
		if _contacts_elapsed>=10.0:
			_contacts_elapsed=0.0
			_begin("contacts","/contacts",HTTPClient.METHOD_GET)
			return
		if _recipient.is_empty():return
	if _elapsed >= 3.0 and _operation.is_empty():
		_elapsed = 0.0
		_begin("read","/blocks" if _blocked_mode else "/messages?channel="+_channel+("&recipientId="+_recipient.uri_encode() if _channel=="private" else ""),HTTPClient.METHOD_GET)

func _begin(operation: String, path: String, method: HTTPClient.Method, data: Dictionary = {}) -> bool:
	if not _operation.is_empty() or not AuthGateway.access_token_ready_for_connection():
		return false
	_operation = operation
	_requested_channel = _channel
	_requested_recipient = _recipient
	var headers := PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
	var prefix := "/v1/social" if operation=="inspect_profile" else ("/v1/co-op" if operation=="invite_player" else "/v1/chat")
	var err := _request.request(AuthGateway.api_base_url+prefix+path,headers,method,JSON.stringify(data) if method==HTTPClient.METHOD_POST else "")
	if err!=OK:
		_operation = ""
		_layout.get_node("Status").text = "Chat connection unavailable."
	_update_controls()
	return err==OK

func _send() -> void:
	if _blocked_mode or not AuthGateway.is_authenticated() or (_channel=="private" and (_recipient.is_empty() or not _contacts_loaded)) or (_channel=="guild" and _guild_id.is_empty()) or _next_send_at>0 or _mute_deadline>Time.get_ticks_msec():
		return
	var field: LineEdit = _layout.get_node("Composer/Message")
	var message := field.text.strip_edges()
	if message.is_empty():
		return
	_send_message(message,true)

func _send_message(message: String, clear_draft: bool) -> void:
	if _blocked_mode or not AuthGateway.is_authenticated() or (_channel=="private" and (_recipient.is_empty() or not _contacts_loaded)) or (_channel=="guild" and _guild_id.is_empty()) or _next_send_at>0 or _mute_deadline>Time.get_ticks_msec():
		return
	if message.is_empty() or message.length()>200:
		_layout.get_node("Status").text = "Message is too long (200 characters)."
		return
	var field: LineEdit = _layout.get_node("Composer/Message")
	var payload: Dictionary={"channel":_channel,"text":message}
	if _channel=="private":payload["recipientId"]=_recipient
	if _channel=="guild":payload["guildId"]=_guild_id
	if not _reply_to.is_empty():payload["replyTo"]=_reply_to
	if _begin("send","/messages",HTTPClient.METHOD_POST,payload):
		_sent_reply_to = _reply_to
		_draft = field.text
		_clear_draft_on_send = clear_draft
		_track_chat_send()
		_update_controls()

func _block() -> void:
	var players: OptionButton = _layout.get_node("PlayerActions/Players")
	if players.selected<0:
		return
	var id := str(players.get_item_metadata(players.selected))
	if id.is_empty():
		return
	_begin("block","/unblock" if _blocked_mode else "/block",HTTPClient.METHOD_POST,{"playerId":id})

func _update_controls() -> void:
	if _layout == null:return
	var ready: bool = AuthGateway.is_authenticated() and _operation.is_empty()
	var has_recipient:=(_channel!="private" or (_contacts_loaded and not _recipient.is_empty())) and (_channel!="guild" or not _guild_id.is_empty())
	_layout.get_node("Contacts").disabled=not ready
	_layout.get_node("Composer/Send").disabled = not ready or not has_recipient or _next_send_at>0 or _mute_deadline>Time.get_ticks_msec()
	_layout.get_node("Composer/Message").editable = AuthGateway.is_authenticated() and has_recipient
	var emotes_allowed: bool = AuthGateway.is_authenticated() and has_recipient and not _blocked_mode and _mute_deadline<=Time.get_ticks_msec()
	_layout.get_node("Composer/Emotes").disabled = not emotes_allowed
	if not emotes_allowed:_hide_emotes()
	for button in _layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_children():
		button.disabled = not emotes_allowed or (not _pin_mode and (not ready or _next_send_at>0))
	var players: OptionButton = _layout.get_node("PlayerActions/Players")
	_layout.get_node("PlayerActions/Block").disabled = not ready or players.selected<0
	_layout.get_node("PlayerActions/Profile").visible=not _blocked_mode
	_layout.get_node("PlayerActions/Profile").disabled=not ready or _blocked_mode or _selected_profile_id().is_empty()
	if _profile_card!=null:_profile_content().get_node("Invite").disabled=not ready or not _profile_access

func _completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var operation := _operation
	_operation = ""
	if _requested_channel!=_channel or _requested_recipient!=_recipient or _identity!=str(AuthGateway.current_player().get("id","")):
		return
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if operation in ["inspect_profile","invite_player"]:
		_complete_profile_action(operation,result,code,data)
		_update_controls()
		return
	if result!=HTTPRequest.RESULT_SUCCESS or not data is Dictionary or code<200 or code>=300:
		var reason := str(data.get("error","")) if data is Dictionary else ""
		if code==403 and reason not in ["sticker_locked","chat_muted"] and _channel in ["party","private","guild"]:_clear_messages()
		if reason=="guild_membership_required":
			_layout.get_node("Composer/Message").clear()
			_hide_emotes()
		if reason=="sticker_locked":
			_sticker_refresh_at=0
			_refresh_sticker_unlocks()
		if reason=="friendship_required":
			_recipient=""
			_contacts_loaded=false
			_contacts_elapsed=10.0
			_layout.get_node("Composer/Message").clear()
		_layout.get_node("Status").text = "Join a party to use Party Chat." if reason=="party_membership_required" else ("You're sending too quickly." if code==429 else "Chat unavailable. Try again.")
		if reason=="guild_membership_required":_layout.get_node("Status").text="Join a guild to use Guild Chat."
		if reason=="chat_duplicate_spam":
			_layout.get_node("Status").text="Repeated world message blocked. Try a different message."
			EventBus.toast_requested.emit("Repeated world message blocked. Try a different message.")
		if code==429 and operation=="send" and reason!="chat_duplicate_spam":
			_next_send_at=maxi(_next_send_at,Time.get_ticks_msec()+10000)
		if reason=="sticker_locked":_layout.get_node("Status").text="Obtain the matching Mythic character to unlock this sticker."
		if reason=="chat_muted":
			_notice_next=0
			_layout.get_node("Status").text="Your chat access is temporarily muted."
			EventBus.toast_requested.emit("Your chat access is temporarily muted.")
		if reason=="report_message_unavailable":EventBus.toast_requested.emit("This message is no longer available to report.")
		if reason=="report_limit":EventBus.toast_requested.emit("Daily report limit reached.")
		if reason=="reply_unavailable":
			_cancel_reply()
			_layout.get_node("Status").text="Original message unavailable. Send again without reply."
		_update_controls()
		return
	if operation=="contacts":
		_render_contacts(data.get("players",[]))
	elif operation=="read":
		if _blocked_mode:
			_render_blocks(data.get("players",[]))
		else:
			var messages: Array = data.get("messages",[])
			var party := str(data.get("partyId",""))
			if _channel=="guild":
				var guild := str(data.get("guildId",""))
				if guild.is_empty() or guild=="<null>":
					_clear_messages()
					_update_controls()
					return
				if guild!=_guild_id:
					_clear_messages()
					_layout.get_node("Composer/Message").clear()
					_hide_emotes()
					_guild_id=guild
			if _channel=="private" and messages!=_last_messages:
				AuthGateway.refresh_social_summary()
				_contacts_elapsed=10.0
			if messages!=_last_messages or party!=_party_id:
				_party_id=party
				_render(messages)
			_layout.get_node("Status").text = "World channel — all signed-in players" if _channel=="world" else "Party channel — current members only" if _channel=="party" else "Private chat - latest 100 messages; history is cleared if friendship ends."
		if _channel=="guild":_layout.get_node("Status").text="Guild channel - current members only."
	elif operation=="send":
		var field: LineEdit = _layout.get_node("Composer/Message")
		if _clear_draft_on_send and field.text==_draft:field.clear()
		if _reply_to==_sent_reply_to:_cancel_reply()
		_hide_emotes()
		_accept_sent_message(data)
		_elapsed=3.0
		_layout.get_node("Status").text = "Message sent."
	elif operation=="report":
		EventBus.toast_requested.emit("Already reported." if bool(data.get("duplicate",false)) else "Report sent to the moderation team.")
		_elapsed=3.0
	elif operation=="block":
		_clear_messages()
		_elapsed=3.0
		_layout.get_node("Status").text = "Player unblocked." if _blocked_mode else "Player blocked."
	_update_controls()

func _render(messages: Array) -> void:
	_last_messages=messages.duplicate(true)
	var history: RichTextLabel = _layout.get_node("History")
	history.clear()
	var players: OptionButton = _layout.get_node("PlayerActions/Players")
	var old_id := str(players.get_item_metadata(players.selected)) if players.selected>=0 else ""
	players.clear()
	var seen := {}
	for message in messages:
		if not message is Dictionary:continue
		var name_text := str(message.get("name","Player"))
		var id := str(message.get("playerId",""))
		if _channel == "world" and str(message.get("kind", "")) == "mythic_summon":
			var portrait := PortraitAssetSource.texture_for(str(message.get("characterId", "")), "collection")
			if portrait != null:
				history.add_image(portrait, 32, 32)
				history.add_text("  ")
			history.push_color(Color("#e9a5ff"))
			history.push_bold()
			history.add_text("[MYTHIC SUMMON] ")
			history.pop()
			history.add_text(str(message.get("text", "")) + "\n")
			history.pop()
			continue
		var parent_id := str(message.get("replyTo",""))
		if not parent_id.is_empty() and parent_id!="<null>":
			var parent := _find_message(parent_id)
			history.push_color(Color("#aaa3be"))
			history.add_text("Reply to "+_reply_preview(parent)+"\n" if not parent.is_empty() else "Reply to unavailable message\n")
			history.pop()
		var avatar := preload("res://scripts/ui/social_portrait.gd").texture(str(message.get("avatar","kael_avatar")))
		if avatar != null:
			history.add_image(avatar,32,32)
			history.add_text("  ")
		history.push_color(UITheme.GOLD if id==_identity else UITheme.TEAL)
		if not id.is_empty() and id!=_identity:history.push_meta("profile:"+id)
		history.add_text(name_text)
		if not id.is_empty() and id!=_identity:history.pop()
		history.pop()
		var equipped_title:=str(message.get("title",""))
		if not equipped_title.is_empty():
			history.push_color(preload("res://scripts/ui/achievement_title_style.gd").color(equipped_title))
			history.add_text(" ["+equipped_title+"]")
			history.pop()
		history.push_color(UITheme.GOLD if id==_identity else UITheme.TEAL)
		history.add_text(": ")
		history.pop()
		_render_message_body(history,str(message.get("text","")))
		var message_id := str(message.get("id",""))
		if not message_id.is_empty():
			history.push_color(UITheme.TEAL)
			history.push_meta("reply:"+message_id)
			history.add_text("Reply")
			history.pop()
			history.pop()
			if _channel=="world" and id!=_identity and not id.is_empty():
				history.add_text("  ")
				history.push_color(Color("#e8ae9d"))
				history.push_meta("report:"+message_id)
				history.add_text("Report")
				history.pop()
				history.pop()
			history.add_text("\n")
		if id!=_identity and not id.is_empty() and not seen.has(id):
			seen[id]=true
			players.add_item(name_text)
			players.set_item_metadata(players.item_count-1,id)
			if id==old_id:players.select(players.item_count-1)
	if messages.is_empty():history.add_text("No recent messages.")
	if not _reply_to.is_empty() and _find_message(_reply_to).is_empty():_cancel_reply()

func _render_blocks(blocks: Array) -> void:
	var history: RichTextLabel = _layout.get_node("History")
	history.clear()
	var players: OptionButton = _layout.get_node("PlayerActions/Players")
	var old_id := str(players.get_item_metadata(players.selected)) if players.selected>=0 else ""
	players.clear()
	for entry in blocks:
		players.add_item(str(entry.name))
		players.set_item_metadata(players.item_count-1,str(entry.id))
		if str(entry.id)==old_id:players.select(players.item_count-1)
		history.add_text(str(entry.name)+"\n")
	if blocks.is_empty():history.add_text("No blocked players.")
	_layout.get_node("Status").text = "Manage blocked players"


func _setup_emotes() -> void:
	var toggle: Button = _layout.get_node("Composer/Emotes")
	toggle.toggled.connect(_toggle_emote_picker)
	_layout.get_node("EmotePicker/Tabs/Favorites").toggled.connect(_set_pin_mode)
	_layout.get_node("EmotePicker/Tabs/Emoji").pressed.connect(_emote_tab.bind(false))
	_layout.get_node("EmotePicker/Tabs/Stickers").pressed.connect(_emote_tab.bind(true))
	var system_emoji := SystemFont.new()
	system_emoji.font_names = PackedStringArray(["Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji","Noto Emoji"])
	_emoji_font = FontVariation.new()
	_emoji_font.base_font = _layout.get_node("Composer/Message").get_theme_font("font")
	_emoji_font.fallbacks = [system_emoji]
	var field: LineEdit = _layout.get_node("Composer/Message")
	field.add_theme_font_override("font",_emoji_font)
	var history: RichTextLabel = _layout.get_node("History")
	history.add_theme_font_override("normal_font",_emoji_font)
	for code in EMOJI_CODES:
		var emoji := String.chr(code)
		var button := Button.new()
		button.custom_minimum_size = Vector2(44,44)
		button.text = emoji
		button.set_meta("emoji",emoji)
		button.add_theme_font_override("font",_emoji_font)
		button.add_theme_font_size_override("font_size",23)
		button.pressed.connect(_insert_emoji.bind(emoji))
		_layout.get_node("EmotePicker/EmojiScroll/EmojiGrid").add_child(button)
	for id in STICKER_PICKER_IDS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(84,84)
		button.icon = STICKERS[id]
		button.set_meta("sticker_id",str(id))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = "Send "+str(STICKER_LABELS.get(id,id))+" sticker"
		button.pressed.connect(_sticker_pressed.bind(str(id)))
		_layout.get_node("EmotePicker/StickerScroll/StickerGrid").add_child(button)

func _emote_tab(stickers: bool) -> void:
	if not stickers:_set_pin_mode(false)
	_layout.get_node("EmotePicker/Tabs/Favorites").visible=stickers
	_layout.get_node("EmotePicker/Tabs/Emoji").set_pressed_no_signal(not stickers)
	_layout.get_node("EmotePicker/Tabs/Stickers").set_pressed_no_signal(stickers)
	_layout.get_node("EmotePicker/Tabs/Hint").text = "Tap to send | swipe for more" if stickers else "Tap to insert | swipe for more"
	_layout.get_node("EmotePicker/EmojiScroll").visible = not stickers
	_layout.get_node("EmotePicker/StickerScroll").visible = stickers
	if stickers:_refresh_sticker_unlocks()

func _hide_emotes() -> void:
	if _layout==null:return
	_set_pin_mode(false,false)
	_layout.get_node("EmotePicker").hide()
	_layout.get_node("Composer/Emotes").set_pressed_no_signal(false)

func _insert_emoji(emoji: String) -> void:
	var field: LineEdit = _layout.get_node("Composer/Message")
	if not field.editable:return
	var candidate := field.text
	if field.has_selection():
		candidate = candidate.erase(field.get_selection_from_column(),field.get_selection_to_column()-field.get_selection_from_column())
	if (candidate+emoji).length()>200:return
	if field.has_selection():
		var start := field.get_selection_from_column()
		field.text = candidate.insert(start,emoji)
		field.caret_column = start+emoji.length()
		field.deselect()
	else:
		field.insert_text_at_caret(emoji)
	if not _identity.is_empty():
		_recent_emojis.erase(emoji)
		_recent_emojis.push_front(emoji)
		if _recent_emojis.size()>8:_recent_emojis.resize(8)
		_save_emote_preferences()

func _send_sticker(id: String) -> void:
	if STICKERS.has(id) and _sticker_unlocked(id):_send_message("[sticker:"+id+"]",false)

func _render_message_body(history: RichTextLabel, message: String) -> void:
	if message.begins_with("[sticker:") and message.ends_with("]"):
		var id := message.substr(9,message.length()-10)
		if STICKERS.has(id):
			var texture: Texture2D = STICKERS[id]
			history.add_text("\n")
			var art_size := texture.get_size()
			var scale_factor := 124.0/maxf(art_size.x,art_size.y)
			history.add_image(texture,maxi(1,roundi(art_size.x*scale_factor)),maxi(1,roundi(art_size.y*scale_factor)),Color.WHITE,INLINE_ALIGNMENT_CENTER)
			history.add_text("\n")
			return
	history.add_text(message+"\n")

func _fit_chat_layout() -> void:
	if _layout==null or _shell==null:return
	var compact := size.y<650
	var margin: MarginContainer = _shell.get_node("Margin")
	var inset := 12.0 if compact else 34.0
	margin.offset_left=inset
	margin.offset_top=inset
	margin.offset_right=-inset
	margin.offset_bottom=-inset
	var panel: PanelContainer = margin.get_node("Panel")
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBox
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_content_margin(side,10.0 if compact else 18.0)
	panel.add_theme_stylebox_override("panel",style)
	var root: VBoxContainer = panel.get_node("Root")
	root.add_theme_constant_override("separation",5 if compact else 12)
	var header: HBoxContainer = root.get_node("Header")
	header.get_node("Titles/Subtitle").visible=not compact
	_layout.add_theme_constant_override("separation",4 if compact else 7)
	_layout.get_node("History").custom_minimum_size.y=70 if compact else 110
	_layout.get_node("Status").add_theme_font_size_override("font_size",14 if compact else 16)
	_layout.get_node("Notice").add_theme_font_size_override("font_size",12 if compact else 14)
	_layout.get_node("Notice").visible=not (compact and not _reply_to.is_empty())
	_layout.get_node("EmotePicker/StickerScroll").custom_minimum_size.y=76 if compact else 96
	for button in _layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_children():
		button.custom_minimum_size=Vector2(64,64) if compact else Vector2(84,84)

# Only display a send after the API has acknowledged it. The next poll remains authoritative.
func _accept_sent_message(data: Dictionary) -> void:
	var message = data.get("message")
	if not message is Dictionary:return
	var id := str(message.get("id",""))
	if id.is_empty() or str(message.get("playerId",""))!=_identity:return
	if str(message.get("channel",""))!=_channel:return
	if _channel=="private" and str(message.get("recipientId",""))!=_recipient:return
	if _channel=="guild" and str(data.get("guildId",""))!=_guild_id:return
	if _channel=="party":
		var party := str(data.get("partyId",""))
		if party.is_empty() or party=="<null>":return
		if party!=_party_id:
			_clear_messages()
			_party_id=party
	for item in _last_messages:
		if item is Dictionary and str(item.get("id",""))==id:return
	var updated := _last_messages.duplicate()
	updated.append(message)
	if updated.size()>100:updated=updated.slice(-100)
	_render(updated)

func _find_message(id: String) -> Dictionary:
	for message in _last_messages:
		if message is Dictionary and str(message.get("id",""))==id:
			return message
	return {}

func _reply_preview(message: Dictionary) -> String:
	var body := str(message.get("text",""))
	if body.begins_with("[sticker:") and body.ends_with("]"):
		var sticker := body.substr(9,body.length()-10)
		if STICKERS.has(sticker):body="[Sticker: "+str(STICKER_LABELS.get(sticker,sticker))+"]"
	if body.length()>64:body=body.left(64)+"..."
	return str(message.get("name","Player"))+": "+body

func _request_notices(ids: Array[String]=[]) -> void:
	if _notice_http==null or not _notice_op.is_empty() or not AuthGateway.access_token_ready_for_connection():return
	_notice_owner=_identity
	if _notice_owner.is_empty():return
	_notice_op="read" if ids.is_empty() else "ack"
	_notice_next=Time.get_ticks_msec()+15000
	var headers:=PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
	var path:="moderation-status" if ids.is_empty() else "moderation-ack"
	var err:=_notice_http.request(AuthGateway.api_base_url+"/v1/chat/"+path,headers,HTTPClient.METHOD_GET if ids.is_empty() else HTTPClient.METHOD_POST,"" if ids.is_empty() else JSON.stringify({"ids":ids}))
	if err!=OK:
		_notice_op=""
		if not ids.is_empty():EventBus.toast_requested.emit("Could not mark notices read. Try again.")

func _notice_completed(result: int,code: int,_headers: PackedStringArray,bytes: PackedByteArray) -> void:
	var op:=_notice_op
	_notice_op=""
	if _notice_owner!=_identity or _identity!=str(AuthGateway.current_player().get("id","")):return
	var data=JSON.parse_string(bytes.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not data is Dictionary or str(data.get("playerId",""))!=_identity:
		if op=="ack":EventBus.toast_requested.emit("Could not mark notices read. Try again.")
		return
	if op=="ack":
		_notice_next=0
		_request_notices()
		return
	_notice_rows=data.get("notices",[]).duplicate(true)
	_notice_unread=int(data.get("unread",0))
	var remaining:=int(data.get("remainingSeconds",0))
	_mute_deadline=Time.get_ticks_msec()+remaining*1000 if remaining>0 else 0
	var new_notice:=false
	for row in _notice_rows:
		if not row.get("acknowledged",false) and not _notice_alerted.has(str(row.id)):
			_notice_alerted[str(row.id)]=true
			new_notice=true
	if new_notice:EventBus.toast_requested.emit("New moderation notice. Open Chat Notices for details.")
	_refresh_notice_bar()
	_update_controls()

func _refresh_notice_bar() -> void:
	var bar: HBoxContainer=_layout.get_node("Moderation")
	bar.visible=not _notice_rows.is_empty() or _mute_deadline>0 or _notice_unread>0
	bar.get_node("Notices").text="Notices (%d)" % _notice_unread if _notice_unread>0 else "Notices"
	var remaining:=maxi(0,ceili(float(_mute_deadline-Time.get_ticks_msec())/60000.0))
	bar.get_node("MuteStatus").text="Chat muted - %d min left" % remaining if remaining>0 else ""

func _open_notices() -> void:
	_notice_shown_ids.clear()
	var content_label: RichTextLabel=_notice_dialog.get_node("History")
	content_label.clear()
	for row in _notice_rows:
		var action:=str(row.get("action","notice"))
		var date:=str(row.get("created_at","")).replace("T"," ").left(19)
		var unread:=not bool(row.get("acknowledged",false))
		content_label.add_text(("%s - %s UTC%s\n" % [action.capitalize(),date," (new)" if unread else ""]))
		content_label.add_text(str(row.get("reason",""))+"\n")
		if action=="mute" and row.get("muted_until")!=null:
			content_label.add_text("Until "+str(row.muted_until).replace("T"," ").left(19)+" UTC\n")
		content_label.add_text("\n")
		if unread:_notice_shown_ids.append(str(row.id))
	if _notice_rows.is_empty():content_label.add_text("No moderation notices.")
	_notice_dialog.get_ok_button().disabled=_notice_shown_ids.is_empty()
	_notice_dialog.popup_centered()

func _ack_notices() -> void:
	if _notice_shown_ids.is_empty():return
	if not _notice_op.is_empty():
		EventBus.toast_requested.emit("Chat is busy. Open notices and try again.")
		return
	_request_notices(_notice_shown_ids.duplicate())

func _submit_report() -> void:
	if _channel!="world" or _identity!=_report_owner or _report_id.is_empty():return
	if not _begin("report","/reports",HTTPClient.METHOD_POST,{"messageId":_report_id}):
		EventBus.toast_requested.emit("Chat is busy. Please try reporting again.")
	_report_id=""
	_report_owner=""

func _reply_clicked(meta: Variant) -> void:
	if str(meta).begins_with("report:"):
		if _channel!="world" or not AuthGateway.is_authenticated():return
		var report_id := str(meta).substr(7)
		var reported := _find_message(report_id)
		if reported.is_empty() or str(reported.get("playerId",""))==_identity or str(reported.get("kind",""))=="mythic_summon":return
		_report_id=report_id
		_report_owner=_identity
		_report_dialog.dialog_text="Report this public message from "+str(reported.get("name","Player"))+" for staff review?"
		_report_dialog.popup_centered()
		return
	if str(meta).begins_with("profile:"):
		_open_chat_profile(str(meta).substr(8))
		return
	if _blocked_mode or not str(meta).begins_with("reply:"):return
	var id := str(meta).substr(6)
	var message := _find_message(id)
	if message.is_empty() or str(message.get("kind",""))=="mythic_summon":return
	_reply_to=id
	_layout.get_node("ReplyBar/Preview").text="Reply to "+_reply_preview(message)
	_layout.get_node("ReplyBar").show()
	_fit_chat_layout()

func _cancel_reply() -> void:
	_reply_to=""
	if _layout!=null:
		_layout.get_node("ReplyBar").hide()
		_fit_chat_layout()

func _track_chat_send() -> void:
	var now := Time.get_ticks_msec()
	while not _recent_sends.is_empty() and now-_recent_sends[0]>=10000:
		_recent_sends.pop_front()
	_recent_sends.append(now)
	_next_send_at=now+1100
	if _recent_sends.size()>=5:
		_next_send_at=maxi(_next_send_at,_recent_sends[0]+10100)

func _contact_preview(entry: Dictionary) -> String:
	var value = entry.get("preview")
	if not value is String or value.is_empty():return ""
	var preview: String=value
	if preview.begins_with("[sticker:") and preview.ends_with("]"):
		var id := preview.substr(9,preview.length()-10)
		if STICKERS.has(id):preview="Sticker: "+str(STICKER_LABELS.get(id,id))
	if str(entry.get("preview_sender",""))==_identity:preview="You: "+preview
	if preview.length()>42:preview=preview.left(42)+"..."
	return preview

func _emote_preferences_path() -> String:
	return "user://chat_emotes_"+_identity.sha256_text()+".cfg"

func _load_emote_preferences() -> void:
	_recent_emojis.clear()
	_favorite_stickers.clear()
	_pin_mode=false
	if not _identity.is_empty() and OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")!="1":
		var config := ConfigFile.new()
		if config.load(_emote_preferences_path())==OK:
			var saved_recent = config.get_value("emotes","recent",[])
			if saved_recent is Array:
				for value in saved_recent:
					if value is String and value.length()==1 and value.unicode_at(0) in EMOJI_CODES and not _recent_emojis.has(value) and _recent_emojis.size()<8:_recent_emojis.append(value)
			var saved_favorites = config.get_value("emotes","favorites",[])
			if saved_favorites is Array:
				for value in saved_favorites:
					if value is String and value in STICKER_PICKER_IDS and not _favorite_stickers.has(value):_favorite_stickers.append(value)
	_apply_emote_order()

func _save_emote_preferences() -> void:
	if _identity.is_empty() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE")=="1":return
	var config := ConfigFile.new()
	config.set_value("emotes","recent",_recent_emojis)
	config.set_value("emotes","favorites",_favorite_stickers)
	config.save(_emote_preferences_path())

func _toggle_emote_picker(open: bool) -> void:
	if open:
		_apply_emote_order()
		if _layout.get_node("EmotePicker/StickerScroll").visible:_refresh_sticker_unlocks()
	else:_set_pin_mode(false)
	_layout.get_node("EmotePicker").visible=open

func _apply_emote_order() -> void:
	var emoji_grid: HBoxContainer=_layout.get_node("EmotePicker/EmojiScroll/EmojiGrid")
	var emoji_order: Array[String]=_recent_emojis.duplicate()
	for code in EMOJI_CODES:
		var emoji:=String.chr(code)
		if not emoji_order.has(emoji):emoji_order.append(emoji)
	for index in range(emoji_order.size()):
		for button in emoji_grid.get_children():
			if button.get_meta("emoji","")==emoji_order[index]:
				emoji_grid.move_child(button,index)
				break
	var sticker_grid: HBoxContainer=_layout.get_node("EmotePicker/StickerScroll/StickerGrid")
	var sticker_order: Array[String]=[]
	for id in _favorite_stickers:
		if _sticker_unlocked(id):sticker_order.append(id)
	for id in STICKER_PICKER_IDS:
		if not sticker_order.has(id) and _sticker_unlocked(id):sticker_order.append(id)
	for id in STICKER_PICKER_IDS:
		if not sticker_order.has(id):sticker_order.append(id)
	for index in range(sticker_order.size()):
		for button in sticker_grid.get_children():
			if button.get_meta("sticker_id","")==sticker_order[index]:
				sticker_grid.move_child(button,index)
				break
	_refresh_pin_buttons()

func _refresh_pin_buttons() -> void:
	for button in _layout.get_node("EmotePicker/StickerScroll/StickerGrid").get_children():
		var id:=str(button.get_meta("sticker_id",""))
		var pinned:=_favorite_stickers.has(id)
		button.text=String.chr(0x2605) if pinned else (String.chr(0x2606) if _pin_mode else "")
		button.tooltip_text=("Pinned | " if pinned else "")+str(STICKER_LABELS.get(id,id))
		button.add_theme_color_override("font_color",UITheme.GOLD)
		button.modulate=Color.WHITE if _sticker_unlocked(id) else Color(0.62,0.62,0.62,1.0)
		if not _sticker_unlocked(id):
			button.text="Locked"
			button.tooltip_text="Obtain "+str(STICKER_LABELS.get(id,id))+" to unlock"

func _set_pin_mode(enabled: bool, refresh_controls: bool = true) -> void:
	_pin_mode=enabled
	_layout.get_node("EmotePicker/Tabs/Favorites").set_pressed_no_signal(enabled)
	_layout.get_node("EmotePicker/Tabs/Favorites").text="Done" if enabled else "Pin stickers"
	if enabled:
		_layout.get_node("EmotePicker/Tabs/Hint").text="Tap a sticker to pin or unpin"
		_refresh_pin_buttons()
	else:
		_layout.get_node("EmotePicker/Tabs/Hint").text="Tap to send | swipe for more" if _layout.get_node("EmotePicker/StickerScroll").visible else "Tap to insert | swipe for more"
		_apply_emote_order()
	if refresh_controls and _request!=null:_update_controls()

func _sticker_pressed(id: String) -> void:
	if not _sticker_unlocked(id):
		_layout.get_node("EmotePicker/Tabs/Hint").text="Obtain "+str(STICKER_LABELS.get(id,id))+" to unlock"
		return
	if _pin_mode:
		if _identity.is_empty() or not id in STICKER_PICKER_IDS:return
		if _favorite_stickers.has(id):_favorite_stickers.erase(id)
		else:_favorite_stickers.append(id)
		_save_emote_preferences()
		_refresh_pin_buttons()
	else:_send_sticker(id)

func _profile_content() -> VBoxContainer:
	return _profile_card.get_node("Center/Panel/Content") as VBoxContainer

func _selected_profile_id() -> String:
	if _channel=="private":return _recipient
	var players: OptionButton=_layout.get_node("PlayerActions/Players")
	return str(players.get_item_metadata(players.selected)) if players.selected>=0 else ""

func _inspect_selected_player() -> void:
	_open_chat_profile(_selected_profile_id())

func _open_chat_profile(id: String) -> void:
	if _blocked_mode or not AuthGateway.is_authenticated() or not _operation.is_empty() or id.is_empty() or id==_identity:return
	var source: Dictionary={}
	for message in _last_messages:
		if message is Dictionary and str(message.get("playerId",""))==id and str(message.get("kind",""))!="mythic_summon":
			source=message
	if source.is_empty() and not (_channel=="private" and id==_recipient and _contacts_loaded):return
	_profile_target=id
	_profile_access=false
	_profile_elapsed=0.0
	_profile_notice=""
	var details:=_profile_content()
	details.get_node("Identity/Portrait").texture=preload("res://scripts/ui/social_portrait.gd").texture(str(source.get("avatar","kael_avatar")))
	details.get_node("Identity/Text/Name").text=str(source.get("name","Friend"))
	details.get_node("Identity/Text/Title").text=str(source.get("title",""))
	details.get_node("Identity/Text/Presence").text=""
	details.get_node("Stats").text=""
	details.get_node("Badges").text=""
	details.get_node("Status").text="Loading profile..."
	details.get_node("Invite").disabled=true
	_profile_card.show()
	if not _begin("inspect_profile","/friend-profile?playerId="+id.uri_encode(),HTTPClient.METHOD_GET):
		details.get_node("Status").text="Profile connection unavailable."

func _close_chat_profile() -> void:
	if _profile_card==null:return
	_profile_target=""
	_profile_access=false
	_profile_notice=""
	_profile_card.hide()
	var details:=_profile_content()
	details.get_node("Identity/Portrait").texture=null
	details.get_node("Identity/Text/Name").text=""
	details.get_node("Identity/Text/Title").text=""
	details.get_node("Identity/Text/Presence").text=""
	details.get_node("Stats").text=""
	details.get_node("Badges").text=""
	details.get_node("Status").text=""
	_elapsed=3.0

func _invite_from_chat() -> void:
	if not _profile_access or _profile_target.is_empty() or not _profile_card.visible:return
	if _begin("invite_player","/friend-invites",HTTPClient.METHOD_POST,{"playerId":_profile_target}):
		_profile_content().get_node("Status").text="Sending party invitation..."

func _complete_profile_action(operation: String,result: int,code: int,data: Variant) -> void:
	if _profile_target.is_empty() or not _profile_card.visible:return
	var details:=_profile_content()
	if result!=HTTPRequest.RESULT_SUCCESS or code<200 or code>=300 or not data is Dictionary:
		if operation=="inspect_profile":
			var had_access:=_profile_access
			_profile_access=false
			if had_access:
				details.get_node("Identity/Portrait").texture=null
				details.get_node("Identity/Text/Name").text="Profile unavailable"
				details.get_node("Identity/Text/Title").text=""
			details.get_node("Identity/Text/Presence").text=""
			details.get_node("Stats").text=""
			details.get_node("Badges").text=""
			details.get_node("Status").text="Full profiles are available for accepted friends only." if code in [403,404] else "Profile unavailable. Close and try again."
		else:
			var reason:=str(data.get("error","")) if data is Dictionary else ""
			_profile_notice={
				"create_or_lead_party_first":"Create or lead a party first.",
				"friendship_required":"Only accepted friends can be invited.",
				"friend_already_in_party":"This friend is already in a party.",
				"lobby_full":"Your party is full."
			}.get(reason,"Invitation unsuccessful. Try again.")
			details.get_node("Status").text=_profile_notice
		return
	if operation=="invite_player":
		_profile_notice="Party invitation sent. Valid for 10 minutes."
		details.get_node("Status").text=_profile_notice
		return
	if str(data.get("id",""))!=_profile_target:return
	_profile_access=true
	details.get_node("Identity/Portrait").texture=preload("res://scripts/ui/social_portrait.gd").texture(str(data.get("avatar","kael_avatar")))
	details.get_node("Identity/Text/Name").text=str(data.get("name","Friend"))
	var title:=str(data.get("title",""))
	details.get_node("Identity/Text/Title").text=title if not title.is_empty() else "No equipped title"
	details.get_node("Identity/Text/Title").add_theme_color_override("font_color",preload("res://scripts/ui/achievement_title_style.gd").color(title))
	details.get_node("Identity/Text/Presence").text="Online" if bool(data.get("online",false)) else "Offline"
	var stats: Dictionary=data.get("stats",{})
	details.get_node("Stats").text="Level %d | %s XP\n%d expedition victories | %d explored landmarks\n%d / %d achievements" % [int(stats.get("level",1)),str(stats.get("xp","0")),int(stats.get("victories",0)),int(stats.get("landmarks",0)),int(data.get("achievementCount",0)),int(data.get("achievementTotal",0))]
	var badges: PackedStringArray=[]
	for badge in data.get("badges",[]):
		if badge is Dictionary:badges.append(str(badge.get("name","")))
	details.get_node("Badges").text="Featured: "+", ".join(badges) if not badges.is_empty() else "No featured badges"
	details.get_node("Status").text=_profile_notice if not _profile_notice.is_empty() else "Friend profile | Read only"

func _sticker_unlocked(id: String) -> bool:
	return not id in CHARACTER_STICKER_IDS or id in _unlocked_stickers

func _refresh_sticker_unlocks() -> void:
	if _sticker_request==null or not _sticker_request_player.is_empty() or not AuthGateway.is_authenticated() or not AuthGateway.access_token_ready_for_connection():return
	if Time.get_ticks_msec()<_sticker_refresh_at:return
	_sticker_refresh_at=Time.get_ticks_msec()+10000
	_sticker_request_player=_identity
	var err:=_sticker_request.request(AuthGateway.api_base_url+"/v1/chat/stickers",PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request()]))
	if err!=OK:_sticker_request_player=""

func _sticker_unlocks_completed(result: int,code: int,_headers: PackedStringArray,bytes: PackedByteArray) -> void:
	var requested:=_sticker_request_player
	_sticker_request_player=""
	var data=JSON.parse_string(bytes.get_string_from_utf8())
	if requested.is_empty() or requested!=_identity or requested!=str(AuthGateway.current_player().get("id","")):return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not data is Dictionary or str(data.get("playerId",""))!=requested:return
	_apply_sticker_unlocks(data.get("unlocked",[]))

func _apply_sticker_unlocks(values: Variant) -> void:
	_unlocked_stickers.clear()
	if values is Array:
		for id in values:
			if id is String and id in CHARACTER_STICKER_IDS and not _unlocked_stickers.has(id):_unlocked_stickers.append(id)
	_apply_emote_order()