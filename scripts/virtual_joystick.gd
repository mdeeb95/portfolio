class_name VirtualJoystick
extends Control
## Floating thumbstick: touch in the right zone, drag from the press point to move.

@export var max_radius: float = 90.0
@export var deadzone: float = 0.15
## When true, F5 in the editor shows the stick and maps left-click drag to movement.
@export var simulate_mobile_in_editor: bool = true

var vector: Vector2 = Vector2.ZERO

@onready var _base: Control = $Base
@onready var _knob: Control = $Knob

var _touch_index: int = -1
var _using_mouse_sim: bool = false
var _origin: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	_base.visible = false
	_knob.visible = false
	visible = _should_show()
	mouse_filter = Control.MOUSE_FILTER_STOP


func is_simulating_mobile() -> bool:
	return _simulate_in_editor()


func _should_show() -> bool:
	return DisplayServer.is_touchscreen_available() or _simulate_in_editor()


func _simulate_in_editor() -> bool:
	return simulate_mobile_in_editor and not DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Dialogue.is_active:
		return

	if _simulate_in_editor():
		_handle_mouse_sim(event)

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index == -1 and not _using_mouse_sim and _should_capture_touch(touch.position):
				_begin_stick(touch.position, touch.index)
				get_viewport().set_input_as_handled()
		elif touch.index == _touch_index:
			_end_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_stick(drag.position)
			get_viewport().set_input_as_handled()


func _handle_mouse_sim(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and not _active and _should_capture_touch(mb.position):
			_begin_stick(mb.position, -1)
			_using_mouse_sim = true
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _using_mouse_sim:
			_end_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _using_mouse_sim:
		_update_stick(event.position)
		get_viewport().set_input_as_handled()


func is_point_in_zone(screen_pos: Vector2) -> bool:
	return visible and get_global_rect().has_point(screen_pos)


func _is_in_zone(screen_pos: Vector2) -> bool:
	return get_global_rect().has_point(screen_pos)


func _should_capture_touch(screen_pos: Vector2) -> bool:
	if not _is_in_zone(screen_pos):
		return false
	if GameUI.blocks_joystick_at(screen_pos):
		return false
	return true


func _begin_stick(screen_pos: Vector2, index: int) -> void:
	_touch_index = index
	_origin = screen_pos
	_active = true
	_place_ring(screen_pos)
	_update_stick(screen_pos)


func _end_stick() -> void:
	_touch_index = -1
	_using_mouse_sim = false
	_active = false
	vector = Vector2.ZERO
	_base.visible = false
	_knob.visible = false


func _update_stick(screen_pos: Vector2) -> void:
	var delta := screen_pos - _origin
	var clamped := delta.limit_length(max_radius)
	_knob.global_position = _origin + clamped - _knob.size * 0.5

	var strength := clamped.length() / max_radius
	if strength < deadzone:
		vector = Vector2.ZERO
	else:
		vector = clamped / max_radius


func _place_ring(center: Vector2) -> void:
	var diameter := max_radius * 2.0
	_base.size = Vector2(diameter, diameter)
	_base.global_position = center - Vector2(max_radius, max_radius)
	_base.visible = true
	_knob.visible = true
	_knob.global_position = center - _knob.size * 0.5
