extends SceneTree

# Tests what violence costs the player (docs/PLAYER_SYSTEMS.md §1.2, §1.4, §3, §7):
# - children: the player can strike one (Combat.can_target / can_target_node for player attackers);
#   the deed carries victim_minor and the heaviest weight in the game, for every party that knows it
# - "anyone sees": line-of-sight witnesses. "Somehow knows": the child who lives tells their own
#   people; a body nobody saw is found later by whoever comes to that place (a rumour, unless the
#   stranger was seen there about then), while the world is open; then gossip as usual
# - a struck child runs or screams (CombatAI); grown-ups who hear decide by soul (Oskar's harm:rook
#   Line keeps him from running); nobody is offered a fight with a child, nor an emergent harm of one
# - self-defence: Combat remembers who struck first; the player's blow back is self_defence, weighed
#   far lower only by those who saw the first blow (or heard it told well); a defender of the
#   player's victim did not start it
# - the law answers by soul where it keeps the peace: Aldric's watch (now kills too), Renna's rangers
#   where she rides, Lucan's garrison at Ashguard, the crown's soldiers in the Capitol; never while
#   the world is closed (opening hours)
# - epilogue weighs harm to a child heaviest, self-defence not at all; traces save and load
# No API calls, nothing reaches ./chroma, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_violence_consequences.gd

const AI = preload("res://scripts/combat/combat_ai.gd")
const Rep = preload("res://scripts/world_state/reputation.gd")
const EpilogueScript = preload("res://scripts/storyline/epilogue.gd")
const DAY = 24 * 60

class FakeStats extends RefCounted:
	var stamina: float = 100.0
	var health: float = 100.0
	func get_stamina() -> float:
		return stamina
	func spend_stamina(amount: float) -> bool:
		if stamina < amount:
			return false
		stamina -= amount
		return true
	func get_skill(_skill: String) -> float:
		return 0.0
	func use_skill(_skill: String, _d: float = 1.0, _c: Dictionary = {}) -> Dictionary:
		return {"gained": 0.0, "level": 0.0, "milestone": 0}
	func damage(amount: float, _type: String = "blunt", _source: String = "") -> Dictionary:
		health -= amount
		return {"health": health, "staggered": false, "dead": health <= 0.0}

class FakeInventory extends RefCounted:
	var equipped: Dictionary = {}
	func get_equipped(slot: String) -> Dictionary:
		return equipped.get(slot, {}).duplicate(true)
	func wear(_slot: String, _amount: float = 1.0) -> Dictionary:
		return {"broke": false}
	func has(_item_id: String, _qty: int = 1) -> bool:
		return true
	func remove(_item_id: String, _qty: int = 1) -> bool:
		return true

class FakePlayer extends Node2D:
	var is_alive: bool = true
	var facing: Vector2 = Vector2.RIGHT
	func get_facing_vector() -> Vector2:
		return facing

class FakeBody extends StaticBody2D:
	var npc_id: String = ""
	var npc_name: String = ""
	var is_alive: bool = true
	var facing: Vector2 = Vector2.LEFT
	var combat_side: String = ""
	var profile: Dictionary = {"weapon": "short_sword"}
	func get_combat_profile() -> Dictionary:
		return profile

var failures: int = 0
var world_state: Node
var director: Node
var registry: Node
var pe: Node
var combat: Node
var propagator: Node
var gm: Node
var em
var scene: Node2D
var BaseNPCScript
var saved_flags: Dictionary
var saved_states: Dictionary
var saved_minutes: int
var saved_pe: Dictionary
var saved_gm: Dictionary
var saved_propagation: Dictionary
var save_existed: bool
var real_capture = null

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	pe = root.get_node("PlayerEvents")
	combat = root.get_node("Combat")
	propagator = root.get_node("EventPropagator")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_pe = pe.save()
	saved_gm = gm.save() if gm else {}
	saved_propagation = propagator.save()
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	world_state.set_idle_clock_rate(0.0)
	real_capture = pe.capture_enabled
	pe.capture_enabled = false
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.end_on_season_end = false
	director.set_player_events(null)
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	if gm:
		gm.register_all_souls()
	director.load_emergence("res://resources/emergence")
	em = director.get_emergence()

	print("============================================================")
	print("🧪 VIOLENCE CONSEQUENCES TEST")
	print("============================================================\n")

	_test_weights()
	await _test_child_targeting()
	_test_child_tells()
	_test_body_found_later()
	await _test_child_ai()
	await _test_cry_for_help()
	await _test_self_defence()
	await _test_the_law()
	_test_epilogue_and_save()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================

func _test_weights():
	print("Reputation: a child is the heaviest weight in the game")
	_reset()
	var heaviest = 0.0
	for k in Rep.KIND_WEIGHTS:
		heaviest = minf(heaviest, float(Rep.KIND_WEIGHTS[k]))
	heaviest = minf(heaviest, minf(Rep.PROMISE_BROKEN, Rep.LIE_EXPOSED))
	_check("Killing a child weighs more than anything else (%.0f vs %.0f)" % [Rep.MINOR_KILL, heaviest], Rep.MINOR_KILL < heaviest * 3.0)
	_check("Even harming a child weighs well beyond killing a grown man", Rep.MINOR_HARM < Rep.KIND_WEIGHTS.kill * 1.5)
	_check("Self-defence weighs far less than the plain deed", absf(Rep.SELF_DEFENCE_HARM) * 4.0 <= absf(Rep.KIND_WEIGHTS.harm) and absf(Rep.SELF_DEFENCE_KILL) * 3.0 <= absf(Rep.KIND_WEIGHTS.kill))
	var child = _record("harm", "struck Rook across the face", ["rook"], ["gen_dockhand_1"], "capitol_docks")
	_check("victim_minor is found from `about` when the caller does not say", pe.get_event(child).get("victim_minor", false))
	var adult = _record("kill", "killed Hollis in the Guildhall", ["hollis"], ["gen_clerk_1"], "capitol_guildhall")
	_check("...and not for a grown man", not pe.get_event(adult).get("victim_minor", false))
	var saw_child = Rep.of("npc", "gen_dockhand_1")
	var saw_kill = Rep.of("npc", "gen_clerk_1")
	_check("One who saw a child struck thinks worse of the stranger (%.0f) than one who saw a man killed (%.0f)" % [saw_child, saw_kill], saw_child < saw_kill and saw_child <= -80.0)
	_check("Nobody who does not know it holds it against them", Rep.of("npc", "gen_miner_1") == 0.0)
	_check("The gossip names the child", "only a child" in str(pe.known_by("gen_dockhand_1")[0].text))

func _test_child_targeting():
	print("\nCombat: the player can strike a child; the deed says so")
	_reset()
	var player = await _fresh_scene()
	var rook = _body(registry.get_npc_id("rook"), Vector2(30, 0), "Rook")
	var onlooker = _body("gen_dockhand_2", Vector2(30, -150), "a dockhand")
	await _settle()
	_check("can_target_node(rook, player) yes; for anyone else no", combat.can_target_node(rook, player) and not combat.can_target_node(rook, onlooker) and not combat.can_target_node(rook))
	var r = combat.attack(onlooker, rook, "light")
	_check("An NPC's blow at a child is refused", r.get("refused", "") == "minor")
	r = combat.attack(player, null, "light")
	var harm = _last("harm")
	_check("The player's blow lands", r.get("damage", 0.0) > 0.0)
	_check("...harm about Rook, victim_minor, seen by the dockhand in sight", harm.get("victim_minor", false) and "rook" in harm.about and "gen_dockhand_2" in harm.witnesses)
	_check("...and no self-defence (a child never strikes first)", not harm.get("self_defence", false))
	_check("The dockhand's view of the stranger falls hard (%.0f)" % Rep.of("npc", "gen_dockhand_2"), Rep.of("npc", "gen_dockhand_2") <= -80.0)

func _test_child_tells():
	print("\nThe child who lives tells their own people")
	_reset()
	var urchins = Rep.faction_members("the_warrens").filter(func(w): return w != "rook")
	_check("The Warrens have their own (%d urchins)" % urchins.size(), not urchins.is_empty())
	var id = _record("harm", "cuffed Rook in a back alley", ["rook"], ["rook"], "capitol_warrens")
	var ev = pe.get_event(id)
	var told = urchins.filter(func(u): return ev.heard_by.has(u) and str(ev.heard_by[u].via) == pe.CHILD_TOLD_VIA)
	var flying = pe.in_flight.filter(func(i): return str(i.event) == id and str(i.via) == pe.CHILD_TOLD_VIA)
	_check("Rook tells the Warrens himself (%d heard, %d on the way)" % [told.size(), flying.size()], told.size() + flying.size() >= 1)
	_check("...so the Warrens think the worst of the stranger (%.0f)" % Rep.of("faction", "the_warrens"), Rep.of("faction", "the_warrens") <= -90.0)
	_reset()
	world_state.register_npc_death(registry.get_npc_id("rook"), {"cause": "test"})
	id = _record("harm", "struck Rook down", ["rook"], ["rook"], "capitol_warrens")
	_check("A dead child tells nobody", pe.get_event(id).heard_by.is_empty() and pe.in_flight.is_empty())

func _test_body_found_later():
	print("\nA body nobody saw is found later, by whoever comes")
	_reset()
	var t0 = DAY + 9 * 60
	world_state.game_minutes = t0
	world_state.register_npc_death(registry.get_npc_id("varn"), {"cause": "test"})
	var id = pe.record("kill", "killed Varn on the forest path", ["varn"], {"witnesses": [], "location": "forest_path"})
	_check("A kill with no witness leaves a trace", pe.traces.any(func(t): return str(t.event) == id))
	world_state.set_npc_location(registry.get_npc_id("bjorn"), "forest_path")
	world_state.game_minutes = t0 + 10
	_check("Nobody finds it in the first minutes", pe.check_traces().is_empty() and not pe.get_event(id).heard_by.has("bjorn"))
	world_state.game_minutes = t0 + 60
	_check("Bjorn, who comes that way, finds it", id in pe.check_traces() and pe.get_event(id).heard_by.has("bjorn"))
	var h = pe.get_event(id).heard_by.get("bjorn", {})
	_check("...a rumour only: nothing says who (%.2f)" % float(h.get("fidelity", 0)), float(h.get("fidelity", 1.0)) < pe.ANON_BELOW and h.get("found", false))
	_check("...so it costs the stranger nothing with him", Rep.of("npc", "bjorn") == 0.0)
	_check("The trace is gone once found", not pe.traces.any(func(t): return str(t.event) == id))

	print("\n...and a child's body, where the stranger was seen, at night and by day")
	_reset()
	var night = DAY * 2 + 2 * 60
	world_state.game_minutes = night - 90
	pe.record("seen_at", "was seen on the docks", [], {"witnesses": ["gen_dockhand_3"], "location": "capitol_docks", "spread": false})
	world_state.game_minutes = night
	world_state.register_npc_death(registry.get_npc_id("rook"), {"cause": "test"})
	id = pe.record("kill", "killed Rook on the docks", ["rook"], {"witnesses": [], "location": "capitol_docks"})
	world_state.set_npc_location(registry.get_npc_id("oskar"), "capitol_docks")
	world_state.game_minutes = night + 60
	_check("While the world is closed (03:00) nobody comes upon it", pe.check_traces().is_empty())
	world_state.game_minutes = DAY * 2 + 7 * 60
	_check("At opening Oskar comes and finds the boy", id in pe.check_traces() and pe.get_event(id).heard_by.has("oskar"))
	h = pe.get_event(id).heard_by.get("oskar", {})
	_check("...and since the stranger was seen there about then, it is pinned on them (%.2f)" % float(h.get("fidelity", 0)), float(h.get("fidelity", 0)) >= pe.ANON_BELOW)
	_check("...the heaviest cost with him (%.0f)" % Rep.of("npc", "oskar"), Rep.of("npc", "oskar") <= -70.0)
	_check("...and the word goes round from the finder", not pe.in_flight.filter(func(i): return str(i.event) == id).is_empty() or pe.get_event(id).heard_by.size() > 1)

func _test_child_ai():
	print("\nCombatAI: a struck child runs or screams; grown-ups decide by soul")
	var hook = AI.build_hook("rook", {"kind": "attacked", "attacker": "player"}, 90)
	var actions = hook.options.map(func(o): return o.action)
	_check("Rook's options are run or scream, both crying out (%s)" % [actions], actions.size() == 2 and "flee" in actions and "call_for_help" in actions and hook.options.all(func(o): return o.get("cry", false)))
	var d = await AI.decide_full("rook", {"kind": "attacked", "attacker": "player"})
	_check("Rook chooses one of them (%s) and cries out" % d.action, d.action in ["flee", "call_for_help"] and d.cry)
	_check("A child with no soul runs", AI.fallback_action({"kind": "attacked"}, 90.0, "rook") == "flee")
	var w = AI.build_hook("hollis", {"kind": "witness", "attacker": "player", "victim": "rook"}, 90)
	_check("Nobody is offered to join in against a child", w.options.all(func(o): return o.get("side", "") != "join"))
	_check("...the soul is told it is a child", "a child" in str(w.situation))
	_check("A child struck steadies a grown onlooker", AI.morale_for("hollis", {"kind": "witness", "attacker": "player", "victim": "rook"}) > AI.morale_for("hollis", {"kind": "witness", "attacker": "player", "victim": "corwin"}))
	director.relationship_dims_override = {"oskar": {"fear": 90}, "hollis": {"fear": 90}}
	var oskar = await AI.decide_full("oskar", {"kind": "witness", "attacker": "player", "victim": "rook", "morale": 10})
	var hollis = await AI.decide_full("hollis", {"kind": "witness", "attacker": "player", "victim": "rook", "morale": 10})
	_check("Afraid, Oskar still will not run and leave Rook to it (harm:rook) -> %s" % oskar.action, oskar.action != "flee")
	_check("...Hollis, afraid and bound to nobody, gets away (%s)" % hollis.action, hollis.action == "flee")
	director.relationship_dims_override = {}
	_check("NPC targeting stays closed: CombatAI.can_target('rook') false, for the player true", not AI.can_target("rook") and AI.can_target("rook", "player"))

func _test_cry_for_help():
	print("\nA child's scream carries round a wall")
	_reset()
	await _fresh_scene()
	var player = scene.get_node("Player")
	var rook = _npc("rook", Vector2(40, 0))
	var hollis = _npc("hollis", Vector2(40, 400))
	scene.add_child(_wall(Vector2(40, 200), Vector2(600, 20)))
	await _settle()
	_check("Hollis cannot see Rook (a wall)", not registry.get_npc_id("hollis") in AI.Witnesses.in_sight(scene, rook.global_position))
	rook.take_hit({"damage": 10.0, "type": "blunt", "staggered": false, "killed": false}, player)
	for i in 6:
		await process_frame
	_check("Rook runs or screams (%s)" % rook.combat_state, rook.combat_state in ["flee", "call_for_help"])
	var hd: Dictionary = hollis.last_combat_decision
	_check("Hollis heard and decided by his own soul (%s)" % str(hd.get("action", "-")), str(hd.get("hook", {}).get("id", "")) == "combat_witness" and str(hd.get("action", "")) in AI.ACTIONS)
	_check("...never to join in against the child", str(hd.get("side", "")) != "join")
	rook.end_fight("over", false)
	hollis.end_fight("over", false)

func _test_self_defence():
	print("\nSelf-defence: who struck first, and who saw it")
	_reset()
	var player = await _fresh_scene()
	var varn = _body(registry.get_npc_id("varn"), Vector2(40, 0), "Varn")
	var saw_first = _body("test_saw_first", Vector2(40, -150), "an onlooker")
	await _settle()
	var r = combat.attack(varn, player, "light")
	_check("Varn strikes the player first", r.get("damage", 0.0) > 0.0 and combat.first_strike(varn, player).get("by", "") == registry.get_npc_id("varn"))
	_check("...seen by the onlooker", "test_saw_first" in combat.first_strike(varn, player).get("seen_by", []))
	var came_late = _body("test_came_late", Vector2(40, 150), "a latecomer")
	await _settle()
	_tick(1.0)
	r = combat.attack(player, null, "light")
	var harm = _last("harm")
	_check("The player strikes back: harm marked self_defence", r.get("damage", 0.0) > 0.0 and harm.get("self_defence", false))
	_check("...known to the one who saw the first blow and to Varn, not to the latecomer",
		"test_saw_first" in harm.get("self_defence_known", []) and "varn" in harm.get("self_defence_known", []) and not "test_came_late" in harm.get("self_defence_known", []))
	_check("...both saw the player's blow", "test_saw_first" in harm.witnesses and "test_came_late" in harm.witnesses)
	var first_view = Rep.breakdown("npc", "test_saw_first")
	var late_view = Rep.breakdown("npc", "test_came_late")
	_check("Who saw it all weighs it far lower (%.1f vs %.1f)" % [first_view.raw, late_view.raw], first_view.raw > late_view.raw and first_view.raw >= Rep.SELF_DEFENCE_HARM - 0.01)
	_check("...and remembers who started it", "went for them first" in str(pe.known_by("test_saw_first")[0].text) and not "went for them first" in str(pe.known_by("test_came_late")[0].text))
	var ended: Array = []
	combat.fight_ended.connect(func(info): ended.append(info))
	combat.end_fight(player, varn, "parted")
	_check("fight_ended names the aggressor", ended.size() == 1 and ended[0].get("aggressor", "") == registry.get_npc_id("varn"))

	print("\n...it travels only when told well")
	var sd_id = str(harm.id)
	world_state.set_npc_location(registry.get_npc_id("varn"), "capitol_market")
	var spread = pe.spread(sd_id, ["hollis"], "test")
	var item = pe.in_flight.filter(func(i): return str(i.event) == sd_id and str(i.to) == "hollis")
	var told = item[0].get("self_defence", false) if not item.is_empty() else bool(pe.get_event(sd_id).heard_by.get("hollis", {}).get("self_defence", false))
	_check("Varn's telling carries who struck first (fidelity %.2f)" % (float(spread.scheduled[0].fidelity) if not spread.scheduled.is_empty() else 0.0), not spread.scheduled.is_empty() and told)

	print("\n...the player who starts it gets none of this")
	_reset()
	player = await _fresh_scene()
	varn = _body(registry.get_npc_id("varn"), Vector2(40, 0), "Varn")
	await _settle()
	combat.attack(player, null, "light")
	_check("The player struck first: no self_defence", not _last("harm").get("self_defence", false))
	_tick(1.0)
	var defender = _body("test_defender", Vector2(-40, 0), "a defender")
	defender.combat_side = "defend"
	defender.facing = Vector2.RIGHT
	await _settle()
	combat.attack(defender, player, "light")
	_check("Someone standing up for the player's victim did not start it", combat.first_strike(defender, player).get("by", "") == "player")
	_tick(1.0)
	player.facing = Vector2.LEFT
	combat.attack(player, defender, "light")
	_check("...so striking them is no self-defence either", not combat.self_defence_opts(player, defender).get("self_defence", false))

func _test_the_law():
	print("\nThe law answers where it keeps the peace, by soul")
	_reset()
	world_state.game_minutes = DAY + 10 * 60
	var id = _record("kill", "killed a farmer in the square", ["gen_valley_farmer_1"], ["aldric"], "thornhaven_town_square")
	var inst = _instance("the_watch_answers", id)
	_check("Aldric's watch answers a killing too", inst.get("roles", {}).get("keeper", "") == "aldric")

	_reset()
	world_state.game_minutes = DAY + 10 * 60
	id = _record("harm", "knocked a hawker down in the market", ["gen_street_hawker_1"], ["renna"], "capitol_market")
	inst = _instance("the_rangers_answer", id)
	_check("Renna, in the Capitol where it happened, answers it", inst.get("roles", {}).get("keeper", "") == "renna")
	var made = await _decide(inst)
	_check("...by her own soul (%s)" % made.get("renna", {}).get("choice", "-"), made.has("renna") and made.renna.choice != "pass")
	_reset()  # a fresh world each time: templates keep a cooldown
	world_state.set_npc_location(registry.get_npc_id("renna"), "capitol_gate")
	id = _record("harm", "struck a woodcutter on the forest path", ["gen_woodcutter_1"], ["renna"], "forest_path")
	_check("The Rangers do not answer where Renna is not riding", _instance("the_rangers_answer", id).is_empty())
	_reset()
	world_state.set_npc_location(registry.get_npc_id("renna"), "village_gate")
	id = _record("harm", "struck a woodcutter by the gate", ["gen_woodcutter_1"], ["renna"], "forest_path")
	_check("...and do once she rides the valley", _instance("the_rangers_answer", id).get("roles", {}).get("keeper", "") == "renna")

	_reset()
	world_state.game_minutes = DAY + 10 * 60
	id = _record("harm", "struck a soldier at the fort gate", [], ["lucan"], "fort_ashguard")
	inst = _instance("the_garrison_answers", id)
	_check("Lucan's garrison answers at Fort Ashguard", inst.get("roles", {}).get("keeper", "") == "lucan")
	made = await _decide(inst)
	_check("...by Lucan's soul (%s)" % made.get("lucan", {}).get("choice", "-"), made.has("lucan") and made.lucan.choice != "pass")
	_clean(made)
	_reset()
	id = _record("harm", "struck a miner in the Pit", [], ["lucan"], "the_pit")
	_check("...not down the Pit, which is not the fort's to keep", _instance("the_garrison_answers", id).is_empty())

	var soldier = _capitol_soldier()
	_check("A crown soldier stands the Dawn Gate (%s)" % soldier, soldier != "")
	_reset()
	world_state.game_minutes = DAY + 10 * 60
	id = _record("harm", "struck a pilgrim at the Dawn Gate", [], [soldier], "capitol_gate")
	inst = _instance("the_capitol_watch_answers", id)
	_check("The Capitol's watch answers inside the walls", inst.get("roles", {}).get("keeper", "") == soldier)
	made = await _decide(inst)
	_clean(made)
	_reset()
	id = _record("harm", "struck a miner at Greystone", [], [soldier], "greystone_mines")
	_check("...not out on the march", _instance("the_capitol_watch_answers", id).is_empty())

	print("\n...no keeper is offered to side against a child")
	_reset()
	world_state.game_minutes = DAY + 10 * 60
	id = _record("harm", "struck Rook at the Dawn Gate", ["rook"], [soldier], "capitol_gate")
	inst = _instance("the_capitol_watch_answers", id)
	var hook = em.resolved_hook(inst, "keeping_the_peace") if not inst.is_empty() else {}
	_check("It grows (keeper %s)" % inst.get("roles", {}).get("keeper", "-"), not inst.is_empty())
	_check("...and 'take their side' (harming Rook) is not on the table", not hook.is_empty() and hook.options.all(func(o): return o.id != "take_their_side"))

	print("\n...and nobody answers while the world is closed")
	_reset()
	world_state.game_minutes = DAY * 3 + 3 * 60
	id = _record("harm", "struck a soldier at the fort gate at night", [], ["lucan"], "fort_ashguard")
	inst = _instance("the_garrison_answers", id)
	await director.advance_round("test")
	var at_night = director.get_chronicle(0).filter(func(e): return e.get("emergent", "") == inst.get("id", "-") and e.choice not in ["instantiated"])
	_check("At 03:00 the beat waits (%d decisions)" % at_night.size(), not inst.is_empty() and at_night.is_empty())
	world_state.game_minutes = DAY * 3 + 7 * 60
	made = await _decide(inst)
	_check("At opening Lucan answers", made.has("lucan"))

func _test_epilogue_and_save():
	print("\nEpilogue and save")
	_check("Harm to a child counts three times against an intention", EpilogueScript._deed_sign({"kind": "harm", "victim_minor": true}) == -3)
	_check("Self-defence counts nothing against it", EpilogueScript._deed_sign({"kind": "harm", "self_defence": true}) == 0)
	_check("A plain harm counts once", EpilogueScript._deed_sign({"kind": "harm"}) == -1)
	_reset()
	var id = pe.record("kill", "killed Hollis in an alley", ["hollis"], {"witnesses": [], "location": "capitol_docks"})
	var data = pe.save()
	pe.reset()
	pe.load_from_dict(data)
	_check("Unfound bodies save and load", pe.traces.size() == 1 and str(pe.traces[0].event) == id)

# =============================================================================

func _reset() -> void:
	world_state.world_flags = {}
	world_state.npc_states = {}
	world_state.load_calendar()
	world_state.reset_calendar(world_state.start_minute)
	world_state.game_minutes = DAY + 10 * 60
	director.reset_state()
	em.reset()
	pe.reset()
	pe.now_override = -1
	combat.reset()
	director.player_location_override = ""
	director.relationship_dims_override = {}

func _record(kind: String, summary: String, about: Array, witnesses: Array, location: String) -> String:
	director.player_location_override = location
	var ids: Array = witnesses.map(func(w): return director._npc_id(w))
	return pe.record(kind, summary, about.map(func(a): return director._npc_id(a)), {"witnesses": ids, "location": location, "spread": false})

func _last(kind: String) -> Dictionary:
	for i in range(pe.order.size() - 1, -1, -1):
		if pe.events[pe.order[i]].kind == kind:
			return pe.events[pe.order[i]].duplicate(true)
	return {}

func _instance(tid: String, event_id: String) -> Dictionary:
	for inst in director.get_emergent_instances():
		if inst.template == tid and inst.event_id == event_id:
			return inst
	return {}

func _decide(inst: Dictionary) -> Dictionary:
	var made: Dictionary = {}
	if inst.is_empty():
		_check("(no instance to decide)", false)
		return made
	for r in 4:
		await director.advance_round("test")
	for e in director.get_chronicle(0):
		if e.get("mode", "") == "emergent" and e.get("emergent", "") == inst.id and e.choice not in ["instantiated", "resolved", "expired"]:
			made[e.npc] = e
			print("    %s/%s: %s (%s)" % [e.npc, e.hook, e.choice, e.reason])
	return made

func _clean(made: Dictionary) -> void:
	var dropped: Array = []
	for k in made:
		for d in made[k].get("dropped", []):
			dropped.append("%s: %s" % [k, d.get("reason", "")])
	_check("...nothing dropped by Agency or Lines%s" % ("" if dropped.is_empty() else " %s" % [dropped]), dropped.is_empty())

func _capitol_soldier() -> String:
	if gm == null:
		return ""
	for gid in gm.get_ids():
		var inst = gm.get_instance(gid)
		if inst and str(inst.archetype_id) == "garrison_soldier" and str(inst.region) == "the_capitol" and director.has_soul(gid):
			return gid
	return ""

func _fresh_scene() -> FakePlayer:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = Node2D.new()
	scene.name = "ViolenceTestScene"
	root.add_child(scene)
	combat.stats_provider = FakeStats.new()
	var inv = FakeInventory.new()
	inv.equipped = {"main_hand": {"id": "short_sword", "qty": 1, "quality": 50, "durability": 50.0, "max_durability": 50.0}}
	combat.inventory_provider = inv
	combat.reset()
	combat.set_test_clock(100.0)
	var p = FakePlayer.new()
	p.name = "Player"
	p.add_to_group("player")
	scene.add_child(p)
	return p

func _body(id: String, at: Vector2, name: String) -> FakeBody:
	var b = FakeBody.new()
	b.npc_id = id
	b.npc_name = name
	b.position = at
	b.collision_layer = 2
	b.collision_mask = 0
	b.add_to_group("npcs")
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	b.add_child(shape)
	scene.add_child(b)
	return b

func _npc(key: String, at: Vector2) -> CharacterBody2D:
	var n = BaseNPCScript.new()
	n.npc_id = registry.get_npc_id(key) if registry.has_npc(key) else key
	n.npc_name = key.capitalize()
	n.position = at
	n.add_to_group("npcs")
	scene.add_child(n)
	return n

func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var w = StaticBody2D.new()
	w.position = at
	w.collision_layer = 4
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	w.add_child(shape)
	return w

func _settle() -> void:
	await physics_frame
	await physics_frame

func _tick(seconds: float) -> void:
	combat.set_test_clock(combat.now() + seconds)

func _restore() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	combat.stats_provider = null
	combat.inventory_provider = null
	combat.set_test_clock(-1.0)
	combat.reset()
	director.relationship_dims_override = {}
	director.player_location_override = ""
	director.end_on_season_end = true
	director.reset_state()
	em.reset()
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	pe.load_from_dict(saved_pe)
	propagator.load_from_dict(saved_propagation)
	if gm:
		gm.load_from_dict(saved_gm)
		gm.register_all_souls()
	pe.capture_enabled = real_capture
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_states
	world_state.game_minutes = saved_minutes
	world_state.reset_calendar()
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
