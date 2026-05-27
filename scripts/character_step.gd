class_name CharacterStep
extends RefCounted
## Lightweight ledge step for CharacterBody3D (no extra nodes). Call before move_and_slide().

const DEFAULT_STEP_HEIGHT := 0.45
const DEFAULT_PROBE_DISTANCE := 0.42


static func try_step_up(body: CharacterBody3D, step_height: float = DEFAULT_STEP_HEIGHT) -> void:
	if not body.is_on_floor():
		return
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horizontal.length() < 0.2:
		return
	var forward := horizontal.normalized()
	var space := body.get_world_3d().direct_space_state
	var foot := body.global_position + Vector3.UP * 0.08
	var low_to := foot + forward * DEFAULT_PROBE_DISTANCE
	var low_hit := space.intersect_ray(_ray(body, foot, low_to))
	if low_hit.is_empty():
		return
	var high_from := foot + Vector3.UP * step_height
	var high_to := high_from + forward * DEFAULT_PROBE_DISTANCE
	if not space.intersect_ray(_ray(body, high_from, high_to)).is_empty():
		return
	var land_from := high_from + forward * DEFAULT_PROBE_DISTANCE
	var land_to := land_from - Vector3.UP * (step_height + 0.1)
	var floor_hit := space.intersect_ray(_ray(body, land_from, land_to))
	if floor_hit.is_empty():
		return
	var floor_y: float = floor_hit.position.y
	var rise := floor_y - body.global_position.y
	if rise < 0.02 or rise > step_height + 0.05:
		return
	body.global_position.y = floor_y


static func _ray(body: CharacterBody3D, from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return query
