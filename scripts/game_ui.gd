extends CanvasLayer

@onready var _joystick: VirtualJoystick = $TouchJoystick


func get_move_vector() -> Vector2:
	if _joystick == null or not _joystick.visible:
		return Vector2.ZERO
	return _joystick.vector


func is_joystick_zone(screen_pos: Vector2) -> bool:
	if _joystick == null or not _joystick.visible:
		return false
	return _joystick.is_point_in_zone(screen_pos)


func is_mobile_controls() -> bool:
	return _joystick != null and _joystick.visible
