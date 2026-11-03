extends SceneTree

# Tests ContextBuilder's behavioral guidance for five archetypal relationships (synchronous, no NPC):
# stranger, trusted ally, romantic interest, conflicted (affection + fear) and enemy
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_dimension_sync.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const CASES = [
	["Neutral stranger", {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0},
		["Formal, asking basic questions"], ["CONFLICTED", "INTIMATE BOND"]],
	["Trusted ally", {"trust": 70, "respect": 60, "affection": 40, "fear": -20, "familiarity": 80},
		["Be open but maintain some boundaries", "Friendly and welcoming tone", "Reference shared history"], ["Formal", "CONFLICTED"]],
	["Romantic interest", {"trust": 85, "respect": 70, "affection": 90, "fear": 0, "familiarity": 95},
		["Share secrets and vulnerabilities", "Show warmth and genuine care", "INTIMATE BOND"], ["CONFLICTED"]],
	["Conflicted (affection + fear)", {"trust": 30, "respect": 40, "affection": 70, "fear": 60, "familiarity": 75},
		["You're attracted but afraid", "Careful with words"], ["INTIMATE BOND"]],
	["Enemy", {"trust": -80, "respect": -60, "affection": -90, "fear": 20, "familiarity": 50},
		["Be guarded and skeptical", "Dismissive tone", "Cold, minimal interaction"], ["Friendly", "INTIMATE BOND"]],
]

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "DIMENSION GUIDANCE TEST (SYNCHRONOUS)")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 DIMENSION GUIDANCE TEST (SYNCHRONOUS)")
	print("============================================================\n")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	for c in CASES:
		var prompt: String = builder.build_context({"system_prompt": "You are a test character.", "relationship_dimensions": c[1], "player_input": "Hello"}).system_prompt
		_check("%s: trust reading in the prompt" % c[0], ("**Trust:** %d/100 - %s" % [c[1].trust, builder._interpret_dimension("trust", c[1].trust)]) in prompt)
		for phrase in c[2]:
			_check("%s: guidance has \"%s\"" % [c[0], phrase], phrase in prompt)
		for phrase in c[3]:
			_check("%s: guidance lacks \"%s\"" % [c[0], phrase], not phrase in prompt)
	builder.free()
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
