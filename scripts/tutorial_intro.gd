extends CanvasLayer
## Intro / tutorial gate shown when the game first appears.
##
## The game starts paused on a still frame. Everything is desaturated except a
## colour "spotlight" circle at the spot the player entered from (the finger
## position of the web "tap and hold to enter" hold, or screen-centre off the
## web). A short hint tells them how to move; the first movement input dismisses
## the overlay, the colour spreads back out from the spotlight, and play begins.
##
## This also replaces the old boot freeze: pausing here gives the web boot shell
## a still first frame to iris-reveal into.

const ARM_DELAY := 0.7      # ignore dismiss input briefly (lets the iris finish)
const FADE_SPEED := 3.0     # hint text fade per second
const SPREAD_SPEED := 4.5   # spotlight growth per second while dismissing

var _mat: ShaderMaterial
var _hint: Label

var _is_web := false
var _entered := false
var _armed := false
var _arm_t := 0.0
var _dismissing := false
var _text_alpha := 0.0
var _radius := 0.16

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_web = OS.has_feature("web")
	_build()
	get_tree().paused = true
	if not _is_web:
		_enter(Vector2(0.5, 0.5))

func _build() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/grayscale_spotlight.gdshader")
	_mat.set_shader_parameter("center", Vector2(0.5, 0.5))
	_mat.set_shader_parameter("radius", _radius)
	_mat.set_shader_parameter("amount", 1.0)
	rect.material = _mat
	add_child(rect)

	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -190.0
	_hint.offset_bottom = -90.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = _hint_text()
	var font := load("res://assets/ui/fonts/eclipse-foundry.ttf") as Font
	if font:
		_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 34)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 10)
	_hint.modulate.a = 0.0
	add_child(_hint)

func _hint_text() -> String:
	if DisplayServer.is_touchscreen_available():
		return "Drag anywhere to move"
	return "Use WASD or the Arrow Keys to move"

func _enter(uv: Vector2) -> void:
	_mat.set_shader_parameter("center", uv)
	_entered = true
	_arm_t = 0.0
	# On desktop there's no held-finger to worry about, so allow instant dismiss
	# (keeps in-editor F5 testing fast). On web we wait out the iris first.
	if not _is_web:
		_armed = true
	Analytics.track("game_started", Analytics.tech_props())

func _process(delta: float) -> void:
	# Web: wait for the shell to report the player entered + where their finger was.
	if _is_web and not _entered:
		if JavaScriptBridge.eval("window.__deebStarted === true", true):
			var x := float(JavaScriptBridge.eval("Number(window.__deebEnterX) || 0.5", true))
			var y := float(JavaScriptBridge.eval("Number(window.__deebEnterY) || 0.5", true))
			_enter(Vector2(x, y))

	var vp := get_viewport().get_visible_rect().size
	if vp.y > 0.0:
		_mat.set_shader_parameter("aspect", vp.x / vp.y)

	if _entered and not _armed:
		_arm_t += delta
		if _arm_t >= ARM_DELAY:
			_armed = true

	var target_alpha := 1.0 if (_entered and not _dismissing) else 0.0
	_text_alpha = move_toward(_text_alpha, target_alpha, delta * FADE_SPEED)
	_hint.modulate.a = _text_alpha

	if _dismissing:
		_radius = move_toward(_radius, 3.0, delta * SPREAD_SPEED)
		_mat.set_shader_parameter("radius", _radius)
		if _radius >= 3.0:
			queue_free()

func _input(event: InputEvent) -> void:
	if _dismissing or not _entered or not _armed:
		return
	if _is_dismiss_input(event):
		_dismiss()

func _is_dismiss_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		for action in ["move_forward", "move_back", "move_left", "move_right"]:
			if event.is_action(action):
				return true
		return false
	if event is InputEventScreenTouch and event.pressed:
		return true
	if event is InputEventScreenDrag:
		return true
	if event is InputEventMouseButton and event.pressed:
		return true
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		return true
	return false

func _dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	Analytics.track("first_move", {})
	get_tree().paused = false  # world comes alive; colour spreads from the spotlight
