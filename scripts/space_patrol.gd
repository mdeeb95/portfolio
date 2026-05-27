@tool
extends Node3D

## Fly-by along waypoints (Spawn → Exit). Can loop, despawn, or stop when done.
##
## In town_square: Scene → Instantiate Child Scene → space_ship_patrol.tscn
## (or add SpaceShipPatrol node). Make editable children, add Marker3D under Waypoints.

const EDITOR_PREVIEW_NAME := "EditorPreview"

@export_group("Ship")
@export var craft_scene: PackedScene
@export var ship_scale: float = 2.2
## Centers the FBX mesh on Ship so the editor box matches the model (Kenney exports are often offset).
@export var auto_center_craft: bool = true
## Nudge after auto-center — use if the mesh still sits off the Spawn handle.
@export var craft_visual_offset: Vector3 = Vector3.ZERO
## Applied after auto-aiming at Exit. Tweak if the model's mesh forward isn't -Z (e.g. (0, 180, 0)).
@export var model_rotation_fix_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)

@export_group("Movement")
@export var speed: float = 18.0
@export var start_delay: float = 0.0
@export var loop: bool = false
@export var respawn_delay: float = 3.0
@export var destroy_when_finished: bool = true

@export_group("Editor Preview")
## Run the full patrol path while editing the scene (no F5 required).
@export var preview_patrol_in_editor: bool = true

@export_group("Route")
@export_node_path("Node3D") var waypoints_root: NodePath = NodePath("Waypoints")
@export_node_path("Node3D") var ship_path: NodePath = NodePath("Waypoints/Spawn/Ship")

@export_group("Tumble Spin")
@export var random_spin_enabled: bool = false
@export var spin_axis_x: bool = false
@export var spin_axis_y: bool = false
@export var spin_axis_z: bool = true
@export_range(0.0, 720.0, 0.1) var spin_speed_min_deg: float = 20.0
@export_range(0.0, 720.0, 0.1) var spin_speed_max_deg: float = 120.0

var _ship: Node3D
var _points: PackedVector3Array = PackedVector3Array()
var _segment_index: int = 0
var _segment_t: float = 0.0
var _rotation_fix: Basis = Basis.IDENTITY
var _active: bool = false
var _finished: bool = false
var _editor_preview_key: String = ""
var _editor_preview_dirty: bool = true
var _spin_config_key: String = ""
var _spin_speeds: Vector3 = Vector3.ZERO
var _spin_angles: Vector3 = Vector3.ZERO
var _editor_respawn_timer: float = 0.0
var _editor_start_delay_left: float = 0.0
var _preview_patrol_enabled_last: bool = true


func _ready() -> void:
	_cache_ship()
	_apply_rotation_fix()
	_sync_spin_config()
	if Engine.is_editor_hint():
		set_process(true)
		_preview_patrol_enabled_last = preview_patrol_in_editor
		_ensure_editor_preview()
		if preview_patrol_in_editor:
			_begin_patrol_run()
		else:
			_update_editor_spawn_pose(0.0)
		return
	_clear_editor_preview()
	_setup_craft()
	_reload_waypoints()
	if _points.size() < 2:
		push_warning("SpaceShipPatrol: need at least two Marker3D nodes under Waypoints on %s" % name)
		return
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	_begin_patrol_run()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_clear_editor_preview()
		NOTIFICATION_ENTER_TREE:
			_editor_preview_dirty = true


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_process_editor(delta)
		return
	_step_patrol(delta)


func _process_editor(delta: float) -> void:
	var preview_key := _editor_preview_key_str()
	if preview_key != _editor_preview_key or _editor_preview_dirty:
		_editor_preview_dirty = true
		_ensure_editor_preview()
		_active = false
		_editor_respawn_timer = 0.0
	_sync_spin_config()
	if preview_patrol_in_editor != _preview_patrol_enabled_last:
		_preview_patrol_enabled_last = preview_patrol_in_editor
		_active = false
		_editor_respawn_timer = 0.0
		if preview_patrol_in_editor:
			_begin_patrol_run()
		else:
			_update_editor_spawn_pose(0.0)
		return
	if not preview_patrol_in_editor:
		_update_editor_spawn_pose(delta)
		return
	if _editor_respawn_timer > 0.0:
		_editor_respawn_timer = maxf(0.0, _editor_respawn_timer - delta)
		if _editor_respawn_timer <= 0.0:
			_begin_patrol_run()
		return
	if _editor_start_delay_left > 0.0:
		_editor_start_delay_left = maxf(0.0, _editor_start_delay_left - delta)
		if _editor_start_delay_left <= 0.0:
			_active = true
		return
	_reload_waypoints()
	if _points.size() < 2:
		return
	if not _active:
		_begin_patrol_run()
	_step_patrol(delta)


func _step_patrol(delta: float) -> void:
	if not _active or _finished or _points.size() < 2 or _ship == null:
		return
	_reload_waypoints()
	if _points.size() < 2:
		return
	var from: Vector3 = _points[_segment_index]
	var to: Vector3 = _points[_segment_index + 1]
	var segment_length: float = from.distance_to(to)
	if segment_length < 0.01:
		_advance_segment()
		return
	_segment_t += delta * speed / segment_length
	if _segment_t >= 1.0:
		_advance_segment()
		return
	_ship.global_position = from.lerp(to, _segment_t)
	_accumulate_spin(delta)
	_face_exit()


func _cache_ship() -> void:
	_ship = get_node_or_null(ship_path) as Node3D
	if _ship == null:
		_ship = get_node_or_null("Waypoints/Spawn/Ship") as Node3D
	if _ship == null:
		_ship = get_node_or_null("Ship") as Node3D
	if _ship == null:
		push_warning("SpaceShipPatrol: add Node3D Ship under the Spawn marker (%s)" % ship_path)


func _apply_rotation_fix() -> void:
	_rotation_fix = Basis.from_euler(model_rotation_fix_degrees * (PI / 180.0))


func _get_exit_position() -> Vector3:
	return _points[_points.size() - 1]


func _face_exit() -> void:
	if _ship == null or _points.size() < 2:
		return
	var target: Vector3 = _get_exit_position()
	var forward: Vector3 = target - _ship.global_position
	if forward.length_squared() < 0.0001:
		return
	var ship_basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	ship_basis = ship_basis * _rotation_fix
	if random_spin_enabled:
		ship_basis = ship_basis * Basis.from_euler(_spin_angles)
	_ship.global_transform = Transform3D(ship_basis, _ship.global_position)


func _sync_spin_config() -> void:
	var key := _spin_config_key_str()
	if key == _spin_config_key:
		return
	_spin_config_key = key
	_spin_angles = Vector3.ZERO
	_roll_spin_speeds()


func _spin_config_key_str() -> String:
	# Avoid % formatting with bools — it spams "a number is required" in the editor.
	return "|".join([
		str(random_spin_enabled),
		str(spin_axis_x),
		str(spin_axis_y),
		str(spin_axis_z),
		str(snappedf(spin_speed_min_deg, 0.01)),
		str(snappedf(spin_speed_max_deg, 0.01)),
	])


func _roll_spin_speeds() -> void:
	_spin_speeds = Vector3.ZERO
	if not random_spin_enabled:
		return
	if not spin_axis_x and not spin_axis_y and not spin_axis_z:
		push_warning("SpaceShipPatrol: enable at least one spin axis on %s" % name)
		return
	var min_rad: float = deg_to_rad(minf(spin_speed_min_deg, spin_speed_max_deg))
	var max_rad: float = deg_to_rad(maxf(spin_speed_min_deg, spin_speed_max_deg))
	if spin_axis_x:
		_spin_speeds.x = _random_signed_speed(min_rad, max_rad)
	if spin_axis_y:
		_spin_speeds.y = _random_signed_speed(min_rad, max_rad)
	if spin_axis_z:
		_spin_speeds.z = _random_signed_speed(min_rad, max_rad)


func _random_signed_speed(min_rad: float, max_rad: float) -> float:
	var magnitude: float = randf_range(min_rad, max_rad)
	return -magnitude if randf() < 0.5 else magnitude


func _accumulate_spin(delta: float) -> void:
	if not random_spin_enabled:
		return
	if spin_axis_x:
		_spin_angles.x += _spin_speeds.x * delta
	if spin_axis_y:
		_spin_angles.y += _spin_speeds.y * delta
	if spin_axis_z:
		_spin_angles.z += _spin_speeds.z * delta


func _ensure_editor_preview() -> void:
	if _ship == null:
		return
	var key := _editor_preview_key_str()
	if not _editor_preview_dirty and key == _editor_preview_key:
		var existing := _ship.get_node_or_null(EDITOR_PREVIEW_NAME)
		if existing != null:
			return
	_clear_editor_preview()
	_editor_preview_key = key
	_editor_preview_dirty = false
	if craft_scene == null:
		return
	var model: Node3D = craft_scene.instantiate() as Node3D
	if model == null:
		return
	model.name = EDITOR_PREVIEW_NAME
	_ship.add_child(model)
	_fit_craft_to_ship_origin(model)
	_disable_shadows(model)


func _clear_editor_preview() -> void:
	if _ship == null:
		return
	var preview := _ship.get_node_or_null(EDITOR_PREVIEW_NAME)
	if preview:
		preview.free()
	_editor_preview_key = ""


func _editor_preview_key_str() -> String:
	var path := craft_scene.resource_path if craft_scene else ""
	return "|".join([
		path,
		str(snappedf(ship_scale, 0.001)),
		str(auto_center_craft),
		str(craft_visual_offset),
		str(snappedf(model_rotation_fix_degrees.x, 0.001)),
		str(snappedf(model_rotation_fix_degrees.y, 0.001)),
		str(snappedf(model_rotation_fix_degrees.z, 0.001)),
	])


func _update_editor_spawn_pose(delta: float) -> void:
	if _ship == null:
		return
	_reload_waypoints()
	if _points.is_empty():
		return
	_reset_ship_to_spawn_local()
	_apply_rotation_fix()
	_accumulate_spin(delta)
	_face_exit()


func _setup_craft() -> void:
	if _ship == null:
		return
	for child: Node in _ship.get_children():
		child.queue_free()
	if craft_scene == null:
		return
	var model: Node3D = craft_scene.instantiate() as Node3D
	if model == null:
		return
	_ship.add_child(model)
	_fit_craft_to_ship_origin(model)
	_disable_shadows(model)


func _fit_craft_to_ship_origin(model: Node3D) -> void:
	model.scale = Vector3.ONE * ship_scale
	if not auto_center_craft:
		model.position = craft_visual_offset
		return
	model.force_update_transform()
	var mesh_aabb := _combined_mesh_aabb(model)
	if mesh_aabb.size.length_squared() < 0.0001:
		model.position = craft_visual_offset
		return
	model.position = -mesh_aabb.get_center() + craft_visual_offset


func _combined_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var to_root: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var piece: AABB = to_root * mi.mesh.get_aabb()
		if not found:
			result = piece
			found = true
		else:
			result = result.merge(piece)
	return result


func _reload_waypoints() -> void:
	_points.clear()
	var root: Node = get_node_or_null(waypoints_root)
	if root == null:
		return
	for child: Node in root.get_children():
		if child is Marker3D:
			_points.append((child as Marker3D).global_position)


func _reset_ship_to_spawn_local() -> void:
	if _ship == null:
		return
	_ship.position = Vector3.ZERO
	_ship.basis = Basis.IDENTITY


func _advance_segment() -> void:
	if _segment_index + 1 >= _points.size() - 1:
		_ship.global_position = _points[_points.size() - 1]
		_finish()
		return
	_segment_index += 1
	_segment_t = 0.0


func _begin_patrol_run() -> void:
	_reload_waypoints()
	if _points.size() < 2:
		return
	_segment_index = 0
	_segment_t = 0.0
	_finished = false
	_spin_angles = Vector3.ZERO
	if _ship:
		_ship.visible = true
		_reset_ship_to_spawn_local()
		_face_exit()
	if Engine.is_editor_hint() and start_delay > 0.0:
		_editor_start_delay_left = start_delay
		_active = false
	else:
		_active = true


func _finish() -> void:
	_active = false
	if Engine.is_editor_hint():
		if not preview_patrol_in_editor:
			return
		if _ship:
			_ship.visible = false
		if loop or respawn_delay > 0.0:
			_editor_respawn_timer = respawn_delay if respawn_delay > 0.0 else 0.05
		else:
			_begin_patrol_run()
		return
	if loop:
		if _ship:
			_ship.visible = false
		_run_respawn_cycle()
		return
	_finished = true
	if destroy_when_finished:
		queue_free()


func _run_respawn_cycle() -> void:
	if respawn_delay > 0.0:
		await get_tree().create_timer(respawn_delay).timeout
	if not is_inside_tree():
		return
	_begin_patrol_run()


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)
