@tool
class_name PhysicsLetter
extends RigidBody3D
## Knockable extruded-letter physics prop. Drop the scene in a level, type the
## letter in the inspector, done. The root origin sits on the floor under the
## glyph; the mesh offset and collision box are re-derived from the TextMesh
## AABB whenever `letter` changes, so the box always wraps the glyph exactly.

const _MIN_GLYPH_SIZE := 0.05

## Character to display (first character is used, uppercased).
@export var letter: String = "D":
	set(value):
		letter = value
		if is_node_ready():
			_apply_letter()

## Letter height in meters. Drives the TextMesh size and collision box; depth
## scales along with it. Don't scale the node itself — RigidBody3D ignores it.
## Tip: mass stays fixed, so consider raising it for letters well above ~2 m.
@export_range(0.3, 5.0, 0.05) var letter_height: float = 1.2:
	set(value):
		letter_height = value
		if is_node_ready():
			_apply_letter()

## Respawn at the start transform if the letter falls below this global Y.
@export var fall_reset_y: float = -10.0

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _start_transform: Transform3D


func _ready() -> void:
	_apply_letter()
	if not Engine.is_editor_hint():
		_start_transform = global_transform


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if global_position.y < fall_reset_y:
		_reset_to_start()


func _apply_letter() -> void:
	var text_mesh := _mesh_instance.mesh as TextMesh
	if text_mesh == null:
		return
	if not text_mesh.resource_local_to_scene:
		# Never mutate a resource shared with other placed instances.
		text_mesh = text_mesh.duplicate() as TextMesh
		text_mesh.resource_local_to_scene = true
		_mesh_instance.mesh = text_mesh
	text_mesh.text = letter.strip_edges().left(1).to_upper()
	var aabb := text_mesh.get_aabb()
	if aabb.size.y < _MIN_GLYPH_SIZE:
		return
	# Glyph height scales linearly with pixel_size, so one correction lands
	# exactly on letter_height; keep depth proportional so big letters stay chunky.
	text_mesh.pixel_size *= letter_height / aabb.size.y
	text_mesh.depth = letter_height * 0.25
	aabb = text_mesh.get_aabb()
	_mesh_instance.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var box := _collision_shape.shape as BoxShape3D
	if box == null or not box.resource_local_to_scene:
		box = BoxShape3D.new()
		box.resource_local_to_scene = true
		_collision_shape.shape = box
	box.size = aabb.size
	_collision_shape.position = Vector3(0.0, aabb.size.y * 0.5, 0.0)


func _reset_to_start() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _start_transform
	# Teleport: don't let physics interpolation smear the jump across a frame.
	reset_physics_interpolation()
