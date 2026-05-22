extends CanvasLayer

@onready var _prompt: Label = $Margin/VBox/PromptLabel
@onready var _controls_hint: Label = $Margin/VBox/ControlsHint


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


func _refresh_hints() -> void:
	if _is_touch_device():
		_controls_hint.text = "Drag to move  ·  Tap buildings or Mathew to talk"
	else:
		_controls_hint.text = "WASD to move  ·  Space to jump  ·  Click or [E] to interact"


func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()
