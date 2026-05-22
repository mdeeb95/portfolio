extends CanvasLayer

signal dialogue_started
signal dialogue_ended

const CHAR_INTERVAL := 0.028
const PUNCTUATION_PAUSE := 0.12

var is_active: bool = false

var _pages: Array[Dictionary] = []
var _page_index: int = 0
var _full_text: String = ""
var _visible_chars: int = 0
var _char_timer: float = 0.0
var _waiting_continue: bool = false
var _skip_to_end: bool = false

@onready var _panel: Control = $DialoguePanel
@onready var _speaker_label: Label = $DialoguePanel/Margin/VBox/Header/SpeakerLabel
@onready var _body_label: Label = $DialoguePanel/Margin/VBox/BodyLabel
@onready var _continue_hint: Label = $DialoguePanel/Margin/VBox/ContinueHint
@onready var _babble: BabblePlayer = $BabblePlayer


func _ready() -> void:
	_panel.visible = false
	layer = 20


func _process(delta: float) -> void:
	if not is_active:
		return
	_tick_typewriter(delta)


func start_dialogue(pages: Array[Dictionary]) -> void:
	if pages.is_empty():
		return
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
	if DisplayServer.is_touchscreen_available():
		_continue_hint.text = "▼  Tap to continue"
	else:
		_continue_hint.text = "▼  Click or [E] to continue"

