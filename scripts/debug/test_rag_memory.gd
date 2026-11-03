extends SceneTree

# Tests RAGMemory over the local ChromaDB: initialize, the store helpers (conversation, witnessed event,
# quest), semantic retrieval, importance filtering, recent memories and clearing
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
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
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
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

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
