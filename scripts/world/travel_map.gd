extends Node
## TravelMap - Long-distance travel between travel points along world.json routes.
## Autoload singleton. TravelPoint nodes call open(from_location).
##
## The road network is the world.json `routes` graph restricted to locations with
## `"travel_point": true`. A journey may pass through any travel point (built or not,
## because the road exists even when the town is not playable yet), but only built
## travel points whose scene file exists are offered as destinations.
## Walking-scale places (shops, the Capitol market, Iron Hollow) are reached on foot
## through SceneTriggers, never from this map.
##
## Times: a route's `minutes` is the time on foot (the same figure SceneManager and
## NPC moves use). Other modes scale it by MODE_PACE.
##
## Headless testing: plan_routes(from) and the static plan_routes_for(world, from,
## scene_exists) need no scene tree. See scripts/debug/test_travel.gd.

## Fired just before the clock advances and the scene changes. Road events hook here.
signal journey_started(from_location: String, to_location: String, minutes: int)
## Fired once the destination scene has loaded. Storylines react to arrivals here.
signal journey_completed(from_location: String, to_location: String, minutes: int)
signal map_opened(from_location: String)
signal map_closed()

const WORLD_PATH := "res://resources/world/world.json"
const UI_SCENE_PATH := "res://scenes/ui/travel_map.tscn"
const ARRIVAL_SPAWN := "from_travel"

## Modes in display order.
const MODES := ["foot", "horse", "cart", "barge"]
## Multiplier on a route's listed (on-foot) minutes.
const MODE_PACE := {"foot": 1.0, "horse": 0.6, "cart": 1.2, "barge": 1.0}
## Pseudo-mode for a journey that changes mode on the way (road then barge).
const MIXED := "mixed"

const MODE_LABELS := {
	"foot": "On foot",
	"horse": "On horseback",
	"cart": "By cart",
	"barge": "By barge",
	"mixed": "By road and river",
}

const _MODE_PHRASES := {
	"foot": "on foot",
	"horse": "in the saddle",
	"cart": "behind a cart horse",
	"barge": "by barge",
	"mixed": "by road and river",
}

const _NUMBER_WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
	"nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
	"seventeen", "eighteen", "nineteen", "twenty"]

var is_open: bool = false
var is_travelling: bool = false
## The journey in progress or last completed: {from, to, mode, minutes, legs}
var current_journey: Dictionary = {}

var _world: Dictionary = {}
var _ui = null
var _open_from: String = ""
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --------------------------------------------------------------------------
# World data
# --------------------------------------------------------------------------

## world.json as a Dictionary, loaded once.
func get_world() -> Dictionary:
	if _world.is_empty():
		_world = load_world_file(WORLD_PATH)
	return _world


## Drop the cached world data (e.g. after world.json flips a location to built).
func reload_world() -> void:
	_world = {}


static func load_world_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[TravelMap] Cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("[TravelMap] %s is not a JSON object" % path)
	return {}


# --------------------------------------------------------------------------
# Route planning (pure)
# --------------------------------------------------------------------------

## Every destination reachable from `from_location`, fastest first.
## Each entry: {
##   dest, name, region,
##   minutes_by_mode: {mode: int}  (each mode's shortest path, using only roads that allow it),
##   legs_by_mode:    {mode: [leg]},
##   mixed:           {} or {minutes, legs}  (only when changing mode beats every single mode),
##   fastest_mode, fastest_minutes,
##   legs:            legs of the fastest option
## }
## leg = {from, to, minutes (listed, on foot), modes (allowed on that road), mode, travel_minutes}
## `world` defaults to world.json; `scene_exists(path) -> bool` defaults to ResourceLoader.exists.
func plan_routes(from_location: String, world: Dictionary = {}, scene_exists: Callable = Callable()) -> Array:
	var data: Dictionary = world if not world.is_empty() else get_world()
	return plan_routes_for(data, from_location, scene_exists)


static func plan_routes_for(world: Dictionary, from_location: String, scene_exists: Callable = Callable()) -> Array:
	var exists_fn: Callable = scene_exists
	if not exists_fn.is_valid():
		exists_fn = func(path: String) -> bool: return path != "" and ResourceLoader.exists(path)

	var locs := {}
	for loc in world.get("locations", []):
		if loc is Dictionary and loc.has("id"):
			locs[loc["id"]] = loc
	if not locs.has(from_location):
		return []

	var adjacency := _build_adjacency(world, locs)

	var per_mode := {}
	for mode in MODES:
		per_mode[mode] = _shortest_paths(adjacency, from_location, mode)
	var mixed_tree := _shortest_paths(adjacency, from_location, MIXED)

	var results: Array = []
	var ids: Array = locs.keys()
	ids.sort()
	for dest in ids:
		if dest == from_location:
			continue
		var loc: Dictionary = locs[dest]
		if not is_destination(loc, exists_fn):
			continue

		var minutes_by_mode := {}
		var legs_by_mode := {}
		for mode in MODES:
			var tree: Dictionary = per_mode[mode]
			if tree["dist"].has(dest):
				var legs := _legs_to(tree, dest)
				minutes_by_mode[mode] = _sum_travel(legs)
				legs_by_mode[mode] = legs

		var mixed := {}
		if mixed_tree["dist"].has(dest):
			var mlegs := _legs_to(mixed_tree, dest)
			var mminutes := _sum_travel(mlegs)
			var used := {}
			for leg in mlegs:
				used[leg["mode"]] = true
			var best_single: float = INF
			for m in minutes_by_mode:
				best_single = minf(best_single, float(minutes_by_mode[m]))
			if used.size() > 1 and mminutes < best_single:
				mixed = {"minutes": mminutes, "legs": mlegs}

		if minutes_by_mode.is_empty() and mixed.is_empty():
			continue  # unreachable

		var fastest_mode := ""
		var fastest_minutes := 0
		for mode in MODES:
			if minutes_by_mode.has(mode) and (fastest_mode == "" or minutes_by_mode[mode] < fastest_minutes):
				fastest_mode = mode
				fastest_minutes = minutes_by_mode[mode]
		if not mixed.is_empty():
			fastest_mode = MIXED
			fastest_minutes = mixed["minutes"]

		results.append({
			"dest": dest,
			"name": loc.get("name", dest),
			"region": loc.get("region", ""),
			"minutes_by_mode": minutes_by_mode,
			"legs_by_mode": legs_by_mode,
			"mixed": mixed,
			"fastest_mode": fastest_mode,
			"fastest_minutes": fastest_minutes,
			"legs": mixed["legs"] if fastest_mode == MIXED else legs_by_mode[fastest_mode],
		})

	results.sort_custom(func(a, b):
		if a["fastest_minutes"] != b["fastest_minutes"]:
			return a["fastest_minutes"] < b["fastest_minutes"]
		return a["dest"] < b["dest"])
	return results


## A location the map may offer: a built travel point whose scene file exists.
static func is_destination(loc: Dictionary, scene_exists: Callable) -> bool:
	if not loc.get("travel_point", false):
		return false
	if not loc.get("built", false):
		return false
	return bool(scene_exists.call(str(loc.get("scene", ""))))


## id -> [{to, minutes, modes}], keeping only roads into travel points.
static func _build_adjacency(world: Dictionary, locs: Dictionary) -> Dictionary:
	var adjacency := {}
	for route in world.get("routes", []):
		if not (route is Dictionary):
			continue
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if not locs.has(a) or not locs.has(b):
			continue
		var minutes := int(route.get("minutes", 0))
		var modes: Array = []
		for m in route.get("modes", []):
			if MODE_PACE.has(m):
				modes.append(m)
		if modes.is_empty():
			continue
		for pair in [[a, b], [b, a]]:
			if not locs[pair[1]].get("travel_point", false):
				continue
			if not adjacency.has(pair[0]):
				adjacency[pair[0]] = []
			adjacency[pair[0]].append({"to": pair[1], "minutes": minutes, "modes": modes})
	return adjacency


## Mode used on one road: the travel mode itself, or for MIXED the fastest one allowed.
static func _leg_mode(edge: Dictionary, mode: String) -> String:
	if mode != MIXED:
		return mode if mode in edge["modes"] else ""
	var best := ""
	for m in MODES:
		if m in edge["modes"] and (best == "" or MODE_PACE[m] < MODE_PACE[best]):
			best = m
	return best


## Dijkstra over the travel-point graph. Small graph: O(n^2) selection, ties broken by id.
static func _shortest_paths(adjacency: Dictionary, start: String, mode: String) -> Dictionary:
	var dist := {start: 0.0}
	var prev := {}  # id -> {from, edge, mode}
	var done := {}
	while true:
		var current := ""
		for id in dist:
			if done.has(id):
				continue
			if current == "" or dist[id] < dist[current] or (dist[id] == dist[current] and id < current):
				current = id
		if current == "":
			break
		done[current] = true
		for edge in adjacency.get(current, []):
			var leg_mode := _leg_mode(edge, mode)
			if leg_mode == "":
				continue
			var to: String = edge["to"]
			if done.has(to):
				continue
			var cost: float = dist[current] + edge["minutes"] * MODE_PACE[leg_mode]
			if not dist.has(to) or cost < dist[to]:
				dist[to] = cost
				prev[to] = {"from": current, "edge": edge, "mode": leg_mode}
	dist.erase(start)
	return {"dist": dist, "prev": prev}


static func _legs_to(tree: Dictionary, dest: String) -> Array:
	var legs: Array = []
	var node := dest
	while tree["prev"].has(node):
		var step: Dictionary = tree["prev"][node]
		var edge: Dictionary = step["edge"]
		legs.push_front({
			"from": step["from"],
			"to": node,
			"minutes": edge["minutes"],
			"modes": edge["modes"].duplicate(),
			"mode": step["mode"],
			"travel_minutes": int(round(edge["minutes"] * MODE_PACE[step["mode"]])),
		})
		node = step["from"]
	return legs


static func _sum_travel(legs: Array) -> int:
	var total := 0
	for leg in legs:
		total += int(leg["travel_minutes"])
	return total


# --------------------------------------------------------------------------
# Text helpers (pure)
# --------------------------------------------------------------------------

## Compact duration for lists: "45m", "7h 12m", "1d 8h".
static func format_duration(minutes: int) -> String:
	if minutes < 60:
		return "%dm" % minutes
	var days := floori(minutes / 1440.0)
	var hours := floori((minutes - days * 1440) / 60.0)
	var mins := minutes - days * 1440 - hours * 60
	if days > 0:
		return ("%dd %dh" % [days, hours]) if hours > 0 else ("%dd" % days)
	return ("%dh %dm" % [hours, mins]) if mins > 0 else ("%dh" % hours)


static func _number_word(n: int) -> String:
	return _NUMBER_WORDS[n] if n >= 0 and n < _NUMBER_WORDS.size() else str(n)


static func _sentence_case(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


## Story-voice duration: "Four hours", "A day and a half", "Two days".
static func describe_duration(minutes: int) -> String:
	if minutes < 60:
		return "Less than an hour"
	if minutes < 1080:
		var hours := roundi(minutes / 60.0)
		return "An hour" if hours == 1 else _sentence_case("%s hours" % _number_word(hours))
	var half_days := roundi(minutes / 720.0)
	var days := floori(half_days / 2.0)
	var half := half_days % 2 == 1
	if days == 1:
		return "A day and a half" if half else "A day"
	var word := _sentence_case(_number_word(days))
	return ("%s and a half days" % word) if half else ("%s days" % word)


## The road a journey mostly follows: "the Kingsroad", "the March roads", "the River Ferris".
static func road_name(legs: Array, world: Dictionary) -> String:
	var regions := {}
	for loc in world.get("locations", []):
		if loc is Dictionary:
			regions[loc.get("id", "")] = loc.get("region", "")
	var weight := {}
	for leg in legs:
		var road := "the Kingsroad"
		if leg["mode"] == "barge":
			road = "the River Ferris"
		elif regions.get(leg["from"], "") == "eastern_march" or regions.get(leg["to"], "") == "eastern_march":
			road = "the March roads"
		weight[road] = weight.get(road, 0) + int(leg["travel_minutes"])
	var best := "the Kingsroad"
	for road in weight:
		if weight[road] > weight.get(best, -1):
			best = road
	return best


## First line of the arrival card, e.g. "A day and a half in the saddle on the Kingsroad…"
static func departure_text(minutes: int, mode: String, legs: Array, world: Dictionary) -> String:
	var road := road_name(legs, world)
	var prep := "down" if road == "the River Ferris" else "on"
	return "%s %s %s %s…" % [describe_duration(minutes), _MODE_PHRASES.get(mode, "on the road"), prep, road]


func location_name(location_id: String) -> String:
	for loc in get_world().get("locations", []):
		if loc is Dictionary and loc.get("id", "") == location_id:
			return loc.get("name", location_id)
	return location_id


# --------------------------------------------------------------------------
# Runtime: map UI and journeys
# --------------------------------------------------------------------------

## Show the travel map for the travel point at `from_location`. Pauses gameplay; Esc closes.
func open(from_location: String) -> void:
	if is_open or is_travelling:
		return
	var ui = _ensure_ui()
	if ui == null:
		return
	var routes := _playable_routes(from_location)
	_open_from = from_location
	_was_paused = get_tree().paused
	get_tree().paused = true
	is_open = true
	ui.show_routes(from_location, location_name(from_location), routes)
	print("[TravelMap] Opened at %s: %d destination(s)" % [from_location, routes.size()])
	map_opened.emit(from_location)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if _ui:
		_ui.hide_map()
	get_tree().paused = _was_paused
	map_closed.emit()


## Travel to `dest` by `mode` ("" = fastest). Usable from the UI, debug console or storylines.
## Coroutine: await it to wait for arrival. Returns false if the journey is not possible.
func travel_to(dest: String, mode: String = "", from_location: String = "") -> bool:
	if is_travelling:
		return false
	var from := from_location
	if from == "":
		from = _open_from if is_open else _current_location_id()
	var entry := {}
	for route in _playable_routes(from):
		if route["dest"] == dest:
			entry = route
			break
	if entry.is_empty():
		push_warning("[TravelMap] No road from %s to %s" % [from, dest])
		return false

	if mode == "":
		mode = entry["fastest_mode"]
	var minutes := 0
	var legs: Array = []
	if mode == MIXED and not entry["mixed"].is_empty():
		minutes = entry["mixed"]["minutes"]
		legs = entry["mixed"]["legs"]
	elif entry["minutes_by_mode"].has(mode):
		minutes = entry["minutes_by_mode"][mode]
		legs = entry["legs_by_mode"][mode]
	else:
		push_warning("[TravelMap] Mode %s not possible from %s to %s" % [mode, from, dest])
		return false

	# Leave the map; the scene change needs the tree running.
	if is_open:
		is_open = false
		if _ui:
			_ui.hide_map()
		map_closed.emit()
	get_tree().paused = false

	is_travelling = true
	current_journey = {"from": from, "to": dest, "mode": mode, "minutes": minutes, "legs": legs}
	print("[TravelMap] Journey %s -> %s by %s, %d min" % [from, dest, mode, minutes])

	var ui = _ensure_ui()
	if ui:
		ui.begin_arrival_card(departure_text(minutes, mode, legs, get_world()))

	journey_started.emit(from, dest, minutes)
	_advance_clock(minutes)

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		await scene_manager.transition_to(dest, ARRIVAL_SPAWN)
	else:
		push_warning("[TravelMap] No SceneManager; cannot change scene to %s" % dest)

	journey_completed.emit(from, dest, minutes)

	if ui:
		await ui.finish_arrival_card("you arrive at %s." % entry["name"])
	is_travelling = false
	return true


## Destinations from plan_routes that SceneManager can actually load.
func _playable_routes(from_location: String) -> Array:
	var routes := plan_routes(from_location)
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager == null or not scene_manager.has_method("get_location"):
		return routes
	var playable: Array = []
	for route in routes:
		if scene_manager.get_location(route["dest"]) != null:
			playable.append(route)
		else:
			push_warning("[TravelMap] %s is built but has no LocationData in resources/locations; not listed" % route["dest"])
	return playable


func _advance_clock(minutes: int) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and world_state.has_method("advance_time"):
		world_state.advance_time(minutes, "travel")
	else:
		print("[TravelMap] WorldState.advance_time not available yet; clock not advanced (%d min)" % minutes)


func _current_location_id() -> String:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("get_current_location_id"):
		return scene_manager.get_current_location_id()
	return ""


func _ensure_ui():
	if _ui and is_instance_valid(_ui):
		return _ui
	var packed: PackedScene = load(UI_SCENE_PATH)
	if packed == null:
		push_error("[TravelMap] Cannot load %s" % UI_SCENE_PATH)
		return null
	_ui = packed.instantiate()
	add_child(_ui)
	_ui.destination_chosen.connect(func(dest: String, mode: String): travel_to(dest, mode))
	_ui.close_requested.connect(close)
	return _ui
