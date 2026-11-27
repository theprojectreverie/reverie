extends Control
## A single responsive bottom sheet, separate from the summon presentation.
var opened := false
var _fraction := 0.0
var _animation: Tween
@onready var drawer: Control = $DrawerClip
@onready var panel: PanelContainer = $DrawerClip/Panel
@onready var footer: VBoxContainer = $Footer
@onready var handle: Button = $Footer/DrawerHandle
@onready var actions: BoxContainer = $Footer/Actions
@onready var info: VBoxContainer = $DrawerClip/Panel/Scroll/Info

func _ready() -> void:
	handle.pressed.connect(func(): set_open(not opened))
	resized.connect(_layout)
	footer.minimum_size_changed.connect(_layout)
	_layout.call_deferred()

func set_open(value: bool, animate: bool = true) -> void:
	opened = value
	handle.text = "▼  Close information" if opened else "▲  Banner information"
	if _animation != null: _animation.kill()
	if not animate:
		_set_fraction(1.0 if opened else 0.0)
		return
	if opened: drawer.show()
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.tween_method(_set_fraction, _fraction, 1.0 if opened else 0.0, 0.23)

func _set_fraction(value: float) -> void:
	_fraction = value
	_layout()

func _layout() -> void:
	if not is_node_ready(): return
	var width := maxf(1.0, size.x)
	actions.vertical = width < 660.0
	footer.size.x = minf(width, 1050.0)
	var footer_height := footer.get_combined_minimum_size().y
	footer.size = Vector2(footer.size.x, footer_height)
	footer.position = Vector2((width-footer.size.x)*0.5, maxf(0.0,size.y-footer_height))
	var height := minf(get_viewport_rect().size.y*0.49, maxf(0.0,footer.position.y-6.0))
	var visible_height := height*_fraction
	var drawer_width := minf(width, 1050.0)
	drawer.position = Vector2((width-drawer_width)*0.5,footer.position.y-visible_height-4.0)
	drawer.size = Vector2(drawer_width,visible_height)
	panel.position = Vector2.ZERO
	panel.size = Vector2(drawer_width,height)
	$DrawerClip/Blur.size = Vector2(drawer_width,visible_height)
	drawer.visible = visible_height > 0.5
