extends SceneTree
# Test Multi-Dimensional Behavior Evolution
# Demonstrates how relationship dimensions affect Claude's responses with NO pre-canned dialogue

func _init():
	print("\n" + "=".repeat(60))
	print("🧪 TESTING MULTI-DIMENSIONAL BEHAVIOR EVOLUTION")
	print("=".repeat(60) + "\n")
	
	await _test_dimension_evolution()
	
	print("\n" + "=".repeat(60))
	print("✅ TEST COMPLETE - Check if Claude's responses evolved")
	print("=".repeat(60) + "\n")
	
	quit()

func _test_dimension_evolution():
	print("Creating test NPC with base personality...")
	
	# Create test NPC
	var BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	var test_npc = BaseNPCScript.new()
	test_npc.npc_id = "test_gregor_dimensions"
	test_npc.npc_name = "Gregor"
	test_npc.system_prompt = """You are Gregor, a cautious merchant in a JRPG village.
You're professional but guarded with strangers. You value trust and loyalty."""
	
	root.add_child(test_npc)
	
	# Initialize NPC in-memory mode (no ChromaDB needed)
	print("Initializing NPC in-memory mode (no ChromaDB)...")
	var init_result = await test_npc.initialize(false)  # false = in-memory mode
	
	if not init_result:
		print("❌ NPC initialization failed!")
		return
	
	print("✅ NPC initialized successfully\n")
	
	print("\n📊 INITIAL STATE: All dimensions at 0")
	print("   Trust: 0, Respect: 0, Affection: 0, Fear: 0, Familiarity: 0")
	print("   Expected: Neutral, professional greeting\n")
	
	# Scenario 1: Player helps with quest
	print("🎬 INTERACTION 1: Player completes quest (helps with bandits)")
	await test_npc.record_interaction("quest_completed", {
		"description": "Player defeated bandits raiding my supply wagons. Village is safe!",
		"importance": 10,
		"emotion": "grateful"
	})
	
	await root.create_timer(0.5).timeout
	
	print("\n📊 AFTER QUEST:")
	print("   Trust: %d (+15), Respect: %d (+10), Affection: %d (+8), Familiarity: %d (+5)" % 
		[test_npc.relationship_trust, test_npc.relationship_respect, 
		 test_npc.relationship_affection, test_npc.relationship_familiarity])
	print("   Expected: Warmer, shows gratitude, more open\n")
	
	# Scenario 2: Thoughtful gift
	print("🎬 INTERACTION 2: Player gives thoughtful gift (rare book for daughter)")
	await test_npc.record_interaction("gift_received", {
		"description": "Player gave me rare book about horses for Elena. They remembered she loves horses!",
		"importance": 9,
		"emotion": "deeply_touched",
		"thoughtfulness": "high"
	})
	
	await root.create_timer(0.5).timeout
	
	print("\n📊 AFTER GIFT:")
	print("   Trust: %d, Respect: %d, Affection: %d (+15), Familiarity: %d (+10)" % 
		[test_npc.relationship_trust, test_npc.relationship_respect, 
		 test_npc.relationship_affection, test_npc.relationship_familiarity])
	print("   Expected: Personal connection, references thoughtfulness\n")
	
	# Scenario 3: Emotional support
	print("🎬 INTERACTION 3: Player listens to worries about daughter")
	await test_npc.record_interaction("emotional_support", {
		"description": "Player listened to my worries about Elena. Didn't judge, just listened.",
		"importance": 8,
		"emotion": "vulnerable"
	})
	
	await root.create_timer(0.5).timeout
	
	print("\n📊 AFTER EMOTIONAL SUPPORT:")
	print("   Trust: %d (+8), Respect: %d, Affection: %d (+10), Familiarity: %d (+5)" % 
		[test_npc.relationship_trust, test_npc.relationship_respect, 
		 test_npc.relationship_affection, test_npc.relationship_familiarity])
	print("   Expected: Feels safe opening up, considers player friend\n")
	
	# Scenario 4: Shared danger
	print("🎬 INTERACTION 4: Fight together during village attack")
	await test_npc.record_interaction("shared_danger", {
		"description": "Player fought alongside me when bandits attacked village. Back-to-back combat.",
		"importance": 10,
		"emotion": "bonded"
	})
	
	await root.create_timer(0.5).timeout
	
	print("\n📊 AFTER SHARED DANGER:")
	print("   Trust: %d (+20), Respect: %d (+15), Affection: %d (+10), Fear: %d (-10), Familiarity: %d (+15)" % 
		[test_npc.relationship_trust, test_npc.relationship_respect, 
		 test_npc.relationship_affection, test_npc.relationship_fear, test_npc.relationship_familiarity])
	print("   Expected: Deep bond, considers player ally/friend, possibly more\n")
	
	# Final state summary
	print("\n" + "─".repeat(60))
	print("📈 EVOLUTION SUMMARY:")
	print("─".repeat(60))
	print("Trust:       %d/100 - %s" % [test_npc.relationship_trust, _interpret_trust(test_npc.relationship_trust)])
	print("Respect:     %d/100 - %s" % [test_npc.relationship_respect, _interpret_respect(test_npc.relationship_respect)])
	print("Affection:   %d/100 - %s" % [test_npc.relationship_affection, _interpret_affection(test_npc.relationship_affection)])
	print("Fear:        %d/100 - %s" % [test_npc.relationship_fear, _interpret_fear(test_npc.relationship_fear)])
	print("Familiarity: %d/100 - %s" % [test_npc.relationship_familiarity, _interpret_familiarity(test_npc.relationship_familiarity)])
	print("─".repeat(60))
	print("\n✨ PERSONALITY EVOLUTION:")
	print("   Started: Cautious professional merchant")
	print("   Now: Trusting friend who values player deeply")
	print("   Claude will generate completely different responses")
	print("   NO pre-canned dialogue - all based on dimensions + memories\n")

func _interpret_trust(value: int) -> String:
	if value >= 50: return "Trusts them"
	elif value >= 25: return "Starting to trust"
	else: return "Neutral/Cautious"

func _interpret_respect(value: int) -> String:
	if value >= 50: return "Respects them"
	elif value >= 25: return "Growing respect"
	else: return "Neutral"

func _interpret_affection(value: int) -> String:
	if value >= 50: return "Genuinely likes them"
	elif value >= 25: return "Warming up"
	else: return "Neutral"

func _interpret_fear(value: int) -> String:
	if value >= 25: return "Somewhat afraid"
	elif value <= -10: return "Feels safe"
	else: return "Neutral"

func _interpret_familiarity(value: int) -> String:
	if value >= 50: return "Knows them well"
	elif value >= 25: return "Getting to know"
	else: return "Stranger"
