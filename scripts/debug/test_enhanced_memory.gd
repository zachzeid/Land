extends SceneTree

# Tests RAGMemory's structured conversation memories in in-memory mode: store_conversation
# (topics, intent, emotion, importance), store_player_action (default emotions) and keyword recall
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_enhanced_memory.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "ENHANCED AGENT MEMORY TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 ENHANCED AGENT MEMORY TEST")
	print("============================================================\n")
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
	_finish()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
