extends SceneTree

# Tests the Ranger character type (docs/WORLD_SCHEMA.md §9.1, docs/PLAYER_SYSTEMS.md §3):
# - character types: base traits and skills from resources/characters/character_types.json, reaching
#   main NPCs by world.json key (Renna) and generics by the archetype `type:` header (ranger.md);
#   temperament leans a generic's roll, morale holds steadier, ordinary folk stay neutral
# - what the traits do beyond a fight: trail reading, woodwise sight and concealment, creatures, herbs
#   and the sky in the prompt, under a roof only by day; rangers ride to their posts when the crown
#   sends them (population posted_after)
# - ranged combat: a bow at range, closing for a clear line (walls on world_solid block it), giving
#   ground, the sidearm when closed on, a limited quiver, never at a child and never past one
# - Renna's loadout: her father's bow and the ranger's sword
# - the_rangers_answer: a generic ranger who saw it answers by soul where Renna is not riding
# Fakes only: no API calls, nothing reaches ./chroma, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_ranger.gd

const AI = preload("res://scripts/combat/combat_ai.gd")
const CharacterTypes = preload("res://scripts/npcs/character_types.gd")
const Loadouts = preload("res://scripts/combat/loadouts.gd")
const Archetype = preload("res://scripts/generics/archetype.gd")
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
	func get_equipped(_slot: String) -> Dictionary:
		return {}
	func wear(_slot: String, _amount: float = 1.0) -> Dictionary:
		return {"broke": false}
	func has(_item_id: String, _qty: int = 1) -> bool:
		return true
	func remove(_item_id: String, _qty: int = 1) -> bool:
		return true

class FakePlayer extends Node2D:
	var is_alive: bool = true

class FakeBody extends StaticBody2D:
	var npc_id: String = ""
	var is_alive: bool = true
	var profile: Dictionary = {}
	func get_combat_profile() -> Dictionary:
		return profile

var failures: int = 0
var world_state: Node
var director: Node
var registry: Node
var pe: Node
var combat: Node
var gm: Node
var em
var scene: Node2D
var BaseNPCScript
var GenericNPCScript
var saved_flags: Dictionary
var saved_states: Dictionary
var saved_minutes: int
var saved_pe: Dictionary
var saved_gm: Dictionary
var real_capture: bool
var save_existed: bool

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	pe = root.get_node("PlayerEvents")
	combat = root.get_node("Combat")
	var dyn = root.get_node_or_null("DynamicNPCRegistry")
	gm = dyn.generics if dyn and "generics" in dyn else null
	BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	GenericNPCScript = load("res://scripts/generics/generic_npc.gd")
	saved_flags = world_state.world_flags.duplicate(true)
	saved_states = world_state.npc_states.duplicate(true)
	saved_minutes = world_state.game_minutes
	saved_pe = pe.save()
	saved_gm = gm.save() if gm else {}
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
	print("🧪 RANGER TEST")
	print("============================================================\n")

	_test_types()
	_test_traits_beyond_combat()
	await _test_ranged_combat()
	await _test_renna()
	await _test_rangers_answer()

	_restore()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================

func _test_types():
	print("Character types: base traits and skills")
	_check("GenericManager is running", gm != null)
	var kind = CharacterTypes.resolve("ranger")
	_check("A ranger has the ranger's traits", kind.type == "ranger" and CharacterTypes.has_trait(kind, "trail_reader") and CharacterTypes.has_trait(kind, "keeps_distance"))
	_check("...and skills by skills.json id (bows %.0f, woodcraft %.0f)" % [CharacterTypes.skill(kind, "bows"), CharacterTypes.skill(kind, "woodcraft")],
		CharacterTypes.skill(kind, "bows") == 55.0 and CharacterTypes.skill(kind, "woodcraft") == 45.0)
	var renna = CharacterTypes.of_key("renna")
	_check("Renna is a ranger by world.json key, her own skills over the type's (bows %.0f)" % CharacterTypes.skill(renna, "bows"),
		renna.type == "ranger" and CharacterTypes.skill(renna, "bows") == 80.0 and CharacterTypes.skill(renna, "herbcraft") == 30.0)
	_check("...and holds steadier than the type (morale +%.0f)" % CharacterTypes.morale_bonus(renna), CharacterTypes.morale_bonus(renna) == 12.0)
	_check("Ordinary folk have no type, traits or skills", CharacterTypes.of_key("gregor").type == "" and CharacterTypes.of_key("gregor").skills.is_empty())
	var arch = Archetype.load_from_file("res://resources/generics/archetypes/ranger.md")
	_check("ranger.md parses clean with `type: ranger` (%s)" % [arch.errors if arch else "missing"], arch != null and arch.is_valid() and arch.character_type_id == "ranger")
	_check("The real population has five rangers", gm.get_ids().filter(func(id): return id.begins_with("gen_ranger_")).size() == 5)
	var id = "gen_ranger_4"
	_check("A generic ranger is a ranger (GenericManager.character_kind)", gm.character_kind(id).type == "ranger")
	_check("...a woodcutter is not", gm.character_kind("gen_woodcutter_1").type == "")
	_check("CharacterTypes.of_key finds a generic's type", CharacterTypes.of_key(id).type == "ranger")
	# Temperament leans the roll: the same draws for a ranger and a woodcutter, offset by the type
	var a = RandomNumberGenerator.new()
	var b = RandomNumberGenerator.new()
	a.seed = 4242
	b.seed = 4242
	var leaned = gm.roll_traits(a, "ranger")
	var bare = gm.roll_traits(b, "woodcutter")
	_check("Temperament leans a ranger's roll (conscientiousness %d over %d, neuroticism %d under %d)" % [leaned.conscientiousness, bare.conscientiousness, leaned.neuroticism, bare.neuroticism],
		leaned.conscientiousness == bare.conscientiousness + 15 and leaned.neuroticism == bare.neuroticism - 15 and leaned.agreeableness == bare.agreeableness)
	var npc = _generic_body(id, Vector2.ZERO)
	root.add_child(npc)
	var prof = npc.get_combat_profile()
	_check("Combat reads a generic ranger's skills (bows %.0f)" % float(prof.skills.get("bows", 0)), float(prof.skills.get("bows", 0)) == 55.0)
	npc.free()
	_reset()
	var steady = AI.morale_for(id, {"kind": "attacked", "attacker": "gen_woodcutter_1"})
	_check("Morale counts the type's training (%.0f = base + resolve %.0f + 8)" % [steady, AI.resolve(id)], is_equal_approx(steady, clampf(AI.BASE_MORALE + AI.resolve(id) + 8.0, 0.0, 100.0)))

func _test_traits_beyond_combat():
	print("\n...what the traits do beyond a fight")
	var kind = CharacterTypes.resolve("ranger")
	var plain = CharacterTypes.neutral()
	_check("A trail reader lays a found body at the stranger's door (%.2f from 0.2)" % CharacterTypes.trail_fidelity(kind, 0.2),
		CharacterTypes.trail_fidelity(kind, 0.2) >= 0.6 and CharacterTypes.trail_fidelity(plain, 0.2) == 0.2)
	_check("Woodwise: sees farther under the sky, not under a roof", CharacterTypes.sight_factor(kind, true) > 1.0 and CharacterTypes.sight_factor(kind, false) == 1.0 and CharacterTypes.sight_factor(plain, true) == 1.0)
	_check("...and is harder to see outdoors than in", CharacterTypes.concealment(kind, true) > CharacterTypes.concealment(kind, false))
	_check("Under a roof only by day, outdoors at any hour", not CharacterTypes.present_at(kind, true, 23) and CharacterTypes.present_at(kind, true, 12) and CharacterTypes.present_at(kind, false, 23))
	_check("...ordinary folk keep their own hours", CharacterTypes.present_at(plain, true, 23))
	var lines = CharacterTypes.craft_lines(kind, "forest_path", DAY + 10 * 60)
	_check("Beast lore: the creatures that range the forest path (%s)" % [lines], " ".join(lines).contains("Wolf"))
	_check("Weather eye: the sky ahead", " ".join(lines).contains("sky"))
	_check("Ordinary folk know none of it", CharacterTypes.craft_lines(plain, "forest_path", DAY).is_empty())
	_check("Shooting is quicker with the bows skill", CharacterTypes.shoot_seconds(CharacterTypes.of_key("renna")) < CharacterTypes.shoot_seconds(kind))

	print("\n...rangers ride to their posts when the crown sends them")
	_reset()
	gm.sync_postings()
	_check("Before the Rangers arrive, the forest pickets wait at the Dawn Gate (%s)" % gm.get_location("gen_ranger_1"), gm.get_location("gen_ranger_1") == "capitol_gate")
	_check("...and the Kingsroad rider too (%s)" % gm.get_location("gen_ranger_3"), gm.get_location("gen_ranger_3") == "capitol_gate")
	world_state.world_flags["tithe_rangers_arrive"] = true
	var moved = gm.sync_postings()
	_check("Once they arrive, the pickets are on the forest path (%s)" % [moved], gm.get_location("gen_ranger_1") == "forest_path" and director.get_npc_location("gen_ranger_1") == "forest_path")
	_check("...the Kingsroad rider still waits for the dispatch", gm.get_location("gen_ranger_3") == "capitol_gate")
	var block = gm.get_prompt_block("gen_ranger_1", false)
	_check("A picket's prompt is a ranger's, not ordinary folk's", block.contains("King's Ranger") and not block.contains("Ordinary folk"))
	_check("...with what the forest tells them", block.contains("What your craft tells you here") and block.contains("Wolf"))
	world_state.game_minutes = DAY + 23 * 60
	_check("At night a ranger is out of doors: not in the Halfway House", not gm._within_hours(_posted_at("gen_ranger_3", "kingsroad_waystation")))
	world_state.game_minutes = DAY + 10 * 60
	_check("...by day they are", gm._within_hours(_posted_at("gen_ranger_3", "kingsroad_waystation")))
	_reset()
	gm.sync_postings()

func _test_ranged_combat():
	print("\nRanged combat")
	_reset()
	var player = await _fresh_scene()
	player.position = Vector2(260, 0)
	var ranger = _generic_body("gen_ranger_4", Vector2.ZERO)
	scene.add_child(ranger)
	await _settle()
	_fight(ranger, player)
	_check("A ranger's main weapon is the bow", ranger.has_ranged_weapon() and ranger.get_combat_profile().weapon == "hunting_bow")
	_check("...with a dozen arrows", ranger.arrows_left() == 12)
	var did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("At range with a clear line, the ranger shoots (%s)" % did, did == "shoot")
	_check("...an arrow in flight on the projectile layer", _projectiles().size() == 1 and _projectiles()[0].collision_layer == 64)
	_check("...and one fewer in the quiver", ranger.arrows_left() == 11)
	_check("The draw takes time: no second shot at once", ranger.ranged_step(player.global_position - ranger.global_position, "player") != "shoot")

	player.position = Vector2(110, 0)
	ranger._attack_cooldown = 0.0
	_tick(3.0)
	await _settle()
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("Too close for comfort: the ranger gives ground and still looses (%s, %.0f)" % [did, ranger.velocity.x], ranger.velocity.x < 0.0 and did == "shoot")

	player.position = Vector2(50, 0)
	ranger._attack_cooldown = 0.0
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("Closed on, the ranger draws the knife (%s)" % did, did == "draw_sidearm" and ranger.get_combat_profile().weapon == "fighting_knife")
	ranger._attack_cooldown = 0.0
	_tick(3.0)
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("...and fights hand to hand with it (%s)" % did, did == "melee")
	player.position = Vector2(300, 0)
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("Given room again, the bow comes back out (%s)" % did, did == "draw_bow" and ranger.get_combat_profile().weapon == "hunting_bow")

	print("\n...line of sight")
	scene.add_child(_wall(Vector2(150, 0), Vector2(20, 300)))
	await _settle()
	ranger._attack_cooldown = 0.0
	_tick(3.0)
	var before = ranger.arrows_left()
	_check("A wall between them blocks the line", not combat.has_line_of_sight(ranger, player))
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("...so the ranger closes for a clear shot instead of loosing into stone (%s)" % did, did == "close" and ranger.velocity.x > 0.0 and ranger.arrows_left() == before)

	print("\n...the quiver runs out")
	await _fresh_scene_keep(player)
	ranger = _generic_body("gen_ranger_5", Vector2.ZERO)
	scene.add_child(ranger)
	await _settle()
	_fight(ranger, player)
	ranger.arrows = 1
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("The last arrow goes (%s)" % did, did == "shoot" and ranger.arrows_left() == 0)
	_tick(3.0)
	_check("Combat refuses a shot from an empty quiver", combat.attack(ranger, player, "shoot").get("refused", "") == "no_ammo")
	ranger._attack_cooldown = 0.0
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("...so the ranger draws the knife and closes (%s)" % did, did == "draw_sidearm" and ranger.get_combat_profile().weapon == "fighting_knife")
	ranger._attack_cooldown = 0.0
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("...and does not put it away with nothing to shoot (%s)" % did, did == "melee" and ranger.velocity.x > 0.0)

	print("\n...never at a child")
	await _fresh_scene_keep(player)
	ranger = _generic_body("gen_ranger_5", Vector2.ZERO)
	ranger.arrows = 12
	scene.add_child(ranger)
	var rook = _body(registry.get_npc_id("rook"), Vector2(240, 0))
	await _settle()
	_fight(ranger, rook)
	did = ranger.ranged_step(rook.global_position - ranger.global_position, AI.key_of(rook))
	_check("A ranger set on Rook never looses at him (%s)" % did, did != "shoot" and ranger.arrows_left() == 12 and _projectiles().is_empty())
	_tick(3.0)
	_check("...and Combat refuses the shot outright", combat.attack(ranger, rook, "shoot").get("refused", "") == "minor")
	rook.position = Vector2(120, 4)
	await _settle()
	_fight(ranger, player)
	ranger._attack_cooldown = 0.0
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("With Rook in the line of the shot, the ranger holds it (%s)" % did, did == "hold" and ranger.arrows_left() == 12)
	rook.position = Vector2(120, 140)
	await _settle()
	did = ranger.ranged_step(player.global_position - ranger.global_position, "player")
	_check("...and looses once he is out of it (%s)" % did, did == "shoot")
	ranger.end_fight("over", false)
	_check("A fight's end puts the sidearm away; the quiver stays spent", not ranger.wielding_sidearm and ranger.arrows_left() == 11)

func _test_renna():
	print("\nRenna")
	var kit = Loadouts.for_npc("renna")
	_check("Renna's loadout: her father's bow, the ranger's sword, twenty arrows (%s)" % [kit], kit.weapon == "hunting_bow" and kit.sidearm == "rangers_sword" and kit.arrows == 20 and "leather_jerkin" in kit.armour)
	var player = await _fresh_scene()
	player.position = Vector2(60, 0)
	var renna = BaseNPCScript.new()
	renna.npc_id = registry.get_npc_id("renna")
	renna.npc_name = "Renna"
	scene.add_child(renna)
	await _settle()
	var prof = renna.get_combat_profile()
	_check("Her body fights with the bow and her own skills (bows %.0f)" % float(prof.skills.get("bows", 0)), prof.weapon == "hunting_bow" and float(prof.skills.get("bows", 0)) == 80.0)
	_fight(renna, player)
	var did = renna.ranged_step(player.global_position - renna.global_position, "player")
	_check("Closed on, she draws the ranger's sword (%s)" % did, did == "draw_sidearm" and renna.get_combat_profile().weapon == "rangers_sword")
	_check("A minor carries no bow, whatever the data says", Loadouts.for_npc("rook", true).weapon == "fists" and Loadouts.for_npc("rook", true).arrows == 0)

func _test_rangers_answer():
	print("\nThe Rangers answer: a generic ranger, where Renna is not riding")
	_reset()
	world_state.world_flags["tithe_rangers_arrive"] = true
	gm.sync_postings()
	world_state.set_npc_location(registry.get_npc_id("renna"), "capitol_gate")
	var id = _record("harm", "struck a woodcutter on the forest path", ["gen_woodcutter_1"], ["gen_ranger_1"], "forest_path")
	var inst = _instance("the_rangers_answer", id)
	_check("The picket who saw it is the keeper (%s)" % inst.get("roles", {}).get("keeper", "-"), inst.get("roles", {}).get("keeper", "") == "gen_ranger_1")
	var hook = em.resolved_hook(inst, "keeping_the_peace") if not inst.is_empty() else {}
	_check("...named in the situation", not hook.is_empty() and gm.get_instance("gen_ranger_1").name in str(hook.get("situation", "")))
	var made = await _decide(inst)
	_check("...and answers by their own soul (%s)" % made.get("gen_ranger_1", {}).get("choice", "-"), made.has("gen_ranger_1") and made.gen_ranger_1.choice != "pass")

	_reset()
	world_state.world_flags["tithe_rangers_arrive"] = true
	gm.sync_postings()
	world_state.set_npc_location(registry.get_npc_id("renna"), "village_gate")
	id = _record("harm", "struck a woodcutter on the forest path", ["gen_woodcutter_1"], ["gen_ranger_1", "renna"], "forest_path")
	_check("Both knew it: the nearer ranger answers (the picket on the spot)", _instance("the_rangers_answer", id).get("roles", {}).get("keeper", "") == "gen_ranger_1")
	_reset()
	world_state.world_flags["tithe_rangers_arrive"] = true
	gm.sync_postings()
	world_state.set_npc_location(registry.get_npc_id("renna"), "village_gate")
	id = _record("harm", "struck a farmer in the square", ["gen_valley_farmer_1"], ["renna"], "thornhaven_town_square")
	_check("...Renna, where only she knew it", _instance("the_rangers_answer", id).get("roles", {}).get("keeper", "") == "renna")

	_reset()
	gm.sync_postings()
	world_state.set_npc_location(registry.get_npc_id("renna"), "capitol_gate")
	id = _record("harm", "struck a woodcutter on the forest path", ["gen_woodcutter_1"], [], "forest_path")
	_check("Before the Rangers ride west, nobody answers in the forest", _instance("the_rangers_answer", id).is_empty())
	gm.sync_postings()

# =============================================================================

func _generic_body(id: String, at: Vector2):
	var n = GenericNPCScript.new()
	n.setup(id, gm)
	n.position = at
	n.collision_layer = 2
	n.collision_mask = 0
	n.add_to_group("npcs")
	n.add_to_group("generics")
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	n.add_child(shape)
	return n

func _fight(npc, foe) -> void:
	npc.combat_state = "fight"
	npc.combat_foe = foe
	npc._fight = {"foe_key": AI.key_of(foe), "band": "steady", "harm_recorded": false, "help_recorded": false, "last_hit_ms": Time.get_ticks_msec()}
	npc._attack_cooldown = 0.0
	npc.set_physics_process(false)  # the test drives each step

func _posted_at(id: String, location: String):
	world_state.set_npc_location(id, location)
	return gm.get_instance(id)

func _projectiles() -> Array:
	return scene.get_children().filter(func(c): return c is Area2D and c.collision_layer == 64)

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

func _fresh_scene() -> FakePlayer:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = Node2D.new()
	scene.name = "RangerTestScene"
	root.add_child(scene)
	combat.stats_provider = FakeStats.new()
	combat.inventory_provider = FakeInventory.new()
	combat.reset()
	combat.set_test_clock(100.0)
	var p = FakePlayer.new()
	p.name = "Player"
	p.add_to_group("player")
	scene.add_child(p)
	return p

## A fresh scene with the same player body moved into it
func _fresh_scene_keep(player: Node2D) -> void:
	var at = player.position
	player.get_parent().remove_child(player)
	scene.queue_free()
	await process_frame
	scene = Node2D.new()
	scene.name = "RangerTestScene"
	root.add_child(scene)
	scene.add_child(player)
	player.position = at
	combat.reset()
	combat.set_test_clock(200.0)

func _body(id: String, at: Vector2) -> FakeBody:
	var b = FakeBody.new()
	b.npc_id = id
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
