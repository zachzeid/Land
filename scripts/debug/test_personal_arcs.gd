extends SceneTree

# Tests personal arcs (docs/WORLD_SCHEMA.md §8-9): `## Life` parsing (valid and malformed), soul text
# from strings, step ordering, needs, `at` with real road time, takes, player helps/needed through
# conversation commitments, derived and result flags, fails_if, personal flags readable but never
# settable by storylines or conversation, personal effects blocked from storyline flags (Claude mode
# with a fake client), priority ordering and the per-round cap, register_soul / tiers / unregister,
# and save/load round-trips (including a registered soul re-registered after load).
# Fixtures and fakes only: no API calls, no NPC scenes loaded, nothing written to ./chroma or a save file
# Run: godot --headless --path . -s res://scripts/debug/test_personal_arcs.gd

const Soul = preload("res://scripts/storyline/soul.gd")
const FIXTURE_STORYLINES = "res://scripts/debug/fixtures/life/storylines"
const FIXTURE_SOULS = "res://scripts/debug/fixtures/life/souls"
const FARMER_PATH = "res://scripts/debug/fixtures/life/registered/gen_farmer_1.md"
const FARMER = "gen_farmer_1"

## Stands in for ClaudeClient: returns a canned reply
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
var failures: int = 0
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var steps_done: Array = []
var arcs_ended: Array = []
var farmer_text: String = ""

func _init():
	await process_frame
	await process_frame
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	world_state.set_idle_clock_rate(0.0)  # only the test moves the clock
	world_state.world_flags = {}
	world_state.npc_states = {}
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.personal_step_completed.connect(func(k, a, s): steps_done.append("%s/%s/%s" % [k, a, s]))
	director.personal_arc_ended.connect(func(k, a, o): arcs_ended.append("%s/%s/%s" % [k, a, o]))
	var file = FileAccess.open(FARMER_PATH, FileAccess.READ)
	farmer_text = file.get_as_text()
	file.close()

	print("============================================================")
	print("🧪 PERSONAL ARCS TEST")
	print("============================================================\n")

	_test_parse_valid()
	_test_parse_malformed()
	_test_director_load()
	await _test_steps_travel_takes_and_helps()
	await _test_needs()
	await _test_player_needed()
	await _test_fails_if()
	await _test_personal_flags_read_only()
	await _test_claude_mode_scope()
	await _test_priority_and_cap()
	await _test_registration_and_tiers()
	await _test_save_load()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# PARSING
# =============================================================================

func _test_parse_valid():
	print("Parsing a valid ## Life")
	var soul = Soul.load_from_file(FIXTURE_SOULS + "/bjorn/SOUL.md")
	_check("Bjorn parses with one arc and no errors", soul != null and soul.life_arcs.size() == 1 and soul.life_errors.is_empty())
	var arc = soul.get_arc("true_blade")
	_check("Arc header: id, serves, prose", arc.serves == "honest_steel" and arc.prose.begins_with("One blade"))
	_check("Three steps in file order", arc.steps.map(func(s): return s.id) == ["clean_iron", "the_first_fold", "show_someone"])
	var first = arc.steps[0]
	_check("Step fields: after none, needs with !, at, takes, effects", first.after == "" and first.needs == ["!lf_road_closed"]
		and first.at == "greystone_mines" and first.takes == 2 and first.effects == ["agenda", "move_npc"] and first.player == "")
	_check("after links to the earlier step", arc.steps[1].after == "clean_iron" and arc.steps[1].at == "thornhaven_blacksmith")
	_check("player: helps parsed", arc.steps[2].player == "helps" and arc.steps[2].at == "any")
	_check("Derived step flags <key>_<arc>_<step>", first.flag == "bjorn_true_blade_clean_iron" and arc.steps[2].flag == "bjorn_true_blade_show_someone")
	_check("result and fails_if", arc.result.flag == "bjorn_true_blade_forged" and arc.result.text.begins_with("Bjorn forged") and arc.fails_if == ["lf_forge_burned"])
	_check("Life flags: 3 steps + result, with canon text", soul.get_life_flags().size() == 4 and soul.get_life_flags()["bjorn_true_blade_forged"].begins_with("Bjorn forged"))
	_check("find_step_by_flag accepts help: prefix", soul.find_step_by_flag("help:bjorn_true_blade_show_someone").step.id == "show_someone")
	_check("Fresh life state: active, nothing done", soul.get_arc_status("true_blade") == "active" and not soul.is_step_done("true_blade", "clean_iron"))
	var block = soul.get_conversation_prompt_block()
	_check("Conversation block carries the Life block (active arc + current step)", "YOUR OWN LIFE" in block and "Find ore the Hollow never touched" in block and "Fold the iron" not in block)

	var gregor = Soul.load_from_file(FIXTURE_SOULS + "/gregor/SOUL.md")
	_check("A soul with no ## Life is tolerated", gregor != null and not gregor.has_life() and gregor.life_errors.is_empty() and not "YOUR OWN LIFE" in gregor.get_conversation_prompt_block())

	var text_soul = Soul.from_text(farmer_text, FARMER)
	_check("from_text parses a string; the key overrides the header", text_soul != null and text_soul.npc_key == FARMER and text_soul.life_arcs.size() == 1
		and text_soul.life_arcs[0].result.flag == "gen_farmer_1_cow_bought" and text_soul.npc_id == FARMER)
	_check("from_text without any key gives null", Soul.from_text("## Wants\n- `x` (3): y\n") == null)

func _life_text(life: String, key: String = "tester") -> String:
	return "# SOUL: Tester\nnpc: %s\n\n## Wants\n- `goal` (5): A goal.\n- `other` (3): Another.\n\n## Life\n%s\n" % [key, life]

func _errors_for(life: String) -> Array:
	return Soul.from_text(_life_text(life)).life_errors

func _test_parse_malformed():
	print("Parsing malformed ## Life")
	var head = "### Arc: `a` (serves `goal`)\n"
	var ok_step = "- `s1`: Do it. | after: none | needs: none | at: any | takes: 1 | effects: agenda\n"
	var result = "- result: `tester_a_done`: The tester did it.\n"
	var good = Soul.from_text(_life_text(head + ok_step + result))
	_check("Baseline arc is valid", good.life_arcs.size() == 1 and good.life_errors.is_empty())
	var cases = {
		"set_flag in effects": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: 1 | effects: agenda, set_flag\n" + result,
		"block_beat in effects": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: 1 | effects: block_beat\n" + result,
		"takes out of range": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: 9 | effects: agenda\n" + result,
		"takes not a number": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: two | effects: agenda\n" + result,
		"serves an unknown want": "### Arc: `a` (serves `nothing`)\n" + ok_step + result,
		"result without the key prefix": head + ok_step + "- result: `someone_a_done`: Done.\n",
		"no result": head + ok_step,
		"after an unknown step": head + "- `s1`: Do it. | after: s9 | needs: none | at: any | takes: 1 | effects: agenda\n" + result,
		"after a later step": head + "- `s1`: Do it. | after: s2 | needs: none | at: any | takes: 1 | effects: agenda\n- `s2`: Then. | after: none | needs: none | at: any | takes: 1 | effects: agenda\n" + result,
		"missing field": head + "- `s1`: Do it. | after: none | needs: none | takes: 1 | effects: agenda\n" + result,
		"unknown field": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: 1 | effects: agenda | mood: grim\n" + result,
		"bad player value": head + "- `s1`: Do it. | after: none | needs: none | at: any | takes: 1 | effects: agenda | player: maybe\n" + result,
		"duplicate step": head + ok_step + ok_step + result,
		"no steps": head + result,
		"unrecognised bullet": head + ok_step + "- whatever this is\n" + result,
	}
	for label in cases:
		var soul = Soul.from_text(_life_text(cases[label]))
		_check("Rejected whole: %s" % label, soul.life_arcs.is_empty() and not soul.life_errors.is_empty())
	var mixed = Soul.from_text(_life_text(head + ok_step + result + "### Arc: `b` (serves `other`)\n- `s1`: Bad. | after: none | needs: none | at: any | takes: 1 | effects: set_flag\n- result: `tester_b_done`: B.\n"))
	_check("A bad arc does not take the good one with it", mixed.life_arcs.size() == 1 and mixed.life_arcs[0].id == "a" and mixed.life_errors.size() == 1)
	var heading = Soul.from_text(_life_text("### Arc a serves goal\n" + ok_step + result))
	_check("A malformed arc heading is reported and its lines skipped", heading.life_arcs.is_empty() and heading.life_errors.size() == 1)
	var dup = Soul.from_text(_life_text(head + ok_step + result + head + ok_step + "- result: `tester_a_two`: Two.\n"))
	_check("Duplicate arc ids: the second is rejected", dup.life_arcs.size() == 1 and dup.life_errors.size() == 1)
	_check("Stray bullet before any arc is an error", not _errors_for("- `s1`: Orphan. | after: none | needs: none | at: any | takes: 1 | effects: agenda\n").is_empty())

func _test_director_load():
	print("Director loads Life")
	_check("File souls are tier main", director.get_soul_tier("bjorn") == "main" and director.get_soul_tier("gregor") == "main" and director.get_soul_tier("nobody") == "")
	_check("Personal flags are known flags", director.is_known_flag("bjorn_true_blade_forged") and director.is_known_flag("elena_own_way_ask_the_healer")
		and director.is_personal_flag("mira_count_coin_hidden") and not director.is_personal_flag("lf_pledge"))
	_check("Personal flags have canon text", StoryFlags.get_flag_description("bjorn_true_blade_forged").begins_with("Bjorn forged"))
	_check("Gregor (no Life) loads and takes no turns", director.get_soul("gregor") != null and director.get_life("gregor").plan.is_empty())
	_check("world.json tiers.personal_decisions_per_round is the default cap", director.get_personal_decisions_per_round() == int(registry.data.tiers.personal_decisions_per_round))

# =============================================================================
# STEPS
# =============================================================================

func _test_steps_travel_takes_and_helps():
	print("Steps: ordering, at with travel time, takes, player: helps")
	_fresh()
	var road = registry.travel_minutes("thornhaven_blacksmith", "greystone_mines")
	_check("Greystone is a long road from the forge", road > 60)
	var early = director.apply_conversation_actions("bjorn", [], ["help:bjorn_true_blade_show_someone"])
	_check("Help with a step whose `after` is not done is refused", early.applied.is_empty() and "not yet" in early.dropped[0].reason)

	var turn = await _turn_for("bjorn")
	_check("Turn 1: Bjorn sets off for Greystone (not there yet)", turn.get("choice", "") == "travel" and director.is_npc_travelling("bjorn")
		and turn.applied[0].get("minutes", 0) == road and director.get_npc_location("bjorn") == "greystone_mines")
	turn = await _turn_for("bjorn")
	_check("On the road: no personal turn", turn.is_empty())
	world_state.advance_time(road, "test")
	_check("Arrives when the clock has moved the road's minutes", not director.is_npc_travelling("bjorn"))
	turn = await _turn_for("bjorn")
	_check("Works the step: 1 of 2", turn.get("choice", "") == "work" and director.get_soul("bjorn").get_step_progress("true_blade", "clean_iron") == 1)
	turn = await _turn_for("bjorn")
	_check("takes 2: completes on the second working turn", turn.get("choice", "") == "completed_step" and world_state.get_world_flag("bjorn_true_blade_clean_iron"))
	_check("personal_step_completed signal", "bjorn/true_blade/clean_iron" in steps_done)
	_check("Its agenda applied (Bjorn's own; move_npc adds nothing)", turn.applied.size() == 1 and turn.applied[0].type == "agenda" and turn.applied[0].npc == "bjorn"
		and director.get_agendas("bjorn").size() == 1)
	_check("Chronicled with mode personal", turn.mode == "personal" and turn.arc == "true_blade" and turn.step == "clean_iron")

	turn = await _turn_for("bjorn")
	_check("Next step at the forge: travels back", turn.get("choice", "") == "travel" and turn.step == "the_first_fold")
	world_state.advance_time(road, "test")
	for i in 2:
		turn = await _turn_for("bjorn")
	_check("takes 3: still working after 2 turns", turn.get("choice", "") == "work")
	var weight = director.get_soul("bjorn").get_weight("honest_steel")
	turn = await _turn_for("bjorn")
	_check("Completes on the third", turn.get("choice", "") == "completed_step" and world_state.get_world_flag("bjorn_true_blade_the_first_fold"))
	_check("shift_want strengthened the served want (clamped 1-10)", director.get_soul("bjorn").get_weight("honest_steel") == mini(weight + 1, 10))

	# on_flag:<personal flag> hooks fire: storylines READ personal flags. Their set_flag of one is dropped
	director.personal_turns_enabled = false
	_check("A storyline on_flag hook queued off the personal flag", director.get_decision_queue().any(func(q): return q.hook == "bjorn_cheats"))
	var entries = await director.advance_round("test")
	director.personal_turns_enabled = true
	var cheat = entries.filter(func(e): return e.hook == "bjorn_cheats")
	_check("...and its set_flag of a personal flag is dropped, its agenda applies", cheat.size() == 1 and cheat[0].applied.size() == 1
		and cheat[0].dropped.size() == 1 and "personal flag" in cheat[0].dropped[0].reason and not world_state.get_world_flag("bjorn_true_blade_show_someone"))

	var soul = director.get_soul("bjorn")
	_check("show_someone takes 2 before the player helps", soul.get_effective_takes("true_blade", "show_someone") == 2)
	_check("The Life block offers the help commitment", "help:bjorn_true_blade_show_someone" in director.get_conversation_block("bjorn"))
	var talk = director.apply_conversation_actions("bjorn", [], ["help:bjorn_true_blade_show_someone"], {"said": "You'd do that?", "player": "I'll help you show it."})
	_check("The player's promise lands through conversation commitments", talk.applied.size() == 1 and talk.applied[0].type == "personal_help" and soul.is_step_helped("true_blade", "show_someone"))
	_check("...chronicled in the conversation entry", talk.entry.get("mode", "") == "conversation" and talk.entry.applied[0].type == "personal_help")
	_check("player: helps halves takes (2 -> 1)", soul.get_effective_takes("true_blade", "show_someone") == 1)
	var again = director.apply_conversation_actions("bjorn", [], ["bjorn_true_blade_show_someone"])
	_check("A second promise is refused", again.applied.is_empty() and "already promised" in again.dropped[0].reason)
	turn = await _turn_for("bjorn")
	_check("Completes in one turn after the promise: the whole arc", turn.get("choice", "") == "completed_arc"
		and world_state.get_world_flag("bjorn_true_blade_show_someone") and world_state.get_world_flag("bjorn_true_blade_forged"))
	_check("Arc status completed + personal_arc_ended(completed)", soul.get_arc_status("true_blade") == "completed" and "bjorn/true_blade/completed" in arcs_ended)
	var applied_types = turn.applied.map(func(e): return e.type)
	_check("The step's text names Elena: the agenda crosses into her life", turn.applied.any(func(e): return e.type == "agenda" and e.npc == "elena"))
	_check("adjust_relationship (the player helped) reaches Bjorn's feelings", "adjust_relationship" in applied_types and director.get_pending_relationships("bjorn").get("trust", 0) == 5)
	_check("spread_rumor is refused by his line", turn.dropped.size() == 1 and turn.dropped[0].effect.type == "spread_rumor" and "soul:" in turn.dropped[0].reason)
	_check("Storylines read the result flag: a beat requiring it opens", director.get_beat_status("lf_story", "blade_known") == "open")
	_check("A finished Life takes no more turns", (await _turn_for("bjorn")).is_empty())

	director.personal_turns_enabled = false
	await director.advance_round("test")
	director.personal_turns_enabled = true
	_check("Beat resolves; its on_resolve set_flag of a personal flag is dropped", director.get_beat_status("lf_story", "blade_known") == "resolved"
		and world_state.get_world_flag("bjorn_true_blade_clean_iron"))

func _test_needs():
	print("Steps: needs")
	_fresh()
	world_state.set_world_flag("lf_road_closed", true)
	_check("needs !flag false: Bjorn has nothing available", director.get_life("bjorn").plan.is_empty())
	world_state.set_world_flag("lf_road_closed", false)
	_check("...and available again when it clears", director.get_life("bjorn").plan.get("step", "") == "clean_iron")
	var turn = await _turn_for("mira")
	_check("Mira tallies (takes 1)", turn.get("choice", "") == "completed_step" and turn.step == "tally")
	_check("hide_it needs lf_coin_ready: waits", director.get_life("mira").plan.is_empty() and (await _turn_for("mira")).is_empty())
	world_state.set_world_flag("lf_coin_ready", true)
	turn = await _turn_for("mira")
	_check("needs met: hide_it completes the arc", turn.get("choice", "") == "completed_arc" and world_state.get_world_flag("mira_count_coin_hidden"))
	_check("A storyline resolves on the personal result flag", director.get_beat_status("lf_story", "the_week") == "resolved")

func _test_player_needed():
	print("Steps: player: needed")
	_fresh()
	var turn = await _turn_for("elena")
	_check("Works 1 of 2", turn.get("choice", "") == "work")
	turn = await _turn_for("elena")
	_check("All the work she can do alone: waiting for the player", turn.get("choice", "") == "waiting" and not world_state.get_world_flag("elena_own_way_ask_the_healer"))
	_check("While waiting she takes no turns", (await _turn_for("elena")).is_empty())
	_check("The Life block says she needs help", "cannot finish this without the player's help" in director.get_conversation_block("elena"))
	var other = director.apply_conversation_actions("mira", [], ["help:elena_own_way_ask_the_healer"])
	_check("Mira cannot accept help for Elena's life", other.applied.is_empty() and "belongs to elena" in other.dropped[0].reason)
	var result = director.apply_conversation_actions("elena", [], ["help:elena_own_way_chosen"])
	_check("A result flag is not a step to help with", result.applied.is_empty() and "arc result" in result.dropped[0].reason)
	var committed = director.commit_personal_help("elena", "elena_own_way_ask_the_healer")
	_check("commit_personal_help (debug/API path)", committed.ok and director.get_chronicle(1)[0].choice == "help_committed")
	turn = await _turn_for("elena")
	_check("Completes once the player committed (takes unchanged for needed)", turn.get("choice", "") == "completed_arc" and world_state.get_world_flag("elena_own_way_chosen")
		and director.get_soul("elena").get_effective_takes("own_way", "ask_the_healer") == 2)

func _test_fails_if():
	print("fails_if")
	_fresh()
	await _turn_for("elena")
	var weight = director.get_soul("elena").get_weight("choose_my_life")
	world_state.set_world_flag("lf_elena_locked_in", true)  # the world moves on without her
	var soul = director.get_soul("elena")
	_check("The arc is abandoned the moment its fail flag turns true", soul.get_arc_status("own_way") == "failed" and "elena/own_way/failed" in arcs_ended)
	var last = director.get_chronicle(0).filter(func(e): return e.get("mode", "") == "personal" and e.npc == "elena")
	_check("Abandonment is chronicled", not last.is_empty() and last[-1].choice == "abandoned" and "lf_elena_locked_in" in last[-1].reason)
	_check("Abandonment drifts the served want down", soul.get_weight("choose_my_life") == weight - 1)
	_check("No result flag, no more turns, no help", not world_state.get_world_flag("elena_own_way_chosen") and (await _turn_for("elena")).is_empty()
		and "over" in director.get_personal_help_denial("elena", "elena_own_way_ask_the_healer"))
	_fresh()
	world_state.set_world_flag("lf_forge_burned", true)
	director.reset_state()  # a fail flag already true is caught at the start of the next personal phase
	await director.run_personal_turns("test")
	_check("A fail flag already true abandons at the next phase", director.get_soul("bjorn").get_arc_status("true_blade") == "failed")

# =============================================================================
# SCOPE: storylines read personal flags, nothing else sets them; lives never set storyline flags
# =============================================================================

func _test_personal_flags_read_only():
	print("Personal flags: readable, never settable from outside the Life")
	_fresh()
	var direct = director.apply_effect({"type": "set_flag", "flag": "bjorn_true_blade_forged", "value": true})
	_check("A storyline-style set_flag of a personal flag is refused", not direct.ok and "personal flag" in direct.reason)
	var talk = director.apply_conversation_actions("bjorn", [{"type": "set_flag", "flag": "bjorn_true_blade_forged", "value": true}])
	_check("A conversation set_flag of a personal flag is dropped", talk.applied.is_empty() and "personal flag" in talk.dropped[0].reason)
	var mira_talk = director.apply_conversation_actions("mira", [{"type": "set_flag", "flag": "mira_count_coin_hidden", "value": true}])
	_check("...even its owner cannot set it by talking", mira_talk.applied.is_empty())
	_check("player_choice refuses personal flags", not director.player_choice("bjorn_true_blade_forged").ok)
	_check("Conversation reach never offers a personal flag (even one a beat resolves on)", not director.get_conversation_reach("bjorn").flags.has("mira_count_coin_hidden")
		and not director.get_conversation_reach("mira").flags.has("mira_count_coin_hidden"))
	_check("...so none of them is set", not world_state.get_world_flag("bjorn_true_blade_forged") and not world_state.get_world_flag("mira_count_coin_hidden"))
	var rumor = director.apply_effect({"type": "spread_rumor", "flag": "mira_count_coin_hidden", "to": ["*"]})
	_check("A rumor of an untrue personal flag does not spread", not rumor.ok)

func _test_claude_mode_scope():
	print("Claude mode: phrasing only, personal scope enforced")
	_fresh()
	var fake = FakeClaude.new()
	root.add_child(fake)
	director.set_agent_client(fake)
	director.set_agency_mode("claude")
	fake.reply = JSON.stringify({"effects": [
		{"type": "shift_want", "npc": "mira", "want": "coin", "delta": 2},
		{"type": "set_flag", "flag": "lf_blade_seen", "value": true},
		{"type": "agenda", "npc": "mira", "text": "Count it again."},
		{"type": "block_beat", "storyline": "lf_story", "beat": "the_week"},
		{"type": "shift_want", "npc": "bjorn", "want": "honest_steel", "delta": 2}], "reason": "Every coin counted twice."})
	var turn = await _turn_for("mira")
	_check("Claude phrased the completion", turn.get("agent_mode", "") == "claude" and fake.calls == 1 and turn.reason == "Every coin counted twice.")
	_check("set_flag dropped as storyline scope", turn.dropped.any(func(d): return d.effect.type == "set_flag" and "personal scope" in d.reason))
	var soul = director.get_soul("mira")
	var gate = director._apply_personal_effects("mira", soul, soul.get_arc("count_coin"), soul.get_step("count_coin", "tally"), [
		{"type": "block_beat", "storyline": "lf_story", "beat": "the_week"}, {"type": "unlock_beat", "storyline": "lf_story", "beat": "the_week"},
		{"type": "shift_want", "npc": "bjorn", "want": "honest_steel", "delta": 1}])
	_check("block_beat/unlock_beat dropped as storyline scope; another soul's want is out of scope", gate.applied.is_empty()
		and gate.dropped.filter(func(d): return "personal scope" in d.reason).size() == 3)
	_check("...so no storyline flag or beat changed", not world_state.get_world_flag("lf_blade_seen") and director.get_beat_status("lf_story", "the_week") == "open")
	_check("A type the step does not list is dropped (agenda)", turn.dropped.any(func(d): return d.effect.type == "agenda" and "does not use agenda" in d.reason))
	_check("The step's own type applies (shift_want +2)", turn.applied.size() == 1 and director.get_soul("mira").get_weight("coin") == 7)
	_check("Budget: at most 3 effects per step", turn.dropped.any(func(d): return "budget" in d.reason))
	_fresh()
	director.set_agency_mode("claude")
	fake.reply = "I would rather not say."
	turn = await _turn_for("mira")
	_check("Unusable reply: offline effects, mode claude_fallback", turn.get("agent_mode", "") == "claude_fallback" and director.get_soul("mira").get_weight("coin") == 6)
	director.set_agency_mode("offline")
	director.set_agent_client(null)
	fake.queue_free()

# =============================================================================
# PRIORITY AND CAP
# =============================================================================

func _test_priority_and_cap():
	print("Priority ordering and the per-round cap")
	_fresh()
	world_state.set_world_flag("lf_coin_ready", true)  # Mira's second step stays available
	director.personal_decisions_per_round = 1
	director.player_location_override = "thornhaven_tavern"
	var order = director.get_personal_candidates().map(func(c): return c.npc)
	_check("Near the player first: Mira (at the tavern) leads despite a lighter want", order[0] == "mira" and order.size() == 3)
	var entries = await director.run_personal_turns("test")
	_check("Cap 1: exactly one turn, Mira's", entries.size() == 1 and entries[0].npc == "mira")
	director.player_location_override = "capitol_palace"
	order = director.get_personal_candidates()
	_check("Far from everyone: heaviest want first (9, 9, then 5)", order.map(func(c): return c.npc) == ["bjorn", "elena", "mira"] or order.map(func(c): return c.npc) == ["bjorn", "elena"])
	director.personal_decisions_per_round = 2
	entries = await director.run_personal_turns("test")
	_check("Cap 2: Bjorn and Elena take turns, Mira waits", entries.map(func(e): return e.npc) == ["bjorn", "elena"])
	director.get_soul("mira").shift_want("coin", 4)  # now 9, level with Elena
	order = director.get_personal_candidates().map(func(c): return c.npc)
	_check("Equal weight: the longest-waiting goes first (Mira, then Elena; Bjorn is on the road)", order == ["mira", "elena"])
	director.personal_decisions_per_round = 0
	_check("Cap 0: no turns", (await director.run_personal_turns("test")).is_empty())
	director.personal_decisions_per_round = 10

# =============================================================================
# REGISTRATION AND TIERS
# =============================================================================

func _test_registration_and_tiers():
	print("register_soul, tiers, unregister")
	_fresh()
	_check("validate_soul_text accepts the rolled farmer", director.validate_soul_text(FARMER, farmer_text).ok)
	var bad_life = director.validate_soul_text("gen_bad", _life_text("### Arc: `a` (serves `goal`)\n- `s`: X. | after: none | needs: none | at: any | takes: 1 | effects: set_flag\n- result: `gen_bad_a`: A.\n", "x"))
	_check("validate_soul_text explains a bad Life", not bad_life.ok and bad_life.errors.size() == 1)
	_check("No Wants: refused", not director.register_soul("gen_empty", "# SOUL: Nobody\n## Essence\nNothing.\n", {"tier": "generic"}))
	_check("Bad Life: refused", not director.register_soul("gen_bad", _life_text("### Arc: `a` (serves `goal`)\n- `s`: X. | after: none | needs: none | at: any | takes: 1 | effects: set_flag\n- result: `gen_bad_a`: A.\n"), {"tier": "promoted"}))
	_check("Unknown tier: refused", not director.register_soul(FARMER, farmer_text, {"tier": "boss"}))
	_check("A SOUL.md file's key: refused", not director.register_soul("bjorn", farmer_text, {"tier": "generic"}))
	var clash = _life_text("### Arc: `a` (serves `goal`)\n- `s`: X. | after: none | needs: none | at: any | takes: 1 | effects: agenda\n- result: `lf_blade_seen`: A.\n", "lf")
	_check("Life flags that clash with storyline flags: refused", not director.register_soul("lf", clash, {"tier": "generic"}))

	_check("Registered as generic", director.register_soul(FARMER, farmer_text, {"tier": "generic", "npc_id": FARMER, "home": "thornhaven_town_square"}))
	_check("Tier, soul and npc_id lookups", director.get_soul_tier(FARMER) == "generic" and director.has_soul(FARMER) and director.is_registered_soul(FARMER)
		and director.get_soul(FARMER).npc_id == FARMER and director.get_registered_souls().has(FARMER))
	_check("Its home is its location", director.get_npc_location(FARMER) == "thornhaven_town_square")
	_check("Its Life flags are known, personal flags", director.is_known_flag("gen_farmer_1_cow_bought") and director.is_personal_flag("gen_farmer_1_cow_save_coin"))
	_check("Its conversation block carries its Life", "YOUR OWN LIFE" in director.get_conversation_block(FARMER))
	_check("Generic tier: no personal turns", not director.get_personal_candidates().any(func(c): return c.npc == FARMER) and (await _turn_for(FARMER)).is_empty())
	var talk = director.apply_conversation_actions(FARMER, [{"type": "agenda", "text": "Ask the stranger what a cow costs in the capitol."}])
	_check("Same conversation agency rules: its own agenda applies", talk.applied.size() == 1 and director.get_agendas(FARMER).size() == 1)
	var flagged = director.apply_conversation_actions(FARMER, [{"type": "set_flag", "flag": "lf_coin_ready", "value": true}])
	_check("Generic tier acts at personal scope only in conversation", flagged.applied.is_empty() and "personal scope only" in flagged.dropped[0].reason)

	_check("Promote: set_soul_tier promoted", director.set_soul_tier(FARMER, "promoted") and director.get_soul_tier(FARMER) == "promoted")
	var turn = await _turn_for(FARMER)
	_check("Promoted: gets personal turns", turn.get("choice", "") == "completed_step" and world_state.get_world_flag("gen_farmer_1_cow_save_coin"))
	_check("Re-registering keeps progress where arcs still match", director.register_soul(FARMER, farmer_text, {"tier": "promoted", "npc_id": FARMER})
		and director.get_soul(FARMER).is_step_done("cow", "save_coin"))
	_check("Demote: back to generic, no turns", director.set_soul_tier(FARMER, "generic") and (await _turn_for(FARMER)).is_empty())
	_check("File souls are anchored at main", not director.set_soul_tier("bjorn", "generic") and director.set_soul_tier("bjorn", "main") and director.get_soul_tier("bjorn") == "main")
	_check("Unregister a file soul: refused", not director.unregister_soul("bjorn"))
	_check("Unregister", director.unregister_soul(FARMER) and not director.has_soul(FARMER) and not director.is_known_flag("gen_farmer_1_cow_bought") and director.get_soul_tier(FARMER) == "")
	_check("load_content keeps runtime souls", director.register_soul(FARMER, farmer_text, {"tier": "promoted", "npc_id": FARMER}) and _reload() and director.get_soul_tier(FARMER) == "promoted")
	director.unregister_soul(FARMER)

func _reload() -> bool:
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)
	return true

# =============================================================================
# SAVE / LOAD
# =============================================================================

func _test_save_load():
	print("Save/load round-trip")
	_fresh()
	director.register_soul(FARMER, farmer_text, {"tier": "promoted", "npc_id": FARMER})
	await director.run_personal_turns("test")  # bjorn travels, elena 1/2, mira tallies, farmer saves
	await director.run_personal_turns("test")  # elena waits, farmer 1/2 on the cow
	director.commit_personal_help("elena", "help:elena_own_way_ask_the_healer")
	var before = {
		"bjorn": director.get_soul("bjorn").get_life_state(), "elena": director.get_soul("elena").get_life_state(),
		"mira": director.get_soul("mira").get_life_state(), "farmer": director.get_soul(FARMER).get_life_state(),
		"round": director.get_personal_round(), "coin": director.get_soul("mira").get_weight("coin"),
	}
	_check("State worth saving", before.mira.arcs.count_coin.done == ["tally"] and before.elena.arcs.own_way.helped == ["ask_the_healer"]
		and before.farmer.arcs.cow.progress.get("the_cow", 0) == 1)
	var data = JSON.parse_string(JSON.stringify(director.save()))  # as it would come back from disk

	director.reset_state()
	_check("reset_state forgets Life progress", director.get_soul("mira").get_life_state().arcs.count_coin.done.is_empty())
	director.load_from_dict(data)
	_check("Main souls: progress, help and turns restored", _same(director.get_soul("mira").get_life_state(), before.mira)
		and _same(director.get_soul("elena").get_life_state(), before.elena) and _same(director.get_soul("bjorn").get_life_state(), before.bjorn))
	_check("Registered soul present at load: restored", _same(director.get_soul(FARMER).get_life_state(), before.farmer))
	_check("Personal round and drifted weights restored", director.get_personal_round() == before.round and director.get_soul("mira").get_weight("coin") == before.coin)

	# A fresh boot: the generics engine re-registers its souls after the Director loaded the save
	director.unregister_soul(FARMER)
	director.reset_state()
	director.load_from_dict(data)
	_check("Before re-registration the soul is absent but its state is held", not director.has_soul(FARMER)
		and director.save().life.has(FARMER) and director.save().registered_tiers.get(FARMER, "") == "promoted")
	_check("Re-registered (no tier given): saved tier and progress return", director.register_soul(FARMER, farmer_text, {"npc_id": FARMER})
		and director.get_soul_tier(FARMER) == "promoted" and _same(director.get_soul(FARMER).get_life_state(), before.farmer))
	var turn = await _turn_for("elena")
	_check("Play continues after load: Elena's helped step completes", turn.get("choice", "") == "completed_arc")
	director.unregister_soul(FARMER)

# =============================================================================
# HELPERS
# =============================================================================

## Run one personal phase; the entry for this NPC ({} when it got no turn)
func _turn_for(key: String) -> Dictionary:
	for entry in await director.run_personal_turns("test"):
		if entry.npc == key:
			return entry
	return {}

func _same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)

func _fresh():
	for flag in world_state.world_flags.keys():
		if flag.begins_with("lf_") or director.is_personal_flag(flag):
			world_state.world_flags.erase(flag)
	world_state.npc_states = {}
	director.reset_state()
	director.personal_decisions_per_round = 10
	director.player_location_override = ""
	director.personal_turns_enabled = true
	director.evaluate_all()
	steps_done.clear()
	arcs_ended.clear()

func _restore():
	director.player_location_override = ""
	director.personal_decisions_per_round = -1
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
