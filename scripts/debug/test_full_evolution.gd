extends SceneTree

# Tests that the prompt ContextBuilder sends changes as a relationship grows from stranger to trusted friend:
# each stage's dimension readings and behavioral guidance differ, and the stranger-only guidance goes away
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_full_evolution.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const PERSONALITY = "You are Gregor, a cautious merchant in Thornhaven. You've seen too many adventurers come and go. You protect your daughter Elena fiercely."
const STAGES = [
	["Initial meeting", {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0}, "Hello, I'd like to buy some supplies."],
	["After the quest", {"trust": 15, "respect": 10, "affection": 8, "fear": 0, "familiarity": 5}, "I dealt with those bandits for you."],
	["After the gift", {"trust": 23, "respect": 15, "affection": 23, "fear": 0, "familiarity": 15}, "I found this book about horses for Elena."],
	["Trusted friend", {"trust": 51, "respect": 35, "affection": 43, "fear": -10, "familiarity": 30}, "You fought well back there."],
]

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "FULL RELATIONSHIP EVOLUTION TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 FULL RELATIONSHIP EVOLUTION TEST")
	print("============================================================\n")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()
	var sections = []
	var guidance = []
	for stage in STAGES:
		var context = builder.build_context({"system_prompt": PERSONALITY, "relationship_dimensions": stage[1], "conversation_history": [], "player_input": stage[2]})
		var prompt: String = context.system_prompt
		_check("%s: the player's line is the message" % stage[0], context.messages[-1].content == stage[2])
		var start = prompt.find("**Trust:**")
		var stop = prompt.find("\n\n", prompt.find("**Familiarity:**"))
		_check("%s: dimension readings present" % stage[0], start >= 0 and stop > start)
		sections.append(prompt.substr(start, stop - start))
		var g_start = prompt.find("**How these feelings affect your behavior:**")
		guidance.append(prompt.substr(g_start, prompt.find("## Roleplay Instructions") - g_start) if g_start >= 0 else "")

	for i in range(1, STAGES.size()):
		_check("'%s' reads differently from '%s'" % [STAGES[i][0], STAGES[i - 1][0]], sections[i] != sections[i - 1])
	_check("A stranger is treated formally", "Formal, asking basic questions" in guidance[0])
	_check("A trusted friend is no longer treated formally", not "Formal, asking basic questions" in guidance[3])
	_check("A trusted friend gets open-but-bounded trust guidance", "trust is building" in guidance[3])
	_check("A trusted friend gets a friendly tone", "Friendly and welcoming tone" in guidance[3])
	_check("Stage 1 trust reads cautious, stage 4 trusting", "cautious" in sections[0] and "You trust them - they seem reliable" in sections[3])
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
