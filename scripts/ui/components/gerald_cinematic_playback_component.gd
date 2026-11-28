class_name GeraldCinematicPlaybackComponent
extends Node
## Owns sequence position and optional timed playback.

signal advance_requested
signal shot_changed(index: int, shot: Dictionary, total: int)
signal progress_changed(progress: float)
signal sequence_completed

var shots: Array[Dictionary] = []
var shot_index := 0
var shot_elapsed := 0.0
var auto_play := false
var active := false
var _advance_pending := false
var _music_track_id := ""
var _cue_end_times: Array[float] = []
var _total_duration := 0.0
var _music_started := false

func configure(authored_shots: Array[Dictionary], music_track_id: String = "") -> void:
	shots = authored_shots
	_music_track_id = music_track_id
	_music_started = false
	_cue_end_times.clear()
	_total_duration = 0.0
	for shot in shots:
		_total_duration += maxf(float(shot.get("duration", 5.0)), 1.0)
		_cue_end_times.append(_total_duration)
	shot_index = 0
	shot_elapsed = 0.0
	_advance_pending = false
	active = not shots.is_empty()
	if active:
		shot_changed.emit(shot_index, current_shot(), shots.size())

func set_auto_play(enabled: bool) -> void:
	auto_play = enabled
	shot_elapsed = 0.0

func current_shot() -> Dictionary:
	if shot_index < 0 or shot_index >= shots.size():
		return {}
	return shots[shot_index]

func request_advance() -> void:
	if not active or _advance_pending:
		return
	_advance_pending = true
	advance_requested.emit()

func move_next() -> void:
	if not active:
		return
	shot_index += 1
	shot_elapsed = 0.0
	_advance_pending = false
	if shot_index >= shots.size():
		active = false
		sequence_completed.emit()
		return
	shot_changed.emit(shot_index, current_shot(), shots.size())

## Start the authored 0.32-second fade before the next musical cue.
func cue_due(position: float) -> bool:
	if not active or shot_index >= _cue_end_times.size():
		return false
	var lead := 0.32
	if _music_track_id.begins_with("ravienna_story_"):
		lead = float(shots[shot_index + 1].get("dissolve", 1.5)) * 0.5 if shot_index + 1 < shots.size() else 2.0
	return position >= _cue_end_times[shot_index] - lead

func _process(delta: float) -> void:
	if not active or not auto_play or _advance_pending:
		return
	if not _music_track_id.is_empty():
		var position := AudioDirector.music_position_for(_music_track_id)
		if position < 0.0:
			if _music_started and _music_track_id.begins_with("ravienna_story_"):
				_music_track_id = ""
			return
		_music_started = true
		progress_changed.emit(clampf(position / maxf(_total_duration, 1.0), 0.0, 1.0))
		if cue_due(position):
			request_advance()
		return
	var duration := maxf(float(current_shot().get("duration", 5.0)), 1.0)
	shot_elapsed += delta
	var progress := (float(shot_index) + clampf(shot_elapsed / duration, 0.0, 1.0)) / float(shots.size())
	progress_changed.emit(progress)
	if shot_elapsed >= duration:
		request_advance()
