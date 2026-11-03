extends SceneTree

# Tests the playable opening, the inner-voice UI and the epilogue screen (docs/WORLD_SCHEMA.md §13-15)
# - the congregation (the five plus Thornhaven's generics) stands in the chapel at 20:00
# - the drawing fires at 20:10 (tn_drawing): the player and everyone present witness it, nobody else
# - a conversation turn before it moves the clock a minute
# - speaking up at the urn sets tn_drawing_disrupted and records an accusation/refusal witnessed by
#   all present; the shift rule then moves the drawing a day (PENDING until the director lands it)
# - slipping out is a seen_at event, not witnessed; the name arrives later as gossip
# - the inner-voice UI: the hotkey, the acknowledgement, the journal's Thoughts tab, and the thought
#   never reaching an NPC prompt, a memory, the dialogue history or a world flag
# - the epilogue screen built from a fake Epilogue.generate(), reached through the menu's
#   confirmation and at season_end
# - debug `opening` replays on a fresh state; nothing writes a save
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_opening.gd

const CHAPEL = "thornhaven_chapel"
const SQUARE = "thornhaven_town_square"
const DAY = 24 * 60
const DRAWING_MINUTE = 20 * 60 + 10
const SECRET = "zephyrine"  # a word no NPC prompt could contain unless the thought leaked
const THOUGHT = "Zephyrine plan: I will get Elena out through the undercroft before the cart, whatever Gregor says"

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

class FakeEvents extends Node:
	var events: Array = []
	func record(kind: String, summary: String, about: Array = [], opts: Dictionary = {}) -> String:
		var id = "pe_test_%d" % events.size()
		events.append({"id": id, "kind": kind, "summary": summary, "about": about, "opts": opts})
		return id
	func last() -> Dictionary:
		return events[-1] if not events.is_empty() else {}

class FakeVoice extends Node:
	var heard: Array = []
	func think(text: String) -> Dictionary:
		heard.append(text)
		return {"goal": "get Elena out before the cart", "about": ["elena", "gregor"], "stance": "against_the_tithe", "strength": 0.8}

class FakeEpilogue extends RefCounted:
	var calls: int = 0
	func generate() -> Dictionary:
		calls += 1
		return {
			"title": "The Tithe Night, as it ended",
			"people": [
				{"name": "Elena", "text": "Elena lived to see the spring.", "state": "alive"},
				{"npc": "gregor", "name": "Gregor", "passage": "Gregor never forgave the stranger, or himself."},
			],
			"places": {"thornhaven": {"name": "Thornhaven", "text": "The chapel urn was melted down.", "reputation": 42}},
			"moved_fixed_points": [{"point": "tn_drawing", "reason": "The drawing was broken off and called again for the next evening.", "days": 1}],
			"highlights": ["The Lot Unmasked"],
			"intentions_vs_deeds": [{"goal": "get Elena out before the cart", "verdict": "kept", "deeds": ["refusal at the urn"]}],
			"closing": "The valley remembers you as the one who would not let the lot stand.",
		}

var world_state: Node
var registry: Node
var scene_manager: Node
var director: Node
var propagator: Node
var opening: Node
var events: FakeEvents
var failures: int = 0
var pending: int = 0
var save_existed: bool
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var saved_fired: Dictionary
var fakes: Array = []

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	scene_manager = root.get_node("SceneManager")
	director = root.get_node("StorylineDirector")
	propagator = root.get_node("EventPropagator")
	opening = scene_manager.opening
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_fired = world_state._calendar_fired.duplicate()
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	events = FakeEvents.new()
	root.add_child(events)
	opening.player_events = events
	# Spawned scenes would initialize NPCs (ChromaDB, API): the spawner stays out of these tests
	scene_manager.npc_spawner.initialize_spawned = false

	print("============================================================")
	print("🧪 OPENING + INNER VOICE + EPILOGUE TEST")
	print("============================================================\n")

	_test_congregation()
	_test_drawing_witnessed()
	_test_disruption()
	_test_slip_out()
	await _test_inner_voice()
	_test_epilogue()
	_test_debug_command()

	opening.reset()
	opening.player_events = null
	_set_player_location("")
	world_state.load_calendar()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	world_state._calendar_fired = saved_fired
	paused = false
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

	print("\n============================================================")
	if failures == 0:
		print("✅ ALL TESTS PASSED" + (" (%d check(s) PENDING on the director engine)" % pending if pending > 0 else ""))
	else:
		print("❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# THE OPENING
# =============================================================================

func _test_congregation():
	print("The congregation at 20:00")
	_fresh()
	if not save_existed:
		_check("A new game wants the opening", world_state.is_new_game() and opening.should_play())
	_check("It is Day 1, 20:00", world_state.get_time_string() == "Day 1, 20:00")
	_check("The drawing is the movable fixed point tn_drawing, at 20:10", opening.point_minute() == DRAWING_MINUTE
		and registry.get_calendar().flags.tn_drawing.get("movable", false) == true)
	var gathered: Array = opening.gather_congregation()
	_check("Mathias, Gregor, Elena, Mira and Bjorn are gathered", gathered == ["mathias", "gregor", "elena", "mira", "bjorn"])
	var spawner = scene_manager.npc_spawner
	_check("The spawner puts them in the chapel", gathered.all(func(k): return spawner.should_be_at(k, CHAPEL)) and not spawner.should_be_at("aldric", CHAPEL))
	var manager = root.get_node("DynamicNPCRegistry").generics
	if manager and not manager.get_ids().is_empty():
		var generics: Array = opening.gathered_generics
		_check("Thornhaven's generics come too (%d)" % generics.size(), generics.size() >= 2 and generics.size() <= opening.MAX_GENERICS)
		_check("...every one of them in the chapel", generics.all(func(id): return manager.is_present(id, CHAPEL)))
		_check("...and only villagers: nobody from the Capitol or the road", generics.all(func(id): return registry.get_area(manager.get_instance(id).home) == "Thornhaven Village"))
		_check("present_in_chapel() counts roster and generics", opening.present_in_chapel().size() >= 5 + generics.size())
	else:
		_check("No generics loaded: the five alone", opening.gathered_generics.is_empty())
	_check("The urn is a DrawingUrn and the recut tile waits for the drawing", _chapel_wiring())

func _test_drawing_witnessed():
	print("The drawing at 20:10, watched")
	_fresh()
	opening.gather_congregation()
	_set_player_location(CHAPEL)
	opening.phase = "awaiting"  # as after the establishing card
	propagator.load_from_dict({})
	var gregor_id = registry.get_npc_id("gregor")
	var aldric_id = registry.get_npc_id("aldric")
	var gregor = _fake_npc(gregor_id, CHAPEL)
	var aldric = _fake_npc(aldric_id, SQUARE)
	world_state.advance_time(5, "idle")
	root.get_node("EventBus").npc_response_generated.emit(gregor_id, {"response": "Not now, stranger."})
	_check("A conversation turn before the drawing takes a minute (20:06)", world_state.get_game_minutes() == 20 * 60 + 6)
	world_state.advance_time(3, "idle")
	_check("At 20:09 nothing has been drawn", not world_state.has_calendar_fired("tn_drawing") and not world_state.get_world_flag(opening.FLAG))
	world_state.advance_time(1, "idle")
	_check("At 20:10 the drawing fires", world_state.has_calendar_fired("tn_drawing") and world_state.get_world_flag("tn_drawing"))
	_check("The player was there: tithe_drawing_witnessed", world_state.get_world_flag(opening.FLAG) and opening.outcome == "witnessed")
	_check("Mathias reads Elena's name, in a short in-world card", opening.get_card_kind() == "drawing" and opening.get_card_text().contains("Elena"))
	_check("Everyone in the chapel is marked witnessed", world_state.npc_states.get(gregor_id, {}).has(opening.WITNESSED)
		and world_state.npc_states.get(registry.get_npc_id("elena"), {}).has(opening.WITNESSED))
	_check("...nobody elsewhere is", not world_state.npc_states.get(aldric_id, {}).has(opening.WITNESSED))
	_check("Those present remember it; Aldric in the square does not", _remembers(gregor, opening.FLAG) and not _remembers(aldric, opening.FLAG))
	var watched = events.last()
	_check("Watching is the first PlayerEvent: seen_at in the chapel", watched.get("kind") == "seen_at" and watched.opts.get("location") == CHAPEL)
	_check("...witnessed by those present only", gregor_id in watched.opts.witnesses and aldric_id not in watched.opts.witnesses)
	_check("Speaking up is no longer offered", not opening.can_disrupt())
	opening.skip()
	_check("The card closes", not opening.is_card_open() and opening.phase == "done")
	world_state.advance_time(110, "idle")  # 22:00, two hours after they gathered
	_check("At 22:00 the congregation sets off home", world_state.is_npc_travelling(gregor_id) and world_state.get_npc_location(gregor_id) == registry.get_npc_home("gregor"))
	_free_fakes()

func _test_disruption():
	print("Speaking up at the urn")
	_fresh()
	opening.gather_congregation()
	_set_player_location(CHAPEL)
	opening.phase = "awaiting"
	_check("Before the drawing the urn offers to stop it", opening.can_disrupt())
	var urn = load("res://scripts/world/drawing_urn.gd").new()
	root.add_child(urn)
	urn.choose("accusation")
	var present = opening.present_in_chapel()
	_check("tn_drawing_disrupted is set", world_state.get_world_flag("tn_drawing_disrupted"))
	var ev = events.last()
	_check("An accusation is recorded, about Mathias", ev.get("kind") == "accusation" and "mathias" in ev.get("about", []) and ev.opts.get("flag") == "tn_drawing_disrupted")
	_check("...witnessed by everyone present", present.size() >= 5 and present.all(func(id): return id in ev.opts.witnesses))
	_check("The chapel reacts in a short card", opening.get_card_kind() == "disruption" and opening.outcome == "disrupted")
	_check("It can only be done once", not opening.can_disrupt() and opening.disrupt("refusal") == "")
	urn.free()
	opening.skip()
	var moved = opening.point_minute() == DAY + DRAWING_MINUTE
	if director.has_method("shift_fixed_point") and moved:
		_check("The shift rule delays the drawing a day", moved)
		world_state.advance_time(10, "idle")
		_check("Nothing is drawn at 20:10", not world_state.has_calendar_fired("tn_drawing") and not world_state.get_world_flag(opening.FLAG))
		world_state.advance_time(20, "idle")
		var mathias_id = registry.get_npc_id("mathias")
		_check("The broken-off rite empties the chapel", world_state.get_npc_location(mathias_id) != CHAPEL or world_state.is_npc_travelling(mathias_id) or registry.get_npc_home("mathias") == CHAPEL)
		world_state.advance_time(DAY - 80, "travel")  # disrupted at 20:00; now Day 2, 19:10
		_check("An hour before the new time they come back", world_state.get_npc_location(registry.get_npc_id("gregor")) == CHAPEL)
		world_state.advance_time(60, "idle")
		_check("The next evening, it is drawn", world_state.has_calendar_fired("tn_drawing"))
	else:
		_pending("The shift rule delays the drawing a day (director: shift_fixed_point / shift_rules not in yet)")
		world_state.advance_time(10, "idle")
		_check("Until then the drawing goes on at 20:10, and Mathias draws anyway", world_state.has_calendar_fired("tn_drawing")
			and opening.get_card_kind() == "drawing" and opening.get_card_text().contains("without looking at you"))
		opening.skip()

func _test_slip_out():
	print("Slipping out before the drawing")
	_fresh()
	opening.gather_congregation()
	_set_player_location(CHAPEL)
	opening.phase = "awaiting"
	propagator.load_from_dict({})
	var gregor_id = registry.get_npc_id("gregor")
	var gregor = _fake_npc(gregor_id, CHAPEL)
	world_state.advance_time(4, "idle")
	scene_manager.scene_transition_started.emit(CHAPEL, SQUARE)
	_set_player_location(SQUARE)
	var ev = events.last()
	_check("Leaving is a seen_at event, seen by those in the chapel", ev.get("kind") == "seen_at" and gregor_id in ev.opts.get("witnesses", []) and opening.outcome == "slipped_out")
	_check("The congregation stays for the drawing", world_state.get_npc_location(gregor_id) == CHAPEL and not world_state.is_npc_travelling(gregor_id))
	world_state.advance_time(6, "idle")
	_check("At 20:10 the name is read without the player", world_state.has_calendar_fired("tn_drawing") and not world_state.get_world_flag(opening.FLAG))
	_check("...the chapel witnessed it, the player did not", world_state.npc_states[gregor_id].has(opening.WITNESSED) and not _remembers(gregor, opening.FLAG))
	_check("No drawing card for a player who was not there", opening.get_card_kind() != "drawing" and opening.is_hearing_pending())
	world_state.advance_time(opening.HEAR_AFTER, "idle")
	_check("Later the name reaches them as gossip", world_state.get_world_flag(opening.KNOWN) and not world_state.get_world_flag(opening.FLAG) and opening.outcome == "heard"
		and opening.get_card_kind() == "heard" and opening.get_card_text().contains("Elena"))
	opening.skip()
	_free_fakes()

# =============================================================================
# INNER VOICE
# =============================================================================

func _test_inner_voice():
	print("Inner voice: your thoughts")
	_fresh()
	var player_ui = scene_manager.get_node_or_null("PlayerUI")
	_check("PlayerUI hangs beside the opening under SceneManager", player_ui != null)
	if player_ui == null:
		return
	var ui = player_ui.inner_voice_ui
	var key_t = InputMap.has_action("inner_voice") and InputMap.action_get_events("inner_voice").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_T)
	_check("The inner_voice action is bound to T", key_t)
	_check("No conflict: T is not the journal or interact key", not InputMap.action_get_events("open_journal").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_T)
		and not InputMap.action_get_events("interact").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_T))
	paused = true
	_check("It will not open during a conversation (the tree is paused)", not ui.can_open())
	paused = false
	_check("...and will otherwise", ui.can_open())

	var voice = FakeVoice.new()
	root.add_child(voice)
	ui.voice = voice
	var gregor_id = registry.get_npc_id("gregor")
	var gregor = _fake_npc(gregor_id, CHAPEL)
	var dialogue = root.get_node("DialogueManager")
	var history_before = JSON.stringify(dialogue.conversation_history)
	var bus = root.get_node("EventBus")
	var bus_traffic: Array = []
	var listener = func(a = null, b = null, c = null): bus_traffic.append(str([a, b, c]))
	bus.player_action.connect(listener)
	bus.npc_response_generated.connect(listener)
	bus.world_event.connect(listener)
	var events_before = events.events.size()
	ui.open()
	_check("T opens a small 'your thoughts' box", ui.is_open)
	var entry: Dictionary = ui.submit(THOUGHT)
	_check("Submit hands the thought to InnerVoice.think()", voice.heard == [THOUGHT])
	_check("...closes the box and acknowledges it quietly", not ui.is_open and ui.get_ack_text() == ui.ACK_TEXT)
	_check("...and keeps the parsed intention", entry.get("intention", {}).get("goal", "") == "get Elena out before the cart")
	await process_frame
	bus.player_action.disconnect(listener)
	bus.npc_response_generated.disconnect(listener)
	bus.world_event.disconnect(listener)

	# The thought must reach no NPC: their prompts, memories, the dialogue history, flags, events
	var leaks: Array = []
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var manager = root.get_node("DynamicNPCRegistry").generics
	var prompt_ids: Array = ["mathias", "gregor", "elena", "mira", "bjorn", "aldric"].map(func(k): return registry.get_npc_id(k))
	if manager and not manager.get_ids().is_empty():
		prompt_ids.append(manager.get_ids()[0])
	for npc_id in prompt_ids:
		var context = builder.build_context({"system_prompt": "You are %s." % npc_id, "npc_id": npc_id,
			"world_state": world_state.get_relevant_state(npc_id), "conversation_history": dialogue.get_history(npc_id),
			"player_input": "Good evening."})
		var text = (str(context.get("system_prompt", "")) + JSON.stringify(context.get("messages", []))).to_lower()
		if SECRET in text or "undercroft before the cart" in text:
			leaks.append(npc_id)
		if manager and manager.is_generic(npc_id) and SECRET in manager.get_prompt_block(npc_id).to_lower():
			leaks.append(npc_id + " (generic block)")
	if builder is Node:
		builder.free()
	_check("No NPC prompt contains the thought (%d prompts scanned)" % prompt_ids.size(), leaks.is_empty())
	if not leaks.is_empty():
		print("    leaked into: %s" % [leaks])
	_check("No NPC memory holds it", gregor.rag_memory.stored.all(func(m): return not SECRET in JSON.stringify(m).to_lower()))
	_check("The dialogue history is untouched", JSON.stringify(dialogue.conversation_history) == history_before)
	_check("No world flag carries it", not SECRET in JSON.stringify(world_state.world_flags).to_lower())
	_check("No PlayerEvent and no EventBus traffic", events.events.size() == events_before and bus_traffic.is_empty())
	var real_events = root.get_node_or_null("PlayerEvents")
	if real_events and real_events.has_method("known_by"):
		_check("PlayerEvents knows nothing of it", not SECRET in JSON.stringify(real_events.known_by(gregor_id)).to_lower())

	# The journal's Thoughts tab
	var journal = load("res://scenes/ui/quest_journal.tscn").instantiate()
	root.add_child(journal)
	await process_frame
	_check("The journal lists past intentions", journal.get_thoughts().size() == 1 and journal.thought_text(journal.get_thoughts()[0]) == THOUGHT)
	journal._switch_tab(journal.Tab.THOUGHTS)
	_check("...under a Thoughts tab", journal.thoughts_tab != null and journal.thoughts_tab.text == "Thoughts (1)" and journal.quest_list.get_child_count() == 1
		and journal.quest_title.text == THOUGHT)
	ui.open()
	var typed = InputEventAction.new()
	typed.action = "open_journal"
	typed.pressed = true
	journal._input(typed)
	_check("Typing J in a thought does not open the journal", not journal.is_open)
	ui.close()
	journal.queue_free()

	# The real InnerVoice (a stub until the director lands it) is called the same way
	ui.voice = null
	var real_entry: Dictionary = ui.submit("I mean to keep watch on Bjorn")
	_check("With the real InnerVoice the thought is still kept privately", real_entry.get("text", "") == "I mean to keep watch on Bjorn")
	voice.queue_free()
	_free_fakes()

# =============================================================================
# EPILOGUE
# =============================================================================

func _test_epilogue():
	print("The epilogue screen")
	var player_ui = scene_manager.get_node_or_null("PlayerUI")
	if player_ui == null:
		_check("PlayerUI exists", false)
		return
	var screen = player_ui.epilogue_screen
	var fake = FakeEpilogue.new()
	screen.source = fake
	paused = false
	_check("The menu opens over the world", player_ui.can_open_menu())
	player_ui.open_menu()
	_check("...and pauses it", player_ui.is_menu_open() and paused)
	player_ui.request_end_story()
	_check("'End my story here' asks first", player_ui._confirm.visible and not screen.is_open)
	player_ui.cancel_end_story()
	_check("'Not yet' goes back to the menu", player_ui._menu.visible and not screen.is_open)
	player_ui.request_end_story()
	player_ui.confirm_end_story()
	_check("Confirming shows the epilogue from Epilogue.generate()", screen.is_open and fake.calls == 1 and not player_ui.is_menu_open())
	_check("Sections in order: people, places, moved fixed points, highlights, intentions vs deeds",
		screen.sections_built == ["people", "places", "fixed_points", "highlights", "intentions"])
	var text: String = screen.get_text()
	_check("People and places are told", text.contains("Elena lived to see the spring.") and text.contains("Gregor never forgave") and text.contains("The chapel urn was melted down."))
	_check("The moved point, the highlight and the kept intention appear", text.contains("tn_drawing") and text.contains("The Lot Unmasked") and text.contains("Verdict: kept"))
	_check("The title and closing frame it", text.contains("The Tithe Night, as it ended") and text.contains("would not let the lot stand"))
	_check("It is full screen, scrollable, and pauses the world", screen.get_node("EpilogueRoot").visible and screen.get_node("EpilogueRoot").get_anchor(SIDE_RIGHT) == 1.0 and paused
		and screen.find_child("Scroll", true, false) is ScrollContainer)
	_check("The menu will not open over it", not player_ui.can_open_menu())
	screen.close()
	_check("Close returns to an unpaused world", not screen.is_open and not paused)

	root.get_node("EventBus").calendar_flag_fired.emit("season_end", 29 * DAY + 20 * 60)
	_check("season_end shows it by itself", screen.is_open and fake.calls == 2)
	screen.close()

	screen.source = RefCounted.new()  # no generate(): the director engine has not landed it
	screen.show_epilogue()
	_check("Without an epilogue yet it says so, without errors", screen.is_open and screen.sections_built.is_empty() and screen.get_text().contains("not been written down yet"))
	screen.close()
	screen.source = null
	paused = false

# =============================================================================
# DEBUG
# =============================================================================

func _test_debug_command():
	print("Debug command: opening")
	_fresh()
	world_state.advance_time(3 * DAY, "travel")
	world_state.set_world_flag("ledger_found", true)
	var console = load("res://scenes/ui/debug_console.tscn").instantiate()
	root.add_child(console)
	# No chapel scene headless: play() then shows the establishing card where it stands
	var chapel = scene_manager.locations.get(CHAPEL)
	scene_manager.locations.erase(CHAPEL)
	console._on_command_submitted("opening")
	scene_manager.locations[CHAPEL] = chapel
	_check("'opening' starts from a fresh world: Day 1, 20:00, no flags", world_state.get_time_string() == "Day 1, 20:00" and not world_state.get_world_flag("ledger_found")
		and not world_state.has_calendar_fired("tn_day_2"))
	_check("...gathers the congregation and sets the scene", opening.playing and opening.get_card_kind() == "establishing"
		and scene_manager.npc_spawner.should_be_at("gregor", CHAPEL))
	opening.skip()
	_check("Skip hands control to the player before the drawing", opening.phase == "awaiting" and not opening.is_card_open())
	console.queue_free()

# =============================================================================

## A new game: clock at the start, calendar unfired (and unmoved), no flags, nobody moved
func _fresh() -> void:
	opening.reset()
	world_state.load_calendar()
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.reset_calendar(world_state.start_minute)
	_set_player_location("")
	paused = false

## Where SceneManager thinks the player is ("" = nowhere: no scene loaded)
func _set_player_location(location_id: String) -> void:
	scene_manager.current_location = scene_manager.get_location(location_id) if location_id != "" else null

func _chapel_wiring() -> bool:
	var chapel = load("res://scenes/interiors/thornhaven_chapel.tscn").instantiate()
	var urn = chapel.get_node_or_null("Interactables/LotUrn")
	var tile = chapel.get_node_or_null("Interactables/DrawnTile")
	var slots = chapel.get_node_or_null("PewPlaces")
	var ok = urn != null and urn.has_method("show_choices") and tile != null and tile.requires_flag == "tn_drawing" \
		and slots != null and slots.get_child_count() >= opening.MAX_GENERICS and chapel.get_node_or_null("SpawnPoints/opening") != null
	chapel.free()
	return ok

func _remembers(npc: FakeNPC, flag_name: String) -> bool:
	return npc.rag_memory.stored.any(func(m): return str(m.get("source_flag", m.get("flag", ""))) == flag_name or JSON.stringify(m).contains(flag_name))

func _fake_npc(npc_id: String, location: String) -> FakeNPC:
	var npc = FakeNPC.new()
	npc.npc_id = npc_id
	npc.location = location
	npc.rag_memory = FakeMemory.new()
	npc.add_child(npc.rag_memory)
	npc.add_to_group("npcs")
	root.add_child(npc)
	fakes.append(npc)
	return npc

func _free_fakes() -> void:
	for npc in fakes:
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.free()
	fakes.clear()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _pending(label: String):
	print("  ⏳ PENDING: %s" % label)
	pending += 1
