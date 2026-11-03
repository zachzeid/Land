extends SceneTree

# Tests calling chroma_cli.py from Godot with OS.execute (create_collection, list_collections)
# Uses a temp ChromaDB directory (LAND_CHROMA_PATH), never ./chroma; SKIPs if python3 cannot import chromadb
# Run: godot --headless --path . -s res://scripts/debug/test_os_execute.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "OS.EXECUTE CHROMA CLI TEST")
	print("============================================================")
	print("🧪 OS.EXECUTE CHROMA CLI TEST")
	print("============================================================\n")
	if not Support.chroma_available():
		print("SKIP (python3 cannot import chromadb)")
		quit(0)
		return
	var chroma_dir = Support.use_temp_chroma()
	var cli_path = ProjectSettings.globalize_path("res://chroma_cli.py")

	var output = []
	var code = OS.execute("python3", [cli_path, "create_collection", "test_godot_exec"], output, true)
	_check("create_collection exits 0", code == 0)
	var result = JSON.parse_string(output[0].strip_edges()) if output.size() > 0 else null
	_check("create_collection prints JSON success", result is Dictionary and result.get("success", false) and result.get("name") == "test_godot_exec")

	output = []
	code = OS.execute("python3", [cli_path, "list_collections"], output, true)
	var listed = JSON.parse_string(output[0].strip_edges()) if output.size() > 0 else null
	_check("list_collections sees the new collection", code == 0 and listed is Dictionary and "test_godot_exec" in str(listed.get("collections", [])))
	_check("The database was written to the temp directory", FileAccess.file_exists(chroma_dir.path_join("chroma.sqlite3")))

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
