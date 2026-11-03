extends SceneTree

# Tests PlayerStats and Teaching (docs/PLAYER_SYSTEMS.md §2-3):
# - gain = base_xp x difficulty x (1 - level/110); no gain when the action could not fail or at 100
# - derived level from the top six skills, max health and stamina +5 per level
# - milestones 25/50/75/100 unlock perks (smithing 50 = maker's mark), skill_raised fires
# - stamina spend and regen, poise and stagger
# - death: normal (1%, +1 per death, cap 25%) and hard (doubling, cap 50%) over several deaths; the
#   pack dropped where the player fell; a `fell` deed witnessed only by line of sight (a wall hides);
#   waking at the nearest inn, then at the last bed; deaths counted
# - feats: the first time a skill is seen past 25/50/75, never unwitnessed; respect from a witness
#   whose trade it is (an adjust_relationship effect through the Director)
# - teaching: the soul accepts or refuses on trust and respect; coin or a favour; time passes and gain
#   doubles; a child never teaches fighting; no trade, no lesson
# - save/load through JSON
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_player_stats.gd

class FakeInventory extends RefCounted:
	var coin: int = 0
	var drops: Array = []
	func get_coin() -> int:
		return coin
	func add_coin(copper: int) -> void:
		coin += copper
	func drop_all_at(scene_root: Node, position: Vector2) -> Node:
		drops.append({"scene": scene_root, "position": position})
		return null

class _Body extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true

var failures: int = 0
var stats: Node
var director: Node
var events: Node
var registry: Node
var world_state: Node
var inv: FakeInventory

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	world_state.set_idle_clock_rate(0.0)
	director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.load_content(director.DEFAULT_STORYLINE_DIR, director.DEFAULT_SOUL_DIR)
	events = root.get_node("PlayerEvents")
	registry = root.get_node("WorldRegistry")
	stats = root.get_node("PlayerStats")
	stats.move_on_respawn = false
	inv = FakeInventory.new()
	stats.inventory = inv
	print("============================================================")
	print("🧪 PLAYER STATS TEST")
	print("============================================================\n")

	_test_gain()
	_test_level()
	_test_milestones()
	_test_stamina_poise()
	_test_death_schedules()
	await _test_fell_and_respawn()
	await _test_feats()
	await _test_teaching()
	_test_save_load()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _test_gain():
	print("Gain curve")
	stats.reset()
	_check("Twelve skills from skills.json", stats.get_skill_ids().size() == 12)
	var r = stats.use_skill("blades", 1.0)
	_check("At 0, a full-difficulty use gains base_xp (1.0)", is_equal_approx(r.gained, 1.0) and is_equal_approx(stats.get_skill("blades"), 1.0))
	stats.set_skill("blades", 55.0)
	r = stats.use_skill("blades", 1.0)
	_check("At 55, gain is halved (1 - 55/110)", is_equal_approx(r.gained, 0.5))
	stats.set_skill("blunt", 0.0)
	_check("A practice post (difficulty 0.1) gives a tenth", is_equal_approx(stats.use_skill("blunt", 0.1).gained, 0.1))
	_check("No gain when the action could not fail (difficulty 0)", stats.use_skill("blunt", 0.0).gained == 0.0)
	stats.set_skill("lore", 100.0)
	_check("No gain past mastery", stats.use_skill("lore", 1.0).gained == 0.0 and stats.get_skill("lore") == 100.0)
	stats.set_skill("mining", 99.9)
	stats.use_skill("mining", 5.0)
	_check("Never above 100", stats.get_skill("mining") <= 100.0)
	_check("An unknown skill gains nothing", stats.use_skill("juggling", 1.0).gained == 0.0)

func _test_level():
	print("\nLevel and max stats")
	stats.reset()
	_check("A new player is level 0 with 100 health and stamina", stats.get_level() == 0 and stats.get_max_health() == 100.0 and stats.get_max_stamina() == 100.0)
	for s in ["blades", "blunt", "bows", "defence", "stealth", "smithing"]:
		stats.set_skill(s, 30.0)
	stats.set_skill("lore", 10.0)
	_check("Top six at 30 = level 6 (the seventh does not count)", stats.get_level() == 6)
	_check("Max health and stamina +5 per level", stats.get_max_health() == 130.0 and stats.get_max_stamina() == 130.0)
	_check("The new headroom is filled", stats.get_health() == 130.0)
	stats.set_skill("athletics", 40.0)
	_check("Athletics adds to the stamina pool (and counts in the top six)", stats.get_level() == 6 and stats.get_max_stamina() == 130.0 + 20.0)
	for s in stats.get_skill_ids():
		stats.set_skill(s, 100.0)
	_check("Everything mastered = level 20", stats.get_level() == 20 and stats.get_max_health() == 200.0)

func _test_milestones():
	print("\nMilestones and perks")
	stats.reset()
	var raised: Array = []
	var listener = func(skill, level, milestone): raised.append([skill, level, milestone])
	stats.skill_raised.connect(listener)
	stats.set_skill("blades", 24.5)
	var r = stats.use_skill("blades", 1.0)
	_check("Crossing 25 reports milestone 25", r.milestone == 25)
	_check("...and unlocks the blades 25 perk", stats.has_perk("blades_25_steady_edge") and not stats.has_perk("blades_50_riposte"))
	_check("skill_raised fires with the milestone", raised.size() == 1 and raised[0][0] == "blades" and raised[0][2] == 25)
	stats.use_skill("blades", 0.1)
	_check("A gain within the same point does not fire skill_raised", raised.size() == 1)
	stats.set_skill("smithing", 49.9)
	stats.use_skill("smithing", 1.0)
	_check("Smithing 50 unlocks the maker's mark", stats.has_perk("smithing_50_makers_mark"))
	stats.set_skill("herbcraft", 74.9)
	r = stats.use_skill("herbcraft", 1.0)
	_check("Herbcraft 75", r.milestone == 75 and stats.has_perk("herbcraft_75_no_waste"))
	stats.skill_raised.disconnect(listener)

func _test_stamina_poise():
	print("\nStamina and poise")
	stats.reset()
	_check("Spend 30 of 100", stats.spend_stamina(30.0) and is_equal_approx(stats.get_stamina(), 70.0))
	_check("Cannot spend more than is left", not stats.spend_stamina(1000.0) and is_equal_approx(stats.get_stamina(), 70.0))
	stats.tick(0.5)
	_check("No regen right after spending", is_equal_approx(stats.get_stamina(), 70.0))
	stats.tick(1.0)
	_check("Regen once not spent for a moment", stats.get_stamina() > 70.0)
	stats.tick(30.0)
	_check("Regen stops at the max", stats.get_stamina() == stats.get_max_stamina())
	var hit = stats.damage(30.0, "cut", "")
	_check("A cut takes health, no stagger", is_equal_approx(hit.health, 70.0) and not hit.staggered and not hit.dead)
	hit = stats.damage(50.0, "blunt", "")
	_check("Blunt drains poise to a stagger", hit.staggered and is_equal_approx(hit.health, 20.0))
	stats.heal(500.0)
	_check("Heal stops at max", stats.get_health() == stats.get_max_health())

func _test_death_schedules():
	print("\nDeath schedules")
	_check("Normal: 1, 2, 3 ... capped at 25", stats.loss_percent(1, "normal") == 1.0 and stats.loss_percent(2, "normal") == 2.0 and stats.loss_percent(10, "normal") == 10.0 and stats.loss_percent(25, "normal") == 25.0 and stats.loss_percent(40, "normal") == 25.0)
	_check("Hard: 1, 2, 4, 8, 16, 32, then capped at 50", [1, 2, 3, 4, 5, 6, 7, 9].map(func(n): return stats.loss_percent(n, "hard")) == [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 50.0, 50.0])
	stats.reset()
	stats.set_difficulty("normal")
	for s in stats.get_skill_ids():
		stats.set_skill(s, 50.0)
	var expected = 50.0
	for n in range(1, 4):
		var hit = stats.damage(10000.0, "cut", "")
		expected *= 1.0 - n / 100.0
		_check("Normal death %d costs %d%%" % [n, n], hit.dead and hit.death.loss_percent == float(n) and is_equal_approx(stats.get_skill("blades"), expected))
	_check("Deaths counted", stats.get_deaths() == 3)
	_check("get_death_count", stats.get_death_count() == 3)
	_check("set_difficulty refuses anything but normal/hard", not stats.set_difficulty("easy") and stats.difficulty == "normal")
	_check("The player wakes whole", stats.get_health() == stats.get_max_health())
	_check("Each death drops the pack", inv.drops.size() == 3)
	stats.reset()
	stats.set_difficulty("hard")
	for s in stats.get_skill_ids():
		stats.set_skill(s, 100.0)
	expected = 100.0
	for n in range(1, 5):
		var info = stats.die()
		expected *= 1.0 - pow(2.0, n - 1) / 100.0
		_check("Hard death %d costs %d%%" % [n, int(pow(2.0, n - 1))], is_equal_approx(info.loss_percent, pow(2.0, n - 1)) and is_equal_approx(stats.get_skill("smithing"), expected))
	for n in range(5, 9):
		stats.die()
	_check("Hard caps at 50%% by the 7th death", stats.get_deaths() == 8 and stats.loss_percent(stats.get_deaths(), "hard") == 50.0)
	_check("Perks earned are kept after the fall", stats.has_perk("smithing_100_master_smith"))
	stats.set_difficulty("normal")

func _test_fell_and_respawn():
	print("\nThe fell deed and waking")
	stats.reset()
	var bjorn_id = registry.get_npc_id("bjorn")
	var gregor_id = registry.get_npc_id("gregor")
	var scene = Node2D.new()
	root.add_child(scene)
	scene.add_child(_npc(bjorn_id, Vector2(0, 0)))
	scene.add_child(_npc(gregor_id, Vector2(0, 300)))
	scene.add_child(_wall(Vector2(100, 150), Vector2(400, 20)))   # between the player and Gregor
	var player = Node2D.new()
	player.position = Vector2(100, 0)
	player.add_to_group("player")
	scene.add_child(player)
	await physics_frame
	await physics_frame
	var deaths: Array = []
	var listener = func(info): deaths.append(info)
	stats.died.connect(listener)
	var drops_before = inv.drops.size()
	var hit = stats.damage(1000.0, "cut", "varn")
	var info = hit.get("death", {})
	_check("died fires", deaths.size() == 1)
	_check("The pack drops where the player fell, in that scene", inv.drops.size() == drops_before + 1 and inv.drops[-1].position == Vector2(100, 0) and inv.drops[-1].scene == scene)
	var ev = events.get_event(str(info.get("deed", "")))
	_check("A fell deed is recorded", not ev.is_empty() and ev.kind == "fell")
	_check("Bjorn, in sight, witnessed it", bjorn_id in ev.get("witnesses", []))
	_check("Gregor, behind the wall, did not", not gregor_id in ev.get("witnesses", []))
	_check("The deed is about who struck the blow", "varn" in ev.get("about", []) or registry.get_npc_id("varn") in ev.get("about", []))
	var inns = ["thornhaven_tavern", "kingsroad_waystation"]
	_check("No bed: wakes at an inn", str(info.get("respawn", {}).get("location", "")) in inns)
	_check("The nearest inn from Ferrisford is the Halfway House", stats.nearest_inn("ferrisford").location == "kingsroad_waystation")
	_check("...and from the smithy, the Rusty Nail", stats.nearest_inn("thornhaven_blacksmith").location == "thornhaven_tavern")
	stats.set_respawn("healer_hut", "bed")
	info = stats.die()
	_check("After sleeping in a bed, wakes there", info.respawn == {"location": "healer_hut", "spawn_point": "bed"})
	stats.died.disconnect(listener)
	player.remove_from_group("player")
	scene.queue_free()
	await process_frame

func _test_feats():
	print("\nFeats")
	stats.reset()
	var bjorn_id = registry.get_npc_id("bjorn")
	director.relationship_dims_override.erase("bjorn")
	var respect_before = float(director.get_relationship_dims("bjorn").respect)
	var feats_before = _count_kind("feat")
	stats.set_skill("smithing", 24.9)
	stats.use_skill("smithing", 1.0)
	_check("Passing 25 unseen is no feat", _count_kind("feat") == feats_before)
	stats.use_skill("smithing", 1.0, {"witnessed_by": [bjorn_id]})
	_check("The first use past 25 that someone sees is a feat", _count_kind("feat") == feats_before + 1)
	var feat = _last_of_kind("feat")
	_check("...witnessed by Bjorn, with the skill's feat line", bjorn_id in feat.witnesses and "weld" in feat.summary)
	_check("Bjorn respects a feat in his own trade", float(director.get_relationship_dims("bjorn").respect) > respect_before)
	stats.use_skill("smithing", 1.0, {"witnessed_by": [bjorn_id]})
	_check("The same milestone is not a feat twice", _count_kind("feat") == feats_before + 1)
	var gregor_id = registry.get_npc_id("gregor")
	var respect_gregor = float(director.get_relationship_dims("gregor").respect)
	stats.set_skill("smithing", 52.0)
	stats.use_skill("smithing", 1.0, {"witnessed_by": [gregor_id]})
	_check("Seen past 50 later still counts", _count_kind("feat") == feats_before + 2 and _last_of_kind("feat").summary.contains("blade"))
	_check("Gregor (not a smith) gains no respect from it", float(director.get_relationship_dims("gregor").respect) == respect_gregor)
	# Line of sight from a scene: Gregor behind a wall does not count
	var scene = Node2D.new()
	root.add_child(scene)
	scene.add_child(_npc(gregor_id, Vector2(0, 300)))
	scene.add_child(_wall(Vector2(100, 150), Vector2(400, 20)))
	await physics_frame
	await physics_frame
	stats.set_skill("blades", 26.0)
	stats.use_skill("blades", 1.0, {"scene_root": scene, "position": Vector2(100, 0)})
	_check("Nobody in sight, no feat", _count_kind("feat") == feats_before + 2)
	scene.add_child(_npc(bjorn_id, Vector2(0, 0)))
	await physics_frame
	stats.use_skill("blades", 1.0, {"scene_root": scene, "position": Vector2(100, 0)})
	_check("Someone in sight: the feat", _count_kind("feat") == feats_before + 3 and bjorn_id in _last_of_kind("feat").witnesses)
	scene.queue_free()
	await process_frame

func _test_teaching():
	print("\nTeaching")
	stats.reset()
	var teaching = stats.get_teaching()
	inv.coin = 500
	director.relationship_dims_override["bjorn"] = {}
	var r = await teaching.request_training("bjorn", "smithing")
	_check("A stranger Bjorn neither trusts nor respects is refused", not r.ok and r.choice == "refuse" and r.reason == "refused")
	_check("...and pays nothing", inv.coin == 500)
	director.relationship_dims_override["bjorn"] = {"trust": 40, "respect": 30}
	var clock = world_state.get_game_minutes()
	r = await teaching.request_training("bjorn", "smithing")
	_check("Trusted and respected, Bjorn teaches", r.ok and r.choice == "teach" and r.paid == "coin")
	_check("...for coin", r.cost_copper > 0 and inv.coin == 500 - r.cost_copper)
	_check("...and the lesson takes game time", r.minutes > 0 and world_state.get_game_minutes() == clock + r.minutes)
	var base_xp = float(stats.get_skill_def("smithing").base_xp)
	_check("Gain doubles for a while", is_equal_approx(stats.use_skill("smithing", 1.0).gained, 2.0 * base_xp))
	world_state.advance_time(3 * 24 * 60, "test")
	_check("...and wears off", stats.use_skill("smithing", 1.0).gained <= base_xp)
	inv.coin = 0
	director.relationship_dims_override["bjorn"] = {"trust": 40, "affection": 30}
	r = await teaching.request_training("bjorn", "smithing")
	_check("With no coin, a friend teaches for a favour owed", r.ok and r.choice == "teach_for_favour" and r.cost_copper == 0 and _last_of_kind("promise").summary.contains("favour"))
	r = await teaching.request_training("gregor", "smithing")
	_check("Gregor has no smithing to teach", not r.ok and r.reason == "does not know that trade")
	r = await teaching.request_training("rook", "blades")
	_check("Rook (a child) never teaches fighting", not r.ok and r.reason == "a child does not teach fighting")
	director.relationship_dims_override["rook"] = {"trust": 50, "respect": 50}
	inv.coin = 500
	r = await teaching.request_training("rook", "stealth")
	_check("...but stealth goes to her soul", r.has("choice"))
	stats.set_skill("smithing", 95.0)
	r = await teaching.request_training("bjorn", "smithing")
	_check("Past the teacher's own mastery, nothing more to teach", not r.ok and r.reason == "has nothing more to teach you")
	_check("Generic teachers by archetype", "mining" in teaching.trades_of("gen_miner_3") and teaching.trades_of("gen_pilgrim_1").is_empty())
	_check("Aldric's trade is blades and defence", teaching.trades_of("aldric") == ["blades", "defence"])
	director.relationship_dims_override.erase("bjorn")
	director.relationship_dims_override.erase("rook")

func _test_save_load():
	print("\nSave and load")
	stats.reset()
	stats.set_difficulty("hard")
	stats.set_skill("smithing", 52.5)
	stats.set_skill("lore", 12.25)
	stats.use_skill("smithing", 1.0, {"witnessed_by": [registry.get_npc_id("bjorn")]})
	stats.set_respawn("healer_hut", "bed")
	stats.add_training("lore", 2.0, world_state.get_game_minutes() + 600)
	stats.die()
	stats.damage(20.0, "cut", "")
	var saved = JSON.parse_string(JSON.stringify(stats.save()))
	var smithing = stats.get_skill("smithing")
	stats.reset()
	stats.set_difficulty("normal")
	stats.load_from_dict(saved)
	_check("Difficulty", stats.difficulty == "hard")
	_check("Skills", is_equal_approx(stats.get_skill("smithing"), smithing) and stats.get_skill("lore") > 12.0)
	_check("Perks", stats.has_perk("smithing_50_makers_mark"))
	_check("Deaths", stats.get_deaths() == 1)
	_check("Respawn bed", stats.get_respawn() == {"location": "healer_hut", "spawn_point": "bed"})
	_check("Health", is_equal_approx(stats.get_health(), stats.get_max_health() - 20.0))
	_check("Feats shown stay shown", 50 in stats.get_feats().get("smithing", []))
	_check("Training", stats.training_multiplier("lore") == 2.0)
	_check("WorldState saves the block", world_state.save().player_systems.PlayerStats.deaths == 1)
	stats.reset()
	stats.set_difficulty("normal")

func _count_kind(kind: String) -> int:
	return events.get_events().filter(func(e): return e.kind == kind).size()

func _last_of_kind(kind: String) -> Dictionary:
	var found = events.get_events().filter(func(e): return e.kind == kind)
	return found[-1] if not found.is_empty() else {}

func _npc(id: String, at: Vector2) -> Node2D:
	var n = _Body.new()
	n.npc_id = id
	n.position = at
	n.add_to_group("npcs")
	return n

func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var b = StaticBody2D.new()
	b.position = at
	b.collision_layer = 4
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	b.add_child(shape)
	return b

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
