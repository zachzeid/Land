extends SceneTree

# Tests SafeExec and the ChromaDB command line: no player text can reach a shell
# - arguments holding $, `, \ or " are refused and nothing runs; free text is cleaned
# - a memory query full of shell characters travels base64-encoded and arrives intact
# No API calls; ChromaDB is not touched (the query check stops at the argument list)
# Run: godot --headless --path . -s res://scripts/debug/test_safe_exec.gd

const SafeExec = preload("res://scripts/core/safe_exec.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	print("============================================================")
	print("🧪 SAFE EXEC TEST")
	print("============================================================\n")

	var marker = OS.get_cache_dir().path_join("land_safe_exec_marker")
	DirAccess.remove_absolute(marker)
	var attack = "hello $(touch %s) `touch %s`" % [marker, marker]
	_check("A plain argument is safe", SafeExec.is_safe("npc_gregor_memories"))
	_check("$( ) is unsafe", not SafeExec.is_safe("$(id)"))
	_check("Backticks are unsafe", not SafeExec.is_safe("`id`"))
	var out = []
	var code = SafeExec.execute("python3", ["-c", "print(1)", attack], out)
	_check("An unsafe argument is refused (-1)", code == -1 and out.is_empty())
	_check("...and nothing ran", not FileAccess.file_exists(marker))
	_check("Clean drops shell characters, keeps the words", SafeExec.clean(attack) == "hello (touch %s) touch %s" % [marker, marker])
	out = []
	code = SafeExec.execute("python3", ["-c", "import sys; print(sys.argv[1])", "plain words"], out)
	_check("A safe call still runs", code == 0 and out.size() > 0 and "plain words" in str(out[0]))

	var b64 = "b64:" + Marshalls.utf8_to_base64(attack)
	_check("An encoded query is a safe argument", SafeExec.is_safe(b64))
	out = []
	var cli_decode = "import base64,sys; t=sys.argv[1]; print(base64.b64decode(t[4:]).decode() if t.startswith('b64:') else t)"
	code = SafeExec.execute("python3", ["-c", cli_decode, b64], out)
	_check("The CLI's decode gives back the player's exact words", code == 0 and out.size() > 0 and str(out[0]).strip_edges() == attack)
	_check("...and still nothing ran", not FileAccess.file_exists(marker))
	var cli = FileAccess.get_file_as_string("res://chroma_cli.py")
	_check("chroma_cli.py decodes b64: queries", 'query_text.startswith("b64:")' in cli)
	var client = FileAccess.get_file_as_string("res://scripts/memory/chroma_client.gd")
	_check("ChromaClient has no raw OS.execute left", "OS.execute" not in client)

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool):
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
