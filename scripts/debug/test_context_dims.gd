extends SceneTree

# Tests that ContextBuilder writes the five relationship dimensions into the system prompt
# (value + plain-language reading) instead of the legacy single score, for a bonded relationship
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_context_dims.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "CONTEXT BUILDER DIMENSIONS TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 CONTEXT BUILDER DIMENSIONS TEST")
	print("============================================================\n")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	# After 4 positive interactions (quest, gift, support, danger)
	var dims = {"trust": 51, "respect": 35, "affection": 43, "fear": -10, "familiarity": 30}
	var context = builder.build_context({
		"system_prompt": "You are Gregor, a friendly merchant in Thornhaven village. You have a daughter named Elena who you worry about constantly.",
		"relationship_dimensions": dims,
		"conversation_history": [],
		"player_input": "Hey Gregor, how are things?"
	})
	var prompt: String = context.system_prompt
	_check("Multi-dimensional relationship section", "## Your Multi-Dimensional Relationship with the Player" in prompt)
	_check("No legacy single-score section", not "## Current Relationship with Player" in prompt)
	_check("Trust 51 reads as trusting", "**Trust:** 51/100 - You trust them - they seem reliable" in prompt)
	_check("Respect 35 reads as growing respect", "**Respect:** 35/100 - You're starting to respect them" in prompt)
	_check("Affection 43 reads as warming up", "**Affection:** 43/100 - You're warming up to them" in prompt)
	_check("Fear -10 reads as unafraid", "**Fear:** -10/100 - You're not afraid of them" in prompt)
	_check("Familiarity 30 reads as getting to know", "**Familiarity:** 30/100 - You're getting to know them" in prompt)
	_check("Behavioral guidance follows", "**How these feelings affect your behavior:**" in prompt and "trust is building" in prompt)
	_check("One message: the player's input", context.messages.size() == 1 and context.messages[0].content == "Hey Gregor, how are things?")
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
