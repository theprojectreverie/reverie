extends Node
## Persistent graceful exit, including after the menu scene is replaced.
var quitting := false

func _ready() -> void:
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		request_quit()

func request_quit() -> void:
	if quitting or not is_inside_tree():
		return
	quitting = true
	# Let the current world receive its close notification and capture its checkpoint first.
	_finish_quit.call_deferred()

func _finish_quit() -> void:
	GameState.save_now()
	await AudioDirector.drain_for_shutdown()
	if is_inside_tree():
		get_tree().quit()
