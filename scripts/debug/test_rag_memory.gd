extends SceneTree

# Tests RAGMemory in both modes:
# - in memory (always runs): structured conversation memories from store_conversation (topics,
#   intent, emotion, importance), store_player_action's default emotions, keyword recall
#   (absorbed test_enhanced_memory.gd)
# - over the local ChromaDB: initialize, the store helpers (conversation, witnessed event, quest),
#   semantic retrieval, importance filtering, recent memories and clearing
# The ChromaDB part uses a temp directory (LAND_CHROMA_PATH), never ./chroma, and is skipped when
# python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_rag_memory.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "RAGMEMORY INTEGRATION TEST")
	print("============================================================")
	print("🧪 RAGMEMORY INTEGRATION TEST")
	print("============================================================\n")
	await _test_in_memory()
	if not Support.chroma_available():
		print("\nChromaDB part SKIPPED (python3 cannot import chromadb)")
		_finish()
		return
	print("\nOver ChromaDB")
	var chroma_dir = Support.use_temp_chroma()
	var chroma = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma)
	var rag = load("res://scripts/npcs/rag_memory.gd").new()
	root.add_child(rag)

	_check("Initializes against ChromaDB", await rag.initialize("test_aldric", chroma))
	_check("Stays in ChromaDB mode", rag.use_chromadb)

	_check("store_conversation", await rag.store_conversation("player", "Do you know anything about the rebellion?", {"emotion": "cautious"}))
	_check("store_witnessed_event", await rag.store_witnessed_event("The player stole bread from the market stall", 9, "disapproving"))
	_check("store", await rag.store({
		"text": "The player asked about magical swords. I told them about the Frostblade in the northern mountains.",
		"event_type": "conversation", "importance": 7, "emotion": "helpful", "participants": ["player"], "location": "my_shop"
	}))
	_check("store_quest_memory", await rag.store_quest_memory("find_lost_sword", "completed successfully", 8))
	_check("store (low importance)", await rag.store({"text": "It rained today. The roads are muddy.", "event_type": "observation", "importance": 2, "emotion": "neutral"}))
	_check("All 5 memories are in the collection", await rag.get_memory_count() == 5)

	var crime = await rag.retrieve_relevant("player crimes theft stealing", {"limit": 1})
	_check("A theft query recalls the theft", crime.size() == 1 and "bread" in crime[0])
	var weapons = await rag.retrieve_relevant("weapons swords magic items", {"limit": 1})
	_check("A weapons query recalls the magical swords", weapons.size() == 1 and "magical swords" in weapons[0])
	_check("Recalled memories carry their event type and importance", weapons.size() == 1 and weapons[0].begins_with("[Memory - conversation, importance: 7"))

	var important = await rag.retrieve_relevant("player", {"limit": 10, "min_importance": 7})
	_check("min_importance 7 keeps only the 3 memories at 7+", important.size() == 3)
	var default_floor = await rag.retrieve_relevant("weather rain roads", {"limit": 10})
	_check("The default importance floor drops the importance-2 weather", not default_floor.any(func(m): return "rained" in m))

	var recent = await rag.get_recent(3)
	_check("get_recent returns 3", recent.size() == 3)

	await rag.clear_all_memories()
	_check("clear_all_memories empties the collection", await rag.get_memory_count() == 0)

	rag.free()
	chroma.free()
	Support.remove_temp_chroma(chroma_dir)
	_finish()

func _test_in_memory():
	print("In memory")
	var memory = load("res://scripts/npcs/rag_memory.gd").new()
	root.add_child(memory)
	_check("Initializes in-memory", await memory.initialize("test_agent_memory", null, false) and not memory.use_chromadb)
	_check("Player question stored", await memory.store_conversation("player", "Do you have any quests?", {"topics": ["quest", "help"], "intent": "asking_for_help", "emotion": "hopeful", "importance": 8}))
	_check("NPC answer stored", await memory.store_conversation("npc", "Yes! Bandits raiding wagons.", {"topics": ["quest", "bandits"], "importance": 7}))
	_check("Player action stored", await memory.store_player_action("quest_accepted", "Player agreed to deal with bandits", 9))
	var cache: Array = memory.memory_cache
	_check("Three memories, none overwritten", cache.size() == 3)
	if cache.size() == 3:
		var question = cache[0]
		_check("Player line is remembered from the NPC's side, with topics and intent", (question.get("document_full", question.document)).begins_with("Player said: \"Do you have any quests?\" (discussing: quest, help) [Player seemed to be asking_for_help]"))
		_check("Topics flattened for ChromaDB metadata", question.metadata.get("topics") == "quest,help")
		_check("Intent kept as metadata", question.metadata.get("player_intent") == "asking_for_help")
		_check("Importance override kept", question.metadata.get("importance") == 8)
		_check("NPC line is in the first person", (cache[1].get("document_full", cache[1].document)).begins_with("I told the player: \"Yes! Bandits raiding wagons.\""))
		_check("Quest acceptance defaults to feeling hopeful", cache[2].metadata.get("emotion") == "hopeful" and cache[2].metadata.get("event_type") == "quest_accepted")
	var recalled = await memory.retrieve_relevant("bandits quest", {"limit": 5})
	_check("Recall finds all three", recalled.size() == 3)
	_check("The most important memory comes first", recalled.size() > 0 and "quest_accepted" in recalled[0])
	memory.queue_free()
	await process_frame

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
