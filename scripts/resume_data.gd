extends Node

const RESUME_PATH := "res://data/resume.json"

var data: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	var file := FileAccess.open(RESUME_PATH, FileAccess.READ)
	if file == null:
		push_error("ResumeData: could not open %s" % RESUME_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("ResumeData: invalid JSON")


func get_dialogue_pages(zone_key: String) -> Array[Dictionary]:
	# Each page: { "speaker": String, "text": String, "role": String (optional) }
	match zone_key:
		"intro":
			return _pages_intro()
		"work":
			return _pages_work()
		"hobbies":
			return _pages_hobbies()
		"accomplishments":
			return _pages_accomplishments()
		"about":
			return _pages_about()
		_:
			return [{"speaker": "???", "text": "Nothing here yet."}]


func _pages_intro() -> Array[Dictionary]:
	var name: String = data.get("name", "Mathew Deeb")
	var role: String = data.get("speaker_role", data.get("title", ""))
	return [
		{
			"speaker": name,
			"role": role,
			"text": data.get("intro", "Welcome to my portfolio town!")
		},
		{
			"speaker": name,
			"role": role,
			"text": "%s\n\n%s" % [data.get("title", ""), data.get("tagline", "")]
		},
	]


func _pages_work() -> Array[Dictionary]:
	var zone: Dictionary = data.get("zones", {}).get("work", {})
	var title: String = zone.get("title", "Work")
	var pages: Array[Dictionary] = []
	pages.append({
		"speaker": title,
		"text": "Here's where I've worked. Take a look!"
	})
	for entry: Dictionary in zone.get("entries", []):
		var lines: PackedStringArray = PackedStringArray()
		lines.append(entry.get("company", ""))
		lines.append("%s · %s" % [entry.get("role", ""), entry.get("period", "")])
		if entry.has("location"):
			lines.append(entry.get("location", ""))
		lines.append("")
		for bullet: String in entry.get("highlights", []):
			lines.append("• %s" % bullet)
		pages.append({"speaker": title, "text": "\n".join(lines)})
	return pages


func _pages_hobbies() -> Array[Dictionary]:
	var zone: Dictionary = data.get("zones", {}).get("hobbies", {})
	var title: String = zone.get("title", "Hobbies")
	var pages: Array[Dictionary] = []
	pages.append({"speaker": title, "text": "What I get up to outside of work:"})
	for item: Dictionary in zone.get("items", []):
		pages.append({
			"speaker": title,
			"text": "%s\n\n%s" % [item.get("name", ""), item.get("detail", "")]
		})
	return pages


func _pages_accomplishments() -> Array[Dictionary]:
	var zone: Dictionary = data.get("zones", {}).get("accomplishments", {})
	var title: String = zone.get("title", "Accomplishments")
	var pages: Array[Dictionary] = []
	pages.append({"speaker": title, "text": "A few things I'm proud of:"})
	for item: Dictionary in zone.get("items", []):
		pages.append({
			"speaker": title,
			"text": "%s\n\n%s" % [item.get("name", ""), item.get("detail", "")]
		})
	return pages


func _pages_about() -> Array[Dictionary]:
	var zone: Dictionary = data.get("zones", {}).get("about", {})
	var name: String = data.get("name", "Mathew Deeb")
	var pages: Array[Dictionary] = []
	pages.append({"speaker": name, "text": zone.get("bio", "")})
	var edu: Dictionary = zone.get("education", {})
	if not edu.is_empty():
		pages.append({
			"speaker": name,
			"text": "%s\n%s (%s)\n%s" % [
				edu.get("school", ""),
				edu.get("degree", ""),
				edu.get("period", ""),
				edu.get("concentration", "")
			]
		})
	var skills: Dictionary = zone.get("skills", {})
	if not skills.is_empty():
		var lines: PackedStringArray = PackedStringArray(["Skills & tools:"])
		for key: String in skills.keys():
			var list: Array = skills[key]
			lines.append("%s: %s" % [key.capitalize(), ", ".join(list)])
		pages.append({"speaker": name, "text": "\n".join(lines)})
	var links: Array = zone.get("links", [])
	if not links.is_empty():
		var link_lines: PackedStringArray = PackedStringArray(["Let's connect!"])
		for link: Dictionary in links:
			link_lines.append("%s — %s" % [link.get("label", ""), link.get("url", "")])
		pages.append({"speaker": name, "text": "\n".join(link_lines)})
	return pages
