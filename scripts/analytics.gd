extends Node
## Forwards gameplay events to the web shell's window.__analytics helper
## (see web/godot_shell.html). No-ops outside web builds or when the helper
## is missing (default shell, local preview), so it is always safe to call.

var _enabled := false
var _seen: Dictionary = {}


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_enabled = bool(JavaScriptBridge.eval("!!(window.__analytics && window.__analytics.track)", true))


func track(event_name: String, props: Dictionary = {}) -> void:
	if not _enabled:
		return
	var code := "window.__analytics.track(%s, %s);" % [
		JSON.stringify(event_name),
		JSON.stringify(props),
	]
	JavaScriptBridge.eval(code, true)


## Emits the event only the first time this (event, key) pair is seen during
## the session — e.g. zone_visited should not fire on every re-approach.
func track_once(event_name: String, key: String, props: Dictionary = {}) -> void:
	var k := event_name + "/" + key
	if _seen.has(k):
		return
	_seen[k] = true
	track(event_name, props)


func tech_props() -> Dictionary:
	var mobile := OS.has_feature("web_android") or OS.has_feature("web_ios")
	return {
		"mobile": mobile,
		"touch": DisplayServer.is_touchscreen_available(),
		"tier": "mobile" if mobile else "desktop",
	}
