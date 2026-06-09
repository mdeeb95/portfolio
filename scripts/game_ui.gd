extends CanvasLayer

@onready var _joystick: VirtualJoystick = $TouchJoystick
@onready var _mute_button: Button = $MuteButton


func _ready() -> void:
	_apply_portfolio_theme()
	if _mute_button:
		_mute_button.toggled.connect(_on_mute_toggled)


func _on_mute_toggled(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), muted)
	_mute_button.text = "UNMUTE" if muted else "MUTE"


func _apply_portfolio_theme() -> void:
	var portfolio_theme := UITokens.get_theme()
	if portfolio_theme:
		if _joystick:
			_joystick.theme = portfolio_theme
		if _mute_button:
			_mute_button.theme = portfolio_theme
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


func blocks_joystick_at(screen_pos: Vector2) -> bool:
	# The joystick now claims every touch so a drag can always move; interaction
	# happens on tap-release (see try_tap_interact). Only dialogue and on-screen
	# buttons (mute) block the stick so their taps reach the GUI.
	if Dialogue.is_active:
		return true
	return _mute_button != null and _mute_button.visible \
			and _mute_button.get_global_rect().has_point(screen_pos)


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
