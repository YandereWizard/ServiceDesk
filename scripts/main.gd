extends Control
## Boot root: Shift Start → Desk HUD for Demo Day 1.


func _ready() -> void:
	_show_shift_start()


func _show_shift_start() -> void:
	_clear_children()
	var scene: PackedScene = load("res://scenes/shift_start.tscn")
	var screen: Control = scene.instantiate()
	screen.shift_started.connect(_on_shift_started)
	add_child(screen)


func _on_shift_started() -> void:
	_clear_children()
	GameState.reset_shift()
	var scene: PackedScene = load("res://scenes/desk_hud.tscn")
	var desk: Control = scene.instantiate()
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
