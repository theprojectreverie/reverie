extends Control
## Auth UI composition; visual elements remain authored scene nodes.
signal closed
signal account_authenticated(player: Dictionary)
var _appeal_ticket := ""
var _appeal_owner := ""
var _appeal_http: HTTPRequest
var _appeal_inflight := false
var _login_owner := ""
@onready var _appeal_button: Button = $Center/Panel/Margins/Content/Tabs/SignIn/AppealButton
@onready var _appeal_dialog: ConfirmationDialog = $AppealDialog
@onready var _appeal_statement: LineEdit = $AppealDialog/Statement

@onready var email_login: LineEdit = $Center/Panel/Margins/Content/Tabs/SignIn/Email
@onready var password_login: LineEdit = $Center/Panel/Margins/Content/Tabs/SignIn/Password
@onready var login_status: Label = $Center/Panel/Margins/Content/Tabs/SignIn/Status
@onready var player_name: LineEdit = $Center/Panel/Margins/Content/Tabs/CreateAccount/PlayerName
@onready var email_register: LineEdit = $Center/Panel/Margins/Content/Tabs/CreateAccount/Email
@onready var password_register: LineEdit = $Center/Panel/Margins/Content/Tabs/CreateAccount/Password
@onready var verification_token: LineEdit = $Center/Panel/Margins/Content/Tabs/CreateAccount/VerificationToken
@onready var register_status: Label = $Center/Panel/Margins/Content/Tabs/CreateAccount/Status

func show_registration() -> void:
	$Center/Panel/Margins/Content/Tabs.current_tab = 1
	player_name.grab_focus()

func _ready() -> void:
	UIFactory.set_full_rect(self)
	password_register.placeholder_text = "Password (at least %d characters)" % AuthGateway.minimum_registration_password_length()
	if OS.is_debug_build() and AuthGateway.api_base_url.begins_with("http://127.0.0.1:"):
		verification_token.hide()
		$Center/Panel/Margins/Content/Tabs/CreateAccount/VerifyButton.hide()
		register_status.text = "Create your account, then sign in. No email code needed for local testing."
	$Center/Panel/Margins/Content/Header/CloseButton.pressed.connect(closed.emit)
	$Center/Panel/Margins/Content/Tabs/SignIn/LoginButton.pressed.connect(_login)
	$Center/Panel/Margins/Content/Tabs/SignIn/ForgotPassword.pressed.connect(_forgot_password)
	$Center/Panel/Margins/Content/Tabs/CreateAccount/RegisterButton.pressed.connect(_register)
	$Center/Panel/Margins/Content/Tabs/CreateAccount/VerifyButton.pressed.connect(_verify)
	_appeal_http=HTTPRequest.new()
	_appeal_http.timeout=10
	add_child(_appeal_http)
	_appeal_http.request_completed.connect(_appeal_completed)
	_appeal_button.pressed.connect(_open_appeal)
	_appeal_dialog.confirmed.connect(_send_appeal)
	email_login.text_changed.connect(func(_value):_clear_appeal())
	AuthGateway.auth_result.connect(_on_auth_result)
	AuthGateway.authentication_changed.connect(_on_authentication_changed)
	$Center/Panel/Margins/Content/Tabs/SignIn/Email.grab_focus()

func _exit_tree() -> void:
	if AuthGateway.auth_result.is_connected(_on_auth_result):
		AuthGateway.auth_result.disconnect(_on_auth_result)
	if AuthGateway.authentication_changed.is_connected(_on_authentication_changed):
		AuthGateway.authentication_changed.disconnect(_on_authentication_changed)

func _request_error_text(result: Error, action: String) -> String:
	if result == ERR_INVALID_PARAMETER:
		match action:
			"Sign-in":
				return "Enter your username and password."
			"Registration":
				return "Use a valid email, a password of at least %d characters, and a 3-20 character player name using letters, numbers or underscores." % AuthGateway.minimum_registration_password_length()
			"Verification":
				return "Enter the complete email verification token."
	if result == ERR_BUSY:
		return "A " + action.to_lower() + " request is already running."
	return action + " could not be started. Please try again."

func _forgot_password() -> void:
	login_status.text = "Password recovery is not available yet. Email delivery must be configured before secure resets can be issued. Your existing account is unchanged."

func _clear_appeal() -> void:
	_appeal_ticket=""
	_appeal_owner=""
	_appeal_inflight=false
	if _appeal_http!=null:_appeal_http.cancel_request()
	_appeal_button.hide()
	_appeal_button.disabled=false
	_appeal_dialog.hide()
	_appeal_statement.clear()

func _open_appeal() -> void:
	if _appeal_ticket.is_empty() or _appeal_inflight or email_login.text.strip_edges().to_lower()!=_appeal_owner:return
	_appeal_dialog.popup_centered_clamped()

func _send_appeal() -> void:
	if _appeal_ticket.is_empty() or _appeal_inflight or email_login.text.strip_edges().to_lower()!=_appeal_owner:return
	var statement:=_appeal_statement.text.strip_edges()
	if statement.length()<10:
		login_status.text="Explain your appeal in at least 10 characters."
		return
	_appeal_inflight=true
	_appeal_button.disabled=true
	var result:=_appeal_http.request(AuthGateway.api_base_url+"/v1/auth/suspension-appeal",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"ticket":_appeal_ticket,"statement":statement}))
	if result!=OK:
		_appeal_inflight=false
		_appeal_button.disabled=false
		login_status.text="Could not submit the appeal. Try again."
	else:login_status.text="Submitting appeal..."

func _appeal_completed(result: int,code: int,_headers: PackedStringArray,body: PackedByteArray) -> void:
	if not _appeal_inflight or _appeal_owner!=email_login.text.strip_edges().to_lower():return
	_appeal_inflight=false
	_appeal_button.disabled=false
	var data=JSON.parse_string(body.get_string_from_utf8())
	if result==HTTPRequest.RESULT_SUCCESS and code==200 and data is Dictionary:
		var appeal_status:=str(data.get("status","pending"))
		_clear_appeal()
		login_status.text="Appeal: "+appeal_status.capitalize()+". Sign in again later to check the decision."
	elif code in [401,409]:
		_clear_appeal()
		login_status.text="Appeal access expired or the suspension changed. Sign in again."
	else:
		login_status.text="Appeal could not be submitted. Try again."

func _login() -> void:
	_clear_appeal()
	_login_owner=email_login.text.strip_edges().to_lower()
	login_status.text = "Connecting securely…"
	var result: Error = AuthGateway.login(email_login.text,password_login.text)
	if result != OK:
		login_status.text = _request_error_text(result, "Sign-in")

func _register() -> void:
	register_status.text = "Creating your account…"
	var result: Error = AuthGateway.register_account(email_register.text,password_register.text,player_name.text)
	if result != OK:
		register_status.text = _request_error_text(result, "Registration")

func _verify() -> void:
	register_status.text = "Verifying email…"
	var result: Error = AuthGateway.verify_email(verification_token.text)
	if result != OK:
		register_status.text = _request_error_text(result, "Verification")

func _on_auth_result(operation: String,success: bool,payload: Dictionary) -> void:
	var message := str(payload.get("message",payload.get("error","")))
	match operation:
		"register":
			if success:
				register_status.text = message if not message.is_empty() else "Account created."
				if str(payload.get("status", "")) == "verification_required":
					verification_token.show()
					$Center/Panel/Margins/Content/Tabs/CreateAccount/VerifyButton.show()
				if payload.has("developmentVerificationToken"):
					verification_token.text = str(payload["developmentVerificationToken"])
					register_status.text += "\nDevelopment verification token inserted below."
			else:
				register_status.text = message if not message.is_empty() else "Registration failed. Check your details."
		"verify_email":
			register_status.text = "Email verified. You can now sign in." if success else (message if not message.is_empty() else "Verification failed.")
		"login":
			if email_login.text.strip_edges().to_lower()!=_login_owner:return
			_clear_appeal()
			login_status.text = "Welcome to Reverie." if success else (message if not message.is_empty() else "Sign-in failed.")
			if not success and str(payload.get("error",""))=="account_suspended":
				login_status.text="Account suspended until "+str(payload.get("suspendedUntil","")).replace("T"," ").left(19)+" UTC.\nReason: "+str(payload.get("reason",""))
				var review=payload.get("appeal")
				if review is Dictionary:
					login_status.text+="\nAppeal: "+str(review.get("status","pending")).capitalize()
					if review.get("reviewNote")!=null:login_status.text+=". "+str(review.reviewNote)
				else:
					_appeal_ticket=str(payload.get("appealTicket",""))
					_appeal_owner=_login_owner
					_appeal_button.visible=not _appeal_ticket.is_empty()
		"refresh":
			login_status.text = "Session refreshed." if success else "Your session expired. Sign in again."
		"logout":
			login_status.text = "Signed out."

func _on_authentication_changed(authenticated: bool,player: Dictionary) -> void:
	if authenticated:
		account_authenticated.emit(player)
