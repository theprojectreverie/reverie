extends Node
## Short-lived root child owns a single threaded resource request. No permanent
## texture cache. ResourceLoader.get is called only after a terminal status.
signal completed(sheet: SpriteFrames)
var _path := ""

func begin(path: String) -> void:
	if not ResourceLoader.exists(path, "SpriteFrames"):
		_finish(null)
		return
	var error := ResourceLoader.load_threaded_request(path,"SpriteFrames",false)
	if error != OK:
		_finish(null)
		return
	_path = path
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func _process(_delta: float) -> void:
	if _path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var sheet: SpriteFrames = null
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED:
		sheet = ResourceLoader.load_threaded_get(_path) as SpriteFrames
	_path = ""
	_finish(sheet)

func _finish(sheet: SpriteFrames) -> void:
	set_process(false)
	completed.emit(sheet)
	queue_free()
