@tool
extends Node
## Applies metallic floor materials in editor + game.
## Edit **Floor Material** for the main grid; optional **Panel Accent** for floor-panel pieces only.

@export var floor_material: StandardMaterial3D
@export var panel_accent_material: StandardMaterial3D
@export var apply_to_decorations: bool = true
@export var preview_in_editor: bool = true


func _ready() -> void:
	_queue_apply()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_queue_apply()


func _queue_apply() -> void:
	if not preview_in_editor and Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	call_deferred(&"_apply_all")


func _apply_all() -> void:
	if not is_inside_tree():
		return

	var floor_mat: StandardMaterial3D = floor_material
	if floor_mat == null:
		floor_mat = load("res://resources/materials/space_station_floor_deck.tres") as StandardMaterial3D

	var panel_mat: StandardMaterial3D = panel_accent_material if panel_accent_material else floor_mat
	if panel_mat == null:
		panel_mat = load("res://resources/materials/space_station_floor_panel.tres") as StandardMaterial3D

	if floor_mat == null:
		return

	var env := get_parent()
	if env == null:
		return

	var floor_root := env.get_node_or_null("Floor") as Node3D
	if floor_root:
		for child: Node in floor_root.get_children():
			if child is Node3D:
				_apply_under(child as Node3D, floor_mat, panel_mat)

	if apply_to_decorations:
		var deco := env.get_node_or_null("Decorations") as Node3D
		if deco:
			for child: Node in deco.get_children():
				if _is_panel_name(child.name) and child is Node3D:
					_apply_under(child as Node3D, floor_mat, panel_mat)


func _apply_under(root: Node3D, floor_mat: StandardMaterial3D, panel_mat: StandardMaterial3D) -> void:
	var use_mat: StandardMaterial3D = panel_mat if _is_panel_name(root.name) else floor_mat
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var surface_mat: StandardMaterial3D = panel_mat if _is_panel_name(mi.name) or _is_panel_name(root.name) else floor_mat
		for surface_idx: int in mi.mesh.get_surface_count():
			mi.set_surface_override_material(surface_idx, surface_mat)


func _is_panel_name(node_name: String) -> bool:
	return node_name.to_lower().contains("floor-panel")
