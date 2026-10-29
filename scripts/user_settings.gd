extends Node
## Persisted player preferences (ConfigFile → user://settings.cfg).

signal settings_changed

const PATH := "user://settings.cfg"
const SECTION := "display"

var second_window_enabled: bool = false
var second_screen_index: int = 0


func _ready() -> void:
	load_from_disk()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		return
	second_window_enabled = bool(cfg.get_value(SECTION, "second_window", false))
	second_screen_index = int(cfg.get_value(SECTION, "second_screen", 0))
	_clamp_screen_index()


func save_to_disk() -> void:
	_clamp_screen_index()
	var cfg := ConfigFile.new()
	# Preserve unrelated sections if the file already exists.
	cfg.load(PATH)
	cfg.set_value(SECTION, "second_window", second_window_enabled)
	cfg.set_value(SECTION, "second_screen", second_screen_index)
	cfg.save(PATH)
	settings_changed.emit()


func set_second_window_enabled(enabled: bool, persist: bool = true) -> void:
	if second_window_enabled == enabled:
		return
	second_window_enabled = enabled
	if persist:
		save_to_disk()
	else:
		settings_changed.emit()


func set_second_screen_index(index: int, persist: bool = true) -> void:
	var clamped := clampi(index, 0, maxi(DisplayServer.get_screen_count() - 1, 0))
	if second_screen_index == clamped:
		return
	second_screen_index = clamped
	if persist:
		save_to_disk()
	else:
		settings_changed.emit()


func screen_count() -> int:
	return DisplayServer.get_screen_count()


func screen_label(index: int) -> String:
	var count := screen_count()
	if count <= 0:
		return "No displays detected"
	if index < 0 or index >= count:
		return "Display ?"
	var size := DisplayServer.screen_get_size(index)
	var primary := " (primary)" if index == DisplayServer.get_primary_screen() else ""
	return "Display %d — %d×%d%s" % [index + 1, size.x, size.y, primary]


func _clamp_screen_index() -> void:
	var count := screen_count()
	if count <= 0:
		second_screen_index = 0
		return
	second_screen_index = clampi(second_screen_index, 0, count - 1)
