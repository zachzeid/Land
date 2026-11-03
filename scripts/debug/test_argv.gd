extends SceneTree

# Tests that OS.execute passes each argument to python3 intact (a multi-word argument stays one argv entry),
# which ChromaClient relies on when it hands documents to chroma_cli.py
# Also reports (without failing) whether this platform shell-expands arguments: on macOS, Godot 4.5.1 strips
# double quotes and expands $VARS and `commands`, which is why ChromaClient base64-encodes documents
# No ChromaDB, no network; SKIPs if python3 is missing
# Run: godot --headless --path . -s res://scripts/debug/test_argv.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const ARGS = ["collection_name", "memory_id", "This is a document with multiple words", "VGhpcyBpcyBhIHRlc3Q=", "eyJpbXBvcnRhbmNlIjogOH0="]
const SHELLY = "quotes \"and\" $HOME"

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "OS.EXECUTE ARGV TEST")
	print("============================================================")
	print("🧪 OS.EXECUTE ARGV TEST")
	print("============================================================\n")
	var output = []
	var code = OS.execute("python3", ["-c", "import sys, json; print(json.dumps(sys.argv[1:]))"] + ARGS, output, true)
	if code == -1 or output.is_empty():
		print("SKIP (python3 not found)")
		quit(0)
		return
	var received = JSON.parse_string(output[0].strip_edges())
	_check("python3 exits 0", code == 0)
	_check("All %d arguments arrive" % ARGS.size(), received is Array and received.size() == ARGS.size())
	for i in range(ARGS.size()):
		_check("Argument %d arrives unchanged: %s" % [i, ARGS[i]], received is Array and i < received.size() and received[i] == ARGS[i])
	output = []
	OS.execute("python3", ["-c", "import sys; print(sys.argv[1])", SHELLY], output, true)
	if output.size() > 0 and output[0].strip_edges() != SHELLY:
		print("  ⚠ OS.execute shell-expands arguments here: %s -> %s (not counted)" % [SHELLY, output[0].strip_edges()])
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
