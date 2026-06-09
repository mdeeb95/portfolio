class_name VirtualJoystick
extends Control
## Floating thumbstick anywhere on screen. Claims every touch: dragging past
## tap_slop moves the player; releasing without dragging is a tap that interacts
## with whatever was under the press (so the player can always drag to move,
## even right next to an interactable).

@export var max_radius: float = 140.0
@export var deadzone: float = 0.15
## How far (px) a touch may move before it counts as a drag rather than a tap.
## Below this, releasing the touch is treated as a tap (interact); above it, the
## touch drives movement and never interacts. High-DPI phones jitter a few px on a
## "stationary" tap, so this is generous.
@export var tap_slop: float = 30.0
## A touch released within this many ms still counts as a tap (interact) even if it
## jittered past tap_slop, as long as it settled back near the press point. Covers
## quick taps on mobile browsers that briefly register as drags.
@export var quick_tap_ms: int = 220
## When true, F5 in the editor shows the stick and maps left-click drag to movement.
@export var simulate_mobile_in_editor: bool = true

var vector: Vector2 = Vector2.ZERO

@onready var _base: Control = $Base
@onready var _knob: Control = $Knob

var _touch_index: int = -1
var _using_mouse_sim: bool = false
var _origin: Vector2 = Vector2.ZERO
var _down_pos: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _down_time_ms: int = 0
var _moved: bool = false
var _active: bool = false


func _ready() -> void:
	_base.visible = false
	_knob.visible = false
	visible = _should_show()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
			_release()
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
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _using_mouse_sim:
		_update_stick(event.position)
		get_viewport().set_input_as_handled()


func _should_capture_touch(screen_pos: Vector2) -> bool:
	return not GameUI.blocks_joystick_at(screen_pos)


func _begin_stick(screen_pos: Vector2, index: int) -> void:
	_touch_index = index
	_origin = screen_pos
	_down_pos = screen_pos
	_last_pos = screen_pos
	_down_time_ms = Time.get_ticks_msec()
	_moved = false
	_active = true
	# Ring is shown lazily once the touch becomes a drag (see _update_stick), so a
	# tap-to-interact doesn't flash the stick.
	_update_stick(screen_pos)


## Release: a touch that never dragged past tap_slop counts as a tap and tries to
## interact at the press point. A quick touch that jittered but settled back near the
## press point also counts (mobile browsers can report a tap as a tiny drag).
func _release() -> void:
	if _active and _is_tap():
		GameUI.try_tap_interact(_down_pos)
	_end_stick()


func _is_tap() -> bool:
	if not _moved:
		return true
	var brief := Time.get_ticks_msec() - _down_time_ms <= quick_tap_ms
	var settled := (_last_pos - _down_pos).length() <= tap_slop * 2.0
	return brief and settled


func _end_stick() -> void:
	_touch_index = -1
	_using_mouse_sim = false
	_active = false
	_moved = false
	vector = Vector2.ZERO
	_base.visible = false
	_knob.visible = false


func _update_stick(screen_pos: Vector2) -> void:
	_last_pos = screen_pos
	var delta := screen_pos - _origin
	if not _moved:
		if delta.length() <= tap_slop:
			vector = Vector2.ZERO
			return
		# Crossed the threshold: this is a drag. Show the stick and start moving.
		_moved = true
		_place_ring(_origin)

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
