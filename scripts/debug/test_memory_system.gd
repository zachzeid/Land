extends SceneTree

# Tests the ChromaDB memory round trip NPC memories rely on: delete-then-recreate a collection,
# store four memories, semantic query with and without an importance floor
# Overlaps test_chroma_client.gd; kept for the delete-before-create and min_importance query paths
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_memory_system.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const COLLECTION = "test_gregor_memories"

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "CHROMADB MEMORY SYSTEM TEST")
	print("============================================================")
	print("🧪 CHROMADB MEMORY SYSTEM TEST")
	print("============================================================\n")
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
	var chroma_dir = Support.use_temp_chroma()
	var chroma = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma)

	_check("Deleting a collection that does not exist is harmless", not chroma.delete_collection(COLLECTION).has("error"))
	_check("Collection created", not chroma.create_collection(COLLECTION).has("error"))
	var memories = [
		["memory_1", "quest_completed", 8, "grateful", "The player helped me recover my stolen sword from the bandits. I'm grateful for their bravery."],
		["memory_2", "conversation", 6, "proud", "The player asked about my daughter Elena. I told them she's studying to be a healer. I'm proud of her."],
		["memory_3", "witnessed_crime", 9, "disapproval", "I saw the player steal from the merchant's stall. They looked around nervously. I don't trust thieves."],
		["memory_4", "conversation", 3, "neutral", "The player greeted me warmly this morning. They seem friendly enough."],
	]
	var stored = 0
	for m in memories:
		var result = chroma.add_memory({"collection": COLLECTION, "id": m[0], "document": m[4],
			"metadata": {"event_type": m[1], "importance": m[2], "emotion": m[3]}})
		if result.get("success", false):
			stored += 1
	_check("All 4 memories stored", stored == 4)

	var sword = chroma.query_memories({"collection": COLLECTION, "query": "Did the player help with the sword quest?", "limit": 3, "min_importance": 5})
	_check("The sword quest memory ranks first", sword.size() > 0 and sword[0].id == "memory_1")
	var above_floor = true
	for m in sword:
		above_floor = above_floor and int(m.metadata.importance) >= 5
	_check("min_importance 5 drops the importance-3 greeting", sword.size() == 3 and above_floor)

	var trust = chroma.query_memories({"collection": COLLECTION, "query": "Is the player a thief?", "limit": 2})
	_check("A query without a floor returns the limit", trust.size() == 2)
	_check("The theft memory is among them", trust.any(func(m): return m.id == "memory_3"))

	var high = chroma.query_memories({"collection": COLLECTION, "query": "general conversation", "limit": 5, "min_importance": 7})
	var ids = high.map(func(m): return m.id)
	ids.sort()
	_check("min_importance 7 returns exactly memories 1 and 3", ids == ["memory_1", "memory_3"])

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
