extends SceneTree

# Tests the non-linear world runtime (docs/WORLD_SCHEMA.md §11-13):
# - movable fixed points: shift_rules (delay, advance, cancel), applied once each, eves that move with
#   their point, cancelled points that never fire, fired points that cannot move, the shift_fixed_point
#   effect (clamps, movable only, Agency), chronicle + PlayerEvents for the player's shifts, save/load
# - emergent beats: template loading (storyline effects refused), event / reputation / relationship /
#   flag triggers, role binding (witness, near_player, npc:, trigger_match, prefer), generics as roles
#   (lead ruling: every emergent effect but shift_fixed_point), the appeal chooser, Lines, cooldown,
#   max_active, expiry, talked_to resolution, flag resolution, storyline flags untouched, save/load,
#   and the shipped resources/emergence templates
# - inner voice: parsing, boosts in the decision queue and personal turns, pressure from opposed wants,
#   Claude refinement validation, and the never-leaks scan of every prompt builder
# Fixtures and fakes only: a fake PlayerEvents and Claude client, no API calls, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_emergence.gd

const FIX = "res://scripts/debug/fixtures/emergence"
const FIX_STORYLINES = FIX + "/storylines"
const FIX_SOULS = FIX + "/souls"
const FIX_TEMPLATES = FIX + "/templates"
const BAD_TEMPLATES = FIX + "/bad_templates"
const GENERIC_PATH = FIX + "/gen_gossip.md"
const GENERIC = "gen_woodcutter_1"
const POINT = "tn_collection_night"
const DAY = 24 * 60
const SECRET = "xyzzyquux"

class FakePlayerEvents extends Node:
	signal player_event_recorded(ev: Dictionary)
	signal player_event_changed(ev: Dictionary)
	signal player_event_heard(event_id: String, who: String, fidelity: float)
	var events: Dictionary = {}
	var order: Array = []
	var spreads: Array = []
	var counter: int = 0
	func record(kind: String, summary: String, about: Array = [], opts: Dictionary = {}) -> String:
		counter += 1
		var id = "pe_%06d" % counter
		var ev = {"id": id, "kind": kind, "summary": summary, "about": about.duplicate(), "status": str(opts.get("status", "open")),
			"truth": "unknown", "location": str(opts.get("location", "thornhaven_town_square")), "minute": int(opts.get("minute", 0)),
			"witnesses": opts.get("witnesses", []).duplicate(), "heard_by": opts.get("heard_by", {}).duplicate(), "fidelity": 1.0,
			"tone": str(opts.get("tone", ""))}
		events[id] = ev
		order.append(id)
		player_event_recorded.emit(ev.duplicate(true))
		return id
	func set_status(id: String, status: String) -> void:
		events[id]["status"] = status
		player_event_changed.emit(events[id].duplicate(true))
	func get_event(id: String) -> Dictionary:
		return events[id].duplicate(true) if events.has(id) else {}
	func get_events() -> Array:
		return order.map(func(id): return events[id].duplicate(true))
	func events_matching(_query: Dictionary = {}) -> Array:
		return get_events()
	func known_by(key: String) -> Array:
		var out: Array = []
		for id in order:
			if events[id].heard_by.has(key):
				out.append({"id": id, "text": "the stranger " + events[id].summary, "fidelity": float(events[id].heard_by[key].get("fidelity", 1.0))})
		return out
	func fidelity_for(id: String, key: String) -> float:
		return float(events[id].heard_by.get(key, {}).get("fidelity", 0.0)) if events.has(id) else 0.0
	func spread(event_id: String, to_keys: Array, via: String = "") -> Dictionary:
		spreads.append({"event": event_id, "to": to_keys.duplicate(), "via": via})
		return {"ok": true, "scheduled": [{"to": "x"}], "refused": []}

class FakeClaude extends Node:
	var api_key_override: String = "fake-key-for-tests"
	var reply: String = ""
	var calls: int = 0
	func send_message(_messages: Array, _system_prompt: String = "") -> Dictionary:
		calls += 1
		return {"text": reply}

var director: Node
var world_state: Node
var registry: Node
var voice: Node
var fake: FakePlayerEvents
var failures: int = 0
var fired_log: Array = []
var rep: Dictionary = {}
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var save_existed: bool
var real_pe_capture = null

func _init():
	await process_frame
	await process_frame
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	voice = root.get_node("InnerVoice")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	var real_pe = root.get_node_or_null("PlayerEvents")
	if real_pe and "capture_enabled" in real_pe:
		real_pe_capture = real_pe.capture_enabled
		real_pe.capture_enabled = false
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.end_on_season_end = false
	director.player_location_override = "thornhaven_town_square"
	director.reputation_override = func(scope, id): return float(rep.get("%s:%s" % [scope, id], 0.0))
	fake = FakePlayerEvents.new()
	root.add_child(fake)
	director.set_player_events(fake)
	root.get_node("EventBus").calendar_flag_fired.connect(func(flag, _at): fired_log.append(flag))
	_fresh_world()

	print("============================================================")
	print("🧪 EMERGENCE, FIXED POINTS + INNER VOICE TEST")
	print("============================================================\n")

	_test_shift_rules()
	_test_eves()
	_test_shift_effect()
	_test_derived_flag_declared_by_storyline()
	_test_shift_save_load()
	_test_world_advance_cap()
	_test_templates_load()
	await _test_event_trigger_roles_appeal()
	await _test_generic_role()
	await _test_condition_triggers()
	_test_storyline_flags_untouched()
	_test_emergence_save_load()
	_test_shipped_templates()
	await _test_collection_night_templates()
	_test_inner_voice_parse()
	await _test_inner_voice_boosts()
	await _test_inner_voice_claude()
	await _test_never_leaks()
	_test_console()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# MOVABLE FIXED POINTS (§11)
# =============================================================================

func _point_minute(point: String = POINT) -> int:
	return int(world_state.get_calendar_point(point).minute)

func _base(point: String = POINT) -> int:
	return int(world_state.get_calendar_point(point).base_minute)

func _last_shift_entry() -> Dictionary:
	var rows = director.get_chronicle(0).filter(func(e): return e.mode == "fixed_point")
	return rows.back() if not rows.is_empty() else {}

func _test_shift_rules():
	print("Shift rules")
	_fresh_world()
	_check("Collection Night is movable, with three rules", world_state.is_movable_point(POINT) and _base() == 6 * DAY + 22 * 60)
	var before = fake.order.size()
	world_state.set_world_flag("hc_varn_dead", true)
	_check("hc_varn_dead delays it two days", _point_minute() == _base() + 2 * DAY and world_state.get_calendar_point(POINT).shift_days == 2)
	var entry = _last_shift_entry()
	_check("...chronicled (mode fixed_point, the rule, the player who set the flag)", entry.get("trigger", "") == "shift_rule:hc_varn_dead" and entry.get("npc", "") == "player" and entry.choice == "delay")
	_check("...and the player's doing is a PlayerEvents event", fake.order.size() == before + 1 and fake.events[fake.order.back()].kind == "refusal")
	world_state.set_world_flag("hc_varn_dead", false)
	world_state.set_world_flag("hc_varn_dead", true)
	_check("A rule applies once, however often its flag turns true", _point_minute() == _base() + 2 * DAY)
	world_state.set_world_flag("cou_council_refuses", true)
	_check("cou_council_refuses brings it a day earlier (net +1)", _point_minute() == _base() + DAY)

	_fresh_world()
	world_state.set_world_flag("cou_council_refuses", true)
	_check("Advance: -1 day", _point_minute() == _base() - DAY)
	world_state.advance_time(_base() - DAY - world_state.get_game_minutes() + 1, "test")
	_check("...and it falls a day early", POINT in fired_log and world_state.get_world_flag(POINT))

	_fresh_world()
	world_state.advance_time(5 * DAY + 3 * 60, "test")  # day 6, 23:00: past the advanced time already
	fired_log.clear()
	world_state.set_world_flag("cou_council_refuses", true)
	_check("A shift that lands in the past fires at once", POINT in fired_log)

	_fresh_world()
	world_state.set_world_flag("tn_taken_freed", true)
	_check("tn_taken_freed cancels it", world_state.is_point_cancelled(POINT) and world_state.get_world_flag("tn_collection_night_cancelled"))
	_check("...<point>_cancelled is a calendar flag with canon text", StoryFlags.get_flag_description("tn_collection_night_cancelled") != "")
	world_state.advance_time(12 * DAY, "test")
	_check("A cancelled point never fires", not world_state.get_world_flag(POINT) and not POINT in fired_log and not world_state.has_calendar_fired(POINT))
	_check("...nor its eve", not world_state.get_world_flag("tn_collection_night_eve"))
	world_state.set_world_flag("hc_varn_dead", true)
	_check("...and no rule moves it after", world_state.get_calendar_point(POINT).shift_days == 0)

	_fresh_world()
	world_state.advance_time(15, "test")  # 20:15: the drawing (20:10) has fallen
	var moved = director.shift_fixed_point("tn_drawing", 1, "too late", "player")
	_check("A point that fired cannot move", not moved.ok and "already" in moved.reason)
	var fixed = director.shift_fixed_point("season_end", 1, "no", "player")
	_check("A point that is not movable cannot move", not fixed.ok and "cannot move" in fixed.reason)
	var nonsense = director.shift_fixed_point("tn_day_99", 1, "no", "player")
	_check("Nor can an unknown one", not nonsense.ok)

func _test_eves():
	print("Eves (<point>_eve, 24 game hours before the point's current time)")
	_fresh_world()
	var eve = _point_minute() - DAY
	world_state.advance_time(eve - world_state.get_game_minutes() - 10, "test")
	_check("Not before its eve", not world_state.get_world_flag("tn_collection_night_eve"))
	world_state.advance_time(20, "test")
	_check("The eve falls a day before the point", world_state.get_world_flag("tn_collection_night_eve") and not world_state.get_world_flag(POINT))
	_check("...with canon text", StoryFlags.get_flag_description("tn_collection_night_eve").contains("Collection Night"))
	_fresh_world()
	world_state.set_world_flag("hc_varn_dead", true)  # +2 days
	world_state.advance_time(6 * DAY, "test")       # day 7, 20:00: the old eve has long passed
	_check("A delayed point's eve moves with it", not world_state.get_world_flag("tn_collection_night_eve"))
	world_state.advance_time(DAY + 3 * 60, "test")  # day 8, 23:00 (eve: day 8, 22:00)
	_check("...and falls at the new eve", world_state.get_world_flag("tn_collection_night_eve") and not world_state.get_world_flag(POINT))
	_fresh_world()
	world_state.advance_time(5 * DAY - 60, "test")  # day 6, 19:00 (eve day 6 22:00 not yet)
	world_state.set_world_flag("cou_council_refuses", true)  # eve now day 5, 22:00: already past
	_check("An eve a shift lands in the past fires at once", world_state.get_world_flag("tn_collection_night_eve"))

func _test_shift_effect():
	print("The shift_fixed_point effect")
	_fresh_world()
	var v = director._effects.validate({"type": "shift_fixed_point", "point": POINT, "days": 9, "reason": "r"})
	_check("days clamp to +3", v.ok and v.effect.days == 3)
	v = director._effects.validate({"type": "shift_fixed_point", "point": POINT, "days": -7})
	_check("...and to -3", v.ok and v.effect.days == -3)
	_check("0 days is refused", not director._effects.validate({"type": "shift_fixed_point", "point": POINT, "days": 0}).ok)
	_check("No days and no cancel is refused", not director._effects.validate({"type": "shift_fixed_point", "point": POINT}).ok)
	_check("cancel: true needs no days", director._effects.validate({"type": "shift_fixed_point", "point": POINT, "cancel": true}).ok)
	_check("A fixed (not movable) point is refused", not director._effects.validate({"type": "shift_fixed_point", "point": "season_end", "days": 1}).ok)
	_check("A flag that is no calendar point is refused", not director._effects.validate({"type": "shift_fixed_point", "point": "fx_story_done", "days": 1}).ok)
	var before = fake.order.size()
	var result = director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": 2, "reason": "Mira sent word to wait."}, "mira")
	_check("An NPC's effect moves the point", result.ok and _point_minute() == _base() + 2 * DAY)
	var entry = _last_shift_entry()
	_check("...chronicled with the NPC as actor and its reason", entry.npc == "mira" and entry.label == "Mira sent word to wait." and entry.trigger == "effect")
	_check("...and no player event (the player did not do it)", fake.order.size() == before)
	_check("Canon: a WorldEvents event carries the reason", root.get_node("WorldEvents").canonical_events.values().any(func(e): return e.description == "Mira sent word to wait."))
	var mira = director.get_soul("mira")
	var aldric = director.get_soul("aldric")
	var effect = {"type": "shift_fixed_point", "point": POINT, "days": 1}
	_check("Agency: Mira's scheme grants it; Aldric's react does not", mira.get_denial_reason("scheme", effect) == "" and aldric.get_denial_reason("react", effect) != "")
	_check("No effect may set <point>_cancelled or <point>_eve", not director._effects.validate({"type": "set_flag", "flag": "tn_collection_night_cancelled"}).ok
		and not director._effects.validate({"type": "set_flag", "flag": "tn_collection_night_eve"}).ok)
	director.shift_fixed_point(POINT, "cancel", "The Pit was emptied.", "player")
	_check("cancel through the API", world_state.is_point_cancelled(POINT) and StoryFlags.get_flag_description("tn_collection_night_cancelled") == "The Pit was emptied.")

func _test_derived_flag_declared_by_storyline():
	print("A storyline that declares <point>_cancelled")
	_fresh_world()
	StoryFlags.register_flag_descriptions({"tn_collection_night_cancelled": "No cart came, by the storyline's own words"})
	world_state.refresh_calendar_descriptions()
	_check("The storyline's description wins", StoryFlags.get_flag_description("tn_collection_night_cancelled") == "No cart came, by the storyline's own words")
	_check("...and the calendar does not register it twice", not StoryFlags.is_calendar_flag("tn_collection_night_cancelled") and StoryFlags.is_calendar_flag("tn_collection_night_eve"))
	_check("...yet no effect may set it", not director._effects.validate({"type": "set_flag", "flag": "tn_collection_night_cancelled"}).ok)
	world_state.set_world_flag("tn_taken_freed", true)
	_check("Cancelling still sets it, and keeps the storyline's text", world_state.get_world_flag("tn_collection_night_cancelled")
		and StoryFlags.get_flag_description("tn_collection_night_cancelled") == "No cart came, by the storyline's own words")
	StoryFlags._registered_descriptions.erase("tn_collection_night_cancelled")
	world_state.refresh_calendar_descriptions()

func _test_shift_save_load():
	print("Save and load of shifts")
	_fresh_world()
	world_state.set_world_flag("hc_varn_dead", true)
	director.shift_fixed_point("tn_drawing", "cancel", "The drawing was called off.", "mira")
	world_state.advance_time(7 * DAY + 3 * 60, "test")  # day 8, 23:00: the shifted eve (day 8, 22:00) passed
	var eve_before = world_state.get_world_flag("tn_collection_night_eve")
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))
	_check("The save carries shifts and eves", saved.get("calendar_shifts", {}).has(POINT) and saved.get("calendar_eves_fired", {}).has(POINT))
	_fresh_world()
	world_state.load_from_dict(saved)
	_check("Loading restores the shift", _point_minute() == _base() + 2 * DAY and world_state.get_calendar_point(POINT).shifts.size() == 1)
	_check("...the cancellation", world_state.is_point_cancelled("tn_drawing") and StoryFlags.get_flag_description("tn_drawing_cancelled") == "The drawing was called off.")
	_check("...and the eve that fell", eve_before and world_state.get_world_flag("tn_collection_night_eve"))
	fired_log.clear()
	world_state.set_world_flag("hc_varn_dead", false)
	world_state.set_world_flag("hc_varn_dead", true)
	_check("Rules already applied stay applied after a load", _point_minute() == _base() + 2 * DAY)
	world_state.advance_time(DAY, "test")
	_check("The point falls once at its shifted time; the cancelled drawing never", fired_log.count(POINT) == 1 and not "tn_drawing" in fired_log)

func _test_world_advance_cap():
	print("The world alone brings a point at most one day early")
	_fresh_world()
	var two = director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": -2, "reason": "Varn brought the cart early."}, "varn")
	var entry = _last_shift_entry()
	_check("An NPC's -2 with no player in its chain is clamped to -1", two.ok and _point_minute() == _base() - DAY and entry.get("clamped_from", 0) == -2 and "clamped" in entry.reason)
	var more = director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": -1, "reason": "Earlier still."}, "mira")
	entry = _last_shift_entry()
	_check("A further world-only advance is refused, and chronicled as clamped", not more.ok and _point_minute() == _base() - DAY and entry.choice == "clamped" and entry.npc == "mira")
	director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": 2, "reason": "Then it was delayed."}, "mira")
	_check("Delays are not capped", _point_minute() == _base() + DAY)
	director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": -1, "reason": "Early again."}, "varn")
	_check("...and the cap counts advances, not the net (still refused)", _point_minute() == _base() + DAY)
	world_state.set_world_flag("hc_varn_dead", false)
	director._apply_effect_as_director({"type": "set_flag", "flag": "cou_council_refuses", "value": true}, "mathias", {"player_chain": false})
	_check("A rule whose flag an NPC set on its own counts as the world's (refused)", _point_minute() == _base() + DAY)

	_fresh_world()
	director.shift_fixed_point(POINT, -2, "The stranger forced the Hollow's hand.", "player")
	_check("The player's own -2 is not capped", _point_minute() == _base() - 2 * DAY)
	director._apply_effect_as_director({"type": "set_flag", "flag": "cou_council_refuses", "value": true}, "mathias", {"player_chain": true})
	_check("A flag an NPC set in the player's chain is player-caused: its rule brings it to Day 4, 22:00", _point_minute() == _base() - 3 * DAY
		and world_state.get_calendar_point(POINT).minute == 3 * DAY + 22 * 60)
	_check("...chronicled as player-caused", _last_shift_entry().get("player_caused", false) == true)

	_fresh_world()
	director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": -1, "reason": "Early."}, "varn")
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))
	_check("The save keeps the per-source totals", int(saved.calendar_shifts[POINT].get("world_advance", 0)) == -1)
	_fresh_world()
	world_state.load_from_dict(saved)
	var after = director.apply_effect({"type": "shift_fixed_point", "point": POINT, "days": -1, "reason": "Earlier."}, "mira")
	_check("...so after a load the cap still holds", not after.ok and _point_minute() == _base() - DAY)
	director.shift_fixed_point(POINT, -1, "The stranger hurried it.", "player")
	_check("...while the player can still bring it earlier", _point_minute() == _base() - 2 * DAY and int(world_state.get_calendar_shifts()[POINT].player_advance) == -1)

# =============================================================================
# EMERGENT BEATS (§12)
# =============================================================================

func _test_templates_load():
	print("Templates")
	var n = director.load_emergence(BAD_TEMPLATES)
	var errors = director.get_emergence_errors()
	_check("A template using set_flag is refused at load", n == 1 and errors.any(func(e): return "never use set_flag" in e))
	_check("...as is one whose hook names an undeclared role", errors.any(func(e): return "ghost" in e) and director.get_emergence_templates() == ["fx_good_one"])
	n = director.load_emergence(FIX_TEMPLATES)
	_check("The fixture templates load", n == 4 and director.get_emergence_errors().is_empty())

func _test_event_trigger_roles_appeal():
	print("Event triggers, roles, the appeal chooser, cooldown, talked_to, expiry")
	_fresh_world()
	_dims({"aldric": {"affection": 40, "trust": -60}, "mira": {"affection": 10}})
	var id = fake.record("promise", "get Elena out before the cart", ["elena"], {"witnesses": ["mira_tavern_keeper_001", "aldric_peacekeeper_001"]})
	_check("An open promise matches nothing", director.get_emergent_instances().is_empty())
	fake.set_status(id, "broken")
	var instances = director.get_emergent_instances()
	_check("A broken promise grows the template", instances.size() == 1 and instances[0].template == "fx_broken_promise" and instances[0].event_id == id)
	var inst = instances[0]
	_check("event_witness + affection_desc binds Aldric (most fond), not Mira", inst.roles.get("wronged", "") == "aldric")
	_check("{wronged.home} fills the location", inst.location == registry.get_npc_home("aldric"))
	var hook = director.get_emergence().resolved_hook(inst, "confront")
	_check("{player} and {event.summary} fill the situation", hook.situation == "the stranger swore to get Elena out before the cart. They didn't.")
	_check("{wronged} fills effect npc fields with the key", hook.options[0].effects[0].npc == "aldric" and ("(%s)" % id) in hook.options[0].effects[0].text)
	_check("The instantiation is chronicled (mode emergent)", director.get_chronicle(0).any(func(e): return e.mode == "emergent" and e.choice == "instantiated" and e.emergent == inst.id))
	_check("...and its on_open hook waits in the decision queue", director.get_decision_queue().any(func(q): return q.storyline == "emergent:" + inst.id and q.hook == "confront"))
	var entries = await director.advance_round("test")
	var made = entries.filter(func(e): return e.get("mode", "") == "emergent")
	_check("The story clock decides it: appeal picks 'demand' (trust -60)", made.size() == 1 and made[0].choice == "demand" and made[0].npc == "aldric")
	_check("...its effects apply (agenda + trust)", made[0].applied.size() == 2 and director.get_agendas("aldric").any(func(a): return id in a.text))
	var em = director.get_emergence()
	var aldric = director.get_soul("aldric")
	_dims({"aldric": {"affection": -100}})
	var choice = em.choose_by_appeal(aldric, "aldric", hook)
	_check("Lines filter the chooser: Aldric will not spread_event even when it appeals most", choice.choice == "demand")
	_check("Appeal = Σ coefficient × feeling", is_equal_approx(em.appeal_score({"trust": -0.5, "fear": -0.3}, {"trust": -60, "fear": 10}), 27.0))

	var id2 = fake.record("promise", "stand at the gate", ["aldric"], {"witnesses": ["aldric_peacekeeper_001"]})
	fake.set_status(id2, "broken")
	_check("max_active: a second broken promise grows nothing while one is active", director.get_emergent_instances(false).size() == 1)
	director.finish_conversation("mira")
	_check("Talking to someone else resolves nothing", director.get_emergent_instances(false).size() == 1)
	director.finish_conversation("aldric")
	var closed = director.get_emergent_instances()[0]
	_check("talked_to:wronged resolves when the conversation with Aldric ends", closed.status == "resolved" and closed.outcome == "talked_to:aldric")
	var id3 = fake.record("promise", "bring bread", ["mira"], {"witnesses": ["mira_tavern_keeper_001"]})
	fake.set_status(id3, "broken")
	_check("Cooldown: none within a day of the last", director.get_emergent_instances(false).is_empty() and "cooling" in em.get_block_reason("fx_broken_promise"))
	world_state.advance_time(DAY + 10, "test")
	var id4 = fake.record("promise", "fetch water", ["mira"], {"witnesses": ["mira_tavern_keeper_001"]})
	fake.set_status(id4, "broken")
	_check("After the cooldown it grows again (Mira, the only witness)", director.get_emergent_instances(false).size() == 1 and director.get_emergent_instances(false)[0].roles.wronged == "mira")
	world_state.advance_time(2 * DAY + 10, "test")
	var last = director.get_emergent_instances().back()
	_check("expires_days closes it as expired", last.status == "expired" and last.outcome == "expired")
	fake.set_status(id4, "broken")
	_check("One event never grows the same template twice", director.get_emergent_instances().filter(func(i): return i.event_id == id4).size() == 1)
	director.relationship_dims_override = {}

func _test_generic_role():
	print("Generics as roles (near_player), the lead's Agency ruling, tone")
	_fresh_world()
	var text = FileAccess.get_file_as_string(GENERIC_PATH)
	_check("A generic soul registers", director.register_soul(GENERIC, text, {"tier": "generic", "npc_id": GENERIC, "home": "thornhaven_town_square"}))
	world_state.set_npc_location(GENERIC, "thornhaven_town_square")
	_dims({GENERIC: {"familiarity": 50}})
	fake.record("gift", "gave Aldric a loaf", ["aldric"], {"tone": "cold"})
	_check("tone must match", director.get_emergent_instances().is_empty())
	var gift = fake.record("gift", "gave Aldric a loaf", ["aldric"], {"tone": "warm"})
	var inst = director.get_emergent_instances(false)
	_check("near_player + familiarity_desc binds the generic", inst.size() == 1 and inst[0].roles.gossip == GENERIC)
	var minute = _point_minute()
	var entries = await director.advance_round("test")
	var made = entries.filter(func(e): return e.get("mode", "") == "emergent")
	_check("The generic cannot shift_fixed_point, so 'tell_round' wins", made.size() == 1 and made[0].choice == "tell_round" and _point_minute() == minute)
	_check("...and spread_event is allowed despite its converse-only Agency (role slot + '*')", fake.spreads.any(func(s): return s.event == gift and s.to == [GENERIC, "*"]))
	_check("...a literal NPC key works as an agenda npc", director.get_agendas("aldric").any(func(a): return a.text.begins_with("Mention that %s talks" % director.get_display_name(GENERIC))))
	var soul = director.get_soul(GENERIC)
	_check("Lines still apply to generics", director.get_emergence().effect_denial(soul, GENERIC, "converse", {"type": "adjust_relationship", "npc": GENERIC, "dimension": "trust", "delta": 1}) != "")
	world_state.advance_time(DAY + 5, "test")
	_check("days:1 resolves it", director.get_emergent_instances()[0].status == "resolved" and director.get_emergent_instances()[0].outcome == "days:1")
	director.unregister_soul(GENERIC)
	director.relationship_dims_override = {}

func _test_condition_triggers():
	print("Reputation, relationship and flag triggers")
	_fresh_world()
	rep = {"faction:thornhaven": -50.0}
	_dims({"mathias": {"trust": 50}})
	var entries = await director.advance_round("test")
	var cold = director.get_emergent_instances().filter(func(i): return i.template == "fx_cold_village")
	_check("Reputation below -40 grows it at the round, binding npc:mathias", cold.size() == 1 and cold[0].roles.elder == "mathias")
	entries = await director.advance_round("test")
	_check("Mathias (aid grants shift_fixed_point) begs a day: Collection Night +1", _point_minute() == _base() + DAY)
	_check("...chronicled with Mathias as actor", _last_shift_entry().npc == "mathias" and _last_shift_entry().emergent == cold[0].id)
	world_state.set_world_flag("fx_story_done", true)
	_check("A flag in resolves_on resolves it", director.get_emergent_instances().filter(func(i): return i.template == "fx_cold_village")[0].status == "resolved")
	rep = {}
	_dims({"bjorn": {"fear": 70}})
	entries = await director.advance_round("test")
	var feared = director.get_emergent_instances().filter(func(i): return i.template == "fx_feared")
	_check("relationship any/fear>50 binds the NPC it matched (trigger_match)", feared.size() == 1 and feared[0].roles.afraid == "bjorn")
	await director.advance_round("test")
	_check("...who acts", director.get_agendas("bjorn").any(func(a): return "Keep the talk short" in a.text))
	director.relationship_dims_override = {}

func _test_storyline_flags_untouched():
	print("Emergent beats never set storyline flags")
	_fresh_world()
	var em = director.get_emergence()
	var inst = em.try_instantiate("fx_feared", {}, ["bjorn"])
	_check("(an instance to test with)", not inst.is_empty())
	var flags_before = _storyline_flag_snapshot()
	var status_before = director.get_beat_status("fx_story", "the_ledger")
	var hook = em.resolved_hook(inst, "flinch")
	var decision = {"choice": "avoid", "option": hook.options[0], "effects": [
		{"type": "set_flag", "flag": "fx_ledger_burned", "value": true},
		{"type": "block_beat", "storyline": "fx_story", "beat": "the_ledger"},
		{"type": "agenda", "npc": "bjorn", "text": "Stay quiet."}], "reason": "", "mode": "offline"}
	var entry = em.carry_out(inst, hook, "manual", "bjorn", director.get_soul("bjorn"), decision)
	_check("set_flag and block_beat are dropped", entry.dropped.size() == 2 and entry.dropped.all(func(d): return "never change storylines" in d.reason))
	_check("...the personal effect still applies", entry.applied.size() == 1 and entry.applied[0].type == "agenda")
	_check("Storyline flags and beats are untouched", _storyline_flag_snapshot() == flags_before and director.get_beat_status("fx_story", "the_ledger") == status_before)

func _test_emergence_save_load():
	print("Save and load of emergent instances")
	_fresh_world()
	var em = director.get_emergence()
	var inst = em.try_instantiate("fx_feared", {}, ["bjorn"])
	var saved = JSON.parse_string(JSON.stringify(director.save()))
	director.reset_state()
	_check("(reset forgets it)", director.get_emergent_instances().is_empty())
	director.load_from_dict(saved)
	var back = director.get_emergent_instances()
	_check("Loading restores the instance with its roles", back.size() == 1 and back[0].id == inst.id and back[0].roles.afraid == "bjorn" and back[0].status == "active")
	_check("...and its cooldown", "cooling" in em.get_block_reason("fx_feared") or "max_active" in em.get_block_reason("fx_feared"))
	_check("...and its queued hook", director.get_decision_queue().any(func(q): return q.storyline == "emergent:" + inst.id))

func _test_shipped_templates():
	print("The shipped templates (resources/emergence)")
	var n = director.load_emergence("res://resources/emergence")
	_check("All %d shipped templates load without errors" % n, n >= 20 and director.get_emergence_errors().is_empty())
	for err in director.get_emergence_errors():
		print("    ! %s" % err)
	var em = director.get_emergence()
	for tid in ["widow_hastens_the_cart", "varn_reads_the_gate", "elder_begs_a_day"]:
		var t: Dictionary = em.get_template(tid)
		var uses = false
		for hook in t.get("hooks", []):
			for option in hook.options:
				for e in option.get("effects", []):
					if e.get("type", "") == "shift_fixed_point" and director._effects.validate(e).ok:
						uses = true
		_check("%s offers a valid shift_fixed_point" % tid, uses)
	director.load_emergence(FIX_TEMPLATES)

## The three Collection Night templates against the real souls (Mira scheme, Varn scheme, Mathias aid)
func _test_collection_night_templates():
	print("Collection Night templates with the real souls")
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	director.load_emergence("res://resources/emergence")
	var em = director.get_emergence()
	var cases = [
		["widow_hastens_the_cart", "mira", {"fear": 50, "respect": 50}, -1, {}],
		["elder_begs_a_day", "mathias", {"trust": 50, "respect": 30}, 1, {"id": "pe_test_1", "kind": "promise", "status": "open", "about": ["mathias"], "summary": "swore to stand with the council"}],
		["varn_reads_the_gate", "varn", {"respect": -50, "fear": -50}, -1, {"id": "pe_test_2", "kind": "kill", "about": [], "summary": "killed a Hollow man on the trail"}],
	]
	for c in cases:
		world_state.world_flags = {}
		world_state.npc_states = {}
		world_state.load_calendar()
		world_state.reset_calendar(world_state.start_minute)
		director.reset_state()
		em.reset()
		_dims({c[1]: c[2]})
		var inst = em.try_instantiate(c[0], c[4], [])
		_check("%s binds %s" % [c[0], c[1]], not inst.is_empty() and c[1] in inst.roles.values())
		await director.advance_round("test")
		var shift = _last_shift_entry()
		_check("...who moves Collection Night %+d day (Agency grants shift_fixed_point)" % c[3], _point_minute() == _base() + c[3] * DAY and shift.get("npc", "") == c[1])
		if shift.is_empty():
			for e in director.get_chronicle(0).filter(func(x): return x.mode == "emergent"):
				print("    %s %s dropped=%s" % [e.choice, e.reason, e.dropped])
	director.relationship_dims_override = {}
	director.storyline_dir = ""  # _fresh_world reloads the fixtures

# =============================================================================
# INNER VOICE (§13)
# =============================================================================

func _test_inner_voice_parse():
	print("Inner voice: parsing")
	_fresh_world()
	voice.clear()
	var i = voice.think("I must save Elena from Varn before the cart comes!")
	_check("NPC names become about ids", "npc:elena" in i.about and "npc:varn" in i.about)
	_check("save -> support; must and ! strengthen it", i.stance == "support" and i.strength > 0.5 and i.goal == "save Elena")
	var c = voice.think("I wonder who keeps the tavern")
	_check("wonder -> curious, hedged", c.stance == "curious" and c.strength <= 0.5)
	var n = voice.think("I will never help Varn")
	_check("A negation flips the stance", n.stance == "oppose")
	var s = voice.think("burn the ledger in the square")
	_check("Storyline beats match by their words", "beat:fx_story/the_ledger" in s.about)
	_check("Flags match by their words", "flag:fx_ledger_burned" in s.about)
	var a = voice.think("help with the chapel roof slates")
	_check("Life arcs match", "arc:mathias/chapel_roof" in a.about)
	_check("The history keeps every thought for the epilogue", voice.get_history().size() == 5)
	voice.clear()

func _test_inner_voice_boosts():
	print("Inner voice: boosts and pressure")
	_fresh_world()
	director.evaluate_all()
	var queue = director.get_decision_queue().map(func(q): return q.hook)
	_check("Three fixture hooks queue in file order", queue == ["burn_it", "hide_elena", "take_her"])
	var first = await director.advance_round("test")
	_check("Without thoughts the round takes the oldest (burn_it)", not first.is_empty() and first[0].hook == "burn_it")
	_fresh_world()
	director.evaluate_all()
	voice.think("I will hide Elena in the cellar")
	_check("A matching thought pulls hide_elena to the front", director._ordered_queue()[0].hook == "hide_elena")
	var boosted = await director.advance_round("test")
	_check("...and the round decides it first", not boosted.is_empty() and boosted[0].hook == "hide_elena")
	_check("The decision queue itself is unchanged by thinking (only the order it is taken in)", director.get_decision_queue().map(func(q): return q.hook).has("burn_it"))
	voice.clear()
	_fresh_world()
	director.evaluate_all()
	voice.think("I will protect Elena")
	_check("Pressure: Varn's 'take the girl' harms Elena, so Varn opposes", voice.pressure_for("varn") > 0.0 and voice.pressure_for("aldric") == 0.0)
	var q = director.get_decision_queue()
	var p_take = director.get_queue_priority(q.filter(func(x): return x.hook == "take_her")[0])
	var p_burn = director.get_queue_priority(q.filter(func(x): return x.hook == "burn_it")[0])
	_check("...so his hook gets a turn sooner than an unrelated one", p_take > p_burn)
	voice.clear()
	_fresh_world()
	director.player_location_override = "nowhere_at_all"
	var plain = director.get_personal_candidates().map(func(c): return c.npc)
	_check("Personal turns without thoughts: Bjorn (weight 9) before Mathias (3)", plain.find("bjorn") < plain.find("mathias") and plain.find("mathias") >= 0)
	voice.think("Help Mathias mend the chapel roof")
	var steered = director.get_personal_candidates().map(func(c): return c.npc)
	_check("A thought about Mathias's Life puts him first", steered[0] == "mathias")
	director.player_location_override = "thornhaven_town_square"
	voice.clear()

func _test_inner_voice_claude():
	print("Inner voice: Claude refinement, validated")
	voice.clear()
	var checked = voice.validate_refinement('{"goal": "save Elena", "about": ["npc:elena", "npc:nobody_at_all"], "stance": "support", "strength": 3}')
	_check("Unknown ids are dropped; strength clamps", checked.ok and checked.intention.about == ["npc:elena"] and checked.intention.strength == 1.0)
	_check("An unknown stance is refused", not voice.validate_refinement('{"goal": "x", "stance": "furious", "strength": 0.5}').ok)
	_check("Prose is refused", not voice.validate_refinement("I think they want to save her").ok)
	var claude = FakeClaude.new()
	root.add_child(claude)
	voice.mode = "claude"
	voice.client_override = claude
	claude.reply = '{"goal": "keep Elena from the cart", "about": ["npc:elena", "beat:fx_story/the_girl"], "stance": "support", "strength": 0.9}'
	var refined = await voice.think_async("she can't go")
	_check("A valid reply refines the intention", refined.mode == "claude" and refined.goal == "keep Elena from the cart" and "beat:fx_story/the_girl" in refined.about)
	claude.reply = "no json here"
	var kept = await voice.think_async("I will hide Elena")
	_check("A bad reply keeps the offline parse", kept.mode == "claude_fallback" and "npc:elena" in kept.about)
	voice.mode = ""
	voice.client_override = null
	claude.queue_free()
	voice.clear()

func _test_never_leaks():
	print("Thoughts never reach an NPC")
	_fresh_world()
	var text = FileAccess.get_file_as_string(GENERIC_PATH)
	director.register_soul(GENERIC, text, {"tier": "generic", "npc_id": GENERIC, "home": "thornhaven_town_square"})
	director.evaluate_all()
	var thought = voice.think("I secretly mean to betray Mira and Elena, %s, and burn the ledger in the square" % SECRET)
	_check("(the thought is kept privately)", SECRET in JSON.stringify(voice.get_history()))
	var em = director.get_emergence()
	var inst = em.try_instantiate("fx_feared", {}, ["bjorn"])
	fake.record("gift", "gave Mira a ribbon", ["mira"], {"tone": "warm", "witnesses": ["mira_tavern_keeper_001"]})
	await director.advance_round("test")
	await director.advance_round("test")
	var texts: Array = []
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var agent = director.get_agent()
	for key in director.get_soul_keys():
		var soul = director.get_soul(key)
		texts.append(director.get_conversation_block(key))
		texts.append(director.get_conversation_agency_block(key))
		texts.append(soul.get_prompt_block(true))
		texts.append(soul.get_conversation_prompt_block())
		texts.append(builder._build_storyline_section(director._npc_id(key)))
		texts.append(JSON.stringify(director.get_agendas(key, true)))
		for arc in soul.life_arcs:
			for step in arc.steps:
				var p = agent.build_personal_prompt(soul, arc, step, {"location": "x", "people": ""})
				texts.append(p.system + p.user)
	for sid in director.get_storyline_ids():
		for beat in director.get_storyline(sid).beats:
			for hook in beat.get("hooks", []):
				for key in hook.get("eligible", []):
					var soul = director.get_soul(str(key))
					if soul:
						var p = agent.build_prompt(soul, hook, {"storyline_title": sid, "beat_title": beat.title})
						texts.append(p.system + p.user)
	for i in director.get_emergent_instances():
		var t = em.get_template(i.template)
		for hook in t.get("hooks", []):
			var resolved = em.resolved_hook(i, str(hook.id))
			for key in resolved.eligible:
				var soul = director.get_soul(key)
				if soul:
					var p = agent.build_prompt(soul, resolved, {"storyline_title": i.title, "beat_title": ""})
					texts.append(p.system + p.user)
	texts.append(JSON.stringify(director.get_chronicle(0)))
	texts.append(JSON.stringify(director.save()))
	texts.append(JSON.stringify(root.get_node("WorldEvents").canonical_events))
	texts.append(JSON.stringify(fake.get_events()))
	var real_pe = root.get_node_or_null("PlayerEvents")
	if real_pe and real_pe.has_method("get_heard_block"):
		for key in director.get_soul_keys():
			texts.append(real_pe.get_heard_block(director._npc_id(key)))
	var generics = director.get_generics()
	if generics and generics.has_method("get_prompt_block"):
		for id in generics.get_ids().slice(0, 5):
			texts.append(generics.get_prompt_block(id))
	var leaked = texts.filter(func(t): return SECRET in str(t) or str(thought.text) in str(t))
	_check("No prompt, memory, gossip, agenda, chronicle or canon text carries it (%d texts scanned)" % texts.size(), leaked.is_empty() and texts.size() > 20)
	builder.free()
	director.unregister_soul(GENERIC)
	voice.clear()

func _test_console():
	print("Debug commands")
	_fresh_world()
	world_state.set_world_flag("hc_varn_dead", true)
	var console = load("res://scenes/ui/debug_console.tscn").instantiate()
	root.add_child(console)
	console._on_command_submitted("calendar")
	console._on_command_submitted("think I will save Elena")
	console._on_command_submitted("intentions")
	console._on_command_submitted("emergence all")
	console._on_command_submitted("shift tn_collection_night -1 The Hollow came early")
	console._on_command_submitted("epilogue_text")
	_check("think, intentions, emergence, shift and the shifted calendar run", voice.get_history().size() == 1 and _point_minute() == _base() + DAY)
	console.queue_free()
	voice.clear()

# =============================================================================

## Feelings toward the player for every soul: zero unless given (the real ledger stays out of it)
func _dims(given: Dictionary) -> void:
	var dims: Dictionary = {}
	for key in director.get_soul_keys():
		dims[key] = {}
	for key in given:
		dims[key] = given[key]
	director.relationship_dims_override = dims

func _storyline_flag_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for flag in director.get_storyline("fx_story").flags:
		out[flag] = world_state.get_world_flag(flag)
	return out

## Fixture content, a new game's clock and calendar, empty flags, no instances
func _fresh_world() -> void:
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.load_calendar()
	world_state.reset_calendar(world_state.start_minute)
	if director.storyline_dir != FIX_STORYLINES:
		director.load_content(FIX_STORYLINES, FIX_SOULS)
		director.load_emergence(FIX_TEMPLATES)
	director.reset_state()
	director.get_emergence().reset()
	_dims({})
	fake.events.clear()
	fake.order.clear()
	fake.spreads.clear()
	fired_log.clear()

func _restore() -> void:
	director.relationship_dims_override = {}
	director.reputation_override = Callable()
	director.player_location_override = ""
	director.end_on_season_end = true
	director.set_player_events(null)
	director.emergence_dir = director.DEFAULT_EMERGENCE_DIR
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	var real_pe = root.get_node_or_null("PlayerEvents")
	if real_pe and real_pe_capture != null:
		real_pe.capture_enabled = real_pe_capture
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
