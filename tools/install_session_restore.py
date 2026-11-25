from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
def edit(rel,fn):
 f=p/rel;t=f.read_text(encoding='utf-8-sig');shutil.copy2(f,str(f)+'.before_session_restore');f.write_text(fn(t),encoding='utf-8')
# Windows DPAPI stores only the refresh token, bound to the current Windows user.
def auth(t):
 t=t.replace('var _signing_out_all := false','var _signing_out_all := false\nvar restoring_session := false\nsignal session_restore_finished\nconst SESSION_FILE := "user://remembered_session.dpapi"')
 t=t.replace(' authentication_changed.connect(GameState.lifecycle_component.switch_player)',' authentication_changed.connect(GameState.lifecycle_component.switch_player)\n call_deferred("_restore_remembered_session")')
 t=t.replace('func _clear_session() -> void:\n','func _clear_session() -> void:\n _forget_remembered_session()\n')
 t=t.replace('  authentication_changed.emit(true,_player.duplicate(true))\n  auth_result.emit("login"', '  _remember_session()\n  authentication_changed.emit(true,_player.duplicate(true))\n  auth_result.emit("login"')
 t=t.replace('  _apply_tokens(payload)\n  auth_result.emit("refresh",true,payload)','  _apply_tokens(payload)\n  if restoring_session:\n   _player = payload.get("player", {}).duplicate(true)\n   if _player.is_empty():\n    _clear_session()\n   else:\n    _remember_session()\n    authentication_changed.emit(true,_player.duplicate(true))\n  else:\n   _remember_session()\n  auth_result.emit("refresh",true,payload)')
 t=t.replace('  _emit_response("refresh",result,response_code,body)\n','  _emit_response("refresh",result,response_code,body)\n if restoring_session:\n  restoring_session = false\n  session_restore_finished.emit()\n')
 t+='''

func _remember_session() -> void:
 if OS.get_name() != "Windows" or _refresh_token.is_empty() or OS.get_environment("REVERIE_E2E_DISABLE_LOCAL_SAVE") == "1":
  return
 var path := ProjectSettings.globalize_path(SESSION_FILE)
 # Token is passed through stdin, not command-line arguments or a plaintext file.
 var command := "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Security; $s=[Console]::ReadLine(); $b=[Text.Encoding]::UTF8.GetBytes($s); $e=[Security.Cryptography.ProtectedData]::Protect($b,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); [IO.File]::WriteAllBytes($args[0],$e)"
 # Godot's execute_with_pipe permits stdin without exposing the credential in process arguments.
 var pipe := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command + " '" + path.replace("'", "''") + "'"])
 if pipe.has("stdio"):
  var stream: FileAccess = pipe["stdio"]
  stream.store_string(_refresh_token + "\\n")
  stream.flush()
  stream.close()

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
'''
 # Fix path expression: use literal path directly in PS script, not args.
 t=t.replace('[IO.File]::WriteAllBytes($args[0],$e)"','[IO.File]::WriteAllBytes(\'" + path.replace("\'", "\'\'") + "\',$e)"').replace('command + " \'" + path.replace("\'", "\'\'") + "\'"','command')
 return t
edit('scripts/online/auth_gateway.gd',auth)
# Return server-verified identity on token refresh.
edit('backend/api/src/routes/auth.ts',lambda t:t.replace('refreshToken:nextToken,tokenType:"Bearer",expiresIn:config.ACCESS_TOKEN_TTL_SECONDS}', 'refreshToken:nextToken,tokenType:"Bearer",expiresIn:config.ACCESS_TOKEN_TTL_SECONDS,player:{id:row.player_id,name:row.player_name}}'))
def startup(t):
 t=t.replace('var loading: LoadingScreen','var loading: LoadingScreen\nvar pending_account_action := ""')
 t=t.replace('func _on_title_action(action: String) -> void:\n','''func _on_title_action(action: String) -> void:
	if not AuthGateway.is_authenticated():
		if AuthGateway.restoring_session:
			return
		pending_account_action = action
		if title.has_node("RequiredAccountOverlay"):
			return
		var overlay := preload("res://scenes/online/account_screen.tscn").instantiate()
		overlay.name = "RequiredAccountOverlay"
		overlay.z_index = 50
		title.add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.closed.connect(overlay.queue_free)
		overlay.account_authenticated.connect(func(_player: Dictionary) -> void:
			overlay.queue_free()
			var next := pending_account_action
			pending_account_action = ""
			_on_title_action.call_deferred(next)
		)
		return
''')
 return t
edit('scripts/game/components/main_startup_flow_component.gd',startup)
def title(t):
 t=t.replace('refresh_save_actions()\n\nfunc refresh_save_actions','AuthGateway.authentication_changed.connect(func(_ok: bool, _player: Dictionary) -> void: refresh_save_actions())\n\tAuthGateway.session_restore_finished.connect(refresh_save_actions)\n\trefresh_save_actions()\n\nfunc refresh_save_actions',1)
 t=t.replace('var has_save := SaveService.has_save()','var has_save := SaveService.has_save() if AuthGateway.is_authenticated() else true')
 return t
edit('scripts/ui/components/title_screen_actions_component.gd',title)
def game(t):
 t=t.replace('func _start_game() -> void:\n','func _start_game() -> void:\n\tif not AuthGateway.is_authenticated():\n\t\tif is_instance_valid(menu):\n\t\t\tmenu._open_profile_account()\n\t\treturn\n')
 return t
edit('scripts/game/components/main_gameplay_flow_component.gd',game)
print('Installed authenticated Continue gate and Windows remembered-session support.')
