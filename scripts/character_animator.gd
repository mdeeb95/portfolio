class_name CharacterAnimator
extends Node

## Drives the Kenney character through an AnimationTree blend tree.
## Locomotion is a BlendSpace1D ("Move": idle@0 → walk@WALK_SPEED) blended by horizontal
## speed; the "talk" clip is swapped in via a Transition node. The blend tree and the baked
## locomotion AnimationLibrary live in kenney_character.tscn (authored through Godot MCP).

## A foot planted on the ground this frame (see _process: support-foot switch
## detection). The player plays a footstep sound per emission — by construction
## these land in sync with the animation at any locomotion blend speed.
signal foot_planted

## AnimationTree parameter paths (pinned from the live tree in Godot 4.6).
const BLEND_PARAM := "parameters/Move/blend_position"
const TRANSITION_PARAM := "parameters/Transition/transition_request"

## Locomotion speeds (m/s) — tune these in the inspector on the KenneyCharacter node (it's shared by
## every character). The blend tree shows the walk pose at walk_speed and the run pose at run_speed
## (idle at 0). The player reads them to scale movement: keyboard/tap-to-move = walk_speed; the
## virtual joystick scales from a slow walk up to run_speed at full push.
@export var walk_speed := 5.0
@export var run_speed := 5.6
## Speeds below this (m/s) are treated as a full stop. move_and_slide() leaves tiny residual x/z
## velocity on slopes/contacts even when "stopped"; without a dead zone that blends a sliver of walk
## into idle — a "shuffle in place". (Mirrors the old controller's 0.25 threshold.)
const MOVE_THRESHOLD := 0.25
## blend_position damping rate (frame-rate independent); higher = snappier idle<->walk easing.
const BLEND_DAMP := 14.0

## Below this grounded speed (m/s) foot-plant detection is off (idle shuffle must not step).
const FOOTSTEP_MIN_SPEED := 0.5
## Vertical gap (m, world space) one foot must open over the other before it counts as the new
## support foot. 0.012 was validated against the real blend tree at blends 1.2–5.6: clean
## alternation, no double-fires, even where the slow-gait foot lift compresses to ~7 cm.
@export_range(0.001, 0.05, 0.001) var foot_switch_deadband := 0.012

## Mixamo locomotion + talk clips retargeted onto the Kenney rig in Mixamo, so each FBX shares
## the Kenney skeleton and a single clip named "mixamo_com". These are baked into
## res://assets/characters/kenney/locomotion_library.res and assigned to the AnimationPlayer in
## the scene; this dict is only the runtime rebuild fallback (see _ensure_library).
const MIXAMO_CLIP := "mixamo_com"
const ANIM_SOURCES := {
	"idle": "res://assets/characters/mixamo/animations/idle.fbx",
	"walk": "res://assets/characters/mixamo/animations/walking.fbx",
	"run": "res://assets/characters/mixamo/animations/running.fbx",
	"talk": "res://assets/characters/mixamo/animations/talking.fbx",
}

const SKIN_TEXTURE := preload("res://assets/characters/kenney/skins/business_male_a.png")
const MESH_NODE_NAME := "characterLargeMale"
const ANIM_TRACK_PREFIX := "Root/Skeleton3D"
const ANIM_TRACK_REMAP := "Root/Root/Skeleton3D"

## Kenney FBX import scales an inner Root by 100 (~2.5 m). Scale outer Root to fit the 1.6 m capsule.
@export var model_scale := Vector3(0.64, 0.64, 0.64)

@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _tree: AnimationTree = $AnimationTree
@onready var _model_root: Node3D = $Root

var _talking: bool = false

var _skel: Skeleton3D
var _bone_left: int = -1
var _bone_right: int = -1
var _grounded_speed: float = 0.0
## Which foot is currently the support (lower) foot: -1 left, 1 right, 0 unknown/reset.
var _lower_foot: int = 0


func _enter_tree() -> void:
	_apply_model_scale()


func _ready() -> void:
	_apply_model_scale()
	_apply_skin()
	if Engine.is_editor_hint():
		return
	_ensure_library()
	_ensure_blend_points()
	# The grayscale intro pauses the world. Process the tree anyway so characters hold their idle
	# pose during the pause instead of a rest-pose T-pose, and don't snap to idle when play begins.
	_tree.process_mode = Node.PROCESS_MODE_ALWAYS
	_tree.active = true
	_tree.set(BLEND_PARAM, 0.0)
	_tree.set(TRANSITION_PARAM, "move")
	_tree.advance(0.0)
	_skel = get_node_or_null("Root/Root/Skeleton3D") as Skeleton3D
	if _skel:
		_bone_left = _skel.find_bone("LeftFoot")
		_bone_right = _skel.find_bone("RightFoot")
	if _skel == null or _bone_left < 0 or _bone_right < 0:
		push_warning("CharacterAnimator: foot bones not found on %s; footstep events disabled." % name)


func _apply_model_scale() -> void:
	var root := get_node_or_null("Root") as Node3D
	if root:
		root.scale = model_scale


func set_talking(talking: bool) -> void:
	if _talking == talking:
		return
	_talking = talking
	_tree.set(TRANSITION_PARAM, "talk" if talking else "move")


## Feed horizontal body speed (m/s) into the locomotion blend space. Sub-threshold speed snaps to a
## clean idle, and the blend is damped so idle<->walk eases instead of popping.
func update_locomotion(horizontal_speed: float, is_on_floor: bool) -> void:
	_grounded_speed = horizontal_speed if is_on_floor else 0.0
	var target := 0.0 if horizontal_speed < MOVE_THRESHOLD else horizontal_speed
	var current := float(_tree.get(BLEND_PARAM))
	var weight := 1.0 - exp(-BLEND_DAMP * get_physics_process_delta_time())
	_tree.set(BLEND_PARAM, lerpf(current, target, weight))


## Support-foot switch detection: a footstep is the moment the lower foot changes identity
## (left<->right past a small deadband). Scale- and threshold-free, so it stays in sync with
## the animation no matter how slowly or fast the locomotion blend plays. Runs on idle frames,
## matching the AnimationTree's default process callback (the rendered pose).
func _process(_delta: float) -> void:
	if _skel == null or _bone_left < 0 or _bone_right < 0:
		return
	if _grounded_speed < FOOTSTEP_MIN_SPEED or _talking:
		# Re-baseline on resume so a stale switch doesn't fire (also covers landings:
		# airborne -> gate closed -> reset; the player's landing thud stays un-doubled).
		_lower_foot = 0
		return
	var left_y := (_skel.global_transform * _skel.get_bone_global_pose(_bone_left)).origin.y
	var right_y := (_skel.global_transform * _skel.get_bone_global_pose(_bone_right)).origin.y
	var diff := left_y - right_y
	if _lower_foot == 0:
		if absf(diff) > foot_switch_deadband:
			_lower_foot = -1 if diff < 0.0 else 1
	elif _lower_foot == -1 and diff > foot_switch_deadband:
		_lower_foot = 1
		foot_planted.emit()
	elif _lower_foot == 1 and diff < -foot_switch_deadband:
		_lower_foot = -1
		foot_planted.emit()


func _apply_skin() -> void:
	var mesh := _model_root.find_child(MESH_NODE_NAME, true, false) as MeshInstance3D
	if mesh == null:
		var meshes := _model_root.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			return
		mesh = meshes[0] as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.albedo_texture = SKIN_TEXTURE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mesh.material_override = material


## The locomotion library is normally baked into the scene's AnimationPlayer. Rebuild it at
## runtime only if it's missing/incomplete (e.g. after a re-import) so the blend tree always has
## its clips. Idempotent. Mirrors the bake: remap Mixamo→Kenney track paths + strip root motion.
func _ensure_library() -> void:
	var library: AnimationLibrary
	if _animation_player.has_animation_library(""):
		library = _animation_player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library("", library)
	for anim_name: String in ANIM_SOURCES:
		if library.has_animation(anim_name):
			continue
		var scene: PackedScene = load(ANIM_SOURCES[anim_name] as String)
		var instance := scene.instantiate()
		var source_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var animation := source_player.get_animation(MIXAMO_CLIP).duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR
		_remap_animation_paths(animation)
		_remove_root_motion(animation)
		library.add_animation(anim_name, animation)
		instance.free()


## The locomotion BlendSpace1D is easy to corrupt by hand in the AnimationTree editor — a deleted
## or re-assigned point makes every character play one clip (the "idle characters walk in place"
## bug). Self-heal: if the idle↔walk pair is missing, rebuild the canonical idle@0 / walk points at
## runtime. A valid idle+walk setup is left alone, so point positions stay tunable in the editor.
func _ensure_blend_points() -> void:
	var blend_tree := _tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null:
		return
	var space := blend_tree.get_node(&"Move") as AnimationNodeBlendSpace1D
	if space == null:
		return
	var has_idle := false
	var has_walk := false
	var has_run := false
	for i: int in space.get_blend_point_count():
		var point := space.get_blend_point_node(i) as AnimationNodeAnimation
		if point == null:
			continue
		if point.animation == &"idle":
			has_idle = true
		elif point.animation == &"walk":
			has_walk = true
		elif point.animation == &"run":
			has_run = true
	# Rebuild the canonical idle/walk/run set if any are missing or there are stray points (a hand
	# edit in the AnimationTree editor can drop/duplicate/reassign points, and pressing Play saves it).
	if not (has_idle and has_walk and has_run) or space.get_blend_point_count() != 3:
		for i: int in range(space.get_blend_point_count() - 1, -1, -1):
			space.remove_blend_point(i)
		var idle_node := AnimationNodeAnimation.new()
		idle_node.animation = &"idle"
		var walk_node := AnimationNodeAnimation.new()
		walk_node.animation = &"walk"
		var run_node := AnimationNodeAnimation.new()
		run_node.animation = &"run"
		space.add_blend_point(idle_node, 0.0)
		space.add_blend_point(walk_node, walk_speed)
		space.add_blend_point(run_node, run_speed)
		push_warning("CharacterAnimator: rebuilt locomotion blend points (idle/walk/run).")
	# Pin positions to the tunable speeds — the @export values are the single source of truth, so an
	# editor drag can't break the mapping: idle stays at 0 (a clean stop), walk/run track the speeds.
	for i: int in space.get_blend_point_count():
		var point := space.get_blend_point_node(i) as AnimationNodeAnimation
		if point == null:
			continue
		if point.animation == &"idle":
			space.set_blend_point_position(i, 0.0)
		elif point.animation == &"walk":
			space.set_blend_point_position(i, walk_speed)
		elif point.animation == &"run":
			space.set_blend_point_position(i, run_speed)
	space.min_space = 0.0
	space.max_space = run_speed


func _remap_animation_paths(animation: Animation) -> void:
	for track_idx: int in animation.get_track_count():
		var path := str(animation.track_get_path(track_idx))
		if path.begins_with(ANIM_TRACK_PREFIX):
			animation.track_set_path(
				track_idx,
				NodePath(path.replace(ANIM_TRACK_PREFIX, ANIM_TRACK_REMAP)),
			)


## Mixamo clips retargeted onto Kenney still key HipsCtrl translation. Under the inner 100× Root
## that reads as world-space drift and a loop snap — strip it so movement comes only from
## CharacterBody3D velocity (in-place locomotion).
func _remove_root_motion(animation: Animation) -> void:
	for track_idx: int in range(animation.get_track_count() - 1, -1, -1):
		if animation.track_get_type(track_idx) == Animation.TYPE_POSITION_3D:
			animation.remove_track(track_idx)
