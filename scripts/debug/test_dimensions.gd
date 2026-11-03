extends SceneTree

# Tests the five relationship dimensions without initializing an NPC (the NPC end to end is
# test_dimension_evolution.gd):
# - impacts: BaseNPC._calculate_relationship_impacts, each interaction's direction and the context
#   rules that reshape it (low familiarity dampens trust x0.7, high trust magnifies affection x1.5,
#   high fear halves trust, high affection makes a betrayal cost double affection)
# - readings and guidance: ContextBuilder._interpret_dimension bands and _generate_behavioral_guidance
# - the prompt: the five readings replace the legacy single score, for five archetypal relationships
#   and as a relationship grows from stranger to trusted friend
# Replaces test_calc_only, test_dimensions_simple, test_context_dims, test_dimension_sync and
# test_full_evolution, which overlapped
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_dimensions.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const GREGOR = "You are Gregor, a cautious merchant in Thornhaven. You've seen too many adventurers come and go. You protect your daughter Elena fiercely."
const ARCHETYPES = [
	["Neutral stranger", {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0},
		["Formal, asking basic questions"], ["CONFLICTED", "INTIMATE BOND"]],
	["Trusted ally", {"trust": 70, "respect": 60, "affection": 40, "fear": -20, "familiarity": 80},
		["Be open but maintain some boundaries", "Friendly and welcoming tone", "Reference shared history"], ["Formal", "CONFLICTED"]],
	["Romantic interest", {"trust": 85, "respect": 70, "affection": 90, "fear": 0, "familiarity": 95},
		["Share secrets and vulnerabilities", "Show warmth and genuine care", "INTIMATE BOND"], ["CONFLICTED"]],
	["Conflicted (affection + fear)", {"trust": 30, "respect": 40, "affection": 70, "fear": 60, "familiarity": 75},
		["You're attracted but afraid", "Careful with words"], ["INTIMATE BOND"]],
	["Enemy", {"trust": -80, "respect": -60, "affection": -90, "fear": 20, "familiarity": 50},
		["Be guarded and skeptical", "Dismissive tone", "Cold, minimal interaction"], ["Friendly", "INTIMATE BOND"]],
]
const STAGES = [
	["Initial meeting", {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0}, "Hello, I'd like to buy some supplies."],
	["After the quest", {"trust": 15, "respect": 10, "affection": 8, "fear": 0, "familiarity": 5}, "I dealt with those bandits for you."],
	["After the gift", {"trust": 23, "respect": 15, "affection": 23, "fear": 0, "familiarity": 15}, "I found this book about horses for Elena."],
	["Trusted friend", {"trust": 51, "respect": 35, "affection": 43, "fear": -10, "familiarity": 30}, "You fought well back there."],
]

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "RELATIONSHIP DIMENSIONS TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 RELATIONSHIP DIMENSIONS TEST")
	print("============================================================\n")
	_test_impacts()
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	_test_readings(builder)
	_test_guidance(builder)
	_test_prompt(builder)
	_test_archetypes(builder)
	_test_evolution(builder)
	builder.free()
	_finish()

func _test_impacts():
	print("Impacts (a familiar NPC, so trust is not dampened)")
	var npc = load("res://scripts/npcs/base_npc.gd").new()
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

	print("\nImpacts in context")
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

func _test_readings(builder):
	print("\nDimension readings")
	_check("Trust 75 = deep trust", "deeply" in builder._interpret_dimension("trust", 75).to_lower())
	_check("Trust -60 = betrayed", "betrayed" in builder._interpret_dimension("trust", -60))
	_check("Affection 75 = deep care", "possibly love" in builder._interpret_dimension("affection", 75))
	_check("Affection -60 = active dislike", "actively dislike" in builder._interpret_dimension("affection", -60))
	_check("Fear -30 = safe", "safe" in builder._interpret_dimension("fear", -30).to_lower())
	_check("Fear -25 = not afraid (the 'safe' band starts below -25)", builder._interpret_dimension("fear", -25) == "You're not afraid of them")
	_check("Fear 80 = terrified", "terrified" in builder._interpret_dimension("fear", 80))
	_check("Familiarity 10 = stranger", "stranger" in builder._interpret_dimension("familiarity", 10))
	_check("Respect 50 = capable", "capable" in builder._interpret_dimension("respect", 50))
	_check("Unknown dimension", builder._interpret_dimension("loyalty", 50) == "Unknown")

func _test_guidance(builder):
	print("\nBehavioral guidance")
	var close = builder._generate_behavioral_guidance({"trust": 75, "respect": 60, "affection": 75, "fear": -10, "familiarity": 65}).to_lower()
	_check("High trust: share secrets", "share secrets" in close)
	_check("High affection (>70): warmth", "warmth" in close)
	_check("High familiarity: shared history", "shared history" in close)
	_check("All three high: intimate bond", "intimate bond" in close)
	var at_seventy = builder._generate_behavioral_guidance({"affection": 70}).to_lower()
	_check("Affection exactly 70 is friendly, not warm (threshold is > 70)", "friendly and welcoming" in at_seventy and not "warmth" in at_seventy)
	var conflicted = builder._generate_behavioral_guidance({"trust": 15, "respect": 70, "affection": 10, "fear": 10, "familiarity": 30}).to_lower()
	_check("Respect 70 + trust 15: CONFLICTED", "conflicted" in conflicted and "respect but don't trust" in conflicted)
	_check("Guidance always has its header", builder._generate_behavioral_guidance({}).begins_with("**How these feelings affect your behavior:**"))

func _test_prompt(builder):
	print("\nThe prompt (after four good interactions)")
	var context = builder.build_context({
		"system_prompt": "You are Gregor, a friendly merchant in Thornhaven village. You have a daughter named Elena who you worry about constantly.",
		"relationship_dimensions": STAGES[3][1],
		"conversation_history": [],
		"player_input": "Hey Gregor, how are things?"
	})
	var prompt: String = context.system_prompt
	_check("Multi-dimensional relationship section", "## Your Multi-Dimensional Relationship with the Player" in prompt)
	_check("No legacy single-score section", not "## Current Relationship with Player" in prompt)
	_check("Trust 51 reads as trusting", "**Trust:** 51/100 - You trust them - they seem reliable" in prompt)
	_check("Respect 35 reads as growing respect", "**Respect:** 35/100 - You're starting to respect them" in prompt)
	_check("Affection 43 reads as warming up", "**Affection:** 43/100 - You're warming up to them" in prompt)
	_check("Fear -10 reads as unafraid", "**Fear:** -10/100 - You're not afraid of them" in prompt)
	_check("Familiarity 30 reads as getting to know", "**Familiarity:** 30/100 - You're getting to know them" in prompt)
	_check("Behavioral guidance follows", "**How these feelings affect your behavior:**" in prompt and "trust is building" in prompt)
	_check("One message: the player's input", context.messages.size() == 1 and context.messages[0].content == "Hey Gregor, how are things?")

func _test_archetypes(builder):
	print("\nFive archetypal relationships")
	for c in ARCHETYPES:
		var prompt: String = builder.build_context({"system_prompt": "You are a test character.", "relationship_dimensions": c[1], "player_input": "Hello"}).system_prompt
		_check("%s: trust reading in the prompt" % c[0], ("**Trust:** %d/100 - %s" % [c[1].trust, builder._interpret_dimension("trust", c[1].trust)]) in prompt)
		for phrase in c[2]:
			_check("%s: guidance has \"%s\"" % [c[0], phrase], phrase in prompt)
		for phrase in c[3]:
			_check("%s: guidance lacks \"%s\"" % [c[0], phrase], not phrase in prompt)

func _test_evolution(builder):
	print("\nFrom stranger to trusted friend")
	var sections = []
	var guidance = []
	for stage in STAGES:
		var context = builder.build_context({"system_prompt": GREGOR, "relationship_dimensions": stage[1], "conversation_history": [], "player_input": stage[2]})
		var prompt: String = context.system_prompt
		_check("%s: the player's line is the message" % stage[0], context.messages[-1].content == stage[2])
		var start = prompt.find("**Trust:**")
		var stop = prompt.find("\n\n", prompt.find("**Familiarity:**"))
		_check("%s: dimension readings present" % stage[0], start >= 0 and stop > start)
		sections.append(prompt.substr(start, stop - start))
		var g_start = prompt.find("**How these feelings affect your behavior:**")
		guidance.append(prompt.substr(g_start, prompt.find("## Roleplay Instructions") - g_start) if g_start >= 0 else "")
	for i in range(1, STAGES.size()):
		_check("'%s' reads differently from '%s'" % [STAGES[i][0], STAGES[i - 1][0]], sections[i] != sections[i - 1])
	_check("A stranger is treated formally", "Formal, asking basic questions" in guidance[0])
	_check("A trusted friend is no longer treated formally", not "Formal, asking basic questions" in guidance[3])
	_check("A trusted friend gets a friendly tone", "Friendly and welcoming tone" in guidance[3])
	_check("Stage 1 trust reads cautious", "cautious" in sections[0])

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
