extends Node
## Test Suite for Phase 1: Personality Anchoring System
## Run this to validate the structured personality implementation

## ============================================================================
## PHASE 1 SUCCESS CRITERIA
## ============================================================================
##
## SC-1: NPCPersonality resources load correctly
## SC-2: Core identity block generates properly
## SC-3: Speech patterns are enforced in prompts
## SC-4: Personality modifiers affect impact calculations
## SC-5: Secrets unlock at correct thresholds
## SC-6: Romance unlocks at correct thresholds
## SC-7: ContextBuilder integrates personality correctly
## SC-8: KPI tracker measures all metrics
##
## ============================================================================

var tests_passed: int = 0
var tests_failed: int = 0
var test_results: Array = []

func _ready():
	print("\n" + "=".repeat(60))
	print("PHASE 1 VALIDATION TEST SUITE")
	print("Personality Anchoring System")
	print("=".repeat(60) + "\n")

	await run_all_tests()

	print_summary()

func run_all_tests():
	await test_sc1_resource_loading()
	await test_sc2_core_identity_generation()
	await test_sc3_speech_pattern_enforcement()
	await test_sc4_personality_modifiers()
	await test_sc5_secret_unlocking()
	await test_sc6_romance_unlocking()
	await test_sc7_context_builder_integration()
	await test_sc8_kpi_tracker()

## ============================================================================
## SC-1: NPCPersonality resources load correctly
## ============================================================================
func test_sc1_resource_loading():
	print("SC-1: Testing NPCPersonality resource loading...")

	var gregor_path = "res://resources/npc_personalities/gregor_merchant.tres"
	var elena_path = "res://resources/npc_personalities/elena_daughter.tres"

	# Test Gregor loads
	if ResourceLoader.exists(gregor_path):
		var gregor = load(gregor_path)
		if gregor != null and gregor.npc_id == "gregor_merchant_001":
			record_pass("SC-1a", "Gregor personality resource loads correctly")
		else:
			record_fail("SC-1a", "Gregor resource loaded but has wrong npc_id")
	else:
		record_fail("SC-1a", "Gregor personality resource file not found")

	# Test Elena loads
	if ResourceLoader.exists(elena_path):
		var elena = load(elena_path)
		if elena != null and elena.npc_id == "elena_daughter_001":
			record_pass("SC-1b", "Elena personality resource loads correctly")
		else:
			record_fail("SC-1b", "Elena resource loaded but has wrong npc_id")
	else:
		record_fail("SC-1b", "Elena personality resource file not found")

	# Test personality has required fields
	var gregor = load(gregor_path)
	if gregor:
		var required_fields = ["display_name", "core_identity", "identity_anchors",
							   "vocabulary_level", "speaking_style", "signature_phrases"]
		var missing = []
		for field in required_fields:
			if not field in gregor or gregor.get(field) == null:
				missing.append(field)

		if missing.size() == 0:
			record_pass("SC-1c", "All required personality fields present")
		else:
			record_fail("SC-1c", "Missing fields: %s" % ", ".join(missing))

## ============================================================================
## SC-2: Core identity block generates properly
## ============================================================================
func test_sc2_core_identity_generation():
	print("\nSC-2: Testing core identity block generation...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-2a", "Could not load Gregor for testing")
		return

	var identity_block = gregor.get_core_identity_block()

	# Check block contains display name
	if gregor.display_name in identity_block:
		record_pass("SC-2a", "Identity block contains display name")
	else:
		record_fail("SC-2a", "Identity block missing display name")

	# Check block contains core identity
	if gregor.core_identity.substr(0, 50) in identity_block:
		record_pass("SC-2b", "Identity block contains core identity text")
	else:
		record_fail("SC-2b", "Identity block missing core identity text")

	# Check block contains identity anchors
	var anchors_found = 0
	for anchor in gregor.identity_anchors:
		if anchor in identity_block:
			anchors_found += 1

	if anchors_found == gregor.identity_anchors.size():
		record_pass("SC-2c", "Identity block contains all %d anchors" % anchors_found)
	else:
		record_fail("SC-2c", "Only %d/%d anchors in identity block" % [anchors_found, gregor.identity_anchors.size()])

	# Check block has proper structure
	if "CORE IDENTITY" in identity_block and "Immutable Facts" in identity_block:
		record_pass("SC-2d", "Identity block has proper section headers")
	else:
		record_fail("SC-2d", "Identity block missing section headers")

## ============================================================================
## SC-3: Speech patterns are enforced in prompts
## ============================================================================
func test_sc3_speech_pattern_enforcement():
	print("\nSC-3: Testing speech pattern enforcement...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-3a", "Could not load Gregor for testing")
		return

	var speech_block = gregor.get_speech_pattern_block()

	# Check vocabulary level is mentioned
	if gregor.vocabulary_level in speech_block:
		record_pass("SC-3a", "Speech block contains vocabulary level")
	else:
		record_fail("SC-3a", "Speech block missing vocabulary level")

	# Check speaking style is mentioned
	if gregor.speaking_style in speech_block:
		record_pass("SC-3b", "Speech block contains speaking style")
	else:
		record_fail("SC-3b", "Speech block missing speaking style")

	# Check signature phrases are included
	var sig_found = false
	for phrase in gregor.signature_phrases:
		if phrase in speech_block:
			sig_found = true
			break
	if sig_found:
		record_pass("SC-3c", "Speech block contains signature phrases")
	else:
		record_fail("SC-3c", "Speech block missing signature phrases")

	# Check forbidden phrases are mentioned
	var forbidden_found = false
	for phrase in gregor.forbidden_phrases:
		if phrase in speech_block:
			forbidden_found = true
			break
	if forbidden_found:
		record_pass("SC-3d", "Speech block contains forbidden phrases")
	else:
		record_fail("SC-3d", "Speech block missing forbidden phrases")

## ============================================================================
## SC-4: Personality modifiers affect impact calculations
## ============================================================================
func test_sc4_personality_modifiers():
	print("\nSC-4: Testing personality modifier calculations...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-4a", "Could not load Gregor for testing")
		return

	# Test base impacts
	var base_impacts = {
		"trust": 10,
		"respect": 10,
		"affection": 10,
		"fear": 10,
		"familiarity": 5
	}

	var modified = gregor.apply_personality_modifiers(base_impacts)

	# Gregor has affection_sensitivity = 1.3
	var expected_affection = int(10 * 1.3)
	if modified.affection == expected_affection:
		record_pass("SC-4a", "Affection sensitivity modifier applied correctly (1.3x)")
	else:
		record_fail("SC-4a", "Affection modifier wrong: expected %d, got %d" % [expected_affection, modified.affection])

	# Gregor has respect_sensitivity = 0.8
	var expected_respect = int(10 * 0.8)
	if modified.respect == expected_respect:
		record_pass("SC-4b", "Respect sensitivity modifier applied correctly (0.8x)")
	else:
		record_fail("SC-4b", "Respect modifier wrong: expected %d, got %d" % [expected_respect, modified.respect])

	# Gregor has fear_sensitivity = 1.2
	var expected_fear = int(10 * 1.2)
	if modified.fear == expected_fear:
		record_pass("SC-4c", "Fear sensitivity modifier applied correctly (1.2x)")
	else:
		record_fail("SC-4c", "Fear modifier wrong: expected %d, got %d" % [expected_fear, modified.fear])

	# Test forgiveness tendency on negative trust
	var negative_impacts = {"trust": -10, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0}
	var modified_neg = gregor.apply_personality_modifiers(negative_impacts)
	# Gregor has forgiveness_tendency = 30 (positive but < 50, so no reduction)
	if modified_neg.trust == -10:
		record_pass("SC-4d", "Forgiveness tendency correctly doesn't apply at 30")
	else:
		record_fail("SC-4d", "Forgiveness calculation wrong: expected -10, got %d" % modified_neg.trust)

## ============================================================================
## SC-5: Secrets unlock at correct thresholds
## ============================================================================
func test_sc5_secret_unlocking():
	print("\nSC-5: Testing secret unlocking thresholds...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-5a", "Could not load Gregor for testing")
		return

	# Test with low stats - should unlock nothing
	var unlocked_low = gregor.get_unlocked_secrets(20, 20)
	if unlocked_low.size() == 0:
		record_pass("SC-5a", "No secrets unlocked with low trust/affection (20/20)")
	else:
		record_fail("SC-5a", "Secrets unlocked prematurely with low stats")

	# Test with medium stats - should unlock loneliness secret (trust 50, affection 60)
	var unlocked_med = gregor.get_unlocked_secrets(50, 60)
	if unlocked_med.size() >= 1:
		record_pass("SC-5b", "Secret unlocked at medium thresholds (50/60)")
	else:
		record_fail("SC-5b", "Secret should unlock at trust 50, affection 60")

	# Test with high stats - should unlock all 3 secrets
	var unlocked_high = gregor.get_unlocked_secrets(70, 70)
	if unlocked_high.size() >= 2:
		record_pass("SC-5c", "Multiple secrets unlocked at high thresholds (70/70)")
	else:
		record_fail("SC-5c", "Expected 2+ secrets at trust 70, affection 70")

	# Test that unbreakable secrets are never in unlocked list
	for secret in unlocked_high:
		var is_unbreakable = false
		for unbreakable in gregor.unbreakable_secrets:
			if unbreakable in secret:
				is_unbreakable = true
				break
		if is_unbreakable:
			record_fail("SC-5d", "Unbreakable secret was returned in unlocked list")
			return

	record_pass("SC-5d", "Unbreakable secrets never returned")

## ============================================================================
## SC-6: Romance unlocks at correct thresholds
## ============================================================================
func test_sc6_romance_unlocking():
	print("\nSC-6: Testing romance unlocking thresholds...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-6a", "Could not load Gregor for testing")
		return

	# Gregor thresholds: trust 50, affection 60, familiarity 40

	# Test below all thresholds
	if not gregor.is_romance_unlocked(30, 30, 20):
		record_pass("SC-6a", "Romance locked when below all thresholds")
	else:
		record_fail("SC-6a", "Romance should be locked at 30/30/20")

	# Test meeting only some thresholds
	if not gregor.is_romance_unlocked(60, 30, 50):
		record_pass("SC-6b", "Romance locked when affection below threshold")
	else:
		record_fail("SC-6b", "Romance should require affection >= 60")

	# Test meeting all thresholds
	if gregor.is_romance_unlocked(50, 60, 40):
		record_pass("SC-6c", "Romance unlocked when all thresholds met (50/60/40)")
	else:
		record_fail("SC-6c", "Romance should unlock at exact thresholds")

	# Test Elena who has romance_only style
	var elena = load("res://resources/npc_personalities/elena_daughter.tres")
	if elena and elena.relationship_style == "romance_only":
		record_pass("SC-6d", "Elena has romance_only relationship style")
	else:
		record_fail("SC-6d", "Elena should have romance_only relationship style")

## ============================================================================
## SC-7: ContextBuilder integrates personality correctly
## ============================================================================
func test_sc7_context_builder_integration():
	print("\nSC-7: Testing ContextBuilder personality integration...")

	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")
	if gregor == null:
		record_fail("SC-7a", "Could not load Gregor for testing")
		return

	# Create a ContextBuilder instance
	var ContextBuilderScript = load("res://scripts/dialogue/context_builder.gd")
	var context_builder = ContextBuilderScript.new()

	# Build context with personality
	var context = context_builder.build_context({
		"personality": gregor,
		"relationship_dimensions": {
			"trust": 50,
			"respect": 40,
			"affection": 60,
			"fear": 10,
			"familiarity": 45
		},
		"rag_memories": [],
		"raw_memories": [],
		"world_state": {},
		"conversation_history": [],
		"player_input": "Hello there!"
	})

	var system_prompt = context.system_prompt

	# Check core identity is at the TOP of the prompt
	var identity_pos = system_prompt.find("CORE IDENTITY")
	if identity_pos >= 0 and identity_pos < 100:
		record_pass("SC-7a", "Core identity appears at top of system prompt")
	else:
		record_fail("SC-7a", "Core identity should be at start of prompt (pos: %d)" % identity_pos)

	# Check personality summary is included
	if "YOUR PERSONALITY" in system_prompt:
		record_pass("SC-7b", "Personality summary section included")
	else:
		record_fail("SC-7b", "Missing YOUR PERSONALITY section")

	# Check speech patterns section
	if "SPEECH PATTERNS" in system_prompt:
		record_pass("SC-7c", "Speech patterns section included")
	else:
		record_fail("SC-7c", "Missing SPEECH PATTERNS section")

	# Check relationship section
	if "Multi-Dimensional Relationship" in system_prompt:
		record_pass("SC-7d", "Relationship section included")
	else:
		record_fail("SC-7d", "Missing relationship section")

	# Check response format section
	if "CRITICAL: Response Format" in system_prompt:
		record_pass("SC-7e", "Response format section included")
	else:
		record_fail("SC-7e", "Missing response format section")

	# Check forbidden phrases are mentioned
	if "NEVER use these words" in system_prompt or "forbidden" in system_prompt.to_lower():
		record_pass("SC-7f", "Forbidden phrases enforcement included")
	else:
		record_fail("SC-7f", "Forbidden phrases not enforced in prompt")

	context_builder.queue_free()

## ============================================================================
## SC-8: KPI tracker measures all metrics
## ============================================================================
func test_sc8_kpi_tracker():
	print("\nSC-8: Testing KPI tracker functionality...")

	var KPITrackerScript = load("res://scripts/debug/personality_kpi_tracker.gd")
	if KPITrackerScript == null:
		record_fail("SC-8a", "Could not load KPI tracker script")
		return

	var tracker = KPITrackerScript.new()
	var gregor = load("res://resources/npc_personalities/gregor_merchant.tres")

	# Start session
	tracker.start_session("gregor_merchant_001", gregor)
	if tracker.tracked_npc_id == "gregor_merchant_001":
		record_pass("SC-8a", "KPI session started correctly")
	else:
		record_fail("SC-8a", "KPI session not started properly")

	# Analyze a good response
	var good_response = "Ah, fine wares for a fine customer! What brings you to my shop today?"
	var context = {"trust": 30, "affection": 25, "familiarity": 20}
	var analysis = tracker.analyze_response(good_response, context)

	if analysis.has("checks"):
		record_pass("SC-8b", "KPI analysis returns checks dictionary")
	else:
		record_fail("SC-8b", "KPI analysis missing checks")

	# Analyze a bad response (uses forbidden phrase)
	var bad_response = "Dude, that's awesome! Whatever you need, cool?"
	var bad_analysis = tracker.analyze_response(bad_response, context)

	if bad_analysis.checks.speech.forbidden_used.size() > 0:
		record_pass("SC-8c", "KPI detects forbidden phrase violations")
	else:
		record_fail("SC-8c", "KPI failed to detect forbidden phrases")

	# End session and check report
	var final_metrics = tracker.end_session()

	if final_metrics.has("identity_anchor_adherence") and \
	   final_metrics.has("speech_pattern_compliance") and \
	   final_metrics.has("overall_health"):
		record_pass("SC-8d", "KPI final metrics contain all expected fields")
	else:
		record_fail("SC-8d", "KPI final metrics missing expected fields")

	# Test report generation
	var report = tracker.generate_report()
	if "PERSONALITY CONSISTENCY KPI REPORT" in report:
		record_pass("SC-8e", "KPI report generates correctly")
	else:
		record_fail("SC-8e", "KPI report generation failed")

	tracker.queue_free()

## ============================================================================
## HELPER FUNCTIONS
## ============================================================================

func record_pass(test_id: String, message: String):
	tests_passed += 1
	test_results.append({"id": test_id, "passed": true, "message": message})
	print("  [PASS] %s: %s" % [test_id, message])

func record_fail(test_id: String, message: String):
	tests_failed += 1
	test_results.append({"id": test_id, "passed": false, "message": message})
	print("  [FAIL] %s: %s" % [test_id, message])

func print_summary():
	print("\n" + "=".repeat(60))
	print("TEST SUMMARY")
	print("=".repeat(60))
	print("Passed: %d" % tests_passed)
	print("Failed: %d" % tests_failed)
	print("Total:  %d" % (tests_passed + tests_failed))
	print("")

	var pass_rate = 0.0
	if (tests_passed + tests_failed) > 0:
		pass_rate = float(tests_passed) / (tests_passed + tests_failed) * 100

	print("Pass Rate: %.1f%%" % pass_rate)

	if tests_failed == 0:
		print("\n*** ALL TESTS PASSED - PHASE 1 COMPLETE ***")
	else:
		print("\n*** TESTS FAILED - REVIEW FAILURES ABOVE ***")
		print("\nFailed tests:")
		for result in test_results:
			if not result.passed:
				print("  - %s: %s" % [result.id, result.message])

	print("=".repeat(60) + "\n")
