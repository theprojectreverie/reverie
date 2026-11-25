class_name InteractiveProp
extends Interactable
## Interactive environmental prop: lore objects are inspect-only, while
## explicitly configured gathering nodes grant one-time, save-persistent rewards.
## Every successful interaction emits a local signal; visual art is procedural.
## This keeps exploration rewards isolated from quest and combat state
## untouched. Visual is a ProceduralArt Sprite2D plus a soft highlight ring that
## brightens when the player is near. All art is procedural placeholder.
##
## The exact EventBus signal used is `toast_requested(message: String)` (verified
## in scripts/core/event_bus.gd). If a build ever drops it, interact() still emits
## the local `activated` signal and simply does nothing else gameplay-affecting.

## Local, non-gameplay signal emitted on a successful interact.
signal activated(prop: InteractiveProp)

const HIGHLIGHT_RADIUS := 156.0

var prop_kind: String = "rune_stone"
var variant: int = 0
var display_name: String = "Ancient Stone"
var lore: String = ""
var toast_on_interact: bool = true
var collectible_id: String = ""
var collectible_rewards: Dictionary = {}
var collectible_label: String = ""
var _sprite: Sprite2D
var _authored_visual: CanvasItem
var _highlight_node: Node2D
var _highlight_player: AnimationPlayer
var _highlight: float = 0.0
var _player: Node2D
var _collect_animation: AnimationPlayer


## `p_position` is a world-space position. Called before or after add_child() —
## both are safe.
func setup(p_kind: String, p_position: Vector2, p_name: String, p_lore: String, p_variant: int = 0) -> void:
	prop_kind = p_kind
	variant = p_variant
	display_name = p_name
	lore = p_lore
	prompt = "Examine"
	interaction_radius = 74.0
	position = p_position
	_build_visual()


func configure_collectible(p_id: String, p_rewards: Dictionary, p_label: String = "Collected") -> void:
	collectible_id = p_id
	collectible_rewards = p_rewards.duplicate(true)
	collectible_label = p_label
	prompt = "Gather"


func _ready() -> void:
	super._ready()  # adds this node to the "interactables" group
	if not collectible_id.is_empty() and bool(GameState.quest_domain.flags.get("collectible:" + collectible_id, false)):
		enabled = false
		visible = false
		set_process(false)
		return
	_build_visual()  # refresh scene-authored child references after the prop enters the tree
	set_process(true)


func _build_visual() -> void:
	if _authored_visual == null:
		_authored_visual = get_node_or_null("AuthoredVisual") as CanvasItem
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if _highlight_node == null:
		_highlight_node = get_node_or_null("InteractionHighlight") as Node2D
	if _highlight_player == null and _highlight_node != null:
		_highlight_player = _highlight_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _collect_animation == null:
		_collect_animation = get_node_or_null("AnimationPlayer") as AnimationPlayer
		if _collect_animation != null and not _collect_animation.animation_finished.is_connected(_on_collect_animation_finished):
			_collect_animation.animation_finished.connect(_on_collect_animation_finished)
	if _sprite == null:
		_sprite = Sprite2D.new() # compatibility for bare InteractiveProp.new()
		_sprite.name = "Sprite"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	# Keep interaction and collectible behavior available without inventing
	# placeholder art. A matching authored sprite can be assigned by the scene.
	_sprite.texture = null
	_sprite.visible = false


func _on_collect_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"collect":
		visible = false


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var target := 0.0
	if _player != null and is_instance_valid(_player):
		var d := global_position.distance_to(_player.global_position)
		if d < HIGHLIGHT_RADIUS:
			target = 1.0 - d / HIGHLIGHT_RADIUS
	var previous_highlight := _highlight
	_highlight = move_toward(_highlight, target, delta * 3.0)
	if not is_equal_approx(previous_highlight, _highlight) and _sprite != null:
		var boost := 1.0 + _highlight * 0.35
		_sprite.modulate = Color(boost, boost, boost, 1.0)
	if _authored_visual != null:
		_authored_visual.modulate = Color(1.0 + _highlight * 0.18, 1.0 + _highlight * 0.10, 1.0 - _highlight * 0.08, 1.0)
	if _highlight_node != null:
		var active := _highlight > 0.005
		_highlight_node.visible = active
		_highlight_node.modulate.a = _highlight
		if _highlight_player != null:
			if active and not _highlight_player.is_playing() and _highlight_player.has_animation(&"pulse"):
				_highlight_player.play(&"pulse")
			elif not active and _highlight_player.is_playing():
				_highlight_player.stop()
				_highlight_node.scale = Vector2.ONE


## Lore props remain flavour-only. Configured gathering props grant their
## explicit one-time rewards and persist the claim flag in the existing save.
func interact() -> void:
	if not can_interact():
		return
	activated.emit(self)
	if not collectible_id.is_empty():
		var flag_key := "collectible:" + collectible_id
		if bool(GameState.quest_domain.flags.get(flag_key, false)):
			enabled = false
			visible = false
			set_process(false)
			return
		GameState.quest_domain.flags[flag_key] = true
		GameState.inventory_domain.grant_reward_items(collectible_rewards)
		GameState.queue_save()
		enabled = false
		set_process(false)
		if _collect_animation != null and _collect_animation.has_animation(&"collect"):
			_collect_animation.play(&"collect")
		else:
			visible = false
		var reward_names: Array[String] = []
		for item_id in collectible_rewards.keys():
			var item: Dictionary = ContentDB.get_item(str(item_id))
			reward_names.append("%s ×%d" % [str(item.get("name", item_id)), int(collectible_rewards[item_id])])
		var reward_text := ", ".join(reward_names)
		EventBus.toast_requested.emit("%s — %s" % [collectible_label, reward_text])
		return
	if toast_on_interact:
		var message := display_name
		if not lore.is_empty():
			message = "%s — %s" % [display_name, lore]
		EventBus.toast_requested.emit(message)
