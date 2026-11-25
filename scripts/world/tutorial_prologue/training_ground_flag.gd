extends Interactable


func _ready() -> void:
	prompt = "Inspect training flag"
	super._ready()


func interact() -> void:
	EventBus.toast_requested.emit("Practice dummy: J for a light hit, K for a heavy hit.")
