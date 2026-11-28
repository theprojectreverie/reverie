extends RefCounted
## One trusted origin for public alpha HTTPS and WSS; no client supplied host.
const PUBLIC_ORIGIN := "https://reverie-staging-fra1.tailad29fa.ts.net:8443"
const LOCAL_ORIGIN := "http://127.0.0.1:8787"
static func is_public_alpha() -> bool:
	return OS.has_feature("reverie_public_alpha")
static func api_origin(public_alpha: bool) -> String:
	return PUBLIC_ORIGIN if public_alpha else LOCAL_ORIGIN
static func realtime_url(public_alpha: bool) -> String:
	return api_origin(public_alpha).replace("https://", "wss://").replace("http://", "ws://") + "/v1/realtime"
static func persistent_world_enabled(public_alpha: bool) -> bool:
	return not public_alpha
static func persistent_world_url(public_alpha: bool) -> String:
	return "" if public_alpha else "ws://127.0.0.1:8787/v1/world/realtime"