extends Node
## Gives Eclipse Foundry a bundled glyph fallback.
##
## Eclipse Foundry is a small display face (~149 glyphs) and is missing common
## punctuation such as the middle dot (·), en/em dashes (– —), bullet (•) and
## ellipsis (…). On desktop Godot substitutes those from the OS fonts, but in the
## browser/WASM sandbox there are no system fonts, so they render as ".notdef"
## tofu boxes (most visibly on iOS). Outfit-Regular is bundled and covers them.
##
## FontFile resources are cached by path, so setting `fallbacks` on the shared
## instance here applies everywhere it is referenced (theme, dialogue, 3D labels).

func _ready() -> void:
	var primary := load("res://assets/ui/fonts/eclipse-foundry.ttf") as FontFile
	var fallback := load("res://assets/ui/fonts/Outfit-Regular.ttf") as Font
	if primary == null or fallback == null:
		return
	if primary.fallbacks.is_empty():
		var list := primary.fallbacks
		list.append(fallback)
		primary.fallbacks = list
