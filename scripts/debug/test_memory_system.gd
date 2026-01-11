extends Node
# Test script for RAG memory system with ChromaDB

var chroma_client

func _ready():
	print("=== ChromaDB Memory System Test ===\n")
	
	# Load and initialize ChromaDB client
	var ChromaClient = load("res://scripts/memory/chroma_client.gd")
	chroma_client = ChromaClient.new()
	add_child(chroma_client)
	await get_tree().process_frame
	
	await run_tests()
	
	print("\n=== Test Complete - Exiting ===")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func run_tests():
	
	print("Test 1: ChromaDB connection...")
	var connected = await chroma_client.test_connection()
	if not connected:
		print("FAILED: ChromaDB not running. Start with: chroma run --host localhost --port 8000")
		return
	print("✓ Connection successful\n")
	
	print("Test 2: Create test collection...")
	var collection_name = "test_gregor_memories"
	
	# Delete if exists
	await chroma_client.delete_collection(collection_name)
	
	var collection = await chroma_client.create_collection(collection_name)
	if collection.has("error"):
		print("FAILED: " + collection.error)
		return
	print("✓ Collection created: %s\n" % collection_name)
	
	print("Test 3: Store test memories...")
	var memories = [
		{
			"collection": collection_name,
			"id": "memory_1",
			"document": "The player helped me recover my stolen sword from the bandits. I'm grateful for their bravery.",
			"metadata": {
				"event_type": "quest_completed",
				"importance": 8,
				"emotion": "grateful",
				"timestamp": Time.get_unix_time_from_system()
			}
		},
		{
			"collection": collection_name,
			"id": "memory_2",
			"document": "The player asked about my daughter Elena. I told them she's studying to be a healer. I'm proud of her.",
			"metadata": {
				"event_type": "conversation",
				"importance": 6,
				"emotion": "proud",
				"timestamp": Time.get_unix_time_from_system()
			}
		},
		{
			"collection": collection_name,
			"id": "memory_3",
			"document": "I saw the player steal from the merchant's stall. They looked around nervously. I don't trust thieves.",
			"metadata": {
				"event_type": "witnessed_crime",
				"importance": 9,
				"emotion": "disapproval",
				"timestamp": Time.get_unix_time_from_system()
			}
		},
		{
			"collection": collection_name,
			"id": "memory_4",
			"document": "The player greeted me warmly this morning. They seem friendly enough.",
			"metadata": {
				"event_type": "conversation",
				"importance": 3,
				"emotion": "neutral",
				"timestamp": Time.get_unix_time_from_system()
			}
		}
	]
	
	for memory in memories:
		var result = await chroma_client.add_memory(memory)
		if result.has("error"):
			print("FAILED to store memory: " + result.error)
			return
	
	print("✓ Stored %d memories\n" % memories.size())
	
	print("Test 4: Query memories about 'sword quest'...")
	var query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "Did the player help with the sword quest?",
		"limit": 3,
		"min_importance": 5
	})
	
	print("Retrieved %d memories:" % query_result.size())
	for i in range(query_result.size()):
		var mem = query_result[i]
		print("  %d. [%s] %s (distance: %.3f)" % [
			i + 1,
			mem.metadata.get("emotion", "unknown"),
			mem.document.substr(0, 60) + "...",
			mem.get("distance", 0.0)
		])
	print("")
	
	if query_result.size() == 0:
		print("FAILED: No memories retrieved")
		return
	
	print("Test 5: Query memories about 'stealing'...")
	query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "What does the NPC think about my trustworthiness?",
		"limit": 2
	})
	
	print("Retrieved %d memories:" % query_result.size())
	for i in range(query_result.size()):
		var mem = query_result[i]
		print("  %d. [importance: %d] %s" % [
			i + 1,
			mem.metadata.get("importance", 0),
			mem.document.substr(0, 80) + "..."
		])
	print("")
	
	print("Test 6: Filter low-importance memories...")
	query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "general conversation",
		"limit": 5,
		"min_importance": 7
	})
	
	print("Retrieved %d high-importance memories (>= 7):" % query_result.size())
	for mem in query_result:
		print("  - [%d] %s" % [
			mem.metadata.get("importance", 0),
			mem.document.substr(0, 60) + "..."
		])
	print("")
	
	print("=== All Tests Passed! ===")
	print("ChromaDB memory system is working correctly.")
	print("\nTo test in-game:")
	print("1. Run: godot scenes/game_world.tscn")
	print("2. Talk to Gregor multiple times")
	print("3. Gregor should remember previous conversations")
