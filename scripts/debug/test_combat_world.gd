extends SceneTree

# Tests combat in the world (docs/PLAYER_SYSTEMS.md §3 "Who fights" and "Endings"):
# - CombatAI.decide on real souls: Bjorn will not strike Elena (harm:elena), defends her when the
#   player does, and will not run and leave her to it; Aldric refuses a mob (his crowd Line); nobody
#   fights a child
# - NPC bodies: hits wound, stagger and lower morale; morale breaking ends in yielding, not death;
#   sparing records `spared`, killing records `kill` and the NPC is dead for the Director; the
#   player standing up for someone records `help`, running records `fled`; witnesses by line of sight
# - minors: Rook and a fixture archetype with `minor: true` (GenericManager.is_minor) cannot be hit
# - creatures: data, spawning by location, stalk / charge / flee when hurt, drops
# Fake hit results (Combat.resolve_hit's shape); no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_combat_world.gd

const AI = preload("res://scripts/combat/combat_ai.gd")
const CreatureScript = preload("res://scripts/combat/creature.gd")
const SpawnerScript = preload("res://scripts/combat/creature_spawner.gd")
const GenericManagerScript = preload("res://scripts/generics/generic_manager.gd")
const FIXTURE_ARCHETYPES = "res://scripts/debug/fixtures/combat_world/archetypes"

class FakePlayer extends Node2D:
	var is_alive: bool = true

var world_state: Node
var director: Node
var registry: Node
var pe: Node
var failures: int = 0
var scene: Node2D
var player: FakePlayer
var saved_flags: Dictionary
var saved_npc_states: Dictionary
var saved_minutes: int
var saved_pe: Dictionary
var save_existed: bool
var BaseNPCScript  # loaded at run time: base_npc.gd names autoloads, which a -s script cannot compile against

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	pe = root.get_node("PlayerEvents")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_npc_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_pe = pe.save()
	save_existed = FileAccess.file_exists(world_state.SAVE_PATH)
	BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	world_state.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	director.relationship_dims_override = {}
	print("============================================================")
	print("🧪 COMBAT IN THE WORLD TEST")
	print("============================================================\n")

	await _test_soul_decisions()
	await _test_generic_soul()
	_test_morale()
	_new_scene()
	await _test_yield_and_spare()
	await _test_kill()
	await _test_help_and_fled()
	await _test_minors()
	_test_creature_data_and_spawning()
	await _test_creature_behaviour()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# DECISIONS ON REAL SOULS
# =============================================================================

func _test_soul_decisions():
	print("Soul-driven decisions")
	var bjorn_struck = await AI.decide_full("bjorn", {"kind": "attacked", "attacker": "elena", "morale": 80})
	_check("Bjorn struck by Elena will not fight her (harm:elena) -> %s" % bjorn_struck.action, bjorn_struck.action != "fight" and bjorn_struck.action in AI.ACTIONS)
	var hollis_struck = await AI.decide_full("hollis", {"kind": "attacked", "attacker": "elena", "morale": 80})
	_check("...while Hollis, with no such Line, fights back", hollis_struck.action == "fight")

	var defend = await AI.decide_full("bjorn", {"kind": "witness", "attacker": "player", "victim": "elena"})
	_check("Bjorn seeing the player strike Elena stands up for her (%s/%s)" % [defend.action, defend.side], defend.action == "fight" and defend.side == "defend" and defend.foe == "player")
	director.relationship_dims_override = {"bjorn": {"fear": 60}, "hollis": {"fear": 60}}
	var afraid = await AI.decide_full("bjorn", {"kind": "witness", "attacker": "player", "victim": "elena"})
	_check("Afraid of the player, Bjorn still will not run and leave Elena to it (%s)" % afraid.action, afraid.action != "flee" and afraid.choice != "pass")
	var hollis_afraid = await AI.decide_full("hollis", {"kind": "witness", "attacker": "player", "victim": "elena"})
	_check("...Hollis, afraid and bound to nobody, gets away from it", hollis_afraid.action == "flee")
	director.relationship_dims_override = {"bjorn": {"affection": 80, "trust": 80}, "hollis": {"affection": 80, "trust": 80}}
	var hollis_joins = await AI.decide_full("hollis", {"kind": "witness", "attacker": "player", "victim": "elena", "morale": 90})
	_check("Hollis, fond of the player, joins in against Elena (%s/%s)" % [hollis_joins.action, hollis_joins.side], hollis_joins.side == "join")
	var join = await AI.decide_full("bjorn", {"kind": "witness", "attacker": "player", "victim": "elena", "morale": 90})
	_check("...even fond of the player, he does not side with them against Elena (%s/%s)" % [join.action, join.side], join.side != "join")
	director.relationship_dims_override = {}

	var aldric_mob = await AI.decide_full("aldric", {"kind": "crowd", "target": "varn", "morale": 80})
	_check("Aldric refuses to join a mob against Varn (crowd Line) -> %s" % aldric_mob.action, aldric_mob.action != "fight")
	var bjorn_mob = await AI.decide_full("bjorn", {"kind": "crowd", "target": "varn", "morale": 80})
	_check("...Bjorn, without that Line, lays hands on him", bjorn_mob.action == "fight" and bjorn_mob.side == "join")
	var mob_on_player = AI.build_hook("aldric", {"kind": "crowd", "target": "player"}, 80)
	_check("A mob's violence is marked crowd: true", mob_on_player.options.filter(func(o): return o.action == "fight").all(func(o): return o.get("crowd", false) == true))

	var child_hook = AI.build_hook("aldric", {"kind": "attacked", "attacker": "rook"}, 90)
	_check("Nobody is offered a fight with a child (Rook)", child_hook.options.all(func(o): return o.action != "fight"))
	var rook_hook = AI.build_hook("rook", {"kind": "attacked", "attacker": "player"}, 90)
	_check("...and a child is offered no fight at all", rook_hook.options.all(func(o): return o.action != "fight"))
	_check("A soul-less NPC falls back without fighting", (await AI.decide("nobody_at_all", {"kind": "attacked", "attacker": "player", "morale": 90})) != "fight")

	var broken = AI.build_hook("hollis", {"kind": "attacked", "attacker": "player"}, 10)
	_check("Broken morale takes fighting off the table", broken.options.all(func(o): return o.action != "fight") and broken.options[0].id == "yield")
	var steady = AI.build_hook("hollis", {"kind": "attacked", "attacker": "player"}, 80)
	_check("Steady morale does not think of yielding", steady.options.all(func(o): return o.action != "yield"))
	director.relationship_dims_override = {"hollis": {"affection": 70, "trust": 60}}
	_check("A friend of the player tries words first", (await AI.decide("hollis", {"kind": "attacked", "attacker": "player", "morale": 80})) == "talk")
	director.relationship_dims_override = {}

## A generic soul with harm:elena (valley farmer, valley widow) decides like a main soul
func _test_generic_soul():
	var generics = root.get_node("DynamicNPCRegistry").generics
	var gen = ""
	for id in generics.get_ids():
		var soul = director.get_soul(id)
		if soul and soul._forbidding_rule("harm:elena") != "":
			gen = id
			break
	if gen == "":
		_check("A generic with harm:elena exists", false)
		return
	director.relationship_dims_override = {gen: {"fear": 60}}
	var d = await AI.decide_full(gen, {"kind": "witness", "attacker": "player", "victim": "elena"})
	_check("Generic %s will not run and leave Elena to the player (%s)" % [gen, d.action], d.action != "flee" and d.choice != "pass")
	director.relationship_dims_override = {}

func _test_morale():
	print("\nMorale")
	var calm = AI.morale_for("hollis", {"kind": "attacked", "attacker": "player"})
	director.relationship_dims_override = {"hollis": {"fear": 80}}
	var feared = AI.morale_for("hollis", {"kind": "attacked", "attacker": "player"})
	director.relationship_dims_override = {}
	_check("Fear of the player lowers morale (%.0f -> %.0f)" % [calm, feared], feared < calm)
	_check("Wounds lower it", AI.morale_for("hollis", {"kind": "attacked", "attacker": "player", "health_fraction": 0.3}) < calm)
	_check("Allies down lower it", AI.morale_for("hollis", {"kind": "attacked", "attacker": "player", "allies_down": 2}) < calm)
	_check("Standing over someone they will not let be harmed raises it",
		AI.morale_for("bjorn", {"kind": "witness", "attacker": "player", "victim": "elena"}) > AI.morale_for("bjorn", {"kind": "witness", "attacker": "player", "victim": "hollis"}))
	_check("The soul's resolve counts (Aldric's wants are worth a fight)", AI.resolve("aldric") > 0.0)

# =============================================================================
# BODIES AND ENDINGS
# =============================================================================

func _new_scene():
	scene = Node2D.new()
	scene.name = "CombatTestScene"
	root.add_child(scene)
	player = FakePlayer.new()
	player.name = "Player"
	player.add_to_group("player")
	scene.add_child(player)

func _body(key: String, at: Vector2) -> CharacterBody2D:
	var n = BaseNPCScript.new()
	n.npc_id = registry.get_npc_id(key) if registry.has_npc(key) else key
	n.npc_name = key.capitalize()
	n.position = at
	n.add_to_group("npcs")
	scene.add_child(n)
	return n

func _events(kind: String, about: String) -> Array:
	return pe.order.filter(func(id): return pe.events[id].kind == kind and about in pe.events[id].about).map(func(id): return pe.events[id])

func _hit(damage: float, extra: Dictionary = {}) -> Dictionary:
	var r = {"damage": damage, "type": "cut", "staggered": false, "killed": false}
	r.merge(extra, true)
	return r

func _test_yield_and_spare():
	print("\nYielding and sparing")
	var hollis = _body("hollis", Vector2(40, 0))
	var onlooker = _body("wren", Vector2(-200, 60))
	await physics_frame
	var first = hollis.take_hit(_hit(10, {"staggered": true}), player)
	await process_frame
	_check("A hit wounds and staggers (health %.0f)" % first.health, first.health == 90.0 and hollis.is_staggered())
	_check("Steady, Hollis fights back (%s)" % hollis.combat_state, hollis.combat_state == "fight")
	var harms = _events("harm", "hollis")
	_check("Wounding him is one harm deed, seen by Wren (line of sight)", harms.size() == 1 and registry.get_npc_id("wren") in harms[0].witnesses)
	_check("Wren, seeing it, made her own choice (%s)" % onlooker.combat_state, onlooker.combat_state in AI.ACTIONS)
	var states: Array = []
	for i in 6:
		hollis.take_hit(_hit(12), player)
		await process_frame
		states.append(hollis.combat_state)
		if hollis.combat_state == "yield":
			break
	_check("Morale breaks into yielding before death (%s, health %.0f, morale %.0f)" % [states, hollis.health, hollis.morale], hollis.combat_state == "yield" and hollis.is_alive)
	_check("...still one harm deed for the whole fight", _events("harm", "hollis").size() == 1)
	_check("A fight against someone who has not yielded cannot be 'spared'", not onlooker.spare(player) or onlooker.combat_state == "")
	_check("Letting him go records spared", hollis.spare(player) and _events("spared", "hollis").size() == 1)
	_check("...witnessed by Wren, and the fight is over", registry.get_npc_id("wren") in _events("spared", "hollis")[0].witnesses and hollis.combat_state == "")

	# Left unhit long enough, a yielded person has been let go
	var mira = _body("mira", Vector2(60, 40))
	director.relationship_dims_override = {"mira": {"fear": 90}}
	mira.take_hit(_hit(30), player)
	await process_frame
	director.relationship_dims_override = {}
	_check("Mira, terrified, yields at once (%s)" % mira.combat_state, mira.combat_state == "yield")
	mira._fight.last_hit_ms = Time.get_ticks_msec() - mira.SPARE_MS - 10
	mira.combat_tick(0.1)
	_check("...and walking away from her records spared", _events("spared", "mira").size() == 1 and mira.combat_state == "")
	for n in [hollis, onlooker, mira]:
		n.queue_free()
	await process_frame

func _test_kill():
	print("\nKilling")
	var corwin = _body("corwin", Vector2(30, 0))
	var onlooker = _body("oskar", Vector2(0, -150))
	await physics_frame
	var r = corwin.take_hit(_hit(500, {"killed": true}), player)
	await process_frame
	var kills = _events("kill", "corwin")
	_check("A killing blow kills (%s)" % r, r.get("dead", false) and not corwin.is_alive)
	_check("...records kill about Corwin, witnessed by Oskar", kills.size() == 1 and registry.get_npc_id("oskar") in kills[0].witnesses)
	_check("...and he is dead for WorldState and the Director", not world_state.is_npc_alive(registry.get_npc_id("corwin")) and not director._is_npc_alive("corwin"))
	_check("The dead cannot be hit again", corwin.take_hit(_hit(5), player).get("refused", false))
	var lucan = _body("lucan", Vector2(30, 30))
	lucan.take_hit(_hit(150), player)
	_check("Health run out is death too, by any adult", not lucan.is_alive and not director._is_npc_alive("lucan"))
	for n in [corwin, onlooker, lucan]:
		n.queue_free()
	await process_frame

func _test_help_and_fled():
	print("\nHelp and flight")
	var varn = _body("varn", Vector2(60, 0))
	var elena = _body("elena", Vector2(90, 0))
	await physics_frame
	varn._fight = {"foe_key": "elena", "band": "steady", "harm_recorded": false, "help_recorded": false, "last_hit_ms": Time.get_ticks_msec()}
	varn._set_combat_state({"action": "fight", "side": ""}, elena)
	varn.take_hit(_hit(5), player)
	await process_frame
	var helps = _events("help", "elena")
	_check("Striking Varn while he fights Elena records help about her", helps.size() == 1 and "elena" in helps[0].about)
	_check("...and harm about Varn", _events("harm", "varn").size() == 1)

	var dagna = _body("dagna", Vector2(30, 0))
	dagna._fight = {"foe_key": "player", "band": "steady", "harm_recorded": true, "help_recorded": false, "last_hit_ms": Time.get_ticks_msec()}
	dagna._set_combat_state({"action": "fight", "side": ""}, player)
	player.position = Vector2(2000, 0)
	dagna.combat_tick(0.1)
	_check("The player running from someone still fighting records fled", _events("fled", "dagna").size() == 1 and dagna.combat_state == "")
	player.position = Vector2.ZERO
	var d = AI.record_fled(["creature:wolf"], scene, Vector2.ZERO)
	_check("Running from a wolf is fled too, about nobody", d != "" and pe.events[d].about.is_empty())
	for n in [varn, elena, dagna]:
		n.queue_free()
	await process_frame

func _test_minors():
	print("\nChildren are never targets")
	var rook = _body("rook", Vector2(40, 0))
	await physics_frame
	var before = pe.order.size()
	var r = rook.take_hit(_hit(30), player)
	_check("Rook cannot be hit (%s)" % r.get("reason", ""), r.get("refused", false) and rook.health == rook.max_health and rook.is_alive)
	_check("...and no deed is recorded", pe.order.size() == before)
	rook.queue_free()

	var dyn = root.get_node("DynamicNPCRegistry")
	var real = dyn.generics
	_check("No shipped archetype is a minor", real.minor_archetypes.is_empty())
	var gm = GenericManagerScript.new()
	gm.auto_boot = false
	gm.director_override = Node.new()
	root.add_child(gm)
	gm.load_content(FIXTURE_ARCHETYPES)
	_check("Fixture archetypes load (%s)" % [gm.archetypes.keys()], gm.archetypes.has("fixture_child") and gm.archetypes.has("fixture_adult"))
	var child = gm.create_instance(gm.get_archetype("fixture_child"), "capitol_warrens", 1)
	var adult = gm.create_instance(gm.get_archetype("fixture_adult"), "capitol_warrens", 1)
	_check("`minor: true` makes its instances minors; `minor: false` does not", gm.is_minor(child.id) and not gm.is_minor(adult.id) and gm.is_minor("fixture_child"))
	dyn.generics = gm
	_check("WorldRegistry.is_minor asks GenericManager for generic ids", registry.is_minor(child.id) and not registry.is_minor(adult.id))
	_check("Combat.can_target refuses the child, allows the adult", not root.get_node("Combat").can_target(child.id) and root.get_node("Combat").can_target(adult.id))
	var child_body = _body(child.id, Vector2(40, 0))
	var adult_body = _body(adult.id, Vector2(-40, 0))
	await physics_frame
	_check("The child's body refuses the hit", child_body.take_hit(_hit(20), player).get("refused", false) and child_body.health == child_body.max_health)
	_check("The adult's body takes it", not adult_body.take_hit(_hit(20), player).get("refused", false) and adult_body.health == 80.0)
	dyn.generics = real
	for id in [child.id, adult.id]:
		world_state.npc_states.erase(id)
	gm.reset()
	gm.director_override.free()
	gm.queue_free()
	child_body.queue_free()
	adult_body.queue_free()
	await process_frame

# =============================================================================
# CREATURES
# =============================================================================

func _test_creature_data_and_spawning():
	print("\nCreatures: data and spawning")
	var defs = CreatureScript.definitions()
	for id in ["wolf", "boar", "adder", "rat", "bear"]:
		_check("%s is defined, with a scene" % id, defs.has(id) and ResourceLoader.exists("res://scenes/creatures/%s.tscn" % id))
	var spawner = SpawnerScript.new()
	var seen = func(loc: String) -> Dictionary:
		var out = {}
		for day in 200:
			for row in spawner.plan_for(loc, day):
				out[row.creature] = int(out.get(row.creature, 0)) + 1
		return out
	var darkwood: Dictionary = seen.call("forest_path")
	_check("Wolves and boar live in the Darkwood (%s)" % darkwood, darkwood.has("wolf") and darkwood.has("boar") and darkwood.size() == 2)
	var ridge: Dictionary = seen.call("iron_hollow_camp")
	_check("Adders on the ridge, and a rare bear (%s in 200 days)" % ridge.get("bear", 0), ridge.has("adder") and ridge.get("bear", 0) > 0 and ridge.get("bear", 0) < 40)
	_check("Rats in the Pit and the Warrens", seen.call("the_pit").keys() == ["rat"] and seen.call("capitol_warrens").keys() == ["rat"])
	_check("Nothing wild in Thornhaven square", seen.call("thornhaven_town_square").is_empty())
	_check("The same visit on the same day sees the same creatures", spawner.plan_for("forest_path", 3) == spawner.plan_for("forest_path", 3))
	var day = 0
	while spawner.plan_for("the_pit", day).is_empty():
		day += 1
	var pit = Node2D.new()
	root.add_child(pit)
	var marks = Node2D.new()
	marks.name = "CreatureSpawns"
	pit.add_child(marks)
	var m = Marker2D.new()
	m.position = Vector2(500, 500)
	marks.add_child(m)
	var made: Array = spawner.spawn_into("the_pit", pit, day)
	_check("The Pit's rats spawn at its CreatureSpawns marker (%d)" % made.size(), not made.is_empty() and made.all(func(c): return c.creature_id == "rat" and c.position.distance_to(Vector2(500, 500)) < 200 and c.is_in_group("creatures")))
	pit.queue_free()
	spawner.free()

func _creature(id: String, at: Vector2) -> Node:
	var c = SpawnerScript.instance(id)
	c.position = at
	scene.add_child(c)
	return c

func _test_creature_behaviour():
	print("\nCreatures: behaviour")
	player.position = Vector2(200, 0)
	var wolf = _creature("wolf", Vector2.ZERO)
	var boar = _creature("boar", Vector2(0, 100))
	var adder = _creature("adder", Vector2(0, -400))
	await physics_frame
	var v = wolf.think(0.1)
	_check("A wolf stalks: closes in slowly (%s, %.0f px/s)" % [wolf.state, v.length()], wolf.state == "stalk" and v.x > 0 and v.length() < float(wolf.def.speed))
	var bv = boar.think(0.1)
	_check("A boar charges (%s, %.0f px/s)" % [boar.state, bv.length()], boar.state == "charge" and bv.length() == float(boar.def.charge_speed))
	_check("An adder lies still until you are close", adder.think(0.1) == Vector2.ZERO and adder.state == "idle")
	var x0 = wolf.position.x
	for i in 10:
		await physics_frame
	_check("...and the wolf really moves toward the player", wolf.position.x > x0)
	wolf.position = player.position - Vector2(20, 0)
	wolf._cooldown = 0.0
	wolf.think(0.1)
	_check("In reach, it strikes (then waits out its attack time)", wolf._cooldown > 0.0)
	_check("Its natural weapon is data (%s)" % wolf.get_weapon(), wolf.get_weapon().damage == float(wolf.def.damage) and wolf.get_weapon().type == "cut")
	wolf.take_hit(_hit(wolf.max_health * 0.8), player)
	var fv = wolf.think(0.1)
	_check("Hurt badly, the wolf flees (%s)" % wolf.state, wolf.state == "flee" and fv.x < 0)
	adder.take_hit(_hit(adder.max_health * 0.8), player)
	_check("An adder does not flee when hurt", adder.state != "flee")
	var heard: Array = []
	boar.died.connect(func(info): heard.append(info))
	var r = boar.take_hit(_hit(500, {"killed": true}), player)
	var items = boar.drops.map(func(d): return d.item)
	_check("Its death is announced with the drops", heard.size() == 1 and heard[0].drops == boar.drops and heard[0].by_player)
	_check("A boar killed drops hide and meat (%s)" % [items], r.dead and "hide" in items and "raw_meat" in items)
	_check("Drops are seeded", CreatureScript.roll_drops(CreatureScript.definition("boar"), 5) == CreatureScript.roll_drops(CreatureScript.definition("boar"), 5))
	_check("Killing a creature is no deed", pe.order.filter(func(id): return pe.events[id].kind in ["kill", "harm"] and pe.events[id].about.is_empty()).is_empty())
	await process_frame
	for c in [wolf, adder]:
		if is_instance_valid(c):
			c.queue_free()
	await process_frame

# =============================================================================

func _restore() -> void:
	director.relationship_dims_override = {}
	if is_instance_valid(scene):
		scene.queue_free()
	world_state.world_flags = saved_flags
	world_state.npc_states = saved_npc_states
	world_state.game_minutes = saved_minutes
	pe.load_from_dict(saved_pe)
	_check("No save file was written", FileAccess.file_exists(world_state.SAVE_PATH) == save_existed)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
