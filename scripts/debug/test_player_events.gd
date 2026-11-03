extends SceneTree

# Tests PlayerEvents and Reputation (docs/WORLD_SCHEMA.md §10): recording and save/load, promises kept
# and broken (by day, by flag, by a fail flag), claims exposed as lies, utterances parsed from a fake NPC
# reply (and through BaseNPC.respond_to_player with a fake Claude), witnesses limited to who is present,
# Director commitments, StoryItem discoveries, arrivals, kept_company throttling, spread over the routes
# graph with time delay and fidelity loss, attitude drift in wording, the anonymous-rumour threshold,
# no impossible hearers, reputation per npc / faction / region from known events only, Iron Hollow
# excluding Mira until she is revealed, the prompt block's budget, and dedup across sessions.
# Fakes only: no API calls, in-memory RAG (nothing reaches ./chroma), no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_player_events.gd

const FIXTURE_STORYLINES = "res://scripts/debug/fixtures/conversation/storylines"
const FIXTURE_SOULS = "res://scripts/debug/fixtures/conversation/souls"
const SHOP = "thornhaven_gregor_shop"
const TAVERN = "thornhaven_tavern"
const SQUARE = "thornhaven_town_square"
const CAMP = "iron_hollow_camp"
const GREGOR = "gregor_merchant_001"
const ELENA = "elena_daughter_001"
const MIRA = "mira_tavern_keeper_001"
const VARN = "varn_bandit_001"
const BJORN = "bjorn_blacksmith_001"
const DAY = 1440
const T0 = 2 * DAY + 9 * 60   # day 3, 09:00

const Rep = preload("res://scripts/world_state/reputation.gd")

## Stands in for a ChromaDB collection that outlives the save file
class FakeMemory extends Node:
	var stored: Array = []
	func store(data: Dictionary, _custom_id: String = "", _skip_validation: bool = false) -> bool:
		stored.append(data)
		return true
	func has_memory_with(where: Dictionary) -> bool:
		for m in stored:
			var ok = true
			for k in where:
				if str(m.get(k, "")) != str(where[k]):
					ok = false
			if ok:
				return true
		return false

class FakeNPC extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true
	var _is_initialized: bool = true
	var rag_memory: Node
	var current_location: String = ""
	var relationship_trust: float = 0.0
	var relationship_respect: float = 0.0
	var relationship_affection: float = 0.0
	var relationship_fear: float = 0.0
	var relationship_familiarity: float = 0.0
	func get_current_location() -> String:
		return current_location

## Stands in for ClaudeClient: returns canned replies in order (the last one repeats)
class FakeClaude extends Node:
	var api_key_override: String = "fake-key-for-tests"
	var replies: Array = []
	var calls: int = 0
	var systems: Array = []
	## system_prompt: a String or ContextBuilder's system_blocks (kept as the text they make up)
	func send_message(_messages: Array, system_prompt = "") -> Dictionary:
		calls += 1
		systems.append(system_prompt if system_prompt is String else "".join(system_prompt.map(func(b): return str(b.text))))
		var reply = replies[mini(calls - 1, replies.size() - 1)] if not replies.is_empty() else ""
		return {"text": reply}

var pe: Node
var world_state: Node
var registry: Node
var propagator: Node
var director: Node
var gm: Node
var failures: int = 0
var npcs: Array = []
var changed: Array = []
var saved_flags: Dictionary
var saved_states: Dictionary
var saved_minutes: int
var saved_pe: Dictionary
var saved_propagation: Dictionary

func _init():
	await process_frame
	await process_frame
	pe = root.get_node("PlayerEvents")
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	propagator = root.get_node("EventPropagator")
	director = root.get_node_or_null("StorylineDirector")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	saved_flags = world_state.world_flags.duplicate(true)
	saved_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_pe = pe.save()
	saved_propagation = propagator.save()
	world_state.set_idle_clock_rate(0.0)
	if director:
		director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)
		director.round_boundaries_enabled = false
		director.set_round_timer_paused(true)
	pe.player_event_changed.connect(func(ev): changed.append(ev))

	print("============================================================")
	print("🧪 PLAYER EVENTS TEST")
	print("============================================================\n")

	await _test_record_and_save_load()
	await _test_promises()
	await _test_claims_become_lies()
	await _test_utterance_parsing()
	await _test_reply_end_to_end()
	await _test_witnesses_are_who_is_present()
	await _test_commitments()
	await _test_discoveries_and_arrivals()
	await _test_kept_company()
	await _test_spread_over_routes()
	await _test_attitude_drift()
	await _test_anonymous_rumour()
	await _test_no_impossible_hearers()
	await _test_reputation_known_events_only()
	await _test_iron_hollow_mira()
	await _test_prompt_block_budget()
	await _test_dedup_across_sessions()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# RECORD, SAVE / LOAD
# =============================================================================

func _test_record_and_save_load():
	print("Record and save/load")
	await _reset()
	var id = pe.record("promise", "The stranger promised Gregor to get Elena out before the cart.", ["gregor", "elena_daughter_001", "marta"],
		{"location": SHOP, "witnesses": [GREGOR], "due": {"day": 4}})
	var ev = pe.get_event(id)
	_check("Ids are pe_NNNNNN", id == "pe_000001")
	_check("The §10 shape", ev.kind == "promise" and ev.status == "open" and ev.truth == "unknown" and ev.location == SHOP
		and ev.minute == T0 and ev.fidelity == 1.0 and ev.heard_by.is_empty() and ev.witnesses == [GREGOR])
	_check("Summary loses its subject and full stop", ev.summary == "promised Gregor to get Elena out before the cart")
	_check("About is normalised to keys; unknown names dropped", ev.about == ["gregor", "elena"])
	_check("Unknown kinds are refused", pe.record("bribe", "paid someone") == "" and pe.record("gift", "   ") == "")
	var second = pe.record("help", "carried water for Gregor", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	pe.spread(second, ["elena"], "test")
	await _advance(5)
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))  # through text, as the save file does
	_check("WorldState's save carries a player_events section", saved is Dictionary and saved.get("player_events", {}).get("events", {}).has(id))
	pe.reset()
	_check("Reset forgets", pe.get_events().is_empty())
	world_state._apply_player_events_state(saved)
	var back = pe.get_event(id)
	_check("Events come back from the save", back.get("summary") == ev.summary and back.get("witnesses") == [GREGOR] and int(back.get("minute", -1)) == T0
		and back.get("due", {}).get("day") == 4 and back.get("due", {}).get("day") is int)
	_check("...with who heard what", pe.fidelity_for(second, "elena") == 0.85 and pe.known_by("elena").size() == 1)
	_check("...and the id counter", pe.record("gift", "gave Elena an apple", ["elena"], {"location": SHOP, "witnesses": [], "spread": false}) == "pe_000003")
	var in_flight_id = pe.record("help", "mended Varn's boot", ["varn"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	pe.spread(in_flight_id, ["varn"])
	var mid = JSON.parse_string(JSON.stringify(world_state.save()))
	pe.reset()
	world_state._apply_player_events_state(mid)
	_check("Word on the road survives a save", pe.in_flight.size() == 1 and pe.in_flight[0].at is int)
	await _advance(registry.travel_minutes(SHOP, CAMP))
	_check("...and still arrives", pe.fidelity_for(in_flight_id, "varn") > 0.0)

# =============================================================================
# PROMISES AND TRUTH
# =============================================================================

func _test_promises():
	print("Promises: kept or broken, by day and by flag")
	await _reset()
	var by_day = pe.record("promise", "promised Bjorn to return his hammer by tomorrow", ["bjorn"], {"location": SHOP, "witnesses": [GREGOR], "due": {"day": 3}})
	var by_flag = pe.record("promise", "promised Gregor to find the ledger", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "due": {"flag": "pe_test_done"}})
	var flag_late = pe.record("promise", "promised Elena to bring the herb by day 3", ["elena"], {"location": SHOP, "witnesses": [GREGOR], "due": {"flag": "pe_test_herb", "day": 3}})
	var fails = pe.record("promise", "promised Mira to keep the door", ["mira"], {"location": SHOP, "witnesses": [GREGOR], "due": {"fails": ["pe_test_door_lost"]}})
	var no_due = pe.record("promise", "promised to stay a while", [], {"location": SHOP, "witnesses": [GREGOR]})
	_check("All start open", [by_day, by_flag, flag_late, fails, no_due].all(func(i): return pe.get_event(i).status == "open"))
	world_state.set_world_flag("pe_test_done", true)
	_check("A due flag coming true keeps the promise", pe.get_event(by_flag).status == "kept" and pe.get_event(by_flag).truth == "true")
	_check("...and says so (player_event_changed)", changed.any(func(e): return e.id == by_flag and e.status == "kept"))
	await _advance(14 * 60)  # day 3, 23:00
	_check("Still day 3: the day promise is open", pe.get_event(by_day).status == "open")
	await _advance(2 * 60)   # day 4, 01:00
	_check("Day 3 passed: broken", pe.get_event(by_day).status == "broken" and "day 3" in str(pe.get_event(by_day).change_reason))
	_check("A flag promise whose day passes first is broken", pe.get_event(flag_late).status == "broken")
	world_state.set_world_flag("pe_test_herb", true)
	_check("...and stays broken when the flag comes late", pe.get_event(flag_late).status == "broken")
	world_state.set_world_flag("pe_test_door_lost", true)
	_check("A fail flag breaks it", pe.get_event(fails).status == "broken")
	_check("A promise with no due stays open", pe.get_event(no_due).status == "open")
	_check("Breaking is an event of its own", changed.filter(func(e): return e.status == "broken").size() == 3)
	_check("events_matching finds the broken ones", pe.events_matching({"kind": "promise", "status": "broken"}).size() == 3)
	_check("By hand: resolve_promise", pe.resolve_promise(no_due, "kept") and pe.get_event(no_due).status == "kept" and not pe.resolve_promise(no_due, "broken"))

func _test_claims_become_lies():
	print("Claims checked against the world")
	await _reset()
	var denial = pe.record("claim", "swore they never touched the ledger", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "flag": "pe_test_ledger", "value": false})
	var boast = pe.record("claim", "said the bridge would hold", [], {"location": SHOP, "witnesses": [GREGOR], "flag": "pe_test_bridge"})
	_check("Unverified claims", pe.get_event(denial).kind == "claim" and pe.get_event(denial).truth == "unknown")
	world_state.set_world_flag("pe_test_ledger", true)
	var ev = pe.get_event(denial)
	_check("Contradicted by a flag: a lie", ev.kind == "lie" and ev.was == "claim" and ev.truth == "false" and ev.status == "exposed")
	_check("...announced by player_event_changed", changed.any(func(e): return e.id == denial and e.kind == "lie"))
	_check("...still found as a claim", pe.events_matching({"kind": "claim", "status": "exposed"}).size() == 1)
	world_state.set_world_flag("pe_test_bridge", true)
	_check("A claim the world bears out is true, not a lie", pe.get_event(boast).kind == "claim" and pe.get_event(boast).truth == "true")
	var late = pe.record("claim", "said they were never in the shop", [], {"location": SHOP, "witnesses": [GREGOR], "flag": "pe_test_ledger", "value": false})
	_check("A claim already contradicted is a lie at once", pe.get_event(late).kind == "lie")
	_check("Exposed lies weigh worse than plain lies", Rep.kind_weight(pe.get_event(denial)) < Rep.kind_weight({"kind": "lie"}))

# =============================================================================
# CONVERSATION
# =============================================================================

func _test_utterance_parsing():
	print("Utterances parsed from a fake NPC reply")
	await _reset()
	var npc = await _make_base_npc()
	var raw = JSON.stringify({"response": "[narrowing her eyes] Fine words.", "analysis": {"player_tone": "friendly", "emotional_impact": "neutral",
		"interaction_type": "promise_made", "utterances": [
			{"kind": "promise", "about": ["Elena", "gregor"], "summary": "The stranger promised to get Elena out before the cart.", "believed": true, "due_day": 7},
			{"kind": "claim", "about": [], "summary": "claimed to be a pilgrim from the Capitol", "believed": false},
			{"kind": "seen_at", "about": [], "summary": "was here"},
			{"kind": "dance", "about": [], "summary": "danced"},
			{"kind": "threat", "about": ["me"], "summary": "threatened to burn the tavern"},
			{"kind": "insult", "about": [], "summary": "called the ale piss"}]}})
	var parsed = npc._parse_npc_response(raw)
	_check("BaseNPC parses analysis.utterances", parsed.utterances.size() == 6)
	var clean = pe.parse_utterances(parsed.utterances)
	_check("Only conversation kinds; at most 3 per reply", clean.size() == 3 and clean.map(func(u): return u.kind) == ["promise", "claim", "threat"])
	world_state.set_npc_location(MIRA, TAVERN)
	var ids = npc._record_player_utterances(parsed)
	_check("Each becomes a player event", ids.size() == 3)
	var promise = pe.get_event(ids[0])
	_check("Seen from the NPC's side: source and witness", promise.source == "mira" and MIRA in promise.witnesses and promise.location == TAVERN)
	_check("Summary cleaned, about normalised, due day kept", promise.summary == "promised to get Elena out before the cart" and promise.about == ["elena", "gregor"] and promise.due.day == 7)
	_check("Disbelieved claims remember it", pe.get_event(ids[1]).believed == false and Rep.kind_weight(pe.get_event(ids[1])) < 0)
	_check("'me' is the NPC itself", pe.get_event(ids[2]).about == ["mira"])
	_check("Malformed utterances are ignored", pe.parse_utterances("nope").is_empty() and pe.parse_utterances([1, {"kind": "claim"}]).is_empty())
	_free_base_npc(npc)

func _test_reply_end_to_end():
	print("A Claude reply with utterances, through BaseNPC.respond_to_player")
	await _reset()
	var npc = await _make_base_npc()
	var fake: FakeClaude = npc.claude_client
	fake.replies = [JSON.stringify({"response": "[quietly] I'll hold you to that.",
		"analysis": {"player_tone": "friendly", "emotional_impact": "positive", "interaction_type": "promise_made",
			"trust_change": 2, "respect_change": 0, "affection_change": 1, "fear_change": 0, "familiarity_change": 1,
			"learned_about_player": {"name": null, "occupation": null, "origin": null, "notable_facts": []},
			"utterances": [{"kind": "promise", "about": ["mira"], "summary": "promised to pay the tab by tomorrow", "believed": true}]},
		"actions": [], "commitments": []})]
	npc.is_in_conversation = true
	await npc.respond_to_player("I'll pay what I owe by tomorrow, I swear.")
	var found = pe.events_matching({"kind": "promise", "source": "mira"})
	_check("The reply's utterance is a player event", found.size() == 1 and found[0].summary == "promised to pay the tab by tomorrow")
	_check("The prompt asked for utterances and showed nothing heard yet", "\"utterances\": []" in fake.systems[0] and not ("What you have heard of the stranger" in fake.systems[0]))
	await npc.respond_to_player("And the rest?")
	_check("Next turn: the NPC's prompt carries what it saw", "What you have heard of the stranger" in fake.systems[1] and "pay the tab" in fake.systems[1])
	_free_base_npc(npc)

func _test_witnesses_are_who_is_present():
	print("Witnesses are exactly who is present")
	await _reset()
	var gregor = _spawn(GREGOR, SHOP)
	var elena = _spawn(ELENA, SQUARE)
	world_state.set_npc_location(GREGOR, SHOP)
	world_state.set_npc_location(ELENA, SQUARE)
	world_state.start_npc_travel(BJORN, SHOP, 30)  # on the road to the shop: not there yet
	world_state.set_npc_location(VARN, SHOP)
	world_state.npc_states[VARN]["is_alive"] = false  # dead men see nothing
	var expected = ["gregor"]
	if gm:
		expected.append_array(gm.get_present_ids(SHOP))
	var present = pe.get_present(SHOP)
	_check("Presence: Gregor and the generics in the shop, no traveller, no corpse", _same(present, expected) and not ("bjorn" in present) and not ("varn" in present))
	pe.player_location_override = SHOP
	var id = pe.record("harm", "struck a farmer in the shop", [], {"spread": false})
	await process_frame
	var ev = pe.get_event(id)
	_check("Default witnesses are everyone present", ev.witnesses.size() == expected.size() and GREGOR in ev.witnesses and not (ELENA in ev.witnesses))
	_check("Gregor remembers seeing it", gregor.rag_memory.stored.size() == 1 and str(gregor.rag_memory.stored[0].text).begins_with("I saw it myself: The stranger struck a farmer"))
	_check("Elena (in the square) does not", elena.rag_memory.stored.is_empty() and pe.known_by("elena").is_empty())
	if gm and expected.size() > 1:
		var gid = expected[1]
		_check("A generic witness gets a layer", gm.get_instance(gid).has_layer_tag("news:" + pe._source_flag(pe.events[id])))
	world_state.npc_states[VARN]["is_alive"] = true

func _test_commitments():
	print("Commitments the Director accepts are promises")
	if director == null:
		_check("StorylineDirector available", false)
		return
	await _reset()
	world_state.set_npc_location(MIRA, TAVERN)
	world_state.set_world_flag("cv_begin", true)
	var result = director.apply_conversation_actions("mira", [], ["cv_pledge"], {"player": "I swear it.", "said": "[nods] Good."})
	await process_frame
	var promises = pe.events_matching({"kind": "promise", "flag": "cv_pledge"})
	_check("The commitment was accepted", result.applied.size() == 1)
	_check("One promise event, not two", promises.size() == 1)
	_check("...heard by the NPC it was made to", promises.size() == 1 and MIRA in promises[0].witnesses and promises[0].source == "mira" and promises[0].commitment == "cv_pledge")
	director.player_choice("cv_old_pledge")
	await process_frame
	_check("A debug/StoryItem choice is a promise too", pe.events_matching({"kind": "promise", "flag": "cv_old_pledge"}).size() == 1)

func _test_discoveries_and_arrivals():
	print("StoryItem discoveries and arrivals")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	pe.player_location_override = SHOP
	root.get_node("EventBus").world_event.emit({"type": "item_discovered", "item_id": "Ledger", "flag": "ledger_found"})
	var found = pe.events_matching({"kind": "seen_at", "location": SHOP})
	_check("A discovery is a seen_at deed where it happened", found.size() == 1 and "searching" in found[0].summary)
	_check("...seen by who was there, about whoever it implicates", found.size() == 1 and GREGOR in found[0].witnesses and "gregor" in found[0].about)
	world_state.set_npc_location(MIRA, TAVERN)
	var scene_manager = root.get_node("SceneManager")
	scene_manager.scene_transition_completed.emit(TAVERN)
	var seen = pe.events_matching({"kind": "seen_at", "location": TAVERN})
	_check("Arriving is seen_at by those present", seen.size() == 1 and MIRA in seen[0].witnesses and seen[0].summary.begins_with("was seen at"))
	scene_manager.scene_transition_completed.emit(TAVERN)
	_check("...not twice within the hour", pe.events_matching({"kind": "seen_at", "location": TAVERN}).size() == 1)
	_check("Nobody there, nothing seen", pe.note_arrival("capitol_docks_nobody") == "")

func _test_kept_company():
	print("Time near someone: kept_company, hourly")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	pe.player_location_override = SHOP
	await _advance(30, "idle")
	_check("Half an hour: nothing yet", pe.events_matching({"kind": "kept_company", "witness": "gregor"}).is_empty())
	await _advance(30, "idle")
	var kept = pe.events_matching({"kind": "kept_company", "witness": "gregor"})
	_check("An hour: kept_company with Gregor", kept.size() == 1 and kept[0].hours == 1 and kept[0].witnesses == [GREGOR])
	await _advance(60, "idle")
	await _advance(45, "idle")
	kept = pe.events_matching({"kind": "kept_company", "witness": "gregor"})
	_check("Two hours and change: one event, two hours (about once an hour)", kept.size() == 1 and kept[0].hours == 2)
	await _advance(120, "walk:%s->%s" % [SHOP, SQUARE])
	_check("Walking does not count", pe.events_matching({"kind": "kept_company", "witness": "gregor"})[0].hours == 2)
	pe.player_location_override = SQUARE
	await _advance(90, "idle")
	_check("Elsewhere: Gregor's count does not grow", pe.events_matching({"kind": "kept_company", "witness": "gregor"})[0].hours == 2)

# =============================================================================
# SPREAD
# =============================================================================

func _test_spread_over_routes():
	print("Spread over routes: time delay and fidelity loss")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	var id = pe.record("theft", "stole bread from Gregor's counter", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	_check("The witness knows it at 1.0", pe.fidelity_for(id, "gregor") == 1.0)
	var to_camp = registry.travel_minutes(SHOP, CAMP)
	var expected = snappedf(1.0 - pe.FIDELITY_HOP * (1 + floori(to_camp / float(pe.RELAY_MINUTES))), 0.01)
	var result = pe.spread(id, ["varn", "elena"], "a runner")
	_check("Both scheduled from Gregor", result.ok and result.scheduled.size() == 2 and result.scheduled.all(func(s): return s.from == "gregor"))
	_check("Nobody hears before the road is walked", pe.fidelity_for(id, "varn") == 0.0 and pe.fidelity_for(id, "elena") == 0.0)
	await _advance(registry.travel_minutes(SHOP, SQUARE))
	_check("The square hears after its minute, one retelling down (0.85)", pe.fidelity_for(id, "elena") == 0.85)
	_check("...the camp is still waiting", pe.fidelity_for(id, "varn") == 0.0)
	await _advance(to_camp - registry.travel_minutes(SHOP, SQUARE) - 1)
	_check("...a minute short of the camp: not yet", pe.fidelity_for(id, "varn") == 0.0)
	await _advance(1)
	_check("The camp hears after %d minutes at %.2f" % [to_camp, expected], pe.fidelity_for(id, "varn") == expected)
	_check("Heard_by records teller and fidelity", pe.get_event(id).heard_by.varn.from == "gregor")
	world_state.set_npc_location(ELENA, "capitol_palace")
	var far = registry.travel_minutes(SHOP, "capitol_palace")
	var r2 = pe.spread(id, ["edric"])
	_check("Word goes from whoever is nearest (Elena, now in the Capitol)", r2.scheduled.size() == 1 and r2.scheduled[0].from == "elena" and r2.scheduled[0].at == world_state.game_minutes)
	_check("...retold again: fidelity drops a hop more", is_equal_approx(pe.fidelity_for(id, "edric"), 0.7))
	_check("Long roads cost more hops", far > pe.RELAY_MINUTES and snappedf(1.0 - pe.FIDELITY_HOP * (1 + floori(far / float(pe.RELAY_MINUTES))), 0.01) < 0.7)
	_check("A second spread to someone who knows it better does nothing", pe.spread(id, ["varn"]).scheduled.is_empty())
	var loud = pe.record("kill", "killed a Hollow grunt at the gate", [], {"location": SQUARE, "witnesses": ["aldric"]})
	await _advance(1)
	var heard_loud = pe.get_event(loud).heard_by.keys()
	_check("Loud deeds spread round the region on their own", heard_loud.size() > 3 and "mathias" in heard_loud and not ("edric" in heard_loud))

func _test_attitude_drift():
	print("Attitude drift: the teller's feelings colour the tale")
	await _reset()
	var ev = {"id": "pe_x", "kind": "harm", "summary": "struck Bjorn", "status": "none", "truth": "true"}
	var good = {"id": "pe_y", "kind": "help", "summary": "carried water for Elena", "status": "none", "truth": "true"}
	var dark = pe.compose(ev, "dark", 0.85, 0)
	var soft = pe.compose(ev, "soft", 0.85, 0)
	var plain = pe.compose(ev, "plain", 0.85, 0)
	_check("Plain keeps the facts", plain == "The stranger struck Bjorn.")
	_check("Fear tells it darker", dark == "The stranger struck Bjorn. There's malice in that one.")
	_check("A friend softens it", soft == "The stranger struck Bjorn. I'd wager they had their reasons.")
	_check("A good deed from a frightened mouth is suspect", pe.compose(good, "dark", 0.85, 1) == "The stranger carried water for Elena. I don't trust a kindness like that.")
	_check("Deterministic: same tale twice", pe.compose(ev, "dark", 0.85, 3) == pe.compose(ev, "dark", 0.85, 3))
	_check("Half heard is hedged", pe.compose(ev, "plain", 0.45, 0).begins_with("I only half heard it, but the stranger struck Bjorn"))
	var gregor = _spawn(GREGOR, SHOP)
	world_state.set_npc_location(GREGOR, SHOP)
	gregor.relationship_fear = 60.0
	var mira = _spawn(MIRA, SQUARE)
	world_state.set_npc_location(MIRA, SQUARE)
	mira.relationship_affection = 55.0
	var elena = _spawn(ELENA, SQUARE)
	world_state.set_npc_location(ELENA, SQUARE)
	var bjorn = _spawn(BJORN, "thornhaven_blacksmith")
	world_state.set_npc_location(BJORN, "thornhaven_blacksmith")
	_check("Tone from feelings", pe._tone_of("gregor") == "dark" and pe._tone_of("mira") == "soft" and pe._tone_of("elena") == "plain")
	var a = pe.record("threat", "threatened Davin at knifepoint", ["davin"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	pe.spread(a, ["bjorn"])
	await _advance(registry.travel_minutes(SHOP, "thornhaven_blacksmith"))
	var b = pe.record("threat", "threatened Davin at knifepoint again", ["davin"], {"location": SQUARE, "witnesses": [MIRA], "spread": false})
	pe.spread(b, ["bjorn"])
	await _advance(registry.travel_minutes(SQUARE, "thornhaven_blacksmith"))
	await process_frame
	var texts = bjorn.rag_memory.stored.map(func(m): return str(m.text))
	_check("Bjorn heard both", texts.size() == 2)
	_check("From frightened Gregor, darker", texts.size() == 2 and texts[0].begins_with("I heard from Gregor") and ("malice" in texts[0] or "worse besides" in texts[0]))
	_check("From fond Mira, softer", texts.size() == 2 and texts[1].begins_with("I heard from Mira") and ("reasons" in texts[1] or "hard times" in texts[1]))
	_check("The facts survive the drift", texts.all(func(t): return "threatened Davin at knifepoint" in t))

func _test_anonymous_rumour():
	print("Below 0.3: a rumour of a stranger")
	await _reset()
	var ev = {"id": "pe_z", "kind": "kill", "summary": "killed Varn at the old mill", "status": "none", "truth": "true"}
	var text = pe.compose(ev, "dark", 0.25, 0)
	_check("Anonymous and vague", text == "There's a rumour of a stranger who killed a man.")
	_check("No names survive", not ("Varn" in text) and not ("mill" in text))
	_check("At 0.3 the stranger is still the stranger", pe.compose(ev, "plain", 0.3, 0).contains("killed Varn"))
	var promise = {"id": "pe_w", "kind": "promise", "summary": "promised Gregor to save Elena", "status": "broken", "truth": "false"}
	_check("A broken promise, half-forgotten", pe.compose(promise, "plain", 0.2, 0) == "There's a rumour of a stranger who broke a promise.")
	world_state.set_npc_location(GREGOR, SHOP)
	var id = pe.record("harm", "beat a pedlar senseless", [], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	pe.events[id].heard_by["dagna"] = {"fidelity": 0.25, "minute": T0, "from": "x", "via": "", "tone": "plain"}
	var k = pe.known_by("dagna")
	_check("known_by marks it anonymous", k.size() == 1 and k[0].anonymous and k[0].text.begins_with("There's a rumour"))
	_check("A nameless rumour cannot sour anyone on the player", Rep.of("npc", "dagna") == 0.0)

func _test_no_impossible_hearers():
	print("No impossible hearers")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	var id = pe.record("insult", "spat at Gregor's feet", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	var hermit = _spawn("hermit_001", "nowhere_isle")
	var r = pe.spread(id, ["hermit_001"])
	_check("Off the routes graph: refused, unreachable", not r.ok and r.refused.size() == 1 and str(r.refused[0].reason).begins_with("unreachable"))
	r = pe.spread(id, ["nobody_at_all"])
	_check("Someone who is nowhere: refused", not r.ok and r.refused.size() == 1)
	world_state.npc_states[ELENA] = {"is_alive": false, "location": SQUARE}
	r = pe.spread(id, ["elena"])
	_check("The dead hear nothing", not r.ok and "dead" in str(r.refused[0].reason))
	world_state.npc_states[ELENA] = {"is_alive": true, "location": SQUARE}
	world_state.npc_states[GREGOR]["is_alive"] = false
	r = pe.spread(id, ["elena"])
	_check("A dead witness tells no one", not r.ok and str(r.refused[0].reason).begins_with("unreachable"))
	world_state.npc_states[GREGOR]["is_alive"] = true
	pe.spread(id, ["*"], "talk")
	await _advance(600)
	var heard = pe.get_event(id).heard_by.keys()
	var capitol = registry.get_npcs_in_region("the_capitol")
	_check("'*' reaches the event's region", heard.size() > 3 and "mathias" in heard)
	_check("...and nobody outside it", not heard.any(func(w): return w in capitol))
	_check("...and the unreachable never hear", not ("hermit_001" in heard))
	_check("Every hearer was reachable from a teller", heard.all(func(w): return registry.is_reachable(pe._location_of(pe.get_event(id).heard_by[w].from), pe._location_of(w)) or pe._location_of(pe.get_event(id).heard_by[w].from) == pe._location_of(w)))

# =============================================================================
# REPUTATION
# =============================================================================

func _test_reputation_known_events_only():
	print("Reputation per npc, faction and region, from known events only")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	var help = pe.record("help", "carried Gregor's crates", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	var g = Rep.of("npc", "gregor")
	_check("Gregor saw the help: positive", g > 0.0)
	_check("Bjorn knows nothing: 0", Rep.of("npc", "bjorn") == 0.0)
	_check("Thornhaven folk (Gregor) think better of the stranger", Rep.of("faction", "thornhaven") > 0.0)
	_check("Iron Hollow knows nothing yet", Rep.of("faction", "iron_hollow") == 0.0)
	_check("The valley knows; the Capitol does not", Rep.of("region", "western_valley") > 0.0 and Rep.of("region", "the_capitol") == 0.0)
	_check("npc_id and key agree", Rep.of("npc", GREGOR) == g)
	pe.spread(help, ["varn"])
	await _advance(registry.travel_minutes(SHOP, CAMP))
	var v = Rep.of("npc", "varn")
	_check("Heard second-hand counts for less", v > 0.0 and v < g)
	_check("...and now Iron Hollow knows", Rep.of("faction", "iron_hollow") > 0.0)
	world_state.set_npc_location(BJORN, "thornhaven_blacksmith")
	var p = pe.record("promise", "promised Bjorn to bring back his son", ["bjorn"], {"location": "thornhaven_blacksmith", "witnesses": [BJORN], "spread": false})
	var open_rep = Rep.of("npc", "bjorn")
	pe.resolve_promise(p, "broken")
	var broken = Rep.of("npc", "bjorn")
	_check("A broken promise weighs heavily (%.1f)" % broken, broken < -30.0 and absf(broken) > absf(g) and open_rep > 0.0)
	var gift = pe.record("gift", "gave Bjorn a whetstone", ["bjorn"], {"location": "thornhaven_blacksmith", "witnesses": [BJORN], "spread": false})
	_check("A gift after it only softens it", Rep.of("npc", "bjorn") > broken and Rep.of("npc", "bjorn") < 0.0)
	var lie = pe.record("claim", "swore the cart had gone", [], {"location": "thornhaven_blacksmith", "witnesses": [BJORN], "flag": "pe_test_cart", "spread": false})
	var before_lie = Rep.of("npc", "bjorn")
	world_state.set_world_flag("pe_test_cart", false)
	world_state.set_world_flag("pe_test_cart", true)
	world_state.set_world_flag("pe_test_cart", false)
	_check("An exposed lie drags it down", pe.get_event(lie).kind == "lie" and Rep.of("npc", "bjorn") < before_lie)
	var b = Rep.breakdown("npc", "bjorn")
	_check("Breakdown lists only what Bjorn knows", b.events.size() == 3 and not b.events.any(func(e): return e.id == help))
	var old = pe.record("help", "pulled a child from the river", [], {"location": SHOP, "witnesses": [GREGOR], "spread": false, "minute": T0 - 30 * DAY})
	_check("Recency: an old deed counts less than a new one", Rep.recency(pe.get_event(old), world_state.game_minutes) < Rep.recency(pe.get_event(help), world_state.game_minutes))
	_check("Scores stay within -100..100", [Rep.of("npc", "bjorn"), Rep.of("faction", "thornhaven"), Rep.of("region", "western_valley")].all(func(s): return s >= -100.0 and s <= 100.0))
	_check("Unknown scopes are 0", Rep.of("planet", "x") == 0.0 and Rep.of("faction", "nobody") == 0.0)
	_check("Labels", Rep.label(60) == "admired" and Rep.label(-60) == "hated" and Rep.label(0) == "little known")

func _test_iron_hollow_mira():
	print("Iron Hollow counts Mira only once she is revealed")
	await _reset()
	world_state.set_npc_location(MIRA, TAVERN)
	world_state.world_flags.erase("mira_boss_revealed")
	pe.record("spared", "spared a Hollow runner", [], {"location": TAVERN, "witnesses": [MIRA], "spread": false})
	_check("Hidden: Mira is not Iron Hollow", not ("mira" in Rep.faction_members("iron_hollow")) and Rep.of("faction", "iron_hollow") == 0.0)
	_check("...she is reckoned Thornhaven folk", "mira" in Rep.faction_members("thornhaven") and Rep.of("faction", "thornhaven") > 0.0)
	_check("...and her prompt speaks for Thornhaven", Rep.factions_of("mira").has("thornhaven") and not Rep.factions_of("mira").has("iron_hollow"))
	world_state.world_flags["mira_boss_revealed"] = true
	_check("Revealed: Iron Hollow knows what she knows", "mira" in Rep.faction_members("iron_hollow") and Rep.of("faction", "iron_hollow") > 0.0)
	_check("...and Thornhaven no longer counts her", not ("mira" in Rep.faction_members("thornhaven")) and Rep.of("faction", "thornhaven") == 0.0)
	world_state.world_flags.erase("mira_boss_revealed")

# =============================================================================
# PROMPT BLOCK
# =============================================================================

func _test_prompt_block_budget():
	print("The prompt block: compact, fidelity-aware, within budget")
	await _reset()
	world_state.set_npc_location(GREGOR, SHOP)
	_check("Nothing known, no block", pe.get_heard_block(GREGOR) == "")
	var long_text = "promised Gregor on the life of their own mother and every saint in the Cathedral of the Dawn that Elena would be across the river before the Tithe cart came down the ridge trail"
	pe.record("promise", long_text, ["gregor", "elena"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	for i in 6:
		pe.record(["help", "gift", "insult", "threat", "claim", "refusal"][i], "did thing number %d near the counter" % i, [], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	var far = pe.record("kill", "killed a carter on the Kingsroad", [], {"location": "kingsroad_waystation", "witnesses": [], "spread": false})
	pe.events[far].heard_by["gregor"] = {"fidelity": 0.45, "minute": world_state.game_minutes, "from": "wren", "via": "", "tone": "dark"}
	var block = pe.get_heard_block(GREGOR)
	var tokens = int(block.length() / 4.0)
	print("    heard block for Gregor (8 known events): %d chars, ~%d tokens" % [block.length(), tokens])
	print(block.indent("      "))
	_check("Headed 'What you have heard of the stranger'", block.begins_with("## What you have heard of the stranger"))
	_check("At most %d events" % pe.PROMPT_MAX_EVENTS, block.count("\n- (") <= pe.PROMPT_MAX_EVENTS)
	_check("The heaviest first: the promise owed to him, the threat, the killing (half-heard)", "Elena would be across" in block and "thing number 3" in block and "carter" in block)
	_check("Fidelity-aware tags", "(saw it)" in block and "(half-heard)" in block)
	_check("Long lines are clipped", Array(block.split("\n")).all(func(l): return l.length() <= pe.PROMPT_LINE_MAX))
	_check("Faction standing is included", "Thornhaven folk" in block)
	_check("Within budget (<= 200 tokens)", tokens <= 200)
	if director == null:
		return
	# The full per-turn prompt with this block, on the real content (the conversation_agency measure)
	var real_flags = world_state.world_flags
	world_state.world_flags = {}
	director.load_content("res://resources/storylines", "res://souls")
	director.evaluate_all()
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var worst = 0
	for pair in [["gregor", "gregor_merchant"], ["mira", "mira_tavern_keeper"], ["varn", "varn_bandit"], ["corwin", "corwin"]]:
		var npc_id = registry.get_npc_id(pair[0])
		for i in 5:
			pe.record(["promise", "threat", "help", "lie", "gift"][i], "did something memorable to %s, number %d, in front of everyone" % [pair[0], i], [pair[0]],
				{"location": SHOP, "witnesses": [npc_id], "spread": false})
		var params = {"personality": load("res://resources/npc_personalities/%s.tres" % pair[1]), "npc_id": npc_id,
			"tiered_memories": {"pinned": [], "important": ["The stranger asked about the bandits last week."], "relevant": ["Player said: \"Who runs this place?\". I responded: \"I do, love.\"", "The stranger paid in silver."]},
			"relationship_dimensions": {"trust": 10, "respect": 5, "affection": 5, "fear": 0, "familiarity": 20, "memory_count": 3},
			"world_state": {"npc_id": npc_id, "world_flags": {}, "active_quests": []}, "conversation_history": [], "player_input": "What do you know about the bandits?"}
		var full = builder.estimate_token_count(builder.build_context(params))
		var heard = int(pe.get_heard_block(npc_id).length() / 4.0)
		print("    %s: %d tokens per turn (heard block %d)" % [pair[0], full, heard])
		worst = maxi(worst, full)
	_check("Every full prompt with a full heard block stays under ~4000 tokens", worst > 0 and worst <= 4000)
	builder.free()
	world_state.world_flags = real_flags
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)

# =============================================================================
# DEDUP ACROSS SESSIONS
# =============================================================================

func _test_dedup_across_sessions():
	print("Dedup across sessions: nothing stored twice")
	await _reset()
	var gregor = _spawn(GREGOR, SHOP)
	world_state.set_npc_location(GREGOR, SHOP)
	world_state.set_npc_location(ELENA, SQUARE)
	var id = pe.record("help", "patched Gregor's roof", ["gregor"], {"location": SHOP, "witnesses": [GREGOR], "spread": false})
	pe.spread(id, ["elena"])  # Elena is not loaded: her memory waits in the queue
	await _advance(5)
	await process_frame
	_check("Gregor stores it once", gregor.rag_memory.stored.size() == 1)
	_check("Elena's is queued once", propagator.get_pending_count("elena") == 1)
	var key = str(gregor.rag_memory.stored[0].source_flag)
	_check("Keyed by the event (source_flag pe:<id>:<digest>)", key.begins_with("pe:" + id + ":"))
	# A new session: the save is reloaded but ChromaDB (FakeMemory here) kept everything
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))
	propagator.load_from_dict({})
	world_state._apply_player_events_state(saved)
	pe._tell_witnesses(pe.events[id], ["gregor"], false)
	propagator.deliver_memory("gregor", {"flag": key, "how": "witnessed", "text": "again", "event_type": "player_event_witnessed", "importance": 6, "emotion": "x"})
	await process_frame
	_check("Next session: Gregor's collection still holds one", gregor.rag_memory.stored.size() == 1)
	pe.spread(id, ["elena"])
	_check("Elena already heard it: no second telling", propagator.get_pending_count("elena") <= 1)
	var elena = _spawn(ELENA, SQUARE)
	propagator.load_from_dict(JSON.parse_string(JSON.stringify(saved.event_propagation)))
	propagator.deliver_pending(elena)
	await process_frame
	propagator.deliver_pending(elena)
	await process_frame
	_check("Elena gets her queued memory once, on load", elena.rag_memory.stored.size() == 1 and str(elena.rag_memory.stored[0].text).begins_with("I heard from Gregor"))
	if gm:
		var gid = ""
		for g in gm.get_ids():
			if gm.get_instance(g).region == "western_valley":
				gid = g
				break
		if gid != "":
			var tag = pe._source_flag(pe.events[id])
			pe._store_memory(gid, pe.events[id], "first", "heard")
			pe._store_memory(gid, pe.events[id], "second", "heard")
			var count = gm.get_instance(gid).layers.filter(func(l): return str(l.get("tag", "")) == "news:" + tag).size()
			_check("A generic's layer is stored once", count == 1)
	_check("A lost save never collides: same id, different deed, different key", pe._source_flag({"id": id, "summary": "something else", "minute": 1}) != key)

# =============================================================================
# HELPERS
# =============================================================================

func _advance(minutes: int, reason: String = "test") -> void:
	if minutes > 0:
		world_state.advance_time(minutes, reason)
	await process_frame

func _reset():
	for npc in npcs:
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.queue_free()
	npcs.clear()
	await process_frame
	pe.reset()
	pe.player_location_override = ""
	pe.now_override = -1
	pe.capture_enabled = true
	propagator.load_from_dict({})
	changed.clear()
	for flag in world_state.world_flags.keys():
		if flag.begins_with("pe_test_") or flag.begins_with("cv_"):
			world_state.world_flags.erase(flag)
	world_state.npc_states = {}
	world_state.game_minutes = T0
	if director and director.has_method("reset_state"):
		director.reset_state()

func _make_fake(npc_id: String, location: String) -> FakeNPC:
	var npc = FakeNPC.new()
	npc.npc_id = npc_id
	npc.current_location = location
	npc.rag_memory = FakeMemory.new()
	npc.add_child(npc.rag_memory)
	npc.add_to_group("npcs")
	return npc

func _spawn(npc_id: String, location: String) -> FakeNPC:
	var npc = _make_fake(npc_id, location)
	root.add_child(npc)
	npcs.append(npc)
	return npc

## A real BaseNPC (Mira) with in-memory RAGMemory and a fake Claude client
func _make_base_npc() -> Node:
	var npc = load("res://scripts/npcs/base_npc.gd").new()
	npc.npc_id = MIRA
	npc.npc_name = "Mira"
	npc.home_location = TAVERN
	root.add_child(npc)
	await npc.initialize(false, false)  # in-memory: nothing reaches ./chroma
	npc.claude_client.queue_free()
	var fake = FakeClaude.new()
	npc.add_child(fake)
	npc.claude_client = fake
	return npc

func _free_base_npc(npc: Node) -> void:
	npc.is_in_conversation = false
	npc.queue_free()

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if x not in b:
			return false
	return true

func _restore():
	for npc in npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_states
	world_state.game_minutes = saved_minutes
	pe.reset()
	pe.load_from_dict(saved_pe)
	propagator.load_from_dict(saved_propagation)
	pe.player_location_override = ""

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
