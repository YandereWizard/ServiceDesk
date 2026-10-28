extends Node
## Shift-wide stress, score, and grade stubs for Demo Day 1.

signal stress_changed(value: float)
signal score_changed(value: int)
signal shift_failed

const STRESS_START := 20.0
const STRESS_FAIL := 100.0

var stress: float = STRESS_START
var score: int = 0
var call_grades: Array[Dictionary] = []
var shift_active: bool = false


func reset_shift() -> void:
	stress = STRESS_START
	score = 0
	call_grades.clear()
	shift_active = true
	stress_changed.emit(stress)
	score_changed.emit(score)


func add_stress(amount: float) -> void:
	stress = clampf(stress + amount, 0.0, STRESS_FAIL)
	stress_changed.emit(stress)
	if stress >= STRESS_FAIL:
		shift_active = false
		shift_failed.emit()


func relieve_stress(amount: float) -> void:
	add_stress(-amount)


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


func record_grade(grade_data: Dictionary) -> void:
	call_grades.append(grade_data)
	add_score(int(grade_data.get("points", 0)))


func letter_for_percent(pct: float) -> String:
	if pct >= 90.0:
		return "A"
	if pct >= 80.0:
		return "B"
	if pct >= 70.0:
		return "C"
	if pct >= 60.0:
		return "D"
	return "F"
