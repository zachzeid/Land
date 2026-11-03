extends SceneTree

# Tests ContextBuilder's dimension readings and behavioral guidance directly (no NPC):
# _interpret_dimension bands at the high and low ends, guidance for a close bond, and the
# respect-without-trust CONFLICTED state
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_dimensions_simple.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "DIMENSION INTERPRETATION TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 DIMENSION INTERPRETATION TEST")
	print("============================================================\n")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()

	print("Dimension readings")
	_check("Trust 75 = deep trust", "deeply" in builder._interpret_dimension("trust", 75).to_lower())
	_check("Trust -60 = betrayed", "betrayed" in builder._interpret_dimension("trust", -60))
	_check("Affection 75 = deep care", "possibly love" in builder._interpret_dimension("affection", 75))
	_check("Affection -60 = active dislike", "actively dislike" in builder._interpret_dimension("affection", -60))
	_check("Fear -30 = safe", "safe" in builder._interpret_dimension("fear", -30).to_lower())
	_check("Fear -25 = not afraid (the 'safe' band starts below -25)", builder._interpret_dimension("fear", -25) == "You're not afraid of them")
	_check("Fear 80 = terrified", "terrified" in builder._interpret_dimension("fear", 80))
	_check("Familiarity 10 = stranger", "stranger" in builder._interpret_dimension("familiarity", 10))
	_check("Respect 50 = capable", "capable" in builder._interpret_dimension("respect", 50))
	_check("Unknown dimension", builder._interpret_dimension("loyalty", 50) == "Unknown")

	print("\nBehavioral guidance")
	var close = builder._generate_behavioral_guidance({"trust": 75, "respect": 60, "affection": 75, "fear": -10, "familiarity": 65}).to_lower()
	_check("High trust: share secrets", "share secrets" in close)
	_check("High affection (>70): warmth", "warmth" in close)
	_check("High familiarity: shared history", "shared history" in close)
	_check("All three high: intimate bond", "intimate bond" in close)
	var at_seventy = builder._generate_behavioral_guidance({"affection": 70}).to_lower()
	_check("Affection exactly 70 is friendly, not warm (threshold is > 70)", "friendly and welcoming" in at_seventy and not "warmth" in at_seventy)
	var conflicted = builder._generate_behavioral_guidance({"trust": 15, "respect": 70, "affection": 10, "fear": 10, "familiarity": 30}).to_lower()
	_check("Respect 70 + trust 15: CONFLICTED", "conflicted" in conflicted and "respect but don't trust" in conflicted)
	_check("Guidance always has its header", builder._generate_behavioral_guidance({}).begins_with("**How these feelings affect your behavior:**"))

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
