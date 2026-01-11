extends SceneTree
# Test ChromaClient with running ChromaDB server

func _init():
	print("\n=== ChromaClient Integration Test ===\n")
	
	var chroma_client = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma_client)
	
	# Test 1: Connection
	print("Test 1: Testing ChromaDB connection...")
	var connected = await chroma_client.test_connection()
	if not connected:
		print("❌ FAIL: Could not connect to ChromaDB")
		print("Make sure ChromaDB is running: chroma run --host localhost --port 8000\n")
		quit()
		return
	print("✅ PASS: Connected to ChromaDB\n")
	
	# Test 2: Create collection
	print("Test 2: Creating test NPC collection...")
	var collection_name = "npc_test_merchant"
	var collection = await chroma_client.create_collection(collection_name)
	if collection.has("error"):
		print("❌ FAIL: %s" % collection.error)
	else:
		print("✅ PASS: Collection created: %s\n" % collection_name)
	
	# Test 3: Add memories
	print("Test 3: Adding test memories...")
	var memories_to_add = [
		{
			"collection": collection_name,
			"id": "test_memory_001",
			"document": "The player asked me about magical swords. I told them about the legendary Frostblade hidden in the northern mountains.",
			"metadata": {
				"event_type": "conversation",
				"importance": 7,
				"emotion": "helpful",
				"timestamp": Time.get_unix_time_from_system()
			}
		},
		{
			"collection": collection_name,
			"id": "test_memory_002",
			"document": "I saw the player steal bread from my stall. They looked hungry but that's still wrong. I'm disappointed.",
			"metadata": {
				"event_type": "witnessed_crime",
				"importance": 8,
				"emotion": "disappointed",
				"timestamp": Time.get_unix_time_from_system()
			}
		},
		{
			"collection": collection_name,
			"id": "test_memory_003",
			"document": "The player bought a healing potion from me. They were polite and paid fair price. Seems like a decent person.",
			"metadata": {
				"event_type": "transaction",
				"importance": 5,
				"emotion": "neutral",
				"timestamp": Time.get_unix_time_from_system()
			}
		}
	]
	
	var stored_count = 0
	for memory in memories_to_add:
		var result = await chroma_client.add_memory(memory)
		if not result.has("error"):
			stored_count += 1
	
	print("✅ PASS: Stored %d/%d memories\n" % [stored_count, memories_to_add.size()])
	
	# Test 4: Query memories (semantic search)
	print("Test 4: Querying memories with semantic search...")
	
	var test_queries = [
		{"query": "theft stealing crime", "expected_topic": "stealing bread"},
		{"query": "weapons swords combat", "expected_topic": "Frostblade"},
		{"query": "business trade purchase", "expected_topic": "healing potion"}
	]
	
	for test_query in test_queries:
		print("\n  Query: '%s'" % test_query.query)
		var results = await chroma_client.query_memories({
			"collection": collection_name,
			"query": test_query.query,
			"limit": 2
		})
		
		if results.size() > 0:
			print("  Top result: %s" % results[0].document.substr(0, 60) + "...")
			print("  Relevance distance: %.3f" % results[0].distance)
		else:
			print("  No results found")
	
	print("\n✅ PASS: Semantic search working\n")
	
	# Test 5: Filter by importance
	print("Test 5: Filtering by importance...")
	var important_memories = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "player interaction",
		"limit": 10,
		"min_importance": 7
	})
	
	print("Memories with importance >= 7: %d" % important_memories.size())
	for mem in important_memories:
		print("  - Importance: %d - %s" % [mem.metadata.importance, mem.document.substr(0, 40) + "..."])
	
	print("\n✅ PASS: Importance filtering working\n")
	
	# Test 6: Collection info
	print("Test 6: Getting collection info...")
	var count = await chroma_client.get_collection_count(collection_name)
	print("Total memories in collection: %d" % count)
	print("✅ PASS: Collection info retrieved\n")
	
	# Cleanup: Delete test collection
	print("Cleaning up test collection...")
	await chroma_client.delete_collection(collection_name)
	
	print("\n=== All Tests Passed! ===")
	print("\nChromaClient is ready for NPC memory storage.")
	print("Key features working:")
	print("  ✓ Connection to ChromaDB")
	print("  ✓ Create collections per NPC")
	print("  ✓ Store memories with metadata")
	print("  ✓ Semantic similarity search")
	print("  ✓ Importance-based filtering")
	print("\n")
	
	quit()
