class_name GeraldCinematicPresentationComponent
extends Node
## Displays the authored stills and restrained crossfades. No procedural artwork.

var _prefetch = preload("res://scripts/ui/components/cinematic_texture_prefetch.gd").new()
var _artwork: TextureRect
var _previous_artwork: TextureRect
var _dissolve: Tween
var _caption: Label
var _fade_overlay: ColorRect
var _timeline_progress: ColorRect

func bind(owner: Control) -> bool:
	_artwork = owner.get_node_or_null("Artwork") as TextureRect
	_previous_artwork = owner.get_node_or_null("PreviousArtwork") as TextureRect
	_caption = owner.get_node_or_null("Caption") as Label
	_fade_overlay = owner.get_node_or_null("CinematicFade") as ColorRect
	_timeline_progress = owner.get_node_or_null("TimelineTrack/TimelineProgress") as ColorRect
	if _artwork == null or _caption == null or _fade_overlay == null or _timeline_progress == null:
		push_error("[GeraldPresentation] Authored artwork, caption, fade or timeline node is missing.")
		return false
	owner.resized.connect(_update_artwork_pivot)
	_update_artwork_pivot()
	return true

func show_shot(index: int, shot: Dictionary, total: int) -> void:
	var texture_path := str(shot.get("image", ""))
	var texture: Texture2D = _prefetch.take(texture_path)
	if texture == null:
		push_error("[GeraldPresentation] Could not load image: " + texture_path)
		return
	if _previous_artwork != null:
		if _dissolve != null and _dissolve.is_running():
			_dissolve.kill()
		_previous_artwork.texture = _artwork.texture
		_previous_artwork.visible = _previous_artwork.texture != null
		_previous_artwork.modulate.a = 1.0
	_artwork.texture = texture
	_artwork.modulate.a = 0.0
	_artwork.scale = Vector2.ONE
	_artwork.position = Vector2.ZERO
	_caption.text = ""
	_caption.visible = false
	_timeline_progress.anchor_right = float(index) / float(maxi(total, 1))
	_update_artwork_pivot()
	if _previous_artwork != null:
		var seconds := float(shot.get("dissolve", 1.5)) if _previous_artwork.visible else 1.1
		_dissolve = create_tween()
		_dissolve.tween_property(_artwork, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_dissolve.tween_callback(_release_previous_artwork)
	else:
		var fade := create_tween()
		fade.tween_property(_artwork, "modulate:a", 1.0, 0.45)

func _release_previous_artwork() -> void:
	if _previous_artwork != null:
		_previous_artwork.hide()
		_previous_artwork.texture = null

func update_progress(progress: float) -> void:
	_timeline_progress.anchor_right = clampf(progress, 0.0, 1.0)

func crossfade_out() -> void:
	if _previous_artwork != null:
		return
	var fade := create_tween()
	fade.tween_property(_artwork, "modulate:a", 0.0, 0.32)
	await fade.finished

func finish_to_black(natural_end: bool = false) -> void:
	var fade := create_tween()
	fade.tween_property(_fade_overlay, "color:a", 1.0, 2.0 if _previous_artwork != null and natural_end else 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade.finished

func _update_artwork_pivot() -> void:
	if _artwork != null:
		_artwork.pivot_offset = _artwork.size * 0.5

func prefetch_next(path: String) -> void:
	_prefetch.request(path)

func release_prefetch() -> void:
	_prefetch.clear()

func _exit_tree() -> void:
	release_prefetch()