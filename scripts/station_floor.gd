@tool
class_name StationFloor
extends Node3D
## A station floor plaza drawn as a single MultiMesh: one draw call for the whole
## tile grid instead of one node + draw call per tile, plus one walkable collision
## box matching the grid extent (top flush with the tile surface). Resize with
## grid_size / tile_pitch in the inspector — no more hand-placed tile grids.

const _DEFAULT_TILE_SCENE := "res://assets/environment/space_station/models/floor.fbx"
const _DEFAULT_FLOOR_MATERIAL := "res://resources/materials/space_station_floor_deck.tres"

## Number of tiles along X and Z; the grid is centered on this node's origin.
@export var grid_size: Vector2i = Vector2i(15, 15):
	set(value):
		grid_size = value.max(Vector2i.ONE)
		if is_node_ready():
			_rebuild()

## Distance between tile centers in meters (the Kenney tile is 2.5 m square).
@export var tile_pitch: float = 2.5:
	set(value):
		tile_pitch = maxf(value, 0.1)
		if is_node_ready():
			_rebuild()

## Tile source scene; the first MeshInstance3D found inside is drawn per cell.
@export var tile_scene: PackedScene:
	set(value):
		tile_scene = value
		if is_node_ready():
			_rebuild()

## Material for all tiles (defaults to the station deck material).
@export var floor_material: StandardMaterial3D:
	set(value):
		floor_material = value
		if is_node_ready():
			_rebuild()

## Leave a hole in the grid under sibling nodes named "floor*" (panel/detail
## accent tiles placed by hand), so they replace the plain tile in their cell.
## Cells are resolved on rebuild — nudge a grid_size/tile_pitch value to refresh.
@export var skip_under_siblings: bool = true:
	set(value):
		skip_under_siblings = value
		if is_node_ready():
			_rebuild()

@onready var _tiles: MultiMeshInstance3D = $Tiles
@onready var _floor_shape: CollisionShape3D = $FloorBody/CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _tiles == null or _floor_shape == null:
		return
	var scene := tile_scene
	if scene == null:
		scene = load(_DEFAULT_TILE_SCENE) as PackedScene
	if scene == null:
		return
	var source := scene.instantiate()
	var mesh: Mesh = null
	var mesh_xform := Transform3D.IDENTITY
	for mi: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		mesh = mi.mesh
		# Accumulate the mesh's transform relative to the scene root.
		var walker: Node = mi
		while walker != source and walker is Node3D:
			mesh_xform = (walker as Node3D).transform * mesh_xform
			walker = walker.get_parent()
		break
	source.free()
	if mesh == null:
		return

	var half := Vector2((grid_size.x - 1) * 0.5, (grid_size.y - 1) * 0.5)
	var skip := _collect_skip_cells(half)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = grid_size.x * grid_size.y - skip.size()
	var i := 0
	for zi: int in grid_size.y:
		for xi: int in grid_size.x:
			if skip.has(Vector2i(xi, zi)):
				continue
			var pos := Vector3((xi - half.x) * tile_pitch, 0.0, (zi - half.y) * tile_pitch)
			mm.set_instance_transform(i, Transform3D(mesh_xform.basis, pos + mesh_xform.origin))
			i += 1
	_tiles.multimesh = mm

	var mat := floor_material
	if mat == null:
		mat = load(_DEFAULT_FLOOR_MATERIAL) as StandardMaterial3D
	_tiles.material_override = mat

	# One walkable box wrapping the whole grid, top flush with the tile tops.
	var aabb := mesh.get_aabb()
	var box := _floor_shape.shape as BoxShape3D
	if box == null or not box.resource_local_to_scene:
		box = BoxShape3D.new()
		box.resource_local_to_scene = true
		_floor_shape.shape = box
	box.size = Vector3(grid_size.x * tile_pitch, maxf(aabb.size.y, 0.05), grid_size.y * tile_pitch)
	_floor_shape.position = Vector3(0.0, aabb.position.y + box.size.y * 0.5, 0.0)


func _collect_skip_cells(half: Vector2) -> Dictionary:
	var skip := {}
	var parent := get_parent()
	if not skip_under_siblings or parent == null:
		return skip
	for sibling: Node in parent.get_children():
		if sibling == self or not (sibling is Node3D):
			continue
		if not sibling.name.begins_with("floor"):
			continue
		var local := (sibling as Node3D).position - position
		var cell := Vector2i(roundi(local.x / tile_pitch + half.x), roundi(local.z / tile_pitch + half.y))
		if cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y:
			skip[cell] = true
	return skip
