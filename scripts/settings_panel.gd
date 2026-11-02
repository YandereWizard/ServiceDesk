extends CanvasLayer
## Settings overlay — Second window / dual display toggle + screen picker.
## Open via gear button or Escape from the desk HUD.

signal closed

const BG_DIM := Color(0.04, 0.06, 0.08, 0.72)
const PANEL := Color("1e2834")
const PANEL_EDGE := Color("2a3848")
const ACCENT := Color("3dba9c")
const TEXT := Color("e6edf2")
const MUTED := Color("8a9ba8")
const TICKET_BG := Color("161e28")

var _toggle: CheckButton
var _screen_option: OptionButton
var _screen_hint: Label
var _panel_root: Control


func _ready() -> void:
	layer = 64
	_build()
	_refresh_from_settings()
	UserSettings.settings_changed.connect(_on_external_settings_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh_from_settings()
	visible = true
	if _toggle:
		_toggle.grab_focus()


func _close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = BG_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel_root = PanelContainer.new()
	_panel_root.custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_border_width_all(1)
	sb.border_color = PANEL_EDGE
	sb.set_corner_radius_all(6)
	_panel_root.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel_root.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	_style_ghost(close_btn)
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)
	v.add_child(title_row)

	var section := Label.new()
	section.text = "DISPLAY"
	section.add_theme_font_size_override("font_size", 11)
	section.add_theme_color_override("font_color", MUTED)
	v.add_child(section)

	_toggle = CheckButton.new()
	_toggle.text = "Second window"
	_toggle.tooltip_text = "Open a Knowledge Base window on another screen (or offset on the same screen)."
	_toggle.add_theme_color_override("font_color", TEXT)
	_toggle.toggled.connect(_on_toggle)
	v.add_child(_toggle)

	var dual_lbl := Label.new()
	dual_lbl.text = "Dual display — Northwave KB + live ticket mirror"
	dual_lbl.add_theme_font_size_override("font_size", 12)
	dual_lbl.add_theme_color_override("font_color", MUTED)
	v.add_child(dual_lbl)

	var screen_lbl := Label.new()
	screen_lbl.text = "Target display"
	screen_lbl.add_theme_font_size_override("font_size", 12)
	screen_lbl.add_theme_color_override("font_color", TEXT)
	v.add_child(screen_lbl)

	_screen_option = OptionButton.new()
	_screen_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_option.item_selected.connect(_on_screen_selected)
	v.add_child(_screen_option)

	_screen_hint = Label.new()
	_screen_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen_hint.add_theme_font_size_override("font_size", 11)
	_screen_hint.add_theme_color_override("font_color", MUTED)
	v.add_child(_screen_hint)

	var footer := Label.new()
	footer.text = "Esc closes Settings. Closing the second window turns this toggle off."
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.85))
	v.add_child(footer)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _refresh_from_settings() -> void:
	_populate_screens()
	_toggle.set_pressed_no_signal(UserSettings.second_window_enabled)
	_update_picker_enabled()


func _on_external_settings_changed() -> void:
	# e.g. user closed the OS second window → toggle flips off.
	if not visible:
		return
	_toggle.set_pressed_no_signal(UserSettings.second_window_enabled)
	_update_picker_enabled()


func _populate_screens() -> void:
	_screen_option.clear()
	var count := UserSettings.screen_count()
	if count <= 0:
		_screen_option.add_item("No displays detected", 0)
		_screen_option.disabled = true
		_screen_hint.text = "No displays reported by the OS."
		return

	for i in count:
		_screen_option.add_item(UserSettings.screen_label(i), i)

	var idx := clampi(UserSettings.second_screen_index, 0, count - 1)
	_screen_option.select(idx)

	if count == 1:
		_screen_option.disabled = true
		_screen_hint.text = "Only one monitor detected — the second window opens on this screen, offset so both stay visible."
	else:
		_screen_option.disabled = not UserSettings.second_window_enabled
		_screen_hint.text = "Choose which monitor hosts the Knowledge Base window."


func _update_picker_enabled() -> void:
	var count := UserSettings.screen_count()
	if count <= 1:
		_screen_option.disabled = true
	else:
		_screen_option.disabled = not UserSettings.second_window_enabled


func _on_toggle(pressed: bool) -> void:
	UserSettings.set_second_window_enabled(pressed)
	_update_picker_enabled()
	if pressed and UserSettings.screen_count() > 1:
		# Re-assert placement for the currently selected screen.
		UserSettings.set_second_screen_index(_screen_option.get_selected_id())


func _on_screen_selected(index: int) -> void:
	var id := _screen_option.get_item_id(index)
	UserSettings.set_second_screen_index(id)


func _style_ghost(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = TICKET_BG
	normal.set_border_width_all(1)
	normal.border_color = PANEL_EDGE
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate()
	hover.border_color = ACCENT
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_font_size_override("font_size", 12)
