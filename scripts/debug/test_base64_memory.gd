extends SceneTree

# Tests ChromaClient's base64 transport: a memory with metadata is stored, then found by semantic query
# with its metadata intact
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_base64_memory.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const COLLECTION = "npc_test_base64_memories"

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "BASE64 CHROMA MEMORY TEST")
	print("============================================================")
	print("🧪 BASE64 CHROMA MEMORY TEST")
	print("============================================================\n")
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
	var chroma_dir = Support.use_temp_chroma()
	var chroma = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma)

	chroma.create_collection(COLLECTION)
	var result = chroma.add_memory({
		"collection": COLLECTION,
		"id": "test_godot_base64",
		"document": "This is a test from Godot using base64 encoding for metadata: ünïcödé, \"quotes\", newline\nsecond line",
		"metadata": {"event_type": "test", "importance": 8, "emotion": "curious", "timestamp": 1700000000.0}
	})
	_check("add_memory succeeds", result.get("success", false))

	var found = chroma.query_memories({"collection": COLLECTION, "query": "test godot base64", "limit": 3})
	_check("Query finds the memory", found.size() == 1 and found[0].get("id") == "test_godot_base64")
	var memory: Dictionary = found[0] if found.size() > 0 else {}
	_check("Unicode, quotes and newlines survive", "ünïcödé" in memory.get("document", "") and "\nsecond line" in memory.get("document", ""))
	var metadata = memory.get("metadata", {})
	_check("Metadata survives", metadata.get("event_type") == "test" and int(metadata.get("importance", 0)) == 8 and metadata.get("emotion") == "curious")
	_check("A distance is reported", memory.get("distance", null) is float)

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
