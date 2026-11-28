extends RefCounted
## One trusted origin for public alpha HTTPS and WSS; no client supplied host.
const PUBLIC_ORIGIN := "https://reverie-staging-fra1.tailad29fa.ts.net:8443"
const LOCAL_ORIGIN := "http://127.0.0.1:8787"
## Only editor launches may opt into the cloud profile via user arguments.
## Exported public builds always remain cloud-only; local/headless QA defaults stay local.
static func is_editor_cloud() -> bool:
	if OS.has_feature("reverie_public_alpha") or not OS.has_feature("editor"):
		return false
	var args := OS.get_cmdline_user_args()
	if "--reverie-local" in args or OS.get_environment("REVERIE_LOCAL_DEV") == "1":
		return false
	return "--reverie-cloud" in args
static func is_public_alpha() -> bool:
	return OS.has_feature("reverie_public_alpha") or is_editor_cloud()
static func api_origin(public_alpha: bool) -> String:
	return PUBLIC_ORIGIN if public_alpha else LOCAL_ORIGIN
static func realtime_url(public_alpha: bool) -> String:
	return api_origin(public_alpha).replace("https://", "wss://").replace("http://", "ws://") + "/v1/realtime"
static func persistent_world_enabled(public_alpha: bool) -> bool:
	return not public_alpha
static func persistent_world_url(public_alpha: bool) -> String:
	return "" if public_alpha else "ws://127.0.0.1:8787/v1/world/realtime"