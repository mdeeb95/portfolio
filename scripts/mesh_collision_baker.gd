extends Node3D
## Builds world-layer StaticBody3D + convex collision from MeshInstance3D descendants.
## Attach to Environment (or Decorations) and list nodes to bake in the inspector.

@export var bake_targets: Array[NodePath] = [NodePath("Floor"), NodePath("Decorations")]
@export var skip_small_floor_clutter: bool = true
@export var clutter_max_height: float = 0.38
@export var clutter_max_footprint: float = 1.25
@export var clutter_name_hints: PackedStringArray = PackedStringArray([
	"floor-panel",
	"floor-detail",
	"table-display-planet",
	"wall-switch",
])


func _ready() -> void:
	for path: NodePath in bake_targets:
		var target := get_node_or_null(path)
		if target == null:
			push_warning("MeshCollisionBaker: missing node at %s" % path)
			continue
		_bake_node(target)


func _bake_node(node: Node) -> void:
	if not node is Node3D:
		return
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			_bake_prop(node as Node3D)
			return
	for child: Node in node.get_children():
		if child is Node3D:
			_bake_prop(child as Node3D)


func _bake_prop(prop: Node3D) -> void:
	if prop.get_node_or_null("DecoCollision") != null:
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(prop, meshes)
	if meshes.is_empty():
		return
	if _should_skip_prop(prop, meshes):
		return

	var body := StaticBody3D.new()
	body.name = "DecoCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	prop.add_child(body)

	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var shape: Shape3D = mi.mesh.create_convex_shape()
		if shape == null:
			continue
		var col := CollisionShape3D.new()
		col.transform = prop.global_transform.affine_inverse() * mi.global_transform
		col.shape = shape
		body.add_child(col)


func _should_skip_prop(prop: Node3D, meshes: Array[MeshInstance3D]) -> bool:
	var prop_name := prop.name.to_lower()
	for hint: String in clutter_name_hints:
		if prop_name.contains(hint):
			return true
	if not skip_small_floor_clutter:
		return false
	var bounds := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var mesh_aabb: AABB = mi.get_aabb()
		if first:
			bounds = mesh_aabb
			first = false
		else:
			bounds = bounds.merge(mesh_aabb)
	if first:
		return false
	var size := bounds.size
	var footprint := maxf(size.x, size.z)
	return size.y <= clutter_max_height and footprint <= clutter_max_footprint


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		if child is StaticBody3D and child.name == "DecoCollision":
			continue
		_collect_meshes(child, out)
