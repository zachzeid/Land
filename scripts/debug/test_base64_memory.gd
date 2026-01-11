extends SceneTree

func _init():
	print("=== Testing Base64 ChromaDB Memory Storage ===")
	
	# Load ChromaClient
	var ChromaClient = load("res://scripts/memory/chroma_client.gd")
	var chroma = ChromaClient.new()
	
	# Test storing memory with metadata
	var test_memory = {
		"collection": "npc_gregor_merchant_001_memories",
		"id": "test_godot_base64_%d" % Time.get_unix_time_from_system(),
		"document": "This is a test from Godot using base64 encoding for metadata",
		"metadata": {
			"event_type": "test",
			"importance": 8,
			"emotion": "curious",
			"timestamp": Time.get_unix_time_from_system()
		}
	}
	
	print("\nStoring memory with metadata:")
	print("  ID: ", test_memory.id)
	print("  Metadata: ", JSON.stringify(test_memory.metadata))
	
	var result = chroma.add_memory(test_memory)
	print("\nResult: ", JSON.stringify(result))
	
	if result.has("success"):
		print("✓ Memory stored successfully!")
		
		# Query to verify
		print("\nQuerying for the memory...")
		var query_result = chroma.query_memories({
			"collection": "npc_gregor_merchant_001_memories",
			"query": "test godot base64",
			"limit": 3
		})
		
		print("Query result: ", JSON.stringify(query_result))
		
		if query_result.has("memories") and query_result.memories.size() > 0:
			print("✓ Found %d memories" % query_result.memories.size())
			for mem in query_result.memories:
				print("  - %s: %s (distance: %.3f)" % [mem.id, mem.document.substr(0, 50), mem.distance])
				if mem.has("metadata"):
					print("    Metadata: ", JSON.stringify(mem.metadata))
		else:
			print("✗ No memories found")
	else:
		print("✗ Failed to store memory: ", result.get("error", "Unknown error"))
	
	quit()
