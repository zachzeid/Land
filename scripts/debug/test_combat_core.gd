extends SceneTree

# Tests the combat core (docs/PLAYER_SYSTEMS.md §3):
# - stamina prices every action (light 10, heavy 25, dodge 15, sprint 8/s, a block scaled by the hit)
#   and refuses it, spending nothing, when the stamina is not there
# - the parry window (0.25 s, wider with defence) staggers the attacker; a late guard only blocks
# - poise: heavy hits drain more, zero staggers, a staggered fighter cannot act
# - damage types against armour resistances (mail turns a blade, padding a club, leather a flame)
# - weapons wear through Inventory.wear and break; a broken weapon hits like fists
# - skill use on every landed hit (weapon skill, difficulty from the target), block/parry raise
#   defence, dodge/sprint raise athletics
# - minors (docs/PLAYER_SYSTEMS.md §1.4): the player can strike Rook (the harm carries victim_minor);
#   an NPC's swing at him is refused and passes through him to the adult behind, and so does an NPC's
#   arrow, while the player's arrow lands on him
# - striking a person records one `harm` per fight, witnessed by line of sight (not through a wall)
# - dodge invulnerability, projectiles stopped by walls, apply_hit_to for bodies with their own health,
#   hit_landed / fight_ended, the player scene's hurtbox
# Fakes for PlayerStats and Inventory; no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_combat_core.gd

var failures: int = 0
var combat: Node
var stats: FakeStats
var inv: FakeInventory
var scene: Node2D

class FakeStats extends RefCounted:
	var stamina: float = 100.0
	var health: float = 100.0
	var skills: Dictionary = {}
	var used: Array = []
	func get_stamina() -> float:
		return stamina
	func spend_stamina(amount: float) -> bool:
		if stamina < amount:
			return false
		stamina -= amount
		return true
	func get_skill(skill: String) -> float:
		return float(skills.get(skill, 0.0))
	func use_skill(skill: String, difficulty_factor: float = 1.0, context: Dictionary = {}) -> Dictionary:
		used.append({"skill": skill, "difficulty": difficulty_factor, "context": context})
		return {"gained": 0.1, "level": 0.0, "milestone": 0}
	func damage(amount: float, _type: String = "blunt", _source: String = "") -> Dictionary:
		health -= amount
		return {"health": health, "staggered": false, "dead": health <= 0.0}
	func used_skill(skill: String) -> Array:
		return used.filter(func(u): return u.skill == skill)

class FakeInventory extends RefCounted:
	var equipped: Dictionary = {}
	var items: Dictionary = {}
	var wear_calls: int = 0
	func get_equipped(slot: String) -> Dictionary:
		return equipped.get(slot, {}).duplicate(true)
	func wear(slot: String, amount: float = 1.0) -> Dictionary:
		wear_calls += 1
		var rec: Dictionary = equipped.get(slot, {})
		if rec.is_empty():
			return {"broke": false}
		var before = float(rec.durability)
		rec.durability = maxf(before - amount, 0.0)
		return {"broke": before > 0.0 and rec.durability <= 0.0}
	func has(item_id: String, qty: int = 1) -> bool:
		return int(items.get(item_id, 0)) >= qty
	func remove(item_id: String, qty: int = 1) -> bool:
		if not has(item_id, qty):
			return false
		items[item_id] = int(items[item_id]) - qty
		return true

class FakePlayer extends Node2D:
	var facing: Vector2 = Vector2.RIGHT
	func get_facing_vector() -> Vector2:
		return facing

class FakeBody extends StaticBody2D:
	var npc_id: String = ""
	var npc_name: String = ""
	var is_alive: bool = true
	var facing: Vector2 = Vector2.LEFT
	var profile: Dictionary = {}
	func get_combat_profile() -> Dictionary:
		return profile

class OwnHealthBody extends FakeBody:
	var hp: float = 10.0
	func take_combat_hit(result: Dictionary, _attacker: Node) -> Dictionary:
		hp -= float(result.damage)
		return {"health": hp, "staggered": false, "dead": hp <= 0.0}

func _init():
	await process_frame
	await process_frame
	var world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	combat = root.get_node("Combat")
	var registry = root.get_node("WorldRegistry")
	print("============================================================")
	print("🧪 COMBAT CORE TEST")
	print("============================================================\n")

	print("Content")
	_check("weapons.json and armour.json load (fists, iron sword, mail)", not combat.get_weapon_def("fists").is_empty() and not combat.get_weapon_def("short_sword").is_empty() and not combat.get_armour_def("mail_shirt").is_empty())

	print("\nStamina")
	var player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var dummy = _body("practice_post", Vector2(40, 0), ["fighters"])
	await _settle()
	var r = combat.attack(player, dummy, "light")
	_check("A light attack costs 10 and lands", is_equal_approx(stats.stamina, 90.0) and r.get("damage", 0.0) > 0.0)
	_check("...and the next swing waits for the weapon's speed", combat.attack(player, dummy, "light").get("refused", "") == "recovering" and is_equal_approx(stats.stamina, 90.0))
	_tick(2.0)
	combat.attack(player, dummy, "heavy")
	_check("A heavy attack costs 25", is_equal_approx(stats.stamina, 65.0))
	_tick(3.0)
	_check("A dodge costs 15", combat.dodge(player) and is_equal_approx(stats.stamina, 50.0))
	_check("Sprinting costs 8 a second", combat.sprint_tick(player, 1.0) and is_equal_approx(stats.stamina, 42.0))
	_tick(3.0)
	stats.stamina = 5.0
	r = combat.attack(player, dummy, "light")
	_check("Out of stamina the swing is refused and nothing is spent", r.get("refused", "") == "stamina" and is_equal_approx(stats.stamina, 5.0))
	_check("...no dodge either", not combat.dodge(player) and is_equal_approx(stats.stamina, 5.0))
	_check("...no sprint", not combat.sprint_tick(player, 1.0))
	stats.stamina = 0.0
	_check("With no stamina there is no guard", not combat.begin_block(player))

	print("\nBlock and parry")
	player = await _fresh({})
	var foe = _body("test_foe_001", Vector2(40, 0), ["fighters"])
	foe.profile = {"weapon": "short_sword"}
	await _settle()
	combat.begin_block(player)
	_tick(0.1)
	r = combat.attack(foe, player, "light")
	_check("A guard raised 0.1 s before the blow parries it", r.get("parried", false) and r.get("damage", 1.0) == 0.0)
	_check("...the parry staggers the attacker", combat.is_staggered(foe) and combat.attack(foe, player, "light").get("refused", "") == "staggered")
	_check("...costs the parrier 10 and raises defence", is_equal_approx(stats.stamina, 90.0) and stats.used_skill("defence").size() == 1)
	_tick(3.0)
	combat.end_block(player)
	combat.begin_block(player)
	_tick(0.4)
	var before = stats.stamina
	r = combat.attack(foe, player, "light")
	var light_block_cost = before - stats.stamina
	_check("A guard held 0.4 s only blocks: less damage, no stagger of the attacker", r.get("blocked", false) and not r.get("parried", true) and r.damage < r.raw and not combat.is_staggered(foe))
	_check("...blocking costs about 5 per hit, scaled by damage (18 raw -> 9)", is_equal_approx(light_block_cost, 9.0))
	_tick(3.0)
	before = stats.stamina
	combat.attack(foe, player, "heavy")
	_check("...a heavier blow costs more to block", before - stats.stamina > light_block_cost)
	_check("Blocking raises defence", stats.used_skill("defence").size() == 3)
	combat.end_block(player)
	_tick(5.0)
	stats.skills["defence"] = 100.0
	combat.begin_block(player)
	_tick(0.35)
	_check("Defence widens the parry window (0.35 s still parries at defence 100)", combat.attack(foe, player, "light").get("parried", false) and combat.parry_window(player) > 0.25)
	stats.skills.erase("defence")
	combat.end_block(player)
	_tick(5.0)
	stats.stamina = 2.0
	combat.begin_block(player)
	_tick(0.5)
	r = combat.attack(foe, player, "light")
	_check("A guard with no stamina behind it breaks and staggers", r.get("guard_broken", false) and combat.is_staggered(player))

	print("\nPoise and stagger")
	player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var brute = _body("test_brute_001", Vector2(40, 0), ["fighters"])
	await _settle()
	var full = combat.get_poise(brute)
	r = combat.resolve_hit(player, brute, {}, "light")
	var light_poise = full - combat.get_poise(brute)
	_check("A light blow drains a little poise and does not stagger", light_poise > 0.0 and not r.staggered)
	var hammer = combat.make_weapon(_rec("smiths_hammer", 50))
	r = combat.resolve_hit(player, brute, hammer, "heavy")
	_check("A heavy hammer blow drains the rest: staggered", r.staggered and r.poise_damage > light_poise * 2.0 and combat.is_staggered(brute))
	_check("...poise is restored after the stagger", is_equal_approx(combat.get_poise(brute), full))
	_check("A staggered fighter cannot dodge", not combat.dodge(brute))

	print("\nDamage types and armour")
	player = await _fresh({})
	var mail = _body("test_mail_001", Vector2(40, 0), ["fighters"])
	mail.profile = {"armour": ["mail_shirt"]}
	var padded = _body("test_padded_001", Vector2(40, 0), ["fighters"])
	padded.profile = {"armour": ["padded_jack"]}
	var bare = _body("test_bare_001", Vector2(40, 0), ["fighters"])
	var leather = _body("test_leather_001", Vector2(40, 0), ["fighters"])
	leather.profile = {"armour": ["leather_jerkin"]}
	await _settle()
	var sword = combat.make_weapon(_rec("short_sword", 50))
	var club = combat.make_weapon(_rec("cudgel", 50))
	var torch = combat.make_weapon(_rec("torch", 50))
	var on_bare = combat.resolve_hit(player, bare, sword, "light")
	var on_mail = combat.resolve_hit(player, mail, sword, "light")
	_check("A sword is cut damage; on bare skin it does its full 18", on_bare.type == "cut" and is_equal_approx(on_bare.damage, 18.0))
	_check("Mail takes half the cut and a third of the pierce (9.6)", is_equal_approx(on_mail.damage, 9.6))
	var club_mail = combat.resolve_hit(player, mail, club, "light")
	var club_padded = combat.resolve_hit(player, padded, club, "light")
	_check("A club is blunt; padding turns it better than mail", club_mail.type == "blunt" and club_padded.damage < club_mail.damage)
	_check("...and a sword cuts padding deeper than mail", combat.resolve_hit(player, padded, sword, "light").damage > on_mail.damage)
	var torch_bare = combat.resolve_hit(player, bare, torch, "light")
	var torch_leather = combat.resolve_hit(player, leather, torch, "light")
	_check("A torch burns (fire); leather takes some of the flame", torch_bare.raw > 0.0 and torch_leather.damage < torch_bare.damage)
	var weak = _body("test_weak_001", Vector2(40, 0), ["fighters"])
	weak.profile = {"resist": {"fire": -0.5}}
	await _settle()
	_check("A body's own resistances come from data (fire weakness)", combat.resolve_hit(player, weak, torch, "light").damage > torch_bare.damage)

	print("\nDurability")
	player = await _fresh({"main_hand": _rec("short_sword", 2)})
	var post = _body("test_post_001", Vector2(40, 0), ["fighters"])
	await _settle()
	var broke_signal: Array = []
	combat.weapon_broke.connect(func(info): broke_signal.append(info))
	combat.attack(player, post, "light")
	_check("A landed hit wears the weapon through Inventory.wear", inv.wear_calls == 1 and is_equal_approx(float(inv.equipped.main_hand.durability), 1.0))
	_tick(2.0)
	r = combat.attack(player, post, "light")
	_check("...until it breaks (weapon_broke)", r.get("broke", false) and broke_signal.size() == 1 and broke_signal[0].weapon == "short_sword")
	_tick(2.0)
	r = combat.attack(player, post, "light")
	_check("A broken weapon hits like fists (blunt 4) and wears no further", r.get("weapon", "") == "fists" and r.type == "blunt" and is_equal_approx(r.damage, 4.0) and inv.wear_calls == 2)
	_check("Bare hands never wear anything", combat.make_weapon({}).id == "fists")

	print("\nSkill use")
	player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var soldier = _body("test_soldier_001", Vector2(40, 0), ["fighters"])
	var practice = _body("test_practice_001", Vector2(40, 0), ["fighters", "practice"])
	await _settle()
	combat.resolve_hit(player, soldier, {}, "light")
	combat.resolve_hit(player, practice, {}, "light")
	var blades = stats.used_skill("blades")
	_check("Every landed hit uses the weapon's skill (blades)", blades.size() == 2)
	_check("...difficulty from the target: a practice post a tenth of a fighter", blades.size() == 2 and is_equal_approx(blades[0].difficulty, 1.0) and is_equal_approx(blades[1].difficulty, 0.1))
	soldier.is_alive = false
	_check("A dead body cannot be struck at all", not combat.can_target_node(soldier) and combat.difficulty_of(soldier) == 0.0)
	stats.used.clear()
	_tick(5.0)
	combat.dodge(player)
	combat.sprint_tick(player, 1.0)
	_check("Dodging and sprinting raise athletics", stats.used_skill("athletics").size() == 2)
	stats.skills["blades"] = 100.0
	_check("Blades lowers the stamina per swing", combat.stamina_cost(player, combat.weapon_of(player), "light") < 10.0)
	stats.skills.erase("blades")

	print("\nDodge")
	player = await _fresh({})
	foe = _body("test_foe_002", Vector2(40, 0), ["fighters"])
	foe.profile = {"weapon": "short_sword"}
	await _settle()
	combat.dodge(player)
	_tick(0.1)
	r = combat.attack(foe, player, "light")
	_check("Inside the roll the blow misses (invulnerable)", r.get("dodged", false) and is_equal_approx(stats.health, 100.0))
	_tick(1.0)
	r = combat.attack(foe, player, "light")
	_check("After it the blow lands on PlayerStats.damage", not r.get("dodged", true) and stats.health < 100.0)

	print("\nChildren: the player can strike them; NPCs never do")
	player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var rook = _body(registry.get_npc_id("rook"), Vector2(30, 0), ["npcs"])
	rook.npc_name = "Rook"
	await _settle()
	_check("Combat.can_target('rook') is false for anyone but the player", not combat.can_target("rook") and not combat.can_target("rook", "varn") and not combat.can_target_node(rook))
	_check("...and true for the player", combat.can_target("rook", "player") and combat.can_target_node(rook, player))
	var npc_foe = _body("test_npc_attacker_001", Vector2(60, 0), ["fighters"])
	npc_foe.profile = {"weapon": "short_sword"}
	await _settle()
	r = combat.attack(npc_foe, rook, "light")
	_check("An NPC aiming at Rook is refused (minor)", r.get("refused", "") == "minor")
	npc_foe.queue_free()
	var hits: Array = []
	combat.hit_landed.connect(func(info): hits.append(info))
	var pe0 = root.get_node("PlayerEvents")
	var before_rook = pe0.order.size()
	r = combat.attack(player, null, "light")
	_check("The player's swing with only Rook in reach lands on him", r.get("damage", 0.0) > 0.0 and hits.size() == 1 and hits[0].target == rook)
	_check("hit_landed carries attacker, target and keys", hits.size() == 1 and hits[0].attacker_key == "player" and hits[0].target_key == registry.get_npc_id("rook"))
	var rook_harm = pe0.get_event(pe0.order.back()) if pe0.order.size() > before_rook else {}
	_check("...a harm about Rook marked victim_minor", rook_harm.get("kind", "") == "harm" and "rook" in rook_harm.get("about", []) and rook_harm.get("victim_minor", false))
	var behind_rook = _body("test_adult_001", Vector2(55, 0), ["fighters"])
	var swinger = _body("test_npc_swinger_001", Vector2(10, 0), ["fighters"])  # the player stands behind it
	swinger.facing = Vector2.RIGHT
	swinger.profile = {"weapon": "short_sword"}
	await _settle()
	hits.clear()
	r = combat.attack(swinger, null, "light")
	_check("An NPC's swing passes through Rook to the adult behind him", r.get("damage", 0.0) > 0.0 and hits.size() == 1 and hits[0].target == behind_rook)
	swinger.queue_free()
	behind_rook.queue_free()

	print("\nThe harm deed and its witnesses")
	player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var pe = root.get_node("PlayerEvents")
	var varn = _body(registry.get_npc_id("varn"), Vector2(40, 0), ["npcs"])
	varn.npc_name = "Varn"
	var viewer = _body("test_viewer_001", Vector2(40, -200), ["npcs"])
	var walled = _body("test_walled_001", Vector2(40, 300), ["npcs"])
	scene.add_child(_wall(Vector2(40, 150), Vector2(400, 20)))
	await _settle()
	var events_before = pe.get_events().size()
	r = combat.attack(player, null, "light")
	var harm = pe.get_events().filter(func(e): return e.kind == "harm")
	var ev = harm.back() if not harm.is_empty() else {}
	_check("Striking Varn records harm about him", r.get("damage", 0.0) > 0.0 and "varn" in ev.get("about", []) and "Varn" in str(ev.get("summary", "")))
	_check("...seen by the onlooker in the open (and Varn)", registry.get_npc_id("varn") in ev.get("witnesses", []) and "test_viewer_001" in ev.get("witnesses", []))
	_check("...not by the one behind the wall", not "test_walled_001" in ev.get("witnesses", []))
	_tick(2.0)
	combat.attack(player, varn, "light")
	_check("One harm per fight, not one per blow", pe.get_events().size() == events_before + 1)
	var ended: Array = []
	combat.fight_ended.connect(func(info): ended.append(info))
	combat.end_fight(player, varn, "yielded")
	_check("end_fight emits fight_ended with the reason and its harm event", ended.size() == 1 and ended[0].reason == "yielded" and ended[0].harm_events.size() == 1 and ended[0].player)
	var mob = _body("test_wolf_001", Vector2(40, 0), ["creatures"])
	await _settle()
	_tick(2.0)
	events_before = pe.get_events().size()
	combat.resolve_hit(player, mob, {}, "light")
	_check("Striking a creature is no deed", pe.get_events().size() == events_before)

	print("\nBodies with their own health")
	player = await _fresh({"main_hand": _rec("short_sword", 50)})
	var own = OwnHealthBody.new()
	own.npc_id = "test_own_001"
	own.position = Vector2(40, 0)
	own.add_to_group("fighters")
	scene.add_child(own)
	await _settle()
	ended.clear()
	r = combat.attack(player, own, "light")
	_check("take_combat_hit receives the hit; a killing blow says killed", own.hp < 10.0 and r.killed)
	_check("...and ends the fight (fight_ended: killed)", ended.size() == 1 and ended[0].reason == "killed" and ended[0].killed == "test_own_001")
	var plain = _body("test_plain_001", Vector2(-200, 0), ["fighters"])
	_check("apply_hit_to gives any body a hit (Combat's own pool)", is_equal_approx(combat.apply_hit_to(plain, {"damage": 5.0, "type": "fire"}).health, 95.0))

	print("\nProjectiles")
	player = await _fresh({"main_hand": _rec("hunting_bow", 50)})
	var deer = _body("test_target_001", Vector2(200, 0), ["fighters"])
	await _settle()
	r = combat.attack(player, null, "light")
	_check("With a bow the attack key shoots (12 stamina, one arrow)", r.get("action", "") == "shoot" and r.get("projectile") != null and is_equal_approx(stats.stamina, 88.0) and inv.items.arrows == 4)
	var out = await _fly(r.get("projectile"))
	_check("The arrow flies and lands on the target (pierce)", out.get("fighter") == deer and out.result.type == "pierce" and out.result.damage > 0.0)
	var rook2 = _body(registry.get_npc_id("rook"), Vector2(100, 0), ["npcs"])
	var archer = _body("test_npc_archer_001", Vector2(0, 0), ["fighters"])
	archer.facing = Vector2.RIGHT
	archer.profile = {"weapon": "hunting_bow"}
	await _settle()
	out = await _fly(combat.attack(archer, null, "light").get("projectile"))
	_check("An NPC's arrow passes through Rook to the target beyond", out.get("fighter") == deer)
	archer.queue_free()
	await _settle()
	_tick(3.0)
	out = await _fly(combat.attack(player, null, "light").get("projectile"))
	_check("The player's arrow lands on Rook", out.get("fighter") == rook2)
	rook2.queue_free()
	scene.add_child(_wall(Vector2(120, 0), Vector2(20, 200)))
	await _settle()
	_tick(3.0)
	out = await _fly(combat.attack(player, null, "light").get("projectile"))
	_check("A wall stops an arrow", out.get("wall", false))
	_tick(3.0)
	inv.items.arrows = 0
	_check("No arrows, no shot", combat.attack(player, null, "light").get("refused", "") == "no_ammo")

	print("\nThe player")
	var player_script = load("res://scripts/player/player.gd")
	_check("player.gd compiles", player_script != null and player_script.can_instantiate())
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var state = packed.get_state()
	var names: Array = []
	for i in state.get_node_count():
		names.append(str(state.get_node_name(i)))
	_check("player.tscn has a hurtbox", "Hurtbox" in names)
	_check("Combat input actions exist (attack, heavy_attack, block, dodge, sprint)", ["attack", "heavy_attack", "block", "dodge", "sprint"].all(func(a): return InputMap.has_action(a)))

	combat.stats_provider = null
	combat.inventory_provider = null
	combat.set_test_clock(-1.0)
	combat.reset()
	scene.queue_free()
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

## A clean tiny scene with the player at the origin facing right, fresh fakes and a pinned clock
func _fresh(equipped: Dictionary) -> FakePlayer:
	if scene:
		scene.queue_free()
		await process_frame
	scene = Node2D.new()
	root.add_child(scene)
	stats = FakeStats.new()
	inv = FakeInventory.new()
	inv.equipped = equipped
	inv.items = {"arrows": 5}
	combat.stats_provider = stats
	combat.inventory_provider = inv
	combat.reset()
	combat.set_test_clock(100.0)
	var p = FakePlayer.new()
	p.add_to_group("player")
	scene.add_child(p)
	return p

func _rec(id: String, durability: float) -> Dictionary:
	return {"id": id, "qty": 1, "quality": 50, "durability": durability, "max_durability": 50.0}

func _body(id: String, at: Vector2, groups: Array) -> FakeBody:
	var b = FakeBody.new()
	b.npc_id = id
	b.position = at
	b.collision_layer = 2
	b.collision_mask = 0
	for g in groups:
		b.add_to_group(g)
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

## The projectile's outcome once it lands (it frees itself then)
func _fly(p: Node) -> Dictionary:
	if p == null:
		return {}
	return await p.landed

func _tick(seconds: float) -> void:
	combat.set_test_clock(combat.now() + seconds)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
