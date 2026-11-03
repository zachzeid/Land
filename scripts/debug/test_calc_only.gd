extends SceneTree

# Tests BaseNPC._calculate_relationship_impacts without initializing an NPC:
# the direction of each interaction's impact, and the relationship-context rules that reshape it
# (low familiarity dampens trust x0.7, high trust magnifies affection x1.5, high fear halves trust,
# high affection makes a betrayal cost double affection)
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_calc_only.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "RELATIONSHIP IMPACT RULES TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 RELATIONSHIP IMPACT RULES TEST")
	print("============================================================\n")
	var npc = load("res://scripts/npcs/base_npc.gd").new()

	print("Directions (a familiar NPC, so trust is not dampened)")
	npc.relationship_familiarity = 50
	var quest = npc._calculate_relationship_impacts("quest_completed", {})
	_check("quest_completed: trust 15, respect 10, affection 8, familiarity 5", quest == {"trust": 15, "respect": 10, "affection": 8, "fear": 0, "familiarity": 5})
	var gift_high = npc._calculate_relationship_impacts("gift_received", {"thoughtfulness": "high"})
	var gift_low = npc._calculate_relationship_impacts("gift_received", {"thoughtfulness": "low"})
	_check("A thoughtful gift moves affection more than a careless one", gift_high.affection > gift_low.affection and gift_high.trust > gift_low.trust)
	var danger = npc._calculate_relationship_impacts("shared_danger", {})
	_check("shared_danger raises trust and respect and lowers fear", danger.trust > 0 and danger.respect > 0 and danger.fear < 0)
	var broken = npc._calculate_relationship_impacts("promise_broken", {})
	_check("promise_broken lowers trust and affection", broken.trust < 0 and broken.affection < 0)
	var cruelty = npc._calculate_relationship_impacts("witnessed_cruelty", {})
	_check("witnessed_cruelty raises fear", cruelty.fear > 0 and cruelty.respect < 0)
	var brutal = npc._calculate_relationship_impacts("witnessed_combat", {"style": "brutal"})
	var gentle = npc._calculate_relationship_impacts("witnessed_combat", {"style": "non_lethal"})
	_check("Brutal combat frightens more than non-lethal combat", brutal.fear > gentle.fear and gentle.respect > brutal.respect)
	_check("An unknown interaction only adds familiarity", npc._calculate_relationship_impacts("juggling", {}) == {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 1})

	print("\nRelationship context")
	npc.relationship_familiarity = 10
	_check("Low familiarity dampens trust x0.7 (15 -> 10)", npc._calculate_relationship_impacts("quest_completed", {}).trust == 10)
	npc.relationship_familiarity = 50
	npc.relationship_trust = 60
	_check("High trust magnifies affection x1.5 (8 -> 12)", npc._calculate_relationship_impacts("quest_completed", {}).affection == 12)
	npc.relationship_trust = 0
	npc.relationship_fear = 60
	_check("High fear halves trust gains (15 -> 7)", npc._calculate_relationship_impacts("quest_completed", {}).trust == 7)
	npc.relationship_fear = 0
	npc.relationship_affection = 70
	_check("High affection: a broken promise costs affection -15 + 2 x -20 = -55", npc._calculate_relationship_impacts("promise_broken", {}).affection == -55)

	npc.free()
	_finish()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
