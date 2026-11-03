extends RefCounted
## Shared guards for the legacy headless tests in scripts/debug/test_*.gd
## - watchdog: a test that stops early (a script error inside a coroutine) still ends with a FAIL line
## - live gate: tests that make paid API calls run only with `-- --live`
## - temp ChromaDB: chroma_cli.py is pointed at a throwaway directory, never ./chroma
## Use: const Support = preload("res://scripts/debug/legacy_test_support.gd")

const WATCHDOG_SECONDS = 50.0
const SKIP_LIVE = "SKIP (needs --live: makes paid API calls)"

## Fail and quit if the test has not finished within WATCHDOG_SECONDS
static func start_watchdog(tree: SceneTree, test_name: String) -> void:
	tree.create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func():
		print("\n❌ %s: FAIL (timed out after %ds, or stopped on a script error above)" % [test_name, int(WATCHDOG_SECONDS)])
		tree.quit(1))

## True when `--live` was passed after `--`
static func live_requested() -> bool:
	return "--live" in OS.get_cmdline_user_args()

## True when python3 can import chromadb (checked by a short subprocess, no network)
static func chroma_available() -> bool:
	var output = []
	var code = OS.execute("python3", ["-c", "import chromadb"], output, true)
	return code == 0

## Point chroma_cli.py at a fresh temp directory (via LAND_CHROMA_PATH) and return it
static func use_temp_chroma() -> String:
	var base = "/tmp" if OS.has_feature("macos") or OS.has_feature("linux") else OS.get_cache_dir()
	var dir = base.path_join("land_test_chroma_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(dir)
	OS.set_environment("LAND_CHROMA_PATH", dir)
	OS.set_environment("ANONYMIZED_TELEMETRY", "False")
	return dir

## Delete a directory made by use_temp_chroma
static func remove_temp_chroma(dir: String) -> void:
	if dir.is_empty() or not "land_test_chroma_" in dir:
		return
	OS.execute("python3", ["-c", "import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)", dir], [], true)
	OS.unset_environment("LAND_CHROMA_PATH")

## Keep the real save safe: autosave off and any save pointed at user://test_saves/
static func guard_save(tree: SceneTree) -> void:
	var world_state = tree.root.get_node_or_null("WorldState")
	if world_state == null:
		return
	world_state.autosave_enabled = false
	world_state.save_path = "user://test_saves/legacy_game_save.json"
	world_state.save_backup_path = "user://test_saves/legacy_game_save.bak.json"
