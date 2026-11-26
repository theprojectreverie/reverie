extends OverlayScreen
const LAYOUT=preload("res://scenes/ui/components/daily_quests_layout.tscn")
var _layout: VBoxContainer
var _elapsed:=0.0
var _online:=false
var _weekly:=false
var _monthly:=false
var _achievements:=false
var _received_at:=0
var _remote: Dictionary={}
var _request: HTTPRequest
var _request_player:=""
var _operation:=""
var _remote_elapsed:=10.0
var _error:=""
var _history_open:=false
var _history: Array=[]
var _history_loaded:=false
var _achievement_category:=""


func _init() -> void:
	screen_title="Quest Challenges"
	screen_subtitle="Complete your daily duties and collect the bonus."

func _build_content() -> void:
	_layout=LAYOUT.instantiate()
	content.add_child(_layout)
	_request=HTTPRequest.new()
	_request.timeout=8.0
	add_child(_request)
	_request.request_completed.connect(_completed)
	AuthGateway.authentication_changed.connect(_identity_changed)
	_layout.get_node("Actions/ClaimAll").pressed.connect(_claim_all)
	_layout.get_node("Actions/History").pressed.connect(_toggle_history)
	var category:OptionButton=_layout.get_node("Category")
	for label in ["All achievements","Adventure","Combat","Devotion","Bosses","Exploration","Collection","Ascension","Bonds"]:
		category.add_item(label)
	category.select(0)
	category.item_selected.connect(func(index:int):
		_achievement_category="" if index==0 else category.get_item_text(index)
		_layout.get_node("Scroll").scroll_vertical=0
		_refresh())

	_layout.get_node("Modes/Story").pressed.connect(_select_mode.bind(false))
	_layout.get_node("Modes/Online").pressed.connect(_select_mode.bind(true))
	_layout.get_node("Modes/Weekly").pressed.connect(_select_mode.bind(true,true))
	_layout.get_node("Modes/Monthly").pressed.connect(_select_mode.bind(true,false,true))
	_layout.get_node("Modes/Achievements").pressed.connect(_select_mode.bind(true,false,false,true))
	var rows: Array=_layout.get_node("Scroll/Rows").get_children()
	for i in rows.size():
		rows[i].get_node("Row/Reward/Claim").pressed.connect(_claim_index.bind(i))
	var prefer_weekly:=AuthGateway.is_authenticated() and AuthGateway.online_weekly_claimable>0 and AuthGateway.online_daily_claimable==0 and GameState.reward_domain.daily_quest_claimable_count()==0
	var prefer_monthly:=AuthGateway.is_authenticated() and AuthGateway.online_monthly_claimable>0 and AuthGateway.online_weekly_claimable==0 and AuthGateway.online_daily_claimable==0 and GameState.reward_domain.daily_quest_claimable_count()==0
	var prefer_achievements:=AuthGateway.is_authenticated() and AuthGateway.online_achievement_claimable>0 and AuthGateway.online_monthly_claimable==0 and AuthGateway.online_weekly_claimable==0 and AuthGateway.online_daily_claimable==0 and GameState.reward_domain.daily_quest_claimable_count()==0
	_select_mode(prefer_achievements or prefer_monthly or prefer_weekly or not MultiplayerGateway.standalone_expedition_id.is_empty() or (AuthGateway.is_authenticated() and AuthGateway.online_daily_claimable>0 and GameState.reward_domain.daily_quest_claimable_count()==0),prefer_weekly,prefer_monthly,prefer_achievements)

func _process(delta:float) -> void:
	_elapsed+=delta
	_remote_elapsed+=delta
	if _online and not _history_open and _remote_elapsed>=5.0 and _operation.is_empty():
		_fetch()
	if _elapsed>=0.5:
		_elapsed=0.0
		_refresh()

func _select_mode(online:bool,weekly:bool=false,monthly:bool=false,achievements:bool=false) -> void:
	if not _operation.is_empty():
		_sync_tabs()
		return
	_history_open=false
	if online!=_online or weekly!=_weekly or monthly!=_monthly or achievements!=_achievements:
		_remote.clear()
		_error=""
	_online=online
	_weekly=weekly
	_monthly=monthly
	_achievements=achievements
	_sync_tabs()
	if online:
		_fetch()
	_refresh()

func _sync_tabs() -> void:
	_layout.get_node("Modes/Story").set_pressed_no_signal(not _online)
	_layout.get_node("Modes/Online").set_pressed_no_signal(_online and not _weekly and not _monthly and not _achievements)
	_layout.get_node("Modes/Weekly").set_pressed_no_signal(_weekly)
	_layout.get_node("Modes/Monthly").set_pressed_no_signal(_monthly)
	_layout.get_node("Modes/Achievements").set_pressed_no_signal(_achievements)


func _identity_changed(_authenticated:bool,_player:Dictionary) -> void:
	_request.cancel_request()
	_operation=""
	_request_player=""
	_remote.clear()
	_history.clear()
	_history_loaded=false
	_history_open=false
	_error=""
	_remote_elapsed=10.0
	_refresh()

func _fetch() -> void:
	_remote_elapsed=0.0
	_begin("read","/achievements" if _achievements else ("/monthly" if _monthly else ("/weekly" if _weekly else "")),HTTPClient.METHOD_GET,{})

func _begin(operation:String,path:String,method:HTTPClient.Method,payload:Dictionary) -> void:
	if not _operation.is_empty() or not AuthGateway.access_token_ready_for_connection():return
	_request_player=str(AuthGateway.current_player().get("id",""))
	_operation=operation
	var headers:=PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
	if _request.request(AuthGateway.api_base_url+"/v1/daily-quests"+path,headers,method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")!=OK:
		_operation=""
		_request_player=""
		_error="Could not connect. Retrying..."

func _completed(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray) -> void:
	var op:=_operation
	var player:=_request_player
	_operation=""
	_request_player=""
	if player.is_empty() or player!=str(AuthGateway.current_player().get("id","")):return
	var data=JSON.parse_string(body.get_string_from_utf8())
	if op=="history":
		_history_loaded=result==HTTPRequest.RESULT_SUCCESS and code==200 and data is Dictionary and str(data.get("playerId",""))==player
		_history=data.get("entries",[]) if _history_loaded else []
		_refresh()
		return
	if result!=HTTPRequest.RESULT_SUCCESS or code not in [200,409] or not data is Dictionary or str(data.get("playerId",""))!=player or not data.get("rows") is Array:
		# Keep last confirmed claims visible during a failed refresh.
		if not _remote.is_empty():
			for row in _remote.rows:row["can_claim"]=false
		_error="Quest status unavailable. Refreshing..."
		_remote_elapsed=5.0 if code==409 else 0.0
	else:
		var verified:Dictionary = data if _achievements else AuthGateway.remember_quest_status(data,_weekly,_monthly)
		if verified.is_empty():
			_remote_elapsed=5.0
			_refresh()
			return
		_remote=verified
		_received_at=Time.get_ticks_msec()
		_error=""
		_remote_elapsed=0.0
		if _achievements:
			AuthGateway._announce_achievement_ready(_remote.rows.filter(func(row):return bool(row.get("can_claim",false))))
		var count:=0
		for row in _remote.rows:
			if row.can_claim:count+=1
		if _achievements:
			AuthGateway.online_achievement_claimable=count
		elif _monthly:
			AuthGateway.online_monthly_claimable=count
		elif _weekly:
			AuthGateway.online_weekly_claimable=count
		else:
			AuthGateway.online_daily_claimable=count
		if code==200 and op in ["claim","claim_all"]:
			AuthGateway.refresh_online_wallet()
			AuthGateway.refresh_social_summary()
			var gold:=0
			var crystals:=0
			for award in data.get("awards",[]):
				gold+=int(award.gold)
				crystals+=int(award.crystals)
			if gold>0 or crystals>0:
				EventBus.toast_requested.emit("Quest rewards: +%d Gold, +%d Crystals" % [gold,crystals])
		elif code==409:
			AuthGateway.refresh_online_wallet()
			AuthGateway.refresh_social_summary()
	_refresh()

func _toggle_history() -> void:
	if not _operation.is_empty() or not _online:return
	_history_open=not _history_open
	if _history_open:
		_history.clear()
		_history_loaded=false
		_begin("history","/history",HTTPClient.METHOD_GET,{})
	else:
		_fetch()
	_refresh()

func _claim_all() -> void:
	if _history_open:return
	if _online:
		if _remote.is_empty() or not _operation.is_empty() or _seconds_remaining()<=0:return
		_begin("claim_all","/achievements/claim-all" if _achievements else ("/monthly/claim-all" if _monthly else ("/weekly/claim-all" if _weekly else "/claim-all")),HTTPClient.METHOD_POST,{} if _achievements else {"date":_remote.date})
	else:
		for task in GameRewardDomainComponent.DAILY_TASKS:
			GameState.reward_domain.claim_daily_quest(str(task.id))
	_refresh()

func _claim_index(index:int) -> void:
	if _online:
		if _remote.is_empty() or not _operation.is_empty() or _seconds_remaining()<=0 or index>=_remote.rows.size():return
		var row:Dictionary=_remote.rows[index]
		if row.can_claim:
			_begin("claim","/achievements/claim" if _achievements else ("/monthly/claim" if _monthly else ("/weekly/claim" if _weekly else "/claim")),HTTPClient.METHOD_POST,{"id":row.id} if _achievements else {"id":row.id,"date":_remote.date})
	else:
		if index>=GameRewardDomainComponent.DAILY_TASKS.size():return
		GameState.reward_domain.claim_daily_quest(str(GameRewardDomainComponent.DAILY_TASKS[index].id))
	_refresh()

func _refresh() -> void:
	if _layout==null:return
	var data:=_remote if _online else GameState.reward_domain.daily_quest_status()
	var scroll:ScrollContainer=_layout.get_node("Scroll")
	scroll.visible=not data.is_empty() and not _history_open
	var all_button:Button=_layout.get_node("Actions/ClaimAll")
	var history_button:Button=_layout.get_node("Actions/History")
	history_button.visible=_online
	history_button.disabled=not _operation.is_empty() or not AuthGateway.is_authenticated()
	history_button.text="Back to quests" if _history_open else "Reward History"
	all_button.visible=not _history_open
	all_button.text="Claim All Categories" if _achievements else "Claim All"
	all_button.disabled=true
	_layout.get_node("HistoryScroll").visible=_history_open
	_layout.get_node("Category").visible=_achievements and not _history_open
	if _history_open:
		_layout.get_node("Summary").text="Reward history | latest 50 online claims"
		_layout.get_node("Reset").text="Online quest and achievement rewards credited to your server wallet"
		var lines:=PackedStringArray()
		for entry in _history:
			lines.append("%s  |  %s - %s\n+%d Gold   +%d Crystals  |  %s UTC" % [entry.date,entry.period,entry.title,entry.gold,entry.crystals,str(entry.claimedAt).replace("T"," ").left(19)])
		_layout.get_node("HistoryScroll/Entries").text="\n\n".join(lines) if not lines.is_empty() else ("No rewards claimed yet." if _history_loaded else ("Loading..." if not _operation.is_empty() else "History unavailable. Return and try again."))
		return
	if not data.is_empty():
		for task in data.rows:
			if task.can_claim and (not _online or (_operation.is_empty() and _seconds_remaining()>0)):
				all_button.disabled=false
				break
	_layout.get_node("Footer").text="Online rewards go to your account's server wallet." if _online else "Story rewards only. Online expeditions do not count toward this journal."
	if data.is_empty():
		_layout.get_node("Summary").text="Sign in to access online daily quests." if not AuthGateway.is_authenticated() else ("Loading online daily quests..." if _error.is_empty() else _error)
		_layout.get_node("Reset").text="Resets on the first of each month at 00:00 UTC" if _monthly else ("Resets Monday at 00:00 UTC" if _weekly else "Reset at 00:00 UTC")
		return
	var claimed:=0
	var rows: Array=_layout.get_node("Scroll/Rows").get_children()
	for i in rows.size():
		var row: PanelContainer=rows[i]
		row.visible=i<data.rows.size()
		if not row.visible:continue
		var task: Dictionary=data.rows[i]
		if _achievements and not _achievement_category.is_empty() and str(task.get("category",""))!=_achievement_category:
			row.visible=false
			if task.claimed:claimed+=1
			continue
		var accent:=UITheme.GOLD if task.can_claim else (UITheme.GREEN if task.claimed else UITheme.BORDER)
		row.add_theme_stylebox_override("panel",UITheme.style(Color("#21182c"),accent,8,1,10))
		row.get_node("Row/Info/Title").text=task.title
		row.get_node("Row/Info/Title").add_theme_color_override("font_color",accent if task.can_claim or task.claimed else UITheme.TEXT)
		row.get_node("Row/Info/Description").text=("%s | %s\nTitle: %s (%s)" % [task.get("category",""),task.description,task.get("unlockTitle",""),preload("res://scripts/ui/achievement_title_style.gd").tier(str(task.get("unlockTitle","")))]) if _achievements else task.description
		var bar: ProgressBar=row.get_node("Row/Info/Progress")
		bar.max_value=task.target
		bar.value=task.progress
		row.get_node("Row/Info/ProgressText").text="%d / %d" % [task.progress,task.target]
		row.get_node("Row/Reward/Amount").text="%d Gold" % task.gold+("\n%d Crystals" % task.crystals if task.crystals>0 else "")
		var button: Button=row.get_node("Row/Reward/Claim")
		button.disabled=not task.can_claim or (_online and (not _operation.is_empty() or _seconds_remaining()<=0))
		button.text="Claimed" if task.claimed else ("Claim" if task.can_claim else "In progress")
		if (i<3 or _achievements) and task.claimed:claimed+=1
	_layout.get_node("Summary").text="%d / 3 duties claimed" % claimed if bool(data.get("enabled",true)) else "Complete the tutorial to unlock daily quests." if MultiplayerGateway.standalone_expedition_id.is_empty() else "Daily story quests are paused in online expeditions."
	if _achievements:
		_layout.get_node("Summary").text="%d / %d achievements claimed" % [claimed,data.rows.size()]
		_layout.get_node("Reset").text="Permanent achievements | Never reset"+(" | "+_achievement_category if not _achievement_category.is_empty() else "")
		return
	var seconds:=_seconds_remaining()
	var days:=floori(seconds/86400.0)
	var hours:=floori(seconds/3600.0)%24
	var minutes:=floori(seconds/60.0)%60
	var label:="Monthly reset" if _monthly else ("Weekly reset" if _weekly else "Daily reset")
	_layout.get_node("Reset").text="%s in %s%02d:%02d:%02d  |  %s" % [label,("%dd " % days) if days>0 else "",hours,minutes,seconds%60,"First of month 00:00 UTC" if _monthly else ("Monday 00:00 UTC" if _weekly else ("00:00 UTC" if _online else "Local midnight"))]
	if _online and seconds==0 and _operation.is_empty():
		_remote_elapsed=5.0

func _seconds_remaining() -> int:
	if _achievements:return 1 # Permanent, never expires.
	if _online:
		return maxi(0,ceili((float(_remote.get("resetAt",0))-float(_remote.get("serverTime",0))-(Time.get_ticks_msec()-_received_at))/1000.0))
	var local:=Time.get_datetime_dict_from_system()
	return maxi(0,86400-int(local.hour)*3600-int(local.minute)*60-int(local.second))

