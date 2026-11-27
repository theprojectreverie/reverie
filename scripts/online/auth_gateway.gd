extends Node
## Client transport only. The server owns identity, player data and all rewards.
signal online_wallet_changed
signal account_roster_changed
var account_roster: Dictionary = {}
var _roster_inflight := false
var _roster_pending := false
var _roster_last_success := false
var _roster_generation := 0
var _roster_next_at := 0
signal social_summary_changed(incoming: int)
signal unread_messages_changed(unread: int)
var unread_private_messages := 0
var online_daily_claimable := 0
var online_weekly_claimable := 0
var online_monthly_claimable := 0
var online_achievement_claimable := 0
var _achievement_announced:Dictionary={}
var online_season_claimable:=0
var online_season_challenge_claimable:=0
var _season_announced:Dictionary={}
signal season_rewards_ready(count:int)
signal achievement_rewards_ready(count:int)
var _quest_claim_views: Dictionary = {}

func remember_quest_status(data: Dictionary, weekly: bool, monthly: bool=false) -> Dictionary:
 var id := str(_player.get("id", ""))
 if id.is_empty() or id != str(data.get("playerId", "")):
  return data
 var key := id + (":monthly" if monthly else (":weekly" if weekly else ":daily"))
 var date := str(data.get("date", ""))
 var prior: Dictionary = _quest_claim_views.get(key,{})
 if date.is_empty():
  return data
 if not prior.is_empty() and date < str(prior.date):
  return {} # Never revive an earlier period from a delayed response.
 var claimed: Array = prior.get("claimed",[]).duplicate() if date == str(prior.get("date","")) else []
 for row in data.get("rows",[]):
  if bool(row.get("claimed",false)) and not str(row.id) in claimed:
   claimed.append(str(row.id))
 var output := data.duplicate(true)
 for row in output.get("rows",[]):
  if str(row.id) in claimed:
   row["claimed"] = true
   row["can_claim"] = false
   row["progress"] = int(row.get("target",1))
 _quest_claim_views[key] = {"date":date,"claimed":claimed}
 return output
var incoming_friend_requests := 0
var _social_request: HTTPRequest
var _social_request_player := ""
var _portrait_revision := 0
var _social_portrait_revision := -1
var _social_next_at := 0
var online_wallet: Dictionary = {}
var online_inventory: Dictionary = {}
var online_currencies: Dictionary = {}
var _wallet_request_player := ""
var _wallet_refresh_pending := false
@onready var wallet_request: HTTPRequest = $WalletRequest
signal auth_result(operation: String, success: bool, payload: Dictionary)
signal authentication_changed(authenticated: bool, player: Dictionary)
signal profile_picture_changed(avatar: String)
@export var api_base_url := "http://127.0.0.1:8787"
@export_range(5, 60) var request_timeout_seconds := 15
var _access_token := ""
var _refresh_token := ""
var _player: Dictionary = {}
var _access_token_expires_at := 0.0
var _refresh_retry_at := 0.0
var _signing_out_all := false
var restoring_session := false
var _session_fingerprint := ""
signal session_restore_finished
const SESSION_FILE := "user://remembered_session_v2.dpapi"
const ANDROID_SESSION_FILE := "user://remembered_session_v3.keystore"

func _session_path() -> String:
 return ANDROID_SESSION_FILE if OS.get_name()=="Android" else SESSION_FILE
const ACCESS_TOKEN_REFRESH_LEAD_SECONDS := 60.0
const REFRESH_RETRY_SECONDS := 15.0
@onready var register_request: HTTPRequest = $RegisterRequest
@onready var verify_request: HTTPRequest = $VerifyRequest
@onready var login_request: HTTPRequest = $LoginRequest
@onready var refresh_request: HTTPRequest = $RefreshRequest
@onready var logout_request: HTTPRequest = $LogoutRequest
@onready var logout_all_request: HTTPRequest = $LogoutAllRequest

func _ready() -> void:
 if OS.has_feature("reverie_public_alpha"):
  api_base_url=preload("res://scripts/online/connection_profile.gd").api_origin(true)
 wallet_request.request_completed.connect(_on_wallet_completed)
 authentication_changed.connect(_roster_identity_changed)
 _social_request=HTTPRequest.new()
 _social_request.timeout=8.0
 add_child(_social_request)
 _social_request.request_completed.connect(_on_social_summary_completed)
 authentication_changed.connect(_social_identity_changed)
 authentication_changed.connect(_wallet_identity_changed)
 for http_request in [register_request,verify_request,login_request,refresh_request,logout_request,logout_all_request]:
  http_request.timeout = request_timeout_seconds
 register_request.request_completed.connect(_on_register_completed)
 verify_request.request_completed.connect(_on_verify_completed)
 login_request.request_completed.connect(_on_login_completed)
 refresh_request.request_completed.connect(_on_refresh_completed)
 logout_request.request_completed.connect(_on_logout_completed)
 logout_all_request.request_completed.connect(_on_logout_all_completed)
 authentication_changed.connect(GameState.lifecycle_component.switch_player)
 restoring_session = _session_storage_allowed() and FileAccess.file_exists(_session_path())
 call_deferred("_restore_remembered_session")

func _roster_identity_changed(authenticated: bool, _identity: Dictionary) -> void:
 _roster_generation += 1
 _roster_inflight = false
 _roster_pending = false
 _roster_last_success = false
 account_roster.clear()
 _roster_next_at = 0
 account_roster_changed.emit()
 if authenticated:
  refresh_account_roster.call_deferred()

# Reuse the already authenticated collection response instead of fetching /state twice.
func accept_verified_collection_snapshot(payload: Dictionary) -> void:
 var owner := str(_player.get("id",""))
 if not is_authenticated() or owner.is_empty() or owner != str(payload.get("playerId","")) or not payload.get("roster") is Array or not payload.get("party") is Array:
  return
 _roster_next_at = Time.get_ticks_msec() + 10000
 _roster_snapshot_revision += 1
 var snapshot := {"playerId":owner,"roster":payload.roster,"party":payload.party}
 if snapshot != account_roster:
  account_roster = snapshot.duplicate(true)
  account_roster_changed.emit()

var _roster_snapshot_revision := 0

func refresh_account_roster() -> bool:
 if not access_token_ready_for_connection():
  return false
 if _roster_inflight:
  _roster_pending = true
  var waiting_generation := _roster_generation
  while _roster_inflight and waiting_generation == _roster_generation:
   await get_tree().process_frame
  return waiting_generation == _roster_generation and _roster_last_success
 var owner := str(_player.get("id",""))
 var generation := _roster_generation
 var snapshot_revision := _roster_snapshot_revision
 _roster_inflight = true
 _roster_last_success = false
 _roster_next_at = Time.get_ticks_msec() + 10000
 # An account switch may leave the old HTTP request pending; use a separate
 # request node per generation so old responses cannot hydrate a new account.
 var request := HTTPRequest.new()
 request.timeout = 12.0
 add_child(request)
 var err := request.request(api_base_url+"/v1/summon/state",PackedStringArray(["Authorization: Bearer "+_access_token,"X-Reverie-Character-Content: 1"]))
 if err != OK:
  request.queue_free()
  _roster_inflight = false
  return false
 var result: Array = await request.request_completed
 request.queue_free()
 if generation != _roster_generation:
  return false
 var payload := _parse_body(result[3])
 var valid := int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 200 and owner == str(_player.get("id","")) and owner == str(payload.get("playerId","")) and payload.get("roster") is Array and payload.get("party") is Array
 if valid:
  var missing := false
  for row in payload.roster:
   var id := str(row.get("char_id",""))
   if id.begins_with("livechar_") and ContentDB.get_character(id)==null: missing=true
  if missing:
   await LiveCharacterContent.refresh(true)
   if generation!=_roster_generation: return false
   for row in payload.roster:
    var id := str(row.get("char_id",""))
    if id.begins_with("livechar_") and ContentDB.get_character(id)==null: valid=false
 _roster_inflight = false
 _roster_last_success = valid
 if valid and snapshot_revision == _roster_snapshot_revision:
  LiveCharacterContent.refresh.call_deferred()
  var snapshot := {"playerId":owner,"roster":payload.roster,"party":payload.party}
  if snapshot != account_roster:
   account_roster = snapshot.duplicate(true)
   account_roster_changed.emit()
 if _roster_pending:
  _roster_pending = false
  refresh_account_roster.call_deferred()
 return valid

func _wallet_identity_changed(authenticated: bool, _identity: Dictionary) -> void:
 wallet_request.cancel_request()
 _wallet_request_player = ""
 _wallet_refresh_pending = false
 online_wallet.clear()
 online_inventory.clear()
 online_currencies.clear()
 online_wallet_changed.emit()
 if authenticated:
  refresh_online_wallet()

func refresh_online_wallet() -> void:
 if not is_authenticated() or _player.is_empty():
  return
 if not _wallet_request_player.is_empty():
  _wallet_refresh_pending = true
  return
 _wallet_request_player = str(_player.get("id", ""))
 var error := wallet_request.request(api_base_url + "/v1/auth/wallet", PackedStringArray(["Authorization: Bearer " + _access_token]))
 if error != OK:
  _wallet_request_player = ""

func _on_wallet_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
 var requested := _wallet_request_player
 _wallet_request_player = ""
 var payload := _parse_body(body)
 if result == HTTPRequest.RESULT_SUCCESS and code == 200 and not requested.is_empty() and requested == str(_player.get("id", "")) and requested == str(payload.get("playerId", "")):
  online_wallet = {"gold": int(str(payload.get("gold", "0"))), "xp": int(str(payload.get("xp", "0")))}
  online_currencies.clear()
  for currency_id in payload.get("currencies", {}):
   online_currencies[currency_id] = int(str(payload["currencies"][currency_id]))
  online_inventory.clear()
  for item_id in payload.get("items", {}):
   online_inventory[item_id] = int(str(payload["items"][item_id]))
  online_wallet_changed.emit()
 if _wallet_refresh_pending:
  _wallet_refresh_pending = false
  refresh_online_wallet()
func _social_identity_changed(authenticated: bool, _identity: Dictionary) -> void:
 _social_request.cancel_request()
 _social_request_player=""
 _portrait_revision += 1
 incoming_friend_requests=0
 social_summary_changed.emit(0)
 online_daily_claimable=0
 online_weekly_claimable=0
 online_monthly_claimable=0
 online_achievement_claimable=0
 _achievement_announced.clear()
 online_season_claimable=0
 online_season_challenge_claimable=0
 _season_announced.clear()
 unread_private_messages=0
 unread_messages_changed.emit(0)
 _social_next_at=0
 if authenticated:
  refresh_social_summary()

func refresh_social_summary() -> void:
 if _social_request==null or not _social_request_player.is_empty() or not access_token_ready_for_connection():
  return
 # Spread periodic polls across clients; explicit refreshes still run immediately.
 _social_next_at=Time.get_ticks_msec()+10000+randi_range(-1000,1000)
 _social_request_player=str(_player.get("id",""))
 _social_portrait_revision = _portrait_revision
 if _social_request.request(api_base_url+"/v1/social/summary",PackedStringArray(["Authorization: Bearer "+_access_token]))!=OK:
  _social_request_player=""

func _on_social_summary_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
 var requested:=_social_request_player
 _social_request_player=""
 var payload:=_parse_body(body)
 if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or requested.is_empty() or requested!=str(_player.get("id","")) or requested!=str(payload.get("playerId","")):
  return
 if _social_portrait_revision == _portrait_revision and payload.get("avatar") is String and not str(payload.avatar).is_empty():
  update_profile_picture(requested, str(payload.avatar))
 var count:=clampi(int(payload.get("incoming",0)),0,200)
 if count!=incoming_friend_requests:
  incoming_friend_requests=count
  social_summary_changed.emit(count)
 online_daily_claimable=clampi(int(payload.get("dailyClaimable",0)),0,6)
 online_weekly_claimable=clampi(int(payload.get("weeklyClaimable",0)),0,4)
 online_monthly_claimable=clampi(int(payload.get("monthlyClaimable",0)),0,4)
 online_achievement_claimable=clampi(int(payload.get("achievementClaimable",0)),0,15)
 _announce_achievement_ready(payload.get("achievementReady",[]))
 online_season_claimable=maxi(0,int(payload.get("seasonClaimable",0)))
 online_season_challenge_claimable=clampi(int(payload.get("seasonChallengeClaimable",0)),0,5)
 _announce_season_ready(payload.get("seasonReady",[]))
 var unread:=maxi(0,int(payload.get("unread",0)))
 if unread!=unread_private_messages:
  var increase:=unread-unread_private_messages
  unread_private_messages=unread
  unread_messages_changed.emit(unread)
  if increase>0:
   EventBus.toast_requested.emit("New private message" if increase==1 else "%d new private messages" % increase)

# Deduplicate by permanent achievement ID, never by a fluctuating total.
func _announce_season_ready(ready:Variant) -> void:
 if not ready is Array or not is_authenticated():return
 var count:=0
 for entry in ready:
  if not entry is Dictionary:continue
  var id:=str(entry.get("id",""))
  if id.is_empty() or _season_announced.has(id):continue
  _season_announced[id]=true
  count+=1
 if count==0:return
 season_rewards_ready.emit(count)
 EventBus.toast_requested.emit("Season reward ready! Open Leaderboards to claim." if count==1 else "%d season rewards ready! Open Leaderboards to claim." % count)

func _announce_achievement_ready(ready:Variant) -> void:
 if not ready is Array or not is_authenticated():return
 var newly_ready:PackedStringArray=[]
 for entry in ready:
  if not entry is Dictionary:continue
  var id:=str(entry.get("id",""))
  var title:=str(entry.get("title",""))
  if id.is_empty() or title.is_empty() or _achievement_announced.has(id):continue
  _achievement_announced[id]=true
  newly_ready.append(title)
 if newly_ready.is_empty():return
 achievement_rewards_ready.emit(newly_ready.size())
 EventBus.toast_requested.emit("Achievement complete: "+newly_ready[0]+" ? claim your reward!" if newly_ready.size()==1 else "%d achievements ready to claim!" % newly_ready.size())

func _process(_delta: float) -> void:
 if is_authenticated() and not _roster_inflight and Time.get_ticks_msec() >= _roster_next_at:
  _roster_next_at = Time.get_ticks_msec() + 10000
  refresh_account_roster()
 if is_authenticated() and Time.get_ticks_msec()>=_social_next_at:
  refresh_social_summary()
 if not is_authenticated() and not restoring_session and not _refresh_token.is_empty() and _refresh_retry_at>0.0 and Time.get_unix_time_from_system()>=_refresh_retry_at:
  restoring_session=true
  if refresh_session()!=OK:
   restoring_session=false
   _refresh_retry_at=Time.get_unix_time_from_system()+REFRESH_RETRY_SECONDS
  return
 if _signing_out_all or not is_authenticated() or _refresh_token.is_empty():
  return
 var now := Time.get_unix_time_from_system()
 if now >= _refresh_retry_at and _access_token_expires_at > 0.0 and now >= _access_token_expires_at - ACCESS_TOKEN_REFRESH_LEAD_SECONDS:
  refresh_session()

func seconds_until_access_expiry() -> float:
 if _access_token_expires_at <= 0.0:
  return 0.0
 return maxf(0.0, _access_token_expires_at - Time.get_unix_time_from_system())
func access_token_ready_for_connection() -> bool:
 if not is_authenticated():
  return false
 var now := Time.get_unix_time_from_system()
 if _access_token_expires_at - now > ACCESS_TOKEN_REFRESH_LEAD_SECONDS:
  return true
 if now >= _refresh_retry_at:
  refresh_session()
 return false

func is_authenticated() -> bool:
 return not _access_token.is_empty()

func current_player() -> Dictionary:
 return _player.duplicate(true)

func update_profile_picture(player_id: String, avatar: String) -> void:
 if is_authenticated() and player_id == str(_player.get("id", "")):
  _portrait_revision += 1
  if str(_player.get("avatar", "")) == avatar:return
  _player["avatar"] = avatar
  profile_picture_changed.emit(avatar)

func _valid_email(value: String) -> bool:
 var email := value.strip_edges()
 if email.length() < 6 or email.length() > 254 or email.contains(" "):
  return false
 var at_index := email.find("@")
 return at_index > 0 and at_index == email.rfind("@") and email.find(".", at_index + 2) > at_index + 1

func _valid_player_name(value: String) -> bool:
 var candidate := value.strip_edges()
 if candidate.length() < 3 or candidate.length() > 20:
  return false
 var pattern := RegEx.new()
 pattern.compile("^[A-Za-z0-9_]+$")
 return pattern.search(candidate) != null

func access_token_for_request() -> String:
 return _access_token

func minimum_registration_password_length() -> int:
 return 8 if OS.has_feature("reverie_public_alpha") or (OS.is_debug_build() and api_base_url.begins_with("http://127.0.0.1:")) else 12

func register_account(email: String,password: String,player_name: String,invite_code: String="") -> Error:
 if not _valid_email(email) or password.length() < minimum_registration_password_length() or password.length() > 128 or not _valid_player_name(player_name):
  return ERR_INVALID_PARAMETER
 if register_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 var registration: Dictionary={"email":email.strip_edges(),"password":password,"playerName":player_name.strip_edges()}
 if not invite_code.strip_edges().is_empty():registration["inviteCode"]=invite_code.strip_edges()
 var body := JSON.stringify(registration)
 return register_request.request(api_base_url+"/v1/auth/register",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,body)

func verify_email(token: String) -> Error:
 var clean_token := token.strip_edges()
 if clean_token.length() < 32 or clean_token.length() > 200:
  return ERR_INVALID_PARAMETER
 if verify_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 return verify_request.request(api_base_url+"/v1/auth/verify-email",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"token":token.strip_edges()}))

func login(player_name: String,password: String) -> Error:
 if restoring_session:
  return ERR_BUSY
 if not _valid_player_name(player_name) or password.is_empty() or password.length() > 128:
  return ERR_INVALID_PARAMETER
 # Explicit login supersedes any pending retry of the old saved identity.
 if login_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 _refresh_retry_at=0.0
 return login_request.request(api_base_url+"/v1/auth/login",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"playerName":player_name.strip_edges(),"password":password}))

func refresh_session() -> Error:
 if _signing_out_all:
  return ERR_BUSY
 if _refresh_token.is_empty():
  return ERR_UNAUTHORIZED
 if refresh_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 return refresh_request.request(api_base_url+"/v1/auth/refresh",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"refreshToken":_refresh_token}))

func logout() -> void:
 if not _refresh_token.is_empty() and logout_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
  logout_request.request(api_base_url+"/v1/auth/logout",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"refreshToken":_refresh_token}))
 _clear_session()

func logout_all_sessions() -> Error:
 if not is_authenticated():
  return ERR_UNAUTHORIZED
 if logout_all_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or refresh_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _access_token])
 _signing_out_all = true
 var request_error := logout_all_request.request(api_base_url+"/v1/auth/logout-all",headers,HTTPClient.METHOD_POST,"{}")
 if request_error != OK:
  _signing_out_all = false
 return request_error

func invalidate_session(reason: String = "session_revoked") -> void:
 _clear_session()
 auth_result.emit("session_invalidated",false,{"error":reason})

func _clear_session() -> void:
 _forget_remembered_session()
 _access_token = ""
 _refresh_token = ""
 _access_token_expires_at = 0.0
 _refresh_retry_at = 0.0
 _player.clear()
 authentication_changed.emit(false,{})

func _on_register_completed(result: int,response_code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
 _emit_response("register",result,response_code,body)

func _on_verify_completed(result: int,response_code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
 _emit_response("verify_email",result,response_code,body)

func _on_login_completed(result: int,response_code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
 var payload := _parse_body(body)
 var success := result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and payload.has("accessToken") and payload.has("refreshToken")
 if success:
  _apply_tokens(payload)
  _player = payload.get("player",{}).duplicate(true)
  _remember_session(true)
  authentication_changed.emit(true,_player.duplicate(true))
  auth_result.emit("login",true,payload)
 else:
  _emit_response("login",result,response_code,body)

func _on_refresh_completed(result: int,response_code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
 var payload := _parse_body(body)
 var success := result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and payload.has("accessToken") and payload.has("refreshToken")
 if success:
  _apply_tokens(payload)
  if restoring_session:
   _player = _refreshed_player(payload)
   if _player.is_empty():
    _clear_session()
   else:
    _remember_session()
    authentication_changed.emit(true,_player.duplicate(true))
  else:
   _remember_session()
  auth_result.emit("refresh",true,payload)
 else:
  if response_code == 401:
   print("[Auth] Refresh rejected; checking saved session ownership.")
   if restoring_session and _session_storage_allowed() and FileAccess.file_exists(_session_path()) and FileAccess.get_sha256(_session_path()) != _session_fingerprint:
    _restore_remembered_session.call_deferred()
    return
   _clear_session()
  else:
   print("[Auth] Refresh temporarily unavailable, HTTP ", response_code, ", result ", result)
   _refresh_retry_at = Time.get_unix_time_from_system() + REFRESH_RETRY_SECONDS
  _emit_response("refresh",result,response_code,body)
 if restoring_session:
  restoring_session = false
  session_restore_finished.emit()

func _refreshed_player(payload: Dictionary) -> Dictionary:
 var identity: Variant = payload.get("player", {})
 if identity is Dictionary and not str(identity.get("id", "")).is_empty() and not str(identity.get("name", "")).is_empty():
  return identity.duplicate(true)
 # Older API builds return the fresh server-issued JWT without a player object.
 # Read identity claims from that response only; the server remains responsible
 # for verifying JWT signatures and authorizing all online actions.
 var parts := str(payload.get("accessToken", "")).split(".")
 if parts.size() != 3:
  return {}
 var encoded := parts[1].replace("-", "+").replace("_", "/")
 while encoded.length() % 4 != 0:
  encoded += "="
 var claims: Variant = JSON.parse_string(Marshalls.base64_to_raw(encoded).get_string_from_utf8())
 if claims is not Dictionary:
  return {}
 var id := str(claims.get("playerId", ""))
 var name := str(claims.get("playerName", ""))
 var pattern := RegEx.new()
 pattern.compile("^[0-9a-fA-F-]{36}$")
 if pattern.search(id) == null or not _valid_player_name(name):
  print("[Auth] Successful refresh lacked usable player identity.")
  return {}
 print("[Auth] Restored player identity from legacy refresh response.")
 return {"id":id,"name":name}
func _apply_tokens(payload: Dictionary) -> void:
 _access_token = str(payload.get("accessToken",""))
 _refresh_token = str(payload.get("refreshToken",""))
 var lifetime := float(payload.get("expiresIn", 900.0))
 _access_token_expires_at = Time.get_unix_time_from_system() + maxf(1.0, lifetime)
 _refresh_retry_at = 0.0

func _on_logout_completed(result: int,response_code: int,_headers: PackedStringArray,_body: PackedByteArray) -> void:
 auth_result.emit("logout",result == HTTPRequest.RESULT_SUCCESS and response_code == 204,{})

func _on_logout_all_completed(result: int,response_code: int,_headers: PackedStringArray,_body: PackedByteArray) -> void:
 var success := result == HTTPRequest.RESULT_SUCCESS and response_code == 204
 _signing_out_all = false
 if success:
  _clear_session()
 auth_result.emit("logout_all",success,{})

func _emit_response(operation: String,result: int,response_code: int,body: PackedByteArray) -> void:
 var payload := _parse_body(body)
 var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
 auth_result.emit(operation,success,payload if not payload.is_empty() else {"error":"network_or_server_error","result":result,"http_status":response_code})

func _parse_body(body: PackedByteArray) -> Dictionary:
 if body.is_empty():
  return {}
 var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
 return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _session_storage_allowed() -> bool:
 if OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
  return false
 if OS.get_name()=="Android":
  return Engine.has_singleton("JavaClassWrapper")
 if OS.get_name() != "Windows":
  return false
 if DisplayServer.get_name() == "headless":
  return OS.get_environment("REVERIE_ISOLATED_AUTH_TEST") == "1" and OS.get_user_data_dir().to_lower().contains("reverie_auth_test")
 return true

func _remember_session(explicit_login: bool = false) -> void:
 if not _session_storage_allowed() or _refresh_token.is_empty():
  return
 # A background refresh must not replace another game's more recent login.
 if not explicit_login and FileAccess.file_exists(_session_path()) and FileAccess.get_sha256(_session_path()) != _session_fingerprint:
  print("[Auth] Newer session on disk; not overwriting.")
  return
 var path := ProjectSettings.globalize_path(_session_path())
 if _write_protected_session(path, _refresh_token):
  _session_fingerprint = FileAccess.get_sha256(_session_path())
  print("[Auth] Encrypted session saved.")
 else:
  push_warning("[Auth] Could not persist encrypted session.")

func _write_protected_session(path: String, token: String) -> bool:
 if OS.get_name()=="Android":
  return preload("res://scripts/online/android_session_storage.gd").write_token(path,token)
 # Pass the token only through a temporary inherited environment variable.
 var key := "REVERIE_DPAPI_SESSION_INPUT"
 var previous := OS.get_environment(key)
 var existed := OS.has_environment(key)
 OS.set_environment(key, token)
 var command := "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Security; $s=[Environment]::GetEnvironmentVariable('REVERIE_DPAPI_SESSION_INPUT'); if ([string]::IsNullOrEmpty($s)) { throw 'Missing session input' }; $b=[Text.Encoding]::UTF8.GetBytes($s); $e=[Security.Cryptography.ProtectedData]::Protect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); $p='" + path.replace("'", "''") + "'; [IO.File]::WriteAllBytes($p+'.tmp',$e); if ([IO.File]::Exists($p)) { [IO.File]::Delete($p+'.previous'); [IO.File]::Replace($p+'.tmp',$p,$p+'.previous'); [IO.File]::Delete($p+'.previous') } else { [IO.File]::Move($p+'.tmp',$p) }"
 var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command])
 if existed:
  OS.set_environment(key, previous)
 else:
  OS.unset_environment(key)
 return code == 0 and FileAccess.file_exists(path)

func _forget_remembered_session() -> void:
 if _session_storage_allowed() and FileAccess.file_exists(_session_path()) and not _session_fingerprint.is_empty():
  if FileAccess.get_sha256(_session_path()) == _session_fingerprint:
   DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path()))
   print("[Auth] Own saved session cleared.")
  else:
   print("[Auth] Newer session preserved.")
 _session_fingerprint = ""

func _restore_remembered_session() -> void:
 if not _session_storage_allowed():
  restoring_session = false
  session_restore_finished.emit()
  return
 if not FileAccess.file_exists(_session_path()):
  print("[Auth] No remembered session; sign-in required.")
  restoring_session = false
  session_restore_finished.emit()
  return
 restoring_session = true
 _session_fingerprint = FileAccess.get_sha256(_session_path())
 print("[Auth] Restoring encrypted session.")
 if OS.get_name()=="Android":
  _refresh_token=preload("res://scripts/online/android_session_storage.gd").read_token(ProjectSettings.globalize_path(_session_path()))
  if not _refresh_token.is_empty() and refresh_session()==OK:
   return
  restoring_session=false
  session_restore_finished.emit()
  return
 var path := ProjectSettings.globalize_path(_session_path()).replace("'", "''")
 var output: Array = []
 var command := "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Security; $b=[IO.File]::ReadAllBytes('" + path + "'); [Console]::WriteLine([Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)))"
 var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command], output)
 if code == 0 and not output.is_empty():
  _refresh_token = str(output[0]).strip_edges()
  if refresh_session() == OK:
   return
 print("[Auth] Could not start saved-session refresh.")
 restoring_session = false
 session_restore_finished.emit()
