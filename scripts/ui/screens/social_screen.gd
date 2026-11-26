extends OverlayScreen
signal private_chat_requested(player_id: String)
const LAYOUT=preload("res://scenes/ui/components/social_layout.tscn")
const PORTRAIT=preload("res://scripts/ui/social_portrait.gd")
const PORTRAIT_TILE=preload("res://scenes/ui/components/portrait_gallery_tile.tscn")
var _layout: VBoxContainer
var _request: HTTPRequest
var _operation := ""
var _identity := ""
var _found := ""
var _found_name := ""
var _searched_name := ""
var _saved_avatar := ""
var _retry_at := 0
var _elapsed := 5.0
var _friends: Array = []
var _party_invites: Array = []
var _profile_loaded := false
var _queued_refresh := false
var _queued_friend_action: Dictionary = {}
var _mobile_profile_open := false
var _mobile_profile_button: Button
var _queued_picture := ""
var _unlocked_portraits: Array = []
var _roster_refresh := false
var _equipped_title := ""
var _titles_loaded := false
var _title_catalog:Dictionary={}
var _saved_pins:Array=[]
var _draft_pins:Array=[]
var _profile_stats:Dictionary={}
var _inspected_id:=""
var _ranking_open:=false
var _results_open:=false
var _challenges_open:=false
var _challenge_season:=""
var _challenge_deadline:=0
var _hall_open:=false
var _hall_season:=""
var _hall_category:="combat"
var _hall_page:=0
var _hall_more:=false
var _season_results_data:Dictionary={}
var _ranking_category:="achievements"
var _ranking_scope:="friends"
var _ranking_period:="lifetime"
var _season_key:=""
var _season_deadline:=0
var _ranking_enabled:=false
const RANKING_CATEGORIES=["achievements","exploration","combat"]
func _init():
	screen_title="Friends & Profile"
	screen_subtitle="Connect with other players"
func _build_content():
	var guild_button:=UIFactory.button("Guilds")
	header_actions.add_child(guild_button)
	guild_button.pressed.connect(_open_guilds)
	_layout=LAYOUT.instantiate()
	content.add_child(_layout)
	if TouchInput.using_touch:
		_mobile_profile_button=UIFactory.button("Profile")
		header_actions.add_child(_mobile_profile_button)
		_mobile_profile_button.pressed.connect(_toggle_mobile_profile)
		_layout.get_node("Scroll").custom_minimum_size.y=140
	_layout.get_node("Profile/Browse").pressed.connect(_toggle_gallery)
	_layout.get_node("PortraitGallery/Toolbar/Done").pressed.connect(func(): _set_gallery_visible(false))
	_layout.get_node("PortraitGallery/Toolbar/Search").text_changed.connect(func(_value): _render_gallery())
	_layout.get_node("PortraitGallery/Scroll").resized.connect(_resize_gallery)
	_request=HTTPRequest.new()
	_request.timeout=10.0
	add_child(_request)
	_request.request_completed.connect(_completed)
	_layout.get_node("Search/Find").pressed.connect(_search)
	_layout.get_node("Search/Name").text_submitted.connect(func(_s):_search())
	_layout.get_node("Search/Name").text_changed.connect(func(_s):_clear_result(); _update_controls())
	_layout.get_node("Result/Add").pressed.connect(func():_friend_action(_found,"accept" if _found_relationship()=="Incoming request" else "request"))
	_layout.get_node("Profile/Save").pressed.connect(_save_picture)
	_layout.get_node("Titles/Equip").pressed.connect(_equip_title)
	_layout.get_node("FriendProfile/Toolbar/Back").pressed.connect(_close_friend_profile)
	_layout.get_node("Rankings").pressed.connect(_open_rankings)
	_layout.get_node("Leaderboard/Toolbar/Back").pressed.connect(_close_rankings)
	_layout.get_node("Leaderboard/Toolbar/Results").pressed.connect(_open_season_results)
	_layout.get_node("Leaderboard/Challenges").pressed.connect(_open_challenges)
	_layout.get_node("SeasonChallenges/Toolbar/Back").pressed.connect(_close_challenges)
	_layout.get_node("SeasonChallenges/Toolbar/ClaimAll").pressed.connect(_claim_all_challenges)
	_layout.get_node("Leaderboard/Toolbar/Hall").pressed.connect(_open_hall)
	_layout.get_node("ChampionshipHall/Toolbar/Back").pressed.connect(_close_hall)
	var hall_categories:OptionButton=_layout.get_node("ChampionshipHall/Filters/Category")
	for value in ["Combat","Exploration","Achievements"]:hall_categories.add_item(value)
	hall_categories.select(0)
	hall_categories.item_selected.connect(func(index:int):
		_hall_category=["combat","exploration","achievements"][index]
		_hall_page=0
		_request_hall())
	_layout.get_node("ChampionshipHall/Filters/Season").item_selected.connect(func(index:int):
		_hall_season=str(_layout.get_node("ChampionshipHall/Filters/Season").get_item_metadata(index))
		_hall_page=0
		_request_hall())
	_layout.get_node("ChampionshipHall/Pages/Previous").pressed.connect(func():
		if _hall_page>0:_hall_page-=1;_request_hall())
	_layout.get_node("ChampionshipHall/Pages/Next").pressed.connect(func():
		if _hall_more:_hall_page+=1;_request_hall())

	_layout.get_node("SeasonResults/Toolbar/Back").pressed.connect(_close_season_results)
	_layout.get_node("SeasonResults/History").toggled.connect(func(_enabled:bool):
		if _results_open and not _season_results_data.is_empty():_render_season_results(_season_results_data))


	_layout.get_node("Leaderboard/Controls/Refresh").pressed.connect(_request_rankings)
	var scopes:OptionButton=_layout.get_node("Leaderboard/Controls/Scope")
	scopes.add_item("Friends")
	scopes.add_item("Global")
	scopes.select(0)
	scopes.item_selected.connect(func(index:int):
		_ranking_scope="global" if index==1 else "friends"
		_request_rankings())
	_layout.get_node("Leaderboard/Visibility").toggled.connect(_save_ranking_visibility)
	var periods:OptionButton=_layout.get_node("Leaderboard/Controls/Period")
	periods.add_item("Lifetime")
	periods.add_item("Monthly")
	periods.select(0)
	periods.item_selected.connect(func(index:int):
		_ranking_period="monthly" if index==1 else "lifetime"
		_request_rankings())


	var categories:OptionButton=_layout.get_node("Leaderboard/Controls/Category")
	for label in ["Achievements earned","Exploration objectives","Expedition victories"]:categories.add_item(label)
	categories.select(0)
	categories.item_selected.connect(func(index:int):
		_ranking_category=RANKING_CATEGORIES[index]
		_request_rankings())

	_layout.get_node("AchievementShowcase/Open").pressed.connect(func():_set_badge_gallery(true))
	_layout.get_node("BadgeGallery/Toolbar/Done").pressed.connect(func():_set_badge_gallery(false))
	_layout.get_node("BadgeGallery/Toolbar/Save").pressed.connect(_save_badges)

	_layout.get_node("Titles/Options").item_selected.connect(func(_index):_update_controls();_refresh_title_preview())
	_layout.get_node("Profile/Pictures").item_selected.connect(func(index):
		var options: OptionButton = _layout.get_node("Profile/Pictures")
		_layout.get_node("Profile/Portrait").texture=PORTRAIT.texture(str(options.get_item_metadata(index)))
		_update_controls())
	_layout.get_node("Stats").text="Online profile loading..."
	AuthGateway.authentication_changed.connect(_auth_changed)
	EventBus.roster_changed.connect(_on_roster_changed)
	if AuthGateway.is_authenticated(): GameState.lifecycle_component.save_now()
	_identity=str(AuthGateway.current_player().get("id",""))
	var options: OptionButton=_layout.get_node("Profile/Pictures")
	options.add_theme_constant_override("icon_max_width",32)
	options.get_popup().add_theme_constant_override("icon_max_width",32)
	_render_friends()
	_update_controls()
func _auth_changed(authenticated: bool, player: Dictionary):
	var id:=str(player.get("id","")) if authenticated else ""
	if id==_identity:return
	_identity=id
	_request.cancel_request()
	_operation=""
	_profile_loaded=false
	_saved_avatar=""
	_equipped_title=""
	_titles_loaded=false
	_title_catalog.clear()
	_saved_pins.clear()
	_draft_pins.clear()
	_profile_stats.clear()
	_close_friend_profile()
	_close_rankings()
	_set_badge_gallery(false)
	_layout.get_node("Stats").text="Online profile loading..."
	_layout.get_node("AchievementShowcase/Progress").value=0
	_layout.get_node("AchievementShowcase/Preview").text="Select an earned title"
	_layout.get_node("Titles/Options").clear()
	_layout.get_node("Titles/Showcase").text="Achievement titles"
	_retry_at=0
	_queued_refresh=false
	_queued_friend_action.clear()
	_queued_picture=""
	_unlocked_portraits.clear()
	_roster_refresh=false
	_elapsed=5.0
	_clear_result()
	_layout.get_node("Search/Name").text=""
	_friends.clear()
	_party_invites.clear()
	_layout.get_node("Profile/Portrait").texture=null
	_layout.get_node("Profile/Name").text="Profile"
	_layout.get_node("Profile/Pictures").clear()
	_set_gallery_visible(false)
	_layout.get_node("Result/Name").text="Search for a friend"
	_render_friends()
	_update_controls()
func _toggle_mobile_profile() -> void:
	if _ranking_open or not _inspected_id.is_empty():return
	_mobile_profile_open=not _mobile_profile_open
	_apply_mobile_friends_layout()

func _apply_mobile_friends_layout() -> void:
	if not is_instance_valid(_mobile_profile_button):return
	var ordinary:bool=not _ranking_open and _inspected_id.is_empty() and not _layout.get_node("PortraitGallery").visible and not _layout.get_node("BadgeGallery").visible
	_mobile_profile_button.visible=ordinary
	if not ordinary:return
	_mobile_profile_button.text="Friends" if _mobile_profile_open else "Profile"
	for item in ["ProfileHeading","Profile","Stats","Titles","AchievementShowcase","Divider"]:
		_layout.get_node(item).visible=_mobile_profile_open
	for item in ["SearchHeading","Search","Result","Heading","Scroll","Rankings"]:
		_layout.get_node(item).visible=not _mobile_profile_open

func _process(delta):
	if _layout==null:return
	_apply_mobile_friends_layout()
	if not AuthGateway.is_authenticated():
		_layout.get_node("Status").text="Sign in to use friends and profile pictures."
		return
	_elapsed+=delta
	var ready_count:=AuthGateway.online_season_claimable+AuthGateway.online_season_challenge_claimable
	_layout.get_node("Rankings").text="Leaderboards (%d rewards)" % ready_count if ready_count>0 else "Leaderboards"
	_layout.get_node("Leaderboard/Toolbar/Results").text="Season rewards (%d)" % AuthGateway.online_season_claimable if AuthGateway.online_season_claimable>0 else "Season rewards"
	_layout.get_node("Leaderboard/Challenges").text="Season challenges (%d)" % AuthGateway.online_season_challenge_claimable if AuthGateway.online_season_challenge_claimable>0 else "Season challenges"
	if _challenges_open:_update_challenge_countdown()
	if _ranking_open and _ranking_period=="monthly":_update_season_countdown()
	if _operation.is_empty():
		if not _queued_friend_action.is_empty():
			if AuthGateway.access_token_ready_for_connection():
				var pending:=_queued_friend_action.duplicate()
				_queued_friend_action.clear()
				if not _begin("action","/friends",pending):
					_queued_friend_action=pending
			return
		if _ranking_open:
			if _challenges_open:
				if _elapsed>=15.0 or (_challenge_deadline>0 and Time.get_ticks_msec()>=_challenge_deadline):_request_challenges()
				return
			if _results_open:return
			if _hall_open:
				if _elapsed>=15.0:_request_hall()
				return
			if _elapsed>=15.0 or (_season_deadline>0 and Time.get_ticks_msec()>=_season_deadline):_request_rankings()
			return
		if not _inspected_id.is_empty():
			if _elapsed>=5.0:
				_elapsed=0.0
				_begin("inspect","/friend-profile?playerId="+_inspected_id.uri_encode())
			return
		if not _profile_loaded and Time.get_ticks_msec()>=_retry_at:_begin("profile","/profile")
		elif _roster_refresh and _profile_loaded and not _layout.get_node("BadgeGallery").visible:
			if _begin("profile","/profile"):_roster_refresh=false
		elif not _queued_picture.is_empty():
			if _begin("picture","/profile",{"avatar":_queued_picture}):_queued_picture=""
		elif _profile_loaded and not _layout.get_node("PortraitGallery").visible and not _layout.get_node("BadgeGallery").visible and (_queued_refresh or _elapsed>=5.0):
			_elapsed=0.0
			_queued_refresh=false
			_begin("friends","/friends")
func _begin(op: String,path: String,data: Dictionary={})->bool:
	if not _operation.is_empty() or not AuthGateway.access_token_ready_for_connection():return false
	_operation=op
	var err:=_request.request(AuthGateway.api_base_url+("/v1/co-op" if op.begins_with("party_") else "/v1/social")+path,PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"]),HTTPClient.METHOD_GET if data.is_empty() else HTTPClient.METHOD_POST,"" if data.is_empty() else JSON.stringify(data))
	if err!=OK:
		_operation=""
		_retry_at=Time.get_ticks_msec()+3000
		_layout.get_node("Status").text="Connection unavailable."
	_update_controls()
	return err==OK
func _clear_result():
	_found=""
	_found_name=""
	_layout.get_node("Result/Name").text="Search for a friend"
	_layout.get_node("Result/Portrait").visible=false

func _search():
	if not _operation.is_empty():return
	var value:=str(_layout.get_node("Search/Name").text).strip_edges()
	_clear_result()
	if value.length()<3:
		_layout.get_node("Status").text="Enter at least 3 characters of the exact player name."
		_update_controls()
		return
	_searched_name=value
	_begin("search","/search?name="+value.uri_encode())

func _found_relationship()->String:
	for friend in _friends:
		if str(friend.id)==_found:
			return "Already friends" if friend.status=="accepted" else ("Incoming request" if friend.direction=="incoming" else "Request sent")
	return ""
func _friend_action(id: String,action: String):
	if id.is_empty() or not AuthGateway.is_authenticated() or not _queued_friend_action.is_empty() or _operation=="action":return
	var payload:Dictionary={"playerId":id,"action":action}
	if not _begin("action","/friends",payload):
		_queued_friend_action=payload
		_layout.get_node("Status").text="Sending friend action after connection refresh..."
		_update_controls()
func _save_picture():
	var options: OptionButton=_layout.get_node("Profile/Pictures")
	if options.selected<0:return
	var avatar:=str(options.get_item_metadata(options.selected))
	if avatar==_saved_avatar or not _unlocked_portraits.has(avatar):return
	if not _begin("picture","/profile",{"avatar":avatar}):
		_queued_picture=avatar
		_layout.get_node("Status").text="Saving profile picture..."
		_update_controls()
func _equip_title() -> void:
	var options:OptionButton=_layout.get_node("Titles/Options")
	if options.selected<0 or options.is_item_disabled(options.selected):return
	var id:=str(options.get_item_metadata(options.selected))
	if id==_equipped_title:return
	_begin("title","/title",{"titleId":id})

func _render_titles(data:Dictionary) -> void:
	_titles_loaded=data.get("titles") is Array
	_saved_pins=data.get("pins",[]).duplicate()
	_draft_pins=_saved_pins.duplicate()
	_title_catalog.clear()
	_equipped_title=str(data.get("equippedTitle",""))
	var options:OptionButton=_layout.get_node("Titles/Options")
	options.clear()
	options.add_item("No title")
	options.set_item_metadata(0,"")
	options.select(0)
	for title in data.get("titles",[])+data.get("seasonTitles",[]):
		_title_catalog[str(title.id)]=title
		options.add_item(str(title.name) if title.unlocked else str(title.name)+" (Locked)")
		var index:=options.item_count-1
		options.set_item_metadata(index,str(title.id))
		options.set_item_disabled(index,not bool(title.unlocked))
		options.get_popup().set_item_tooltip(index,preload("res://scripts/ui/achievement_title_style.gd").tier(str(title.name))+" | "+str(title.category)+" | "+str(title.achievement))
		if str(title.id)==_equipped_title:options.select(index)
	var equipped:=str(data.get("title",""))
	_layout.get_node("Titles/Showcase").text=("%s  |  " % equipped if not equipped.is_empty() else "")+"%d / %d achievement titles unlocked" % [int(data.get("achievementCount",0)),data.get("titles",[]).size()]

	var pinned_names:=PackedStringArray()
	for id in _saved_pins:
		if _title_catalog.has(id):pinned_names.append(str(_title_catalog[id].name))
	if not pinned_names.is_empty():
		_layout.get_node("Titles/Showcase").text+="\nPinned: "+", ".join(pinned_names)
	var progress:ProgressBar=_layout.get_node("AchievementShowcase/Progress")
	progress.max_value=maxi(1,data.get("titles",[]).size())
	progress.value=int(data.get("achievementCount",0))
	_layout.get_node("Titles/Showcase").add_theme_color_override("font_color",preload("res://scripts/ui/achievement_title_style.gd").color(equipped))
	_refresh_title_preview()
	if _layout.get_node("BadgeGallery").visible:_render_badges()

func _set_badge_gallery(value:bool) -> void:
	if value and not _titles_loaded:return
	if value:_set_gallery_visible(false)
	_layout.get_node("BadgeGallery").visible=value
	for name in ["Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll"]:
		_layout.get_node(name).visible=not value
	if value:
		_draft_pins=_saved_pins.duplicate()
		_render_badges()
	else:
		_draft_pins=_saved_pins.duplicate()
	_update_controls()

func _render_badges() -> void:
	var rows=_layout.get_node("BadgeGallery/Scroll/Rows")
	UIFactory.clear(rows)
	var style=preload("res://scripts/ui/achievement_title_style.gd")
	for id in _title_catalog:
		var title:Dictionary=_title_catalog[id]
		if str(title.category)=="Seasonal":continue
		var row=preload("res://scenes/ui/components/achievement_badge_row.tscn").instantiate()
		rows.add_child(row)
		var earned:bool=title.unlocked
		var accent:Color=style.color(str(title.name)) if earned else UITheme.TEXT_DIM
		row.add_theme_stylebox_override("panel",UITheme.style(Color("#21182c"),accent,6,1,8))
		row.get_node("Row/Badge").add_theme_color_override("font_color",accent)
		row.get_node("Row/Info").text="%s | %s\n%s ? %s" % [title.name,style.tier(str(title.name)),title.achievement,"Earned" if earned else "Locked"]
		var pin:CheckButton=row.get_node("Row/Pin")
		pin.set_pressed_no_signal(_draft_pins.has(id))
		pin.disabled=not earned or (_draft_pins.size()>=3 and not _draft_pins.has(id)) or not _operation.is_empty()
		pin.toggled.connect(_toggle_badge.bind(str(id)))
	_layout.get_node("BadgeGallery/Hint").text="%d / 3 pinned  |  %d / %d earned" % [_draft_pins.size(),int(_layout.get_node("AchievementShowcase/Progress").value),int(_layout.get_node("AchievementShowcase/Progress").max_value)]
	_layout.get_node("BadgeGallery/Stats").text="Online level %d | %s XP | %d expedition victories | %d landmarks" % [int(_profile_stats.get("level",1)),str(_profile_stats.get("xp","0")),int(_profile_stats.get("victories",0)),int(_profile_stats.get("landmarks",0))]
	_update_controls()

func _toggle_badge(pressed:bool,id:String) -> void:
	if not _operation.is_empty() or not bool(_title_catalog.get(id,{}).get("unlocked",false)):return
	if pressed and _draft_pins.size()<3 and not _draft_pins.has(id):_draft_pins.append(id)
	elif not pressed:_draft_pins.erase(id)
	_render_badges()

func _save_badges() -> void:
	if _draft_pins!=_saved_pins:_begin("showcase","/showcase",{"pins":_draft_pins})

func _refresh_title_preview() -> void:
	var options:OptionButton=_layout.get_node("Titles/Options")
	var preview:Label=_layout.get_node("AchievementShowcase/Preview")
	var selected:=str(options.get_item_metadata(options.selected)) if options.selected>=0 else ""
	var title:Dictionary=_title_catalog.get(selected,{})
	var style=preload("res://scripts/ui/achievement_title_style.gd")
	var name_text:=str(title.get("name",""))
	preview.text="No title equipped" if title.is_empty() else "%s | %s" % [style.tier(name_text),name_text]
	preview.add_theme_color_override("font_color",style.color(name_text))


func _update_controls():
	var ready: bool = AuthGateway.is_authenticated() and _operation.is_empty()
	_layout.get_node("AchievementShowcase/Open").disabled=not ready or not _titles_loaded
	_layout.get_node("Rankings").disabled=not ready
	_layout.get_node("SeasonResults/History").disabled=not ready
	_layout.get_node("Leaderboard/Toolbar/Results").disabled=not ready
	_layout.get_node("Leaderboard/Challenges").disabled=not ready
	_layout.get_node("SeasonChallenges/Toolbar/ClaimAll").disabled=not ready or AuthGateway.online_season_challenge_claimable<=0 or _challenge_deadline<=Time.get_ticks_msec()
	_layout.get_node("Leaderboard/Toolbar/Hall").disabled=not ready
	_layout.get_node("ChampionshipHall/Filters/Category").disabled=not ready
	_layout.get_node("ChampionshipHall/Filters/Season").disabled=not ready or _layout.get_node("ChampionshipHall/Filters/Season").item_count==0
	_layout.get_node("ChampionshipHall/Pages/Previous").disabled=not ready or _hall_page<=0
	_layout.get_node("ChampionshipHall/Pages/Next").disabled=not ready or not _hall_more

	_layout.get_node("Leaderboard/Controls/Category").disabled=not ready
	_layout.get_node("Leaderboard/Controls/Refresh").disabled=not ready
	_layout.get_node("Leaderboard/Controls/Scope").disabled=not ready
	_layout.get_node("Leaderboard/Controls/Period").disabled=not ready
	_layout.get_node("Leaderboard/Visibility").disabled=not ready


	_layout.get_node("BadgeGallery/Toolbar/Save").disabled=not ready or _draft_pins==_saved_pins
	var titles:OptionButton=_layout.get_node("Titles/Options")
	titles.disabled=not ready or not _titles_loaded
	_layout.get_node("Titles/Equip").disabled=titles.disabled or titles.selected<0 or titles.is_item_disabled(titles.selected) or str(titles.get_item_metadata(titles.selected))==_equipped_title
	_layout.get_node("Search/Find").disabled=not ready
	var options: OptionButton=_layout.get_node("Profile/Pictures")
	var portrait_ready: bool = AuthGateway.is_authenticated() and _profile_loaded and _operation!="picture" and _queued_picture.is_empty()
	options.disabled=not portrait_ready
	_layout.get_node("Profile/Browse").disabled=not portrait_ready
	var changed: bool = options.selected>=0 and _unlocked_portraits.has(str(options.get_item_metadata(options.selected))) and str(options.get_item_metadata(options.selected))!=_saved_avatar
	_layout.get_node("Profile/Save").disabled=not portrait_ready or not changed
	_layout.get_node("Profile/Save").text="Saving..." if _operation=="picture" or not _queued_picture.is_empty() else "Save picture"
	var relationship:=_found_relationship()
	var friend_ready:bool=AuthGateway.is_authenticated() and (_operation.is_empty() or _operation=="friends") and _queued_friend_action.is_empty()
	_layout.get_node("Result/Add").text="Accept request" if relationship=="Incoming request" else ("Send request" if relationship.is_empty() else relationship)
	_layout.get_node("Result/Add").disabled=not friend_ready or _found.is_empty() or (not relationship.is_empty() and relationship!="Incoming request")
	for node in _layout.get_node("Scroll/Rows").get_children():
		for child in node.get_children():
			if child is Button:
				child.disabled=not friend_ready if child.has_meta("friend_action") else not ready
func _completed(result: int,code: int,_headers: PackedStringArray,bytes: PackedByteArray):
	var operation:=_operation
	_operation=""
	if _identity!=str(AuthGateway.current_player().get("id","")):return
	var data=JSON.parse_string(bytes.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code<200 or code>=300 or not data is Dictionary:
		if operation in ["season_challenges","challenge_claim"]:
			_layout.get_node("SeasonChallenges/Timing").text="Unable to load or claim. Refreshing..."
			_challenge_deadline=0
			_elapsed=12.0
		if operation=="championship_hall":
			_layout.get_node("ChampionshipHall/Summary").text="Unable to load the hall. Return and try again."
		if operation in ["season_results","season_claim"]:
			_layout.get_node("SeasonResults/Rules").text="Unable to load or claim. Return to rankings and reopen Season rewards to retry."
		if operation=="ranking_visibility":
			_layout.get_node("Leaderboard/Visibility").set_pressed_no_signal(_ranking_enabled)
		if operation=="rankings":
			UIFactory.clear(_layout.get_node("Leaderboard/Scroll/Rows"))
			_layout.get_node("Leaderboard/Summary").text="Rankings unavailable. Refresh to retry."
		if operation=="inspect":
			_clear_inspected_details()
			if code in [401,403,404]:_close_friend_profile()
		_retry_at=Time.get_ticks_msec()+3000
		_queued_refresh=operation=="action"
		_layout.get_node("Status").text="Request unsuccessful: "+(str(data.get("error","Try again.")).replace("_"," ") if data is Dictionary else "Try again.")
		_update_controls()
		return
	match operation:
		"season_challenges","challenge_claim":
			if operation=="challenge_claim":
				AuthGateway.refresh_online_wallet()
				AuthGateway.refresh_social_summary()
			_render_challenges(data)
		"championship_hall":
			_render_hall(data)
		"season_results","season_claim":
			if operation=="season_claim":
				AuthGateway.refresh_online_wallet()
				AuthGateway.online_season_claimable=data.get("results",[]).filter(func(r):return bool(r.get("canClaim",false))).size()
				AuthGateway.refresh_social_summary()
				_roster_refresh=true
			_render_season_results(data)
		"ranking_visibility":
			_ranking_enabled=bool(data.get("enabled",false))
			if _ranking_open:_request_rankings()
		"rankings":
			_render_rankings(data)
		"inspect":
			_render_friend_profile(data)
		"profile","picture":
			_profile_loaded=true
			_saved_avatar=str(data.avatar)
			_profile_stats=data.get("stats",{})
			_layout.get_node("Stats").text="Online level %d | %s XP" % [int(_profile_stats.get("level",1)),str(_profile_stats.get("xp","0"))]
			_render_titles(data)
			_unlocked_portraits=data.get("unlocked", [])
			AuthGateway.update_profile_picture(str(data.id), str(data.avatar))
			_layout.get_node("Profile/Name").text=str(data.name)
			_layout.get_node("Profile/Portrait").texture=PORTRAIT.texture(str(data.avatar))
			var options: OptionButton=_layout.get_node("Profile/Pictures")
			options.clear()
			for id in data.choices:
				var tex=PORTRAIT.texture(str(id))
				if tex==null:continue
				options.add_icon_item(tex,str(id).replace("_avatar","").replace("ravienna","queen_ravienna").capitalize())
				options.set_item_metadata(options.item_count-1,id)
				options.set_item_disabled(options.item_count-1, not _unlocked_portraits.has(str(id)))
				options.get_popup().set_item_icon_max_width(options.item_count-1,40)
				if id==data.avatar:options.select(options.item_count-1)
			_layout.get_node("Status").text="Profile picture saved." if operation=="picture" else "Connected"
			_queued_refresh=true
			if _layout.get_node("PortraitGallery").visible:_render_gallery()
		"showcase":
			_render_titles(data)
			_layout.get_node("Status").text="Achievement showcase saved."
		"title":
			_render_titles(data)
			_layout.get_node("Status").text="Player title saved."
			_queued_refresh=true
		"friends":
			var invites: Array=data.get("invites",[])
			if _friends!=data.friends or _party_invites!=invites:
				_friends=data.friends
				_party_invites=invites
				_render_friends()
		"party_send":
			_layout.get_node("Status").text="Party invitation sent (valid for 10 minutes)."
		"party_response":
			_layout.get_node("Status").text="Joined party. Open Online Co-op to enter the expedition." if data.get("status")=="accepted" else "Party invitation declined."
			_queued_refresh=true
		"search":
			if str(_layout.get_node("Search/Name").text).strip_edges()!=_searched_name:
				_clear_result()
				_update_controls()
				return
			if data.players.is_empty():
				_found=""
				_layout.get_node("Result/Name").text="Player not found."
			else:
				_found=str(data.players[0].id)
				_found_name=str(data.players[0].name)
				var title:=str(data.players[0].get("title",""))
				_layout.get_node("Result/Name").text=_found_name+("\n"+title if not title.is_empty() else "")
				_layout.get_node("Result/Portrait").texture=PORTRAIT.texture(str(data.players[0].avatar))
				_layout.get_node("Result/Portrait").visible=true
				_layout.get_node("Status").text="Player found."
		"action":
			_clear_result()
			_layout.get_node("Status").text="Friend list updated."
			AuthGateway.refresh_social_summary()
			_queued_refresh=true
	_update_controls()
func _open_rankings() -> void:
	if not _operation.is_empty() or not AuthGateway.is_authenticated():return
	_ranking_open=true
	_layout.get_node("Leaderboard").visible=true
	for name in ["ProfileHeading","Profile","Stats","Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll","BadgeGallery","PortraitGallery","FriendProfile"]:
		_layout.get_node(name).visible=false
	_request_rankings()

func _close_rankings() -> void:
	_ranking_open=false
	_challenges_open=false
	_challenge_season=""
	_challenge_deadline=0
	_layout.get_node("SeasonChallenges").hide()
	UIFactory.clear(_layout.get_node("SeasonChallenges/Scroll/Rows"))
	_hall_open=false
	_hall_season=""
	_hall_more=false
	_hall_page=0
	_layout.get_node("ChampionshipHall").hide()
	_layout.get_node("ChampionshipHall/Filters/Season").clear()
	UIFactory.clear(_layout.get_node("ChampionshipHall/Scroll/Rows"))
	_results_open=false
	_season_results_data.clear()
	_layout.get_node("SeasonResults").visible=false
	UIFactory.clear(_layout.get_node("SeasonResults/Scroll/Rows"))
	_season_deadline=0
	_season_key=""
	_ranking_enabled=false
	_layout.get_node("Leaderboard/Visibility").set_pressed_no_signal(false)
	_layout.get_node("Leaderboard").visible=false
	UIFactory.clear(_layout.get_node("Leaderboard/Scroll/Rows"))
	for name in ["ProfileHeading","Profile","Stats","Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll"]:
		_layout.get_node(name).visible=true
	_queued_refresh=true
	_update_controls()

func _open_challenges() -> void:
	if not _ranking_open or not _operation.is_empty():return
	_challenges_open=true
	_layout.get_node("Leaderboard").hide()
	_layout.get_node("SeasonChallenges").show()
	_request_challenges()

func _close_challenges() -> void:
	_challenges_open=false
	_challenge_season=""
	_challenge_deadline=0
	_layout.get_node("SeasonChallenges").hide()
	UIFactory.clear(_layout.get_node("SeasonChallenges/Scroll/Rows"))
	_layout.get_node("Leaderboard").show()
	if _operation.is_empty():_request_rankings()

func _request_challenges() -> void:
	if not _challenges_open or not _operation.is_empty():return
	_elapsed=0.0
	_challenge_deadline=0
	_layout.get_node("SeasonChallenges/Timing").text="Loading verified milestones..."
	UIFactory.clear(_layout.get_node("SeasonChallenges/Scroll/Rows"))
	_begin("season_challenges","/season-challenges")

func _render_challenges(data:Dictionary) -> void:
	if not _challenges_open or str(data.get("playerId",""))!=_identity:return
	_challenge_season=str(data.get("season",""))
	_challenge_deadline=Time.get_ticks_msec()+maxi(0,int(data.get("resetAt",0))-int(data.get("serverTime",0)))
	_update_challenge_countdown()
	var rows=_layout.get_node("SeasonChallenges/Scroll/Rows")
	UIFactory.clear(rows)
	var ready_count:=0
	for task in data.get("rows",[]):
		var row=preload("res://scenes/ui/components/daily_quest_row.tscn").instantiate()
		rows.add_child(row)
		row.get_node("Row/Info/Title").text=str(task.title)
		row.get_node("Row/Info/Description").text=str(task.description)
		row.get_node("Row/Info/Progress").max_value=int(task.target)
		row.get_node("Row/Info/Progress").value=int(task.progress)
		row.get_node("Row/Info/ProgressText").text="%d / %d" % [int(task.progress),int(task.target)]
		row.get_node("Row/Reward/Amount").text="%d Gold" % int(task.gold)
		var claim:Button=row.get_node("Row/Reward/Claim")
		claim.disabled=not bool(task.canClaim)
		claim.text="Claimed" if task.claimed else "Claim"
		if task.canClaim:ready_count+=1
		claim.pressed.connect(_claim_challenge.bind(str(task.id)))
	AuthGateway.online_season_challenge_claimable=ready_count
	_layout.get_node("SeasonChallenges/Toolbar/ClaimAll").disabled=ready_count==0 or _challenge_deadline<=Time.get_ticks_msec()
	_layout.get_node("Status").text="Personal monthly progress | Rank and privacy settings do not affect eligibility"

func _claim_all_challenges() -> void:
	if not _challenges_open or _challenge_deadline<=Time.get_ticks_msec():return
	if _begin("challenge_claim","/season-challenges/claim-all",{"season":_challenge_season}):
		for row in _layout.get_node("SeasonChallenges/Scroll/Rows").get_children():
			row.get_node("Row/Reward/Claim").disabled=true

func _claim_challenge(id:String) -> void:
	if not _challenges_open or _challenge_deadline<=Time.get_ticks_msec():return
	if _begin("challenge_claim","/season-challenges/claim",{"season":_challenge_season,"id":id}):
		for row in _layout.get_node("SeasonChallenges/Scroll/Rows").get_children():
			row.get_node("Row/Reward/Claim").disabled=true

func _update_challenge_countdown() -> void:
	if _challenge_deadline<=0:return
	var seconds:=maxi(0,ceili(float(_challenge_deadline-Time.get_ticks_msec())/1000.0))
	_layout.get_node("SeasonChallenges/Timing").text="%s (UTC) | Claim within %dd %02dh %02dm" % [_challenge_season.left(7),floori(float(seconds)/86400.0),floori(float(seconds%86400)/3600.0),floori(float(seconds%3600)/60.0)]

func _open_hall() -> void:
	if not _ranking_open or not _operation.is_empty():return
	_hall_open=true
	_hall_season=""
	_hall_page=0
	_hall_more=false
	_layout.get_node("Leaderboard").hide()
	_layout.get_node("ChampionshipHall").show()
	_request_hall()

func _close_hall() -> void:
	_hall_open=false
	_layout.get_node("ChampionshipHall").hide()
	UIFactory.clear(_layout.get_node("ChampionshipHall/Scroll/Rows"))
	_layout.get_node("Leaderboard").show()
	if _operation.is_empty():_request_rankings()

func _request_hall() -> void:
	if not _hall_open or not _operation.is_empty():return
	_elapsed=0.0
	UIFactory.clear(_layout.get_node("ChampionshipHall/Scroll/Rows"))
	_layout.get_node("ChampionshipHall/Summary").text="Loading frozen champions..."
	_begin("championship_hall","/championship-hall?category="+_hall_category+"&page="+str(_hall_page)+("&season="+_hall_season if not _hall_season.is_empty() else ""))

func _render_hall(data:Dictionary) -> void:
	if not _hall_open or str(data.get("playerId",""))!=_identity or str(data.get("category",""))!=_hall_category or int(data.get("page",-1))!=_hall_page:return
	_hall_season=str(data.get("season","")) if data.get("season")!=null else ""
	_hall_more=bool(data.get("hasMore",false))
	var seasons:OptionButton=_layout.get_node("ChampionshipHall/Filters/Season")
	seasons.clear()
	for value in data.get("seasons",[]):
		seasons.add_item(str(value).left(7))
		seasons.set_item_metadata(seasons.item_count-1,value)
		if value==_hall_season:seasons.select(seasons.item_count-1)
	var rows=_layout.get_node("ChampionshipHall/Scroll/Rows")
	UIFactory.clear(rows)
	var entries:Array=data.get("rows",[])
	for entry in entries:
		var row=preload("res://scenes/ui/components/leaderboard_row.tscn").instantiate()
		rows.add_child(row)
		row.add_theme_stylebox_override("panel",UITheme.style(Color("#21182c"),UITheme.GOLD,6,1,8))
		row.get_node("Row/Rank").text="#1"
		row.get_node("Row/Portrait").texture=PORTRAIT.texture(str(entry.avatar))
		row.get_node("Row/Name").text=str(entry.name)+(" (You)" if entry.self else "")+"\n"+str(entry.title)
		row.get_node("Row/Score").text=str(int(entry.score))
	_layout.get_node("ChampionshipHall/Summary").text="No finalized seasons yet." if _hall_season.is_empty() else ("No visible champions for this category." if entries.is_empty() else _hall_season.left(7)+" | First-place champions | Ties share the crown")
	_layout.get_node("ChampionshipHall/Pages/Page").text="Page %d" % (_hall_page+1)
	_layout.get_node("Status").text="Frozen results | Only currently opted-in players shown"

func _open_season_results() -> void:
	if not _ranking_open or not _operation.is_empty():return
	_results_open=true
	_season_results_data.clear()
	_layout.get_node("SeasonResults/History").set_pressed_no_signal(false)
	_layout.get_node("Leaderboard").hide()
	_layout.get_node("SeasonResults").show()
	UIFactory.clear(_layout.get_node("SeasonResults/Scroll/Rows"))
	_begin("season_results","/season-results")

func _close_season_results() -> void:
	_results_open=false
	_season_results_data.clear()
	_layout.get_node("SeasonResults").hide()
	_layout.get_node("Leaderboard").show()
	UIFactory.clear(_layout.get_node("SeasonResults/Scroll/Rows"))
	if _operation.is_empty():_request_rankings()

func _render_season_results(data:Dictionary) -> void:
	if not _results_open or str(data.get("playerId",""))!=_identity:return
	_season_results_data=data.duplicate(true)
	var rows=_layout.get_node("SeasonResults/Scroll/Rows")
	UIFactory.clear(rows)
	var first:=str(data.get("firstRewardSeason","2026-12-01"))
	_layout.get_node("SeasonResults/Rules").text="From %s (UTC) | Global opt-in at season close | Positive scores only | Ties share rewards | #1: 1000 Gold + title, #2: 600, #3: 300" % first.left(7)
	if _layout.get_node("SeasonResults/History").button_pressed:
		var championships:Array=data.get("championships",[])
		if championships.is_empty():rows.add_child(UIFactory.label("No championships earned yet.",16,UITheme.TEXT_DIM))
		for record in championships:
			var row=preload("res://scenes/ui/components/season_result_row.tscn").instantiate()
			rows.add_child(row)
			row.get_node("Row/Info").text="%s | %s | First place\nScore %d | %s" % [str(record.season).left(7),str(record.category).capitalize(),int(record.score),str(record.title)]
			row.get_node("Row/Info").add_theme_color_override("font_color",UITheme.GOLD)
			row.get_node("Row/Claim").hide()
		_layout.get_node("Status").text="Championship history | All first-place finishes"
		return
	var results:Array=data.get("results",[])
	if results.is_empty():rows.add_child(UIFactory.label("No finalized results yet.",16,UITheme.TEXT_DIM))
	for result in results:
		var row=preload("res://scenes/ui/components/season_result_row.tscn").instantiate()
		rows.add_child(row)
		row.get_node("Row/Info").text="%s | %s | #%d | Score %d\n%d Gold%s" % [str(result.season).left(7),str(result.category).capitalize(),int(result.rank),int(result.score),int(result.gold),(" + "+str(result.title)) if not str(result.title).is_empty() else ""]
		var button:Button=row.get_node("Row/Claim")
		button.disabled=not bool(result.canClaim)
		button.text="Claimed" if result.claimed else ("Claim" if result.canClaim else "No reward")
		button.pressed.connect(_claim_season.bind(str(result.season),str(result.category)))
	_layout.get_node("Status").text="Frozen seasonal results | Rewards are one-time"

func _claim_season(season:String,category:String) -> void:
	if not _results_open or not _operation.is_empty():return
	if _begin("season_claim","/season-results/claim",{"season":season,"category":category}):
		for row in _layout.get_node("SeasonResults/Scroll/Rows").get_children():
			var button=row.get_node_or_null("Row/Claim")
			if button!=null:button.disabled=true

func _request_rankings() -> void:
	if not _ranking_open or not _operation.is_empty():return
	_elapsed=0.0
	_season_deadline=0
	_season_key=""
	_layout.get_node("Leaderboard/Season").visible=_ranking_period=="monthly"
	_layout.get_node("Leaderboard/Season").text="Loading season..."
	UIFactory.clear(_layout.get_node("Leaderboard/Scroll/Rows"))
	_layout.get_node("Leaderboard/Visibility").visible=_ranking_scope=="global"
	_layout.get_node("Leaderboard/Toolbar/Heading").text="GLOBAL LEADERBOARD" if _ranking_scope=="global" else "FRIEND LEADERBOARD"
	_layout.get_node("Leaderboard/Summary").text="Loading verified rankings..."
	_begin("rankings","/leaderboard?category="+_ranking_category+"&scope="+_ranking_scope+"&period="+_ranking_period)

func _save_ranking_visibility(value:bool) -> void:
	if not _ranking_open or _ranking_scope!="global" or not _begin("ranking_visibility","/leaderboard/visibility",{"enabled":value}):
		_layout.get_node("Leaderboard/Visibility").set_pressed_no_signal(_ranking_enabled)

func _render_rankings(data:Dictionary) -> void:
	if not _ranking_open or str(data.get("playerId",""))!=_identity or str(data.get("category",""))!=_ranking_category or str(data.get("scope",""))!=_ranking_scope or str(data.get("period","lifetime"))!=_ranking_period:return
	if _ranking_period=="monthly":
		_season_key=str(data.get("season",""))
		_season_deadline=Time.get_ticks_msec()+maxi(0,int(data.get("resetAt",0))-int(data.get("serverTime",0)))
		_update_season_countdown()
	_ranking_enabled=bool(data.get("enabled",false))
	_layout.get_node("Leaderboard/Visibility").set_pressed_no_signal(_ranking_enabled)
	var rows=_layout.get_node("Leaderboard/Scroll/Rows")
	UIFactory.clear(rows)
	var own_rank:=0
	for entry in data.get("rows",[]):
		var row=preload("res://scenes/ui/components/leaderboard_row.tscn").instantiate()
		rows.add_child(row)
		var mine:bool=entry.self
		var accent:Color=UITheme.GOLD if mine else UITheme.TEXT_DIM
		row.add_theme_stylebox_override("panel",UITheme.style(Color("#21182c"),accent,6,1,8))
		row.get_node("Row/Rank").text="#%d" % int(entry.rank)
		row.get_node("Row/Portrait").texture=PORTRAIT.texture(str(entry.avatar))
		row.get_node("Row/Name").text=str(entry.name)+(" (You)" if mine else "")
		row.get_node("Row/Score").text=str(int(entry.score))
		if mine:own_rank=int(entry.rank)
	var total:=int(data.get("total",data.get("rows",[]).size()))
	var rank_text:="Your rank: #%d" % own_rank if own_rank>0 else "Unranked ? opt in to join"
	_layout.get_node("Leaderboard/Summary").text="%s | %d players | Equal scores share a rank" % [rank_text,total]
	_layout.get_node("Status").text=("Top 50 + your rank | Opt-in global" if _ranking_scope=="global" else "Accepted friends only")+(" | Monthly online progress" if _ranking_period=="monthly" else " | Lifetime online progress")

func _update_season_countdown() -> void:
	if _season_key.is_empty() or _season_deadline<=0:return
	var seconds:=maxi(0,ceili(float(_season_deadline-Time.get_ticks_msec())/1000.0))
	var days:=floori(float(seconds)/86400.0)
	var hours:=floori(float(seconds%86400)/3600.0)
	var minutes:=floori(float(seconds%3600)/60.0)
	_layout.get_node("Leaderboard/Season").text="Season %s (UTC) | Resets in %dd %02dh %02dm" % [_season_key,days,hours,minutes]

func _inspect_friend(id:String) -> void:
	if not _operation.is_empty():return
	if not _friends.any(func(f):return str(f.id)==id and f.status=="accepted"):return
	_inspected_id=id
	_elapsed=0.0
	_layout.get_node("FriendProfile").visible=true
	for name in ["ProfileHeading","Profile","Stats","Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll","BadgeGallery","PortraitGallery"]:
		_layout.get_node(name).visible=false
	_clear_inspected_details()
	_layout.get_node("Status").text="Loading friend profile..."
	_begin("inspect","/friend-profile?playerId="+id.uri_encode())

func _clear_inspected_details() -> void:
	var details=_layout.get_node("FriendProfile/Scroll/Details")
	details.visible=false
	details.get_node("Identity/Portrait").texture=null
	details.get_node("Identity/Text/Name").text=""
	details.get_node("Identity/Text/Title").text=""
	details.get_node("Stats").text=""
	UIFactory.clear(details.get_node("Badges"))

func _close_friend_profile() -> void:
	_inspected_id=""
	_layout.get_node("FriendProfile").visible=false
	_clear_inspected_details()
	for name in ["ProfileHeading","Profile","Stats","Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll"]:
		_layout.get_node(name).visible=true
	_queued_refresh=true
	_update_controls()

func _render_friend_profile(data:Dictionary) -> void:
	if _inspected_id.is_empty() or str(data.get("id",""))!=_inspected_id:return
	var details=_layout.get_node("FriendProfile/Scroll/Details")
	details.visible=true
	details.get_node("Identity/Portrait").texture=PORTRAIT.texture(str(data.avatar))
	details.get_node("Identity/Text/Name").text=str(data.name)
	var title:=str(data.get("title",""))
	var style=preload("res://scripts/ui/achievement_title_style.gd")
	details.get_node("Identity/Text/Title").text=title if not title.is_empty() else "No equipped title"
	details.get_node("Identity/Text/Title").add_theme_color_override("font_color",style.color(title))
	details.get_node("Identity/Text/Presence").text="Online" if data.online else "Offline"
	var stats:Dictionary=data.get("stats",{})
	details.get_node("Stats").text="Level %d | %s XP\n%d expedition victories | %d explored landmarks" % [int(stats.get("level",1)),str(stats.get("xp","0")),int(stats.get("victories",0)),int(stats.get("landmarks",0))]
	details.get_node("Completion").text="%d / %d achievements earned" % [int(data.achievementCount),int(data.achievementTotal)]
	details.get_node("Progress").max_value=maxi(1,int(data.achievementTotal))
	details.get_node("Progress").value=int(data.achievementCount)
	var badges=details.get_node("Badges")
	UIFactory.clear(badges)
	for badge in data.get("badges",[]):
		var row=preload("res://scenes/ui/components/achievement_badge_row.tscn").instantiate()
		badges.add_child(row)
		var accent:Color=style.color(str(badge.name))
		row.add_theme_stylebox_override("panel",UITheme.style(Color("#21182c"),accent,6,1,8))
		row.get_node("Row/Badge").add_theme_color_override("font_color",accent)
		row.get_node("Row/Info").text="%s | %s\n%s" % [badge.name,style.tier(str(badge.name)),badge.achievement]
		row.get_node("Row/Pin").hide()
	details.get_node("Empty").visible=data.get("badges",[]).is_empty()
	_layout.get_node("Status").text="Friend profile ? Read only"

func _open_private(player_id: String) -> void:
	if not AuthGateway.is_authenticated() or not _operation.is_empty():return
	for friend in _friends:
		if str(friend.id)==player_id and friend.status=="accepted":
			private_chat_requested.emit(player_id)
			return

func _invite_friend(player_id: String) -> void:
	_begin("party_send","/friend-invites",{"playerId":player_id})

func _respond_party(invite_id: String, action: String) -> void:
	_begin("party_response","/friend-invites/respond",{"inviteId":invite_id,"action":action})

func _render_friends():
	var rows=_layout.get_node("Scroll/Rows")
	UIFactory.clear(rows)
	var accepted:=0
	var incoming:=0
	for friend in _friends:
		if friend.status=="accepted":accepted+=1
		elif friend.direction=="incoming":incoming+=1
	_layout.get_node("Heading").text="FRIENDS (%d)  |  INCOMING (%d)" % [accepted,incoming]
	if _friends.is_empty():rows.add_child(UIFactory.label("No friends or pending requests.",14,UITheme.TEXT_DIM))
	var display_friends:=_friends.duplicate()
	if TouchInput.using_touch:
		display_friends.sort_custom(func(a,b):return int(a.status=="pending" and a.direction=="incoming")>int(b.status=="pending" and b.direction=="incoming"))
	for friend in display_friends:
		var row:=HBoxContainer.new()
		var portrait:=TextureRect.new()
		portrait.custom_minimum_size=Vector2(48,48)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture=PORTRAIT.texture(str(friend.avatar))
		row.add_child(portrait)
		var label:=UIFactory.label(str(friend.name)+" — "+(("Online" if friend.get("online",false) else "Offline") if friend.status=="accepted" else str(friend.direction).capitalize()+" request"),14,UITheme.TEXT)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var title:=str(friend.get("title",""))
		if not title.is_empty():
			label.text+="\n"+title
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var badges:PackedStringArray=PackedStringArray(friend.get("badges",[]))
		if not badges.is_empty():
			label.text+="\nBadges: "+", ".join(badges)
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if friend.status=="accepted":
			var inspect:=UIFactory.button("Profile",false)
			inspect.pressed.connect(_inspect_friend.bind(str(friend.id)))
			row.add_child(inspect)
			var message:=UIFactory.button("Message",true)
			message.pressed.connect(_open_private.bind(str(friend.id)))
			row.add_child(message)
			var invite:=UIFactory.button("Invite",false)
			invite.pressed.connect(_invite_friend.bind(str(friend.id)))
			row.add_child(invite)
		var actions=["remove"] if friend.status=="accepted" else (["accept","decline"] if friend.direction=="incoming" else ["cancel"])
		for action in actions:
			var button:=UIFactory.button(action.capitalize(),action=="accept")
			button.set_meta("friend_action",true)
			if TouchInput.using_touch:button.custom_minimum_size=Vector2(90,52)
			button.pressed.connect(_friend_action.bind(str(friend.id),action))
			row.add_child(button)
		rows.add_child(row)

	for invite in _party_invites:
		var row:=HBoxContainer.new()
		var label:=UIFactory.label(str(invite.name)+" invites you to "+str(invite.regionId).trim_prefix("six_zone_").replace("_"," ").capitalize(),14,UITheme.TEXT)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		for action in ["accept","decline"]:
			var button:=UIFactory.button(action.capitalize(),action=="accept")
			button.pressed.connect(_respond_party.bind(str(invite.id),action))
			row.add_child(button)
		rows.add_child(row)
func _toggle_gallery() -> void:
	_set_gallery_visible(not _layout.get_node("PortraitGallery").visible)

func _set_gallery_visible(value: bool) -> void:
	if value and _layout.get_node("BadgeGallery").visible:_set_badge_gallery(false)
	var gallery: Control = _layout.get_node("PortraitGallery")
	gallery.visible = value
	for name in ["Titles","AchievementShowcase","Divider","SearchHeading","Search","Result","Heading","Rankings","Scroll"]:
		_layout.get_node(name).visible = not value
	_layout.get_node("Profile/Browse").text = "Back to friends" if value else "Choose portrait"
	if value:
		GameState.lifecycle_component.save_now()
		_layout.get_node("PortraitGallery/Toolbar/Search").clear()
		_render_gallery()
		_layout.get_node("PortraitGallery/Toolbar/Search").grab_focus()

func _render_gallery() -> void:
	var options: OptionButton = _layout.get_node("Profile/Pictures")
	var field: LineEdit = _layout.get_node("PortraitGallery/Toolbar/Search")
	var grid: GridContainer = _layout.get_node("PortraitGallery/Scroll/Grid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var query := field.text.strip_edges().to_lower()
	var count := 0
	for i in range(options.item_count):
		var id := str(options.get_item_metadata(i))
		var label := options.get_item_text(i)
		if not query.is_empty() and not label.to_lower().contains(query) and not id.contains(query):
			continue
		var tile: Button = PORTRAIT_TILE.instantiate()
		tile.name = id
		var unlocked := _unlocked_portraits.has(id)
		tile.text = label if unlocked else label + "\nLocked"
		tile.tooltip_text = label if unlocked else "Obtain this character to unlock its portrait."
		tile.disabled = not unlocked
		if not unlocked: tile.modulate = Color(0.65, 0.65, 0.65, 1.0)
		tile.icon = options.get_item_icon(i)
		tile.button_pressed = i == options.selected
		tile.pressed.connect(_choose_gallery_portrait.bind(i))
		grid.add_child(tile)
		count += 1
	_layout.get_node("PortraitGallery/Toolbar/Count").text = "%d unlocked / %d total  |  %d shown" % [_unlocked_portraits.size(), options.item_count, count]

func _choose_gallery_portrait(index: int) -> void:
	var options: OptionButton = _layout.get_node("Profile/Pictures")
	if options.disabled or index < 0 or index >= options.item_count or options.is_item_disabled(index):
		return
	options.select(index)
	options.item_selected.emit(index)
	_render_gallery()

func _resize_gallery() -> void:
	var grid: GridContainer = _layout.get_node("PortraitGallery/Scroll/Grid")
	var scroll: ScrollContainer = _layout.get_node("PortraitGallery/Scroll")
	grid.columns = clampi(int((scroll.size.x - 24.0) / 160.0), 2, 7)


func _on_roster_changed() -> void:
	if not AuthGateway.is_authenticated() or not _profile_loaded: return
	GameState.lifecycle_component.save_now()
	_roster_refresh=true


func _open_guilds():
	if not AuthGateway.is_authenticated() or not _operation.is_empty():return
	var guild:OverlayScreen=preload("res://scenes/ui/guild_screen.tscn").instantiate()
	_shell.hide()
	set_process(false)
	set_process_unhandled_input(false)
	guild.closed.connect(func():
		if not _closing:
			_shell.show()
			set_process(true)
			set_process_unhandled_input(true)
			_queued_refresh=true)
	add_child(guild)