extends Control
## Auth UI composition; visual elements remain authored scene nodes.
signal closed
signal account_authenticated(player: Dictionary)

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

func _login() -> void:
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
			login_status.text = "Welcome to Reverie." if success else (message if not message.is_empty() else "Sign-in failed.")
		"refresh":
			login_status.text = "Session refreshed." if success else "Your session expired. Sign in again."
		"logout":
			login_status.text = "Signed out."

func _on_authentication_changed(authenticated: bool,player: Dictionary) -> void:
	if authenticated:
		account_authenticated.emit(player)
