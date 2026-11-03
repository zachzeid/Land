extends Node
# WorldRegistry - Typed access to resources/world/world.json (docs/WORLD_SCHEMA.md §5)
# The one place the runtime learns NPC keys, locations, the travel graph, world rules and
# forbidden concepts. world.json is authoritative; nothing else keeps a list of NPCs or places
# Autoloaded first, so every other autoload may query it from _ready()

const WORLD_PATH = "res://resources/world/world.json"
const MODES = ["foot", "horse", "cart", "barge"]

## Period-true substitutes used when sanitising speech (world.json may override with
## "forbidden_substitutes": {word: replacement}). Unlisted words become "that"
const DEFAULT_SUBSTITUTES = {
	"car": "cart", "truck": "wagon", "automobile": "carriage", "engine": "contraption", "motor": "contraption",
	"gun": "crossbow", "pistol": "dagger", "rifle": "longbow", "bullet": "bolt", "gunpowder": "lamp oil",
	"phone": "letter", "telephone": "letter", "radio": "raven", "television": "puppet show",
	"computer": "ledger", "internet": "rumour mill", "email": "letter", "electricity": "lightning",
	"electric": "lightning", "battery": "lantern", "plane": "hawk", "airplane": "hawk",
	"helicopter": "hawk", "train": "wagon train", "railway": "road", "photograph": "portrait",
	"camera": "sketchbook", "plastic": "horn", "factory": "workshop", "police": "watch",
	"cop": "watchman", "okay": "aye",
}

var data: Dictionary = {}
var source_path: String = ""

var _npc_order: Array = []           # keys in roster order
var _npcs: Dictionary = {}           # key -> roster entry
var _id_to_key: Dictionary = {}      # npc_id -> key
var _location_order: Array = []
var _locations: Dictionary = {}      # id -> location entry
var _regions: Dictionary = {}        # id -> region entry
var _adjacency: Dictionary = {}      # id -> Array of {"location", "minutes", "modes", "note"}
var _forbidden: Array = []           # lowercase words
var _forbidden_re: RegEx = null
var _canon_text: String = ""         # lowercase corpus of every proper name world.json knows
var _registered_canon: Array = []    # extra canon text (storyline titles and flags)

func _ready():
	load_world()
	print("WorldRegistry initialized (%d NPCs, %d locations, %d routes)" % [_npc_order.size(), _location_order.size(), get_route_count()])

## (Re)load world.json. Returns false when it is missing or malformed
func load_world(path: String = WORLD_PATH) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[WorldRegistry] Cannot open %s" % path)
		load_from_dict({})
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[WorldRegistry] %s is not a JSON object" % path)
		load_from_dict({})
		return false
	load_from_dict(parsed)
	source_path = path
	return true

## Replace the registry with this world (tests pass a modified copy of data)
func load_from_dict(world: Dictionary) -> void:
	data = world.duplicate(true)
	source_path = ""
	_npc_order.clear()
	_npcs.clear()
	_id_to_key.clear()
	_location_order.clear()
	_locations.clear()
	_regions.clear()
	_adjacency.clear()
	_forbidden.clear()

	for region in data.get("regions", []):
		if region is Dictionary and str(region.get("id", "")) != "":
			_regions[str(region.id)] = region
	for location in data.get("locations", []):
		if not location is Dictionary or str(location.get("id", "")) == "":
			continue
		var id = str(location.id)
		_locations[id] = location
		_location_order.append(id)
		_adjacency[id] = []
	for route in data.get("routes", []):
		if not route is Dictionary:
			continue
		var a = str(route.get("a", ""))
		var b = str(route.get("b", ""))
		if not _locations.has(a) or not _locations.has(b) or a == b:
			push_warning("[WorldRegistry] Route %s - %s names an unknown location" % [a, b])
			continue
		var minutes = maxi(int(route.get("minutes", 0)), 0)
		var modes: Array = []
		for mode in route.get("modes", ["foot"]):
			modes.append(str(mode))
		var note = str(route.get("note", ""))
		_adjacency[a].append({"location": b, "minutes": minutes, "modes": modes, "note": note})
		_adjacency[b].append({"location": a, "minutes": minutes, "modes": modes, "note": note})
	for npc in data.get("npcs", []):
		if not npc is Dictionary or str(npc.get("key", "")) == "":
			continue
		var key = str(npc.key).to_lower()
		_npcs[key] = npc
		_npc_order.append(key)
		_id_to_key[str(npc.get("npc_id", ""))] = key

	for word in data.get("forbidden_concepts", []):
		var w = str(word).strip_edges().to_lower()
		if w != "" and w not in _forbidden:
			_forbidden.append(w)
	_forbidden_re = null
	if not _forbidden.is_empty():
		var escaped: Array = []
		for w in _forbidden:
			escaped.append(_regex_escape(w))
		# Whole words, case-insensitive; a plain plural ("cars", "guns") counts as the word
		_forbidden_re = RegEx.create_from_string("(?i)\\b(%s)s?\\b" % "|".join(escaped))
	# Discovery flags (set by StoryItems) become base flags for every system
	var discovery = data.get("discovery_flags", {})
	StoryFlags.register_discovery_flags(discovery if discovery is Dictionary else {})
	# Calendar fixed points (WorldState sets them as the clock reaches them) are base flags too
	var calendar_flags: Dictionary = {}
	var calendar = data.get("calendar", {})
	if calendar is Dictionary and calendar.get("flags", {}) is Dictionary:
		for flag_name in calendar.flags:
			var entry = calendar.flags[flag_name]
			calendar_flags[str(flag_name)] = str(entry.get("description", "")) if entry is Dictionary else ""
	StoryFlags.register_calendar_flags(calendar_flags)
	_rebuild_canon()

func is_loaded() -> bool:
	return not _npcs.is_empty() or not _locations.is_empty()

# =============================================================================
# NPCS
# =============================================================================

## Roster keys in world.json order ("gregor", "elena", ...)
func get_npc_keys() -> Array:
	return _npc_order.duplicate()

func has_npc(key: String) -> bool:
	return _npcs.has(key.to_lower())

## The roster entry (key, npc_id, name, home, role, scene); {} when unknown
func get_npc(key: String) -> Dictionary:
	return _npcs.get(key.to_lower(), {})

func get_npc_id(key: String) -> String:
	return str(get_npc(key).get("npc_id", ""))

## Key for an npc_id or key ("gregor_merchant_001" or "Gregor" -> "gregor"); "" when not on the roster
## Exact matches first; then an npc_id that starts with "<key>_" (save files, dynamic copies)
func get_npc_key(npc: String) -> String:
	var lower = npc.strip_edges().to_lower()
	if lower == "":
		return ""
	if _npcs.has(lower):
		return lower
	if _id_to_key.has(npc):
		return _id_to_key[npc]
	for npc_id in _id_to_key:
		if str(npc_id).to_lower() == lower:
			return _id_to_key[npc_id]
	for key in _npc_order:
		if lower.begins_with(key + "_"):
			return key
	return ""

func get_npc_name(key: String) -> String:
	var entry = get_npc(key)
	return str(entry.get("name", key.capitalize())) if not entry.is_empty() else key.capitalize()

func get_npc_role(key: String) -> String:
	return str(get_npc(key).get("role", ""))

func get_npc_home(key: String) -> String:
	return str(get_npc(key).get("home", ""))

func get_npc_scene(key: String) -> String:
	return str(get_npc(key).get("scene", ""))

## Keys whose home is this location
func get_npcs_with_home(location_id: String) -> Array:
	return _npc_order.filter(func(k): return get_npc_home(k) == location_id)

## Keys whose home lies in this region
func get_npcs_in_region(region_id: String) -> Array:
	return _npc_order.filter(func(k): return get_region(get_npc_home(k)) == region_id)

# =============================================================================
# LOCATIONS AND REGIONS
# =============================================================================

func get_location_ids() -> Array:
	return _location_order.duplicate()

func has_location(location_id: String) -> bool:
	return _locations.has(location_id)

## The location entry (id, name, region, area, kind, scene, built, travel_point); {} when unknown
func get_location(location_id: String) -> Dictionary:
	return _locations.get(location_id, {})

func get_location_name(location_id: String) -> String:
	return str(get_location(location_id).get("name", location_id))

func is_built(location_id: String) -> bool:
	return get_location(location_id).get("built", false) == true

func get_built_locations() -> Array:
	return _location_order.filter(func(id): return is_built(id))

func get_region(location_id: String) -> String:
	return str(get_location(location_id).get("region", ""))

func get_area(location_id: String) -> String:
	return str(get_location(location_id).get("area", ""))

func get_location_scene(location_id: String) -> String:
	return str(get_location(location_id).get("scene", ""))

func is_travel_point(location_id: String) -> bool:
	return get_location(location_id).get("travel_point", false) == true

func get_locations_in_region(region_id: String) -> Array:
	return _location_order.filter(func(id): return get_region(id) == region_id)

func get_region_ids() -> Array:
	return _regions.keys()

## {id, name, summary}; {} when unknown
func get_region_info(region_id: String) -> Dictionary:
	return _regions.get(region_id, {})

func get_region_name(region_id: String) -> String:
	return str(get_region_info(region_id).get("name", region_id))

## Location whose scene file is this path ("" when none)
func get_location_for_scene(scene_path: String) -> String:
	for id in _location_order:
		if get_location_scene(id) == scene_path:
			return id
	return ""

# =============================================================================
# ROUTES (undirected; minutes are per route, modes say who may use it)
# =============================================================================

func get_route_count() -> int:
	var total = 0
	for id in _adjacency:
		total += _adjacency[id].size()
	return floori(total / 2.0)

## Direct neighbours: [{"location", "minutes", "modes", "note"}], optionally only those a mode may use
func get_neighbours(location_id: String, mode: String = "") -> Array:
	var result: Array = []
	for edge in _adjacency.get(location_id, []):
		if mode == "" or mode in edge.modes:
			result.append(edge.duplicate(true))
	return result

## The direct route between two locations ({} when they are not neighbours)
func get_route(a: String, b: String) -> Dictionary:
	for edge in _adjacency.get(a, []):
		if edge.location == b:
			return edge.duplicate(true)
	return {}

## Minutes of the direct route, -1 when a and b are not neighbours
func get_route_minutes(a: String, b: String) -> int:
	var route = get_route(a, b)
	return int(route.minutes) if not route.is_empty() else -1

## Shortest path (Dijkstra). mode "" lets every leg use any of its modes
## Returns {"minutes": int, "path": [ids from a to b]}; minutes -1 and path [] when unreachable
func find_path(a: String, b: String, mode: String = "") -> Dictionary:
	if not _locations.has(a) or not _locations.has(b):
		return {"minutes": -1, "path": []}
	if a == b:
		return {"minutes": 0, "path": [a]}
	var dist = _dijkstra(a, mode)
	if not dist.minutes.has(b):
		return {"minutes": -1, "path": []}
	var path: Array = [b]
	var current = b
	while current != a:
		current = dist.previous[current]
		path.push_front(current)
	return {"minutes": int(dist.minutes[b]), "path": path}

## Shortest travel minutes from a to b (0 when equal, -1 when unreachable)
func travel_minutes(a: String, b: String, mode: String = "") -> int:
	return int(find_path(a, b, mode).minutes)

func is_reachable(a: String, b: String, mode: String = "") -> bool:
	return travel_minutes(a, b, mode) >= 0

## Every location reachable from here: id -> minutes (excluding the start). max_minutes < 0: no limit
func get_reachable(from: String, max_minutes: int = -1, mode: String = "") -> Dictionary:
	if not _locations.has(from):
		return {}
	var dist = _dijkstra(from, mode)
	var result: Dictionary = {}
	for id in dist.minutes:
		if id != from and (max_minutes < 0 or int(dist.minutes[id]) <= max_minutes):
			result[id] = int(dist.minutes[id])
	return result

func _dijkstra(from: String, mode: String) -> Dictionary:
	var minutes: Dictionary = {from: 0}
	var previous: Dictionary = {}
	var done: Dictionary = {}
	while true:
		var best = ""
		for id in minutes:
			if not done.has(id) and (best == "" or minutes[id] < minutes[best]):
				best = id
		if best == "":
			break
		done[best] = true
		for edge in _adjacency.get(best, []):
			if mode != "" and mode not in edge.modes:
				continue
			var candidate = int(minutes[best]) + int(edge.minutes)
			if not minutes.has(edge.location) or candidate < int(minutes[edge.location]):
				minutes[edge.location] = candidate
				previous[edge.location] = best
	return {"minutes": minutes, "previous": previous}

# =============================================================================
# WORLD RULES AND FORBIDDEN CONCEPTS
# =============================================================================

func get_realm() -> String:
	return str(data.get("realm", ""))

func get_era() -> String:
	return str(data.get("era", ""))

func get_world_rules() -> Array:
	return data.get("world_rules", []).duplicate()

## world.json "opening_hours": [open_hour, close_hour) on the game clock, for every place and NPC
## (nobody acts or arrives anywhere outside them). Without the key the world never closes
func get_opening_hours() -> Array:
	var hours = data.get("opening_hours", {})
	if not hours is Dictionary:
		return [0, 24]
	return [int(hours.get("open_hour", 0)), int(hours.get("close_hour", 24))]

## world.json "calendar": {"start": {day, hour, minute}, "flags": {flag: {day, hour, description}}}
func get_calendar() -> Dictionary:
	var calendar = data.get("calendar", {})
	return calendar.duplicate(true) if calendar is Dictionary else {}

## world.json "discovery_flags": flag -> canonical text (StoryItems set them; base flags at runtime)
func get_discovery_flags() -> Dictionary:
	var discovery = data.get("discovery_flags", {})
	return discovery.duplicate() if discovery is Dictionary else {}

func get_forbidden_concepts() -> Array:
	return _forbidden.duplicate()

## Forbidden concepts used in text (whole word, case-insensitive), lowercase, each once, in order
func find_forbidden_concepts(text: String) -> Array:
	var found: Array = []
	if _forbidden_re == null or text == "":
		return found
	for m in _forbidden_re.search_all(text):
		var word = m.get_string(1).to_lower()
		if word not in found:
			found.append(word)
	return found

func contains_forbidden_concept(text: String) -> bool:
	return _forbidden_re != null and text != "" and _forbidden_re.search(text) != null

## Replace every forbidden concept with a period-true substitute, keeping capitalisation
func sanitize_forbidden(text: String) -> String:
	if _forbidden_re == null or text == "":
		return text
	var substitutes: Dictionary = DEFAULT_SUBSTITUTES.duplicate()
	var authored = data.get("forbidden_substitutes", {})
	if authored is Dictionary:
		for word in authored:
			substitutes[str(word).to_lower()] = str(authored[word])
	var result = ""
	var cursor = 0
	for m in _forbidden_re.search_all(text):
		result += text.substr(cursor, m.get_start() - cursor)
		var original = m.get_string(0)
		var word = m.get_string(1).to_lower()
		var replacement = str(substitutes.get(word, "that"))
		if original.length() > word.length() and replacement != "that":
			replacement += "s"
		var first = original.substr(0, 1)
		if first == first.to_upper() and first != first.to_lower():
			replacement = replacement.substr(0, 1).to_upper() + replacement.substr(1)
		result += replacement
		cursor = m.get_end()
	return result + text.substr(cursor)

# =============================================================================
# CANON NAMES (hallucination checks: is this proper name something the world knows?)
# =============================================================================

## Extra canon text (StorylineDirector registers storyline titles, beat titles and flag text)
## Accepts one String or an Array of them
func register_canon_text(texts) -> void:
	for text in (texts if texts is Array else [texts]):
		if str(text).strip_edges() != "":
			_registered_canon.append(str(text).to_lower())
	_rebuild_canon()

func clear_registered_canon() -> void:
	_registered_canon.clear()
	_rebuild_canon()

## True when a proper name ("The Lantern Market", "Corwin", "Lord Protector") appears in the
## world's own text: NPC names and roles, location, area and region names, realm, era, rules,
## and registered storyline text. A leading "The" is ignored
func is_canon_name(name: String) -> bool:
	var lower = name.strip_edges().to_lower()
	if lower.begins_with("the "):
		lower = lower.substr(4)
	lower = _normalize_words(lower)
	if lower.length() < 3:
		return false
	return (" " + lower + " ") in _canon_text

func _rebuild_canon() -> void:
	var parts: Array = [get_realm(), get_era()]
	parts.append_array(get_world_rules())
	for key in _npc_order:
		parts.append(str(_npcs[key].get("name", "")))
		parts.append(str(_npcs[key].get("role", "")))
		parts.append(key)
	for id in _location_order:
		parts.append(str(_locations[id].get("name", "")))
		parts.append(str(_locations[id].get("area", "")))
	for id in _regions:
		parts.append(str(_regions[id].get("name", "")))
		parts.append(str(_regions[id].get("summary", "")))
	parts.append_array(get_discovery_flags().values())
	parts.append_array(_registered_canon)
	# Words only, single-spaced and padded, so a name matches on whole words ("old inn" never hits "hold inn")
	_canon_text = " " + _normalize_words(" | ".join(parts.map(func(p): return str(p))).to_lower()) + " "

## Lowercase letters, digits and apostrophes kept; every other run of characters becomes one space
func _normalize_words(text: String) -> String:
	var out = ""
	var space = false
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" or c.unicode_at(0) > 127:
			out += c
			space = false
		elif not space:
			out += " "
			space = true
	return out.strip_edges()

func _regex_escape(text: String) -> String:
	var out = ""
	for c in text:
		if c in "\\^$.|?*+()[]{}":
			out += "\\"
		out += c
	return out
