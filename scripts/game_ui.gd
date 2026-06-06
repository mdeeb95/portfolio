extends CanvasLayer

@onready var _joystick: VirtualJoystick = $TouchJoystick


func _ready() -> void:
	_apply_portfolio_theme()


func _apply_portfolio_theme() -> void:
	var portfolio_theme := UITokens.get_theme()
	if portfolio_theme and _joystick:
		_joystick.theme = portfolio_theme
	if _joystick == null:
		return
	var base := _joystick.get_node_or_null("Base") as Panel
	var knob := _joystick.get_node_or_null("Knob") as Panel
	if base:
		base.theme_type_variation = &"JoystickBase"
	if knob:
		knob.theme_type_variation = &"JoystickKnob"


func get_move_vector() -> Vector2:
	if _joystick == null or not _joystick.visible:
		return Vector2.ZERO
	return _joystick.vector


func is_mobile_controls() -> bool:
	return _joystick != null and _joystick.visible


func blocks_joystick_at(_screen_pos: Vector2) -> bool:
	# The joystick now claims every touch so a drag can always move; interaction
	# happens on tap-release (see try_tap_interact). Only dialogue blocks the stick.
	return Dialogue.is_active


## Fired by the joystick when a touch is released without dragging. Returns true
## if the tap landed on an interactable and started a dialogue.
func try_tap_interact(screen_pos: Vector2) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var mgr := player.get_node_or_null("InteractionManager")
	if mgr == null or not mgr.has_method("try_touch_interact"):
		return false
	return mgr.try_touch_interact(screen_pos)
