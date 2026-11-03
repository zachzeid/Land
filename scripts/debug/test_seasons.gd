extends SceneTree

# Tests the seasons and herbs that keep them (docs/PLAYER_SYSTEMS.md §4 "herbs by region and season"):
# - world.json calendar.seasons: the game opens in autumn, winter comes at season_end (day 30, 20:00),
#   then spring, summer and autumn again, 91 days each
# - Crafting.gather refuses a herb out of its season (the node's own `season`, else its ingredient's)
#   and says when it comes back; in season it gathers as before
# - the Grey Fever cure stays possible on the story's clock: fever-root gathers in autumn and winter,
#   and the white salt node has no season
# Fakes for PlayerStats and Inventory; no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_seasons.gd

const Seasons = preload("res://scripts/world/seasons.gd")
const DAY = 1440

class FakeStats extends RefCounted:
	func use_skill(_skill: String, _difficulty: float = 1.0, _context: Dictionary = {}) -> Dictionary:
		return {"gained": 0.0, "level": 0.0, "milestone": 0}
	func get_skill(_skill: String) -> float:
		return 0.0
	func has_perk(_perk: String) -> bool:
		return false
	func spend_stamina(_amount: float) -> bool:
		return true

class FakeInventory extends RefCounted:
	var records: Array = []
	func add(item_id: String, qty: int = 1, props: Dictionary = {}) -> bool:
		records.append(props.merged({"id": item_id, "qty": qty}))
		return true
	func has(item_id: String, qty: int = 1) -> bool:
		return records.filter(func(r): return r.id == item_id).reduce(func(a, r): return a + int(r.qty), 0) >= qty
	func remove(_item_id: String, _qty: int = 1) -> bool:
		return false
	func get_items() -> Array:
		return records.duplicate(true)
	func get_equipped(_slot: String) -> Dictionary:
		return {}
	func wear(_slot: String, _amount: float = 1.0) -> Dictionary:
		return {"broke": false}

var world_state: Node
var crafting: Node
var failures: int = 0
var saved_minutes: int
var saved_nodes: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	crafting = root.get_node("Crafting")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	saved_minutes = world_state.game_minutes
	saved_nodes = crafting.node_state.duplicate(true)
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	crafting.stats_override = FakeStats.new()
	crafting.inventory_override = FakeInventory.new()
	print("============================================================")
	print("🧪 SEASONS TEST")
	print("============================================================\n")

	_test_calendar()
	_test_gathering()
	_test_cure()

	crafting.stats_override = null
	crafting.inventory_override = null
	crafting.player_location_override = ""
	crafting.node_state = saved_nodes
	world_state.game_minutes = saved_minutes
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _test_calendar() -> void:
	print("Seasons on the game clock")
	var end = 29 * DAY + 20 * 60  # season_end: day 30, 20:00
	_check("The game opens in autumn", Seasons.season_at(19 * 60) == "autumn")
	_check("...and it is still autumn on Collection Night and up to season_end", Seasons.season_at(6 * DAY + 22 * 60) == "autumn" and Seasons.season_at(end - 1) == "autumn")
	_check("Winter comes at season_end", Seasons.season_at(end) == "winter")
	_check("Then spring, summer, autumn, 91 days each", Seasons.season_at(end + 91 * DAY) == "spring" and Seasons.season_at(end + 182 * DAY) == "summer" and Seasons.season_at(end + 273 * DAY) == "autumn" and Seasons.season_at(end + 364 * DAY) == "winter")
	_check("The next summer starts 182 days after season_end", Seasons.next_start("summer", 0) == end + 182 * DAY)
	_check("A list of seasons, and any", Seasons.in_season(["summer", "autumn"], "autumn") and not Seasons.in_season(["summer", "autumn"], "winter") and Seasons.in_season("any", "winter"))

func _test_gathering() -> void:
	print("\nHerbs only in their season")
	var end = 29 * DAY + 20 * 60
	world_state.game_minutes = 2 * DAY + 600  # autumn
	crafting.node_state.clear()
	crafting.player_location_override = "village_gate"
	_check("Yarrow keeps its ingredient's season (summer)", str(crafting.node_season("gate_yarrow")) == "summer")
	var r = crafting.gather("gate_yarrow")
	_check("No yarrow in autumn, and the game says when (%s)" % r.reason, not r.ok and "summer" in r.reason and "autumn" in r.reason)
	r = crafting.gather("gate_field_mushrooms")
	_check("Field mushrooms in the autumn meadow", r.ok and r.item.id == "field_mushroom")
	_check("Flax stands through summer and autumn", crafting.gather("gate_flax").ok)
	world_state.game_minutes = end + 190 * DAY  # summer
	_check("It is summer (%s)" % crafting.season_now(), crafting.season_now() == "summer")
	r = crafting.gather("gate_yarrow")
	_check("Yarrow by the road in summer", r.ok and r.item.id == "yarrow")
	_check("...and no field mushrooms then", not crafting.gather("gate_field_mushrooms").ok)
	world_state.game_minutes = end + 10 * DAY  # winter
	_check("Nothing in the nettle beds in winter", not crafting.gather("gate_nettles").ok)
	_check("...nor flax", not crafting.gather("gate_flax").ok)
	crafting.player_location_override = "ferrisford"
	_check("Willow bark is any season (winter too)", crafting.gather("ferrisford_willows").ok)
	_check("Trees and ore have no season", str(crafting.node_season("darkwood_trees")) == "any" and str(crafting.node_season("greystone_old_workings")) == "any")

func _test_cure() -> void:
	print("\nThe Grey Fever cure on the story's clock")
	crafting.node_state.clear()
	crafting.player_location_override = "forest_path"
	for when in [3 * DAY, 29 * DAY + 20 * 60 + DAY]:
		world_state.game_minutes = when
		var r = crafting.gather("darkwood_fever_root")
		_check("Fever-root digs in %s (the cure's root)" % crafting.season_now(), r.ok and r.item.id == "fever_root")
		crafting.node_state.clear()
	_check("The deep vein's white salt has no season", str(crafting.node_season("greystone_deep_vein_salt")) == "any")
	_check("The abbey garden's fever-root is any season too", str(crafting.node_season("abbey_herb_garden")) == "any")

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
