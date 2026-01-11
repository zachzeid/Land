extends SceneTree

func _init():
	print("=== Testing ChromaClient with Multi-Word Documents ===")
	
	var ChromaClient = load("res://scripts/memory/chroma_client.gd")
	var chroma = ChromaClient.new()
	
	var test_memory = {
		"collection": "npc_gregor_merchant_001_memories",
		"id": "test_multiword_%d" % Time.get_unix_time_from_system(),
		"document": "Player asked about the bandits near the village",
		"metadata": {
			"event_type": "conversation",
			"importance": 7,
			"emotion": "concerned"
		}
	}
	
	print("\nStoring memory...")
	print("  Document: ", test_memory.document)
	print("  Metadata: ", JSON.stringify(test_memory.metadata))
	
	var result = chroma.add_memory(test_memory)
	print("\nResult: ", JSON.stringify(result))
	
	if result.has("success"):
		print("✓ Success!")
	else:
		print("✗ Failed: ", result.get("error"))
	
	quit()
