extends SceneTree
## Headless tests for the TravelMap route planner.
## Run: godot --headless --path . -s res://scripts/debug/test_travel.gd
## Exits 0 when every check passes, 1 otherwise.

const TravelMapScript = preload("res://scripts/world/travel_map.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("\n=== TravelMap route tests ===\n")
	var world: Dictionary = TravelMapScript.load_world_file(TravelMapScript.WORLD_PATH)
	_check(not world.is_empty(), "world.json loads")

	_test_real_world_invariants(world)
	var built := _all_travel_points_built(world)
	_test_shortest_paths(built)
	_test_mode_filtering(built)
	_test_multi_hop_times(built)
	_test_unbuilt_filtering(world)
	_test_unreachable(built)
	_test_ridge_trail(world, built)
	_test_text(built)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------

static func _always(_path: String) -> bool:
	return true


## world.json with every travel point marked built.
func _all_travel_points_built(world: Dictionary) -> Dictionary:
	var copy: Dictionary = world.duplicate(true)
	for loc in copy["locations"]:
		if loc.get("travel_point", false):
			loc["built"] = true
	return copy


func _plan(world: Dictionary, from: String, exists: Callable = Callable(_always)) -> Array:
	return TravelMapScript.plan_routes_for(world, from, exists)


func _find(routes: Array, dest: String) -> Dictionary:
	for route in routes:
		if route["dest"] == dest:
			return route
	return {}


func _path(route: Dictionary, mode: String) -> Array:
	var legs: Array = route["mixed"]["legs"] if mode == "mixed" else route["legs_by_mode"].get(mode, [])
	var ids: Array = []
	for leg in legs:
		if ids.is_empty():
			ids.append(leg["from"])
		ids.append(leg["to"])
	return ids


# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

func _test_real_world_invariants(world: Dictionary) -> void:
	print("-- real world.json --")
	var locs := {}
	for loc in world["locations"]:
		locs[loc["id"]] = loc
	for from in locs:
		if not locs[from].get("travel_point", false):
			continue
		for route in TravelMapScript.plan_routes_for(world, from):
			var loc: Dictionary = locs[route["dest"]]
			_check(loc.get("built", false) and loc.get("travel_point", false) and ResourceLoader.exists(loc["scene"]),
				"%s -> %s is a built travel point with a scene file" % [from, route["dest"]])
	_check(true, "every listed destination from every travel point is built and has a scene")


func _test_shortest_paths(world: Dictionary) -> void:
	print("-- shortest paths --")
	var routes := _plan(world, "village_gate")
	var gate := _find(routes, "capitol_gate")
	_check(not gate.is_empty(), "village_gate reaches capitol_gate")
	_check_eq(_path(gate, "foot"), ["village_gate", "kingsroad_waystation", "ferrisford", "capitol_gate"],
		"foot route to the Capitol goes by Ferrisford (1920) not the abbey road (2040)")
	_check_eq(gate["minutes_by_mode"].get("foot"), 1920, "village_gate -> capitol_gate on foot = 1920")

	var abbey := _find(routes, "brackenmoor_abbey")
	_check_eq(_path(abbey, "foot"), ["village_gate", "kingsroad_waystation", "fort_ashguard", "brackenmoor_abbey"],
		"foot route to the abbey goes by Fort Ashguard")

	# Greystone -> Thornhaven gate: the ridge trail reaches Iron Hollow by way of the Pit, but Iron Hollow's
	# only other road is the forest path, which is no travel point, so the gate is still by the Kingsroad.
	var from_mines := _plan(world, "greystone_mines")
	var to_gate := _find(from_mines, "village_gate")
	_check_eq(to_gate["minutes_by_mode"].get("foot"), 1080, "greystone -> village_gate on foot = 1080 by the Kingsroad")
	_check(not ("iron_hollow_camp" in _path(to_gate, "foot")), "travel map never routes through Iron Hollow")

	var ordered := true
	for i in range(1, routes.size()):
		if routes[i]["fastest_minutes"] < routes[i - 1]["fastest_minutes"]:
			ordered = false
	_check(ordered, "results are sorted fastest first")


func _test_mode_filtering(world: Dictionary) -> void:
	print("-- mode filtering --")
	var from_ford := _plan(world, "ferrisford")
	var docks := _find(from_ford, "capitol_docks")
	_check_eq(docks["minutes_by_mode"], {"barge": 600}, "ferrisford -> capitol_docks is barge only (600)")
	var gate := _find(from_ford, "capitol_gate")
	_check(not gate["minutes_by_mode"].has("barge"), "ferrisford -> capitol_gate has no barge")
	_check_eq(gate["minutes_by_mode"].keys(), ["foot", "horse", "cart"], "ferrisford -> capitol_gate: foot, horse, cart")

	# Barge appears only between Ferrisford and the docks.
	var barge_only_ok := true
	for loc in world["locations"]:
		if not loc.get("travel_point", false):
			continue
		for route in _plan(world, loc["id"]):
			if route["minutes_by_mode"].has("barge"):
				var pair := [loc["id"], route["dest"]]
				pair.sort()
				if pair != ["capitol_docks", "ferrisford"]:
					barge_only_ok = false
					print("    unexpected barge: %s" % [pair])
	_check(barge_only_ok, "barge is offered only between Ferrisford and the Capitol docks")

	var from_gate := _plan(world, "village_gate")
	var fort := _find(from_gate, "fort_ashguard")
	_check(not fort["minutes_by_mode"].has("cart"), "no cart to Fort Ashguard (that road is foot/horse)")

	# Cart may take a longer road than foot.
	var abbey := _find(from_gate, "brackenmoor_abbey")
	_check_eq(_path(abbey, "cart"),
		["village_gate", "kingsroad_waystation", "ferrisford", "capitol_gate", "brackenmoor_abbey"],
		"cart to the abbey goes round by the Capitol")
	_check_eq(abbey["minutes_by_mode"].get("cart"), 3024, "cart to the abbey = 2520 * 1.2 = 3024")

	# The docks from the valley need a change of mode: road to Ferrisford, then barge.
	var docks_from_gate := _find(from_gate, "capitol_docks")
	_check(docks_from_gate["minutes_by_mode"].is_empty(), "no single mode reaches the docks from the valley")
	_check_eq(docks_from_gate["mixed"].get("minutes"), 1320, "road and barge to the docks = 1200*0.6 + 600 = 1320")
	var modes: Array = []
	for leg in docks_from_gate["mixed"]["legs"]:
		modes.append(leg["mode"])
	_check_eq(modes, ["horse", "horse", "barge"], "mixed legs ride to Ferrisford then take the barge")
	_check_eq(docks_from_gate["fastest_mode"], "mixed", "fastest way to the docks is mixed")

	# Mixed is only offered when it beats every single mode.
	var ford := _find(from_gate, "ferrisford")
	_check(ford["mixed"].is_empty(), "no mixed option where a single mode is as fast")


func _test_multi_hop_times(world: Dictionary) -> void:
	print("-- multi-hop times --")
	var routes := _plan(world, "village_gate")
	var way := _find(routes, "kingsroad_waystation")
	_check_eq(way["minutes_by_mode"], {"foot": 720, "horse": 432, "cart": 864}, "village_gate -> waystation (one leg)")
	var ford := _find(routes, "ferrisford")
	_check_eq(ford["minutes_by_mode"], {"foot": 1200, "horse": 720, "cart": 1440}, "village_gate -> ferrisford (two legs)")
	_check_eq(ford["legs"].size(), 2, "ferrisford route has 2 legs")
	var gate := _find(routes, "capitol_gate")
	_check_eq(gate["minutes_by_mode"].get("horse"), 1152, "village_gate -> capitol_gate on horse = 1920*0.6 = 1152")
	var leg_sum := 0
	for leg in gate["legs_by_mode"]["horse"]:
		leg_sum += leg["travel_minutes"]
	_check_eq(leg_sum, gate["minutes_by_mode"]["horse"], "leg times add up to the total")

	var from_docks := _plan(world, "capitol_docks")
	_check_eq(_find(from_docks, "ferrisford")["minutes_by_mode"], {"barge": 600}, "capitol_docks -> ferrisford by barge 600")
	_check_eq(_find(from_docks, "kingsroad_waystation")["mixed"].get("minutes"), 888, "docks -> waystation = 600 + 480*0.6")


func _test_unbuilt_filtering(real_world: Dictionary) -> void:
	print("-- unbuilt filtering --")
	var world := _all_travel_points_built(real_world)
	for loc in world["locations"]:
		if loc["id"] == "ferrisford":
			loc["built"] = false
		if loc["id"] == "greystone_mines":
			loc["scene"] = "res://scenes/exterior/__no_such_scene__.tscn"

	var routes := TravelMapScript.plan_routes_for(world, "village_gate")  # real ResourceLoader check
	_check(_find(routes, "ferrisford").is_empty(), "unbuilt ferrisford is not listed")
	_check(_find(routes, "greystone_mines").is_empty(), "built location with a missing scene file is not listed")

	var stubbed := _plan(world, "village_gate")
	_check(_find(stubbed, "ferrisford").is_empty(), "unbuilt ferrisford not listed (scene check stubbed true)")
	var gate := _find(stubbed, "capitol_gate")
	_check(not gate.is_empty() and "ferrisford" in _path(gate, "foot"),
		"roads still pass through unbuilt ferrisford to the Capitol")

	var non_travel := _find(stubbed, "old_mill")
	_check(non_travel.is_empty(), "built locations without a travel point are never listed")

	var none_built := _plan(real_world.duplicate(true), "village_gate", Callable(self, "_never"))
	_check(none_built.is_empty(), "nothing is listed when no scene file exists")


func _never(_path: String) -> bool:
	return false


func _test_unreachable(world: Dictionary) -> void:
	print("-- unreachable --")
	_check(_plan(world, "thornhaven_tavern").is_empty(), "no long roads from inside the tavern")
	_check(_plan(world, "no_such_place").is_empty(), "unknown location returns []")

	var island: Dictionary = world.duplicate(true)
	island["locations"].append({"id": "lonely_tower", "name": "Lonely Tower", "region": "kingsroad",
		"kind": "exterior", "scene": "res://x.tscn", "built": true, "travel_point": true})
	_check(_find(_plan(island, "village_gate"), "lonely_tower").is_empty(), "isolated travel point is unreachable")
	_check(_plan(island, "lonely_tower").is_empty(), "nothing is reachable from an isolated travel point")


## The smugglers' ridge trail runs Iron Hollow <-> the Pit <-> Greystone (foot and horse, no cart)
func _test_ridge_trail(real_world: Dictionary, world: Dictionary) -> void:
	print("-- ridge trail (Iron Hollow, the Pit, Greystone) --")
	var pit_loc: Dictionary = {}
	for loc in real_world["locations"]:
		if loc["id"] == "the_pit":
			pit_loc = loc
	_check(not pit_loc.is_empty() and pit_loc.get("built", false) and pit_loc.get("travel_point", false)
		and ResourceLoader.exists(pit_loc.get("scene", "")), "the_pit is a built travel point with a scene file")
	_check(ResourceLoader.exists("res://resources/locations/the_pit.tres"), "the_pit has LocationData")
	var direct_ok := true
	for route in real_world["routes"]:
		var pair := [route["a"], route["b"]]
		pair.sort()
		if pair == ["greystone_mines", "iron_hollow_camp"]:
			direct_ok = false
	_check(direct_ok, "no direct Iron Hollow - Greystone road: the trail goes through the Pit")

	var from_hollow := _plan(real_world, "iron_hollow_camp")
	var pit := _find(from_hollow, "the_pit")
	_check_eq(pit.get("minutes_by_mode", {}), {"foot": 300, "horse": 180}, "iron_hollow -> the_pit: 300 on foot, 180 on horse, no cart")
	var mines := _find(from_hollow, "greystone_mines")
	_check_eq(_path(mines, "foot"), ["iron_hollow_camp", "the_pit", "greystone_mines"], "iron_hollow -> greystone walks through the Pit")
	_check_eq(mines.get("minutes_by_mode", {}).get("foot"), 600, "iron_hollow -> greystone on foot = 300 + 300")
	_check(not mines.get("minutes_by_mode", {}).has("cart"), "no cart over the ridge trail")

	var from_pit := _plan(real_world, "the_pit")
	_check_eq(_find(from_pit, "iron_hollow_camp").get("minutes_by_mode", {}).get("foot"), 300, "the_pit -> iron_hollow on foot = 300")
	_check_eq(_find(from_pit, "greystone_mines").get("minutes_by_mode", {}).get("foot"), 300, "the_pit -> greystone on foot = 300")
	var gate := _find(from_pit, "village_gate")
	_check(not gate.is_empty() and not ("iron_hollow_camp" in _path(gate, "foot")), "the_pit -> village_gate goes by Greystone and the Kingsroad, not the Hollow")

	var from_mines := _plan(real_world, "greystone_mines")
	_check_eq(_find(from_mines, "the_pit").get("minutes_by_mode", {}).get("foot"), 300, "greystone -> the_pit on foot = 300")
	_check_eq(_path(_find(from_mines, "iron_hollow_camp"), "foot"), ["greystone_mines", "the_pit", "iron_hollow_camp"], "greystone -> iron_hollow climbs through the Pit")

	# With the Pit unbuilt the trail still passes through it, but it is never offered
	var unbuilt: Dictionary = world.duplicate(true)
	for loc in unbuilt["locations"]:
		if loc["id"] == "the_pit":
			loc["built"] = false
	var hollow_unbuilt := _plan(unbuilt, "iron_hollow_camp")
	_check(_find(hollow_unbuilt, "the_pit").is_empty(), "unbuilt Pit is not listed")
	_check_eq(_path(_find(hollow_unbuilt, "greystone_mines"), "foot"), ["iron_hollow_camp", "the_pit", "greystone_mines"], "the trail still runs through an unbuilt Pit")


func _test_text(world: Dictionary) -> void:
	print("-- text --")
	_check_eq(TravelMapScript.format_duration(1920), "1d 8h", "format_duration(1920)")
	_check_eq(TravelMapScript.format_duration(432), "7h 12m", "format_duration(432)")
	_check_eq(TravelMapScript.describe_duration(240), "Four hours", "describe_duration(240)")
	_check_eq(TravelMapScript.describe_duration(1920), "A day and a half", "describe_duration(1920)")
	_check_eq(TravelMapScript.describe_duration(2880), "Two days", "describe_duration(2880)")
	var gate := _find(_plan(world, "village_gate"), "capitol_gate")
	var line: String = TravelMapScript.departure_text(2880, "foot", gate["legs_by_mode"]["foot"], world)
	_check_eq(line, "Two days on foot on the Kingsroad…", "departure text")
	var docks := _find(_plan(world, "ferrisford"), "capitol_docks")
	print("    sample: %s" % TravelMapScript.departure_text(600, "barge", docks["legs"], world))
	_check(TravelMapScript.road_name(docks["legs"], world) == "the River Ferris", "barge road is the River Ferris")


# --------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)


func _check_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_check(true, label)
	else:
		_check(false, "%s (expected %s, got %s)" % [label, expected, actual])
