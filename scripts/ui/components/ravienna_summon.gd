extends Control

signal finished
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var voice: AudioStreamPlayer = $Voice
var _active := false
var _premium := false
var _use_video := false
var _rarity := "common"
var _flip_played := false
var _reveal_played := false

func _ready() -> void:
	resized.connect(_layout_card)
	$Card.resized.connect(_center_pivot)
	_layout_card()
	_center_pivot()
	animation.animation_finished.connect(_on_finished)

func _layout_card() -> void:
	var h := minf(size.y * 0.86, size.x * 1.2)
	var w := h * 0.66
	$Card.set_anchors_preset(Control.PRESET_CENTER)
	$Card.offset_left = -w * 0.5
	$Card.offset_right = w * 0.5
	$Card.offset_top = -h * 0.5
	$Card.offset_bottom = h * 0.5
	var cinematic_scale := minf(size.x / 1364.0, size.y / 768.0)
	$Chamber/Cinematic.scale = Vector2.ONE * cinematic_scale
	$Chamber/Cinematic.position = (size - Vector2(1364, 768) * cinematic_scale) * 0.5
	$Dissolve.position = size * 0.5
	$Dissolve.emission_rect_extents = Vector2(w * 0.44, h * 0.44)
	_center_pivot()

func _center_pivot() -> void:
	$Card.pivot_offset = $Card.size * 0.5
	$Chamber/Portrait.pivot_offset = $Chamber/Portrait.size * 0.5

func configure(rarity: String, face: Texture2D, character_name: String, portrait: Texture2D, background: Texture2D, speech: AudioStream, allow_cinematic: bool = true) -> void:
	_rarity = rarity
	_premium = allow_cinematic and rarity in ["legendary", "mythic"] and face != null and portrait != null
	var back_path := "res://assets/ui/tarot/backs/%s.png" % rarity
	$Card/Back.texture = load(back_path) as Texture2D if ResourceLoader.exists(back_path) else null
	$Card/BackPlaceholder.visible = $Card/Back.texture == null
	$Card/Face.texture = _face_display(face)
	$Chamber/Portrait.texture = portrait
	$Chamber/Portrait.scale = Vector2.ONE
	var hair_material := $Chamber/Portrait.material as ShaderMaterial
	hair_material.set_shader_parameter("motion_strength", 1.0 if portrait != null and portrait.resource_path.ends_with("/ravienna_character.png") else 0.0)
	hair_material.set_shader_parameter("phase", 0.0)
	$Chamber/Background.texture = background
	$Chamber/Name.text = character_name
	voice.stream = speech
	var tint := Color(1.0, 0.78, 0.42, 0.9) if rarity == "legendary" else Color(1.0, 0.08, 0.20, 0.95) if rarity == "mythic" else Color(0.68, 0.34, 1.0, 0.75) if rarity == "epic" else Color(0, 0, 0, 0)
	$Card/Aura.self_modulate = tint
	$Dissolve.color = Color(tint.r, tint.g, tint.b, 0.9)
	$Card/Aura.texture = preload("res://assets/castle_pack_v02/effects/glow_warm.png") if rarity == "legendary" else preload("res://assets/reverie_pack_v01/Corrupted_Environment/Effects/purple_glow_soft.png")
	$Chamber/Fog.modulate = Color(0.19, 0.025, 0.075, 0.88) if rarity == "mythic" else Color(0.15, 0.035, 0.09, 0.65)
	$Chamber/Fog2.modulate = $Chamber/Fog.modulate
	$Card/Aura.visible = rarity in ["epic", "legendary", "mythic"]
	var video: VideoStreamPlayer = $Chamber/Cinematic/Video
	video.stop()
	video.stream = null
	_use_video = _premium and portrait != null and portrait.resource_path.ends_with("/ravienna_character.png")
	if _use_video and ResourceLoader.exists("res://assets/portraits/banners/ravienna_summon_take2.ogv"):
		video.stream = load("res://assets/portraits/banners/ravienna_summon_take2.ogv") as VideoStream
	_use_video = _use_video and video.stream != null
	$Chamber/Cinematic.hide()
	$Chamber/Fog.visible = not _use_video
	$Chamber/Fog2.visible = rarity == "mythic" and not _use_video
	hair_material.set_shader_parameter("motion_strength", 0.0)

func play() -> void:
	_active = true
	_flip_played = false
	_reveal_played = false
	show()
	_center_pivot()
	animation.play("reveal" if _premium else "standard")
	animation.advance(0)

func start_cinematic() -> void:
	if _active and _use_video:
		$Chamber/Cinematic.show()
		$Chamber/Cinematic/Video.play()
		$Chamber/Cinematic/Embers.emitting = true

func _stop_cinematic() -> void:
	$Chamber/Cinematic/Video.stop()
	$Chamber/Cinematic/Video.stream = null
	$Chamber/Cinematic/Embers.emitting = false
	$Chamber/Cinematic.hide()

func cancel() -> void:
	_active = false
	animation.stop()
	voice.stop()
	_stop_card_audio()
	_stop_cinematic()
	$Dissolve.emitting = false
	hide()

func _face_display(face: Texture2D) -> Texture2D:
	if face == null or not face.resource_path.ends_with("ravienna_the_empress.png"):
		return face
	# Non-destructive display crop: remove only the surrounding blank sheet margin.
	var atlas := AtlasTexture.new()
	atlas.atlas = face
	var dimensions := face.get_size()
	atlas.region = Rect2(dimensions * Vector2(0.12, 0.085), dimensions * Vector2(0.765, 0.83))
	return atlas

func _cue(player: AudioStreamPlayer, stream: AudioStream, gain: float, pitch: float = 1.0) -> void:
	if not _active or stream == null:
		return
	player.stop()
	player.stream = stream
	player.volume_db = gain
	player.pitch_scale = pitch
	player.play()

func card_flip() -> void:
	if not _active or _flip_played:
		return
	_flip_played = true
	# Use the short, clearly audible swoosh rather than the very quiet variant.
	_cue($CardFlip, preload("res://assets/audio/sfx/extended/summon_swoosh/summon_swoosh_1.wav"), 4.0)

func card_reveal() -> void:
	if not _active or _reveal_played:
		return
	_reveal_played = true
	match _rarity:
		"common":
			_cue($CardReveal, preload("res://assets/audio/sfx/ui_confirm_select.mp3"), 1.0, 0.94)
		"rare":
			_cue($CardReveal, preload("res://assets/audio/sfx/ui_confirm_select.mp3"), 2.0, 1.14)
		"epic":
			_cue($CardReveal, preload("res://assets/audio/sfx/extended/magic_charge/magic_charge_1.wav"), 0.0, 1.25)
		"legendary":
			_cue($CardReveal, preload("res://assets/audio/sfx/extended/legendary_reveal/legendary_reveal_1.wav"), -2.0)
		"mythic":
			_cue($CardReveal, preload("res://assets/audio/sfx/extended/mythic_reveal/mythic_reveal_1.wav"), -3.0)

func _stop_card_audio() -> void:
	for player: AudioStreamPlayer in [$CardFlip, $CardReveal, $CardDissolve]:
		player.stop()
		player.stream = null

func dissolve() -> void:
	if _active and _premium:
		$Dissolve.restart()
		_cue($CardDissolve, preload("res://assets/audio/sfx/extended/crystal_shatter/crystal_shatter_2.wav"), -5.0)
		$Dissolve.emitting = true


func speak() -> void:
	if _active and voice.stream != null:
		voice.play()

func _on_finished(_animation_name: StringName) -> void:
	if not _active:
		return
	_active = false
	voice.stop()
	_stop_card_audio()
	_stop_cinematic()
	$Dissolve.emitting = false
	hide()
	finished.emit()
