class_name UITokens
extends RefCounted

## Shared palette from pf-design B2 speech dialog.

const INK := Color(0.169, 0.141, 0.094, 1.0)
const INK_SOFT := Color(0.353, 0.322, 0.251, 1.0)
const MUSTARD_HI := Color(0.945, 0.753, 0.396, 1.0)
const MUSTARD_MID := Color(0.890, 0.678, 0.282, 1.0)
const MUSTARD_LO := Color(0.784, 0.518, 0.098, 1.0)
const MUSTARD_DEEP := Color(0.604, 0.396, 0.063, 1.0)
const DIALOG_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const CONTINUE_MUTED := Color(1.0, 1.0, 1.0, 0.72)
const ROLE_ON_TAG := Color(0.169, 0.141, 0.094, 0.7)
const GAME_SKY := Color(0.353, 0.412, 0.522, 1.0)
const PROMPT_FOCUS := Color(0.945, 0.753, 0.396, 1.0)
const PROMPT_UNFOCUS := Color(0.85, 0.82, 0.72, 1.0)

const THEME_PATH := "res://assets/ui/portfolio_theme.tres"


static func get_theme() -> Theme:
	return load(THEME_PATH) as Theme


static func stylebox(variation: StringName) -> StyleBox:
	var theme := get_theme()
	if theme == null:
		return null
	return theme.get_stylebox(&"panel", variation)


static func make_tag_depth_style() -> StyleBox:
	var sb := stylebox(&"SpeechTagDepth")
	return sb if sb else _fallback_tag_depth()


static func make_tag_face_style() -> StyleBox:
	var sb := stylebox(&"SpeechTagFace")
	return sb if sb else _fallback_tag_face()


static func make_prompt_key_style() -> StyleBox:
	var sb := stylebox(&"PromptKey")
	return sb if sb else _fallback_prompt_key()


static func make_joystick_base_style() -> StyleBox:
	var sb := stylebox(&"JoystickBase")
	return sb if sb else _fallback_joystick_base()


static func make_joystick_knob_style() -> StyleBox:
	var sb := stylebox(&"JoystickKnob")
	return sb if sb else _fallback_joystick_knob()


static func _fallback_tag_depth() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = MUSTARD_DEEP
	return s


static func _fallback_tag_face() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = MUSTARD_HI
	s.border_width_bottom = 2
	s.border_color = MUSTARD_LO
	return s


static func _fallback_prompt_key() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 1.0, 1.0, 0.92)
	s.set_corner_radius_all(6)
	return s


static func _fallback_joystick_base() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.059, 0.078, 0.118, 0.35)
	s.set_corner_radius_all(90)
	return s


static func _fallback_joystick_knob() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(MUSTARD_HI.r, MUSTARD_HI.g, MUSTARD_HI.b, 0.58)
	s.set_corner_radius_all(28)
	return s


static func make_fade_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0.059, 0.078, 0.118, 0.0),
		Color(0.059, 0.078, 0.118, 0.55),
		Color(0.039, 0.055, 0.086, 0.94),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex
