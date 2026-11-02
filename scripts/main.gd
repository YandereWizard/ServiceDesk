extends Control
## Boot root: Shift Start → Desk HUD for Demo Day 1.


func _ready() -> void:
	# Root Control must fill the viewport; tscn anchors help, reinforce in code
	# so a bad import / older editor never leaves size (0,0) → blank window.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_show_shift_start()


func _show_shift_start() -> void:
	_clear_children()
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/shift_start.tscn")
	if scene == null:
		_show_boot_error("Could not load shift_start.tscn")
		return
	var screen: Control = scene.instantiate()
	if screen.get_script() == null:
		_show_boot_error("shift_start.gd failed to parse — check Godot version / Output")
		return
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen.shift_started.connect(_on_shift_started)
	add_child(screen)


func _on_shift_started() -> void:
	# Defer: ShiftStart is mid-signal; don't free the emitter this frame.
	call_deferred("_boot_desk")


func _boot_desk() -> void:
	_clear_children()
	# Wait one frame so queue_free'd ShiftStart is gone (avoids empty dual-child frame).
	await get_tree().process_frame
	GameState.reset_shift()
	var scene: PackedScene = load("res://scenes/desk_hud.tscn")
	if scene == null:
		_show_boot_error("Could not load desk_hud.tscn")
		return
	var desk: Control = scene.instantiate()
	# Parse failures leave a bare Control with no methods → empty dark window.
	if desk.get_script() == null or not desk.has_method("start_call"):
		_show_boot_error(
			"desk_hud.gd failed to parse.\nUse Godot 4.3+ (or 4.1+ with this build).\nSee Output for the parse error."
		)
		return
	desk.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	desk.call_finished.connect(_on_call_finished)
	desk.restart_requested.connect(_show_shift_start)
	add_child(desk)
	desk.start_call("res://data/calls/password_purge.json")


func _on_call_finished(_grade: Dictionary) -> void:
	# Demo Day 1: single call. Day 2 wires the full shift queue.
	pass


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


func _show_boot_error(message: String) -> void:
	push_error(message)
	var bg := ColorRect.new()
	bg.color = Color("121820")
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var label := Label.new()
	label.text = "Service Desk boot error\n\n%s" % message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("e0a030"))
	add_child(label)
