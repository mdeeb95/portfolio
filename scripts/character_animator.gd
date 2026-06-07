class_name CharacterAnimator
extends Node

## Drives the Kenney character through an AnimationTree blend tree.
## Locomotion is a BlendSpace1D ("Move": idle@0 → walk@WALK_SPEED) blended by horizontal
## speed; the "talk" clip is swapped in via a Transition node. The blend tree and the baked
## locomotion AnimationLibrary live in kenney_character.tscn (authored through Godot MCP).

## AnimationTree parameter paths (pinned from the live tree in Godot 4.6).
const BLEND_PARAM := "parameters/Move/blend_position"
const TRANSITION_PARAM := "parameters/Transition/transition_request"

## blend_position (= horizontal speed, m/s) at which the walk clip is full weight; idle sits at 0.
## Matches the player's WALK_SPEED.
const WALK_BLEND_POINT := 5.0
## Speeds below this (m/s) are treated as a full stop. move_and_slide() leaves tiny residual x/z
## velocity on slopes/contacts even when "stopped"; without a dead zone that blends a sliver of walk
## into idle — a "shuffle in place". (Mirrors the old controller's 0.25 threshold.)
const MOVE_THRESHOLD := 0.25
## blend_position damping rate (frame-rate independent); higher = snappier idle<->walk easing.
const BLEND_DAMP := 14.0

## Mixamo locomotion + talk clips retargeted onto the Kenney rig in Mixamo, so each FBX shares
## the Kenney skeleton and a single clip named "mixamo_com". These are baked into
## res://assets/characters/kenney/locomotion_library.res and assigned to the AnimationPlayer in
## the scene; this dict is only the runtime rebuild fallback (see _ensure_library).
const MIXAMO_CLIP := "mixamo_com"
const ANIM_SOURCES := {
	"idle": "res://assets/characters/mixamo/animations/idle.fbx",
	"walk": "res://assets/characters/mixamo/animations/walking.fbx",
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
func update_locomotion(horizontal_speed: float, _is_on_floor: bool) -> void:
	var target := 0.0 if horizontal_speed < MOVE_THRESHOLD else horizontal_speed
	var current := float(_tree.get(BLEND_PARAM))
	var weight := 1.0 - exp(-BLEND_DAMP * get_physics_process_delta_time())
	_tree.set(BLEND_PARAM, lerpf(current, target, weight))


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
	var idle_idx := -1
	var walk_idx := -1
	for i: int in space.get_blend_point_count():
		var point := space.get_blend_point_node(i) as AnimationNodeAnimation
		if point == null:
			continue
		if point.animation == &"idle":
			idle_idx = i
		elif point.animation == &"walk":
			walk_idx = i
	# Healthy config: exactly one idle + one walk. Force the idle point to sit at speed 0 so a
	# stopped character (blend_position 0) is PURE idle — an idle point dragged off 0 otherwise
	# blends a little walk into idle (the "shuffle in place"). The walk point stays tunable.
	if idle_idx != -1 and walk_idx != -1 and space.get_blend_point_count() == 2:
		if not is_equal_approx(space.get_blend_point_position(idle_idx), 0.0):
			space.set_blend_point_position(idle_idx, 0.0)
		return
	# Anything else (missing / duplicate / reassigned points): rebuild the canonical pair.
	for i: int in range(space.get_blend_point_count() - 1, -1, -1):
		space.remove_blend_point(i)
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"idle"
	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = &"walk"
	space.add_blend_point(idle_node, 0.0)
	space.add_blend_point(walk_node, WALK_BLEND_POINT)
	push_warning("CharacterAnimator: locomotion blend points were invalid; rebuilt idle/walk.")


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
