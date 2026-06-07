extends Node3D

## Procedurally fills the MultiMesh star shell so the sky has real 3D depth: as the player
## walks around the (bounded) town square, nearer stars and the galaxy billboards parallax
## against the infinitely-distant shader sky. The shell stays fixed in world space after
## start, so the parallax is preserved (it does NOT follow the camera every frame).

@export var star_count: int = 2600
@export var shell_radius: float = 250.0
## Should match the sky shader's `band_tilt` so the 3D stars line up with the painted band.
@export var band_tilt: float = 0.5
## 0 = stars spread evenly over the sphere, 1 = pulled tightly onto the galactic plane.
@export var band_concentration: float = 0.5
@export var min_star_size: float = 0.45
@export var max_star_size: float = 2.2
@export var rng_seed: int = 20260607
## Re-centre the shell on the player once at start so coverage is symmetric around them.
@export var center_on_player_at_start: bool = true

@onready var star_shell: MultiMeshInstance3D = $StarShell

func _ready() -> void:
	if center_on_player_at_start:
		var player := get_tree().get_first_node_in_group("player")
		if player and player is Node3D:
			global_position = (player as Node3D).global_position
	_populate_stars()

func _populate_stars() -> void:
	var mm := star_shell.multimesh
	if mm == null:
		push_warning("SpaceDepth: StarShell has no MultiMesh resource.")
		return
	mm.instance_count = star_count
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var band_normal := Vector3(0.0, cos(band_tilt), sin(band_tilt)).normalized()
	for i in star_count:
		var dir := _sample_direction(rng, band_normal)
		var bright_pick := pow(rng.randf(), 3.0)   # skew most stars toward faint
		var size: float = lerp(min_star_size, max_star_size, bright_pick)
		var xform := Transform3D(Basis().scaled(Vector3(size, size, size)), dir * shell_radius)
		mm.set_instance_transform(i, xform)
		var col := _star_color(rng.randf())
		var intensity: float = lerp(0.5, 1.0, bright_pick)
		mm.set_instance_color(i, Color(col.r * intensity, col.g * intensity, col.b * intensity, 1.0))
	# Big custom AABB so the shell is never frustum-culled when the camera looks away.
	var r2 := shell_radius + 60.0
	star_shell.custom_aabb = AABB(Vector3(-r2, -r2, -r2), Vector3(2.0 * r2, 2.0 * r2, 2.0 * r2))

func _sample_direction(rng: RandomNumberGenerator, band_normal: Vector3) -> Vector3:
	# Uniform point on the sphere via three gaussians, then optionally pulled toward the band.
	var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	if v.length() < 0.0001:
		v = Vector3.UP
	v = v.normalized()
	if band_concentration > 0.0:
		var d := v.dot(band_normal)
		var pull := band_concentration * rng.randf()
		v = (v - band_normal * d * pull).normalized()
	return v

func _star_color(t: float) -> Color:
	if t < 0.45:
		return Color(0.75, 0.84, 1.0).lerp(Color(1.0, 1.0, 1.0), t / 0.45)
	elif t < 0.8:
		return Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.93, 0.78), (t - 0.45) / 0.35)
	elif t < 0.94:
		return Color(1.0, 0.93, 0.78).lerp(Color(1.0, 0.78, 0.55), (t - 0.8) / 0.14)
	return Color(1.0, 0.78, 0.55).lerp(Color(1.0, 0.55, 0.42), (t - 0.94) / 0.06)
