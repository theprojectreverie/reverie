class_name BridgeSegment
extends Node2D

signal bridge_enabled_changed(enabled: bool)

const AUTHORED_BRIDGE_ART := {
	"stone_bridge": "res://assets/environment/greenward/stone_bridge.svg",
}

@export var bridge_kind: String = "wooden_bridge"
@export var variant: int = 0
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
		bridge_enabled_changed.emit(value)
@export var walkable: bool = true
@export var span_length: float = 96.0

@onready var deck: Sprite2D = $Visual/Deck
@onready var walkable_area: Area2D = $WalkableArea
@onready var walk_shape: CollisionShape2D = $WalkableArea/CollisionShape2D


func _ready() -> void:
	_apply()


func _apply() -> void:
	if deck != null:
		var art_path: String = str(AUTHORED_BRIDGE_ART.get(bridge_kind, ""))
		if art_path.is_empty():
			deck.texture = null
			deck.visible = false
		else:
			var texture := load(art_path) as Texture2D
			deck.texture = texture
			deck.visible = texture != null
			if texture != null:
				deck.centered = false
				deck.offset = Vector2(-float(texture.get_width()) * 0.5, -float(texture.get_height()) + 6.0)
	if walk_shape != null and walk_shape.shape is RectangleShape2D:
		(walk_shape.shape as RectangleShape2D).size = Vector2(span_length, 28.0)
	if walkable_area != null:
		walkable_area.monitoring = false
		walkable_area.monitorable = false
	visible = enabled


func set_enabled(value: bool) -> void:
	enabled = value
