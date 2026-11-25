extends Interactable

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var marker: Node2D = $QuestMarker
var home: Vector2
var elapsed := 0.0
var talking := false

func _ready() -> void:
	super._ready()
	prompt = "Talk to Elathra"
	interaction_radius = 140.0
	home = position
	add_to_group("world_minimap_npcs")
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.quest_updated.connect(_refresh_marker)
	_refresh_marker()

func _refresh_marker(_id: String = "") -> void:
	marker.visible = can_interact() and not talking

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if talking:
		return
	if player != null and global_position.distance_to(player.global_position) < 36.0:
		sprite.play("idle")
		return
	elapsed = fmod(elapsed + delta, 12.0)
	if elapsed < 4.0:
		sprite.play("idle")
	elif elapsed < 6.0:
		position.x = home.x + (elapsed - 4.0) * 12.0
		sprite.play("walk_east")
	elif elapsed < 9.0:
		sprite.play("idle")
	elif elapsed < 11.0:
		position.x = home.x + (11.0 - elapsed) * 12.0
		sprite.play("walk_west")
	else:
		position = home
		sprite.play("idle")

func interact() -> void:
	if not can_interact() or talking:
		return
	talking = true
	_refresh_marker()
	sprite.play("idle")
	EventBus.dialogue_requested.emit("elathra")

func _on_dialogue_finished(id: String) -> void:
	if id == "elathra":
		talking = false
		_refresh_marker()
