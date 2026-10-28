extends Control
## Streamlined desk HUD: ticket, name field, dialogue choices, stress + score.
## Demo Day 1 loop: RING → NAME CHECK → DIAGNOSE → RESOLVE → GRADE

signal call_finished(grade: Dictionary)
signal restart_requested

enum Phase { RING, NAME_CHECK, DIAGNOSE, RESOLVE, GRADE, DONE }

const BG := Color("1a2332")
const PANEL := Color("243044")
const PANEL_EDGE := Color("2f4058")
const ACCENT := Color("5ec4b0")
const AMBER := Color("e8a838")
const DANGER := Color("e85a5a")
const TEXT := Color("e8eef2")
const MUTED := Color("9aadb8")
const TICKET_BG := Color("1e2a3a")

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

# UI refs
var _stress_bar: ProgressBar
var _stress_label: Label
var _score_label: Label
var _clock_label: Label
var _ticket_id: Label
var _ticket_subject: Label
var _ticket_caller: Label
var _ticket_dept: Label
var _phase_label: Label
var _dialogue: RichTextLabel
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _choices: VBoxContainer
var _checklist: VBoxContainer
var _grade_panel: PanelContainer
var _accept_btn: Button
var _shake_time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	GameState.stress_changed.connect(_on_stress_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.shift_failed.connect(_on_shift_failed)
	_on_stress_changed(GameState.stress)
	_on_score_changed(GameState.score)


func _process(delta: float) -> void:
	if _timing:
		_elapsed += delta
		_clock_label.text = _format_clock(_elapsed)
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
	_grade_panel.visible = false
	_name_row.visible = false
	_choices.visible = false
	_checklist.visible = false
	_accept_btn.visible = false
	_clock_label.text = "00:00"
	_name_edit.text = ""
	_name_edit.editable = true


func _populate_ticket() -> void:
	_ticket_id.text = str(_call.get("ticket_id", "NW-????"))
	_ticket_subject.text = str(_call.get("subject", ""))
	# Name is visible on the ticket — player must still type it (plan rule).
	_ticket_caller.text = "Caller: %s" % str(_call.get("caller_name", "Unknown"))
	_ticket_dept.text = "Dept: %s · %s" % [
		str(_call.get("department", "—")),
		str(_call.get("title", "Call")),
	]


# --- Phases -----------------------------------------------------------------

func _enter_ring() -> void:
	_phase = Phase.RING
	_phase_label.text = "INCOMING"
	_phase_label.add_theme_color_override("font_color", AMBER)
	var ring: Dictionary = _call.get("ring", {})
	_set_dialogue(
		"[color=#e8a838]%s[/color]\n\n[i]%s[/i]" % [
			str(ring.get("caption", "*ring*")),
			str(ring.get("intro", "…")),
		]
	)
	_accept_btn.text = "  Accept Call  "
	_accept_btn.visible = true
	_accept_btn.grab_focus()


func _on_accept_pressed() -> void:
	match _phase:
		Phase.RING:
			_accept_btn.visible = false
			_timing = true
			_enter_name_check()
		Phase.GRADE, Phase.DONE:
			call_finished.emit(_last_grade())
			restart_requested.emit()


func _enter_name_check() -> void:
	_phase = Phase.NAME_CHECK
	_phase_label.text = "NAME CHECK"
	_phase_label.add_theme_color_override("font_color", ACCENT)
	var nc: Dictionary = _call.get("name_check", {})
	_set_dialogue(str(nc.get("hint", "Type the caller name.")))
	_name_row.visible = true
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
		_set_dialogue("[color=#5ec4b0]%s[/color]" % str(nc.get("correct_reply", "Got it.")))
		await get_tree().create_timer(1.1).timeout
		if not is_inside_tree():
			return
		_enter_diagnose()
	else:
		_name_attempts += 1
		GameState.add_stress(float(nc.get("stress_wrong", 12.0)))
		_pulse_stress()
		_set_dialogue("[color=#e85a5a]%s[/color]" % str(nc.get("wrong_reply", "Wrong name.")))
		_name_edit.text = ""
		_name_edit.grab_focus()
		var max_attempts := int(nc.get("max_attempts", 2))
		if _name_attempts >= max_attempts:
			_name_row.visible = false
			_set_dialogue(
				"[color=#e85a5a]Escalation flag: name mismatch ×%d.\n[/color]Pulling ticket face-value and continuing — QA will notice."
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
		btn.custom_minimum_size = Vector2(0, 44)
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
	var tint := ACCENT if _diagnose_correct else DANGER
	_set_dialogue(
		"[color=#%s]%s[/color]" % [tint.to_html(false), str(choice.get("reply", "…"))]
	)
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
			"[color=#e85a5a]Out of order — QA wants the checklist sequential.\nTry the next required step.[/color]"
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
		_set_dialogue("[color=#5ec4b0]%s[/color]" % str(res.get("success_reply", "Done.")))
		await get_tree().create_timer(1.1).timeout
		if not is_inside_tree():
			return
		_enter_grade()


func _enter_grade() -> void:
	_phase = Phase.GRADE
	_timing = false
	_phase_label.text = "GRADE"
	_phase_label.add_theme_color_override("font_color", AMBER)
	var grade := _compute_grade()
	GameState.record_grade(grade)
	_show_grade_card(grade)
	_set_dialogue(str(grade.get("roast", "")))
	_accept_btn.text = "  Next — End Demo Shift  "
	_accept_btn.visible = true


func _compute_grade() -> Dictionary:
	# Weights from plan: name 15%, diagnose 35%, resolve 35%, speed 15%
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


var _cached_grade: Dictionary = {}


func _last_grade() -> Dictionary:
	return _cached_grade


func _show_grade_card(grade: Dictionary) -> void:
	_cached_grade = grade
	_grade_panel.visible = true
	var body: VBoxContainer = _grade_panel.get_node("Margin/VBox")
	_clear_container(body)

	var title := Label.new()
	title.text = "Ticket Review — %s" % str(grade.get("title", ""))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT)
	body.add_child(title)

	var letter := Label.new()
	letter.text = "%s  ·  %d pts" % [str(grade.get("letter", "?")), int(grade.get("points", 0))]
	letter.add_theme_font_size_override("font_size", 42)
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
	lines.add_theme_font_size_override("font_size", 14)
	lines.add_theme_color_override("font_color", MUTED)
	body.add_child(lines)


# --- UI build ---------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 16
	root.offset_right = -24
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	root.add_child(_build_chrome())
	root.add_child(_build_workspace())


func _build_chrome() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	bar.custom_minimum_size = Vector2(0, 40)

	var brand := Label.new()
	brand.text = "SERVICE DESK"
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", ACCENT)
	bar.add_child(brand)

	var floor := Label.new()
	floor.text = "Floor 2"
	floor.add_theme_font_size_override("font_size", 14)
	floor.add_theme_color_override("font_color", MUTED)
	floor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(floor)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_phase_label = Label.new()
	_phase_label.text = "IDLE"
	_phase_label.add_theme_font_size_override("font_size", 14)
	_phase_label.add_theme_color_override("font_color", MUTED)
	bar.add_child(_phase_label)

	_clock_label = Label.new()
	_clock_label.text = "00:00"
	_clock_label.add_theme_font_size_override("font_size", 16)
	_clock_label.add_theme_color_override("font_color", TEXT)
	bar.add_child(_clock_label)

	_score_label = Label.new()
	_score_label.text = "Score 0"
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", TEXT)
	bar.add_child(_score_label)

	var stress_box := VBoxContainer.new()
	stress_box.custom_minimum_size = Vector2(180, 0)
	_stress_label = Label.new()
	_stress_label.text = "Stress 20"
	_stress_label.add_theme_font_size_override("font_size", 12)
	_stress_label.add_theme_color_override("font_color", MUTED)
	stress_box.add_child(_stress_label)
	_stress_bar = ProgressBar.new()
	_stress_bar.min_value = 0
	_stress_bar.max_value = 100
	_stress_bar.value = 20
	_stress_bar.show_percentage = false
	_stress_bar.custom_minimum_size = Vector2(180, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.set_corner_radius_all(2)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = PANEL_EDGE
	bg_sb.set_corner_radius_all(2)
	_stress_bar.add_theme_stylebox_override("fill", fill)
	_stress_bar.add_theme_stylebox_override("background", bg_sb)
	stress_box.add_child(_stress_bar)
	bar.add_child(stress_box)

	return bar


func _build_workspace() -> Control:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)

	split.add_child(_build_ticket_panel())
	split.add_child(_build_call_panel())
	return split


func _build_ticket_panel() -> Control:
	var panel := _panel_container()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var header := Label.new()
	header.text = "ACTIVE TICKET"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", MUTED)
	v.add_child(header)

	_ticket_id = Label.new()
	_ticket_id.text = "NW-——"
	_ticket_id.add_theme_font_size_override("font_size", 26)
	_ticket_id.add_theme_color_override("font_color", ACCENT)
	v.add_child(_ticket_id)

	_ticket_dept = Label.new()
	_ticket_dept.text = ""
	_ticket_dept.add_theme_font_size_override("font_size", 13)
	_ticket_dept.add_theme_color_override("font_color", MUTED)
	v.add_child(_ticket_dept)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = PANEL_EDGE
	v.add_child(rule)

	_ticket_caller = Label.new()
	_ticket_caller.text = "Caller: —"
	_ticket_caller.add_theme_font_size_override("font_size", 16)
	_ticket_caller.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_caller)

	_ticket_subject = Label.new()
	_ticket_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_subject.add_theme_font_size_override("font_size", 15)
	_ticket_subject.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_subject)

	var tip := Label.new()
	tip.text = "\nTip: The name is on the ticket.\nQA still wants you to type it."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.85))
	v.add_child(tip)

	return panel


func _build_call_panel() -> Control:
	var panel := _panel_container()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	_dialogue = RichTextLabel.new()
	_dialogue.bbcode_enabled = true
	_dialogue.fit_content = false
	_dialogue.scroll_active = true
	_dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue.custom_minimum_size = Vector2(0, 160)
	_dialogue.add_theme_color_override("default_color", TEXT)
	_dialogue.add_theme_font_size_override("normal_font_size", 17)
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
	gmargin.add_theme_constant_override("margin_left", 16)
	gmargin.add_theme_constant_override("margin_right", 16)
	gmargin.add_theme_constant_override("margin_top", 12)
	gmargin.add_theme_constant_override("margin_bottom", 12)
	_grade_panel.add_child(gmargin)
	var gv := VBoxContainer.new()
	gv.name = "VBox"
	gv.add_theme_constant_override("separation", 8)
	gmargin.add_child(gv)
	v.add_child(_grade_panel)

	_accept_btn = Button.new()
	_accept_btn.visible = false
	_accept_btn.custom_minimum_size = Vector2(0, 44)
	_style_primary_button(_accept_btn)
	_accept_btn.pressed.connect(_on_accept_pressed)
	v.add_child(_accept_btn)

	return panel


func _panel_container() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _style_primary_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = ACCENT.lightened(0.1)
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT.darkened(0.1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", BG)
	btn.add_theme_color_override("font_hover_color", BG)
	btn.add_theme_color_override("font_pressed_color", BG)
	btn.add_theme_font_size_override("font_size", 16)


func _style_choice_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = TICKET_BG
	normal.set_border_width_all(1)
	normal.border_color = PANEL_EDGE
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.border_color = ACCENT
	hover.bg_color = Color(0.16, 0.24, 0.30)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", MUTED)
	btn.add_theme_font_size_override("font_size", 15)


func _style_line_edit(edit: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TICKET_BG
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", sb)
	var focus := sb.duplicate()
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
	_name_row.visible = false
	_choices.visible = false
	_checklist.visible = false
	_set_dialogue(
		"[color=#e85a5a][b]MANAGER OVERRIDE[/b]\nStress hit 100. Shift failed.\nGo touch grass, then clock in again.[/color]"
	)
	_accept_btn.text = "  Restart Shift  "
	_accept_btn.visible = true
