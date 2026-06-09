@tool
class_name StationWallRun
extends Node3D
## A straight run of repeated wall segments drawn as a single MultiMesh: one
## draw call per wall instead of one node + draw call per segment. Segments
## march along local +X starting at this node's origin; position/rotate the
## node to set where the wall starts, its direction, and its facing.
## No collision included — the town's BoundaryWalls boxes handle that.

const _DEFAULT_WALL_SCENE := "res://assets/environment/space_station/models/wall-banner.fbx"

## Number of wall segments in the run.
@export var segments: int = 15:
	set(value):
		segments = maxi(value, 1)
		if is_node_ready():
			_rebuild()

## Distance between segment origins in meters (the Kenney wall is 2.5 m wide).
@export var segment_pitch: float = 2.5:
	set(value):
		segment_pitch = maxf(value, 0.1)
		if is_node_ready():
			_rebuild()

## Segment source scene; the first MeshInstance3D found inside is drawn per
## segment with the mesh's own material.
@export var wall_scene: PackedScene:
	set(value):
		wall_scene = value
		if is_node_ready():
			_rebuild()

@onready var _segments_mmi: MultiMeshInstance3D = $Segments


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _segments_mmi == null:
		return
	var scene := wall_scene
	if scene == null:
		scene = load(_DEFAULT_WALL_SCENE) as PackedScene
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

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = segments
	for i: int in segments:
		var pos := Vector3(i * segment_pitch, 0.0, 0.0)
		mm.set_instance_transform(i, Transform3D(mesh_xform.basis, pos + mesh_xform.origin))
	_segments_mmi.multimesh = mm
