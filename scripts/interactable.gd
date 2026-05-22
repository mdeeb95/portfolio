class_name Interactable
extends Area3D

## Walk-up + click/tap target for dialogue.

@export var zone_key: String = ""
@export var display_name: String = "Something"
@export var interact_range: float = 5.5
@export var zone_color: Color = Color.GRAY

var player_in_range: bool = false

@onready var _prompt: Label3D = $InteractPrompt


func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 8
	collision_mask = 2
	_update_label()
	if _prompt:
		_prompt.visible = false


func _update_label() -> void:
	var label := get_node_or_null("Label3D") as Label3D
	if label and display_name != "":
		label.text = display_name


func get_interact_point() -> Vector3:
	return global_position


func is_player_in_range(player_pos: Vector3) -> bool:
	return player_pos.distance_to(get_interact_point()) <= interact_range


func set_focused(focused: bool) -> void:
	if _prompt:
		_prompt.visible = focused and not Dialogue.is_active
	var label := get_node_or_null("Label3D") as Label3D
	if label:
		label.modulate = Color.WHITE if focused else zone_color


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		set_focused(false)
