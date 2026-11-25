extends Node
## Client transport only. The server owns identity, player data and all rewards.
signal auth_result(operation: String, success: bool, payload: Dictionary)
signal authentication_changed(authenticated: bool, player: Dictionary)
@export var api_base_url := "http://127.0.0.1:8787"
@export_range(5, 60) var request_timeout_seconds := 15
var _access_token := ""
var _refresh_token := ""
var _player: Dictionary = {}
var _access_token_expires_at := 0.0
var _refresh_retry_at := 0.0
var _signing_out_all := false
var restoring_session := false
signal session_restore_finished
const SESSION_FILE := "user://remembered_session.dpapi"
const ACCESS_TOKEN_REFRESH_LEAD_SECONDS := 60.0
const REFRESH_RETRY_SECONDS := 15.0
@onready var register_request: HTTPRequest = $RegisterRequest
@onready var verify_request: HTTPRequest = $VerifyRequest
@onready var login_request: HTTPRequest = $LoginRequest
@onready var refresh_request: HTTPRequest = $RefreshRequest
@onready var logout_request: HTTPRequest = $LogoutRequest
@onready var logout_all_request: HTTPRequest = $LogoutAllRequest

func _ready() -> void:
 for http_request in [register_request,verify_request,login_request,refresh_request,logout_request,logout_all_request]:
  http_request.timeout = request_timeout_seconds
 register_request.request_completed.connect(_on_register_completed)
 verify_request.request_completed.connect(_on_verify_completed)
 login_request.request_completed.connect(_on_login_completed)
 refresh_request.request_completed.connect(_on_refresh_completed)
 logout_request.request_completed.connect(_on_logout_completed)
 logout_all_request.request_completed.connect(_on_logout_all_completed)
 authentication_changed.connect(GameState.lifecycle_component.switch_player)
 call_deferred("_restore_remembered_session")

func _process(_delta: float) -> void:
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
 return 8 if OS.is_debug_build() and api_base_url.begins_with("http://127.0.0.1:") else 12

func register_account(email: String,password: String,player_name: String) -> Error:
 if not _valid_email(email) or password.length() < minimum_registration_password_length() or password.length() > 128 or not _valid_player_name(player_name):
  return ERR_INVALID_PARAMETER
 if register_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 var body := JSON.stringify({"email":email.strip_edges(),"password":password,"playerName":player_name.strip_edges()})
 return register_request.request(api_base_url+"/v1/auth/register",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,body)

func verify_email(token: String) -> Error:
 var clean_token := token.strip_edges()
 if clean_token.length() < 32 or clean_token.length() > 200:
  return ERR_INVALID_PARAMETER
 if verify_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
 return verify_request.request(api_base_url+"/v1/auth/verify-email",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"token":token.strip_edges()}))

func login(player_name: String,password: String) -> Error:
 if not _valid_player_name(player_name) or password.is_empty() or password.length() > 128:
  return ERR_INVALID_PARAMETER
 if login_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
  return ERR_BUSY
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
 var request_error := logout_all_request.request(api_base_url+"/v1/auth/logout-all",headers,HTTPClient.METHOD_POST)
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
  _remember_session()
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
   _player = payload.get("player", {}).duplicate(true)
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
   _clear_session()
  else:
   _refresh_retry_at = Time.get_unix_time_from_system() + REFRESH_RETRY_SECONDS
  _emit_response("refresh",result,response_code,body)
 if restoring_session:
  restoring_session = false
  session_restore_finished.emit()

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


func _remember_session() -> void:
 if OS.get_name() != "Windows" or _refresh_token.is_empty() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
  return
 var path := ProjectSettings.globalize_path(SESSION_FILE)
 if not _write_protected_session(path, _refresh_token):
  push_warning("[Auth] Could not persist encrypted session.")

func _write_protected_session(path: String, token: String) -> bool:
 # Pass the token only through a temporary inherited environment variable.
 var key := "REVERIE_DPAPI_SESSION_INPUT"
 var previous := OS.get_environment(key)
 var existed := OS.has_environment(key)
 OS.set_environment(key, token)
 var command := "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Security; $s=[Environment]::GetEnvironmentVariable('REVERIE_DPAPI_SESSION_INPUT'); if ([string]::IsNullOrEmpty($s)) { throw 'Missing session input' }; $b=[Text.Encoding]::UTF8.GetBytes($s); $e=[Security.Cryptography.ProtectedData]::Protect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); $p='" + path.replace("'", "''") + "'; [IO.File]::WriteAllBytes($p+'.tmp',$e); if ([IO.File]::Exists($p)) { [IO.File]::Replace($p+'.tmp',$p,$null) } else { [IO.File]::Move($p+'.tmp',$p) }"
 var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command])
 if existed:
  OS.set_environment(key, previous)
 else:
  OS.unset_environment(key)
 return code == 0 and FileAccess.file_exists(path)

func _forget_remembered_session() -> void:
 if FileAccess.file_exists(SESSION_FILE) and OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") != "1":
  DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))

func _restore_remembered_session() -> void:
 if OS.get_name() != "Windows" or not FileAccess.file_exists(SESSION_FILE) or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
  session_restore_finished.emit()
  return
 restoring_session = true
 var path := ProjectSettings.globalize_path(SESSION_FILE).replace("'", "''")
 var output: Array = []
 var command := "Add-Type -AssemblyName System.Security; $b=[IO.File]::ReadAllBytes('" + path + "'); [Console]::WriteLine([Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)))"
 var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command], output)
 if code == 0 and not output.is_empty():
  _refresh_token = str(output[0]).strip_edges()
  if refresh_session() == OK:
   return
 restoring_session = false
 session_restore_finished.emit()
