class_name TutorialLilithCharacter
extends Node2D
## Character scene adapter: selects Lilith's existing authored sprite sheets.

@onready var visual: ActorVisual = $ActorVisual

func _ready() -> void:
	var definition := ContentDB.get_character("lilith")
	if definition == null:
		push_error("Tutorial Lilith scene could not resolve her character definition.")
		return
	var kind := ActorVisual.Kind.SPIRIT if definition.race == "Spirit" else ActorVisual.Kind.HUMAN
	visual.setup(definition.palette, kind, "lilith", definition.race, definition.element)
	var report := visual.configure_character("lilith")
	if not bool(report.get("registered", false)):
		push_error("Lilith's authored world sprite sheet failed validation.")
	visual.set_body_scale(130.0 / 183.0)
	visual.play(ActorVisual.S_IDLE)

func face_toward(world_position: Vector2) -> void:
	if visual != null:
		visual.set_move_direction(world_position - global_position)
