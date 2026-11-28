extends SceneTree

func _initialize() -> void:
	var profile = load("res://scripts/online/connection_profile.gd")
	var expected := "https://reverie-staging-fra1.tailad29fa.ts.net:8443"
	if profile.api_origin(true) != expected or profile.realtime_url(true) != expected.replace("https://", "wss://") + "/v1/realtime":
		push_error("Public builds must target DigitalOcean HTTPS/WSS")
		quit(1)
		return
	if profile.persistent_world_enabled(true) or not profile.persistent_world_url(true).is_empty():
		push_error("Unverified public persistent world must remain gated")
		quit(1)
		return
	if profile.api_origin(false) != "http://127.0.0.1:8787":
		push_error("Isolated developer test profile changed unexpectedly")
		quit(1)
		return
	print("CLOUD PUBLIC PROFILE HTTPS WSS PASS; no public localhost fallback")
	quit(0)