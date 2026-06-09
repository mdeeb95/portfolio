@tool
class_name FloatingProp
extends RigidBody3D

## A single object floating and tumbling in place (e.g. held by a tractor beam).
## Walk into it and it gets knocked off, becoming a normal pushable prop
## (the player's _push_props impulse does the knocking). Push it back into the
## beam column and it magnetically snaps back into place.
##
## In town_square: instance floating_prop.tscn at the hover point, set
## model_scene, and point tractor_beam_path at the beam underneath (optional).

enum State { FLOATING, KNOCKED, RECAPTURING }
enum CollisionFit { BOX, CYLINDER, SPHERE }

const EDITOR_PREVIEW_NAME := "EditorPreview"

@export_group("Model")
@export var model_scene: PackedScene
@export var model_scale: float = 1.0
## Collider auto-fitted to the model's AABB. Box tips and slides; pick Cylinder
## (Y axis) or Sphere for round props that should roll when knocked off.
@export var collision_fit: CollisionFit = CollisionFit.BOX:
	set(value):
		collision_fit = value
		_refit_collision()
## Centers the mesh on the body so the hover point matches the model (Kenney exports are often offset).
@export var auto_center_model: bool = true
## Nudge after auto-center.
@export var model_visual_offset: Vector3 = Vector3.ZERO
@export var disable_model_shadows: bool = true

@export_group("Float")
## Extra up/down bob around the hover point. 0 = hold position (tumble only).
@export_range(0.0, 2.0, 0.01) var hover_bob_amplitude: float = 0.0
@export_range(0.05, 5.0, 0.01) var hover_bob_speed: float = 1.0
## Spring pulling the body to the hover point while floating (per kg).
@export_range(1.0, 200.0, 0.5) var spring_stiffness: float = 25.0
@export_range(0.0, 40.0, 0.1) var spring_damping: float = 4.0

@export_group("Tumble")
@export var tumble_enabled: bool = true
@export var tumble_axis_x: bool = true
@export var tumble_axis_y: bool = true
@export var tumble_axis_z: bool = true
@export_range(0.0, 720.0, 0.1) var tumble_speed_min_deg: float = 20.0
@export_range(0.0, 720.0, 0.1) var tumble_speed_max_deg: float = 90.0

@export_group("Knock")
## Knocked off the beam when pushed this far from the hover point...
@export_range(0.05, 3.0, 0.01) var knock_distance: float = 0.35
## ...or shoved faster than this (m/s). The player's walk-push crosses it in a couple frames.
@export_range(0.05, 10.0, 0.01) var knock_speed: float = 0.5
@export_range(0.0, 4.0, 0.05) var knocked_gravity_scale: float = 1.4
## Respawn floating if the body falls below this global Y.
@export var fall_reset_y: float = -10.0

@export_group("Capture")
## Radius of the beam column (around the hover point's vertical axis) that re-grabs the prop.
@export_range(0.1, 5.0, 0.05) var capture_radius: float = 0.6
## How far below the hover point the column reaches (to the beam base / ground).
@export_range(0.2, 10.0, 0.05) var capture_height: float = 1.6
## Don't grab objects flying through faster than this (m/s).
@export_range(0.2, 20.0, 0.1) var capture_max_speed: float = 3.0
## Grace period after a knock before the beam tries to re-grab.
@export_range(0.0, 10.0, 0.05) var recapture_delay: float = 1.5
## Stronger spring used while pulling the prop back up.
@export_range(1.0, 400.0, 0.5) var snap_stiffness: float = 60.0
@export_range(0.0, 60.0, 0.1) var snap_damping: float = 14.0

@export_group("Beam")
## Optional TractorBeam underneath — dims while the prop is knocked off, flashes on recapture.
@export_node_path("Node3D") var tractor_beam_path: NodePath

@export_group("Confetti")
## Goofy confetti explosion when the beam re-captures the prop. Pieces settle on
## the ground and stay there (single MultiMesh draw call; mobile-friendly).
@export var confetti_enabled: bool = true
@export_range(10, 400, 1) var confetti_count: int = 90
@export_range(1.0, 12.0, 0.1) var confetti_burst_speed: float = 4.5
@export_range(0.02, 0.3, 0.005) var confetti_piece_size: float = 0.07
## The pedestal under the beam has visuals but no collider, so a ground raycast
## shoots straight through it. Pieces landing within this XZ radius of the hover
## axis settle on the tractor beam's base height (the platform top) instead.
@export_range(0.0, 5.0, 0.05) var confetti_platform_radius: float = 1.35

@export_group("Editor Preview")
## Slowly tumble the preview model while editing.
@export var preview_in_editor: bool = true

@onready var _model_holder: Node3D = $ModelHolder
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _state: State = State.FLOATING
var _hover_transform: Transform3D
var _tumble_speeds: Vector3 = Vector3.ZERO
var _knock_timer: float = 0.0
var _bob_time: float = 0.0
var _beam: Node3D
var _editor_preview_key: String = ""

var _confetti_mmi: MultiMeshInstance3D
var _c_pos: PackedVector3Array
var _c_vel: PackedVector3Array
var _c_settle_y: PackedFloat32Array
var _c_phase: PackedFloat32Array
var _c_landed: PackedByteArray
var _c_spin_axis: Array[Vector3] = []
var _c_spin_angle: PackedFloat32Array
var _c_spin_speed: PackedFloat32Array
var _c_airborne: int = 0
var _c_time: float = 0.0
var _c_ground_y: float = 0.0
var _c_platform_y: float = -1000.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_ensure_editor_preview()
		return
	set_process(false)
	_setup_model()
	_hover_transform = global_transform
	_beam = get_node_or_null(tractor_beam_path) as Node3D
	_roll_tumble_speeds()
	_enter_floating(true)


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_clear_editor_preview()
			if _model_holder:
				_model_holder.basis = Basis.IDENTITY
		NOTIFICATION_ENTER_TREE:
			_editor_preview_key = ""


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_ensure_editor_preview()
		if preview_in_editor:
			if _tumble_speeds == Vector3.ZERO:
				_roll_tumble_speeds()
			if _model_holder:
				_model_holder.rotate_x(_tumble_speeds.x * delta * 0.5)
				_model_holder.rotate_y(_tumble_speeds.y * delta * 0.5)
				_model_holder.rotate_z(_tumble_speeds.z * delta * 0.5)
		return
	_confetti_step(delta)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if global_position.y < fall_reset_y:
		_reset_to_hover()
		return
	match _state:
		State.FLOATING:
			_bob_time += delta
			var err: Vector3 = _hover_target() - global_position
			apply_central_force(mass * (spring_stiffness * err - spring_damping * linear_velocity))
			if tumble_enabled:
				angular_velocity = _tumble_speeds
			if err.length() > knock_distance or linear_velocity.length() > knock_speed:
				_enter_knocked()
		State.KNOCKED:
			_knock_timer = maxf(0.0, _knock_timer - delta)
			if _knock_timer <= 0.0 and _is_in_beam_column(global_position) \
					and linear_velocity.length() < capture_max_speed:
				_enter_recapturing()
		State.RECAPTURING:
			var err: Vector3 = _hover_target() - global_position
			apply_central_force(mass * (snap_stiffness * err - snap_damping * linear_velocity))
			if tumble_enabled:
				angular_velocity = angular_velocity.lerp(_tumble_speeds, minf(1.0, 5.0 * delta))
			if err.length() < 0.08 and linear_velocity.length() < 0.4:
				_enter_floating(false)


func _hover_target() -> Vector3:
	return _hover_transform.origin \
			+ Vector3.UP * hover_bob_amplitude * sin(_bob_time * hover_bob_speed * TAU)


func _is_in_beam_column(pos: Vector3) -> bool:
	var hover: Vector3 = _hover_transform.origin
	var xz_dist: float = Vector2(pos.x - hover.x, pos.z - hover.z).length()
	if xz_dist > capture_radius:
		return false
	return pos.y >= hover.y - capture_height and pos.y <= hover.y + 0.3


func _enter_floating(initial: bool) -> void:
	_state = State.FLOATING
	gravity_scale = 0.0
	if not initial:
		_notify_beam(true)
		if _beam and _beam.has_method("pulse_burst"):
			_beam.pulse_burst()
		if confetti_enabled:
			_confetti_burst()


func _enter_knocked() -> void:
	_state = State.KNOCKED
	gravity_scale = knocked_gravity_scale
	_knock_timer = recapture_delay
	_notify_beam(false)


func _enter_recapturing() -> void:
	_state = State.RECAPTURING
	gravity_scale = 0.0


func _notify_beam(held: bool) -> void:
	if _beam and _beam.has_method("set_held"):
		_beam.set_held(held)


func _reset_to_hover() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _hover_transform
	_roll_tumble_speeds()
	_enter_floating(false)


func _roll_tumble_speeds() -> void:
	_tumble_speeds = Vector3.ZERO
	if not tumble_enabled:
		return
	if not tumble_axis_x and not tumble_axis_y and not tumble_axis_z:
		push_warning("FloatingProp: enable at least one tumble axis on %s" % name)
		return
	var min_rad: float = deg_to_rad(minf(tumble_speed_min_deg, tumble_speed_max_deg))
	var max_rad: float = deg_to_rad(maxf(tumble_speed_min_deg, tumble_speed_max_deg))
	if tumble_axis_x:
		_tumble_speeds.x = _random_signed_speed(min_rad, max_rad)
	if tumble_axis_y:
		_tumble_speeds.y = _random_signed_speed(min_rad, max_rad)
	if tumble_axis_z:
		_tumble_speeds.z = _random_signed_speed(min_rad, max_rad)


func _random_signed_speed(min_rad: float, max_rad: float) -> float:
	var magnitude: float = randf_range(min_rad, max_rad)
	return -magnitude if randf() < 0.5 else magnitude


func _setup_model() -> void:
	if _model_holder == null:
		return
	for child: Node in _model_holder.get_children():
		child.queue_free()
	if model_scene == null:
		return
	var model: Node3D = model_scene.instantiate() as Node3D
	if model == null:
		return
	_model_holder.add_child(model)
	_fit_model(model)
	if disable_model_shadows:
		_disable_shadows(model)
	_fit_collision_shape(model)


func _fit_model(model: Node3D) -> void:
	model.scale = Vector3.ONE * model_scale
	if not auto_center_model:
		model.position = model_visual_offset
		return
	model.force_update_transform()
	var mesh_aabb := _combined_mesh_aabb(model)
	if mesh_aabb.size.length_squared() < 0.0001:
		model.position = model_visual_offset
		return
	model.position = -mesh_aabb.get_center() + model_visual_offset


func _refit_collision() -> void:
	if _model_holder == null:
		return
	var model: Node3D = _model_holder.get_node_or_null(EDITOR_PREVIEW_NAME) as Node3D
	if model == null and _model_holder.get_child_count() > 0:
		model = _model_holder.get_child(0) as Node3D
	if model:
		_fit_collision_shape(model)


func _fit_collision_shape(model: Node3D) -> void:
	if _collision_shape == null:
		return
	model.force_update_transform()
	var mesh_aabb := _combined_mesh_aabb(model)
	if mesh_aabb.size.length_squared() < 0.0001:
		return
	var size: Vector3 = mesh_aabb.size
	# Never mutate a resource shared with other placed instances.
	match collision_fit:
		CollisionFit.CYLINDER:
			var cyl := _collision_shape.shape as CylinderShape3D
			if cyl == null or not cyl.resource_local_to_scene:
				cyl = CylinderShape3D.new()
				cyl.resource_local_to_scene = true
				_collision_shape.shape = cyl
			cyl.radius = maxf(size.x, size.z) * 0.5
			cyl.height = size.y
		CollisionFit.SPHERE:
			var sphere := _collision_shape.shape as SphereShape3D
			if sphere == null or not sphere.resource_local_to_scene:
				sphere = SphereShape3D.new()
				sphere.resource_local_to_scene = true
				_collision_shape.shape = sphere
			sphere.radius = (size.x + size.y + size.z) / 6.0
		_:
			var box := _collision_shape.shape as BoxShape3D
			if box == null or not box.resource_local_to_scene:
				box = BoxShape3D.new()
				box.resource_local_to_scene = true
				_collision_shape.shape = box
			box.size = size
	_collision_shape.position = Vector3.ZERO


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


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_shadows(child)


func _ensure_editor_preview() -> void:
	if _model_holder == null:
		_model_holder = get_node_or_null("ModelHolder") as Node3D
		if _model_holder == null:
			return
	var key := _editor_preview_key_str()
	if key == _editor_preview_key and _model_holder.get_node_or_null(EDITOR_PREVIEW_NAME) != null:
		return
	_clear_editor_preview()
	_editor_preview_key = key
	if model_scene == null:
		return
	var model: Node3D = model_scene.instantiate() as Node3D
	if model == null:
		return
	model.name = EDITOR_PREVIEW_NAME
	_model_holder.add_child(model)
	_fit_model(model)
	if disable_model_shadows:
		_disable_shadows(model)
	_fit_collision_shape(model)


func _clear_editor_preview() -> void:
	if _model_holder == null:
		return
	var preview := _model_holder.get_node_or_null(EDITOR_PREVIEW_NAME)
	if preview:
		preview.free()
	_editor_preview_key = ""


func _editor_preview_key_str() -> String:
	var path := model_scene.resource_path if model_scene else ""
	return "|".join([
		path,
		str(snappedf(model_scale, 0.001)),
		str(auto_center_model),
		str(model_visual_offset),
	])


# --- Confetti -----------------------------------------------------------------
# One MultiMesh of opaque, unshaded, vertex-colored quads: a single draw call,
# no particle nodes, no per-piece physics. CPU integration runs only while
# pieces are airborne; landed pieces freeze flat on the ground and persist
# until the next burst reuses the buffer. Built at runtime only, so nothing
# ever serializes into a scene.

func _confetti_setup() -> void:
	if _confetti_mmi != null:
		return
	var mesh := QuadMesh.new()
	mesh.size = Vector2(confetti_piece_size, confetti_piece_size * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = confetti_count
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in confetti_count:
		mm.set_instance_transform(i, hidden)
	_confetti_mmi = MultiMeshInstance3D.new()
	_confetti_mmi.multimesh = mm
	_confetti_mmi.top_level = true
	_confetti_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_confetti_mmi.custom_aabb = AABB(Vector3(-30.0, -20.0, -30.0), Vector3(60.0, 60.0, 60.0))
	add_child(_confetti_mmi)
	_confetti_mmi.global_transform = Transform3D.IDENTITY
	_c_pos.resize(confetti_count)
	_c_vel.resize(confetti_count)
	_c_settle_y.resize(confetti_count)
	_c_phase.resize(confetti_count)
	_c_landed.resize(confetti_count)
	_c_spin_angle.resize(confetti_count)
	_c_spin_speed.resize(confetti_count)
	_c_spin_axis.resize(confetti_count)


func _confetti_burst() -> void:
	_confetti_setup()
	var origin: Vector3 = _hover_transform.origin
	var ground_y: float = origin.y - capture_height
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 20.0, 1)
	var hit := space.intersect_ray(query)
	if hit.has("position"):
		ground_y = (hit["position"] as Vector3).y
	_c_ground_y = ground_y
	_c_platform_y = _beam.global_position.y if _beam else -1000.0
	var mm := _confetti_mmi.multimesh
	for i in confetti_count:
		var radial := randf() * TAU
		var out_speed: float = randf_range(0.4, 1.6)
		_c_pos[i] = origin + Vector3(cos(radial), 0.0, sin(radial)) * randf_range(0.0, 0.3)
		_c_vel[i] = Vector3(
			cos(radial) * out_speed,
			randf_range(0.8, 1.3) * confetti_burst_speed,
			sin(radial) * out_speed)
		_c_settle_y[i] = ground_y + randf_range(0.005, 0.03)
		_c_phase[i] = randf() * TAU
		_c_landed[i] = 0
		_c_spin_axis[i] = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		_c_spin_angle[i] = randf() * TAU
		_c_spin_speed[i] = randf_range(4.0, 12.0)
		mm.set_instance_color(i, Color.from_hsv(randf(), randf_range(0.7, 0.95), 1.0))
	_c_airborne = confetti_count
	_c_time = 0.0
	set_process(true)


func _confetti_step(delta: float) -> void:
	if _c_airborne <= 0:
		set_process(false)
		return
	_c_time += delta
	var mm := _confetti_mmi.multimesh
	for i in confetti_count:
		if _c_landed[i] == 1:
			continue
		var vel: Vector3 = _c_vel[i]
		vel.y -= 9.8 * delta
		vel.y = maxf(vel.y, -2.2)            # paper falls slowly
		vel.x = lerpf(vel.x, 0.0, 1.2 * delta)
		vel.z = lerpf(vel.z, 0.0, 1.2 * delta)
		var pos: Vector3 = _c_pos[i] + vel * delta
		pos.x += sin(_c_time * 5.0 + _c_phase[i]) * 0.35 * delta   # flutter sway
		pos.z += cos(_c_time * 4.3 + _c_phase[i]) * 0.35 * delta
		_c_vel[i] = vel
		var target_y: float = _c_settle_y[i]
		if _c_platform_y > -100.0:
			var hover: Vector3 = _hover_transform.origin
			if Vector2(pos.x - hover.x, pos.z - hover.z).length() < confetti_platform_radius:
				target_y = _c_platform_y + (_c_settle_y[i] - _c_ground_y)
		if pos.y <= target_y and vel.y < 0.0:
			pos.y = target_y
			_c_pos[i] = pos
			_c_landed[i] = 1
			_c_airborne -= 1
			var flat := Basis.from_euler(Vector3(
				-PI * 0.5 + randf_range(-0.12, 0.12),
				randf() * TAU,
				0.0))
			mm.set_instance_transform(i, Transform3D(flat, pos))
			continue
		_c_pos[i] = pos
		_c_spin_angle[i] += _c_spin_speed[i] * delta
		var spin := Basis(_c_spin_axis[i], _c_spin_angle[i])
		mm.set_instance_transform(i, Transform3D(spin, pos))
