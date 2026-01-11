extends SceneTree

func _init():
	print("=== Testing Enhanced AI-Agent Memory ===\n")
	
	var RAGMemory = load("res://scripts/npcs/rag_memory.gd")
	var memory = RAGMemory.new()
	
	await memory.initialize("test_agent_memory", null, true)
	
	print("1. Storing conversation with topics & intent:\n")
	
	await memory.store_conversation("player", "Do you have any quests?", {
		"topics": ["quest", "help"],
		"intent": "asking_for_help",
		"emotion": "hopeful",
		"importance": 8
	})
	print("  ✓ Player question stored")
	
	await memory.store_conversation("npc", "Yes! Bandits raiding wagons.", {
		"topics": ["quest", "bandits"],
		"importance": 7
	})
	print("  ✓ NPC response stored")
	
	print("\n2. Storing player action:\n")
	
	await memory.store_player_action(
		"quest_accepted",
		"Player agreed to deal with bandits",
		9
	)
	print("  ✓ Quest acceptance stored")
	
	print("\n3. Querying memories:\n")
	
	var mems = await memory.retrieve_relevant("bandits quest", {"limit": 5})
	print("  Found %d memories about bandits/quest" % mems.size())
	
	print("\n✓ Test complete!")
	quit()
