extends CharacterBody3D

const WALK_SPEED := 6.5
const TURN_SPEED := 18.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 7.5
const TAP_MOVE_STOP_DIST := 0.35

@onready var model: Node3D = $Model
@onready var spring_arm: SpringArm3D = $SpringArm3D

var _tap_target: Vector3 = Vector3.ZERO
var _has_tap_target: bool = false


func _physics_process(delta: float) -> void:
	if _is_movement_locked():
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		elif velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := spring_arm.global_transform.basis
	var cam_forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var cam_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var direction := (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()

	if direction != Vector3.ZERO:
		_has_tap_target = false
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), TURN_SPEED * delta)
	elif _has_tap_target:
		var to_target := _tap_target - global_position
		to_target.y = 0.0
		if to_target.length() <= TAP_MOVE_STOP_DIST:
			_has_tap_target = false
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			direction = to_target.normalized()
			velocity.x = direction.x * WALK_SPEED
			velocity.z = direction.z * WALK_SPEED
			model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), TURN_SPEED * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


func set_tap_target(world_pos: Vector3) -> void:
	_tap_target = world_pos
	_tap_target.y = global_position.y
	_has_tap_target = true


func _is_movement_locked() -> bool:
	var mgr := get_node_or_null("InteractionManager")
	return mgr != null and mgr.movement_locked

