@tool
class_name Interactable
extends Area3D

## Walk-up + click/tap target for dialogue.

@export var zone_key: String = ""
@export var display_name: String = "Something"
@export var interact_range: float = 5.5
@export var zone_color: Color = Color.GRAY
@export var face_player_during_dialogue: bool = false
## When false, the full dialogue sequence only plays once per visit (resume zones).
@export var allow_repeat: bool = false
## When false, clicks/taps use proximity focus only (avoids blocking rays to distant zones).
@export var click_to_interact: bool = true

@export_group("Click Hitbox")
## Box size for click/tap raycasts (width, height, depth in meters).
@export var click_hitbox_size: Vector3 = Vector3(4, 6, 4):
	set(value):
		click_hitbox_size = value
		_apply_click_hitbox()
## Local offset of the hitbox center (raise Y to cover floating labels).
@export var click_hitbox_center: Vector3 = Vector3(0, 3, 0):
	set(value):
		click_hitbox_center = value
		_apply_click_hitbox()

const FACE_TURN_SPEED := 12.0

var player_in_range: bool = false

@onready var _name_label: Label3D = get_node_or_null("Label3D") as Label3D
@onready var _assist_label: Label3D = $InteractPrompt

var _dialogue_active: bool = false
var _dialogue_completed: bool = false
var _character_model: Node3D = null


func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 8
	collision_mask = 2
	_update_label()
	_setup_assist_label()
	if _assist_label:
		_assist_label.visible = false
	_character_model = find_child("KenneyCharacter", true, false) as Node3D
	_apply_click_hitbox()


func _physics_process(delta: float) -> void:
	if _dialogue_active and face_player_during_dialogue:
		_face_player(delta)


func _update_label() -> void:
	var label := get_node_or_null("Label3D") as Label3D
	if label and display_name != "":
		label.text = display_name


func _apply_click_hitbox() -> void:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return
	var box := BoxShape3D.new()
	box.size = click_hitbox_size
	collision.shape = box
	collision.position = click_hitbox_center


func get_interact_point() -> Vector3:
	return global_position


func is_player_in_range(player_pos: Vector3) -> bool:
	return player_pos.distance_to(get_interact_point()) <= interact_range


func can_start_dialogue() -> bool:
	return allow_repeat or not _dialogue_completed


func mark_dialogue_completed() -> void:
	if _dialogue_completed:
		return
	_dialogue_completed = true
	if _assist_label:
		_assist_label.visible = false


func set_focused(focused: bool) -> void:
	if _assist_label:
		_assist_label.visible = focused and not Dialogue.is_active and can_start_dialogue()
		if focused and can_start_dialogue():
			_assist_label.text = _get_assist_text()
		_assist_label.modulate = UITokens.PROMPT_FOCUS if focused else UITokens.PROMPT_UNFOCUS
	var label := get_node_or_null("Label3D") as Label3D
	if label:
		label.modulate = Color.WHITE if focused else zone_color


func _setup_assist_label() -> void:
	if _assist_label == null:
		return
	var name_font_size := _name_label.font_size if _name_label else 40
	_assist_label.font_size = 28 if name_font_size >= 44 else 22
	_assist_label.outline_size = 5
	_assist_label.modulate = UITokens.PROMPT_UNFOCUS
	_assist_label.text = _get_assist_text()
	if _name_label:
		_name_label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_BOTTOM
		_assist_label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_BOTTOM
		_assist_label.position = _name_label.position + Vector3(0, -0.45, 0)


func _get_assist_text() -> String:
	if DisplayServer.is_touchscreen_available():
		return "TAP %s" % display_name.to_upper()
	return "CLICK %s  ·  E" % display_name.to_upper()


func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active
	var character := find_child("KenneyCharacter", true, false) as CharacterAnimator
	if character:
		character.set_talking(active)


func _face_player(delta: float) -> void:
	if _character_model == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - _character_model.global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return
	var target_y := atan2(to_player.x, to_player.z)
	_character_model.rotation.y = lerp_angle(
		_character_model.rotation.y,
		target_y,
		FACE_TURN_SPEED * delta,
	)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_focused(false)
