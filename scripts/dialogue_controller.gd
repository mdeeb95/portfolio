@tool
extends CanvasLayer

signal dialogue_started
signal dialogue_ended
signal dialogue_completed_fully

const CHAR_INTERVAL := 0.028
const PUNCTUATION_PAUSE := 0.12

const PREVIEW_SPEAKER := "Mathew Deeb"
const PREVIEW_ROLE := "Designer · Engineer"
const PREVIEW_LINE := "Hey — I'm Mathew. Walk around town to see where I've worked, what I've shipped, and what I do outside of work."
const FADE_MIN_HEIGHT := 160.0
const FADE_MAX_VIEWPORT_RATIO := 0.88

@export_group("Layout")
## Target width of the centered dialogue panel in canvas pixels (not %).
## Clamped to the current window width: values larger than the window use the full window.
@export_range(320.0, 1920.0, 1.0) var content_max_width: float = 720.0:
	set(v):
		content_max_width = v
		_request_layout()
## Body text wrap width in canvas pixels. 0 = use the full panel width inside margins.
## Ignored when the panel spans the full window (see content max width).
@export var body_max_width: float = 0.0:
	set(v):
		body_max_width = maxf(0.0, v)
		_request_layout()
@export var content_padding_horizontal: int = 36:
	set(v):
		content_padding_horizontal = v
		_request_layout()
@export var content_padding_bottom: int = 30:
	set(v):
		content_padding_bottom = v
		_request_layout()

@export_group("Fade")
## How many pixels of gradient sit above the dialogue block (more = more fade over the text).
@export_range(0, 800, 1) var fade_text_cover: int = 120:
	set(v):
		fade_text_cover = v
		_request_layout()

@export_group("Typography")
@export var font_body: Font
@export var font_speaker: Font
@export var body_font_size: int = 19:
	set(v):
		body_font_size = v
		_request_layout()
@export var speaker_font_size: int = 15:
	set(v):
		speaker_font_size = v
		_request_layout()
@export var role_font_size: int = 10:
	set(v):
		role_font_size = v
		_request_layout()
@export var continue_font_size: int = 11:
	set(v):
		continue_font_size = v
		_request_layout()

@export_group("Editor Preview")
## Only works while dialogue_ui.tscn is the open scene tab (uses is_part_of_edited_scene).
## The Dialogue autoload will NOT paint over the whole IDE when you edit other scenes.
@export var preview_in_editor: bool = false:
	set(v):
		preview_in_editor = v
		_update_editor_preview()
## When preview is on: false = mid-typewriter, true = line finished with Continue row.
@export var preview_show_continue: bool = true:
	set(v):
		preview_show_continue = v
		if _can_use_editor_preview():
			_apply_preview_state()
@export var preview_speaker: String = PREVIEW_SPEAKER:
	set(v):
		preview_speaker = v
		if _can_use_editor_preview():
			_apply_preview_state()
@export var preview_role: String = PREVIEW_ROLE:
	set(v):
		preview_role = v
		if _can_use_editor_preview():
			_apply_preview_state()
@export_multiline var preview_line: String = PREVIEW_LINE:
	set(v):
		preview_line = v
		if _can_use_editor_preview():
			_apply_preview_state()

var is_active: bool = false

var _pages: Array[Dictionary] = []
var _page_index: int = 0
var _full_text: String = ""
var _visible_chars: int = 0
var _char_timer: float = 0.0
var _waiting_continue: bool = false
var _skip_to_end: bool = false
var _closing_after_full_read: bool = false
var _is_preview_session: bool = false
var _text_column_width: float = 640.0
var _layout_block_w: float = 720.0

@onready var _root: Control = $DialogueRoot
@onready var _fade: TextureRect = $DialogueRoot/Fade
@onready var _content_column: Control = $DialogueRoot/ContentColumn
@onready var _content: MarginContainer = $DialogueRoot/ContentColumn/Content
@onready var _vbox: VBoxContainer = $DialogueRoot/ContentColumn/Content/VBox
@onready var _body_wrap: Control = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap
@onready var _body_vbox: VBoxContainer = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox
@onready var _name_tag: Control = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag
@onready var _speaker_label: Label = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagFace/TagRow/SpeakerLabel
@onready var _role_label: Label = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagFace/TagRow/RoleLabel
@onready var _role_divider: ColorRect = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagFace/TagRow/RoleDivider
@onready var _body_label: Label = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/BodyLabel
@onready var _type_cursor: ColorRect = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/TypeCursor
@onready var _continue_row: HBoxContainer = $DialogueRoot/ContentColumn/Content/VBox/ContinueRow
@onready var _continue_label: Label = $DialogueRoot/ContentColumn/Content/VBox/ContinueRow/ContinueLabel
@onready var _prompt_key: PanelContainer = $DialogueRoot/ContentColumn/Content/VBox/ContinueRow/PromptKey
@onready var _caret_animator: AnimationPlayer = $DialogueRoot/ContentColumn/Content/VBox/CaretAnimator
@onready var _babble: BabblePlayer = $BabblePlayer


func _ready() -> void:
	_setup_fonts()
	_setup_styles()
	_root.visible = false
	_configure_dialogue_input()
	layer = 20
	if not Engine.is_editor_hint():
		var tree_root := get_tree().root
		if not tree_root.size_changed.is_connected(_apply_responsive_layout):
			tree_root.size_changed.connect(_apply_responsive_layout)
		call_deferred("_apply_responsive_layout")
	else:
		_update_editor_preview()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_active:
		return
	_tick_typewriter(delta)


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what in [
		NOTIFICATION_ENTER_TREE,
		NOTIFICATION_EXIT_TREE,
		NOTIFICATION_EDITOR_PRE_SAVE,
	]:
		call_deferred("_update_editor_preview")


func run_preview() -> void:
	_is_preview_session = true
	is_active = false
	_pages = [{
		"speaker": preview_speaker,
		"role": preview_role,
		"text": preview_line,
	}]
	_page_index = 0
	_root.visible = true
	_apply_responsive_layout()
	if preview_show_continue:
		_show_page_finished()
	else:
		_show_page()
		_waiting_continue = false


func start_dialogue(pages: Array[Dictionary]) -> void:
	if pages.is_empty():
		return
	_is_preview_session = false
	_pages = pages
	_page_index = 0
	is_active = true
	_root.visible = true
	_play_entrance()
	dialogue_started.emit()
	_show_page()
	_queue_layout_refresh()


func close_dialogue() -> void:
	var completed_all := _closing_after_full_read
	_closing_after_full_read = false
	is_active = false
	if not _can_use_editor_preview():
		_root.visible = false
	_pages.clear()
	if completed_all and not _is_preview_session:
		dialogue_completed_fully.emit()
	if not _is_preview_session:
		dialogue_ended.emit()


func cancel_dialogue() -> void:
	if not is_active and not _is_preview_session:
		return
	close_dialogue()


func _configure_dialogue_input() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if not _root.gui_input.is_connected(_on_dialogue_gui_input):
		_root.gui_input.connect(_on_dialogue_gui_input)
	_pass_clicks_to_root(_root)


func _pass_clicks_to_root(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and child != _root:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pass_clicks_to_root(child)


func try_advance() -> void:
	if not is_active:
		return
	if _waiting_continue:
		_next_page()
	elif _visible_chars < _full_text.length():
		_skip_to_end = true
	else:
		_next_page()


func _setup_fonts() -> void:
	if font_body == null:
		font_body = load("res://assets/ui/fonts/eclipse-foundry.ttf") as Font
	if font_speaker == null:
		font_speaker = load("res://assets/ui/fonts/eclipse-foundry.ttf") as Font
	for label: Label in [_speaker_label, _role_label, _body_label, _continue_label]:
		if label == _speaker_label and font_speaker:
			label.add_theme_font_override("font", font_speaker)
		elif font_body:
			label.add_theme_font_override("font", font_body)
	var key_label: Label = _prompt_key.get_node("KeyLabel") as Label
	if key_label and font_body:
		key_label.add_theme_font_override("font", font_body)


func _setup_styles() -> void:
	var portfolio_theme := UITokens.get_theme()
	if portfolio_theme and _root.theme == null:
		_root.theme = portfolio_theme
	_fade.texture = UITokens.make_fade_gradient()
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	if _caret_animator and _caret_animator.has_animation(&"blink"):
		_caret_animator.play(&"blink")


func _play_entrance() -> void:
	_root.modulate.a = 0.0
	_root.position.y = 18.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_root, "modulate:a", 1.0, 0.35)
	tw.tween_property(_root, "position:y", 0.0, 0.35)
	tw.finished.connect(_queue_layout_refresh, CONNECT_ONE_SHOT)


func _on_dialogue_gui_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventScreenTouch:
		if not (event as InputEventScreenTouch).pressed:
			return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
	else:
		return
	try_advance()
	get_viewport().set_input_as_handled()


func _show_page() -> void:
	if _page_index >= _pages.size():
		_closing_after_full_read = true
		close_dialogue()
		return
	var page: Dictionary = _pages[_page_index]
	_speaker_label.text = page.get("speaker", "")
	var role: String = page.get("role", "")
	_role_label.text = role.to_upper()
	_role_label.visible = role != ""
	_role_divider.visible = role != ""
	_full_text = page.get("text", "")
	_visible_chars = 0
	_char_timer = 0.0
	_waiting_continue = false
	_skip_to_end = false
	_body_label.text = ""
	_set_type_cursor_visible(true)
	_continue_row.modulate.a = 0.0
	_continue_row.visible = true
	_update_continue_row()
	_resize_name_tag()


func _show_page_finished() -> void:
	var page: Dictionary = _pages[0] if _pages.size() > 0 else {}
	_speaker_label.text = page.get("speaker", preview_speaker)
	var role: String = page.get("role", preview_role)
	_role_label.text = role.to_upper()
	_role_label.visible = role != ""
	_role_divider.visible = role != ""
	_full_text = page.get("text", preview_line)
	_body_label.text = _full_text
	_set_type_cursor_visible(false)
	_visible_chars = _full_text.length()
	_waiting_continue = true
	_continue_row.modulate.a = 1.0
	_continue_row.visible = true
	_update_continue_row()
	_resize_name_tag()


func _next_page() -> void:
	_page_index += 1
	_show_page()


func _tick_typewriter(delta: float) -> void:
	if _waiting_continue:
		return
	if _visible_chars >= _full_text.length():
		_finish_typing()
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
		_update_body_wrap_height()
		_position_type_cursor()
		if ch != " " and ch != "\n" and _babble:
			_babble.play_blip()
		if ch in [".", "!", "?", ","]:
			_char_timer = PUNCTUATION_PAUSE
		else:
			_char_timer = CHAR_INTERVAL
		if _skip_to_end:
			break

	if _skip_to_end or _visible_chars >= _full_text.length():
		_finish_typing()


func _finish_typing() -> void:
	_body_label.text = _full_text
	_update_body_wrap_height()
	_set_type_cursor_visible(false)
	_waiting_continue = true
	_skip_to_end = false
	var tw := create_tween()
	_continue_row.modulate.a = 0.0
	_continue_row.visible = true
	tw.tween_property(_continue_row, "modulate:a", 1.0, 0.25)
	_update_continue_row()
	_sync_fade_to_content()


func _update_continue_row() -> void:
	var on_last := _page_index >= _pages.size() - 1
	var mobile := _is_mobile_layout()
	if mobile:
		_continue_label.text = "TAP TO CLOSE" if on_last else "TAP TO CONTINUE"
		_prompt_key.visible = false
	else:
		_continue_label.text = "CLOSE" if on_last else "CONTINUE"
		_prompt_key.visible = true


func _is_mobile_layout() -> bool:
	if Engine.is_editor_hint():
		return false
	if is_instance_valid(GameUI) and GameUI.is_mobile_controls():
		return true
	return DisplayServer.is_touchscreen_available()


func _get_canvas_size() -> Vector2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	if size.x < 1.0:
		size = vp.size
	if size.x < 1.0:
		size = Vector2(1280, 720)
	return size


func _get_window_size() -> Vector2:
	var win := get_window()
	if win != null and win.size.x > 0:
		return Vector2(win.size)
	var screen := DisplayServer.window_get_size()
	if screen.x > 0:
		return Vector2(screen)
	return _get_canvas_size()


func _queue_layout_refresh() -> void:
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	if not is_node_ready():
		return

	var canvas_size := _get_canvas_size()
	var window_size := _get_window_size()
	var compact := _is_mobile_layout()
	var h_pad := content_padding_horizontal
	var b_pad := content_padding_bottom
	if compact:
		h_pad = maxi(16, h_pad - 8)
		b_pad = maxi(16, b_pad - 6)

	# Compare max width to the real window (title-bar pixels). Stretch-expand inflates
	# canvas coordinates on tall/narrow windows, so canvas width alone is misleading.
	var window_w := window_size.x
	var canvas_w := canvas_size.x
	var fills_window := content_max_width >= window_w - 0.5
	var block_w := canvas_w if fills_window else minf(content_max_width, canvas_w)
	var inner_w := maxf(120.0, block_w - float(h_pad * 2))
	var text_w := inner_w
	if body_max_width > 0.0 and not fills_window:
		text_w = minf(body_max_width, inner_w)
	_text_column_width = text_w
	_layout_block_w = block_w

	# Full-width gradient band.
	_fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_fade.offset_bottom = 0.0
	_fade.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Full-width host; dialogue column is centered inside it.
	_content_column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_content_column.offset_bottom = 0.0
	_content_column.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_content.add_theme_constant_override("margin_left", h_pad)
	_content.add_theme_constant_override("margin_right", h_pad)
	_content.add_theme_constant_override("margin_bottom", b_pad)
	_content.add_theme_constant_override("margin_top", 0)
	_content.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_content.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_wrap.custom_minimum_size.x = 0.0
	_body_label.custom_minimum_size.x = 0.0
	_body_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body_vbox.offset_left = 0.0
	_body_vbox.offset_top = 0.0
	_body_vbox.offset_right = 0.0
	_body_vbox.offset_bottom = 0.0

	_resize_name_tag()
	_update_body_wrap_height()
	_speaker_label.add_theme_font_size_override("font_size", speaker_font_size + (6 if compact else 0))
	_role_label.add_theme_font_size_override("font_size", role_font_size)
	_body_label.add_theme_font_size_override("font_size", body_font_size + (7 if compact else 0))
	_continue_label.add_theme_font_size_override("font_size", continue_font_size)
	_sync_fade_to_content()


func _request_layout() -> void:
	if is_node_ready():
		_apply_responsive_layout()


func _can_use_editor_preview() -> bool:
	if not Engine.is_editor_hint() or not preview_in_editor:
		return false
	# Autoload is always in the tree; only preview when dialogue_ui.tscn is the active editor tab.
	return is_part_of_edited_scene()


func _update_editor_preview() -> void:
	if not is_node_ready():
		return
	if _can_use_editor_preview():
		_is_preview_session = true
		_root.visible = true
		_apply_responsive_layout()
		_apply_preview_state()
	elif Engine.is_editor_hint() and not is_active:
		_root.visible = false
		_is_preview_session = false


func _resize_name_tag() -> void:
	call_deferred("_resize_name_tag_deferred")


func _set_type_cursor_visible(show_cursor: bool) -> void:
	if _type_cursor:
		_type_cursor.visible = show_cursor
		if show_cursor:
			_position_type_cursor()


func _position_type_cursor() -> void:
	if _type_cursor == null or not _type_cursor.visible:
		return
	var font := _body_label.get_theme_font("font")
	var size := _body_label.get_theme_font_size("font_size")
	if font == null:
		return
	var visible := _body_label.text
	var line_count := visible.count("\n") + 1
	var last_line := visible.get_slice("\n", line_count - 1)
	var x := font.get_string_size(last_line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var line_h := font.get_height(size)
	var cursor_y := _body_vbox.position.y + _body_label.position.y + line_h * float(line_count - 1)
	_type_cursor.position = Vector2(_body_vbox.position.x + x + 3.0, cursor_y)
	_type_cursor.size = Vector2(2.0, float(line_h))


func _update_body_wrap_height() -> void:
	call_deferred("_update_body_wrap_height_deferred")


func _update_body_wrap_height_deferred() -> void:
	if _body_label == null or _body_vbox == null or _name_tag == null:
		return
	var text_w := _text_column_width
	if text_w < 1.0:
		text_w = maxf(120.0, _layout_block_w - float(content_padding_horizontal * 2))
	var font := _body_label.get_theme_font("font")
	var font_size := _body_label.get_theme_font_size("font_size")
	var text_h := 56.0
	if font:
		text_h = font.get_multiline_string_size(
			_body_label.text, HORIZONTAL_ALIGNMENT_LEFT, text_w, font_size, -1
		).y
	var sep := float(_body_vbox.get_theme_constant("separation"))
	var tag_h := _name_tag.custom_minimum_size.y
	if tag_h < 1.0:
		tag_h = _name_tag.size.y
	var block_h := tag_h + sep + text_h
	_body_vbox.custom_minimum_size = Vector2(text_w, block_h)
	_body_wrap.custom_minimum_size.y = block_h
	_sync_fade_to_content()


func _sync_fade_to_content() -> void:
	call_deferred("_sync_fade_to_content_deferred")


func _sync_fade_to_content_deferred() -> void:
	if _fade == null or _content_column == null or _vbox == null:
		return
	var margin_top := float(_content.get_theme_constant("margin_top"))
	var margin_bottom := float(_content.get_theme_constant("margin_bottom"))
	var content_stack_h := _estimate_dialogue_content_height() + margin_top + margin_bottom
	var cover := float(fade_text_cover)
	var fade_h := maxf(FADE_MIN_HEIGHT, content_stack_h + cover)
	var vp_h := get_viewport().get_visible_rect().size.y
	if vp_h > 1.0:
		fade_h = minf(fade_h, vp_h * FADE_MAX_VIEWPORT_RATIO)
	_fade.offset_top = -fade_h
	_content_column.offset_bottom = 0.0
	_content_column.offset_top = -fade_h

	# Dialogue sits on the bottom; extra fade height is gradient above the text only.
	_content.anchor_left = 0.5
	_content.anchor_right = 0.5
	_content.anchor_top = 1.0
	_content.anchor_bottom = 1.0
	_content.offset_left = -_layout_block_w * 0.5
	_content.offset_right = _layout_block_w * 0.5
	_content.offset_top = -content_stack_h
	_content.offset_bottom = 0.0


func _estimate_dialogue_content_height() -> float:
	var body_h := _body_wrap.custom_minimum_size.y
	if body_h < 1.0 and _body_vbox:
		body_h = _body_vbox.custom_minimum_size.y
	var total := body_h
	if _vbox:
		total = maxf(total, _vbox.get_minimum_size().y)
	if _continue_row and _continue_row.visible:
		var outer_sep := float(_vbox.get_theme_constant("separation")) if _vbox else 14.0
		total = maxf(total, body_h + outer_sep + _continue_row.get_minimum_size().y)
	return total


func _resize_name_tag_deferred() -> void:
	var tag_face: Panel = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagFace
	var tag_depth: Panel = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagDepth
	var row: Control = $DialogueRoot/ContentColumn/Content/VBox/BodyWrap/BodyVBox/NameTag/TagFace/TagRow
	if tag_face == null or row == null:
		return
	var pad := Vector2(32, 16)
	var sz := row.get_combined_minimum_size() + pad
	tag_face.custom_minimum_size = sz
	tag_face.size = sz
	var depth_extra := 4.0
	_name_tag.custom_minimum_size = Vector2(sz.x, sz.y + depth_extra)
	if tag_depth:
		tag_depth.position = tag_face.position + Vector2(3, 4)
		tag_depth.size = sz
	_update_body_wrap_height()


func _apply_preview_state() -> void:
	_pages = [{
		"speaker": preview_speaker,
		"role": preview_role,
		"text": preview_line,
	}]
	if preview_show_continue:
		_show_page_finished()
	else:
		_show_page()
