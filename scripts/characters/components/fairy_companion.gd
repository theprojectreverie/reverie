extends Node2D
## Behaviour only: all art and animation frames are authored in the companion scene.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: Player = get_parent() as Player
const DIRECTIONS = [&"south", &"south", &"east", &"east", &"north", &"north", &"west", &"west"]
func _process(_delta: float) -> void:
    if player == null or player.visual == null or player.visual.animator == null:
        return
    visible = player.avatar_id == "kael"
    if not visible:
        return
    var facing: int = clampi(player.visual.animator.direction, 0, 7)
    var next: StringName = DIRECTIONS[facing]
    if sprite.animation != next:
        sprite.play(next)