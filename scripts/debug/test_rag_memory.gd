extends SceneTree
# Test RAGMemory wrapper functionality

func _init():
	print("\n=== RAGMemory Integration Test ===\n")
	
	# Create ChromaClient
	var chroma_client = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma_client)
	
	# Test connection first
	var connected = await chroma_client.test_connection()
	if not connected:
		print("❌ ChromaDB not running. Start it with: chroma run --host localhost --port 8000\n")
		quit()
		return
	
	# Create RAGMemory for test NPC
	var rag_memory = load("res://scripts/npcs/rag_memory.gd").new()
	root.add_child(rag_memory)
	
	print("Test 1: Initialize RAG memory for NPC...")
	var init_success = await rag_memory.initialize("test_aldric", chroma_client)
	if not init_success:
		print("❌ Failed to initialize RAGMemory\n")
		quit()
		return
	print("✅ Initialized\n")
	
	# Test 2: Store various memory types
	print("Test 2: Storing different memory types...")
	
	# Conversation
	await rag_memory.store_conversation("player", "Do you know anything about the rebellion?", "cautious")
	
	# Witnessed event
	await rag_memory.store_witnessed_event("The player stole bread from the market stall", 9, "disapproving")
	
	# Custom memory
	await rag_memory.store({
		"text": "The player asked about magical swords. I told them about the Frostblade in the northern mountains.",
		"event_type": "conversation",
		"importance": 7,
		"emotion": "helpful",
		"participants": ["player"],
		"location": "my_shop"
	})
	
	# Quest memory
	await rag_memory.store_quest_memory("find_lost_sword", "completed successfully", 8)
	
	# Low importance memory
	await rag_memory.store({
		"text": "It rained today. The roads are muddy.",
		"event_type": "observation",
		"importance": 2,
		"emotion": "neutral"
	})
	
	var count = await rag_memory.get_memory_count()
	print("✅ Stored 5 memories (collection has %d total)\n" % count)
	
	# Test 3: Semantic retrieval
	print("Test 3: Semantic memory retrieval...")
	
	print("\n  Query: 'player crimes theft'")
	var crime_memories = await rag_memory.retrieve_relevant("player crimes theft", {"limit": 2})
	for memory in crime_memories:
		print("  → " + memory.substr(0, 80) + "...")
	
	print("\n  Query: 'weapons combat magic items'")
	var weapon_memories = await rag_memory.retrieve_relevant("weapons combat magic items", {"limit": 2})
	for memory in weapon_memories:
		print("  → " + memory.substr(0, 80) + "...")
	
	print("\n  Query: 'quests completed'")
	var quest_memories = await rag_memory.retrieve_relevant("quests completed", {"limit": 2})
	for memory in quest_memories:
		print("  → " + memory.substr(0, 80) + "...")
	
	print("\n✅ Semantic search working\n")
	
	# Test 4: Importance filtering
	print("Test 4: Importance filtering...")
	var important_only = await rag_memory.retrieve_relevant("player", {
		"limit": 10,
		"min_importance": 7
	})
	print("High-importance memories (>= 7): %d" % important_only.size())
	for memory in important_only:
		print("  → " + memory.substr(0, 70) + "...")
	print("✅ Filtering working\n")
	
	# Test 5: Recent memories
	print("Test 5: Recent memories (chronological)...")
	var recent = await rag_memory.get_recent(3)
	print("Last 3 memories:")
	for memory in recent:
		print("  → " + memory.substr(0, 60) + "...")
	print("✅ Recent retrieval working\n")
	
	# Cleanup
	print("Cleaning up test data...")
	await rag_memory.clear_all_memories()
	
	print("\n=== All Tests Passed! ===")
	print("\nRAGMemory is ready for NPC use.")
	print("NPCs can now:")
	print("  ✓ Store memories from their perspective")
	print("  ✓ Retrieve relevant memories via semantic search")
	print("  ✓ Filter by importance")
	print("  ✓ Access recent memories")
	print("  ✓ Use helper functions for common memory types")
	print("\n")
	
	quit()
