extends Node
## Baked TTS playback for call graphs. Prefer OGG/WAV under audio/calls/<id>/;
## fall back to text-only + optional OS TTS. No runtime API keys.

signal line_started(line_id: String)
signal line_finished(line_id: String)

const AUDIO_ROOT := "res://audio/calls"
const EXT_CANDIDATES := [".ogg", ".wav", ".mp3"]

var _player: AudioStreamPlayer
var _call_id: String = ""
var _os_tts_enabled: bool = true
var _current_line: String = ""
var _tts_utterance_id: int = -1


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_stream_finished)
	# OS TTS end-callback differs by platform; we don't block the loop on it.


func set_call(call_id: String) -> void:
	stop()
	_call_id = call_id


func set_os_tts_enabled(enabled: bool) -> void:
	_os_tts_enabled = enabled


func stop() -> void:
	if _player.playing:
		_player.stop()
	if DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()
	_current_line = ""
	_tts_utterance_id = -1


## Play baked clip for line_id. Always shows text via caller; audio is best-effort.
## Returns true if a baked clip started, false if text-only / OS TTS fallback.
func speak(line_id: String, text: String) -> bool:
	stop()
	_current_line = line_id
	line_started.emit(line_id)

	var stream := _load_clip(line_id)
	if stream != null:
		_player.stream = stream
		_player.play()
		return true

	# No clip — optional OS TTS if the platform exposes voices.
	if _os_tts_enabled and text.strip_edges() != "" and _try_os_tts(text):
		return false

	# Text-only: finish immediately so UI timing stays snappy.
	call_deferred("_emit_finished")
	return false


func has_clip(line_id: String) -> bool:
	return _clip_path(line_id) != ""


func _load_clip(line_id: String) -> AudioStream:
	var path := _clip_path(line_id)
	if path == "":
		return null
	var res: Resource = load(path)
	if res is AudioStream:
		return res as AudioStream
	return null


func _clip_path(line_id: String) -> String:
	if _call_id == "" or line_id == "":
		return ""
	for ext in EXT_CANDIDATES:
		var path := "%s/%s/%s%s" % [AUDIO_ROOT, _call_id, line_id, ext]
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			return path
	return ""


func _try_os_tts(text: String) -> bool:
	if not DisplayServer.has_method("tts_speak"):
		return false
	if not DisplayServer.has_method("tts_get_voices"):
		return false
	var voices: Array = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return false
	# Prefer an English voice when available.
	var voice_id := ""
	for v in voices:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = v
		var lang := str(d.get("language", "")).to_lower()
		if lang.begins_with("en"):
			voice_id = str(d.get("id", ""))
			break
	if voice_id == "" and typeof(voices[0]) == TYPE_DICTIONARY:
		voice_id = str((voices[0] as Dictionary).get("id", ""))
	_tts_utterance_id = int(Time.get_ticks_msec())
	DisplayServer.tts_speak(text, voice_id, 100, 1.0, 1.0, _tts_utterance_id, true)
	# Don't wait on OS TTS for loop timing — HUD uses its own short awaits.
	call_deferred("_emit_finished")
	return true


func _on_stream_finished() -> void:
	_emit_finished()


func _emit_finished() -> void:
	var lid := _current_line
	_current_line = ""
	if lid != "":
		line_finished.emit(lid)
