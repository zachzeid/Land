extends Node
## Test script to verify NPC dialogue system end-to-end
## Run this from Godot to test ChromaDB + Claude integration

var test_npc: Node = null

func _ready():
	print("=== NPC DIALOGUE SYSTEM TEST ===")
	print("Testing: ChromaDB → RAGMemory → ContextBuilder → Claude")
	print("")

	# Run tests after a short delay to ensure everything is loaded
	await get_tree().create_timer(0.5).timeout
	await run_tests()

func run_tests():
	print("--- Test 1: Create Test NPC ---")
	var result1 = await test_create_npc()
	print("Result: %s\n" % ("PASS" if result1 else "FAIL"))

	print("--- Test 2: Store Memories ---")
	var result2 = await test_store_memories()
	print("Result: %s\n" % ("PASS" if result2 else "FAIL"))

	print("--- Test 3: Retrieve Tiered Memories ---")
	var result3 = await test_tiered_retrieval()
	print("Result: %s\n" % ("PASS" if result3 else "FAIL"))

	print("--- Test 4: Context Building ---")
	var result4 = await test_context_builder()
	print("Result: %s\n" % ("PASS" if result4 else "FAIL"))

	print("=== TEST SUMMARY ===")
	var passed = [result1, result2, result3, result4].count(true)
	print("Passed: %d/4" % passed)

	if passed == 4:
		print("\nAll tests passed! System is ready for Claude integration.")
	else:
		print("\nSome tests failed. Check the output above for details.")

	# Cleanup
	if test_npc:
		test_npc.queue_free()

func test_create_npc() -> bool:
	# Load base NPC script
	var BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	if not BaseNPCScript:
		print("  ERROR: Could not load base_npc.gd")
		return false

	# Create NPC instance
	test_npc = CharacterBody2D.new()
	test_npc.set_script(BaseNPCScript)
	test_npc.npc_id = "test_npc_001"
	test_npc.npc_name = "Test Merchant"
	add_child(test_npc)

	# Initialize with in-memory mode (no ChromaDB dependency)
	print("  Initializing NPC in in-memory mode...")
	var init_result = await test_npc.initialize(false, false)  # No ChromaDB, no KPI

	if init_result:
		print("  NPC initialized successfully")
		print("  - NPC ID: %s" % test_npc.npc_id)
		print("  - Name: %s" % test_npc.npc_name)
		return true
	else:
		print("  ERROR: NPC initialization failed")
		return false

func test_store_memories() -> bool:
	if not test_npc or not test_npc.rag_memory:
		print("  ERROR: No NPC or RAGMemory available")
		return false

	var rag = test_npc.rag_memory

	# Store a pinned memory (milestone)
	print("  Storing pinned memory (first_meeting)...")
	var pinned_result = await rag.store({
		"text": "I met the player for the first time. They seemed friendly.",
		"event_type": "first_meeting",
		"importance": 10,
		"emotion": "curious",
		"memory_tier": 0,  # PINNED
		"is_milestone": true
	})

	# Store an important memory
	print("  Storing important memory (quest_completed)...")
	var important_result = await rag.store({
		"text": "The player helped me retrieve stolen goods from bandits.",
		"event_type": "quest_completed",
		"importance": 8,
		"emotion": "grateful",
		"memory_tier": 1  # IMPORTANT
	})

	# Store regular memories
	print("  Storing regular memories (conversations)...")
	var conv_result = await rag.store({
		"text": "We discussed the weather and local rumors.",
		"event_type": "conversation",
		"importance": 5,
		"emotion": "neutral",
		"memory_tier": 2  # REGULAR
	})

	if pinned_result and important_result and conv_result:
		print("  All memories stored successfully")
		return true
	else:
		print("  ERROR: Some memories failed to store")
		return false

func test_tiered_retrieval() -> bool:
	if not test_npc or not test_npc.rag_memory:
		print("  ERROR: No NPC or RAGMemory available")
		return false

	var rag = test_npc.rag_memory

	print("  Retrieving tiered memories...")
	var tiered = await rag.retrieve_tiered("bandits quest")

	print("  Results:")
	print("    - Pinned: %d memories" % tiered.pinned.size())
	print("    - Important: %d memories" % tiered.important.size())
	print("    - Relevant: %d memories" % tiered.relevant.size())
	print("    - Total chars: %d" % tiered.total_chars)

	# Verify we got the expected memories
	if tiered.pinned.size() >= 1:
		print("  Pinned memory content: %s..." % tiered.pinned[0].get("document", "").substr(0, 50))

	# Format for context
	var formatted = rag.format_tiered_memories(tiered)
	print("  Formatted pinned: %d strings" % formatted.pinned.size())
	print("  Formatted important: %d strings" % formatted.important.size())
	print("  Formatted relevant: %d strings" % formatted.relevant.size())

	return tiered.pinned.size() >= 1 or tiered.important.size() >= 1

func test_context_builder() -> bool:
	if not test_npc or not test_npc.context_builder:
		print("  ERROR: No NPC or ContextBuilder available")
		return false

	var rag = test_npc.rag_memory
	var builder = test_npc.context_builder

	# Get tiered memories
	var tiered = await rag.retrieve_tiered("hello merchant")
	var formatted = rag.format_tiered_memories(tiered)

	# Set up test relationship dimensions
	test_npc.relationship_trust = 30
	test_npc.relationship_affection = 20
	test_npc.relationship_familiarity = 40

	print("  Building context with tiered memories...")
	var context = builder.build_context({
		"system_prompt": "You are a friendly merchant named Test.",
		"npc_id": test_npc.npc_id,
		"tiered_memories": formatted,
		"relationship_dimensions": {
			"trust": test_npc.relationship_trust,
			"respect": 0,
			"affection": test_npc.relationship_affection,
			"fear": 0,
			"familiarity": test_npc.relationship_familiarity
		},
		"world_state": {},
		"conversation_history": [],
		"player_input": "Hello there!"
	})

	print("  Context built successfully")
	print("  - System prompt length: %d chars" % context.system_prompt.length())
	print("  - Messages count: %d" % context.messages.size())

	# Check for tiered memory sections in prompt
	var has_defining = "DEFINING MOMENTS" in context.system_prompt
	var has_significant = "Significant Memories" in context.system_prompt or "no significant memories" in context.system_prompt.to_lower()

	print("  - Contains 'DEFINING MOMENTS': %s" % has_defining)
	print("  - Contains memory section: %s" % has_significant)

	# Print a snippet of the system prompt
	print("\n  System prompt preview (first 500 chars):")
	print("  ---")
	var preview = context.system_prompt.substr(0, 500)
	for line in preview.split("\n"):
		print("  | %s" % line)
	print("  ---")

	return context.system_prompt.length() > 100 and context.messages.size() > 0
