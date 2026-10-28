extends Control
## Demo mini-map: click a place to walk there. Shows how a game feeds
## QKQuestLog.update_position() and draws a marker and a compass from QKQuestLog.get_target().

signal arrived(place: StringName)

## Map coordinates (the "world" of the demo), in metres.
const PLACES := {
	&"square": [Vector2(40, 70), "Square"],
	&"forest": [Vector2(110, 25), "Forest"],
	&"mira_hut": [Vector2(190, 85), "Mira's hut"],
	&"ruins": [Vector2(255, 30), "Ruins"],
	&"camp": [Vector2(320, 90), "Bandit camp"],
	&"mine": [Vector2(355, 30), "Old mine"],
}
const SPEED := 160.0

var quest_log: QKQuestLog
var player := Vector2(40, 70)
var _goal := Vector2(40, 70)
var _goal_place: StringName
var _compass := Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(390, 150)
	mouse_filter = MOUSE_FILTER_STOP
	_compass.position = Vector2(8, 118)
	_compass.add_theme_font_size_override(&"font_size", 13)
	add_child(_compass)


static func place_position(place: StringName) -> Vector2:
	return PLACES[place][0]


## Walks to a place; [param instant] teleports (tests, the action buttons).
func walk_to(place: StringName, instant: bool = false) -> void:
	_goal = place_position(place)
	_goal_place = place
	if instant:
		player = _goal
		_moved()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best: StringName
		var best_distance := INF
		for place: StringName in PLACES:
			var distance := _to_screen(place_position(place)).distance_to(event.position)
			if distance < best_distance:
				best_distance = distance
				best = place
		walk_to(best)
		accept_event()


func _process(delta: float) -> void:
	if player != _goal:
		player = player.move_toward(_goal, SPEED * delta)
		_moved()
	_update_compass()
	queue_redraw()


func _moved() -> void:
	if quest_log != null:
		quest_log.update_position(player)
	if player == _goal and not _goal_place.is_empty():
		var place := _goal_place
		_goal_place = &""
		arrived.emit(place)


func _update_compass() -> void:
	var target := quest_log.get_target() if quest_log != null else {}
	if target.is_empty():
		_compass.text = "Compass: no place to go for the tracked quests."
		return
	var offset := Vector2(target.position.x, target.position.y) - player
	var directions := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var heading: String = directions[posmod(roundi(offset.angle() / (PI / 4)), 8)]
	_compass.text = "Compass: %s — %d m %s" % [target.text, roundi(offset.length()), heading]


func _to_screen(world: Vector2) -> Vector2:
	return Vector2(10, 8) + world


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.17, 0.12))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
	var font := get_theme_default_font()
	for place: StringName in PLACES:
		var at := _to_screen(place_position(place))
		draw_circle(at, 5, Color(0.85, 0.78, 0.6))
		draw_string(font, at + Vector2(-28, -8), PLACES[place][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
	var target := quest_log.get_target() if quest_log != null else {}
	var me := _to_screen(player)
	if not target.is_empty():
		var goal := _to_screen(Vector2(target.position.x, target.position.y))
		draw_arc(goal, maxf(8.0, target.radius), 0, TAU, 32, Color(1, 0.82, 0.3), 2.0)
		draw_dashed_line(me, goal, Color(1, 0.82, 0.3, 0.6), 1.5, 5.0)
		var tip := me + (goal - me).limit_length(22.0)
		draw_line(me, tip, Color(1, 0.82, 0.3), 3.0)
	draw_circle(me, 6, Color(0.45, 0.8, 1.0))
