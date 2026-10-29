extends Node
class_name PlayerAV
## Opt-in webcam + mic scaffolding. Never blocks play if devices are missing.
## Name-check STT is a stub: push-to-talk records locally; typed entry always works.

signal camera_status_changed(active: bool, message: String)
signal mic_status_changed(active: bool, message: String)
signal mic_transcript_ready(text: String)  # stub / future STT
signal recording_changed(is_recording: bool)

const MIC_BUS := "Record"
const EXPECTED_NAME_SOFT_MATCH := true

var camera_opt_in: bool = false
var mic_opt_in: bool = false

var _feed_active: bool = false
var _feed_id: int = -1
var _camera_tex: CameraTexture
var _preview: TextureRect

var _recording: bool = false
var _record_effect: AudioEffectRecord
var _mic_player: AudioStreamPlayer
var _recorded_buffer: AudioStreamWAV
var _expected_name: String = ""


func _ready() -> void:
	_ensure_record_bus()


func set_preview_target(rect: TextureRect) -> void:
	_preview = rect
	if _preview:
		_preview.texture = null
		_preview.visible = camera_opt_in and _feed_active


func set_expected_name(name: String) -> void:
	_expected_name = name.strip_edges()


func set_camera_enabled(enabled: bool) -> void:
	camera_opt_in = enabled
	if enabled:
		_start_camera()
	else:
		_stop_camera()


func set_mic_enabled(enabled: bool) -> void:
	mic_opt_in = enabled
	if not enabled:
		stop_push_to_talk()
		mic_status_changed.emit(false, "Mic off — type the name instead")
	else:
		var ok: bool = _mic_available()
		if ok:
			mic_status_changed.emit(true, "Mic ready — hold Push-to-Talk")
		else:
			mic_status_changed.emit(false, "No mic — keyboard name entry still works")


func camera_available() -> bool:
	if not ClassDB.class_exists("CameraServer"):
		return false
	CameraServer.set_monitoring_feeds(true)
	return CameraServer.get_feed_count() > 0


func _mic_available() -> bool:
	# Soft-check input devices when the API exists; otherwise allow opt-in and fail soft on record.
	if AudioServer.has_method("get_input_device_list"):
		var inputs: PackedStringArray = AudioServer.get_input_device_list()
		return inputs.size() > 0
	return true


func _start_camera() -> void:
	_stop_camera()
	if not ClassDB.class_exists("CameraServer"):
		camera_status_changed.emit(false, "CameraServer unavailable")
		return
	CameraServer.set_monitoring_feeds(true)
	var count := CameraServer.get_feed_count()
	if count <= 0:
		camera_status_changed.emit(false, "No webcam — preview offline")
		if _preview:
			_preview.texture = null
		return
	var feed: CameraFeed = CameraServer.get_feed(0)
	if feed == null:
		camera_status_changed.emit(false, "Webcam feed failed")
		return
	feed.set_active(true)
	_feed_id = feed.get_id()
	_camera_tex = CameraTexture.new()
	_camera_tex.camera_feed_id = _feed_id
	_camera_tex.camera_is_active = true
	_feed_active = true
	if _preview:
		_preview.texture = _camera_tex
		_preview.visible = true
	camera_status_changed.emit(true, "On camera — Floor 2 softphone")


func _stop_camera() -> void:
	if _feed_active and _feed_id >= 0 and ClassDB.class_exists("CameraServer"):
		var feed: CameraFeed = CameraServer.get_feed(_feed_id)
		# get_feed expects index; fall back to iterating.
		for i in CameraServer.get_feed_count():
			var f: CameraFeed = CameraServer.get_feed(i)
			if f and f.get_id() == _feed_id:
				f.set_active(false)
				break
	_feed_active = false
	_feed_id = -1
	_camera_tex = null
	if _preview:
		_preview.texture = null
	camera_status_changed.emit(false, "Camera off")


func _ensure_record_bus() -> void:
	var idx := AudioServer.get_bus_index(MIC_BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MIC_BUS)
		AudioServer.set_bus_send(idx, "Master")
		# Mute so mic doesn't feed speakers during PTT.
		AudioServer.set_bus_mute(idx, true)
	# Attach / reuse record effect
	var effect_count := AudioServer.get_bus_effect_count(idx)
	_record_effect = null
	for i in effect_count:
		var fx: AudioEffect = AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectRecord:
			_record_effect = fx as AudioEffectRecord
			break
	if _record_effect == null:
		_record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(idx, _record_effect)

	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.bus = MIC_BUS
		_mic_player.stream = AudioStreamMicrophone.new()
		add_child(_mic_player)


func start_push_to_talk() -> void:
	if not mic_opt_in or _recording:
		return
	if _record_effect == null:
		_ensure_record_bus()
	_ensure_input_enabled()
	_recording = true
	_recorded_buffer = null
	if not _mic_player.playing:
		_mic_player.play()
	_record_effect.set_recording_active(true)
	recording_changed.emit(true)
	mic_status_changed.emit(true, "Recording… release to submit")


func stop_push_to_talk() -> void:
	if not _recording:
		return
	_recording = false
	if _record_effect:
		_record_effect.set_recording_active(false)
		_recorded_buffer = _record_effect.get_recording()
	if _mic_player and _mic_player.playing:
		_mic_player.stop()
	recording_changed.emit(false)
	_finish_name_from_recording()


func is_recording() -> bool:
	return _recording


func _ensure_input_enabled() -> void:
	# Best-effort: enable mic input if the project setting exists.
	if ProjectSettings.has_setting("audio/driver/enable_input"):
		if not bool(ProjectSettings.get_setting("audio/driver/enable_input")):
			ProjectSettings.set_setting("audio/driver/enable_input", true)


## v1 STT stub: no cloud/Whisper yet. Soft-match is not available from audio —
## emit empty transcript and tell the HUD to keep typed entry.
## Next PR: Whisper.cpp / Web Speech / cloud STT when Phillip adds keys/plugins.
func _finish_name_from_recording() -> void:
	var frames := 0
	if _recorded_buffer:
		frames = _recorded_buffer.get_data().size()
	if frames <= 0:
		mic_status_changed.emit(mic_opt_in, "No audio captured — type the name")
		mic_transcript_ready.emit("")
		return

	# Practical v1: we captured PCM successfully. Without an STT backend we cannot
	# invent the name — surface a clear status and leave the LineEdit as source of truth.
	mic_status_changed.emit(
		true,
		"Heard %d bytes (STT stub) — type name to confirm" % frames
	)
	# Hook for future STT: compare against _expected_name after transcription.
	mic_transcript_ready.emit("")


func shutdown() -> void:
	stop_push_to_talk()
	_stop_camera()
