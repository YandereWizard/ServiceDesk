extends Control
## Northwave Floor 2 helpdesk workstation HUD.
## Loop: RING → NAME CHECK → DIAGNOSE → RESOLVE → GRADE
## Baked AI voice + optional webcam/mic scaffolding (never required).

signal call_finished(grade: Dictionary)
signal restart_requested

enum Phase { RING, NAME_CHECK, DIAGNOSE, RESOLVE, GRADE, DONE }

# Desk palette — muted terminal teal, amber alerts, cool panel chrome
const BG := Color("121820")
const DESK_TOP := Color("1a222c")
const PANEL := Color("1e2834")
const PANEL_EDGE := Color("2a3848")
const ACCENT := Color("3dba9c")
const AMBER := Color("e0a030")
const DANGER := Color("d94c4c")
const TEXT := Color("e6edf2")
const MUTED := Color("8a9ba8")
const TICKET_BG := Color("161e28")
const RING_GLOW := Color("e0a030")

var _call: Dictionary = {}
var _phase: Phase = Phase.RING
var _name_attempts: int = 0
var _diagnose_correct: bool = false
var _resolve_ok: bool = false
var _name_ok: bool = false
var _elapsed: float = 0.0
var _timing: bool = false
var _expected_step: int = 0
var _completed_steps: Array[String] = []
var _declines: int = 0
var _ring_pulse: float = 0.0
var _shake_time: float = 0.0
var _cached_grade: Dictionary = {}

# Systems — typed so Godot 4.1+ can infer method return types (no Variant :=)
var _voice: CallVoice
var _av: PlayerAV

# Chrome
var _stress_bar: ProgressBar
var _stress_label: Label
var _score_label: Label
var _clock_label: Label
var _phase_label: Label
var _agent_label: Label

# Incoming call control (top-right)
var _incoming_panel: PanelContainer
var _incoming_title: Label
var _incoming_sub: Label
var _ring_dot: ColorRect
var _accept_btn: Button
var _decline_btn: Button

# Ticket
var _ticket_id: Label
var _ticket_subject: Label
var _ticket_caller: Label
var _ticket_dept: Label
var _ticket_voice_badge: Label

# Call workspace
var _dialogue: RichTextLabel
var _voice_status: Label
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _ptt_btn: Button
var _choices: VBoxContainer
var _checklist: VBoxContainer
var _grade_panel: PanelContainer
var _next_btn: Button

# AV panel
var _cam_preview: TextureRect
var _cam_status: Label
var _mic_status: Label
var _cam_toggle: CheckButton
var _mic_toggle: CheckButton
var _softphone_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_voice = CallVoice.new()
	_av = PlayerAV.new()
	add_child(_voice)
	add_child(_av)
	_build_ui()
	_av.set_preview_target(_cam_preview)
	_av.camera_status_changed.connect(_on_camera_status)
	_av.mic_status_changed.connect(_on_mic_status)
	_av.mic_transcript_ready.connect(_on_mic_transcript)
	_av.recording_changed.connect(_on_recording_changed)
	_voice.line_started.connect(_on_voice_started)
	_voice.line_finished.connect(_on_voice_finished)
	GameState.stress_changed.connect(_on_stress_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.shift_failed.connect(_on_shift_failed)
	_on_stress_changed(GameState.stress)
	_on_score_changed(GameState.score)


func _exit_tree() -> void:
	if _av:
		_av.shutdown()
	if _voice:
		_voice.stop()


func _process(delta: float) -> void:
	if _timing:
		_elapsed += delta
		_clock_label.text = _format_clock(_elapsed)
	if _phase == Phase.RING:
		_ring_pulse += delta * 4.0
		var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(_ring_pulse))
		if _ring_dot:
			_ring_dot.color = Color(RING_GLOW.r, RING_GLOW.g, RING_GLOW.b, a)
	if _shake_time > 0.0:
		_shake_time -= delta
		position = Vector2(randf_range(-3, 3), randf_range(-2, 2))
		if _shake_time <= 0.0:
			position = Vector2.ZERO


func start_call(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not load call data: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid call JSON: %s" % path)
		return
	_call = parsed
	_voice.set_call(str(_call.get("voice_dir", _call.get("id", ""))))
	_av.set_expected_name(str(_call.get("caller_name", "")))
	_reset_call_state()
	_populate_ticket()
	_enter_ring()


func _reset_call_state() -> void:
	_phase = Phase.RING
	_name_attempts = 0
	_diagnose_correct = false
	_resolve_ok = false
	_name_ok = false
	_elapsed = 0.0
	_timing = false
	_expected_step = 0
	_completed_steps.clear()
	_declines = 0
	_grade_panel.visible = false
	_name_row.visible = false
	_choices.visible = false
	_checklist.visible = false
	_next_btn.visible = false
	_clock_label.text = "00:00"
	_name_edit.text = ""
	_name_edit.editable = true
	_set_incoming_ringing(true)
	_voice_status.text = ""


func _populate_ticket() -> void:
	_ticket_id.text = str(_call.get("ticket_id", "NW-????"))
	_ticket_subject.text = str(_call.get("subject", ""))
	_ticket_caller.text = "Caller: %s" % str(_call.get("caller_name", "Unknown"))
	_ticket_dept.text = "%s · %s" % [
		str(_call.get("department", "—")),
		str(_call.get("title", "Call")),
	]
	var voice_kind := str(_call.get("voice", "LIVE"))
	_ticket_voice_badge.text = "VO: %s" % voice_kind
	_ticket_voice_badge.add_theme_color_override(
		"font_color", ACCENT if voice_kind == "AI" else MUTED
	)
	_softphone_label.text = "Softphone · %s" % str(_call.get("ticket_id", "—"))


# --- Phases -----------------------------------------------------------------

func _enter_ring() -> void:
	_phase = Phase.RING
	_phase_label.text = "INCOMING"
	_phase_label.add_theme_color_override("font_color", AMBER)
	_set_incoming_ringing(true)
	var ring: Dictionary = _call.get("ring", {})
	_set_dialogue(
		"[color=#e0a030]%s[/color]\n\n[i]%s[/i]" % [
			str(ring.get("caption", "*ring*")),
			str(ring.get("intro", "…")),
		]
	)
	# Intro audio plays when accepted (pickup), not while ringing.


func _set_incoming_ringing(ringing: bool) -> void:
	_incoming_title.text = "INCOMING CALL" if ringing else "ON CALL"
	_incoming_sub.text = str(_call.get("caller_name", "Unknown")) if not _call.is_empty() else "—"
	_accept_btn.visible = ringing
	_decline_btn.visible = ringing
	_ring_dot.visible = ringing
	if ringing:
		_accept_btn.text = "Accept"
		_decline_btn.text = "Decline"
		_accept_btn.grab_focus()
	else:
		_incoming_sub.text = "%s · live" % str(_call.get("caller_name", "Caller"))


func _on_accept_pressed() -> void:
	match _phase:
		Phase.RING:
			_set_incoming_ringing(false)
			_timing = true
			var ring: Dictionary = _call.get("ring", {})
			_speak_line(str(ring.get("line_id", "ring_intro")), str(ring.get("intro", "")))
			_enter_name_check()
		Phase.GRADE, Phase.DONE:
			pass


func _on_decline_pressed() -> void:
	if _phase != Phase.RING:
		return
	_declines += 1
	GameState.add_stress(8.0)
	_pulse_stress()
	_set_dialogue(
		"[color=#d94c4c]Call declined. Floor queue will retry.\n(Decline #%d — stress rising.)[/color]"
		% _declines
	)
	_set_incoming_ringing(false)
	_accept_btn.visible = false
	_decline_btn.visible = false
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	if _declines >= 2:
		GameState.add_stress(10.0)
		_set_dialogue(
			"[color=#e0a030]Queue override — call forced to your headset.\nQA noted the declines.[/color]"
		)
		await get_tree().create_timer(0.9).timeout
		if not is_inside_tree():
			return
		_on_accept_pressed()
	else:
		_enter_ring()


func _enter_name_check() -> void:
	_phase = Phase.NAME_CHECK
	_phase_label.text = "NAME CHECK"
	_phase_label.add_theme_color_override("font_color", ACCENT)
	var nc: Dictionary = _call.get("name_check", {})
	_set_dialogue(str(nc.get("hint", "Type the caller name.")))
	_name_row.visible = true
	_ptt_btn.visible = _mic_toggle.button_pressed
	_name_edit.grab_focus()


func _on_name_submit() -> void:
	if _phase != Phase.NAME_CHECK:
		return
	var nc: Dictionary = _call.get("name_check", {})
	var expected := str(_call.get("caller_name", "")).strip_edges().to_lower()
	var typed := _name_edit.text.strip_edges().to_lower()
	if typed == expected and expected != "":
		_name_ok = true
		GameState.relieve_stress(5.0)
		_name_row.visible = false
		var reply := str(nc.get("correct_reply", "Got it."))
		_speak_line(str(nc.get("correct_line_id", "name_correct")), reply)
		_set_dialogue("[color=#3dba9c]%s[/color]" % reply)
		await get_tree().create_timer(1.1).timeout
		if not is_inside_tree():
			return
		_enter_diagnose()
	else:
		_name_attempts += 1
		GameState.add_stress(float(nc.get("stress_wrong", 12.0)))
		_pulse_stress()
		var wrong := str(nc.get("wrong_reply", "Wrong name."))
		_speak_line(str(nc.get("wrong_line_id", "name_wrong")), wrong)
		_set_dialogue("[color=#d94c4c]%s[/color]" % wrong)
		_name_edit.text = ""
		_name_edit.grab_focus()
		var max_attempts := int(nc.get("max_attempts", 2))
		if _name_attempts >= max_attempts:
			_name_row.visible = false
			_set_dialogue(
				"[color=#d94c4c]Escalation flag: name mismatch ×%d.\n[/color]Pulling ticket face-value and continuing — QA will notice."
				% _name_attempts
			)
			await get_tree().create_timer(1.4).timeout
			if not is_inside_tree():
				return
			_enter_diagnose()


func _enter_diagnose() -> void:
	_phase = Phase.DIAGNOSE
	_phase_label.text = "DIAGNOSE"
	_phase_label.add_theme_color_override("font_color", ACCENT)
	var diag: Dictionary = _call.get("diagnose", {})
	_set_dialogue(str(diag.get("prompt", "What's going on?")))
	_clear_container(_choices)
	_choices.visible = true
	for choice: Variant in diag.get("choices", []):
		if typeof(choice) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = choice
		var btn := Button.new()
		btn.text = str(c.get("text", "…"))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 48)
		_style_choice_button(btn)
		var captured: Dictionary = c
		btn.pressed.connect(func() -> void: _on_diagnose_choice(captured))
		_choices.add_child(btn)


func _on_diagnose_choice(choice: Dictionary) -> void:
	_choices.visible = false
	_diagnose_correct = bool(choice.get("correct", false))
	var stress_hit := float(choice.get("stress", 0.0))
	if stress_hit > 0.0:
		GameState.add_stress(stress_hit)
		_pulse_stress()
	var reply := str(choice.get("reply", "…"))
	var line_id := str(choice.get("line_id", "diagnose_%s" % str(choice.get("id", "x"))))
	_speak_line(line_id, reply)
	var tint := ACCENT if _diagnose_correct else DANGER
	_set_dialogue("[color=#%s]%s[/color]" % [tint.to_html(false), reply])
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	_enter_resolve()


func _enter_resolve() -> void:
	_phase = Phase.RESOLVE
	_phase_label.text = "RESOLVE"
	_phase_label.add_theme_color_override("font_color", ACCENT)
	var res: Dictionary = _call.get("resolve", {})
	_set_dialogue(str(res.get("prompt", "Fix it.")))
	_clear_container(_checklist)
	_checklist.visible = true
	_expected_step = 0
	_completed_steps.clear()
	var steps: Array = res.get("steps", [])
	for i in steps.size():
		var step: Variant = steps[i]
		if typeof(step) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = step
		var step_label := str(s.get("text", "Step"))
		var btn := Button.new()
		btn.text = "☐  %s" % step_label
		btn.set_meta("step_label", step_label)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 40)
		_style_choice_button(btn)
		var idx := i
		var sid := str(s.get("id", str(i)))
		btn.pressed.connect(func() -> void: _on_resolve_step(idx, sid, btn))
		_checklist.add_child(btn)


func _on_resolve_step(index: int, step_id: String, btn: Button) -> void:
	if _phase != Phase.RESOLVE:
		return
	if step_id in _completed_steps:
		return
	var res: Dictionary = _call.get("resolve", {})
	if index != _expected_step:
		GameState.add_stress(float(res.get("wrong_order_stress", 8.0)))
		_pulse_stress()
		_set_dialogue(
			"[color=#d94c4c]Out of order — QA wants the checklist sequential.\nTry the next required step.[/color]"
		)
		return
	_completed_steps.append(step_id)
	_expected_step += 1
	btn.text = "☑  %s" % str(btn.get_meta("step_label", "Done"))
	btn.disabled = true
	var steps: Array = res.get("steps", [])
	if _completed_steps.size() >= steps.size():
		_resolve_ok = true
		GameState.relieve_stress(8.0)
		_checklist.visible = false
		var reply := str(res.get("success_reply", "Done."))
		_speak_line(str(res.get("success_line_id", "resolve_success")), reply)
		_set_dialogue("[color=#3dba9c]%s[/color]" % reply)
		await get_tree().create_timer(1.1).timeout
		if not is_inside_tree():
			return
		_enter_grade()


func _enter_grade() -> void:
	_phase = Phase.GRADE
	_timing = false
	_voice.stop()
	_phase_label.text = "GRADE"
	_phase_label.add_theme_color_override("font_color", AMBER)
	_incoming_title.text = "CALL CLOSED"
	_incoming_sub.text = "Awaiting ticket review"
	var grade := _compute_grade()
	GameState.record_grade(grade)
	_show_grade_card(grade)
	_set_dialogue(str(grade.get("roast", "")))
	_next_btn.text = "  Next — End Demo Shift  "
	_next_btn.visible = true


func _on_next_pressed() -> void:
	match _phase:
		Phase.GRADE, Phase.DONE:
			call_finished.emit(_last_grade())
			restart_requested.emit()


func _compute_grade() -> Dictionary:
	var name_pct := 100.0 if _name_ok and _name_attempts == 0 else (70.0 if _name_ok else 0.0)
	if _name_ok and _name_attempts == 1:
		name_pct = 85.0
	var diag_pct := 100.0 if _diagnose_correct else 25.0
	var res_pct := 100.0 if _resolve_ok else 40.0
	var target := float(_call.get("target_seconds", 90))
	var speed_pct := 100.0
	if _elapsed > target:
		speed_pct = clampf(100.0 - ((_elapsed - target) / target) * 60.0, 20.0, 100.0)
	var total := name_pct * 0.15 + diag_pct * 0.35 + res_pct * 0.35 + speed_pct * 0.15
	var letter := GameState.letter_for_percent(total)
	var roasts: Dictionary = _call.get("grade_roast", {})
	var points := int(round(total))
	return {
		"call_id": str(_call.get("id", "")),
		"title": str(_call.get("title", "")),
		"percent": total,
		"letter": letter,
		"points": points,
		"breakdown": {
			"name": name_pct,
			"diagnose": diag_pct,
			"resolve": res_pct,
			"speed": speed_pct,
		},
		"elapsed": _elapsed,
		"roast": str(roasts.get(letter, "Lead: Noted.")),
	}


func _last_grade() -> Dictionary:
	return _cached_grade


func _show_grade_card(grade: Dictionary) -> void:
	_cached_grade = grade
	_grade_panel.visible = true
	var body: VBoxContainer = _grade_panel.get_node("Margin/VBox")
	_clear_container(body)

	var title := Label.new()
	title.text = "Ticket Review — %s" % str(grade.get("title", ""))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT)
	body.add_child(title)

	var letter := Label.new()
	letter.text = "%s  ·  %d pts" % [str(grade.get("letter", "?")), int(grade.get("points", 0))]
	letter.add_theme_font_size_override("font_size", 40)
	letter.add_theme_color_override("font_color", AMBER)
	body.add_child(letter)

	var bd: Dictionary = grade.get("breakdown", {})
	var lines := Label.new()
	lines.text = "Name %d%% · Diagnose %d%% · Resolve %d%% · Speed %d%%\nTime %s (target %ss)" % [
		int(bd.get("name", 0)),
		int(bd.get("diagnose", 0)),
		int(bd.get("resolve", 0)),
		int(bd.get("speed", 0)),
		_format_clock(float(grade.get("elapsed", 0.0))),
		str(_call.get("target_seconds", 90)),
	]
	lines.add_theme_font_size_override("font_size", 13)
	lines.add_theme_color_override("font_color", MUTED)
	body.add_child(lines)


# --- Voice / AV helpers -----------------------------------------------------

func _speak_line(line_id: String, text: String) -> void:
	if line_id == "" or text == "":
		return
	# Explicit bool: 4.1 rejects := when the callee type was only Node (Variant return).
	var baked: bool = _voice.speak(line_id, text)
	if baked:
		_voice_status.text = "♪ Playing baked line · %s" % line_id
	elif _voice.has_clip(line_id):
		_voice_status.text = "♪ %s" % line_id
	else:
		_voice_status.text = "Text-only (no clip: %s.ogg) · OS TTS if available" % line_id


func _on_voice_started(line_id: String) -> void:
	_voice_status.text = "♪ %s" % line_id


func _on_voice_finished(_line_id: String) -> void:
	if _voice_status:
		_voice_status.text = ""


func _on_camera_status(active: bool, message: String) -> void:
	_cam_status.text = message
	if _cam_preview:
		_cam_preview.modulate = Color.WHITE if active else Color(0.5, 0.55, 0.6, 1)
		if _cam_preview.has_meta("placeholder"):
			var ph: Label = _cam_preview.get_meta("placeholder")
			if ph:
				ph.visible = not active


func _on_mic_status(_active: bool, message: String) -> void:
	_mic_status.text = message


func _on_mic_transcript(text: String) -> void:
	# Future STT fills the name field; v1 stub emits "".
	if text.strip_edges() != "" and _phase == Phase.NAME_CHECK:
		_name_edit.text = text.strip_edges()


func _on_recording_changed(is_recording: bool) -> void:
	if _ptt_btn:
		_ptt_btn.text = "Recording…" if is_recording else "Push-to-Talk"


func _on_cam_toggled(pressed: bool) -> void:
	_av.set_camera_enabled(pressed)


func _on_mic_toggled(pressed: bool) -> void:
	_av.set_mic_enabled(pressed)
	if _ptt_btn:
		_ptt_btn.visible = pressed and _phase == Phase.NAME_CHECK and _name_row.visible


func _on_ptt_down() -> void:
	_av.start_push_to_talk()


func _on_ptt_up() -> void:
	_av.stop_push_to_talk()


# --- UI build ---------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Subtle desk wash
	var wash := ColorRect.new()
	wash.color = Color(0.12, 0.18, 0.22, 0.55)
	wash.set_anchors_preset(PRESET_TOP_WIDE)
	wash.offset_bottom = 72.0
	add_child(wash)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 10
	root.offset_right = -16
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_build_top_bar())
	root.add_child(_build_workspace())


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.custom_minimum_size = Vector2(0, 56)

	var brand_box := VBoxContainer.new()
	brand_box.add_theme_constant_override("separation", 0)
	var brand := Label.new()
	brand.text = "NORTHWAVE DESK"
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", ACCENT)
	brand_box.add_child(brand)
	_agent_label = Label.new()
	_agent_label.text = "Floor 2 · Softphone · Agent Station"
	_agent_label.add_theme_font_size_override("font_size", 11)
	_agent_label.add_theme_color_override("font_color", MUTED)
	brand_box.add_child(_agent_label)
	bar.add_child(brand_box)

	var mid := HBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 16)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER

	_phase_label = Label.new()
	_phase_label.text = "IDLE"
	_phase_label.add_theme_font_size_override("font_size", 13)
	_phase_label.add_theme_color_override("font_color", MUTED)
	mid.add_child(_phase_label)

	_clock_label = Label.new()
	_clock_label.text = "00:00"
	_clock_label.add_theme_font_size_override("font_size", 16)
	_clock_label.add_theme_color_override("font_color", TEXT)
	mid.add_child(_clock_label)

	_score_label = Label.new()
	_score_label.text = "Score 0"
	_score_label.add_theme_font_size_override("font_size", 15)
	_score_label.add_theme_color_override("font_color", TEXT)
	mid.add_child(_score_label)

	var stress_box := VBoxContainer.new()
	stress_box.custom_minimum_size = Vector2(160, 0)
	_stress_label = Label.new()
	_stress_label.text = "Stress 20"
	_stress_label.add_theme_font_size_override("font_size", 11)
	_stress_label.add_theme_color_override("font_color", MUTED)
	stress_box.add_child(_stress_label)
	_stress_bar = ProgressBar.new()
	_stress_bar.min_value = 0
	_stress_bar.max_value = 100
	_stress_bar.value = 20
	_stress_bar.show_percentage = false
	_stress_bar.custom_minimum_size = Vector2(160, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.set_corner_radius_all(2)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = PANEL_EDGE
	bg_sb.set_corner_radius_all(2)
	_stress_bar.add_theme_stylebox_override("fill", fill)
	_stress_bar.add_theme_stylebox_override("background", bg_sb)
	stress_box.add_child(_stress_bar)
	mid.add_child(stress_box)
	bar.add_child(mid)

	bar.add_child(_build_incoming_control())
	return bar


func _build_incoming_control() -> Control:
	_incoming_panel = _panel_container()
	_incoming_panel.custom_minimum_size = Vector2(220, 52)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_incoming_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_ring_dot = ColorRect.new()
	_ring_dot.custom_minimum_size = Vector2(10, 10)
	_ring_dot.color = RING_GLOW
	_ring_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ring_dot)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	_incoming_title = Label.new()
	_incoming_title.text = "INCOMING CALL"
	_incoming_title.add_theme_font_size_override("font_size", 11)
	_incoming_title.add_theme_color_override("font_color", AMBER)
	text_col.add_child(_incoming_title)
	_incoming_sub = Label.new()
	_incoming_sub.text = "—"
	_incoming_sub.add_theme_font_size_override("font_size", 12)
	_incoming_sub.add_theme_color_override("font_color", TEXT)
	text_col.add_child(_incoming_sub)
	row.add_child(text_col)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 4)
	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.custom_minimum_size = Vector2(72, 22)
	_style_primary_button(_accept_btn)
	_accept_btn.add_theme_font_size_override("font_size", 12)
	_accept_btn.pressed.connect(_on_accept_pressed)
	btns.add_child(_accept_btn)
	_decline_btn = Button.new()
	_decline_btn.text = "Decline"
	_decline_btn.custom_minimum_size = Vector2(72, 22)
	_style_ghost_button(_decline_btn)
	_decline_btn.pressed.connect(_on_decline_pressed)
	btns.add_child(_decline_btn)
	row.add_child(btns)

	return _incoming_panel


func _build_workspace() -> Control:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)

	split.add_child(_build_ticket_panel())
	split.add_child(_build_call_panel())
	split.add_child(_build_av_panel())
	return split


func _build_ticket_panel() -> Control:
	var panel := _panel_container()
	panel.custom_minimum_size = Vector2(280, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var header_row := HBoxContainer.new()
	var header := Label.new()
	header.text = "ACTIVE TICKET"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", MUTED)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	_ticket_voice_badge = Label.new()
	_ticket_voice_badge.text = "VO: —"
	_ticket_voice_badge.add_theme_font_size_override("font_size", 11)
	_ticket_voice_badge.add_theme_color_override("font_color", MUTED)
	header_row.add_child(_ticket_voice_badge)
	v.add_child(header_row)

	_ticket_id = Label.new()
	_ticket_id.text = "NW-——"
	_ticket_id.add_theme_font_size_override("font_size", 24)
	_ticket_id.add_theme_color_override("font_color", ACCENT)
	v.add_child(_ticket_id)

	_ticket_dept = Label.new()
	_ticket_dept.text = ""
	_ticket_dept.add_theme_font_size_override("font_size", 12)
	_ticket_dept.add_theme_color_override("font_color", MUTED)
	v.add_child(_ticket_dept)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = PANEL_EDGE
	v.add_child(rule)

	var field_lbl := Label.new()
	field_lbl.text = "REQUESTOR"
	field_lbl.add_theme_font_size_override("font_size", 10)
	field_lbl.add_theme_color_override("font_color", MUTED)
	v.add_child(field_lbl)

	_ticket_caller = Label.new()
	_ticket_caller.text = "Caller: —"
	_ticket_caller.add_theme_font_size_override("font_size", 15)
	_ticket_caller.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_caller)

	var subj_lbl := Label.new()
	subj_lbl.text = "SUBJECT"
	subj_lbl.add_theme_font_size_override("font_size", 10)
	subj_lbl.add_theme_color_override("font_color", MUTED)
	v.add_child(subj_lbl)

	_ticket_subject = Label.new()
	_ticket_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_subject.add_theme_font_size_override("font_size", 14)
	_ticket_subject.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_subject)

	var tip := Label.new()
	tip.text = "\nTip: Name is on the ticket.\nQA still wants you to type it.\n\nDecline twice forces pickup."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.9))
	v.add_child(tip)

	return panel


func _build_call_panel() -> Control:
	var panel := _panel_container()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var call_hdr := HBoxContainer.new()
	var ch := Label.new()
	ch.text = "CALL WORKSPACE"
	ch.add_theme_font_size_override("font_size", 11)
	ch.add_theme_color_override("font_color", MUTED)
	ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_hdr.add_child(ch)
	_voice_status = Label.new()
	_voice_status.text = ""
	_voice_status.add_theme_font_size_override("font_size", 11)
	_voice_status.add_theme_color_override("font_color", ACCENT)
	call_hdr.add_child(_voice_status)
	v.add_child(call_hdr)

	_dialogue = RichTextLabel.new()
	_dialogue.bbcode_enabled = true
	_dialogue.fit_content = false
	_dialogue.scroll_active = true
	_dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue.custom_minimum_size = Vector2(0, 140)
	_dialogue.add_theme_color_override("default_color", TEXT)
	_dialogue.add_theme_font_size_override("normal_font_size", 16)
	v.add_child(_dialogue)

	_name_row = HBoxContainer.new()
	_name_row.visible = false
	_name_row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.text = "Caller name"
	name_lbl.add_theme_color_override("font_color", MUTED)
	_name_row.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Type exact name…"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_name_submit())
	_style_line_edit(_name_edit)
	_name_row.add_child(_name_edit)

	_ptt_btn = Button.new()
	_ptt_btn.text = "Push-to-Talk"
	_ptt_btn.visible = false
	_ptt_btn.tooltip_text = "Hold to record (STT stub — typed name still required in v1)"
	_style_ghost_button(_ptt_btn)
	_ptt_btn.button_down.connect(_on_ptt_down)
	_ptt_btn.button_up.connect(_on_ptt_up)
	_name_row.add_child(_ptt_btn)

	var submit := Button.new()
	submit.text = "Confirm"
	_style_primary_button(submit)
	submit.pressed.connect(_on_name_submit)
	_name_row.add_child(submit)
	v.add_child(_name_row)

	_choices = VBoxContainer.new()
	_choices.visible = false
	_choices.add_theme_constant_override("separation", 8)
	v.add_child(_choices)

	_checklist = VBoxContainer.new()
	_checklist.visible = false
	_checklist.add_theme_constant_override("separation", 8)
	v.add_child(_checklist)

	_grade_panel = _panel_container()
	_grade_panel.visible = false
	var gmargin := MarginContainer.new()
	gmargin.name = "Margin"
	gmargin.add_theme_constant_override("margin_left", 14)
	gmargin.add_theme_constant_override("margin_right", 14)
	gmargin.add_theme_constant_override("margin_top", 10)
	gmargin.add_theme_constant_override("margin_bottom", 10)
	_grade_panel.add_child(gmargin)
	var gv := VBoxContainer.new()
	gv.name = "VBox"
	gv.add_theme_constant_override("separation", 8)
	gmargin.add_child(gv)
	v.add_child(_grade_panel)

	_next_btn = Button.new()
	_next_btn.visible = false
	_next_btn.custom_minimum_size = Vector2(0, 42)
	_style_primary_button(_next_btn)
	_next_btn.pressed.connect(_on_next_pressed)
	v.add_child(_next_btn)

	return panel


func _build_av_panel() -> Control:
	var panel := _panel_container()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var hdr := Label.new()
	hdr.text = "AGENT AV"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", MUTED)
	v.add_child(hdr)

	_softphone_label = Label.new()
	_softphone_label.text = "Softphone · —"
	_softphone_label.add_theme_font_size_override("font_size", 11)
	_softphone_label.add_theme_color_override("font_color", ACCENT)
	v.add_child(_softphone_label)

	# Webcam preview frame
	var cam_frame := PanelContainer.new()
	var cam_sb := StyleBoxFlat.new()
	cam_sb.bg_color = TICKET_BG
	cam_sb.set_border_width_all(1)
	cam_sb.border_color = PANEL_EDGE
	cam_sb.set_corner_radius_all(4)
	cam_frame.add_theme_stylebox_override("panel", cam_sb)
	cam_frame.custom_minimum_size = Vector2(0, 120)
	v.add_child(cam_frame)

	var cam_stack := Control.new()
	cam_stack.custom_minimum_size = Vector2(176, 116)
	cam_frame.add_child(cam_stack)

	var cam_bg := ColorRect.new()
	cam_bg.color = Color("0e141c")
	cam_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	cam_stack.add_child(cam_bg)

	_cam_preview = TextureRect.new()
	_cam_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cam_preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cam_preview.modulate = Color(0.5, 0.55, 0.6, 1)
	cam_stack.add_child(_cam_preview)

	var cam_placeholder := Label.new()
	cam_placeholder.text = "WEBCAM\nOFFLINE"
	cam_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cam_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cam_placeholder.add_theme_font_size_override("font_size", 12)
	cam_placeholder.add_theme_color_override("font_color", MUTED)
	cam_placeholder.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	cam_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cam_stack.add_child(cam_placeholder)
	# Keep placeholder behind texture when live — hide when texture set via status.
	_cam_preview.set_meta("placeholder", cam_placeholder)

	_cam_status = Label.new()
	_cam_status.text = "Camera off — opt in below"
	_cam_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cam_status.add_theme_font_size_override("font_size", 10)
	_cam_status.add_theme_color_override("font_color", MUTED)
	v.add_child(_cam_status)

	_cam_toggle = CheckButton.new()
	_cam_toggle.text = "Enable camera"
	_cam_toggle.add_theme_color_override("font_color", TEXT)
	_cam_toggle.toggled.connect(_on_cam_toggled)
	v.add_child(_cam_toggle)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = PANEL_EDGE
	v.add_child(rule)

	_mic_status = Label.new()
	_mic_status.text = "Mic off — type names"
	_mic_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mic_status.add_theme_font_size_override("font_size", 10)
	_mic_status.add_theme_color_override("font_color", MUTED)
	v.add_child(_mic_status)

	_mic_toggle = CheckButton.new()
	_mic_toggle.text = "Enable mic (PTT)"
	_mic_toggle.add_theme_color_override("font_color", TEXT)
	_mic_toggle.toggled.connect(_on_mic_toggled)
	v.add_child(_mic_toggle)

	var note := Label.new()
	note.text = "AV is optional. Missing devices never block the call — keyboard name entry always works."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.85))
	v.add_child(note)

	return panel


func _panel_container() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _style_primary_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = ACCENT.lightened(0.1)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT.darkened(0.1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", BG)
	btn.add_theme_color_override("font_hover_color", BG)
	btn.add_theme_color_override("font_pressed_color", BG)
	btn.add_theme_font_size_override("font_size", 14)


func _style_ghost_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = TICKET_BG
	normal.set_border_width_all(1)
	normal.border_color = PANEL_EDGE
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.border_color = AMBER
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_font_size_override("font_size", 12)


func _style_choice_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = TICKET_BG
	normal.set_border_width_all(1)
	normal.border_color = PANEL_EDGE
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.border_color = ACCENT
	hover.bg_color = Color(0.14, 0.22, 0.28)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", MUTED)
	btn.add_theme_font_size_override("font_size", 14)


func _style_line_edit(edit: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TICKET_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sb)
	var focus: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("font_placeholder_color", MUTED)


func _set_dialogue(bbcode: String) -> void:
	_dialogue.text = bbcode


func _clear_container(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _format_clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]


func _on_stress_changed(value: float) -> void:
	_stress_bar.value = value
	_stress_label.text = "Stress %d" % int(value)
	var fill := _stress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		if value >= 80.0:
			fill.bg_color = DANGER
		elif value >= 50.0:
			fill.bg_color = AMBER
		else:
			fill.bg_color = ACCENT


func _on_score_changed(value: int) -> void:
	_score_label.text = "Score %d" % value


func _pulse_stress() -> void:
	_shake_time = 0.35


func _on_shift_failed() -> void:
	_timing = false
	_phase = Phase.DONE
	_voice.stop()
	_name_row.visible = false
	_choices.visible = false
	_checklist.visible = false
	_set_incoming_ringing(false)
	_incoming_title.text = "SHIFT FAILED"
	_incoming_sub.text = "Manager override"
	_set_dialogue(
		"[color=#d94c4c][b]MANAGER OVERRIDE[/b]\nStress hit 100. Shift failed.\nGo touch grass, then clock in again.[/color]"
	)
	_next_btn.text = "  Restart Shift  "
	_next_btn.visible = true
