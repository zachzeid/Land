extends SceneTree

# Tests conversation agency (docs/WORLD_SCHEMA.md §5-7): WorldRegistry lookups, the game clock and
# its story rounds, plausibility rules 1-7 in StorylineDirector.apply_conversation_actions, real
# NPC travel with the spawner, player commitments, forbidden-concept regeneration with a fake
# Claude client, save/load of clock and travel state, and the per-turn context token cost.
# Fixtures and fakes only: no API calls, in-memory RAGMemory (nothing reaches ./chroma), no save file
# Run: godot --headless --path . -s res://scripts/debug/test_conversation_agency.gd

const FIXTURE_STORYLINES = "res://scripts/debug/fixtures/conversation/storylines"
const FIXTURE_SOULS = "res://scripts/debug/fixtures/conversation/souls"
const SID = "cv_story"
const MIRA = "mira_tavern_keeper_001"
const GREGOR = "gregor_merchant_001"
const VARN = "varn_bandit_001"

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
	var home_location: String = ""
	func get_current_location() -> String:
		return current_location

## Stands in for ClaudeClient: returns canned replies in order (the last one repeats)
class FakeClaude extends Node:
	var api_key_override: String = "fake-key-for-tests"
	var replies: Array = []
	var calls: int = 0
	var systems: Array = []
	func send_message(_messages: Array, system_prompt: String = "") -> Dictionary:
		calls += 1
		systems.append(system_prompt)
		var reply = replies[mini(calls - 1, replies.size() - 1)] if not replies.is_empty() else ""
		return {"text": reply}

var director: Node
var world_state: Node
var registry: Node
var propagator: Node
var scene_manager: Node
var config: Node
var failures: int = 0
var npcs: Array = []
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int

func _init():
	await process_frame
	await process_frame
	director = root.get_node("StorylineDirector")
	world_state = root.get_node("WorldState")
	registry = root.get_node("WorldRegistry")
	propagator = root.get_node("EventPropagator")
	scene_manager = root.get_node("SceneManager")
	config = root.get_node("Config")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	world_state.set_idle_clock_rate(0.0)  # only the test moves the clock
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)

	print("============================================================")
	print("🧪 CONVERSATION AGENCY TEST")
	print("============================================================\n")

	_test_registry()
	_test_hallucination_checks()
	_test_discovery_flags()
	await _test_clock_and_rounds()
	_test_converse_grants_and_context()
	_test_rule1_vocabulary_and_soul()
	_test_rule2_reach()
	_test_rule3_truth()
	await _test_rule4_far_effects()
	_test_rule4_move_validation()
	await _test_move_travel_and_spawner()
	_test_rule5_commitments()
	_test_rule7_budget()
	_test_chronicle()
	await _test_forbidden_concepts_regenerate_then_sanitise()
	await _test_reply_end_to_end()
	await _test_save_load_clock_and_travel()
	_test_context_token_cost()
	await _test_agency_block_budget_all_npcs()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# REGISTRY
# =============================================================================

func _test_registry():
	print("WorldRegistry lookups")
	_check("All 20 roster NPCs load", registry.get_npc_keys().size() == 20 and registry.has_npc("corwin") and registry.has_npc("anselm") and registry.has_npc("davin"))
	_check("key <-> npc_id both ways", registry.get_npc_key("corwin_magistrate_001") == "corwin" and registry.get_npc_id("rook") == "rook_broker_001" and registry.get_npc_key("Gregor") == "gregor")
	_check("Unknown NPCs give empty answers", registry.get_npc_key("marta_baker_001") == "" and registry.get_npc("nobody").is_empty())
	_check("Home and scene", registry.get_npc_home("edric") == "capitol_palace" and registry.get_npc_scene("varn") == "res://scenes/npcs/varn_bandit.tscn")
	_check("26 locations with built, region and travel_point", registry.get_location_ids().size() == 26 and registry.is_built("thornhaven_tavern")
		and registry.get_location_ids().all(func(id): return registry.is_built(id) == (registry.get_location(id).get("built", false) == true)) and registry.get_region("capitol_docks") == "the_capitol" and registry.is_travel_point("ferrisford"))
	_check("Direct route minutes, -1 for non-neighbours", registry.get_route_minutes("thornhaven_town_square", "thornhaven_tavern") == 1
		and registry.get_route_minutes("thornhaven_tavern", "old_mill") == -1)
	var neighbours = registry.get_neighbours("village_gate").map(func(e): return e.location)
	_check("Neighbours of the gate", "old_mill" in neighbours and "kingsroad_waystation" in neighbours and neighbours.size() == 5)
	_check("Shortest travel (Dijkstra): tavern -> old mill is 24m", registry.travel_minutes("thornhaven_tavern", "old_mill") == 24)
	_check("Mode matters: the barge makes the Capitol closer", registry.travel_minutes("village_gate", "capitol_gate") == 1825
		and registry.travel_minutes("village_gate", "capitol_gate", "foot") == 1920)
	var path = registry.find_path("thornhaven_tavern", "iron_hollow_camp")
	_check("Path through the forest", path.minutes == 124 and path.path == ["thornhaven_tavern", "thornhaven_town_square", "village_gate", "forest_path", "iron_hollow_camp"])
	_check("World rules and forbidden concepts load", registry.get_world_rules().size() >= 5 and "car" in registry.get_forbidden_concepts())
	_check("Forbidden concepts match whole words, any case, plurals", registry.find_forbidden_concepts("He parked the CAR, okay? Guns too.") == ["car", "okay", "gun"])
	_check("...not inside other words", registry.find_forbidden_concepts("A scarf, a carton, carts and a cartographer").is_empty())
	_check("Sanitising keeps case and plural", registry.sanitize_forbidden("Cars and a gun, okay.") == "Carts and a crossbow, aye.")

func _test_hallucination_checks():
	print("Hallucination checks know the whole roster and map")
	var world_events = root.get_node("WorldEvents")
	var corwin = world_events.validate_memory("Player said: \"hello\". Corwin and Hollis met at The High Magistry, then The Lantern Market.", "corwin_magistrate_001")
	_check("Capitol names and places are valid memories", corwin.valid)
	_check("...and Corwin, Hollis, Seraphine are known people", world_events._is_valid_npc_name("Corwin") and world_events._is_valid_npc_name("Seraphine") and world_events._is_valid_npc_name("Anselm"))
	_check("Every registry location name passes", registry.get_location_ids().all(func(id): return world_events.validate_memory("We spoke of %s today." % registry.get_location_name(id), MIRA).valid))
	_check("Storyline titles are canon too", world_events.validate_memory("Everyone talks of The Talking Fixture now.", MIRA).valid)
	_check("Invented establishments still fail", not world_events.validate_memory("I drank at The Golden Goose.", MIRA).valid
		and not world_events.validate_memory("We met at The Crooked Lantern Inn.", MIRA).valid)
	_check("A villager claiming a Capitol visit is rejected", not world_events.validate_memory("I went to the Capitol last spring.", GREGOR).valid)
	_check("...a Capitol resident's is not", world_events.validate_memory("I went to the Capitol cathedral at dawn.", "corwin_magistrate_001").valid)
	var knowledge = root.get_node("WorldKnowledge")
	var facts = knowledge.get_world_facts_for_npc("corwin_magistrate_001")
	_check("A Capitol NPC's world facts are the Capitol's, not Thornhaven's", "High Magistry" in facts and "Lady Seraphine Ashdown" in facts and not ("YOUR VILLAGE: THORNHAVEN" in facts))
	_check("Thornhaven facts now list Aldric, Mathias and Varn", "Captain Aldric" in knowledge.get_world_facts_for_npc(MIRA) and "Varn" in knowledge.get_world_facts_for_npc(MIRA))
	_check("Knowledge scope from the registry", knowledge.get_knowledge_scope_for_location("corwin_magistrate_001", "capitol_palace") == knowledge.KnowledgeScope.LOCAL
		and knowledge.get_knowledge_scope_for_location(MIRA, "old_mill") == knowledge.KnowledgeScope.LOCAL
		and knowledge.get_knowledge_scope_for_location(MIRA, "capitol_palace") == knowledge.KnowledgeScope.DISTANT)

func _test_discovery_flags():
	print("world.json discovery_flags are base flags")
	var discovery: Dictionary = registry.get_discovery_flags()
	_check("Discovery flags load", discovery.has("oskar_tally_seen") and discovery.has("ashguard_ledger_read"))
	_check("Descriptions reach StoryFlags", StoryFlags.get_flag_description("oskar_tally_seen") == str(discovery.oskar_tally_seen))
	_check("is_known_flag knows them (and still not nonsense)", director.is_known_flag("ashguard_ledger_read") and not director.is_known_flag("cv_nonsense"))
	world_state.world_flags.erase("varn_warrant_seen")
	var result = director.apply_effect({"type": "set_flag", "flag": "varn_warrant_seen", "value": true})
	_check("set_flag effects can target them", result.ok and world_state.get_world_flag("varn_warrant_seen"))
	world_state.world_flags.erase("varn_warrant_seen")
	_check("Witnesses notice them", propagator.is_witnessable("deep_vein_salt_seen") and propagator.is_witnessable("ledger_found") and not propagator.is_witnessable("cv_begin"))

# =============================================================================
# CLOCK
# =============================================================================

func _test_clock_and_rounds():
	print("Game clock and time-driven rounds")
	_reset()
	world_state.game_minutes = world_state.start_minute
	_check("New game starts at the drawing: day 1, 20:00", world_state.get_day() == 1 and world_state.get_hour() == 20 and world_state.get_time_string() == "Day 1, 20:00")
	var seen: Array = []
	var bus = root.get_node("EventBus")
	var listener = func(m, total, reason): seen.append([m, total, reason])
	bus.time_advanced.connect(listener)
	world_state.advance_time(17 * 60 + 5, "test")
	_check("advance_time moves day and hour", world_state.get_day() == 2 and world_state.get_hour() == 13 and world_state.get_minute() == 5)
	_check("EventBus.time_advanced carries minutes, total and reason", seen.size() == 1 and seen[0][0] == 1025 and seen[0][2] == "test")
	world_state.advance_time(0, "nothing")
	_check("Zero minutes is no event", seen.size() == 1)
	bus.time_advanced.disconnect(listener)

	director.reset_state()
	_check("119 minutes owe no round", director.add_game_minutes(119) == 0)
	_check("...the 120th owes one", director.add_game_minutes(1) == 1 and director.get_time_round_state().minutes_toward_round == 0)
	_check("A 6-hour journey owes three", director.add_game_minutes(360) == 3)
	_check("Remainders carry over", director.add_game_minutes(100) == 0 and director.add_game_minutes(140) == 2 and director.get_time_round_state().minutes_toward_round == 0)
	director.reset_state()

	director.round_boundaries_enabled = true
	var start = director.get_round()
	world_state.advance_time(250, "walk")
	for i in 8:
		await process_frame
	_check("250 game minutes run 2 story rounds", director.get_round() == start + 2)
	start = director.get_round()
	world_state.advance_time(60, "walk")
	for i in 4:
		await process_frame
	_check("...and the 10 left over plus 60 run none yet", director.get_round() == start)
	director.round_boundaries_enabled = false

# =============================================================================
# CONVERSATION RULES
# =============================================================================

func _test_converse_grants_and_context():
	print("Converse grants and the per-turn context")
	_reset()
	var mira = director.get_soul("mira")
	var gregor = director.get_soul("gregor")
	_check("A converse: line is used as written", mira.get_converse_grants() == ["set_flag", "agenda", "spread_rumor", "move_npc", "block_beat"])
	_check("Without one: union of react, reveal and aid", gregor.get_converse_grants() == ["move_npc", "agenda"] and gregor.get_converse_grant_source() == "react+reveal+aid")
	var block = director.get_conversation_agency_block("mira")
	_check("Context names where and when", "The Rusty Nail" in block and "Day " in block)
	_check("...the world rules", "no engines, firearms" in block)
	_check("...only granted effect shapes", "\"type\":\"move_npc\"" in block and not ("adjust_relationship" in block))
	_check("...open beats and options as suggestions", "Talk at the Bar" in block and "Signal a friend" in block and "ideas, not a menu" in block)
	_check("...flags in reach, not the future beat's", "cv_resolve" in block and "cv_offer" in block and not ("cv_future" in block))
	_check("...the player flags it may recognise", "cv_pledge" in block and "GENUINELY commits" in block)
	_check("...places with travel times", "old_mill 24m" in block and "Iron Hollow, 2h04" in block)
	_check("No SOUL.md, no block", director.get_conversation_agency_block("bjorn") == "")

func _test_rule1_vocabulary_and_soul():
	print("Rule 1: vocabulary, converse Agency, lines")
	_reset()
	var r = _act("mira", [{"type": "agenda", "npc": "mira", "text": "Ask the stranger where they sleep tonight."}])
	_check("A valid action is applied", r.applied.size() == 1 and director.get_agendas("mira").size() == 1)
	r = _act("mira", [{"type": "drive_car", "to": "the hill"}])
	_check("Unknown effect types are dropped", r.applied.is_empty() and _reason(r).begins_with("vocabulary: unknown effect type"))
	r = _act("mira", [{"type": "adjust_relationship", "npc": "mira", "dimension": "trust", "delta": 5}])
	_check("Outside converse Agency is dropped", r.applied.is_empty() and "Agency for converse (converse) does not grant adjust_relationship" in _reason(r))
	r = _act("gregor", [{"type": "spread_rumor", "flag": "cv_begin", "to": ["mira"]}])
	_check("The fallback grant is enforced too", r.applied.is_empty() and "converse (react+reveal+aid) does not grant spread_rumor" in _reason(r))
	r = _act("mira", [{"type": "set_flag", "flag": "cv_exposed", "value": true}])
	_check("A Lines-I-Will-Not-Cross violation is dropped", r.applied.is_empty() and "line 'effect:set_flag:cv_exposed'" in _reason(r) and not world_state.get_world_flag("cv_exposed"))
	r = _act("mira", [{"type": "agenda", "npc": "gregor", "text": "Tell the stranger the shop was shut all night."}])
	_check("Replaying a suggested option tagged aids: gregor hits ally:gregor", r.applied.is_empty() and "line 'ally:gregor'" in _reason(r))
	r = _act("mira", [{"type": "agenda", "text": "Remember the stranger's face."}])
	_check("An agenda with no npc means the speaker", r.applied.size() == 1 and r.applied[0].npc == "mira")

func _test_rule2_reach():
	print("Rule 2: flags in reach")
	_reset()
	var r = _act("mira", [{"type": "set_flag", "flag": "cv_future", "value": true}])
	_check("A future beat's flag is dropped", r.applied.is_empty() and _reason(r).begins_with("reach: 'cv_future' is not in reach"))
	r = _act("mira", [{"type": "set_flag", "flag": "ledger_found", "value": true}])
	_check("A known flag no open beat offers is dropped", r.applied.is_empty() and _reason(r).begins_with("reach:"))
	r = _act("mira", [{"type": "set_flag", "flag": "cv_pledge", "value": true}])
	_check("A player flag cannot be set_flag'd", r.applied.is_empty() and "the player's own choice" in _reason(r))
	r = _act("mira", [{"type": "set_flag", "flag": "cv_offer", "value": true}])
	_check("A flag from her hook's option is in reach and applied", r.applied.size() == 1 and world_state.get_world_flag("cv_offer"))
	r = _act("mira", [{"type": "set_flag", "flag": "cv_offer", "value": true}])
	_check("Setting it again is no change", r.applied.is_empty() and _reason(r).begins_with("no change"))
	r = _act("mira", [{"type": "set_flag", "flag": "cv_resolve", "value": true}])
	_check("An open beat's resolves_on flag resolves it", r.applied.size() == 1 and director.get_beat_status(SID, "talk") == "resolved")
	_check("...which opens the next beat, putting its flag in reach", director.get_conversation_reach("mira").flags.has("cv_future"))
	_reset()
	world_state.set_npc_location(VARN, "iron_hollow_camp")
	var varn_reach = director.get_conversation_reach("varn")
	_check("A far beat with no hook for the speaker is out of reach", not varn_reach.flags.has("cv_second") and not varn_reach.flags.has("cv_resolve"))
	_check("...while the near one he has no hook in is in reach for Mira", director.get_conversation_reach("mira").flags.has("cv_second"))

func _test_rule3_truth():
	print("Rule 3: rumors carry only truth")
	_reset()
	var r = _act("mira", [{"type": "spread_rumor", "flag": "cv_lie", "to": ["gregor"]}])
	_check("An untrue rumor is dropped", r.applied.is_empty() and _reason(r).begins_with("truth: 'cv_lie' is not true"))
	world_state.set_world_flag("cv_secret", true)
	var gregor = _spawn(GREGOR, "thornhaven_gregor_shop")
	r = _act("mira", [{"type": "spread_rumor", "flag": "cv_secret", "to": ["gregor"], "via": "a word over the counter"}])
	_check("A true rumor to someone nearby lands now", r.applied.size() == 1 and gregor.rag_memory.stored.size() == 1)

func _test_rule4_far_effects():
	print("Rule 4: nothing happens instantly at a distance")
	_reset()
	var now = world_state.game_minutes
	var r = _act("mira", [{"type": "set_flag", "flag": "cv_far", "value": true}])
	_check("A flag for a far beat is accepted but delayed", r.applied.size() == 1 and not world_state.get_world_flag("cv_far") and str(r.applied[0].get("when", "")) == "game_minute %d" % (now + 124))
	world_state.set_world_flag("cv_secret", true)
	r = _act("mira", [{"type": "spread_rumor", "flag": "cv_secret", "to": ["varn", "gregor"]}])
	_check("A rumor splits: the near listener now, the far one later", r.applied.size() == 2 and r.applied[0].to == ["gregor"] and r.applied[1].to == ["varn"])
	r = _act("mira", [{"type": "agenda", "npc": "varn", "text": "Lie low until the new moon."}])
	_check("An agenda for someone far away waits for the road", r.applied.size() == 1 and director.get_agendas("varn").is_empty())
	_check("Three effects are in flight", director.get_scheduled_effects().size() == 3)
	world_state.advance_time(123, "test")
	_check("Not yet at 123 minutes", not world_state.get_world_flag("cv_far") and director.get_scheduled_effects().size() == 3)
	world_state.advance_time(1, "test")
	_check("At 124 minutes the word arrives", world_state.get_world_flag("cv_far") and director.get_agendas("varn").size() == 1
		and propagator.get_pending_count("varn") == 1 and director.get_scheduled_effects().is_empty())
	var arrived = director.get_chronicle().filter(func(e): return e.trigger == "word_arrived")
	_check("Each arrival is chronicled", arrived.size() == 3 and arrived[0].mode == "conversation")
	_check("The far beat resolved when the word arrived", director.get_beat_status(SID, "far") == "resolved")

func _test_rule4_move_validation():
	print("Rule 4: move_npc must be reachable")
	_reset()
	var r = _act("mira", [{"type": "move_npc", "npc": "mira", "location": "the_moon"}])
	_check("Unknown places are vocabulary errors", _reason(r).begins_with("vocabulary: unknown location"))
	var island_world: Dictionary = registry.data.duplicate(true)
	island_world.locations.append({"id": "cv_island", "name": "An Island", "region": "western_valley", "area": "Nowhere", "kind": "exterior", "scene": "", "built": false})
	registry.load_from_dict(island_world)
	r = _act("mira", [{"type": "move_npc", "npc": "mira", "location": "cv_island"}])
	_check("A place no road reaches is dropped", r.applied.is_empty() and _reason(r) == "place: cv_island cannot be reached from thornhaven_tavern on the roads")
	registry.load_world()
	r = _act("mira", [{"type": "move_npc", "npc": "gregor", "location": "old_mill"}])
	_check("She cannot move someone who is not here", r.applied.is_empty() and _reason(r).begins_with("place: gregor is not here"))
	r = _act("mira", [{"type": "move_npc", "npc": "mira", "location": "thornhaven_tavern"}])
	_check("Moving to where she is is dropped", _reason(r) == "place: mira is already at thornhaven_tavern")

func _test_move_travel_and_spawner():
	print("move_npc: leaves at conversation end, travels, appears at the destination")
	_reset()
	var spawner = scene_manager.npc_spawner
	spawner.instancer = func(key, _path): return _make_fake(registry.get_npc_id(key), "")
	spawner.initialize_spawned = false
	var tavern_scene = Node2D.new()
	tavern_scene.name = "CvTavern"
	root.add_child(tavern_scene)
	current_scene = tavern_scene
	scene_manager.current_location = scene_manager.get_location("thornhaven_tavern")
	var baked = _make_fake(MIRA, "thornhaven_tavern")
	tavern_scene.add_child(baked)
	var report = spawner.reconcile("thornhaven_tavern", tavern_scene)
	_check("Baked Mira is shown where she is", report.shown == ["mira"] and baked.visible)

	var r = _act("mira", [{"type": "move_npc", "npc": "mira", "location": "old_mill"}])
	_check("A reachable move is accepted for conversation end", r.applied.size() == 1 and r.applied[0].when == "conversation_end" and r.applied[0].minutes == 24)
	_check("...she has not left yet", not world_state.is_npc_travelling(MIRA) and baked.visible)
	r = _act("mira", [{"type": "move_npc", "npc": "mira", "location": "village_gate"}])
	_check("A second move in the same talk is dropped", _reason(r) == "place: mira is already leaving for old_mill")
	var departed = director.finish_conversation(MIRA)
	_check("Conversation end sets her off", departed.size() == 1 and departed[0].ok and world_state.is_npc_travelling(MIRA))
	_check("She is absent from the tavern while travelling", not baked.visible and baked.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("...and belongs nowhere on the road", not spawner.should_be_at("mira", "old_mill") and not spawner.should_be_at("mira", "thornhaven_tavern"))
	var mill_scene = Node2D.new()
	mill_scene.name = "CvMill"
	root.add_child(mill_scene)
	_check("A scene at the mill does not get her early", spawner.reconcile("old_mill", mill_scene).spawned.is_empty())
	world_state.advance_time(23, "test")
	_check("Still on the road at 23 minutes", world_state.is_npc_travelling(MIRA))
	world_state.advance_time(1, "test")
	_check("Arrives after 24 minutes", not world_state.is_npc_travelling(MIRA) and world_state.get_npc_location(MIRA) == "old_mill")
	report = spawner.reconcile("old_mill", mill_scene)
	var spawned = mill_scene.get_children().filter(func(n): return "npc_id" in n and n.npc_id == MIRA)
	_check("The spawner instances her at the mill", report.spawned == ["mira"] and spawned.size() == 1 and spawned[0].visible and spawned[0].current_location == "old_mill")
	_check("...once (already present by npc_id)", spawner.reconcile("old_mill", mill_scene).spawned.is_empty())
	_check("She stays hidden in the tavern", spawner.reconcile("thornhaven_tavern", tavern_scene).hidden == ["mira"] and not baked.visible)
	_check("Travel and arrival are chronicled", director.get_chronicle().any(func(e): return e.trigger == "conversation_end" and e.applied.size() == 1))

	world_state.set_npc_location(MIRA, "thornhaven_tavern")
	report = spawner.reconcile("old_mill", mill_scene)
	_check("Spawner-made NPCs are freed when they leave", report.freed == ["mira"])
	spawner.instancer = Callable()
	var corwin_scene = registry.get_npc_scene("corwin")
	var bogus_world: Dictionary = registry.data.duplicate(true)
	for npc in bogus_world.npcs:
		if npc.key == "corwin":
			npc.scene = "res://scenes/npcs/does_not_exist_cv.tscn"
	registry.load_from_dict(bogus_world)
	world_state.set_npc_location("corwin_magistrate_001", "old_mill")
	report = spawner.reconcile("old_mill", mill_scene)
	_check("A missing NPC scene is skipped with a warning, not an error", report.skipped == ["corwin"])
	registry.load_world()
	_check("(registry restored)", registry.get_npc_scene("corwin") == corwin_scene)
	world_state.npc_states.erase("corwin_magistrate_001")
	current_scene = null
	scene_manager.current_location = null
	tavern_scene.free()
	mill_scene.free()
	spawner.initialize_spawned = true

func _test_rule5_commitments():
	print("Rule 5: player commitments go through player_choice")
	_reset()
	world_state.set_world_flag("cv_over", true)
	_check("(the old quarrel beat is closed)", director.get_beat_status(SID, "over") == "resolved")
	var r = _act("mira", [], ["cv_pledge"])
	_check("An open beat's player flag is applied", r.applied.size() == 1 and r.applied[0].type == "commitment" and world_state.get_world_flag("cv_pledge"))
	_check("...through player_choice (chronicled as the player)", director.get_chronicle().any(func(e): return e.npc == "player" and e.choice == "player_choice"))
	_check("...and it resolves its beat", director.get_beat_status(SID, "talk") == "resolved")
	r = _act("mira", [], ["cv_old_pledge"])
	_check("A closed beat's player flag is dropped", r.applied.is_empty() and _reason(r) == "commitment: no open beat waits on 'cv_old_pledge' (its beat is closed or not open yet)")
	r = _act("mira", [], ["cv_pledge"])
	_check("A commitment already made is dropped", _reason(r) == "commitment: 'cv_pledge' was already made")
	r = _act("mira", [], ["cv_offer", "made_up"])
	_check("Non-player flags are not commitments", _reason(r, 0) == "commitment: 'cv_offer' is not a player flag" and _reason(r, 1) == "commitment: unknown flag 'made_up'")
	var report = director.get_player_flag_report()
	_check("Player-flag report covers every player flag", report.size() == 2 and report.all(func(row): return row.status in ["done", "committable", "waiting", "not in resolves_on"]))

func _test_rule7_budget():
	print("Rule 7: budget")
	_reset()
	var actions: Array = []
	for i in 4:
		actions.append({"type": "agenda", "npc": "mira", "text": "Thought number %d." % i})
	var r = _act("mira", actions)
	_check("At most 3 actions per reply", r.applied.size() == 3 and r.dropped.size() == 1 and _reason(r) == "budget: at most 3 actions per reply")
	_reset()
	r = _act("mira", [{"type": "set_flag", "flag": "cv_resolve", "value": true}, {"type": "set_flag", "flag": "cv_second", "value": true}])
	_check("Only one beat-resolving set_flag per reply", r.applied.size() == 1 and _reason(r) == "budget: only one beat-resolving set_flag per reply"
		and world_state.get_world_flag("cv_resolve") and not world_state.get_world_flag("cv_second"))
	_reset()
	var order: Array = []
	var listener = func(flag, _old, value): if value == true: order.append(flag)
	root.get_node("EventBus").world_flag_changed.connect(listener)
	_act("mira", [{"type": "set_flag", "flag": "cv_offer", "value": true}, {"type": "set_flag", "flag": "cv_second", "value": true}])
	root.get_node("EventBus").world_flag_changed.disconnect(listener)
	_check("Effects apply in array order", order == ["cv_offer", "cv_second"] and director.get_beat_status(SID, "side") == "resolved")

func _test_chronicle():
	print("Chronicle: mode conversation, drops carry their reason")
	_reset()
	_act("mira", [{"type": "agenda", "npc": "mira", "text": "Watch the door."}, {"type": "set_flag", "flag": "cv_future", "value": true}], [], "Will you help me?", "[smiles] Perhaps.")
	var entry = director.get_chronicle().back()
	_check("One entry with mode conversation", entry.mode == "conversation" and entry.npc == "mira" and entry.trigger == "conversation" and entry.hook_type == "converse")
	_check("Applied and dropped, each drop with its reason", entry.applied.size() == 1 and entry.dropped.size() == 1 and str(entry.dropped[0].reason).begins_with("reach:"))
	_check("What was said is kept", entry.reason == "Will you help me?" and entry.label == "[smiles] Perhaps." and entry.has("game_minutes"))
	var before = director.get_chronicle().size()
	director.apply_conversation_actions("mira", [], [])
	_check("Plain talk with no actions adds no entry", director.get_chronicle().size() == before)

# =============================================================================
# CLAUDE REPLIES (fake client)
# =============================================================================

func _test_forbidden_concepts_regenerate_then_sanitise():
	print("Rule 6: forbidden concepts regenerate once, then sanitise")
	_reset()
	var npc = await _make_base_npc()
	var fake: FakeClaude = npc.claude_client
	fake.replies = ['{"response": "[grins] Hop in my car and we drive up the hill.", "actions": []}', '{"response": "[grins] Climb on my cart, then.", "actions": []}']
	var reply = await npc.request_checked_reply([{"role": "user", "content": "Can we go?"}], "SYSTEM")
	_check("A forbidden word triggers one regeneration", fake.calls == 2 and reply.regenerated and reply.sanitised.is_empty())
	_check("...with a correction note naming it", "CORRECTION" in fake.systems[1] and "car" in fake.systems[1] and not ("CORRECTION" in fake.systems[0]))
	_check("The clean regeneration is used", reply.response == "[grins] Climb on my cart, then.")
	fake.calls = 0
	fake.systems.clear()
	fake.replies = ['{"response": "Okay, my car is outside.", "actions": [{"type": "agenda", "npc": "mira", "text": "Telephone the stranger."}]}']
	reply = await npc.request_checked_reply([{"role": "user", "content": "Can we go?"}], "SYSTEM")
	_check("Failing twice: sanitised, never a third call", fake.calls == 2 and reply.sanitised == ["okay", "car", "telephone"])
	_check("Speech is sanitised", reply.response == "Aye, my cart is outside.")
	_check("Action text is sanitised", reply.actions[0].text == "Letter the stranger.")
	fake.calls = 0
	fake.replies = ['{"response": "Ale is two pennies.", "actions": []}']
	reply = await npc.request_checked_reply([{"role": "user", "content": "Price?"}], "SYSTEM")
	_check("Clean replies cost one call", fake.calls == 1 and not reply.regenerated)
	_free_base_npc(npc)

func _test_reply_end_to_end():
	print("A Claude reply with actions, through BaseNPC.respond_to_player")
	_reset()
	var npc = await _make_base_npc()
	var fake: FakeClaude = npc.claude_client
	fake.replies = [JSON.stringify({
		"response": "[lowering her voice] Fine. I'll send word, and you'll keep your mouth shut.",
		"analysis": {"player_tone": "friendly", "emotional_impact": "neutral", "interaction_type": "promise_made",
			"trust_change": 2, "respect_change": 0, "affection_change": 0, "fear_change": 0, "familiarity_change": 1,
			"learned_about_player": {"name": null, "occupation": null, "origin": null, "notable_facts": []}},
		"actions": [
			{"type": "set_flag", "flag": "cv_offer", "value": true},
			{"type": "move_npc", "npc": "mira", "location": "old_mill"},
			{"type": "set_flag", "flag": "cv_future", "value": true}
		],
		"commitments": ["cv_pledge"]
	})]
	npc.is_in_conversation = true
	await npc.respond_to_player("I swear I'll keep your secret. Now signal your man.")
	var result: Dictionary = npc.last_conversation_actions
	_check("The parsed reply's actions reach the Director", result.get("applied", []).size() == 3 and result.get("dropped", []).size() == 1)
	_check("Valid action applied, commitment applied", world_state.get_world_flag("cv_offer") and world_state.get_world_flag("cv_pledge"))
	_check("The future flag was dropped with its reason", str(result.dropped[0].reason).begins_with("reach: 'cv_future'"))
	_check("The prompt carried the agency block and the new JSON keys", "WHAT YOU CAN DO" in fake.systems[0] and "\"commitments\": []" in fake.systems[0])
	_check("The move waits for the conversation to end", not world_state.is_npc_travelling(MIRA))
	npc.end_conversation()
	_check("end_conversation sets her off", world_state.is_npc_travelling(MIRA) and world_state.get_npc_travel(MIRA).get("to") == "old_mill")
	_free_base_npc(npc)

# =============================================================================
# SAVE / LOAD
# =============================================================================

func _test_save_load_clock_and_travel():
	print("Save / load: clock, travel, pending moves, word in flight")
	_reset()
	world_state.game_minutes = 1000
	director.send_npc("mira", "old_mill")
	_act("mira", [{"type": "set_flag", "flag": "cv_far", "value": true}])
	_act("gregor", [{"type": "move_npc", "npc": "gregor", "location": "thornhaven_town_square"}])
	director.add_game_minutes(50)
	var saved = JSON.parse_string(JSON.stringify(world_state.save()))
	world_state.game_minutes = 5
	world_state.npc_states = {}
	director.reset_state()
	_check("(state cleared)", not world_state.is_npc_travelling(MIRA) and director.get_scheduled_effects().is_empty())
	world_state.load_from_dict(saved)
	_check("The clock survives a JSON save", world_state.game_minutes == 1000)
	_check("Travel survives", world_state.is_npc_travelling(MIRA) and int(world_state.get_npc_travel(MIRA).arrive) == 1024)
	_check("Word in flight survives", director.get_scheduled_effects().size() == 1 and int(director.get_scheduled_effects()[0].at) == 1115)
	_check("Pending conversation moves survive", director.get_pending_moves("gregor").gregor.size() == 1)
	_check("Minutes toward the next round survive", director.get_time_round_state().minutes_toward_round == 50)
	world_state.advance_time(24, "test")
	_check("...and the loaded journey still ends on time", world_state.get_npc_location(MIRA) == "old_mill" and not world_state.is_npc_travelling(MIRA))

# =============================================================================
# TOKEN COST (real content, real personalities, sample memories)
# =============================================================================

func _test_context_token_cost():
	print("Per-turn context token cost (real storylines and souls)")
	var real_flags = world_state.world_flags
	world_state.world_flags = {}
	world_state.npc_states = {}
	director.load_content("res://resources/storylines", "res://souls")
	director.evaluate_all()
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var memories = {"pinned": [], "important": ["The stranger asked about the bandits last week."],
		"relevant": ["Player said: \"Who runs this place?\". I responded: \"I do, love.\"", "The stranger paid in silver."]}
	var dims = {"trust": 10, "respect": 5, "affection": 5, "fear": 0, "familiarity": 20, "memory_count": 3}
	var rows: Array = []
	for pair in [["mira", "mira_tavern_keeper"], ["gregor", "gregor_merchant"], ["corwin", "corwin"], ["varn", "varn_bandit"]]:
		var personality = load("res://resources/npc_personalities/%s.tres" % pair[1])
		var npc_id = registry.get_npc_id(pair[0])
		var params = {"personality": personality, "npc_id": npc_id, "tiered_memories": memories, "relationship_dimensions": dims,
			"world_state": {"npc_id": npc_id, "world_flags": {}, "active_quests": []}, "conversation_history": [], "player_input": "What do you know about the bandits?"}
		config.conversation_agency = true
		var full = builder.estimate_token_count(builder.build_context(params))
		config.conversation_agency = false
		var without = builder.estimate_token_count(builder.build_context(params))
		config.conversation_agency = true
		var agency = int(director.get_conversation_agency_block(pair[0]).length() / 4.0)
		rows.append([pair[0], full, without, agency])
		print("    %s: %d tokens per turn (%d without agency; agency block %d)" % [pair[0], full, without, agency])
	_check("Every measured prompt fits ClaudeClient's 16000-char (~4000-token) cap", rows.all(func(row): return row[1] <= 4000))
	_check("The agency block stays compact (under 900 tokens)", rows.all(func(row): return row[3] < 900))
	builder.free()
	world_state.world_flags = real_flags
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)

## Worst-case agency block over every roster NPC: fresh world, after idle rounds, and with every beat open
func _test_agency_block_budget_all_npcs():
	print("Agency block budget: all 19 NPCs on the real content")
	var real_flags = world_state.world_flags
	var real_states = world_state.npc_states
	world_state.world_flags = {}
	world_state.npc_states = {}
	director.load_content("res://resources/storylines", "res://souls")
	director.evaluate_all()
	var worst = _measure_blocks("fresh world")
	_check("Fresh world: every block under 900 tokens", worst < 900)
	for i in 5:
		await director.advance_round("test")
	worst = _measure_blocks("after 5 idle rounds")
	_check("After idle rounds: every block under 900 tokens", worst < 900)
	var opened = 0
	for sid in director.get_storyline_ids():
		for beat in director.get_storyline(sid).beats:
			var key = "%s/%s" % [sid, beat.id]
			if not director._opened.has(key):
				director._open_counter += 1
				director._opened[key] = true
				director._opened_seq[key] = director._open_counter
			director._resolved.erase(key)
			director._blocked.erase(key)
			opened += 1
	print("    (forced %d beats open across %d storylines)" % [opened, director.get_storyline_ids().size()])
	worst = _measure_blocks("every beat open")
	_check("Every beat open: every block under 900 tokens", worst < 900)
	var mira_block = director.get_conversation_agency_block("mira")
	_check("Overflow beats are named, not detailed", "Also in play:" in mira_block and mira_block.count("  · ") <= director.MAX_BEATS_DETAILED * director.MAX_OPTIONS_PER_BEAT)
	_check("The flag list is capped", "less pressing" in mira_block)
	_check("Every block is within the hard char budget", registry.get_npc_keys().all(func(k): return director.get_conversation_agency_block(k).length() <= director.AGENCY_BLOCK_CHAR_BUDGET))
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var worst_full = 0
	var worst_key = ""
	for key in registry.get_npc_keys():
		var personality_name = {"gregor": "gregor_merchant", "elena": "elena_daughter", "mira": "mira_tavern_keeper", "bjorn": "bjorn_blacksmith",
			"aldric": "aldric_peacekeeper", "mathias": "elder_mathias", "varn": "varn_bandit"}.get(key, key)
		var path = "res://resources/npc_personalities/%s.tres" % personality_name
		if not ResourceLoader.exists(path):
			continue
		var npc_id = registry.get_npc_id(key)
		var context = builder.build_context({"personality": load(path), "npc_id": npc_id,
			"tiered_memories": {"pinned": [], "important": ["The stranger asked about the bandits last week."], "relevant": ["The stranger paid in silver."]},
			"relationship_dimensions": {"trust": 10, "respect": 5, "affection": 5, "fear": 0, "familiarity": 20, "memory_count": 2},
			"world_state": {"npc_id": npc_id, "world_flags": {}, "active_quests": []}, "conversation_history": [], "player_input": "What news?"})
		var tokens = builder.estimate_token_count(context)
		if tokens > worst_full:
			worst_full = tokens
			worst_key = key
	print("    worst full per-turn prompt with every beat open: %d tokens (%s)" % [worst_full, worst_key])
	_check("Every full prompt stays under ClaudeClient's ~4000-token cap", worst_full > 0 and worst_full <= 4000)
	_test_budget_with_heavy_memory(builder)
	builder.free()

	world_state.world_flags = real_flags
	world_state.npc_states = real_states
	director.load_content(FIXTURE_STORYLINES, FIXTURE_SOULS)

## Agency block tokens for every roster NPC; prints the worst three and returns the worst
func _measure_blocks(label: String) -> int:
	var rows: Array = []
	for key in registry.get_npc_keys():
		rows.append([key, int(director.get_conversation_agency_block(key).length() / 4.0)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("    %s: worst %s" % [label, ", ".join(rows.slice(0, 3).map(func(r): return "%s %d" % r))])
	return rows[0][1]

# =============================================================================
# HELPERS
# =============================================================================

func _act(npc: String, actions: Array, commitments: Array = [], player: String = "", said: String = "") -> Dictionary:
	return director.apply_conversation_actions(npc, actions, commitments, {"player": player, "said": said})

func _reason(result: Dictionary, index: int = -1) -> String:
	var dropped: Array = result.get("dropped", [])
	if dropped.is_empty():
		return ""
	return str(dropped[index if index >= 0 else dropped.size() - 1].reason)

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
	npc.home_location = "thornhaven_tavern"
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

func _reset():
	for npc in npcs:
		npc.remove_from_group("npcs")
		npc.queue_free()
	npcs.clear()
	for flag in world_state.world_flags.keys():
		if flag.begins_with("cv_"):
			world_state.world_flags.erase(flag)
	world_state.npc_states = saved_npc_states.duplicate(true)
	for npc_id in [MIRA, GREGOR, VARN]:
		world_state.npc_states.erase(npc_id)
	world_state.set_npc_location(MIRA, "thornhaven_tavern")
	propagator.load_from_dict({})
	director.reset_state()
	world_state.set_world_flag("cv_begin", true)

func _restore():
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	registry.load_world()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

## Real play: a full memory budget (~2500 tokens) and a crowded world. The prompt is sized, not cut
func _test_budget_with_heavy_memory(builder) -> void:
	var budget_chars = builder.get_prompt_token_budget() * builder.CHARS_PER_TOKEN
	var pinned = ["PINNED: the stranger pulled Elena from the river on the second night."]
	var important = []
	var relevant = []
	for i in 40:
		important.append("IMPORTANT %d: the stranger said something about the tithe that stayed with you, word for word, long after." % i)
		relevant.append("RELEVANT %d: the stranger bought bread and asked after the mill road, idly, by the fire." % i)
	var flags = {}
	for i in 120:
		flags["test_world_flag_number_%d" % i] = true
	var personality = load("res://resources/npc_personalities/gregor_merchant.tres")
	var npc_id = registry.get_npc_id("gregor")
	var context = builder.build_context({"personality": personality, "npc_id": npc_id,
		"tiered_memories": {"pinned": pinned, "important": important, "relevant": relevant},
		"relationship_dimensions": {"trust": 10, "respect": 5, "affection": 5, "fear": 0, "familiarity": 20, "memory_count": 81},
		"world_state": {"npc_id": npc_id, "world_flags": flags, "active_quests": []}, "conversation_history": [], "player_input": "What news?"})
	var system: String = context.system_prompt
	print("    heavy memory: %d chars of a %d budget" % [system.length(), budget_chars])
	_check("Heavy memory: the system prompt stays within the budget", system.length() <= budget_chars)
	_check("Heavy memory: the response format still opens the prompt", system.begins_with(builder._build_response_format_section()))
	_check("Heavy memory: the storyline/agency block survives whole", builder._build_storyline_section(npc_id) in system)
	_check("Heavy memory: the pinned memory survives", "PINNED:" in system)
	_check("Heavy memory: important memories come before relevant ones", "IMPORTANT 0:" in system and ("RELEVANT 0:" not in system or system.find("IMPORTANT 0:") < system.find("RELEVANT 0:")))
	var memory_chars = 0
	for line in system.split("\n"):
		if line.begins_with("- IMPORTANT ") or line.begins_with("- RELEVANT ") or line.begins_with("- PINNED"):
			memory_chars += line.length() + 1
	print("    heavy memory: %d chars of memories kept" % memory_chars)
	_check("Heavy memory: memories get at least their guaranteed share", memory_chars >= builder.MIN_MEMORY_TOKENS * builder.CHARS_PER_TOKEN - 300)
	_check("Heavy memory: memories are kept ahead of the world flag list", memory_chars > system.count("Test World Flag Number") * 30)
	_check("Heavy memory: the world state keeps a little room", "## " in system.substr(system.find("PINNED:")) and system.count("Test World Flag Number") > 0)
	_check("ClaudeClient's backstop sits above the budget", int(builder.get_prompt_token_budget() * 4 * 1.25) > budget_chars)
	_check("Heavy memory: nothing is cut mid-line", system.ends_with("\n"))
