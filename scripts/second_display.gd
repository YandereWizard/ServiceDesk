extends Node
## Opens a real OS second window (Knowledge Base + ticket mirror) on a chosen screen.
## Content choice: dual-monitor helpdesk fantasy — primary = softphone/ticket workspace,
## secondary = Northwave KB / SOP glance board with live ticket mirror.

const WIN_SIZE := Vector2i(960, 720)
const OFFSET_SAME_SCREEN := Vector2i(48, 48)

# Palette matches desk_hud
const BG := Color("10161e")
const PANEL := Color("1e2834")
const PANEL_EDGE := Color("2a3848")
const ACCENT := Color("3dba9c")
const AMBER := Color("e0a030")
const TEXT := Color("e6edf2")
const MUTED := Color("8a9ba8")
const TICKET_BG := Color("161e28")

var _window: Window
var _ticket_id: Label
var _ticket_caller: Label
var _ticket_subject: Label
var _phase_label: Label
var _stress_label: Label
var _score_label: Label
var _status_label: Label
var _sop_body: RichTextLabel

# Mirrored call context
var _ctx_ticket_id: String = "—"
var _ctx_caller: String = "—"
var _ctx_subject: String = "—"
var _ctx_phase: String = "IDLE"
var _ctx_dept: String = ""


func _ready() -> void:
	UserSettings.settings_changed.connect(_on_settings_changed)
	GameState.stress_changed.connect(_on_stress)
	GameState.score_changed.connect(_on_score)
	# Apply after the main window exists.
	call_deferred("_on_settings_changed")


func _exit_tree() -> void:
	_close_window()


func update_call_context(
	ticket_id: String,
	caller: String,
	subject: String,
	phase: String,
	department: String = ""
) -> void:
	_ctx_ticket_id = ticket_id if ticket_id != "" else "—"
	_ctx_caller = caller if caller != "" else "—"
	_ctx_subject = subject if subject != "" else "—"
	_ctx_phase = phase if phase != "" else "IDLE"
	_ctx_dept = department
	_refresh_mirror()


func clear_call_context() -> void:
	_ctx_ticket_id = "—"
	_ctx_caller = "—"
	_ctx_subject = "—"
	_ctx_phase = "IDLE"
	_ctx_dept = ""
	_refresh_mirror()


func _on_settings_changed() -> void:
	if UserSettings.second_window_enabled:
		_open_window()
		_place_on_screen(UserSettings.second_screen_index)
	else:
		_close_window()


func _open_window() -> void:
	if _window != null and is_instance_valid(_window):
		_refresh_mirror()
		if not _window.visible:
			_window.show()
		return

	_window = Window.new()
	_window.title = "Northwave KB — Second Display"
	_window.size = WIN_SIZE
	_window.min_size = Vector2i(640, 480)
	_window.unresizable = false
	_window.transient = false
	_window.exclusive = false
	_window.close_requested.connect(_on_window_close_requested)
	add_child(_window)
	_build_content(_window)
	_refresh_mirror()
	_on_stress(GameState.stress)
	_on_score(GameState.score)
	_window.show()


func _close_window() -> void:
	if _window == null:
		return
	if is_instance_valid(_window):
		_window.hide()
		_window.queue_free()
	_window = null
	_ticket_id = null
	_ticket_caller = null
	_ticket_subject = null
	_phase_label = null
	_stress_label = null
	_score_label = null
	_status_label = null
	_sop_body = null


func _on_window_close_requested() -> void:
	# Closing the window via OS chrome turns the setting off and persists.
	UserSettings.set_second_window_enabled(false)


func _place_on_screen(screen_index: int) -> void:
	if _window == null or not is_instance_valid(_window):
		return
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return
	var idx := clampi(screen_index, 0, count - 1)
	var screen_pos := DisplayServer.screen_get_position(idx)
	var screen_size := DisplayServer.screen_get_size(idx)
	var win_size := _window.size

	_window.current_screen = idx

	var pos: Vector2i
	if count == 1:
		# Same screen: offset so both windows stay usable.
		var main_id := DisplayServer.MAIN_WINDOW_ID
		var main_pos := DisplayServer.window_get_position(main_id)
		pos = main_pos + OFFSET_SAME_SCREEN
		# Keep on-screen.
		pos.x = clampi(pos.x, screen_pos.x, screen_pos.x + maxi(screen_size.x - win_size.x, 0))
		pos.y = clampi(pos.y, screen_pos.y, screen_pos.y + maxi(screen_size.y - win_size.y, 0))
		if _status_label:
			_status_label.text = "Single display — window offset on the same screen."
	else:
		# Center on the chosen secondary (or any) screen.
		pos = screen_pos + Vector2i(
			maxi((screen_size.x - win_size.x) / 2, 24),
			maxi((screen_size.y - win_size.y) / 2, 24)
		)
		if _status_label:
			_status_label.text = "Placed on %s" % UserSettings.screen_label(idx)

	_window.position = pos


func _build_content(host: Window) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)

	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.add_theme_constant_override("separation", 0)
	var brand := Label.new()
	brand.text = "NORTHWAVE KNOWLEDGE BASE"
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", ACCENT)
	brand_box.add_child(brand)
	var sub := Label.new()
	sub.text = "Second monitor · SOP glance board · Floor 2"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", MUTED)
	brand_box.add_child(sub)
	header.add_child(brand_box)

	_phase_label = Label.new()
	_phase_label.text = "IDLE"
	_phase_label.add_theme_font_size_override("font_size", 13)
	_phase_label.add_theme_color_override("font_color", AMBER)
	header.add_child(_phase_label)

	_stress_label = Label.new()
	_stress_label.add_theme_font_size_override("font_size", 12)
	_stress_label.add_theme_color_override("font_color", MUTED)
	header.add_child(_stress_label)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 12)
	_score_label.add_theme_color_override("font_color", TEXT)
	header.add_child(_score_label)

	# Ticket mirror + SOP split
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	col.add_child(split)

	split.add_child(_build_ticket_mirror())
	split.add_child(_build_sop_panel())

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", MUTED)
	col.add_child(_status_label)


func _build_ticket_mirror() -> Control:
	var panel := _panel()
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

	var hdr := Label.new()
	hdr.text = "LIVE TICKET MIRROR"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", MUTED)
	v.add_child(hdr)

	_ticket_id = Label.new()
	_ticket_id.text = "—"
	_ticket_id.add_theme_font_size_override("font_size", 26)
	_ticket_id.add_theme_color_override("font_color", ACCENT)
	v.add_child(_ticket_id)

	_ticket_caller = Label.new()
	_ticket_caller.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_caller.add_theme_font_size_override("font_size", 15)
	_ticket_caller.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_caller)

	_ticket_subject = Label.new()
	_ticket_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticket_subject.add_theme_font_size_override("font_size", 14)
	_ticket_subject.add_theme_color_override("font_color", TEXT)
	v.add_child(_ticket_subject)

	var tip := Label.new()
	tip.text = "\nGlance here while the softphone stays on your primary screen. Closing this window turns Second window off in Settings."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.9))
	v.add_child(tip)

	return panel


func _build_sop_panel() -> Control:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	var hdr := Label.new()
	hdr.text = "SOP / QUICK REFERENCE"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", MUTED)
	v.add_child(hdr)

	_sop_body = RichTextLabel.new()
	_sop_body.bbcode_enabled = true
	_sop_body.fit_content = false
	_sop_body.scroll_active = true
	_sop_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sop_body.add_theme_color_override("default_color", TEXT)
	_sop_body.add_theme_font_size_override("normal_font_size", 14)
	_sop_body.text = _default_sop_bbcode()
	v.add_child(_sop_body)

	return panel


func _default_sop_bbcode() -> String:
	return (
		"[color=#3dba9c][b]NW-KB · Identity / Access[/b][/color]\n\n"
		+ "[b]Password Purge — Floor 2 script[/b]\n"
		+ "1. Verify caller name against the ticket (type it; QA listens).\n"
		+ "2. Diagnose: prefer stale MFA / token drift over “keyboard mode”.\n"
		+ "3. Resolve in order: invalidate session → force MFA re-enroll → confirm login.\n\n"
		+ "[color=#e0a030]Stress cues[/color]\n"
		+ "· Wrong name or out-of-order checklist spikes stress.\n"
		+ "· Decline twice → queue override forces pickup.\n"
		+ "· Stress 100 → manager override ends the shift.\n\n"
		+ "[color=#8a9ba8]This board is read-only. Interact on the primary softphone window.[/color]"
	)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _refresh_mirror() -> void:
	if _ticket_id == null:
		return
	_ticket_id.text = _ctx_ticket_id
	var dept := (" · %s" % _ctx_dept) if _ctx_dept != "" else ""
	_ticket_caller.text = "Caller: %s%s" % [_ctx_caller, dept]
	_ticket_subject.text = "Subject: %s" % _ctx_subject
	if _phase_label:
		_phase_label.text = _ctx_phase


func _on_stress(value: float) -> void:
	if _stress_label:
		_stress_label.text = "Stress %d" % int(value)


func _on_score(value: int) -> void:
	if _score_label:
		_score_label.text = "Score %d" % value
