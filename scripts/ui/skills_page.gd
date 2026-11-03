extends VBoxContainer
## SkillsPage - every skill with its level, the derived level, perks unlocked, deaths and difficulty
## (docs/PLAYER_SYSTEMS.md §2, §8). A plain Control so it can sit in any panel: the inventory panel's
## Skills tab carries it, and the journal can take it as a tab of its own (`SkillsPage.new()`, then
## refresh() when shown). Reads PlayerStats through the contract getters; skill and perk names come
## from resources/player/{skills,perks}.json when that slice has written them

const UI = preload("res://scripts/ui/player_ui.gd")
## The spec's twelve (§2), used until resources/player/skills.json exists
const SKILLS = ["blades", "blunt", "bows", "defence", "athletics", "stealth", "smithing", "woodcraft",
	"herbcraft", "mining", "speech", "lore"]
const SKILLS_PATH = "res://resources/player/skills.json"
const PERKS_PATH = "res://resources/player/perks.json"

## Injectable for tests; the PlayerStats autoload otherwise
var stats: Node = null
var _header: Label
var _grid: GridContainer
var _perks: VBoxContainer

func _init() -> void:
	name = "SkillsPage"
	add_theme_constant_override("separation", 8)
	_header = UI.label("", 15, UI.GOLD)
	_header.name = "Header"
	add_child(_header)
	_grid = GridContainer.new()
	_grid.name = "Skills"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	add_child(_grid)
	add_child(UI.label("Perks", 15, UI.GOLD))
	_perks = VBoxContainer.new()
	_perks.name = "Perks"
	add_child(_perks)

func refresh() -> void:
	var s = _stats()
	UI.clear(_grid)
	UI.clear(_perks)
	if s == null:
		_header.text = "You do not know yourself yet."
		return
	_header.text = "Level %d   ·   %s   ·   %s" % [int(s.get_level()), difficulty_text(), deaths_text()]
	for skill in skill_rows():
		var level = float(s.get_skill(skill.id))
		_grid.add_child(UI.label(skill.name, 14))
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(180, 12)
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = level
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_grid.add_child(bar)
		_grid.add_child(UI.label("%d" % floori(level), 14))
	var unlocked = perks_unlocked()
	if unlocked.is_empty():
		_perks.add_child(UI.label("None yet. Skills open perks at 25, 50, 75 and 100.", 13, UI.FAINT))
	for perk in unlocked:
		var line = UI.label("%s%s" % [perk.name, (": " + perk.text) if perk.text != "" else ""], 13)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(420, 0)
		_perks.add_child(line)

## [{id, name}] in the skills file's order, or the spec's twelve
func skill_rows() -> Array:
	var s = _stats()
	var listed: Array = UI.records(UI.read_json(SKILLS_PATH), "skills")
	if listed.is_empty() and s and s.has_method("get_skills"):
		var known = s.get_skills()
		if known is Dictionary:
			for id in known:
				listed.append({"id": id})
	if listed.is_empty():
		listed = SKILLS.map(func(id): return {"id": id})
	return listed.map(func(r): return {"id": str(r.get("id", "")), "name": str(r.get("name", str(r.get("id", "")).capitalize()))})

## [{id, name, text}] for every perk PlayerStats says the player has
func perks_unlocked() -> Array:
	var s = _stats()
	if s == null:
		return []
	var defs: Dictionary = {}
	for r in UI.records(UI.read_json(PERKS_PATH), "perks"):
		defs[str(r.get("id", ""))] = r
	var ids: Array = []
	if s.has_method("get_perks"):
		var got = s.get_perks()
		ids = got if got is Array else (got.keys() if got is Dictionary else [])
	else:
		ids = defs.keys().filter(func(id): return s.has_perk(id))
	return ids.map(func(id):
		var d: Dictionary = defs.get(str(id), {})
		return {"id": str(id), "name": str(d.get("name", str(id).replace("_", " ").capitalize())),
			"text": str(d.get("text", d.get("description", "")))})

func difficulty_text() -> String:
	var s = _stats()
	var d = str(s.difficulty) if s and "difficulty" in s else "normal"
	return "Hard" if d == "hard" else "Normal"

func death_count() -> int:
	var s = _stats()
	if s == null:
		return 0
	for method in ["get_death_count", "get_deaths"]:
		if s.has_method(method):
			return int(s.call(method))
	for field in ["death_count", "deaths"]:
		if field in s:
			var v = s.get(field)
			return v.size() if v is Array else int(v)
	return 0

func deaths_text() -> String:
	var n = death_count()
	return "never died" if n == 0 else ("died once" if n == 1 else "died %d times" % n)

func get_text() -> String:
	var parts: Array = [_header.text]
	for child in _grid.get_children():
		if child is Label:
			parts.append(child.text)
	for child in _perks.get_children():
		if child is Label:
			parts.append(child.text)
	return "\n".join(parts)

func _stats() -> Node:
	return stats if stats else UI.autoload("PlayerStats")
