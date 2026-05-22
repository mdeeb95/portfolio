extends CanvasLayer

@onready var _prompt: Label = $Margin/VBox/PromptLabel
@onready var _controls_hint: Label = $Margin/VBox/ControlsHint
@onready var _joystick: VirtualJoystick = $TouchJoystick


func _ready() -> void:
	layer = 10
	_refresh_hints()
	_prompt.visible = false


func set_interact_target(target: Interactable) -> void:
	if Dialogue.is_active:
		_prompt.visible = false
		return
	if target == null:
		_prompt.visible = false
		return
	_prompt.visible = true
	if _is_touch_device():
		_prompt.text = "Tap %s" % target.display_name
	else:
		_prompt.text = "Click %s  ·  [E]" % target.display_name


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


func _refresh_hints() -> void:
	if is_mobile_controls():
		var suffix := " (editor sim)" if _joystick.is_simulating_mobile() else ""
		_controls_hint.text = "Drag left side to move  ·  Tap to interact%s" % suffix
	else:
		_controls_hint.text = "WASD to move  ·  Space to jump  ·  Click or [E] to interact"


func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()
