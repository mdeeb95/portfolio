class_name AssetPlacer
extends RefCounted

var preview_node: Node3D
var preview_aabb: AABB
var node_history: Array[String] = []
var preview_rids = []
var asset: AssetResource
var preview_transform_step: float = 0.1
var preview_rotate_step: float = 5
var undo_redo: EditorUndoRedoManager
var meta_asset_id = &"asset_placer_res_id"
var preview_material = load("res://addons/asset_placer/utils/preview_material.tres")

var _is_node_transform_mode: bool = false
var _original_transform: Transform3D
var _strategy: AssetPlacementStrategy
var _fill_preview_nodes: Array[Node3D] = []
var _fill_dragging: bool = false
var _fill_start_world: Vector3
var _fill_end_world: Vector3
var _preview_root: Window
var _presenter: AssetPlacerPresenter:
	get:
		return AssetPlacerPresenter._instance


func _init(undo_redo: EditorUndoRedoManager):
	self.undo_redo = undo_redo


func start_placement(root: Window, asset: AssetResource, placement: GapPlacementMode):
	stop_placement()
	self.asset = asset
	_is_node_transform_mode = false
	_preview_root = root
	preview_node = _instantiate_asset_resource(asset)
	root.add_child(preview_node)
	preview_rids = get_collision_rids(preview_node)
	set_placement_mode(placement)
	_apply_preview_material(preview_node)
	var scene = EditorInterface.get_selection().get_selected_nodes()[0]
	if scene is Node3D:
		AssetTransformations.apply_transforms(preview_node, AssetPlacerPresenter._instance.options)
		self.preview_aabb = AABBProvider.provide_aabb(preview_node)


func start_node_transform(node: Node3D, placement: GapPlacementMode):
	stop_placement()
	_is_node_transform_mode = true
	preview_node = node
	_original_transform = node.global_transform
	preview_rids = get_collision_rids(preview_node)
	set_placement_mode(placement)
	self.preview_aabb = AABBProvider.provide_aabb(preview_node)


func _apply_preview_material(node: Node3D):
	if not preview_material:
		return
	if node is MeshInstance3D:
		for i in node.get_surface_override_material_count():
			node.set_surface_override_material(i, preview_material)

	for child in node.get_children():
		if child is MeshInstance3D:
			for i in child.get_surface_override_material_count():
				child.set_surface_override_material(i, preview_material)
		_apply_preview_material(child)


func move_preview(mouse_position: Vector2, camera: Camera3D) -> bool:
	if preview_node and _fill_dragging:
		return false
	if preview_node:
		var hit = _strategy.get_placement_point(camera, mouse_position)
		preview_node.global_transform = _build_placement_transform(hit.position, hit.normal)
		return true
	else:
		return false


func is_grid_fill_mode() -> bool:
	return _presenter.placement_mode is GapPlacementMode.GridFillPlacement


func begin_grid_fill(camera: Camera3D, mouse_position: Vector2) -> bool:
	if not preview_node or not is_grid_fill_mode():
		return false
	var hit = _strategy.get_placement_point(camera, mouse_position)
	_fill_dragging = true
	_fill_start_world = hit.position
	_fill_end_world = hit.position
	preview_node.hide()
	update_grid_fill(camera, mouse_position)
	return true


func update_grid_fill(camera: Camera3D, mouse_position: Vector2) -> bool:
	if not _fill_dragging or not preview_node:
		return false
	var hit = _strategy.get_placement_point(camera, mouse_position)
	_fill_end_world = hit.position
	var normal := _placement_normal_from_hit(hit)
	var transforms := _compute_fill_transforms(_fill_start_world, _fill_end_world, normal)
	_sync_fill_previews(transforms)
	return true


func commit_grid_fill(focus_on_placement: bool) -> bool:
	if not _fill_dragging or not preview_node:
		return false
	_fill_dragging = false
	var normal := Vector3.UP
	if _presenter.placement_mode is GapPlacementMode.GridFillPlacement:
		normal = _presenter.placement_mode.plane_options.normal
	var transforms := _compute_fill_transforms(_fill_start_world, _fill_end_world, normal)
	_clear_fill_previews()
	preview_node.show()
	if transforms.is_empty():
		return false
	_place_batch(transforms, focus_on_placement)
	return true


func cancel_grid_fill() -> void:
	_fill_dragging = false
	_clear_fill_previews()
	if preview_node:
		preview_node.show()


func _build_placement_transform(hit_pos: Vector3, normal: Vector3, skip_snap: bool = false) -> Transform3D:
	var n := normal
	if _presenter.options.align_normals:
		n = normal.normalized()
	else:
		n = Vector3.UP

	var snapped_pos := hit_pos if skip_snap else _snap_position(hit_pos, n)
	if _strategy is Terrain3DAssetPlacementStrategy:
		snapped_pos.y = _strategy.terrain_3d_node.data.get_height(snapped_pos)

	var forward_hint := preview_node.global_transform.basis.z
	var new_basis := get_safe_basis(n, forward_hint).scaled(preview_node.scale)
	var new_transform := Transform3D(new_basis, snapped_pos)

	var local_bottom := Vector3(0, preview_aabb.position.y, 0)
	if _presenter.options.use_asset_origin:
		local_bottom = Vector3.ZERO

	var bottom_world := new_transform * local_bottom
	new_transform.origin += snapped_pos - bottom_world
	return new_transform


func _compute_fill_transforms(start_pos: Vector3, end_pos: Vector3, normal: Vector3) -> Array[Transform3D]:
	var n := normal.normalized()
	var tangent := Vector3.UP.cross(n).normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.cross(n).normalized()
	var bitangent := n.cross(tangent).normalized()
	var steps := _get_fill_cell_steps(n)
	var step_t: float = steps.x
	var step_b: float = steps.y

	var start_snapped := _snap_to_cell_grid(start_pos, n, step_t, step_b)
	var end_snapped := _snap_to_cell_grid(end_pos, n, step_t, step_b)

	var start_t := tangent.dot(start_snapped)
	var start_b := bitangent.dot(start_snapped)
	var end_t := tangent.dot(end_snapped)
	var end_b := bitangent.dot(end_snapped)

	var min_t := minf(start_t, end_t)
	var max_t := maxf(start_t, end_t)
	var min_b := minf(start_b, end_b)
	var max_b := maxf(start_b, end_b)
	var height := n.dot(start_snapped)

	var transforms: Array[Transform3D] = []
	var t := min_t
	while t <= max_t + step_t * 0.001:
		var b := min_b
		while b <= max_b + step_b * 0.001:
			var pos := tangent * t + bitangent * b + n * height
			transforms.append(_build_placement_transform(pos, n, true))
			b += step_b
		t += step_t
	return transforms


func _get_fill_cell_steps(normal: Vector3) -> Vector2:
	var n := normal.normalized()
	var tangent := Vector3.UP.cross(n).normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.cross(n).normalized()
	var bitangent := n.cross(tangent).normalized()
	var size := preview_aabb.size
	var step_t: float = (
		float(abs(tangent.x)) * size.x
		+ float(abs(tangent.y)) * size.y
		+ float(abs(tangent.z)) * size.z
	)
	var step_b: float = (
		float(abs(bitangent.x)) * size.x
		+ float(abs(bitangent.y)) * size.y
		+ float(abs(bitangent.z)) * size.z
	)
	return Vector2(maxf(step_t, 0.01), maxf(step_b, 0.01))


func _get_cell_step(normal: Vector3) -> float:
	if is_grid_fill_mode():
		var steps := _get_fill_cell_steps(normal)
		return maxf(steps.x, steps.y)
	if _presenter.options.snapping_enabled:
		return _presenter.options.snapping_grid_step
	var n := normal.normalized()
	var tangent := Vector3.UP.cross(n).normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.cross(n).normalized()
	var bitangent := n.cross(tangent).normalized()
	var size := preview_aabb.size
	var along_t: float = float(abs(tangent.x)) * size.x + float(abs(tangent.y)) * size.y + float(abs(tangent.z)) * size.z
	var along_b: float = float(abs(bitangent.x)) * size.x + float(abs(bitangent.y)) * size.y + float(abs(bitangent.z)) * size.z
	return maxf(maxf(along_t, along_b), 0.1)


func _placement_normal_from_hit(hit: AssetPlacementStrategy.CollisionHit) -> Vector3:
	if _presenter.options.align_normals:
		return hit.normal
	if _presenter.placement_mode is GapPlacementMode.GridFillPlacement:
		return _presenter.placement_mode.plane_options.normal
	return Vector3.UP


func _sync_fill_previews(transforms: Array[Transform3D]) -> void:
	while _fill_preview_nodes.size() < transforms.size():
		var dup := _instantiate_asset_resource(asset)
		_apply_preview_material(dup)
		_preview_root.add_child(dup)
		_fill_preview_nodes.append(dup)
	for i: int in transforms.size():
		_fill_preview_nodes[i].global_transform = transforms[i]
		_fill_preview_nodes[i].show()
	for i: int in range(transforms.size(), _fill_preview_nodes.size()):
		_fill_preview_nodes[i].hide()


func _clear_fill_previews() -> void:
	for node: Node3D in _fill_preview_nodes:
		node.queue_free()
	_fill_preview_nodes.clear()


func place_asset(focus_on_placement: bool):
	if preview_node:
		if _is_node_transform_mode:
			_confirm_node_transform()
			return true
		else:
			_place_instance(preview_node.global_transform, focus_on_placement)
			return true
	else:
		return false


func set_plugin_settings(settings: AssetPlacerSettings):
	preview_rotate_step = settings.rotation_step
	preview_transform_step = settings.transform_step
	if settings.preview_material_resource.is_empty():
		preview_material = null
	else:
		preview_material = load(settings.preview_material_resource)


func transform_preview(
	mode: AssetPlacerPresenter.TransformMode, axis: Vector3, direction: int
) -> bool:
	if not preview_node:
		return false

	match mode:
		AssetPlacerPresenter.TransformMode.None:
			return false
		AssetPlacerPresenter.TransformMode.Scale:
			var factor := 1.0 + preview_transform_step * direction
			var min_scale := 0.01
			var new_scale := preview_node.scale
			if axis.x != 0:
				new_scale.x = max(preview_node.scale.x * factor, min_scale)
			if axis.y != 0:
				new_scale.y = max(preview_node.scale.y * factor, min_scale)
			if axis.z != 0:
				new_scale.z = max(preview_node.scale.z * factor, min_scale)
			preview_node.scale = new_scale
			return true
		AssetPlacerPresenter.TransformMode.Rotate:
			# Can be replaced with deg_to_rad(preview_transform_step) however 0.1 deg is low.
			preview_node.rotate(axis.normalized() * direction, deg_to_rad(preview_rotate_step))
			return true

		AssetPlacerPresenter.TransformMode.Move:
			_presenter.move_plane_up(direction)
			return true
		_:
			return false


func get_collision_rids(node: Node) -> Array:
	var rids = []
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child in node.get_children():
		rids += get_collision_rids(child)
	return rids


func _snap_position(hit_pos: Vector3, normal: Vector3) -> Vector3:
	if !AssetPlacerPresenter._instance.options.snapping_enabled:
		return hit_pos

	var grid_step: float = AssetPlacerPresenter._instance.options.snapping_grid_step

	# Build tangent basis aligned to the surface normal
	var n := normal.normalized()
	var tangent := Vector3.UP.cross(n).normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.cross(n).normalized()
	var bitangent := n.cross(tangent).normalized()

	var local_tangent := tangent.dot(hit_pos)
	var local_bitangent := bitangent.dot(hit_pos)
	var local_height := n.dot(hit_pos)

	var snapped_tangent = round(local_tangent / grid_step) * grid_step
	var snapped_bitangent = round(local_bitangent / grid_step) * grid_step

	var snapped = tangent * snapped_tangent + bitangent * snapped_bitangent + n * local_height

	return snapped


func _snap_to_cell_grid(hit_pos: Vector3, normal: Vector3, step_t: float, step_b: float) -> Vector3:
	var n := normal.normalized()
	var tangent := Vector3.UP.cross(n).normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.cross(n).normalized()
	var bitangent := n.cross(tangent).normalized()

	var local_tangent: float = tangent.dot(hit_pos)
	var local_bitangent: float = bitangent.dot(hit_pos)
	var local_height: float = n.dot(hit_pos)

	var snapped_tangent: float = snapped(local_tangent, step_t)
	var snapped_bitangent: float = snapped(local_bitangent, step_b)

	return tangent * snapped_tangent + bitangent * snapped_bitangent + n * local_height


func _place_instance(transform: Transform3D, select_after_placement: bool):
	var scene := EditorInterface.get_edited_scene_root()
	var scene_root := scene.get_node(AssetPlacerPresenter._instance._parent)
	var options := AssetPlacerPresenter._instance.options
	var parent := AssetParentSelector.pick_parent(scene_root, asset, options.group_automatically)

	if is_instance_valid(parent) and is_instance_valid(asset.get_resource()):
		undo_redo.create_action("Place Asset: %s" % asset.name)
		undo_redo.add_do_method(self, "_do_placement", parent, transform, select_after_placement)
		undo_redo.add_undo_method(self, "_undo_placement", parent)
		undo_redo.commit_action()
		AssetTransformations.apply_transforms(preview_node, AssetPlacerPresenter._instance.options)
		_presenter.on_asset_placed()


func _place_batch(transforms: Array[Transform3D], select_after_placement: bool) -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var scene_root := scene.get_node(AssetPlacerPresenter._instance._parent)
	var options := AssetPlacerPresenter._instance.options
	var parent := AssetParentSelector.pick_parent(scene_root, asset, options.group_automatically)

	if not is_instance_valid(parent) or not is_instance_valid(asset.get_resource()):
		return

	undo_redo.create_action("Fill Grid: %d × %s" % [transforms.size(), asset.name])
	undo_redo.add_do_method(self, "_do_batch_placement", parent, transforms, select_after_placement)
	undo_redo.add_undo_method(self, "_undo_batch_placement", parent, transforms.size())
	undo_redo.commit_action()
	AssetTransformations.apply_transforms(preview_node, AssetPlacerPresenter._instance.options)
	_presenter.on_asset_placed()


func _do_batch_placement(root: Node3D, transforms: Array, select_after_placement: bool) -> void:
	var last_node: Node3D = null
	for transform: Transform3D in transforms:
		last_node = _do_placement(root, transform, false)
	if select_after_placement and last_node:
		AssetPlacerPresenter._instance.clear_selection()
		EditorInterface.edit_node(last_node)


func _undo_batch_placement(root: Node3D, count: int) -> void:
	for _i: int in count:
		_undo_placement(root)


func _do_placement(root: Node3D, transform: Transform3D, select_after_placement: bool) -> Node3D:
	var new_node: Node3D = _instantiate_asset_resource(asset)
	new_node.global_transform = transform
	new_node.transform = root.global_transform.affine_inverse() * transform
	new_node.set_meta(meta_asset_id, asset.id)
	new_node.name = _pick_name(new_node, root)
	root.add_child(new_node)
	new_node.owner = EditorInterface.get_edited_scene_root()
	node_history.push_front(new_node.name)
	if select_after_placement:
		AssetPlacerPresenter._instance.clear_selection()
		EditorInterface.edit_node(new_node)
	return new_node


func _undo_placement(root: Node3D):
	var last_added = node_history.pop_front()
	var children = root.get_children()
	var node_index = -1
	for a in root.get_child_count():
		if children[a].name == last_added:
			node_index = a
			break
	var node = root.get_child(node_index)
	node.queue_free()


func _confirm_node_transform():
	if _is_node_transform_mode and preview_node:
		# Create undo action for the node transformation
		undo_redo.create_action("Transform Node: %s" % preview_node.name)
		undo_redo.add_do_method(
			self, "_do_node_transform", preview_node, preview_node.global_transform
		)
		undo_redo.add_undo_method(self, "_undo_node_transform", preview_node, _original_transform)
		undo_redo.commit_action()

		# Exit node transform mode
		_presenter.end_node_transform_mode()
		stop_placement()


func _do_node_transform(node: Node3D, new_transform: Transform3D):
	node.global_transform = new_transform


func _undo_node_transform(node: Node3D, original_transform: Transform3D):
	node.global_transform = original_transform


func stop_placement():
	self.asset = null
	var was_node_transform_mode = _is_node_transform_mode
	_is_node_transform_mode = false
	_fill_dragging = false
	_clear_fill_previews()
	if preview_node and not was_node_transform_mode:
		preview_node.queue_free()
	preview_node = null


func _instantiate_asset_resource(asset: AssetResource) -> Node3D:
	var new_node: Node3D
	var resource := asset.get_resource()
	if resource is PackedScene:
		new_node = (resource.instantiate() as Node3D)
	elif resource is ArrayMesh:
		new_node = MeshInstance3D.new()
		new_node.name = asset.name
		new_node.mesh = resource.duplicate()
	else:
		push_error("Not supported resource type %s" % str(resource))

	return new_node


func set_placement_mode(placement_mode: GapPlacementMode):
	if placement_mode is GapPlacementMode.SurfacePlacement:
		_strategy = SurfaceAssetPlacementStrategy.new(preview_rids)
	elif placement_mode is GapPlacementMode.PlanePlacement:
		_strategy = PlanePlacementStrategy.new(placement_mode.plane_options)
	elif placement_mode is GapPlacementMode.GridFillPlacement:
		_strategy = PlanePlacementStrategy.new(placement_mode.plane_options)
	elif placement_mode is GapPlacementMode.Terrain3DPlacement:
		_strategy = Terrain3DAssetPlacementStrategy.new(placement_mode.get_terrain_3d_node())
	else:
		push_error("Placement mode %s is not supported" % str(placement_mode))


func _pick_name(node: Node3D, parent: Node3D) -> String:
	var number_of_same_scenes = 0
	for child in parent.get_children():
		if child.has_meta(meta_asset_id) && child.get_meta(meta_asset_id) == asset.id:
			number_of_same_scenes += 1
	return node.name if number_of_same_scenes == 0 else node.name + " (%s)" % number_of_same_scenes


func get_safe_basis(up: Vector3, forward_hint: Vector3) -> Basis:
	up = up.normalized()
	var forward = forward_hint.normalized()

	if abs(up.dot(forward)) > 0.99:
		if abs(up.dot(Vector3.UP)) < 0.9:
			forward = Vector3.UP
		else:
			forward = Vector3.FORWARD

	var right = up.cross(forward).normalized()

	if right.length() < 0.001:
		right = up.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.001:
			right = up.cross(Vector3.RIGHT).normalized()

	forward = right.cross(up).normalized()

	if up.length() < 0.001 or right.length() < 0.001 or forward.length() < 0.001:
		return Basis()

	return Basis(right, up, forward).orthonormalized()
