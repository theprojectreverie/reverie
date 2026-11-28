class_name GeraldBossIntro
extends Control
## Authored full-screen memory sequence.

signal finished

@onready var sequence_component: GeraldCinematicSequenceComponent = $Sequence
@onready var presentation_component: GeraldCinematicPresentationComponent = $Presentation
@onready var playback_component: GeraldCinematicPlaybackComponent = $Playback
@onready var input_component: GeraldCinematicInputComponent = $Input

var _transitioning := false
var _done := false
var music_track_id := ""

func _ready() -> void:
	UIFactory.set_full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.build()
	if not presentation_component.bind(self) or not input_component.bind(self):
		finished.emit.call_deferred()
		return
	if not sequence_component.load_sequence():
		finished.emit.call_deferred()
		return
	playback_component.advance_requested.connect(_advance)
	playback_component.shot_changed.connect(_present_shot)
	playback_component.progress_changed.connect(presentation_component.update_progress)
	playback_component.sequence_completed.connect(_finish)
	input_component.advance_requested.connect(playback_component.request_advance)
	input_component.auto_play_changed.connect(playback_component.set_auto_play)
	input_component.skip_requested.connect(_finish)
	playback_component.configure(sequence_component.shots, music_track_id)
	input_component.set_auto_play(true)

func _present_shot(index: int, shot: Dictionary, total: int) -> void:
	presentation_component.show_shot(index, shot, total)
	if index + 1 < playback_component.shots.size():
		presentation_component.prefetch_next(str(playback_component.shots[index + 1].get("image", "")))

func _advance() -> void:
	if _transitioning or _done:
		return
	_transitioning = true
	await presentation_component.crossfade_out()
	if _done:
		return
	playback_component.move_next()
	_transitioning = false

func _finish() -> void:
	if _done:
		return
	_done = true
	await presentation_component.finish_to_black(not playback_component.active)
	presentation_component.release_prefetch()
	finished.emit()
