extends SceneTree

# Tests the ChromaDB memory operations RAGMemory relies on, against a real (temporary) database:
# - ChromaClient.delete_memory and update_memory (RAGMemory called them; they did not exist)
# - RAGMemory._delete_memory and _update_memory_metadata in ChromaDB mode
# - RAGMemory.retrieve_relevant_raw in ChromaDB mode (it treated query_memories' Array as a Dictionary)
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_memory_ops.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "MEMORY OPS TEST")
	print("============================================================")
	print("🧪 MEMORY OPS TEST")
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
	_check("RAGMemory starts in ChromaDB mode", await rag.initialize("test_ops", chroma) and rag.use_chromadb)
	var collection: String = rag.collection_name

	var add = chroma.add_memory({"collection": collection, "id": "ops_1", "document": "The stranger mended the mill wheel.",
		"metadata": {"event_type": "help", "importance": 7}})
	_check("A memory is stored", not add.has("error"))
	chroma.add_memory({"collection": collection, "id": "ops_2", "document": "The stranger asked about the mill road.",
		"metadata": {"event_type": "conversation", "importance": 6}})

	var raw: Array = await rag.retrieve_relevant_raw("mill wheel", {"limit": 5, "min_importance": 1})
	_check("retrieve_relevant_raw returns ChromaDB memories (%d)" % raw.size(), raw.size() == 2)
	_check("...with their metadata", raw.size() > 0 and raw[0].get("importance", 0) >= 6 and raw[0].get("document", "") != "")

	_check("ChromaClient.update_memory exists and works", chroma.has_method("update_memory")
		and chroma.update_memory({"collection": collection, "id": "ops_1", "metadata": {"event_type": "help", "importance": 9}}).get("success", false))
	var after = chroma.get_memory_by_id(collection, "ops_1")
	_check("...the new metadata is stored", after.get("metadata", {}).get("importance", 0) == 9)
	_check("...and the text is unchanged", after.get("document", "") == "The stranger mended the mill wheel.")
	_check("Updating a missing memory is an error, not a silent add", chroma.update_memory({"collection": collection, "id": "nope", "metadata": {"a": 1}}).has("error"))
	_check("RAGMemory._update_memory_metadata works in ChromaDB mode", await rag._update_memory_metadata("ops_2", {"event_type": "conversation", "importance": 6, "superseded_by": "pending"}))

	_check("ChromaClient.delete_memory exists and works", chroma.has_method("delete_memory")
		and chroma.delete_memory({"collection": collection, "id": "ops_1"}).get("success", false))
	_check("...the memory is gone (an empty result, not a \"<null>\" document)", chroma.get_memory_by_id(collection, "ops_1").is_empty())
	_check("RAGMemory._delete_memory works in ChromaDB mode", await rag._delete_memory("ops_2"))
	_check("...the collection is empty", chroma.get_collection_count(collection) == 0)

	Support.remove_temp_chroma(chroma_dir)
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
