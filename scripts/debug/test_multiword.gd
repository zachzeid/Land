extends SceneTree

# Tests ChromaClient storing and reading back a multi-word document with metadata (base64 transport)
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_multiword.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const COLLECTION = "npc_test_multiword_memories"
const DOCUMENT = "Player asked about the bandits near the village, \"twice\" & with 'quotes'"

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "CHROMACLIENT MULTI-WORD TEST")
	print("============================================================")
	print("🧪 CHROMACLIENT MULTI-WORD TEST")
	print("============================================================\n")
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
	var chroma_dir = Support.use_temp_chroma()
	var chroma = load("res://scripts/memory/chroma_client.gd").new()
	root.add_child(chroma)

	_check("Collection created", not chroma.create_collection(COLLECTION).has("error"))
	var result = chroma.add_memory({
		"collection": COLLECTION,
		"id": "test_multiword",
		"document": DOCUMENT,
		"metadata": {"event_type": "conversation", "importance": 7, "emotion": "concerned"}
	})
	_check("add_memory succeeds", result.get("success", false))
	var stored = chroma.get_memory_by_id(COLLECTION, "test_multiword")
	_check("The document comes back whole", stored.get("document", "") == DOCUMENT)
	var metadata = stored.get("metadata", {})
	_check("Metadata comes back", metadata.get("emotion", "") == "concerned" and int(metadata.get("importance", 0)) == 7)

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
