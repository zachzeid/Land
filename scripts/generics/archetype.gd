extends RefCounted
# Archetype - One generic NPC template (resources/generics/archetypes/<id>.md), docs/WORLD_SCHEMA.md §9
# SOUL.md format with these differences:
# - header `archetype: <id>` and `regions: <region ids>` instead of `npc:`
# - want weights are ranges `id` (lo-hi); each instance rolls its own
# - Essence and Voice may use {name}, {home}, {region}
# - Agency is limited to `converse:` with personal-scope effects
# - ## Life holds 1-2 small arcs whose result flags start with the literal `{id}_`
# Voice variants: bullet lines in ## Voice (prose before them is shared by every variant)
# Optional `type: <id>` header: a character type (resources/characters/character_types.json) whose
# base traits and skills every instance has

const PERSONAL_EFFECTS = ["agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"]
const SLOTS = ["{name}", "{home}", "{region}", "{id}"]

var id: String = ""
var title: String = ""             # "# ARCHETYPE: Farmer" / "# SOUL: Farmer" title, else id capitalised
var regions: Array = []            # region ids ("*" or "any" = everywhere)
var sprite: String = ""            # optional `sprite:` header (pregenerated character id)
var character_type_id: String = "" # optional `type:` header (CharacterTypes id)
var essence: String = ""
var voice_shared: String = ""      # Voice prose shared by every variant
var voice_variants: Array = []     # Voice bullet lines; the seed picks one
var fears: Array = []
var wants: Dictionary = {}         # want_id -> {"lo": int, "hi": int, "text": String}
var want_order: Array = []
var lines: Array = []              # raw "- `rule`: reason" lines (kept verbatim)
var converse: Array = []           # personal-scope effect types granted in conversation
var life_lines: Array = []         # raw ## Life lines (slots still in them)
var life_arc_count: int = 0
var secrets: String = ""
var source_path: String = ""
var errors: Array = []             # why this file is malformed ([] = valid)
var warnings: Array = []

static func load_from_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var archetype = load("res://scripts/generics/archetype.gd").new()
	archetype.source_path = path
	archetype.parse(file.get_as_text())
	file.close()
	return archetype

func is_valid() -> bool:
	return errors.is_empty()

func serves_region(region: String) -> bool:
	return regions.is_empty() or "*" in regions or "any" in regions or region in regions

## Parse archetype text. Malformed machine lines become errors, never crashes
func parse(text: String) -> void:
	var want_re = RegEx.create_from_string("^[-*]\\s*`([A-Za-z0-9_]+)`\\s*\\(\\s*(\\d+)\\s*(?:-\\s*(\\d+)\\s*)?\\)\\s*:?\\s*(.*)$")
	var agency_re = RegEx.create_from_string("^[-*]\\s*`?([A-Za-z_]+)`?\\s*:\\s*(.+)$")
	var line_re = RegEx.create_from_string("^[-*]\\s*`([^`]+)`\\s*:?\\s*(.*)$")
	var section = ""
	var prose: Dictionary = {}
	var voice_prose: Array = []
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.begins_with("# ") and not line.begins_with("## "):
			var t = line.substr(2).strip_edges()
			for prefix in ["archetype:", "soul:"]:
				if t.to_lower().begins_with(prefix):
					t = t.substr(prefix.length()).strip_edges()
			title = t
			continue
		if line.begins_with("## "):
			section = line.substr(3).strip_edges().to_lower()
			continue
		if section == "":
			var lower = line.to_lower()
			if lower.begins_with("archetype:"):
				id = line.substr(10).strip_edges().to_lower()
			elif lower.begins_with("regions:") or lower.begins_with("region:"):
				for part in line.substr(line.find(":") + 1).replace(",", " ").split(" ", false):
					var region = part.strip_edges().trim_prefix("`").trim_suffix("`")
					if region != "":
						regions.append(region)
			elif lower.begins_with("sprite:"):
				sprite = line.substr(7).strip_edges()
			elif lower.begins_with("type:"):
				character_type_id = line.substr(5).strip_edges().to_lower()
			elif lower.begins_with("npc:"):
				errors.append("archetypes use `archetype:`, not `npc:`")
			continue
		match section:
			"wants":
				if line == "" or not (line.begins_with("-") or line.begins_with("*")):
					continue
				var m = want_re.search(line)
				if m == null:
					errors.append("bad want line: %s" % line)
					continue
				var lo = int(m.get_string(2))
				var hi = int(m.get_string(3)) if m.get_string(3) != "" else lo
				if lo < 1 or hi > 10 or lo > hi:
					errors.append("want `%s` range (%d-%d) must satisfy 1 <= lo <= hi <= 10" % [m.get_string(1), lo, hi])
					continue
				wants[m.get_string(1)] = {"lo": lo, "hi": hi, "text": m.get_string(4).strip_edges()}
				want_order.append(m.get_string(1))
			"agency":
				if line == "":
					continue
				var m = agency_re.search(line)
				if m == null:
					continue
				var hook_type = m.get_string(1).to_lower()
				if hook_type != "converse":
					errors.append("archetype Agency may only grant converse: (found %s:)" % hook_type)
					continue
				for part in m.get_string(2).split(","):
					var effect = part.strip_edges().trim_prefix("`").trim_suffix("`").to_lower()
					if effect == "":
						continue
					if effect not in PERSONAL_EFFECTS:
						errors.append("converse grants %s, which is not a personal-scope effect" % effect)
					elif effect not in converse:
						converse.append(effect)
			"lines i will not cross":
				if line_re.search(line):
					lines.append(line)
			"fears":
				if line.begins_with("- ") or line.begins_with("* "):
					fears.append(line.substr(2).strip_edges())
			"voice":
				if line.begins_with("- ") or line.begins_with("* "):
					voice_variants.append(line.substr(2).strip_edges())
				else:
					voice_prose.append(raw.rstrip(" \t"))
			"life":
				life_lines.append(raw.rstrip(" \t"))
			_:
				if not prose.has(section):
					prose[section] = []
				prose[section].append(raw.rstrip(" \t"))
	essence = "\n".join(prose.get("essence", [])).strip_edges()
	secrets = "\n".join(prose.get("secrets", [])).strip_edges()
	voice_shared = "\n".join(voice_prose).strip_edges()
	if title == "":
		title = id.replace("_", " ").capitalize()
	_validate()

func _validate() -> void:
	if id == "":
		errors.append("missing `archetype:` header")
	elif not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
		errors.append("archetype id '%s' must be lowercase letters, digits and _" % id)
	if regions.is_empty():
		errors.append("missing `regions:` header")
	if wants.is_empty():
		errors.append("no wants (need at least one `id` (lo-hi): text)")
	if essence == "":
		warnings.append("no Essence prose")
	_validate_life()

## Life arcs: §8 shapes, personal-scope effects only, results prefixed with the literal {id}_
func _validate_life() -> void:
	var arc_re = RegEx.create_from_string("^###\\s*Arc:\\s*`([a-z0-9_]+)`\\s*\\(serves\\s*`([A-Za-z0-9_]+)`\\)")
	var step_re = RegEx.create_from_string("^-\\s*`([a-z0-9_]+)`\\s*:.*\\|\\s*effects:\\s*([^|]+)")
	var result_re = RegEx.create_from_string("^-\\s*result:\\s*`([^`]+)`\\s*:")
	var arcs = 0
	var arc_has_result = true
	for raw in life_lines:
		var line = raw.strip_edges()
		var m = arc_re.search(line)
		if m:
			if arcs > 0 and not arc_has_result:
				errors.append("Life arc before `%s` has no result line" % m.get_string(1))
			arcs += 1
			arc_has_result = false
			if not wants.has(m.get_string(2)):
				errors.append("Life arc `%s` serves unknown want `%s`" % [m.get_string(1), m.get_string(2)])
			continue
		m = result_re.search(line)
		if m:
			arc_has_result = true
			if not m.get_string(1).begins_with("{id}_"):
				errors.append("Life result `%s` must start with the literal {id}_" % m.get_string(1))
			continue
		m = step_re.search(line)
		if m:
			for part in m.get_string(2).split(","):
				var effect = part.strip_edges()
				if effect != "" and effect not in PERSONAL_EFFECTS:
					errors.append("Life step `%s` uses %s (personal-scope effects only)" % [m.get_string(1), effect])
	if arcs > 0 and not arc_has_result:
		errors.append("last Life arc has no result line")
	if arcs > 2:
		warnings.append("%d Life arcs (schema suggests 1-2)" % arcs)
	life_arc_count = arcs

## Replace {name}/{home}/{region}/{id} in archetype prose
static func fill_slots(text: String, slots: Dictionary) -> String:
	var out = text
	for key in slots:
		out = out.replace("{%s}" % key, str(slots[key]))
	return out

func to_debug_dict() -> Dictionary:
	return {
		"id": id, "title": title, "regions": regions, "wants": want_order.map(func(w): return "%s %d-%d" % [w, wants[w].lo, wants[w].hi]),
		"type": character_type_id, "converse": converse, "voice_variants": voice_variants.size(), "life_arcs": life_arc_count, "errors": errors
	}
