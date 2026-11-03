extends SceneTree

# Tests StorylineDirector: beats, triggers, story clock, souls, permissions, drift, effects, chronicle,
# save/load, offline determinism and Claude-mode validation/fallback, plus EventPropagator's witness
# source and memory dedup. Fixtures and fakes only (no API, nothing written to ./chroma); the last
# section paces the REAL content on a fresh WorldState without any NPCs loaded
# Run: godot --headless --path . -s res://scripts/debug/test_storyline_director.gd

const FIXTURE_STORYLINES = "res://scripts/debug/fixtures/storylines"
const FIXTURE_SOULS = "res://scripts/debug/fixtures/souls"
const SID = "fx_story"

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
	var current_location: String = ""
	var relationship_trust: float = 0.0
	var relationship_fear: float = 0.0
	func get_current_location() -> String:
		return current_location
	func apply_relationship_delta(dimension: String, delta: float) -> void:
		set("relationship_" + dimension, get("relationship_" + dimension) + delta)

## Stands in for ClaudeClient: returns a canned reply, optionally after a delay
class FakeClaude extends Node:
	var api_key_override: String = "fake-key-for-tests"
	var reply: String = ""
	var delay: float = 0.0
	var calls: int = 0
	var last_system: String = ""
	var last_user: String = ""
	func send_message(messages: Array, system_prompt: String = "") -> Dictionary:
		calls += 1
		last_system = system_prompt
		last_user = messages[0].content if not messages.is_empty() else ""
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		return {"text": reply}

var director: Node
var world_state: Node
var propagator: Node
var config: Node
var failures: int = 0
var npcs: Array = []
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_api_key: String
var signal_log: Array = []

func _init():
	await process_frame
	await process_frame  # let the Director's deferred startup evaluation finish
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	propagator = root.get_node("EventPropagator")
	config = root.get_node("Config")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_api_key = config.claude_api_key
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)
	director.round_boundaries_enabled = false  # tests drive rounds explicitly with advance_round()
	director.set_round_timer_paused(true)
	director.beat_opened.connect(func(s, b): signal_log.append("opened:%s/%s" % [s, b]))
	director.beat_resolved.connect(func(s, b): signal_log.append("resolved:%s/%s" % [s, b]))
	director.ending_reached.connect(func(s, e): signal_log.append("ending:%s/%s" % [s, e]))
	director.hook_offered.connect(func(s, h, n): signal_log.append("offered:%s/%s" % [h, n]))

	print("============================================================")
	print("🧪 STORYLINE DIRECTOR TEST")
	print("============================================================\n")

	_test_content_loading()
	_test_soul_parsing()
	_test_permission_checks()
	await _test_beat_open_and_resolve()
	await _test_on_flag_trigger()
	await _test_idle_trigger_and_once()
	await _test_first_wins_and_stack()
	await _test_offline_determinism_and_weights()
	await _test_offline_respects_lines_and_agency()
	await _test_block_and_unlock()
	await _test_drift()
	await _test_all_effects()
	await _test_endings()
	await _test_rumor_and_cascade()
	_test_player_choice()
	await _test_chronicle_content()
	await _test_agendas_and_context()
	await _test_save_load_roundtrip()
	await _test_claude_fallback_without_key()
	await _test_claude_validation()
	await _test_claude_timeout()
	await _test_story_clock()
	await _test_round_boundaries()
	await _test_witness_source()
	await _test_memory_dedup_across_sessions()
	await _test_real_content_pacing()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# TESTS
# =============================================================================

func _test_content_loading():
	print("Content loading")
	_check("Fixture storyline loaded (and only it)", director.get_storyline_ids() == [SID])
	_check("Both fixture souls loaded", director.get_soul("mira") != null and director.get_soul("gregor_merchant_001") != null)
	_check("Storyline flag descriptions reach StoryFlags", StoryFlags.get_flag_description("fx_begin") == "A stranger arrived in the fixture village")
	_check("Base flag descriptions still work", StoryFlags.get_flag_description("ledger_found") == StoryFlags.FLAG_DESCRIPTIONS["ledger_found"] and StoryFlags.get_flag_description("ledger_found").begins_with("The player"))
	_check("Declared flags are known to effects", director.is_known_flag("fx_signal") and not director.is_known_flag("fx_nonsense"))

func _test_soul_parsing():
	print("Soul parsing")
	var mira = director.get_soul("mira")
	_check("Name, key and id parsed", mira.display_name == "Mira (fixture)" and mira.npc_key == "mira" and mira.npc_id == "mira_tavern_keeper_001")
	_check("Wants parsed with weights in file order", mira.want_order == ["power", "coin", "safety"] and mira.get_weight("power") == 8 and mira.get_weight("safety") == 3)
	_check("Lines parsed", mira.lines.size() == 2 and mira.lines[1].rule == "ally:gregor")
	_check("Agency parsed", mira.agency.get("intercept", []) == ["set_flag", "agenda", "block_beat"] and mira.agency.has("aid"))
	_check("Drift parsed (two rules on one flag)", mira.drift.size() == 2 and mira.drift[1].want == "power" and mira.drift[1].delta == -2)
	_check("Essence, voice and secrets kept as prose", mira.essence.begins_with("Test fixture soul") and mira.voice != "" and mira.secrets == "She is The Boss.")
	_check("Top wants ordered by weight", mira.get_top_wants(2) == ["power", "coin"])
	var block = mira.get_prompt_block(false)
	_check("Compact prompt block has essence and wants, no secrets", "Test fixture soul" in block and "Keep her hold" in block and not ("The Boss" in block))
	_check("Full prompt block adds lines, voice and secrets", "She is The Boss." in mira.get_prompt_block(true))

func _test_permission_checks():
	print("Permission checks")
	var mira = director.get_soul("mira")
	var gregor = director.get_soul("gregor")
	var agenda = {"type": "agenda", "npc": "mira", "text": "x"}
	_check("Agency grants listed effect", mira.permits("intercept", agenda))
	_check("Agency: effect not granted at this hook type", not mira.permits("react", agenda))
	_check("Agency: no line for hook type always refuses", not gregor.permits("reveal", agenda) and not gregor.engages("reveal"))
	_check("effect: line forbids the effect entirely", not gregor.permits("scheme", {"type": "spread_rumor", "flag": "fx_secret", "to": ["*"]}))
	_check("effect:x:flag forbids only that flag", not mira.permits("intercept", {"type": "set_flag", "flag": "fx_mira_exposed", "value": true})
		and mira.permits("intercept", {"type": "set_flag", "flag": "fx_choice_power", "value": true}))
	_check("hook: line refuses that hook type despite Agency", not gregor.engages("betray") and not gregor.permits("betray", {"type": "set_flag", "flag": "fx_choice_coin", "value": true}))
	_check("ally: refuses options that aid that NPC", mira.get_option_denial_reason({"id": "o", "aids": "gregor"}) != "" and mira.get_option_denial_reason({"id": "o", "aids": "elena"}) == "")
	_check("harm: refuses options whose harms names that NPC", "harm:elena" in gregor.get_option_denial_reason({"id": "o", "harms": ["elena"]})
		and gregor.get_option_denial_reason({"id": "o", "harms": ["varn"]}) == "")
	_check("harm: does nothing else (no flag-name guessing)", gregor.permits("scheme", {"type": "set_flag", "flag": "elena_shown_proof", "value": true})
		and gregor.permits("scheme", {"type": "set_flag", "flag": "fx_gregor", "value": true}))
	_check("Denial reasons name the rule", "effect:spread_rumor" in gregor.get_denial_reason("scheme", {"type": "spread_rumor", "flag": "fx_secret"}))

func _test_beat_open_and_resolve():
	print("Beat open / resolve, on_open and on_resolve triggers")
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	_check("Beat starts locked", director.get_beat_status(SID, "arrival") == "locked")
	await _set_flag("fx_begin")
	_check("Beat opens when requires hold", director.get_beat_status(SID, "arrival") == "open")
	_check("beat_opened signal emitted", "opened:%s/arrival" % SID in signal_log)
	_check("on_open hook fired (greet chronicled)", _entries("greet").size() == 1)
	_check("Unknown beat has empty status", director.get_beat_status(SID, "nope") == "")
	var beats = director.get_beats(SID)
	_check("Optional act is read (2 on arrival, 0 when absent)", beats[0].act == 2 and beats[1].act == 0)
	await _set_flag("fx_done")
	_check("Beat resolves on resolves_on", director.get_beat_status(SID, "arrival") == "resolved")
	_check("beat_resolved signal emitted", "resolved:%s/arrival" % SID in signal_log)
	_check("on_resolve effects applied (fx_after set)", world_state.get_world_flag("fx_after"))
	_check("Cascade opened the next beat", director.get_beat_status(SID, "choice") == "open")
	_check("on_resolve hook fired (gregor moved)", _entries("aftermath").size() == 1 and gregor.current_location == "old_mill")
	var elena_agendas = director.get_agendas("elena")
	_check("An NPC may set an agenda for another NPC", elena_agendas.size() == 1 and elena_agendas[0].from == "gregor" and director.get_agendas("gregor").is_empty())
	var last_word = _entries("last_word")
	var aftermath = _entries("aftermath")
	_check("One flag both firing on_flag and resolving: on_flag hooks first, then on_resolve hooks",
		last_word.size() == 1 and aftermath.size() == 1 and last_word[0].seq < aftermath[0].seq)
	_check("Flags set by hooks are processed after the current change (choice opened later)",
		_entries("weigh").size() == 1 and _entries("weigh")[0].seq > aftermath[0].seq)

func _test_on_flag_trigger():
	print("on_flag trigger")
	_reset()
	await _set_flag("fx_begin")
	_check("on_flag does not fire while its flag is false", _entries("lantern").is_empty())
	await _set_flag("fx_signal")
	_check("on_flag fires when the flag turns true while the beat is open", _entries("lantern").size() == 1)
	_check("Its effect applied", world_state.get_world_flag("fx_choice_power"))
	_reset()
	await _set_flag("fx_signal")
	await _set_flag("fx_begin")
	var lantern = _entries("lantern")
	var greet = _entries("greet")
	_check("on_flag whose flag is already true fires when the beat opens", lantern.size() == 1)
	_check("...right after the on_open hooks", lantern.size() == 1 and greet.size() == 1 and lantern[0].seq > greet[0].seq and lantern[0].trigger == "on_flag:fx_signal")
	world_state.world_flags.erase("fx_signal")
	await _set_flag("fx_signal")
	_check("...and once still holds afterwards", _entries("lantern").size() == 1)

func _test_idle_trigger_and_once():
	print("idle trigger, once")
	_reset()
	await director.advance_round()
	_check("Idle hooks need an open beat", _entries("brood").is_empty())
	world_state.set_world_flag("fx_begin", true)
	director.decisions_per_round_per_storyline = 99
	await director.advance_round()
	await director.advance_round()
	director.decisions_per_round_per_storyline = 1
	_check("once: false idle hook acts every round", _entries("brood").size() == 2)
	_check("once (default) on_open hook is not re-offered", _entries("greet").size() == 1)
	world_state.world_flags.erase("fx_signal")
	await _set_flag("fx_signal")
	world_state.world_flags.erase("fx_signal")
	await _set_flag("fx_signal")
	_check("once on_flag hook acts only once", _entries("lantern").size() == 1)

func _test_first_wins_and_stack():
	print("Competing NPCs: first wins, stack")
	_reset()
	await _set_flag("fx_begin")
	var greet = _entries("greet")
	_check("First eligible NPC to act wins", greet.size() == 1 and greet[0].npc == "mira" and greet[0].choice == "plot")
	_check("Second NPC was never offered the hook", not ("offered:greet/gregor" in signal_log))
	var rally = _entries("rally")
	_check("stack: true lets every eligible NPC act", rally.size() == 2 and rally[0].npc == "mira" and rally[1].npc == "gregor")

func _test_offline_determinism_and_weights():
	print("Offline choice: determinism and want weights")
	_reset()
	var choices = []
	for i in 3:
		var entries = await director.fire_hook(SID, "weigh")
		choices.append(entries[0].choice if not entries.is_empty() else "")
	_check("Same state, same choice, every time", choices == ["for_power", "for_power", "for_power"])
	_check("Ties go to the earlier option (power 8 vs coin 5 + safety 3)", choices[0] == "for_power")
	director.shift_want("mira", "coin", 3)
	var entries = await director.fire_hook(SID, "weigh")
	_check("Raising a want's weight changes the choice", not entries.is_empty() and entries[0].choice == "for_coin")
	_check("Reason cites the served wants and weight", not entries.is_empty() and "coin, safety (weight 11)" in entries[0].reason)

func _test_offline_respects_lines_and_agency():
	print("Offline choice respects lines and agency")
	_reset()
	var mira_entries = await director.fire_hook(SID, "weigh")
	_check("Higher-weight options forbidden by lines are skipped (expose_self, help_gregor)",
		not mira_entries.is_empty() and mira_entries[0].choice == "for_power")
	await _set_flag("fx_gregor")
	_check("No Agency for hook type: pass", _entries("gregor_reveal").size() == 1 and _entries("gregor_reveal")[0].choice == "pass")
	_check("hook: line: pass", _entries("gregor_betray")[0].choice == "pass" if not _entries("gregor_betray").is_empty() else false)
	var rumor = _entries("gregor_rumor")
	_check("effect: line and harms-tagged option steer to the permitted option", not rumor.is_empty() and rumor[0].choice == "quiet")
	_check("...without touching the harmed NPC", not world_state.get_world_flag("elena_shown_proof"))
	_check("Pass decisions do not count as acting", director.get_hooks(SID).filter(func(h): return h.id == "gregor_reveal")[0].acted == 0)

func _test_block_and_unlock():
	print("block_beat / unlock_beat")
	_reset()
	await _set_flag("fx_secret")
	_check("on_open intercept blocked its own beat", director.get_beat_status(SID, "meeting") == "blocked")
	_check("on_open hooks after the block do not fire", _entries("late_open").is_empty())
	await _set_flag("fx_met")
	_check("Blocked beat does not resolve", director.get_beat_status(SID, "meeting") == "blocked")
	await _set_flag("fx_signal")
	_check("Blocked beat's other hooks do not fire", _entries("mill_gossip").is_empty() and not world_state.get_world_flag("fx_choice_coin"))
	_check("A hook that can unlock the beat still fires", _entries("free_it").size() == 1 and _entries("free_it")[0].choice == "open")
	_check("...and its unlock lets the beat resolve", director.get_beat_status(SID, "meeting") == "resolved")
	_reset()
	await _set_flag("fx_secret")
	await _set_flag("fx_met")
	var result = director.apply_effect({"type": "unlock_beat", "storyline": SID, "beat": "meeting"})
	_check("unlock_beat applies", result.ok)
	await process_frame
	_check("Unlocked beat resolves on flags already true", director.get_beat_status(SID, "meeting") == "resolved")
	_check("Unknown beat is rejected", not director.apply_effect({"type": "block_beat", "storyline": SID, "beat": "nope"}).ok)
	_reset()
	director.apply_effect({"type": "block_beat", "storyline": SID, "beat": "arrival"})
	await _set_flag("fx_begin")
	_check("Blocked beat cannot open", director.get_beat_status(SID, "arrival") == "blocked" and _entries("greet").is_empty())
	director.apply_effect({"type": "unlock_beat", "storyline": SID, "beat": "arrival"})
	await _drain()
	_check("Unlocked beat opens and fires on_open", director.get_beat_status(SID, "arrival") == "open" and _entries("greet").size() == 1)

func _test_drift():
	print("Drift")
	_reset()
	var mira = director.get_soul("mira")
	await _set_flag("fx_drift")
	_check("Drift raises a want", mira.get_weight("safety") == 7)
	_check("Drift lowers a want", mira.get_weight("power") == 6)
	_check("Drift applies to every soul with a rule", director.get_soul("gregor").get_weight("coin") == 5)
	world_state.world_flags.erase("fx_drift")
	await _set_flag("fx_drift")
	_check("Drift applies once per flag", mira.get_weight("safety") == 7)
	director.shift_want("mira", "safety", 3)
	director.shift_want("mira", "safety", 3)
	_check("Weights clamp at 10", mira.get_weight("safety") == 10)
	_check("Drift does not rewrite the authored weight", mira.wants.safety.weight == 3)

func _test_all_effects():
	print("Effect vocabulary")
	_reset()
	var mira = _spawn("mira_tavern_keeper_001", "thornhaven_tavern")
	var r: Dictionary

	r = director.apply_effect({"type": "set_flag", "flag": "fx_choice_coin", "value": true})
	_check("set_flag sets the WorldState flag", r.ok and world_state.get_world_flag("fx_choice_coin"))
	_check("set_flag rejects unknown flags", not director.apply_effect({"type": "set_flag", "flag": "made_up_flag", "value": true}).ok)

	r = director.apply_effect({"type": "adjust_relationship", "npc": "mira", "dimension": "trust", "delta": 50})
	_check("adjust_relationship reaches a loaded NPC, clamped to 20", r.ok and mira.relationship_trust == 20.0)
	director.apply_effect({"type": "adjust_relationship", "npc": "bjorn", "dimension": "fear", "delta": -5})
	director.apply_effect({"type": "adjust_relationship", "npc": "bjorn", "dimension": "fear", "delta": -5})
	_check("adjust_relationship queues for an unloaded NPC", director.get_pending_relationships("bjorn").get("fear", 0) == -10)
	var bjorn = _spawn("bjorn_blacksmith_001", "thornhaven_blacksmith")
	director.deliver_pending(bjorn)
	_check("Queued feelings arrive on initialize", bjorn.relationship_fear == -10.0 and director.get_pending_relationships("bjorn").is_empty())
	_check("adjust_relationship rejects bad dimensions", not director.apply_effect({"type": "adjust_relationship", "npc": "mira", "dimension": "lust", "delta": 1}).ok)

	await _set_flag("fx_secret")
	r = director.apply_effect({"type": "spread_rumor", "flag": "fx_secret", "to": ["mira", "elena"], "via": "a whisper at the bar"})
	var text = str(mira.rag_memory.stored.back().get("text", "")) if not mira.rag_memory.stored.is_empty() else ""
	_check("spread_rumor delivers the canonical storyline text via EventPropagator", r.ok and text == "I heard through a whisper at the bar: A secret meeting at the old mill was arranged")
	_check("spread_rumor queues for unloaded NPCs", propagator.get_pending_count("elena") == 1)
	_check("spread_rumor refuses a flag that is not true", not director.apply_effect({"type": "spread_rumor", "flag": "fx_end_b", "to": ["*"]}).ok)

	var long_text = "x".repeat(300)
	r = director.apply_effect({"type": "agenda", "npc": "aldric", "text": long_text})
	var agendas = director.get_agendas("aldric")
	_check("agenda stored per NPC, trimmed to 160 chars", r.ok and agendas.size() == 1 and agendas[0].text.length() == 160)

	r = director.apply_effect({"type": "move_npc", "npc": "mira", "location": "council_hall"})
	_check("move_npc moves a live NPC", r.ok and mira.current_location == "council_hall")
	_check("move_npc records WorldState npc_states", world_state.npc_states.get("mira_tavern_keeper_001", {}).get("location") == "council_hall")
	_check("move_npc keeps existing npc state", world_state.is_npc_alive("mira_tavern_keeper_001"))
	_check("move_npc rejects unknown locations", not director.apply_effect({"type": "move_npc", "npc": "mira", "location": "the_moon"}).ok)

	r = director.apply_effect({"type": "block_beat", "storyline": SID, "beat": "cornered"})
	_check("block_beat blocks", r.ok and director.get_beat_status(SID, "cornered") == "blocked")
	r = director.apply_effect({"type": "unlock_beat", "storyline": SID, "beat": "cornered"})
	_check("unlock_beat unblocks", r.ok and director.get_beat_status(SID, "cornered") == "locked")

	r = director.apply_effect({"type": "shift_want", "npc": "gregor", "want": "coin", "delta": -9})
	_check("shift_want clamps delta to -3", r.ok and director.get_soul("gregor").get_weight("coin") == 1)
	_check("shift_want rejects unknown wants", not director.apply_effect({"type": "shift_want", "npc": "gregor", "want": "glory", "delta": 1}).ok)
	_check("Unknown effect types are rejected", not director.apply_effect({"type": "summon_dragon"}).ok)

func _test_endings():
	print("Endings")
	_reset()
	await _set_flag("fx_end_a")
	_check("Ending reached when its requires hold", director.get_ending(SID) == "end_a")
	_check("ending_reached signal emitted", "ending:%s/end_a" % SID in signal_log)
	await _set_flag("fx_end_b")
	_check("First ending reached sticks", director.get_ending(SID) == "end_a")
	_reset()
	await _set_flag("fx_end_b")
	await _set_flag("fx_end_a")
	_check("!flag in requires: end_a refused while fx_end_b holds", director.get_ending(SID) == "end_b")
	_check("File order: end_b wins over end_c, which also holds", "ending:%s/end_b" % SID in signal_log and not ("ending:%s/end_c" % SID in signal_log))

func _test_player_choice():
	print("Player choice")
	_reset()
	var r = director.player_choice("fx_begin")
	_check("player_choice sets a declared storyline flag", r.ok and world_state.get_world_flag("fx_begin"))
	var player_entries = director.get_chronicle().filter(func(e): return e.npc == "player")
	var entry = player_entries[0] if player_entries.size() == 1 else {}
	_check("...chronicled with actor player", entry.get("npc") == "player" and entry.get("storyline") == SID and entry.get("applied", [{}])[0].get("flag") == "fx_begin")
	_check("...and drives beats like any flag", director.get_beat_status(SID, "arrival") == "open")
	_check("player_choice refuses base and unknown flags", not director.player_choice("ledger_found").ok and not director.player_choice("fx_nope").ok)
	var before = director.get_chronicle().size()
	director.player_choice("fx_nope")
	_check("Refused choices are not chronicled", director.get_chronicle().size() == before)

func _test_rumor_and_cascade():
	print("Untrue rumors, cascade limit")
	_reset()
	await _set_flag("fx_free")
	var whisper = _entries("whisper")
	var dropped = whisper[0].dropped if not whisper.is_empty() else []
	_check("spread_rumor of a false flag is dropped as 'rumor of untrue flag'", dropped.size() == 1 and str(dropped[0].reason).begins_with("rumor of untrue flag"))
	_check("Nobody heard the falsehood", propagator.get_pending_count() == 0)
	_reset()
	await _set_flag("fx_begin")
	director.cascade_limit = 1
	var overflows = director.cascade_overflows
	world_state.set_world_flag("fx_done", true)
	director.cascade_limit = director.MAX_CASCADE
	_check("Cascade beyond the limit stops and is counted", director.cascade_overflows == overflows + 1)
	_check("Queued changes past the limit are dropped", director._flag_queue.is_empty())
	await _set_flag("fx_drift")
	_check("The next change processes normally", director.cascade_overflows == overflows + 1 and director.get_soul("mira").get_weight("safety") == 7)
	_check("Default cascade limit is 32", director.MAX_CASCADE == 32)

func _test_chronicle_content():
	print("Chronicle")
	_reset()
	var world_events = root.get_node("WorldEvents")
	var events_before = world_events.canonical_events.size()
	var actions = []
	director.npc_acted.connect(func(e): actions.append(e), CONNECT_ONE_SHOT)
	await _set_flag("fx_gregor")
	var rumor = _entries("gregor_rumor")
	var entry = rumor[0] if not rumor.is_empty() else {}
	_check("Entry records who, hook, trigger, option and mode", entry.get("npc") == "gregor" and entry.get("hook") == "gregor_rumor"
		and entry.get("trigger") == "on_open" and entry.get("choice") == "quiet" and entry.get("mode") == "offline" and entry.get("label") == "Talk prices")
	_check("Entry records applied effects", entry.get("applied", []).size() == 1 and entry.applied[0].type == "agenda")
	_check("Passes are chronicled too", _entries("gregor_reveal").size() == 1)
	_check("Every decision registered with WorldEvents", world_events.canonical_events.size() - events_before >= 3)
	_check("npc_acted fires for acts", actions.size() == 1)
	# Dropped effects come with reasons (an NPC acting outside its soul)
	director.set_agent_client(_fake_claude('{"choice": "freeform", "effects": [{"type": "set_flag", "flag": "fx_mira_exposed", "value": true}], "reason": "test"}'))
	director.set_agency_mode("claude")
	var entries = await director.fire_hook(SID, "weigh")
	director.set_agency_mode("offline")
	var dropped = entries[0].dropped if not entries.is_empty() else []
	_check("Dropped effects are chronicled with the rule that dropped them", dropped.size() == 1 and "effect:set_flag:fx_mira_exposed" in dropped[0].reason)
	_check("get_chronicle(n) returns the last n", director.get_chronicle(1).size() == 1 and director.get_chronicle(1)[0].hook == "weigh")

func _test_agendas_and_context():
	print("Agendas and ContextBuilder")
	_reset()
	await _set_flag("fx_begin")
	var agendas = director.get_agendas("mira")
	_check("Hook agenda stored for Mira", agendas.size() == 1 and agendas[0].status == "pending" and agendas[0].storyline == SID)
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var context = builder.build_context({"system_prompt": "You are Mira.", "npc_id": "mira_tavern_keeper_001", "player_input": "hello"})
	var prompt: String = context.system_prompt
	_check("System prompt carries the SOUL block", "YOUR SOUL" in prompt and "Keep her hold on Thornhaven" in prompt)
	_check("System prompt carries the pending agenda", "Ask the stranger where they came from." in prompt)
	_check("Building a prompt alone does not consume the agenda", director.get_agendas("mira")[0].status == "pending")
	director.mark_agendas_raised("mira_tavern_keeper_001")
	_check("Raised agenda stays in the prompt during the conversation", "Ask the stranger" in builder.build_context({"system_prompt": "x", "npc_id": "mira_tavern_keeper_001"}).system_prompt)
	_check("Conversation end marks raised agendas done", director.complete_raised_agendas("mira_tavern_keeper_001") == 1 and director.get_agendas("mira").is_empty())
	_check("Done agenda leaves the prompt", not ("Ask the stranger" in builder.build_context({"system_prompt": "x", "npc_id": "mira_tavern_keeper_001"}).system_prompt))
	_check("NPCs without a soul get no storyline block", not ("YOUR SOUL" in builder.build_context({"system_prompt": "x", "npc_id": "bjorn_blacksmith_001"}).system_prompt))
	builder.free()

func _test_save_load_roundtrip():
	print("Save / load")
	_reset()
	await _set_flag("fx_begin")
	await _set_flag("fx_secret")
	await _set_flag("fx_drift")
	director.apply_effect({"type": "adjust_relationship", "npc": "varn", "dimension": "trust", "delta": 7})
	world_state.set_world_flag("fx_gregor", true)  # undecided: its hooks wait in the queue
	var queue_size = director.get_decision_queue().size()
	var round_number = director.get_round()
	var chronicle_size = director.get_chronicle().size()
	var saved = JSON.parse_string(JSON.stringify(director.save()))
	director.reset_state()
	_check("Reset clears state", director.get_beat_status(SID, "arrival") == "locked" and director.get_chronicle().is_empty() and director.get_soul("mira").get_weight("safety") == 3)
	director.load_from_dict(saved)
	_check("Beat states survive a JSON save", director.get_beat_status(SID, "arrival") == "open" and director.get_beat_status(SID, "meeting") == "blocked")
	_check("Want weights survive", director.get_soul("mira").get_weight("safety") == 7 and director.get_soul("mira").get_weight("power") == 6)
	_check("Agendas survive", director.get_agendas("mira").size() == 2)
	_check("Pending relationships survive as ints", director.get_pending_relationships("varn").get("trust") == 7)
	_check("Chronicle survives", director.get_chronicle().size() == chronicle_size)
	_check("Decision queue and round counter survive", queue_size == 3 and director.get_decision_queue().size() == queue_size and director.get_round() == round_number and round_number > 0)
	await director.evaluate_all()
	_check("Fired once-hooks stay fired after load", _entries("greet").size() == 1)
	_check("Applied drift is not re-applied after load", director.get_soul("mira").get_weight("safety") == 7)
	_check("WorldState save includes storyline state", world_state.save().get("storylines", {}).get("opened", []).size() == 3)
	director.reset_state()
	world_state._apply_storyline_state({"storylines": saved})
	_check("WorldState load hands state to the Director", director.get_beat_status(SID, "meeting") == "blocked")

func _test_claude_fallback_without_key():
	print("Claude mode: fallback without an API key")
	_reset()
	config.claude_api_key = ""
	director.set_agent_client(null)  # the Director makes a real ClaudeClient, which must never be called
	director.set_agency_mode("claude")
	var entries = await director.fire_hook(SID, "weigh")
	director.set_agency_mode("offline")
	config.claude_api_key = saved_api_key
	var entry = entries[0] if not entries.is_empty() else {}
	_check("Falls back to the offline choice", entry.get("choice") == "for_power")
	_check("Chronicle marks the fallback and why", entry.get("mode") == "claude_fallback" and entry.get("fallback_reason") == "no API key")
	_check("Fallback effects applied", world_state.get_world_flag("fx_choice_power"))
	_check("set_agency_mode rejects unknown modes", not director.set_agency_mode("psychic") and director.agency_mode == "offline")

func _test_claude_validation():
	print("Claude mode: validation")
	_reset()
	director.set_agency_mode("claude")

	var fake = _fake_claude('{"choice": "for_coin", "effects": [{"type": "set_flag", "flag": "fx_end_b", "value": true}], "reason": "Coin first."}')
	var entries = await director.fire_hook(SID, "weigh")
	var entry = entries[0] if not entries.is_empty() else {}
	_check("Claude's option choice is used", entry.get("choice") == "for_coin" and entry.get("mode") == "claude" and entry.get("reason") == "Coin first.")
	_check("Option effects come from the authored option, not the model", world_state.get_world_flag("fx_choice_coin") and not world_state.get_world_flag("fx_end_b"))
	_check("Prompt carries the soul, situation and numbered options", "YOUR SOUL" in fake.last_system and "too many questions" in fake.last_user and "2. id \"for_coin\"" in fake.last_user)
	_check("Prompt offers freeform with only permitted types", "freeform" in fake.last_user and '"type": "agenda"' in fake.last_user and not ('"type": "move_npc"' in fake.last_user))

	_fake_claude('```json\n{"choice": "freeform", "effects": [{"type": "agenda", "npc": "mira", "text": "Find out who sent the stranger."}, {"type": "set_flag", "flag": "fx_mira_exposed", "value": true}, {"type": "move_npc", "npc": "mira", "location": "old_mill"}, {"type": "teleport"}], "reason": "My own way."}\n```')
	entries = await director.fire_hook(SID, "weigh")
	entry = entries[0] if not entries.is_empty() else {}
	var reasons = entry.get("dropped", []).map(func(d): return d.reason)
	_check("Freeform: permitted effect applied", entry.get("applied", []).size() == 1 and director.get_agendas("mira").size() == 1)
	_check("Freeform: line-forbidden effect dropped", reasons.any(func(r): return "fx_mira_exposed" in r) and not world_state.get_world_flag("fx_mira_exposed"))
	_check("Freeform: type outside freeform_effects dropped", reasons.any(func(r): return "freeform_effects" in r))
	_check("Freeform: unknown effect type dropped", reasons.any(func(r): return "unknown effect type" in r))

	_fake_claude('{"choice": "freeform", "effects": [{"type": "agenda", "npc": "gregor", "text": "x"}]}')
	entries = await director.fire_hook(SID, "greet", "mira")
	_check("Freeform where the hook does not allow it falls back", not entries.is_empty() and entries[0].mode == "claude_fallback" and "not allowed" in entries[0].fallback_reason)

	for bad in ["I would rather not say.", '{"choice": "burn_it_all"}', '{"choice": 3}']:
		_fake_claude(bad)
		entries = await director.fire_hook(SID, "weigh")
		_check("Invalid reply falls back to offline: %s" % bad, not entries.is_empty() and entries[0].mode == "claude_fallback" and entries[0].choice == "for_power")

	_fake_claude('{"choice": "pass", "reason": "Not my problem."}')
	entries = await director.fire_hook(SID, "weigh")
	_check("Claude may pass", not entries.is_empty() and entries[0].choice == "pass" and entries[0].mode == "claude")

	var calls_before = fake.calls
	await director.fire_hook(SID, "gregor_reveal")
	_check("No API call when the soul cannot act at the hook", fake.calls == calls_before)
	director.set_agency_mode("offline")

func _test_claude_timeout():
	print("Claude mode: timeout")
	_reset()
	var fake = _fake_claude('{"choice": "for_coin"}')
	fake.delay = 0.8
	director.set_agent_timeout(0.1)
	director.set_agency_mode("claude")
	var started = Time.get_ticks_msec()
	var entries = await director.fire_hook(SID, "weigh")
	var elapsed = Time.get_ticks_msec() - started
	director.set_agency_mode("offline")
	director.set_agent_timeout(20.0)
	_check("Timed-out request falls back to offline", not entries.is_empty() and entries[0].choice == "for_power" and "timeout" in entries[0].fallback_reason)
	_check("Fallback did not wait for the slow reply", elapsed < 600)
	await create_timer(1.0).timeout  # let the abandoned slow reply land, so nothing leaks at exit
	_check("A late reply after the timeout changes nothing", director.get_chronicle().size() == 1)

func _test_story_clock():
	print("Story clock: decision queue and rounds")
	_reset()
	world_state.set_world_flag("fx_begin", true)
	var queue = director.get_decision_queue().map(func(q): return q.hook)
	_check("Triggered hooks queue instead of deciding", director.get_beat_status(SID, "arrival") == "open" and director.get_chronicle().is_empty() and queue == ["greet", "rally"])
	var entries = await director.advance_round()
	_check("A round decides one queued hook per storyline, oldest first", entries.size() == 1 and entries[0].hook == "greet" and entries[0].round == 1)
	_check("The rest waits (plus this round's idle hook)", director.get_decision_queue().map(func(q): return q.hook) == ["rally", "brood"])
	world_state.world_flags.erase("fx_signal")
	world_state.set_world_flag("fx_signal", true)
	world_state.world_flags.erase("fx_signal")
	world_state.set_world_flag("fx_signal", true)
	_check("Queue is deduplicated by storyline + hook", director.get_decision_queue().filter(func(q): return q.hook == "lantern").size() == 1)
	director.decisions_per_round_per_storyline = 2
	entries = await director.advance_round()
	_check("decisions_per_round_per_storyline is honoured", entries.map(func(e): return e.hook) == ["rally", "rally", "brood"].slice(0, entries.size()) and _distinct_hooks(entries) == 2)
	director.decisions_per_round_per_storyline = 1
	_reset()
	await _set_flag("fx_begin")
	world_state.set_world_flag("fx_done", true)
	_check("A player flag resolves its beat at once", director.get_beat_status(SID, "arrival") == "resolved")
	_check("...while NPC reactions wait for rounds", _entries("aftermath").is_empty() and _entries("last_word").is_empty())
	await director.advance_round()  # the idle brood queued earlier is older, so it goes first
	await director.advance_round()
	_check("Queued reactions take their turn, one per round, in queue order",
		_entries("last_word").size() == 1 and _entries("aftermath").is_empty() and _entries("weigh").is_empty())
	var weigh_entries = await director.fire_hook(SID, "weigh")
	_check("fire_hook stays immediate", weigh_entries.size() == 1)

func _test_round_boundaries():
	print("Story clock: round boundaries")
	_reset()
	director.round_boundaries_enabled = true
	var start = director.get_round()
	world_state.set_world_flag("fx_begin", true)
	_check("A boundary runs at the end of the frame, not mid-change", director.get_round() == start)
	await process_frame
	await process_frame
	_check("A player-caused flag change is a round boundary", director.get_round() == start + 1 and _entries("greet").size() == 1)
	start = director.get_round()
	director.apply_effect({"type": "set_flag", "flag": "fx_choice_coin", "value": true})
	await process_frame
	await process_frame
	_check("A Director effect's flag change is not", director.get_round() == start)
	director.player_choice("fx_end_a")
	director.request_round("conversation_ended")
	root.get_node("SceneManager").scene_transition_completed.emit("thornhaven_tavern")
	await process_frame
	await process_frame
	_check("player_choice, conversation end and scene change in one frame make one round", director.get_round() == start + 1)
	start = director.get_round()
	director.set_round_seconds(1.0)
	director.set_round_timer_paused(false)
	await create_timer(1.3).timeout
	_check("Idle fallback timer runs a round", director.get_round() == start + 1)
	director.set_round_timer_paused(true)
	start = director.get_round()
	await create_timer(1.3).timeout
	_check("Paused timer runs none", director.get_round() == start)
	director.set_round_seconds(director.DEFAULT_ROUND_SECONDS)
	director.set_round_timer_paused(true)
	director.round_boundaries_enabled = false
	_check("STORY_ROUND_SECONDS defaults to 300", config.story_round_seconds == 300.0)

func _test_witness_source():
	print("EventPropagator: only the player is witnessed")
	_reset()
	var elena = _spawn("elena_daughter_001", "")
	world_state.world_flags.erase("elena_shown_proof")
	director.apply_effect({"type": "set_flag", "flag": "elena_shown_proof", "value": true})
	_check("Director-set flag: no false 'I witnessed' memory", elena.rag_memory.stored.is_empty())
	world_state.world_flags.erase("elena_shown_proof")
	world_state.set_world_flag("elena_shown_proof", true)
	await process_frame
	var text = str(elena.rag_memory.stored[0].get("text", "")) if elena.rag_memory.stored.size() == 1 else ""
	_check("Player-caused flag: witnessed as before", text.begins_with("I witnessed:"))
	world_state.world_flags.erase("elena_shown_proof")

func _test_memory_dedup_across_sessions():
	print("EventPropagator: no duplicate memories across sessions (in-memory RAGMemory)")
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	gregor.rag_memory.free()
	var rag = load("res://scripts/npcs/rag_memory.gd").new()
	gregor.add_child(rag)
	await rag.initialize("dedup_test_gregor", null, false)  # in-memory: nothing reaches ./chroma
	gregor.rag_memory = rag
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	_check("First session stores the memory", rag.memory_cache.size() == 1)
	var metadata: Dictionary = rag.memory_cache[0].metadata if not rag.memory_cache.is_empty() else {}
	_check("Metadata carries source_flag and how", metadata.get("source_flag") == "ledger_found" and metadata.get("how") == "witnessed")
	_check("has_memory_with matches on metadata", await rag.has_memory_with({"source_flag": "ledger_found", "event_type": "witnessed_event"})
		and not await rag.has_memory_with({"source_flag": "ledger_found", "event_type": "heard_news"}))
	propagator.load_from_dict({})  # a new session: the save-file dedup set is gone, the DB is not
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	_check("New session does not store it again", rag.memory_cache.size() == 1)
	_check("...and remembers it delivered", propagator.has_delivered(gregor.npc_id, "ledger_found"))

func _test_real_content_pacing():
	print("Real content: the world drifts, it does not play itself")
	var real_flags = world_state.world_flags
	world_state.world_flags = {}
	world_state.npc_states = {}
	director.load_content("res://resources/storylines", "res://souls")
	director.evaluate_all()
	var ids = director.get_storyline_ids()
	_check("Real storylines and souls load", ids.size() >= 1 and director.get_soul_keys().size() >= 1)
	_check("Boot + 0 rounds: no NPC decisions at all", director.get_chronicle().is_empty())
	_check("...but hooks are waiting", not director.get_decision_queue().is_empty())
	var entries = await director.advance_round("test")
	var worst = 0
	for sid in ids:
		worst = max(worst, _distinct_hooks(entries.filter(func(e): return e.storyline == sid)))
	_check("After 1 round each storyline made at most 1 decision", worst <= 1)
	print("    round 1: %d decision(s) across %d storylines, %d queued" % [_distinct_hooks(entries), ids.size(), director.get_decision_queue().size()])
	world_state.world_flags = real_flags
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)

# =============================================================================
# HELPERS
# =============================================================================

func _fake_claude(reply: String) -> FakeClaude:
	var fake: FakeClaude = null
	for child in root.get_children():
		if child is FakeClaude:
			fake = child
	if fake == null:
		fake = FakeClaude.new()
		root.add_child(fake)
	fake.reply = reply
	fake.delay = 0.0
	director.set_agent_client(fake)
	return fake

## Set a flag (as the player would) and run rounds until only idle hooks are left queued
func _set_flag(flag: String) -> void:
	world_state.set_world_flag(flag, true)
	await _drain()

func _drain() -> void:
	for i in 30:
		if director.get_decision_queue().filter(func(q): return q.trigger != "idle").is_empty():
			return
		await director.advance_round("test")

func _distinct_hooks(entries: Array) -> int:
	var seen = {}
	for entry in entries:
		seen["%s/%s" % [entry.storyline, entry.hook]] = true
	return seen.size()

func _entries(hook_id: String) -> Array:
	return director.get_chronicle().filter(func(e): return e.hook == hook_id)

func _spawn(npc_id: String, location: String) -> FakeNPC:
	var npc = FakeNPC.new()
	npc.npc_id = npc_id
	npc.current_location = location
	npc.rag_memory = FakeMemory.new()
	npc.add_child(npc.rag_memory)
	npc.add_to_group("npcs")
	root.add_child(npc)
	npcs.append(npc)
	return npc

func _reset():
	for npc in npcs:
		npc.remove_from_group("npcs")
		npc.queue_free()
	npcs.clear()
	for flag in world_state.world_flags.keys():
		if flag.begins_with("fx_") or flag == "elena_shown_proof":
			world_state.world_flags.erase(flag)
	world_state.npc_states = saved_npc_states.duplicate(true)
	propagator.load_from_dict({})
	director.reset_state()
	director.decisions_per_round_per_storyline = 1
	signal_log.clear()

func _restore():
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	config.claude_api_key = saved_api_key

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
