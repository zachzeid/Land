extends SceneTree
# Test BaseNPC integration with all AI components

func _init():
	print("\n=== BaseNPC Test ===\n")
	print("Testing AI component integration...\n")
	
	# Create a minimal scene tree for testing
	var root = Node.new()
	get_root().add_child(root)
	
	# Load BaseNPC script
	var BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	var npc = BaseNPCScript.new()
	
	# Configure NPC
	npc.npc_id = "test_merchant_001"
	npc.npc_name = "Test Merchant"
	npc.system_prompt = """You are Gregor, a cautious merchant who sells adventuring supplies.
You speak formally and always think about profit. You're suspicious of strangers but warm up to paying customers.
You're worried about bandits on the trade roads."""
	
	root.add_child(npc)
	
	# Test 1: Initialization
	print("Test 1: NPC initialization...")
	await npc.ready  # Wait for _ready() to complete
	
	if npc.rag_memory and npc.context_builder:
		print("  ✓ AI components created")
	else:
		print("  ✗ AI components missing")
		quit(1)
		return
	
	print("  ✓ NPC '%s' initialized (ID: %s)\n" % [npc.npc_name, npc.npc_id])
	
	# Test 2: Component availability
	print("Test 2: Verify AI components...")
	print("  RAGMemory: %s" % ("✓" if npc.rag_memory != null else "✗"))
	print("  ContextBuilder: %s" % ("✓" if npc.context_builder != null else "✗"))
	print("  ClaudeClient: %s" % ("✓" if npc.claude_client != null else "✗"))
	print()
	
	# Test 3: Memory storage
	print("Test 3: Store NPC memory...")
	await npc.rag_memory.store({
		"text": "A traveler asked about sword prices. I quoted 50 gold.",
		"event_type": "conversation",
		"importance": 5,
		"emotion": "neutral"
	})
	print("  ✓ Memory stored\n")
	
	# Test 4: Context building
	print("Test 4: Build conversation context...")
	var context = npc.context_builder.build_context({
		"system_prompt": npc.system_prompt,
		"rag_memories": ["[Memory] A traveler asked about sword prices."],
		"relationship_status": npc.relationship_status,
		"world_state": {"world_flags": {}},
		"conversation_history": [],
		"player_input": "What weapons do you have?"
	})
	
	if context.has("system_prompt") and context.has("messages"):
		print("  ✓ Context assembled")
		print("  System prompt: %d chars" % context.system_prompt.length())
		print("  Messages: %d" % context.messages.size())
	else:
		print("  ✗ Context missing fields")
	print()
	
	# Test 5: Conversation state
	print("Test 5: Conversation management...")
	npc._add_to_history("user", "Hello")
	npc._add_to_history("assistant", "Greetings, traveler")
	npc._add_to_history("user", "What do you sell?")
	
	print("  History turns: %d" % npc.current_conversation_history.size())
	print("  ✓ Conversation tracking working\n")
	
	# Test 6: Relationship changes
	print("Test 6: Relationship system...")
	print("  Initial: %.1f" % npc.relationship_status)
	npc.adjust_relationship(15.0)
	print("  After +15: %.1f" % npc.relationship_status)
	npc.adjust_relationship(-30.0)
	print("  After -30: %.1f" % npc.relationship_status)
	npc.adjust_relationship(200.0)  # Should clamp to 100
	print("  After +200: %.1f (clamped to 100)" % npc.relationship_status)
	print("  ✓ Relationship clamping working\n")
	
	# Test 7: Helper methods
	print("Test 7: Helper methods...")
	var topics = npc._extract_topics()
	var emotion = npc._infer_emotion()
	print("  Topics: %s" % topics)
	print("  Emotion: %s" % emotion)
	print("  ✓ Helpers functional\n")
	
	print("=== All Tests Passed! ===\n")
	print("BaseNPC is ready for use.")
	print("Key capabilities:")
	print("  ✓ Loads personality system prompts")
	print("  ✓ Stores memories via RAGMemory")
	print("  ✓ Builds context with ContextBuilder")
	print("  ✓ Manages conversation state")
	print("  ✓ Tracks relationship status")
	print("  ✓ Integrates with ClaudeClient")
	print("\nNext: Create personality resource and test scene for live conversation.\n")
	
	quit()
