extends RefCounted
## Keeps at most one upcoming cinematic texture in the threaded loader.
var pending_path := ""

func request(path: String) -> void:
	if path.is_empty() or path == pending_path:
		return
	clear()
	if ResourceLoader.exists(path, "Texture2D") and ResourceLoader.load_threaded_request(path, "Texture2D", false) == OK:
		pending_path = path

func take(path: String) -> Texture2D:
	if pending_path == path and not pending_path.is_empty():
		pending_path = ""
		var texture := ResourceLoader.load_threaded_get(path) as Texture2D
		if texture != null:
			return texture
	else:
		clear()
	return load(path) as Texture2D

func clear() -> void:
	if pending_path.is_empty():
		return
	var path := pending_path
	pending_path = ""
	# Consume the request even if the viewer skips or closes the scene.
	ResourceLoader.load_threaded_get(path)