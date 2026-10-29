extends Control
## Login / shift-start beat — nameplate into the desk.

signal shift_started

const BG := Color("1a2332")
const PANEL := Color("243044")
const ACCENT := Color("5ec4b0")
const AMBER := Color("e8a838")
const TEXT := Color("e8eef2")
const MUTED := Color("9aadb8")


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Soft desk atmosphere — radial-ish wash via layered rects
	var wash := ColorRect.new()
	wash.color = Color(0.18, 0.28, 0.34, 0.45)
	wash.set_anchors_preset(PRESET_TOP_WIDE)
	wash.offset_bottom = 280.0
	add_child(wash)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_CENTER)
	center.offset_left = -320.0
	center.offset_right = 320.0
	center.offset_top = -180.0
	center.offset_bottom = 180.0
	center.add_theme_constant_override("separation", 16)
	add_child(center)

	var brand := Label.new()
	brand.text = "SERVICE DESK"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 48)
	brand.add_theme_color_override("font_color", ACCENT)
	center.add_child(brand)

	var floor := Label.new()
	floor.text = "Northwave Corp — Floor 2"
	floor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor.add_theme_font_size_override("font_size", 20)
	floor.add_theme_color_override("font_color", MUTED)
	center.add_child(floor)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	center.add_child(rule)

	var pitch := Label.new()
	pitch.text = "Type the name. Diagnose the mess.\nFix it before stress cooks you."
	pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch.add_theme_font_size_override("font_size", 18)
	pitch.add_theme_color_override("font_color", TEXT)
	center.add_child(pitch)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	center.add_child(spacer)

	var start_btn := Button.new()
	start_btn.text = "  Clock In — Start Shift  "
	start_btn.custom_minimum_size = Vector2(0, 48)
	_style_primary_button(start_btn)
	start_btn.pressed.connect(func() -> void: shift_started.emit())
	center.add_child(start_btn)

	var note := Label.new()
	note.text = "Demo · Password Purge · baked AI voice + desk AV"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", AMBER)
	center.add_child(note)


func _style_primary_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = ACCENT.lightened(0.12)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT.darkened(0.1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", BG)
	btn.add_theme_color_override("font_hover_color", BG)
	btn.add_theme_color_override("font_pressed_color", BG)
	btn.add_theme_font_size_override("font_size", 18)
