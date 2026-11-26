extends OverlayScreen
const LAYOUT=preload("res://scenes/ui/components/guild_layout.tscn")
const PORTRAIT=preload("res://scripts/ui/social_portrait.gd")
const EMBLEMS=["moon","star","shield","flame","rose","crown"]
var _layout:VBoxContainer
var _body:VBoxContainer
var _request:HTTPRequest
var _identity:=""
var _operation:=""
var _guild:Dictionary={}
var _invite_id:=""
var _invite_name:=""
var _page:=0
var _search:=""
var _confirmed:Callable
var _loaded:=false
var _treasury:Dictionary={}
var _pending_donation:Dictionary={}
var _shop:Dictionary={}
var _pending_shop:Dictionary={}
var _raid:Dictionary={}
var _raid_attempt:Dictionary={}
var _raid_result:Dictionary={}
var _raid_notice:=""

func _init():
	screen_title="Guilds"
	screen_subtitle="Build your community in Reverie"

func _build_content():
	_layout=LAYOUT.instantiate()
	content.add_child(_layout)
	_body=_layout.get_node("Scroll/Body")
	_request=HTTPRequest.new()
	_request.timeout=45.0
	add_child(_request)
	_request.request_completed.connect(_completed)
	var options:OptionButton=_body.get_node("Editor/Emblem")
	for emblem in EMBLEMS:options.add_item(emblem.capitalize())
	options.select(0)
	var amounts:OptionButton=_body.get_node("Treasury/Donation/Amount")
	for amount in [100,500,1000]:amounts.add_item("%d gold" % amount,amount)
	amounts.select(0)
	amounts.item_selected.connect(func(_index):_controls())
	_body.get_node("Treasury/Donation/Donate").pressed.connect(_donate)
	_body.get_node("Shop/Retry").pressed.connect(_retry_shop)
	_body.get_node("Competition/Open").pressed.connect(func():_begin("competition","/competition"))
	_body.get_node("Raid/Boss/Portrait").texture=PORTRAIT.texture("cassien")
	_body.get_node("Raid/Buttons/Start").pressed.connect(_raid_start)
	_body.get_node("Raid/Buttons/Claim").pressed.connect(_raid_claim)
	_body.get_node("Raid/Battle/Abandon").pressed.connect(_raid_abandon)
	_body.get_node("Raid/Battle/Stage").playback_changed.connect(func(_busy):_controls())
	_layout.get_node("Toolbar/Refresh").pressed.connect(_load)
	_layout.get_node("Toolbar/Find").pressed.connect(_find)
	_layout.get_node("Toolbar/Search").text_submitted.connect(func(_v):_find())
	_body.get_node("Editor/Save").pressed.connect(_save)
	_body.get_node("Invite/Find").pressed.connect(_find_player)
	_body.get_node("Invite/Name").text_changed.connect(func(_v):_invite_id="";_invite_name="";_controls())
	_body.get_node("Invite/Confirm").pressed.connect(func():_confirm("Invite "+_invite_name+"?",func():_post("/invite",{"playerId":_invite_id})))
	_body.get_node("Leave").pressed.connect(func():_confirm("Disband this guild? Its treasury will be lost." if _guild.get("role","")=="leader" and int(_guild.get("memberCount",0))==1 else "Leave your guild? Donations are not refunded.",func():_post("/leave",{})))
	_layout.get_node("ConfirmAction").confirmed.connect(func():if _confirmed.is_valid():_confirmed.call())
	AuthGateway.authentication_changed.connect(_auth_changed)
	_identity=str(AuthGateway.current_player().get("id",""))
	_load()

func _auth_changed(authenticated:bool,player:Dictionary):
	var id:=str(player.get("id","")) if authenticated else ""
	if id==_identity:return
	_identity=id
	_request.cancel_request()
	_operation=""
	_guild.clear()
	_clear_competition()
	_raid.clear()
	_raid_attempt.clear()
	_raid_result.clear()
	_raid_notice=""
	_treasury.clear()
	_pending_donation.clear()
	_pending_shop.clear()
	_shop.clear()
	_loaded=false
	_invite_id=""
	_invite_name=""
	_body.get_node("Editor/Name").clear()
	_body.get_node("Editor/Description").clear()
	_layout.get_node("ConfirmAction").hide()
	for key in ["Requests","Members","Results"]:UIFactory.clear(_body.get_node(key))
	_render({})
	_load()

func _begin(op:String,path:String,method:=HTTPClient.METHOD_GET,payload:Dictionary={}):
	if not _operation.is_empty() or not AuthGateway.is_authenticated() or not AuthGateway.access_token_ready_for_connection():return
	_operation=op
	var prefix:="/v1/social" if op=="player" else "/v1/guilds"
	var headers:=PackedStringArray(["Authorization: Bearer "+AuthGateway.access_token_for_request(),"Content-Type: application/json"])
	if _request.request(AuthGateway.api_base_url+prefix+path,headers,method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")!=OK:
		_operation=""
		_layout.get_node("Status").text="Guild service unavailable."
	_controls()

func _load():
	if not AuthGateway.is_authenticated():
		_layout.get_node("Status").text="Sign in to use guilds."
		_controls()
		return
	_begin("me","/me")

func _post(path:String,payload:Dictionary):
	_begin("mutation",path,HTTPClient.METHOD_POST,payload)

func _find():
	_search=_layout.get_node("Toolbar/Search").text.strip_edges()
	_page=0
	_search_page(0)

func _search_page(page:int):
	_page=page
	_begin("search","/search?q="+_search.uri_encode()+"&page="+str(page))

func _find_player():
	var name:=str(_body.get_node("Invite/Name").text).strip_edges()
	if name.length()<3:return
	_invite_id=""
	_begin("player","/search?name="+name.uri_encode())

func _save():
	var options:OptionButton=_body.get_node("Editor/Emblem")
	var payload={"name":str(_body.get_node("Editor/Name").text).strip_edges(),"description":str(_body.get_node("Editor/Description").text).strip_edges(),"emblem":EMBLEMS[options.selected]}
	_post("/create" if _guild.is_empty() else "/settings",payload)

func _completed(result:int,code:int,_headers:PackedStringArray,bytes:PackedByteArray):
	var op:=_operation
	_operation=""
	if _identity!=str(AuthGateway.current_player().get("id","")):return
	var data=JSON.parse_string(bytes.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code<200 or code>=300 or not data is Dictionary:
		if op.begins_with("raid_"):
			_raid_attempt.clear()
			_raid_notice="Raid request unsuccessful. Refresh or resume to recover."
			_render_raid_battle()
			if result==HTTPRequest.RESULT_SUCCESS and data is Dictionary and str(data.get("error","")) in ["raid_defeated","guild_membership_required","raid_week_changed","raid_attempt_unavailable"]:
				_load()
		if op=="shop_buy":
			if result==HTTPRequest.RESULT_SUCCESS and code>=400 and code<500 and code!=429:_pending_shop.clear()
			AuthGateway.refresh_online_wallet()
		if op=="donate" and result==HTTPRequest.RESULT_SUCCESS and code>=400 and code<500 and code!=429:_pending_donation.clear()
		if op=="donate":AuthGateway.refresh_online_wallet()
		_layout.get_node("Status").text="Guild request unsuccessful: "+(str(data.get("error","try again")).replace("_"," ") if data is Dictionary else "try again")
		_controls()
		return
	match op:
		"me":
			_loaded=true
			_render(data)
			_layout.get_node("Status").text="Guild information updated."
		"search":_render_search(data)
		"player":
			var players:Array=data.get("players",[])
			if players.is_empty():_layout.get_node("Status").text="Player not found."
			else:
				_invite_id=str(players[0].id)
				_invite_name=str(players[0].name)
				_layout.get_node("Status").text="Invite "+_invite_name+"?"
		"donate":
			_pending_donation.clear()
			_render_treasury(data.get("treasury",{}))
			AuthGateway.refresh_online_wallet()
			_layout.get_node("Status").text="Donation confirmed: %d gold." % int(data.get("donated",0))
			_load()
		"raid_start","raid_action":
			_raid_attempt=data
			if str(data.get("status",data.get("view",{}).get("status","")))=="active":
				_raid_notice=""
				_raid["activeAttemptId"]=str(data.get("attemptId",""))
				_render_raid_battle()
			else:
				_raid_notice="Attempt complete: %d damage credited to your guild." % int(data.get("damage",0))
				_raid_result=data.duplicate(true)
				_raid_attempt.clear()
				_render_raid_battle()
				_load()
		"raid_abandon":
			_raid_attempt.clear()
			_raid_notice="Attempt abandoned. No damage credited."
			_render_raid_battle()
			_load()
		"raid_claim":
			_raid_notice="Weekly reward confirmed."
			AuthGateway.refresh_online_wallet()
			_load()
		"shop_buy":
			_pending_shop.clear()
			AuthGateway.refresh_online_wallet()
			_layout.get_node("Status").text="Guild purchase confirmed."
			_load()
		"competition_claim":
			AuthGateway.refresh_online_wallet()
			_begin("competition","/competition")
		"competition":
			_render_competition(data)
			_layout.get_node("Status").text="Guild league updated."
		"mutation":
			_invite_id=""
			UIFactory.clear(_body.get_node("Results"))
			if data.has("awardedTokens"):AuthGateway.refresh_online_wallet()
			_layout.get_node("Status").text="Guild action completed."
			_load()
	_controls()

func _render(data:Dictionary):
	var raw=data.get("guild")
	var next_guild:Dictionary=raw if raw is Dictionary else {}
	if str(next_guild.get("id",""))!=str(_guild.get("id","")):
		_raid_attempt.clear()
		_raid_result.clear()
		_raid_notice=""
		_clear_competition()
	_guild=next_guild
	_body.get_node("Competition").visible=_loaded
	_render_raid(data.get("raid"))
	_render_progression(data)
	_render_treasury(data.get("treasury",{}))
	_render_perks(data.get("perks",[]))
	_render_shop(data.get("shop"))
	var role:=str(_guild.get("role",""))
	var manage:=role in ["leader","officer"]
	_body.get_node("Summary").text="Find or create a guild" if _guild.is_empty() else "%s | Level %d | %d/%d members\n%s | %s\n%s" % [_guild.name,int(_guild.level),int(_guild.memberCount),int(data.get("capacity",30)),role.capitalize(),str(_guild.emblem).capitalize(),str(_guild.description)]
	_body.get_node("Editor").visible=_loaded and (_guild.is_empty() or role=="leader")
	_body.get_node("Editor/Save").text="Create guild" if _guild.is_empty() else "Save guild settings"
	if role=="leader":
		_body.get_node("Editor/Name").text=str(_guild.name)
		_body.get_node("Editor/Description").text=str(_guild.description)
		_body.get_node("Editor/Emblem").select(maxi(0,EMBLEMS.find(str(_guild.emblem))))
	_body.get_node("Invite").visible=manage
	_body.get_node("Leave").visible=not _guild.is_empty()
	for key in ["Requests","Members","Results"]:UIFactory.clear(_body.get_node(key))
	var requests:VBoxContainer=_body.get_node("Requests")
	if not data.get("requests",[]).is_empty():requests.add_child(UIFactory.heading("Guild requests",18))
	for entry in data.get("requests",[]):
		var row:=_row(requests,str(entry.get("name","Guild"))+" | "+str(entry.kind).capitalize())
		if _guild.is_empty():
			var gid:=str(entry.guildId)
			if entry.kind=="invitation":
				_button(row,"Accept",func():_post("/invitation",{"guildId":gid,"accept":true}))
				_button(row,"Decline",func():_post("/invitation",{"guildId":gid,"accept":false}))
			else:_button(row,"Cancel",func():_post("/cancel",{"guildId":gid}))
		elif manage:
			var pid:=str(entry.playerId)
			_button(row,"Accept",func():_post("/application",{"playerId":pid,"accept":true}))
			_button(row,"Decline",func():_post("/application",{"playerId":pid,"accept":false}))
	var members:VBoxContainer=_body.get_node("Members")
	if not _guild.is_empty():members.add_child(UIFactory.heading("Members",18))
	for entry in data.get("members",[]):
		var pid:=str(entry.id)
		var rank:=str(entry.role)
		var row:=_row(members,"%s | Lv %d | %s | %s" % [entry.name,int(entry.level),rank.capitalize(),"Online" if entry.online else "Offline"])
		var portrait:=TextureRect.new()
		portrait.custom_minimum_size=Vector2(40,40)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture=PORTRAIT.texture(str(entry.avatar))
		row.add_child(portrait)
		row.move_child(portrait,0)
		if pid==_identity:continue
		if role=="leader":
			var new_rank:="member" if rank=="officer" else "officer"
			_button(row,"Demote" if rank=="officer" else "Promote",func():_post("/role",{"playerId":pid,"role":new_rank}))
			_button(row,"Transfer",func():_confirm("Transfer guild leadership to "+str(entry.name)+"?",func():_post("/role",{"playerId":pid,"role":"leader"})))
		if (role=="leader" and rank!="leader") or (role=="officer" and rank=="member"):
			_button(row,"Remove",func():_confirm("Remove "+str(entry.name)+" from the guild?",func():_post("/kick",{"playerId":pid})))
	_controls()

func _render_search(data:Dictionary):
	var results:VBoxContainer=_body.get_node("Results")
	UIFactory.clear(results)
	results.add_child(UIFactory.heading("Guild search results",18))
	for entry in data.get("guilds",[]):
		var capacity:=int(entry.get("capacity",30))
		var row:=_row(results,"%s | Lv %d | %d/%d | %s" % [entry.name,int(entry.level),int(entry.memberCount),capacity,entry.emblem])
		var gid:=str(entry.id)
		if _guild.is_empty() and int(entry.memberCount)<capacity:_button(row,"Apply",func():_post("/apply",{"guildId":gid}))
	if data.get("guilds",[]).is_empty():results.add_child(UIFactory.wrapped("No matching guilds."))
	var pages:=HBoxContainer.new()
	results.add_child(pages)
	if _page>0:_button(pages,"Previous",func():_search_page(_page-1))
	if data.get("hasMore",false):_button(pages,"Next",func():_search_page(_page+1))
	_layout.get_node("Status").text="Guild search complete."

func _row(parent:VBoxContainer,value:String)->HBoxContainer:
	var row:=HBoxContainer.new()
	parent.add_child(row)
	var label:=UIFactory.wrapped(value,15)
	row.add_child(label)
	return row

func _button(parent:HBoxContainer,value:String,action:Callable):
	var button:=UIFactory.button(value)
	parent.add_child(button)
	button.pressed.connect(action)

func _confirm(message:String,action:Callable):
	if not _operation.is_empty():return
	_confirmed=action
	var dialog:ConfirmationDialog=_layout.get_node("ConfirmAction")
	dialog.dialog_text=message
	dialog.popup_centered()

func _controls():
	var ready:bool=AuthGateway.is_authenticated() and _operation.is_empty()
	_raid_controls(ready)
	_shop_controls(ready)
	_body.get_node("Competition/Open").disabled=not ready
	for league_row in _body.get_node("Competition/Rows").get_children():
		for child in league_row.get_children():
			if child is Button:child.disabled=not ready or bool(child.get_meta("unavailable",false))
	_layout.get_node("Toolbar/Refresh").disabled=not ready
	_layout.get_node("Toolbar/Find").disabled=not ready
	_body.get_node("Editor/Save").disabled=not ready or not _loaded
	_body.get_node("Invite/Find").disabled=not ready
	_body.get_node("Invite/Confirm").disabled=not ready or _invite_id.is_empty()
	_body.get_node("Leave").disabled=not ready
	var amounts:OptionButton=_body.get_node("Treasury/Donation/Amount")
	var amount:=amounts.get_selected_id()
	var remaining:=int(_treasury.get("dailyCap",0))-int(_treasury.get("donatedToday",0))
	amounts.disabled=not ready or not _pending_donation.is_empty()
	var retry:=not _pending_donation.is_empty()
	var donate:Button=_body.get_node("Treasury/Donation/Donate")
	donate.text="Retry donation" if retry else "Donate gold"
	donate.disabled=not ready or _treasury.is_empty() or (not retry and (amount<=0 or amount>remaining or amount>int(_treasury.get("wallet","0"))))
	for key in ["Requests","Members","Results","Progression/Missions","Perks/Rows"]:
		for row in _body.get_node(key).get_children():
			for child in row.get_children():
				if child is Button:child.disabled=not ready or bool(child.get_meta("unavailable",false))

func _render_progression(data:Dictionary):
	var section:VBoxContainer=_body.get_node("Progression")
	var missions:VBoxContainer=section.get_node("Missions")
	var ranking:VBoxContainer=section.get_node("Ranking")
	UIFactory.clear(missions)
	UIFactory.clear(ranking)
	section.visible=not _guild.is_empty()
	if _guild.is_empty():return
	var xp:=int(_guild.get("xp","0"))
	var per_level:=maxi(1,int(_guild.get("xpPerLevel",1000)))
	var progress:ProgressBar=section.get_node("Progress")
	progress.max_value=per_level
	progress.value=xp%per_level
	section.get_node("XP").text="%d total guild XP | %d / %d XP to next level" % [xp,xp%per_level,per_level]
	missions.add_child(UIFactory.heading("Daily guild missions | resets 00:00 UTC",18))
	var state=data.get("missions")
	if state is Dictionary:
		var day:=str(state.get("day",""))
		var guild_id:=str(_guild.id)
		for task in state.get("rows",[]):
			var row:=_row(missions,"%s | %d/%d | +%d guild XP | +%d tokens\n%s" % [task.title,int(task.progress),int(task.target),int(task.xp),int(task.get("tokens",0)),task.description])
			var mission_id:=str(task.id)
			_button(row,"Claimed" if task.claimed else "Claim",func():_post("/missions/claim",{"guildId":guild_id,"day":day,"missionId":mission_id}))
			var button:Button=row.get_child(row.get_child_count()-1)
			button.set_meta("unavailable",not bool(task.canClaim))
			button.disabled=not bool(task.canClaim)
	else:missions.add_child(UIFactory.wrapped("Missions unavailable. Refresh to retry."))
	ranking.add_child(UIFactory.heading("Weekly contributions | Monday UTC reset",18))
	var rank:=0
	for member in data.get("contributions",[]):
		rank+=1
		ranking.add_child(UIFactory.wrapped("%d. %s - %d XP" % [rank,member.name,int(member.xp)]))

func _render_treasury(raw:Variant):
	var section:VBoxContainer=_body.get_node("Treasury")
	_treasury=raw if raw is Dictionary else {}
	if not _pending_donation.is_empty() and str(_pending_donation.get("guildId",""))!=str(_guild.get("id","")):_pending_donation.clear()
	section.visible=not _guild.is_empty() and not _treasury.is_empty()
	var history:VBoxContainer=section.get_node("History")
	UIFactory.clear(history)
	if not section.visible:return
	section.get_node("Balance").text="Treasury: %s gold | Your gold: %s" % [str(_treasury.get("gold","0")),str(_treasury.get("wallet","0"))]
	section.get_node("Daily").text="Donated today: %d / %d gold" % [int(_treasury.get("donatedToday",0)),int(_treasury.get("dailyCap",0))]
	history.add_child(UIFactory.heading("Recent treasury transactions",16))
	for entry in _treasury.get("history",[]):
		var amount:=int(str(entry.amount))
		var action:="Donation" if str(entry.get("reason",""))=="guild_donation" else "Hall upgrade"
		history.add_child(UIFactory.wrapped("%s | %s | %s%d gold | %s" % [entry.name,action,"+" if amount>0 else "",amount,str(entry.createdAt).left(10)]))
	if _treasury.get("history",[]).is_empty():history.add_child(UIFactory.wrapped("No treasury transactions yet."))

func _donate():
	if not _operation.is_empty() or _guild.is_empty():return
	if not _pending_donation.is_empty():
		_begin("donate","/treasury/donate",HTTPClient.METHOD_POST,_pending_donation)
		return
	var amounts:OptionButton=_body.get_node("Treasury/Donation/Amount")
	var amount:=amounts.get_selected_id()
	if amount<=0 or amount>int(_treasury.get("wallet","0")) or amount>int(_treasury.get("dailyCap",0))-int(_treasury.get("donatedToday",0)):return
	var guild_id:=str(_guild.id)
	_confirm("Permanently donate %d gold to %s?" % [amount,str(_guild.name)],func():
		if guild_id!=str(_guild.get("id","")):return
		var bytes:=Crypto.new().generate_random_bytes(16)
		bytes[6]=(bytes[6]&15)|64
		bytes[8]=(bytes[8]&63)|128
		var h:=bytes.hex_encode()
		var request_id:="%s-%s-%s-%s-%s" % [h.substr(0,8),h.substr(8,4),h.substr(12,4),h.substr(16,4),h.substr(20,12)]
		_pending_donation={"guildId":guild_id,"amount":amount,"requestId":request_id}
		_begin("donate","/treasury/donate",HTTPClient.METHOD_POST,_pending_donation))


func _render_perks(perks:Array):
	var section:VBoxContainer=_body.get_node("Perks")
	var rows:VBoxContainer=section.get_node("Rows")
	UIFactory.clear(rows)
	section.visible=not _guild.is_empty()
	if not section.visible:return
	for perk in perks:
		var perk_id:=str(perk.id)
		var guild_id:=str(_guild.id)
		var cost:=int(perk.cost)
		var title_text:=str(perk.title)
		var details:="%s | %d member slots\nGuild Lv %d | %d treasury gold" % [title_text,int(perk.capacity),int(perk.level),cost]
		if perk.get("requires")!=null and not bool(perk.owned):details+=" | Previous hall required"
		var row:=_row(rows,details)
		var caption_text:="Owned" if bool(perk.owned) else ("Upgrade" if bool(perk.canPurchase) else "Locked")
		_button(row,caption_text,func():
			_confirm("Spend %d treasury gold on %s? This is permanent." % [cost,title_text],func():
				if guild_id==str(_guild.get("id","")):_post("/perks/purchase",{"guildId":guild_id,"perkId":perk_id})))
		var button:Button=row.get_child(row.get_child_count()-1)
		button.set_meta("unavailable",not bool(perk.canPurchase))
		button.disabled=not bool(perk.canPurchase)


func _render_raid(raw:Variant):
	var section:VBoxContainer=_body.get_node("Raid")
	var previous_week:=str(_raid.get("week",""))
	_raid=raw if raw is Dictionary else {}
	if previous_week!=str(_raid.get("week","")):_raid_result.clear()
	section.visible=not _guild.is_empty() and not _raid.is_empty()
	if not section.visible:
		_raid_attempt.clear()
		_raid_result.clear()
		_raid_notice=""
		_render_raid_battle()
		return
	if str(_raid.get("activeAttemptId",""))!=str(_raid_attempt.get("attemptId","")):
		_raid_attempt.clear()
	var hp:=int(_raid.get("hp",0))
	var maximum:=maxi(1,int(_raid.get("maxHp",1)))
	var health:ProgressBar=section.get_node("Boss/Info/Health")
	health.max_value=maximum
	health.value=hp
	section.get_node("Boss/Info/Stats").text="%d / %d shared HP | %d / %d attempts used today\nYour damage: %d | Weekly reset Monday UTC" % [hp,maximum,int(_raid.attemptsUsed),int(_raid.attemptsPerDay),int(_raid.damage)]
	var reward:Dictionary=_raid.get("rewards",{})
	section.get_node("Reward").text="%d gold + %d crystals | Minimum %d damage\n%s" % [int(reward.get("gold",0)),int(reward.get("crystals",0)),int(_raid.get("minDamage",100)),_raid_notice]
	var rank:VBoxContainer=section.get_node("Ranking")
	UIFactory.clear(rank)
	rank.add_child(UIFactory.heading("Raid contributions this week",16))
	var n:=0
	for member in _raid.get("ranking",[]):
		n+=1
		rank.add_child(UIFactory.wrapped("%d. %s - %d damage" % [n,member.name,int(member.damage)]))
	_render_raid_battle()

func _raid_start():
	if _guild.is_empty() or _body.get_node("Raid/Battle/Stage").playing:return
	_raid_result.clear()
	_begin("raid_start","/raid/start",HTTPClient.METHOD_POST,{"guildId":str(_guild.id)})

func _raid_claim():
	if _guild.is_empty() or _body.get_node("Raid/Battle/Stage").playing or not bool(_raid.get("canClaim",false)):return
	_begin("raid_claim","/raid/claim",HTTPClient.METHOD_POST,{"guildId":str(_guild.id),"week":str(_raid.week)})

func _raid_abandon():
	if _raid_attempt.is_empty() or _body.get_node("Raid/Battle/Stage").playing:return
	var attempt_id:=str(_raid_attempt.attemptId)
	var guild_id:=str(_guild.id)
	_confirm("Retreat? This attempt is spent and no damage will be credited.",func():
		_begin("raid_abandon","/raid/abandon",HTTPClient.METHOD_POST,{"guildId":guild_id,"attemptId":attempt_id}))

func _raid_unit_name(unit:Dictionary)->String:
	var id:=str(unit.get("charId",""))
	if int(unit.get("team",0))==1:return "Crimson Echo"
	var definition:=ContentDB.get_character(id)
	return definition.display_name if definition!=null else id

func _raid_action(kind:String,skill_id:String="",target:String=""):
	if _raid_attempt.is_empty() or _body.get_node("Raid/Battle/Stage").playing:return
	var view:Dictionary=_raid_attempt.get("view",{})
	var action:Dictionary={"kind":kind,"actorUid":str(view.get("actorUid",""))}
	if kind=="skill":
		action["skillId"]=skill_id
		action["targetUids"]=[] if target.is_empty() else [target]
	_begin("raid_action","/raid/action",HTTPClient.METHOD_POST,{"guildId":str(_guild.id),"attemptId":str(_raid_attempt.attemptId),"sequence":int(view.get("sequence",0))+1,"action":action})

func _render_raid_battle():
	var battle:VBoxContainer=_body.get_node("Raid/Battle")
	var units:VBoxContainer=battle.get_node("Units")
	var actions:VBoxContainer=battle.get_node("Actions")
	UIFactory.clear(units)
	UIFactory.clear(actions)
	var finished:=_raid_attempt.is_empty() and not _raid_result.is_empty()
	battle.visible=not _raid_attempt.is_empty() or finished
	battle.get_node("Abandon").visible=not finished
	if not battle.visible:
		battle.get_node("Stage").reset_stage()
		return
	var shown:Dictionary=_raid_result if finished else _raid_attempt
	var view:Dictionary=shown.get("view",{})
	battle.get_node("Stage").show_snapshot(str(shown.attemptId),view)
	var actor:Dictionary={}
	for unit in view.get("units",[]):
		var row:=HBoxContainer.new()
		units.add_child(row)
		var name_label:=UIFactory.wrapped("%s%s" % [_raid_unit_name(unit)," (turn)" if str(unit.uid)==str(view.get("actorUid","")) else ""],15)
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var bar:=ProgressBar.new()
		bar.custom_minimum_size=Vector2(140,20)
		bar.max_value=maxf(1,float(unit.maxHp))
		bar.value=float(unit.hp)
		bar.show_percentage=false
		row.add_child(bar)
		row.add_child(UIFactory.wrapped("%d/%d HP" % [int(unit.hp),int(unit.maxHp)],14))
		if str(unit.uid)==str(view.get("actorUid","")):actor=unit
	if finished or actor.is_empty():
		battle.get_node("Turn").text=_raid_notice if finished else "Battle ended."
		return
	battle.get_node("Turn").text="Round %d | %s | Energy %d" % [int(view.get("round",1)),_raid_unit_name(actor),int(actor.get("energy",0))]
	var skills:Array=actor.get("skills",[]).duplicate()
	var ultimate:=str(actor.get("ultimate",""))
	if not ultimate.is_empty() and not skills.has(ultimate):skills.append(ultimate)
	for skill_id in skills:
		var skill:=ContentDB.get_skill(str(skill_id))
		if skill==null:continue
		var cooldown:=int(actor.get("cooldowns",{}).get(str(skill_id),0))
		var disabled:=cooldown>0 or (str(skill_id)==ultimate and float(actor.get("energy",0))<100)
		var targets:Array=[""]
		if skill.target in ["single_ally","single_enemy"]:
			targets=[]
			for unit in view.get("units",[]):
				if float(unit.hp)>0 and int(unit.team)==(0 if skill.target=="single_ally" else 1):targets.append(str(unit.uid))
		for target in targets:
			var label_text:=skill.display_name
			if not str(target).is_empty():
				for unit in view.get("units",[]):
					if str(unit.uid)==str(target):label_text+=" > "+_raid_unit_name(unit)
			if cooldown>0:label_text+=" (%d turns)" % cooldown
			var button:=UIFactory.button(label_text)
			button.custom_minimum_size.y=44
			actions.add_child(button)
			button.set_meta("unavailable",disabled)
			button.pressed.connect(_raid_action.bind("skill",str(skill_id),str(target)))
	for kind in ["defend","end_turn"]:
		var button:=UIFactory.button(str(kind).replace("_"," ").capitalize())
		button.custom_minimum_size.y=44
		actions.add_child(button)
		button.pressed.connect(_raid_action.bind(kind))
	_raid_controls(_operation.is_empty())

func _raid_controls(ready:bool):
	var section:VBoxContainer=_body.get_node("Raid")
	ready=ready and not section.get_node("Battle/Stage").playing
	var has_active:=_raid.get("activeAttemptId")!=null and not str(_raid.get("activeAttemptId","")).is_empty()
	var start:Button=section.get_node("Buttons/Start")
	start.text="Resume attempt" if has_active or not _raid_attempt.is_empty() else "Fight"
	start.disabled=not ready or _raid.is_empty() or int(_raid.get("hp",0))<=0 or (not has_active and _raid_attempt.is_empty() and int(_raid.get("attemptsUsed",0))>=int(_raid.get("attemptsPerDay",0)))
	var claim:Button=section.get_node("Buttons/Claim")
	claim.text="Claimed" if bool(_raid.get("claimed",false)) else "Claim reward"
	claim.disabled=not ready or not bool(_raid.get("canClaim",false))
	section.get_node("Battle/Abandon").disabled=not ready
	for button in section.get_node("Battle/Actions").get_children():
		if button is Button:button.disabled=not ready or bool(button.get_meta("unavailable",false))


func _render_shop(raw:Variant):
	var section:VBoxContainer=_body.get_node("Shop")
	_shop=raw if raw is Dictionary else {}
	if not _pending_shop.is_empty() and str(_pending_shop.get("guildId",""))!=str(_guild.get("id","")):_pending_shop.clear()
	section.visible=not _guild.is_empty() and not _shop.is_empty()
	var rows:VBoxContainer=section.get_node("Rows")
	UIFactory.clear(rows)
	if not section.visible:return
	section.get_node("Balance").text="Your guild tokens: %s" % str(_shop.get("balance","0"))
	for offer in _shop.get("offers",[]):
		var offer_id:=str(offer.id)
		var title_text:=str(offer.name)
		var cost:=int(offer.cost)
		var quantity:=int(offer.quantity)
		var guild_id:=str(_guild.id)
		var week:=str(_shop.week)
		var details:="%s x%d | %d tokens\nGuild Lv %d | %d/%d weekly purchases" % [title_text,quantity,cost,int(offer.level),int(offer.purchased),int(offer.limit)]
		var row:=_row(rows,details)
		var title_button:="Sold out" if int(offer.purchased)>=int(offer.limit) else ("Buy" if bool(offer.canBuy) else "Locked")
		_button(row,title_button,func():
			_confirm("Spend %d guild tokens on %s x%d?" % [cost,title_text,quantity],func():
				if guild_id!=str(_guild.get("id","")) or week!=str(_shop.get("week","")) or not _pending_shop.is_empty():return
				var bytes:=Crypto.new().generate_random_bytes(16)
				bytes[6]=(bytes[6]&15)|64
				bytes[8]=(bytes[8]&63)|128
				var h:=bytes.hex_encode()
				var request_id:="%s-%s-%s-%s-%s" % [h.substr(0,8),h.substr(8,4),h.substr(12,4),h.substr(16,4),h.substr(20,12)]
				_pending_shop={"guildId":guild_id,"week":week,"offerId":offer_id,"requestId":request_id}
				_retry_shop()))
		var button:Button=row.get_child(row.get_child_count()-1)
		button.set_meta("unavailable",not bool(offer.canBuy))
	_shop_controls(_operation.is_empty())

func _retry_shop():
	if _pending_shop.is_empty():return
	_begin("shop_buy","/shop/buy",HTTPClient.METHOD_POST,_pending_shop)

func _shop_controls(ready:bool):
	var section:VBoxContainer=_body.get_node("Shop")
	var retry:Button=section.get_node("Retry")
	retry.visible=not _pending_shop.is_empty()
	retry.disabled=not ready
	for row in section.get_node("Rows").get_children():
		for button in row.get_children():
			if button is Button:button.disabled=not ready or not _pending_shop.is_empty() or bool(button.get_meta("unavailable",false))


func _clear_competition():
	var section:VBoxContainer=_body.get_node("Competition")
	section.get_node("Period").text=""
	section.get_node("Own").text=""
	UIFactory.clear(section.get_node("Rows"))

func _render_competition(data:Dictionary):
	var section:VBoxContainer=_body.get_node("Competition")
	var rows:VBoxContainer=section.get_node("Rows")
	UIFactory.clear(rows)
	section.get_node("Period").text="Season: %s to %s (exclusive, UTC)\nMission XP + 1 point per 10 raid damage. Top %d contributors count." % [str(data.get("start","")),str(data.get("end","")),int(data.get("memberLimit",30))]
	var own=data.get("own")
	section.get_node("Own").text="Your guild: unranked" if not own is Dictionary or own.get("rank")==null else "Your guild: #%d | %s points | %d contributors" % [int(own.rank),str(own.points),int(own.contributors)]
	for entry in data.get("leaders",[]):
		rows.add_child(UIFactory.wrapped("#%d  %s | %s points\n%d contributors | Guild Lv %d" % [int(entry.rank),str(entry.name),str(entry.points),int(entry.contributors),int(entry.level)]))
	if rows.get_child_count()==0:rows.add_child(UIFactory.wrapped("No guild has scored yet."))
	section.get_node("Open").text="Refresh leaderboard"
	var history:Dictionary=data.get("history",{})
	rows.add_child(UIFactory.heading("Season results and rewards",16))
	rows.add_child(UIFactory.wrapped("Prize seasons begin "+str(history.get("firstRewardSeason","2026-12-21"))+". Top 30 contributors with at least 200 points qualify for podium rewards."))
	for entry in history.get("titles",[]):
		rows.add_child(UIFactory.wrapped("%s | %s | %s" % [entry.title,entry.name,entry.season]))
	for entry in history.get("champions",[]):
		rows.add_child(UIFactory.wrapped("%s | #%d %s | %s points" % [entry.season,int(entry.rank),entry.name,entry.points]))
	for entry in history.get("rewards",[]):
		var season:=str(entry.season)
		var row:=_row(rows,"%s | #%d %s | %d tokens" % [season,int(entry.rank),entry.name,int(entry.tokens)])
		_button(row,"Claimed" if bool(entry.claimed) else "Claim",func():_begin("competition_claim","/competition/claim",HTTPClient.METHOD_POST,{"season":season}))
		var button:Button=row.get_child(row.get_child_count()-1)
		button.set_meta("unavailable",bool(entry.claimed))
		button.disabled=bool(entry.claimed)
