extends SceneTree

# Tests The Tithe Night's calendar and opening (docs/STORY_NARRATIVE.md, "The seven days"):
# - world.json calendar: a new game starts at calendar.start (day 1, 20:00)
# - fixed points fire in order, exactly once, across long time jumps, re-entrant listeners,
#   JSON save/load and saves from before the calendar existed
# - they are world-caused (no witnesses), base flags with descriptions, known to the Director,
#   and no storyline effect may set them
# - the debug command `day <n>`
# - the opening: congregation gathered in the chapel at 20:00, a skippable establishing card that hands
#   control to the player, the drawing (tn_drawing, 20:10) setting tithe_drawing_witnessed for a player
#   in the chapel, the congregation walking home afterwards, and nothing writing a save
#   (the opening's choices are in test_opening.gd)
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_calendar.gd

const CALENDAR_ORDER = ["tn_day_2", "tn_day_3", "tn_day_4", "tn_day_5", "tn_day_6", "tn_day_7", "tn_collection_night"]
const DAY = 24 * 60

class FakeMemory extends Node:
	var stored: Array = []
	func store(data: Dictionary, _custom_id: String = "", _skip_validation: bool = false) -> bool:
		stored.append(data)
		return true

class FakeNPC extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true
	var _is_initialized: bool = true
	var rag_memory: Node
	var location: String = ""
	func get_current_location() -> String:
		return location

var world_state: Node
var director: Node
var registry: Node
var propagator: Node
var scene_manager: Node
var failures: int = 0
var fired_log: Array = []
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var saved_fired: Dictionary
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	propagator = root.get_node("EventPropagator")
	scene_manager = root.get_node("SceneManager")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_fired = world_state._calendar_fired.duplicate()
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	root.get_node("EventBus").calendar_flag_fired.connect(func(flag, _at): if flag in CALENDAR_ORDER: fired_log.append(flag))

	print("============================================================")
	print("🧪 CALENDAR + OPENING TEST")
	print("============================================================\n")

	_test_calendar_loaded()
	_test_long_jump()
	_test_reentrant_listener()
	_test_world_caused()
	_test_save_load()
	_test_old_save()
	_test_effects_cannot_set()
	_test_day_command()
	await _test_opening()

	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	world_state._calendar_fired = saved_fired
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# CALENDAR
# =============================================================================

func _test_calendar_loaded():
	print("world.json calendar")
	# The seven days (the drawing, its eve and season_end are checked in test_opening / the director's tests)
	var calendar: Array = world_state.get_calendar().filter(func(e): return e.flag in CALENDAR_ORDER)
	_check("Seven fixed points, in clock order", calendar.map(func(e): return e.flag) == CALENDAR_ORDER)
	_check("A new game starts at calendar.start: day 1, 20:00", world_state.start_minute == 20 * 60)
	_fresh()
	_check("...which reads 'Day 1, 20:00', evening", world_state.get_time_string() == "Day 1, 20:00" and world_state.get_time_of_day() == "evening")
	_check("tn_day_2 falls on day 2, 06:00", calendar[0].minute == DAY + 6 * 60)
	_check("Collection Night is day 7, 22:00", calendar[6].minute == 6 * DAY + 22 * 60)
	var described = true
	for entry in calendar:
		var text = registry.get_calendar().flags[entry.flag].description
		if StoryFlags.get_flag_description(entry.flag) != text or not StoryFlags.is_base_flag(entry.flag) or not director.is_known_flag(entry.flag):
			described = false
	_check("Each has its world.json description, is a base flag and a known flag", described)
	_check("...and is a calendar flag, not a discovery flag", StoryFlags.is_calendar_flag("tn_day_4") and not StoryFlags.is_discovery_flag("tn_day_4") and not StoryFlags.is_calendar_flag("ledger_found"))
	_check("Nonsense is still unknown", not director.is_known_flag("tn_day_9"))
	_check("Mornings: day 4 at 06:00", world_state.get_morning_minute(4) == 3 * DAY + 6 * 60)

func _test_long_jump():
	print("Long time jumps")
	_fresh()
	world_state.advance_time(10, "walk")
	_check("Ten minutes fire nothing", fired_log.is_empty())
	# Day 1 20:10 -> day 5 09:10 in one journey
	world_state.advance_time(3 * DAY + 13 * 60, "travel:long")
	_check("One long journey fires days 2-5, in order", fired_log == ["tn_day_2", "tn_day_3", "tn_day_4", "tn_day_5"])
	_check("Their flags are true; day 6 is not", world_state.get_world_flag("tn_day_5") and not world_state.get_world_flag("tn_day_6"))
	world_state.advance_time(60, "walk")
	_check("Nothing fires twice", fired_log.size() == 4)
	world_state.world_flags["tn_day_3"] = false  # something cleared it (debug, a test)
	world_state.advance_time(60, "walk")
	world_state.fire_due_calendar_flags()
	_check("A fixed point never fires again, even if its flag was cleared", fired_log.size() == 4 and not world_state.get_world_flag("tn_day_3"))
	world_state.advance_time(10 * DAY, "travel:very_long")
	_check("Ten more days fire the rest, Collection Night last", fired_log == CALENDAR_ORDER)
	_check("All fired, each recorded", world_state.get_calendar().filter(func(e): return e.flag in CALENDAR_ORDER).all(func(e): return e.fired))

func _test_reentrant_listener():
	print("A listener that moves the clock")
	_fresh()
	var bus = root.get_node("EventBus")
	var pusher = func(flag, _at):
		if flag == "tn_day_2":
			world_state.advance_time(2 * DAY, "listener")
	bus.calendar_flag_fired.connect(pusher)
	world_state.advance_time(DAY, "walk")  # day 2, 20:00
	bus.calendar_flag_fired.disconnect(pusher)
	_check("Order holds and nothing repeats", fired_log == ["tn_day_2", "tn_day_3", "tn_day_4"])
	_check("The clock is where the listener left it", world_state.get_day() == 4 and world_state.get_hour() == 20)

func _test_world_caused():
	print("World-caused, not player-caused")
	_fresh()
	var seen: Array = []
	var watcher = func(flag, _old, value):
		if value == true:
			seen.append([flag, world_state.is_world_change()])
	root.get_node("EventBus").world_flag_changed.connect(watcher)
	world_state.advance_time(DAY, "walk")
	root.get_node("EventBus").world_flag_changed.disconnect(watcher)
	_check("The calendar sets its flag as a world change", seen.size() == 1 and seen[0] == ["tn_day_2", true])
	_check("...and only while it is setting it", not world_state.is_world_change())

	# A flag the world sets is witnessed by nobody; the same kind of flag set by the player is
	propagator.load_from_dict({})
	var npc = _fake_npc("gregor_merchant_001", "")
	world_state.world_flags.erase("pit_seam_names_seen")
	world_state._world_change_depth += 1
	world_state.set_world_flag("pit_seam_names_seen", true)
	world_state._world_change_depth -= 1
	_check("No witness memory for a world-caused change", npc.rag_memory.stored.is_empty())
	world_state.world_flags.erase("pit_tally_book_found")
	world_state.set_world_flag("pit_tally_book_found", true)
	_check("...while the player's own discovery is witnessed", npc.rag_memory.stored.size() == 1)
	npc.remove_from_group("npcs")
	npc.free()
	propagator.load_from_dict({})

func _test_save_load():
	print("Save and load")
	_fresh()
	world_state.advance_time(3 * DAY + 12 * 60, "travel")  # day 5, 08:00
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))
	_check("The save carries which fixed points fired", saved.get("calendar_fired", {}).keys().filter(func(f): return f in CALENDAR_ORDER) == ["tn_day_2", "tn_day_3", "tn_day_4", "tn_day_5"])
	_fresh()
	world_state.load_from_dict(saved)
	_check("Loading restores the clock", world_state.get_time_string() == "Day 5, 08:00")
	_check("...and fires nothing", fired_log.is_empty() and world_state.has_calendar_fired("tn_day_4") and not world_state.has_calendar_fired("tn_day_6"))
	world_state.fire_due_calendar_flags()
	_check("A check after loading fires nothing either", fired_log.is_empty())
	world_state.advance_time(2 * DAY + 15 * 60, "travel")  # day 7, 23:00
	_check("Travel after loading fires only what is left, in order", fired_log == ["tn_day_6", "tn_day_7", "tn_collection_night"])

func _test_old_save():
	print("A save from before the calendar")
	_fresh()
	var old = {"world_flags": {"tn_day_2": true, "ledger_found": true}, "npc_states": {}, "game_minutes": 2 * DAY + 10 * 60}
	world_state.load_from_dict(old)
	_check("A fixed point already true counts as fired", world_state.has_calendar_fired("tn_day_2"))
	_check("One still due waits for the next check", not world_state.has_calendar_fired("tn_day_3") and fired_log.is_empty())
	world_state.fire_due_calendar_flags()
	_check("...which fires it, once", fired_log == ["tn_day_3"])
	var bare = {"world_flags": {}, "npc_states": {}}
	world_state.load_from_dict(bare)
	_check("A save with no clock starts at calendar.start", world_state.get_game_minutes() == world_state.start_minute)

func _test_effects_cannot_set():
	print("Storyline effects")
	var check: Dictionary = director._effects.validate({"type": "set_flag", "flag": "tn_collection_night"})
	_check("No effect may set a calendar flag", not check.ok and "calendar" in str(check.reason))
	var rumor: Dictionary = director._effects.validate({"type": "spread_rumor", "flag": "tn_day_3", "to": ["mira"]})
	_check("...but one may spread word of it", rumor.ok)

func _test_day_command():
	print("Debug command: day <n>")
	_fresh()
	var console = load("res://scenes/ui/debug_console.tscn").instantiate()
	root.add_child(console)
	console._on_command_submitted("day 4")
	_check("'day 4' goes to day 4, 06:00", world_state.get_time_string() == "Day 4, 06:00")
	_check("...firing the mornings on the way", fired_log == ["tn_day_2", "tn_day_3", "tn_day_4"])
	console._on_command_submitted("day 2")
	_check("'day 2' afterwards does not turn the clock back", world_state.get_time_string() == "Day 4, 06:00")
	console._on_command_submitted("day x")
	_check("Bad input changes nothing", world_state.get_time_string() == "Day 4, 06:00")
	console._on_command_submitted("calendar")
	console.queue_free()

# =============================================================================
# OPENING
# =============================================================================

func _test_opening():
	print("The opening (the drawing)")
	_fresh()
	world_state.world_flags.erase("tithe_drawing_witnessed")
	var opening = scene_manager.opening
	_check("SceneManager owns the opening", opening != null and opening.has_method("play"))
	if opening == null:
		return
	opening.reset()
	if not save_existed:
		_check("No save file: it is a new game and the opening wants to play", world_state.is_new_game() and opening.should_play())
	var gathered: Array = opening.gather_congregation()
	_check("The five gather in the chapel", gathered == ["mathias", "gregor", "elena", "mira", "bjorn"])
	var spawner = scene_manager.npc_spawner
	var all_there = gathered.all(func(k): return spawner.should_be_at(k, "thornhaven_chapel"))
	_check("The spawner puts them in the chapel", all_there and not spawner.should_be_at("aldric", "thornhaven_chapel") and not spawner.should_be_at("mathias", "thornhaven_town_square"))

	var finished: Array = []
	var on_finished = func(skipped): finished.append(skipped)
	opening.opening_finished.connect(on_finished)
	var real_location = scene_manager.current_location
	scene_manager.current_location = scene_manager.get_location("thornhaven_chapel")  # the player stands in the chapel
	opening.playing = true  # as play() would, without loading scenes headless
	opening.show_establishing()
	_check("A short establishing card, and no flag yet", opening.get_card_kind() == "establishing" and not world_state.get_world_flag("tithe_drawing_witnessed"))
	_check("It will not play twice", not opening.should_play())
	opening.skip()
	await process_frame
	_check("Skip ends it at once and hands control to the player", finished == [true] and opening.get_node_or_null("OpeningNarration") == null and opening.phase == "awaiting")
	opening.opening_finished.disconnect(on_finished)
	world_state.advance_time(10, "idle")
	_check("At 20:10 the drawing sets tithe_drawing_witnessed for the player in the chapel", world_state.has_calendar_fired("tn_drawing")
		and world_state.get_world_flag("tithe_drawing_witnessed") and opening.get_card_kind() == "drawing")
	_check("The flag is a discovery flag with canon text", StoryFlags.is_discovery_flag("tithe_drawing_witnessed") and StoryFlags.get_flag_description("tithe_drawing_witnessed").contains("Elena"))
	opening.skip()
	scene_manager.current_location = real_location

	# The drawing breaks up two hours after they gathered, if the player lingers
	world_state.advance_time(50, "idle")
	_check("An hour later they are still at the drawing", spawner.should_be_at("gregor", "thornhaven_chapel"))
	world_state.advance_time(60, "idle")
	var gregor_id = registry.get_npc_id("gregor")
	_check("At 22:00 they set off home", world_state.is_npc_travelling(gregor_id) and world_state.get_npc_location(gregor_id) == "thornhaven_gregor_shop")
	world_state.advance_time(60, "idle")
	_check("...and arrive", not world_state.is_npc_travelling(gregor_id) and spawner.should_be_at("gregor", "thornhaven_gregor_shop")
		and spawner.should_be_at("bjorn", "thornhaven_blacksmith") and spawner.should_be_at("mira", "thornhaven_tavern")
		and spawner.should_be_at("mathias", "thornhaven_town_square"))
	_check("Nobody is left marked at the drawing", world_state.npc_states.values().all(func(s): return not (s is Dictionary and s.has("at_drawing"))))

	# After the drawing, leaving the chapel sends them home at once; NPCs moved meanwhile are left alone
	opening.gather_congregation()
	world_state.set_npc_location(registry.get_npc_id("mira"), "thornhaven_tavern")
	scene_manager.scene_transition_started.emit("thornhaven_chapel", "thornhaven_town_square")
	var elena_id = registry.get_npc_id("elena")
	_check("Leaving the chapel after the drawing sends the congregation home", world_state.get_npc_location(elena_id) == registry.get_npc_home("elena"))
	_check("Mira, moved since, is not sent anywhere", world_state.get_npc_location(registry.get_npc_id("mira")) == "thornhaven_tavern" and not world_state.is_npc_travelling(registry.get_npc_id("mira")))
	opening.reset()

	# Davin's scene may not exist yet: the spawner skips it without an error
	var hut = Node2D.new()
	root.add_child(hut)
	spawner.initialize_spawned = false
	spawner.spawn_generics = false
	var report = spawner.reconcile("healer_hut", hut)
	spawner.initialize_spawned = true
	spawner.spawn_generics = true
	var scene_exists = ResourceLoader.exists(registry.get_npc_scene("davin"))
	_check("Davin is wanted at the healer's hut: %s" % ("spawned" if scene_exists else "skipped, his scene is not there yet"),
		("davin" in report.spawned) if scene_exists else ("davin" in report.skipped))
	for npc in hut.get_children():
		npc.remove_from_group("npcs")
		npc.free()
	# ...and a missing scene is skipped with a warning, never an error
	var real_scene = registry.get_npc("davin").get("scene", "")
	registry._npcs["davin"]["scene"] = "res://scenes/npcs/__no_such_davin__.tscn"
	spawner.initialize_spawned = false
	spawner.spawn_generics = false
	report = spawner.reconcile("healer_hut", hut)
	spawner.initialize_spawned = true
	spawner.spawn_generics = true
	registry._npcs["davin"]["scene"] = real_scene
	_check("A missing Davin scene is skipped gracefully", "davin" in report.skipped and not "davin" in report.spawned and hut.get_child_count() == 0)
	hut.free()

# =============================================================================

## A new game's clock and calendar (calendar flags cleared), log emptied
func _fresh() -> void:
	for flag in CALENDAR_ORDER:
		world_state.world_flags.erase(flag)
	world_state.npc_states = {}
	world_state.reset_calendar(world_state.start_minute)
	fired_log.clear()

func _fake_npc(npc_id: String, location: String) -> FakeNPC:
	var npc = FakeNPC.new()
	npc.npc_id = npc_id
	npc.location = location
	npc.rag_memory = FakeMemory.new()
	npc.add_child(npc.rag_memory)
	npc.add_to_group("npcs")
	root.add_child(npc)
	return npc

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
