extends SceneTree

# Tests saving (WorldState.save_game / load_game / request_save):
# - a save holds the world, the quests and where the player stands
# - writes are atomic: no .tmp left behind, and the save each write replaces is kept as the backup
# - a save that will not parse falls back to the backup
# - autosave: off in headless runs, bursts of requests make one write, travel and conversations ask
#   for one, and nothing saves mid-opening or once the story has ended
# Writes only to its own files under user://test_saves/; the real save is never touched
# Run: godot --headless --path . -s res://scripts/debug/test_save.gd

const TEST_DIR = "user://test_saves"

var world_state: Node
var scene_manager: Node
var failures: int = 0
var saves: Array = []
var real_save_text: String = ""

func _init():
	await process_frame
	await process_frame
	world_state = root.get_node("WorldState")
	scene_manager = root.get_node("SceneManager")
	world_state.set_idle_clock_rate(0.0)
	var director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	if FileAccess.file_exists(world_state.SAVE_PATH):
		real_save_text = FileAccess.get_file_as_string(world_state.SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_clear_test_dir()
	world_state.save_path = TEST_DIR + "/game_save.json"
	world_state.save_backup_path = TEST_DIR + "/game_save.bak.json"
	world_state.game_saved.connect(func(path, reason): saves.append([path, reason]))

	print("============================================================")
	print("🧪 SAVE TEST")
	print("============================================================\n")

	_test_headless_default()
	_test_contents()
	_test_atomic_and_backup()
	_test_corrupt_falls_back()
	await _test_coalesced()
	await _test_triggers()
	await _test_held()

	world_state.autosave_enabled = false
	_clear_test_dir()
	var real_now = FileAccess.get_file_as_string(world_state.SAVE_PATH) if FileAccess.file_exists(world_state.SAVE_PATH) else ""
	_check("The real save was not touched", real_now == real_save_text)

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _test_headless_default():
	print("Headless default")
	_check("Autosave is off in a headless run", world_state.autosave_enabled == false)
	world_state.request_save("test")
	_check("A request while off starts nothing", world_state._autosave_timer.is_stopped())

func _test_contents():
	print("What a save holds")
	var data: Dictionary = world_state.save()
	for key in ["world_flags", "game_minutes", "storylines", "player_events", "inner_voice", "generics", "quests", "player_location"]:
		_check("Holds %s" % key, data.has(key))
	_check("Quests come from QuestManager", data.quests.has("active") and data.quests.has("completed"))
	var restored = data.duplicate(true)
	restored.player_location = "thornhaven_chapel"
	restored.quests = {"available": [], "active": {}, "completed": {}, "failed": {}}
	world_state.load_from_dict(restored)
	_check("Loading restores where the player stood", world_state.player_location == "thornhaven_chapel")
	_check("Loading keeps the quest state for QuestManager", world_state.quest_state.has("active"))

func _test_atomic_and_backup():
	print("Atomic writes and the backup")
	world_state.world_flags["test_save_marker"] = 1
	_check("First save succeeds", world_state.save_game())
	_check("No backup after the first save", not FileAccess.file_exists(world_state.save_backup_path))
	world_state.world_flags["test_save_marker"] = 2
	_check("Second save succeeds", world_state.save_game())
	_check("No .tmp is left behind", not FileAccess.file_exists(world_state.save_path + ".tmp"))
	_check("The save holds the newest world", _marker(world_state.save_path) == 2)
	_check("The backup holds the one it replaced", _marker(world_state.save_backup_path) == 1)

func _test_corrupt_falls_back():
	print("A broken save falls back to the backup")
	var f = FileAccess.open(world_state.save_path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	world_state.world_flags.erase("test_save_marker")
	world_state.loaded_from_save = false
	world_state.load_game()
	_check("Loaded from the backup", world_state.loaded_from_save and world_state.world_flags.get("test_save_marker") == 1)
	world_state.world_flags.erase("test_save_marker")

func _test_coalesced():
	print("Autosave requests coalesce")
	world_state.autosave_enabled = true
	saves.clear()
	for i in 5:
		world_state.request_save("burst %d" % i)
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("Five requests make one write", saves.size() == 1)
	_check("It carries the first reason", saves.size() == 1 and saves[0][1] == "burst 0")

func _test_triggers():
	print("What asks for a save")
	saves.clear()
	world_state.advance_time(5, "travel")
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("Travel time saves", saves.size() == 1 and saves[0][1] == "travel")
	saves.clear()
	world_state.advance_time(1, "idle")
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("An idle clock tick does not (the idle timer saves on its own cadence)", saves.is_empty())
	saves.clear()
	var dialogue = root.get_node("DialogueManager")
	dialogue.start_conversation("test_npc", null)
	dialogue.end_conversation("test_npc")
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("Ending a conversation saves", saves.size() == 1 and saves[0][1] == "talked to test_npc")

func _test_held():
	print("Held mid-opening and after the end")
	var opening = scene_manager.opening
	saves.clear()
	opening.playing = true
	world_state.request_save("during opening")
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("Nothing saves mid-opening", saves.is_empty())
	opening.playing = false
	var holder = _StoryOver.new()
	holder.add_to_group("player_ui")
	root.add_child(holder)
	world_state.request_save("after the end")
	await create_timer(world_state.AUTOSAVE_DELAY_SECONDS + 0.5).timeout
	_check("Nothing saves once the story has ended", saves.is_empty())
	holder.queue_free()

class _StoryOver extends Node:
	var story_over: bool = true

func _marker(path: String) -> int:
	var json = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return -1
	return int(json.data.get("world_flags", {}).get("test_save_marker", -1))

func _clear_test_dir():
	var dir = DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
