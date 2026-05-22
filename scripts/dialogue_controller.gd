extends CanvasLayer

signal dialogue_started
signal dialogue_ended

const CHAR_INTERVAL := 0.028
const PUNCTUATION_PAUSE := 0.12

const DESKTOP_SIDE_MARGIN := 24
const DESKTOP_BOTTOM_MARGIN := 24
const DESKTOP_PANEL_HEIGHT := 200

const MOBILE_SIDE_MARGIN := 10
const MOBILE_BOTTOM_MARGIN := 12
const MOBILE_PANEL_HEIGHT_RATIO := 0.42
const MOBILE_PANEL_MIN_HEIGHT := 220
const MOBILE_PANEL_MAX_HEIGHT := 420

var is_active: bool = false

var _pages: Array[Dictionary] = []
var _page_index: int = 0
var _full_text: String = ""
var _visible_chars: int = 0
var _char_timer: float = 0.0
var _waiting_continue: bool = false
var _skip_to_end: bool = false

@onready var _panel: PanelContainer = $DialoguePanel
@onready var _margin: MarginContainer = $DialoguePanel/Margin
@onready var _speaker_label: Label = $DialoguePanel/Margin/VBox/Header/SpeakerLabel
@onready var _body_label: Label = $DialoguePanel/Margin/VBox/BodyLabel
@onready var _continue_hint: Label = $DialoguePanel/Margin/VBox/ContinueHint
@onready var _babble: BabblePlayer = $BabblePlayer


func _ready() -> void:
	_panel.visible = false
	layer = 20
	var root := get_tree().root
	if not root.size_changed.is_connected(_apply_responsive_layout):
		root.size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func _process(delta: float) -> void:
	if not is_active:
		return
	_tick_typewriter(delta)


func start_dialogue(pages: Array[Dictionary]) -> void:
	if pages.is_empty():
		return
	_apply_responsive_layout()
	_pages = pages
	_page_index = 0
	is_active = true
	_panel.visible = true
	dialogue_started.emit()
	_show_page()


func close_dialogue() -> void:
	is_active = false
	_panel.visible = false
	_pages.clear()
	dialogue_ended.emit()


func try_advance() -> void:
	if not is_active:
		return
	if _waiting_continue:
		_next_page()
	elif _visible_chars < _full_text.length():
		_skip_to_end = true
	else:
		_next_page()


func _show_page() -> void:
	if _page_index >= _pages.size():
		close_dialogue()
		return
	var page: Dictionary = _pages[_page_index]
	_speaker_label.text = page.get("speaker", "")
	_full_text = page.get("text", "")
	_visible_chars = 0
	_char_timer = 0.0
	_waiting_continue = false
	_skip_to_end = false
	_body_label.text = ""
	_continue_hint.visible = false


func _next_page() -> void:
	_page_index += 1
	_show_page()


func _tick_typewriter(delta: float) -> void:
	if _waiting_continue:
		return
	if _visible_chars >= _full_text.length():
		_waiting_continue = true
		_continue_hint.visible = true
		_update_continue_hint()
		return

	_char_timer -= delta
	if _char_timer > 0.0 and not _skip_to_end:
		return

	var step := 1
	if _skip_to_end:
		step = _full_text.length() - _visible_chars

	while step > 0 and _visible_chars < _full_text.length():
		var ch: String = _full_text[_visible_chars]
		_visible_chars += 1
		step -= 1
		_body_label.text = _full_text.left(_visible_chars)
		if ch != " " and ch != "\n":
			_babble.play_blip()
		if ch in [".", "!", "?", ","]:
			_char_timer = PUNCTUATION_PAUSE
		else:
			_char_timer = CHAR_INTERVAL
		if _skip_to_end:
			break

	if _skip_to_end or _visible_chars >= _full_text.length():
		_body_label.text = _full_text
		_waiting_continue = true
		_continue_hint.visible = true
		_update_continue_hint()
		_skip_to_end = false


func _update_continue_hint() -> void:
	if _is_mobile_layout():
		_continue_hint.text = "▼  Tap to continue"
	else:
		_continue_hint.text = "▼  Click or [E] to continue"


func _is_mobile_layout() -> bool:
	if is_instance_valid(GameUI) and GameUI.is_mobile_controls():
		return true
	return DisplayServer.is_touchscreen_available()


func _apply_responsive_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var mobile := _is_mobile_layout() or vp_size.x < 900.0

	var side_margin := MOBILE_SIDE_MARGIN if mobile else DESKTOP_SIDE_MARGIN
	var bottom_margin := MOBILE_BOTTOM_MARGIN if mobile else DESKTOP_BOTTOM_MARGIN
	var panel_height: int
	if mobile:
		panel_height = int(vp_size.y * MOBILE_PANEL_HEIGHT_RATIO)
		panel_height = clampi(panel_height, MOBILE_PANEL_MIN_HEIGHT, MOBILE_PANEL_MAX_HEIGHT)
	else:
		panel_height = DESKTOP_PANEL_HEIGHT

	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = side_margin
	_panel.offset_right = -side_margin
	_panel.offset_top = -panel_height - bottom_margin
	_panel.offset_bottom = -bottom_margin

	var inner_pad := 18 if mobile else 14
	_margin.add_theme_constant_override("margin_left", inner_pad)
	_margin.add_theme_constant_override("margin_top", inner_pad)
	_margin.add_theme_constant_override("margin_right", inner_pad)
	_margin.add_theme_constant_override("margin_bottom", inner_pad)

	var speaker_size := 30 if mobile else 22
	var body_size := 26 if mobile else 18
	var hint_size := 22 if mobile else 16
	_speaker_label.add_theme_font_size_override("font_size", speaker_size)
	_body_label.add_theme_font_size_override("font_size", body_size)
	_continue_hint.add_theme_font_size_override("font_size", hint_size)

	# Reserve space for header + hint; body fills the rest.
	var chrome := 88 if mobile else 72
	_body_label.custom_minimum_size.y = maxf(80.0, panel_height - chrome)
