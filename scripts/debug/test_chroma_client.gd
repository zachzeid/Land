extends SceneTree

# Tests ChromaClient against the local ChromaDB (chroma_cli.py, PersistentClient):
# connection, collections, storing memories, semantic search, importance filtering, counts, deletion
# (absorbed test_memory_system.gd, which overlapped it)
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_chroma_client.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const COLLECTION = "npc_test_merchant"

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "CHROMACLIENT INTEGRATION TEST")
	print("============================================================")
	print("🧪 CHROMACLIENT INTEGRATION TEST")
	print("============================================================\n")
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
	var chroma_dir = Support.use_temp_chroma()
	var chroma = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma)

	_check("Connection works", chroma.test_connection())
	_check("Deleting a collection that does not exist is harmless", not chroma.delete_collection("test_never_created").has("error"))
	_check("Collection created", not chroma.create_collection(COLLECTION).has("error"))

	var now = Time.get_unix_time_from_system()
	var memories = [
		{"id": "test_memory_001", "event_type": "conversation", "importance": 7, "emotion": "helpful",
			"document": "The player asked me about magical swords. I told them about the legendary Frostblade hidden in the northern mountains."},
		{"id": "test_memory_002", "event_type": "witnessed_crime", "importance": 8, "emotion": "disappointed",
			"document": "I saw the player steal bread from my stall. They looked hungry but that's still wrong. I'm disappointed."},
		{"id": "test_memory_003", "event_type": "transaction", "importance": 5, "emotion": "neutral",
			"document": "The player bought a healing potion from me. They were polite and paid fair price. Seems like a decent person."},
	]
	var stored = 0
	for m in memories:
		var result = chroma.add_memory({"collection": COLLECTION, "id": m.id, "document": m.document,
			"metadata": {"event_type": m.event_type, "importance": m.importance, "emotion": m.emotion, "timestamp": now}})
		if result.get("success", false):
			stored += 1
	_check("All 3 memories stored", stored == 3)
	_check("Collection count is 3", chroma.get_collection_count(COLLECTION) == 3)

	# Semantic search: the closest memory is the one on topic
	var queries = [["theft stealing crime", "test_memory_002"], ["weapons swords combat", "test_memory_001"], ["buying a potion, paying a fair price", "test_memory_003"]]
	for q in queries:
		var results = chroma.query_memories({"collection": COLLECTION, "query": q[0], "limit": 2})
		_check("'%s' finds %s first" % [q[0], q[1]], results.size() == 2 and results[0].id == q[1])

	var important = chroma.query_memories({"collection": COLLECTION, "query": "player interaction", "limit": 10, "min_importance": 7})
	var all_important = important.size() == 2
	for m in important:
		all_important = all_important and int(m.metadata.importance) >= 7
	_check("min_importance 7 returns only the 2 memories at 7+", all_important)

	chroma.delete_collection(COLLECTION)
	_check("Deleted collection is gone", not COLLECTION in chroma.list_collections())

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
