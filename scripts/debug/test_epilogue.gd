extends SceneTree

# Tests Epilogue.generate() (docs/WORLD_SCHEMA.md §15): per-NPC passages for every main and promoted
# NPC the player touched (and nobody else), settlement and region passages, the fixed points that
# moved, reached storyline endings as named highlights, intentions set against deeds (kept, betrayed,
# abandoned), offline determinism, the validated Claude rewrite (fake client), StorylineDirector.end_game
# and the season_end trigger
# Fixtures and fakes only: a fake PlayerEvents and Claude client, no API calls, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_epilogue.gd

const FIX = "res://scripts/debug/fixtures/emergence"
const PROMOTED = "gen_farmer_9"
const GENERIC = "gen_woodcutter_1"
const DAY = 24 * 60

class FakePlayerEvents extends Node:
	signal player_event_recorded(ev: Dictionary)
	signal player_event_changed(ev: Dictionary)
	var events: Dictionary = {}
	var order: Array = []
	var counter: int = 0
	func record(kind: String, summary: String, about: Array = [], opts: Dictionary = {}) -> String:
		counter += 1
		var id = "pe_%06d" % counter
		events[id] = {"id": id, "kind": kind, "summary": summary, "about": about.duplicate(), "status": str(opts.get("status", "open")),
			"truth": "unknown", "location": "thornhaven_town_square", "minute": int(opts.get("minute", 0)),
			"witnesses": opts.get("witnesses", []).duplicate(), "heard_by": opts.get("heard_by", {}).duplicate(), "fidelity": 1.0}
		order.append(id)
		return id
	func get_event(id: String) -> Dictionary:
		return events[id].duplicate(true) if events.has(id) else {}
	func get_events() -> Array:
		return order.map(func(id): return events[id].duplicate(true))
	func known_by(key: String) -> Array:
		var out: Array = []
		for id in order:
			if events[id].heard_by.has(key):
				out.append({"id": id, "text": "the stranger " + events[id].summary})
		return out
	func spread(_id: String, _to: Array, _via: String = "") -> Dictionary:
		return {"ok": true, "scheduled": [], "refused": []}

class FakeClaude extends Node:
	var api_key_override: String = "fake-key-for-tests"
	var reply: String = ""
	func send_message(_messages: Array, _system_prompt: String = "") -> Dictionary:
		return {"text": reply}

var director: Node
var world_state: Node
var voice: Node
var fake: FakePlayerEvents
var failures: int = 0
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	voice = root.get_node("InnerVoice")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.load_calendar()
	world_state.reset_calendar(world_state.start_minute)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.load_content(FIX + "/storylines", FIX + "/souls")
	director.load_emergence(FIX + "/templates")
	fake = FakePlayerEvents.new()
	root.add_child(fake)
	director.set_player_events(fake)
	director.reputation_override = func(scope, id): return {"faction:thornhaven": 35.0, "region:western_valley": 25.0, "npc:mira": -30.0}.get("%s:%s" % [scope, id], 0.0)
	voice.clear()

	print("============================================================")
	print("🧪 EPILOGUE TEST")
	print("============================================================\n")

	_build_world()
	_test_sections()
	_test_people()
	_test_places_points_highlights()
	_test_intentions()
	_test_determinism()
	await _test_claude_rewrite()
	await _test_end_game()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

## A small played world: thoughts, deeds, feelings, a shifted point, an ending, a promoted generic
func _build_world() -> void:
	var dims: Dictionary = {}
	for key in director.get_soul_keys():
		dims[key] = {}
	dims["aldric"] = {"trust": 40, "respect": 20}
	director.relationship_dims_override = dims
	voice.think("I will help Aldric keep the peace")          # day 1: kept (a help event about Aldric follows)
	voice.think("I will protect Mira")                         # betrayed (a harm event about Mira follows)
	voice.think("I want to burn the ledger in the square")     # kept (fx_ledger_burned turns true)
	fake.record("help", "carried water for Aldric's men", ["aldric"], {"witnesses": ["aldric_peacekeeper_001"], "minute": world_state.get_game_minutes() + 5})
	fake.record("harm", "struck Mira in the tavern", ["mira"], {"witnesses": ["mira_tavern_keeper_001"], "heard_by": {"mira": {"fidelity": 1.0}}, "minute": world_state.get_game_minutes() + 6})
	director.register_soul(PROMOTED, FileAccess.get_file_as_string(FIX + "/promoted_farmer.md"), {"tier": "promoted", "npc_id": PROMOTED, "home": "thornhaven_town_square"})
	director.register_soul(GENERIC, FileAccess.get_file_as_string(FIX + "/gen_gossip.md"), {"tier": "generic", "npc_id": GENERIC, "home": "thornhaven_town_square"})
	dims = director.relationship_dims_override
	dims[PROMOTED] = {"affection": 30}
	dims[GENERIC] = {"affection": 30}
	director.relationship_dims_override = dims
	director.evaluate_all()
	world_state.set_world_flag("fx_ledger_burned", true)        # the player's doing: the ledger ending
	world_state.set_world_flag("hc_varn_dead", true)            # Collection Night +2 (shift rule, the player's flag)
	world_state.advance_time(3 * DAY, "test")                   # time passes: an old thought with no deeds
	voice.think("I wonder who keeps the tavern")                # unresolved (fresh, no deeds)

func _test_sections():
	print("Sections")
	var e = Epilogue.generate({"trigger": "player"})
	var ids = e.sections.map(func(s): return s.id)
	_check("Opening, highlights, people, places, fixed points, intentions, in order",
		ids == ["opening", "highlights", "people", "places", "fixed_points", "intentions"])
	_check("Offline mode, a trigger, a time, and one text", e.mode == "offline" and e.trigger == "player" and e.time.begins_with("day 4") and e.text.contains("## The people you touched"))

func _test_people():
	print("People")
	var e = Epilogue.generate()
	var keys = e.people.map(func(p): return p.npc)
	_check("Aldric (feelings, a deed) and Mira (a deed, word of it) are there", "aldric" in keys and "mira" in keys)
	_check("Untouched souls are not (Bjorn, Mathias)", not "bjorn" in keys and not "mathias" in keys)
	_check("Varn is: the player's shift of Collection Night ('With Varn dead...') is a deed about him", "varn" in keys)
	_check("A promoted generic the player touched is there; a plain generic is not", PROMOTED in keys and not GENERIC in keys)
	var aldric = e.people.filter(func(p): return p.npc == "aldric")[0]
	_check("Aldric's passage: trust and respect, where he is", "trusted you and respected you" in aldric.text and "Thornhaven Square" in aldric.text)
	var mira = e.people.filter(func(p): return p.npc == "mira")[0]
	_check("Mira's: what she heard, and her opinion of you (Reputation)", "had heard of 1 thing you did: the stranger struck Mira in the tavern" in mira.text and "you were distrusted" in mira.text)
	var tam = e.people.filter(func(p): return p.npc == PROMOTED)[0]
	_check("The promoted generic's passage names him and his feeling", tam.text.begins_with("At the last, Tam the Farmer") and "was fond of you" in tam.text)

func _test_places_points_highlights():
	print("Places, fixed points, highlights")
	var e = Epilogue.generate()
	_check("The ending reached is a named highlight", e.highlights.size() == 1 and e.highlights[0].title == "Ashes of the Ledger"
		and e.highlights[0].text == "The Fixture Ledger: Ashes of the Ledger. The ledger burned and nobody read it.")
	var points = e.fixed_points.map(func(f): return f.point)
	_check("Collection Night moved, and only what moved is listed", points == ["tn_collection_night"])
	var fp = e.fixed_points[0]
	_check("...two days late, because of the player, with the reason", fp.shift_days == 2 and fp.by_player and "it came 2 days late because of you" in fp.text and "the Hollow had no one to lead the cart" in fp.text)
	var settlement = e.places.filter(func(p): return p.scope == "settlement")
	var region = e.places.filter(func(p): return p.scope == "region")
	_check("A settlement passage with its storyline state", settlement.size() >= 1 and settlement[0].name == "Thornhaven Village" and "The Fixture Ledger came to an end" in settlement[0].text)
	_check("A region passage with reputation and factions", region.size() >= 1 and region[0].id == "western_valley" and "To the people of Western Valley you were well thought of" in region[0].text
		and "To Thornhaven folk you were well thought of" in region[0].text)

func _test_intentions():
	print("Intentions against deeds")
	var e = Epilogue.generate()
	var by_goal: Dictionary = {}
	for i in e.intentions:
		by_goal[i.goal] = i
	_check("Four intentions, oldest first %s" % [e.intentions.map(func(i): return i.goal)], e.intentions.size() == 4 and e.intentions[0].goal == "help Captain Aldric")
	_check("help Aldric: kept (a help deed about him)", by_goal.get("help Captain Aldric", {}).get("verdict", "") == "kept" and "carried water" in by_goal["help Captain Aldric"].text)
	_check("protect Mira: betrayed (struck her)", by_goal.get("protect Mira", {}).get("verdict", "") == "betrayed")
	var burn = e.intentions.filter(func(i): return "ledger" in i.goal)
	_check("burn the ledger: kept (its flag came true)", burn.size() == 1 and burn[0].verdict == "kept")
	_check("A fresh wondering with no deeds: unresolved", e.intentions[3].verdict == "unresolved")
	voice.think("I will rescue Bjorn")
	world_state.advance_time(2 * DAY + 1, "test")
	var later = Epilogue.generate()
	_check("An intention two days old with no deeds: abandoned", later.intentions.back().goal == "rescue Bjorn" and later.intentions.back().verdict == "abandoned")
	_check("The text says it", "On day 4 you meant to rescue Bjorn. Nothing you did came of it." in later.text)

func _test_determinism():
	print("Determinism (offline)")
	var a = Epilogue.generate({"trigger": "debug"})
	var b = Epilogue.generate({"trigger": "debug"})
	_check("Two generations of the same world are identical", JSON.stringify(a) == JSON.stringify(b) and a.text.length() > 400)
	_check("Every section has text", a.sections.all(func(s): return str(s.text).strip_edges() != ""))

func _test_claude_rewrite():
	print("Claude rewrite (validated)")
	var e = Epilogue.generate()
	var invented = e.text.replace("Ashes of the Ledger.", "Ashes of the Ledger, as Lord Zebulon foretold.")
	_check("A rewrite that invents a name is refused", not Epilogue.validate_rewrite(invented, e).ok)
	var numbers = e.text.replace("2 days late", "17 days late")
	_check("...one that invents a number too", not Epilogue.validate_rewrite(numbers, e).ok)
	var headless = e.text.replace("## The places", "## Elsewhere")
	_check("...and one that drops a heading", not Epilogue.validate_rewrite(headless, e).ok)
	var faithful = e.text.replace("At the last,", "When all was done,").replace("had no settled feeling about you", "never quite made up their mind about you")
	_check("A faithful rewording passes", Epilogue.validate_rewrite(faithful, e).ok)
	var claude = FakeClaude.new()
	root.add_child(claude)
	claude.reply = invented
	var rejected = await Epilogue.rewrite(e, claude, self)
	_check("rewrite() keeps the offline text when validation fails", rejected.mode == "claude_rejected" and rejected.text == e.text)
	claude.reply = faithful
	var kept = await Epilogue.rewrite(e, claude, self)
	_check("...and takes a valid one, keeping the offline text beside it", kept.mode == "claude" and kept.text == faithful and kept.offline_text == e.text)
	claude.queue_free()

func _test_end_game():
	print("end_game and season_end")
	var got: Array = []
	director.epilogue_ready.connect(func(ep): got.append(ep))
	var e = await director.end_game("player")
	_check("end_game() generates, keeps and signals the epilogue", got.size() == 1 and e.trigger == "player" and director.get_epilogue().text == e.text and director.get_game_ended() == "player")
	director.reset_state()  # a world still going on
	got.clear()
	world_state.advance_time(30 * DAY, "test")  # past day 30, 20:00
	await process_frame
	await process_frame
	_check("season_end ends the game with an epilogue", got.size() == 1 and got[0].trigger == "season_end" and director.get_game_ended() == "season_end")

func _restore() -> void:
	director.relationship_dims_override = {}
	director.reputation_override = Callable()
	director.set_player_events(null)
	director.unregister_soul(PROMOTED)
	director.unregister_soul(GENERIC)
	director.emergence_dir = director.DEFAULT_EMERGENCE_DIR
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	voice.clear()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	world_state.reset_calendar()
	fake.queue_free()
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
