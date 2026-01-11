extends Node
class_name PersonalityKPITracker
## PersonalityKPITracker - Measures and tracks NPC personality consistency
## Used to validate Phase 1 implementation and ongoing character coherence

## ============================================================================
## KPI DEFINITIONS
## ============================================================================
##
## 1. IDENTITY ANCHOR ADHERENCE (Target: 100%)
##    - Core identity facts should never be contradicted
##    - Measured by checking responses against identity_anchors
##
## 2. SPEECH PATTERN COMPLIANCE (Target: 95%+)
##    - Forbidden phrases should never appear
##    - Signature phrases should appear in 20%+ of responses
##    - Vocabulary level should match personality
##
## 3. RELATIONSHIP THRESHOLD ACCURACY (Target: 100%)
##    - Secrets only revealed when thresholds met
##    - Romance only available when thresholds met
##
## 4. PERSONALITY TRAIT CONSISTENCY (Target: 90%+)
##    - Responses should align with defined traits
##    - Measured through sentiment/tone analysis
##
## 5. WORLD KNOWLEDGE ACCURACY (Target: 100%)
##    - NPC should never contradict WorldKnowledge facts
##    - Names, locations, relationships must be accurate
##
## ============================================================================

## Tracking data structure
var kpi_data: Dictionary = {
	"sessions": [],
	"current_session": null,
	"aggregate_metrics": {}
}

## Current NPC being tracked
var tracked_npc_id: String = ""
var tracked_personality: Resource = null

## ============================================================================
## SESSION MANAGEMENT
## ============================================================================

## Start a new tracking session for an NPC
func start_session(npc_id: String, personality: Resource) -> void:
	tracked_npc_id = npc_id
	tracked_personality = personality

	kpi_data.current_session = {
		"npc_id": npc_id,
		"start_time": Time.get_unix_time_from_system(),
		"end_time": 0,
		"responses": [],
		"metrics": {
			"identity_adherence": {"total": 0, "passed": 0},
			"speech_compliance": {
				"forbidden_violations": 0,
				"signature_uses": 0,
				"total_responses": 0
			},
			"threshold_accuracy": {"total": 0, "passed": 0},
			"trait_consistency": {"total": 0, "aligned": 0},
			"world_accuracy": {"total": 0, "passed": 0}
		},
		"violations": []
	}

	print("[KPI] Started tracking session for %s" % npc_id)

## End current session and calculate final metrics
func end_session() -> Dictionary:
	if kpi_data.current_session == null:
		return {}

	kpi_data.current_session.end_time = Time.get_unix_time_from_system()

	var final_metrics = _calculate_session_metrics()
	kpi_data.current_session.final_metrics = final_metrics

	kpi_data.sessions.append(kpi_data.current_session)

	var session = kpi_data.current_session
	kpi_data.current_session = null

	print("[KPI] Session ended. Final metrics: %s" % JSON.stringify(final_metrics))

	return final_metrics

## ============================================================================
## RESPONSE ANALYSIS
## ============================================================================

## Analyze a single NPC response for KPI compliance
func analyze_response(response: String, context: Dictionary) -> Dictionary:
	if kpi_data.current_session == null:
		push_warning("[KPI] No active session - call start_session() first")
		return {}

	var analysis = {
		"timestamp": Time.get_unix_time_from_system(),
		"response": response,
		"checks": {}
	}

	# Run all KPI checks
	analysis.checks.identity = _check_identity_adherence(response)
	analysis.checks.speech = _check_speech_compliance(response)
	analysis.checks.thresholds = _check_threshold_accuracy(response, context)
	analysis.checks.traits = _check_trait_consistency(response, context)
	analysis.checks.world = _check_world_accuracy(response)

	# Record response
	kpi_data.current_session.responses.append(analysis)

	# Update running metrics
	_update_session_metrics(analysis)

	# Log violations
	var violations = _extract_violations(analysis)
	if violations.size() > 0:
		for v in violations:
			kpi_data.current_session.violations.append(v)
			print("[KPI VIOLATION] %s: %s" % [v.type, v.detail])

	return analysis

## ============================================================================
## KPI CHECK IMPLEMENTATIONS
## ============================================================================

## Check 1: Identity Anchor Adherence
func _check_identity_adherence(response: String) -> Dictionary:
	var result = {"passed": true, "violations": []}

	if tracked_personality == null:
		return result

	var response_lower = response.to_lower()

	# Check for contradictions to identity anchors
	for anchor in tracked_personality.identity_anchors:
		var contradiction = _check_for_contradiction(response_lower, anchor)
		if contradiction.found:
			result.passed = false
			result.violations.append({
				"anchor": anchor,
				"contradiction": contradiction.detail
			})

	# Update metrics
	kpi_data.current_session.metrics.identity_adherence.total += 1
	if result.passed:
		kpi_data.current_session.metrics.identity_adherence.passed += 1

	return result

## Check 2: Speech Pattern Compliance
func _check_speech_compliance(response: String) -> Dictionary:
	var result = {
		"forbidden_used": [],
		"signature_used": [],
		"vocabulary_appropriate": true
	}

	if tracked_personality == null:
		return result

	var response_lower = response.to_lower()

	# Check forbidden phrases
	for phrase in tracked_personality.forbidden_phrases:
		if phrase.to_lower() in response_lower:
			result.forbidden_used.append(phrase)
			kpi_data.current_session.metrics.speech_compliance.forbidden_violations += 1

	# Check signature phrases
	for phrase in tracked_personality.signature_phrases:
		# Allow partial matches for signature phrases
		var phrase_words = phrase.to_lower().split(" ")
		var match_count = 0
		for word in phrase_words:
			if word in response_lower:
				match_count += 1
		if match_count >= phrase_words.size() * 0.7:  # 70% match threshold
			result.signature_used.append(phrase)
			kpi_data.current_session.metrics.speech_compliance.signature_uses += 1

	# Check vocabulary level
	result.vocabulary_appropriate = _check_vocabulary_level(response, tracked_personality.vocabulary_level)

	kpi_data.current_session.metrics.speech_compliance.total_responses += 1

	return result

## Check 3: Threshold Accuracy
func _check_threshold_accuracy(response: String, context: Dictionary) -> Dictionary:
	var result = {"passed": true, "violations": []}

	if tracked_personality == null:
		return result

	var trust = context.get("trust", 0)
	var affection = context.get("affection", 0)
	var familiarity = context.get("familiarity", 0)

	# Check if secrets were revealed when they shouldn't be
	for secret_data in tracked_personality.secrets:
		var secret_text = secret_data.get("secret", "")
		var required_trust = secret_data.get("unlock_trust", 100)
		var required_affection = secret_data.get("unlock_affection", 100)

		# Check if secret content appears in response
		if _response_contains_secret(response, secret_text):
			if trust < required_trust or affection < required_affection:
				result.passed = false
				result.violations.append({
					"type": "premature_secret_reveal",
					"secret": secret_text.substr(0, 50) + "...",
					"required_trust": required_trust,
					"actual_trust": trust,
					"required_affection": required_affection,
					"actual_affection": affection
				})

	# Check romance availability
	var romance_indicators = ["kiss", "love you", "spend the night", "my heart", "romantic"]
	var has_romance_content = false
	var response_lower = response.to_lower()
	for indicator in romance_indicators:
		if indicator in response_lower:
			has_romance_content = true
			break

	if has_romance_content and not tracked_personality.is_romance_unlocked(trust, affection, familiarity):
		result.passed = false
		result.violations.append({
			"type": "premature_romance",
			"actual_stats": {"trust": trust, "affection": affection, "familiarity": familiarity}
		})

	kpi_data.current_session.metrics.threshold_accuracy.total += 1
	if result.passed:
		kpi_data.current_session.metrics.threshold_accuracy.passed += 1

	return result

## Check 4: Trait Consistency
func _check_trait_consistency(response: String, context: Dictionary) -> Dictionary:
	var result = {"aligned": true, "analysis": {}}

	if tracked_personality == null:
		return result

	var response_lower = response.to_lower()

	# Check trait alignment
	var trait_checks = []

	# Extraversion check
	if tracked_personality.trait_extraversion > 50:
		# Extraverted NPCs should have more enthusiastic responses
		var enthusiastic_markers = ["!", "wonderful", "excellent", "delighted", "pleasure"]
		var found = false
		for marker in enthusiastic_markers:
			if marker in response_lower:
				found = true
				break
		trait_checks.append({"trait": "extraversion_high", "expected": "enthusiastic", "found": found})
	elif tracked_personality.trait_extraversion < -50:
		# Introverted NPCs should have more reserved responses
		var reserved_markers = ["...", "hmm", "perhaps", "quietly"]
		var found = false
		for marker in reserved_markers:
			if marker in response_lower:
				found = true
				break
		trait_checks.append({"trait": "extraversion_low", "expected": "reserved", "found": found})

	# Agreeableness check
	if tracked_personality.trait_agreeableness > 50:
		var agreeable_markers = ["of course", "happy to", "glad to help", "certainly"]
		var found = false
		for marker in agreeable_markers:
			if marker in response_lower:
				found = true
				break
		trait_checks.append({"trait": "agreeableness_high", "expected": "helpful", "found": found})

	# Calculate alignment percentage
	var aligned_count = 0
	for check in trait_checks:
		if check.found:
			aligned_count += 1

	result.analysis.checks = trait_checks
	result.analysis.alignment_rate = float(aligned_count) / max(1, trait_checks.size())
	result.aligned = result.analysis.alignment_rate >= 0.5  # 50% threshold

	kpi_data.current_session.metrics.trait_consistency.total += 1
	if result.aligned:
		kpi_data.current_session.metrics.trait_consistency.aligned += 1

	return result

## Check 5: World Knowledge Accuracy
func _check_world_accuracy(response: String) -> Dictionary:
	var result = {"passed": true, "violations": []}

	if tracked_personality == null:
		return result

	var response_lower = response.to_lower()

	# Check if NPC contradicts their own WorldKnowledge facts
	if WorldKnowledge:
		var npc_facts = WorldKnowledge.get_fact("npcs", tracked_personality.npc_id)
		if npc_facts:
			# Check name consistency
			if npc_facts.has("name"):
				var wrong_names = _detect_wrong_self_reference(response, npc_facts.name)
				if wrong_names.size() > 0:
					result.passed = false
					result.violations.append({
						"type": "wrong_name",
						"expected": npc_facts.name,
						"found": wrong_names
					})

			# Check family consistency
			if npc_facts.has("family"):
				for family_id in npc_facts.family:
					var family_member = WorldKnowledge.get_fact("npcs", family_id)
					if family_member and family_member.has("name"):
						# If NPC mentions family member, name should be correct
						var family_keywords = ["daughter", "father", "mother", "son", "sister", "brother"]
						for keyword in family_keywords:
							if keyword in response_lower:
								# Check if wrong name is used for family
								pass  # Complex check - simplified for now

	kpi_data.current_session.metrics.world_accuracy.total += 1
	if result.passed:
		kpi_data.current_session.metrics.world_accuracy.passed += 1

	return result

## ============================================================================
## HELPER FUNCTIONS
## ============================================================================

## Check for contradiction between response and an identity anchor
func _check_for_contradiction(response_lower: String, anchor: String) -> Dictionary:
	# This is a simplified contradiction check
	# In production, could use Claude to analyze for contradictions

	var result = {"found": false, "detail": ""}

	# Extract key facts from anchor
	var anchor_lower = anchor.to_lower()

	# Check for age contradictions
	var age_pattern = RegEx.new()
	age_pattern.compile("age (\\d+)")
	var anchor_age_match = age_pattern.search(anchor_lower)
	if anchor_age_match:
		var correct_age = anchor_age_match.get_string(1)
		# Check if response mentions a different age
		var response_age_match = age_pattern.search(response_lower)
		if response_age_match:
			var stated_age = response_age_match.get_string(1)
			if stated_age != correct_age:
				result.found = true
				result.detail = "Age contradiction: anchor says %s, response says %s" % [correct_age, stated_age]

	# Check for name contradictions
	if "you are" in anchor_lower:
		var name_start = anchor_lower.find("you are ") + 8
		var name_end = anchor_lower.find(",", name_start)
		if name_end == -1:
			name_end = anchor_lower.find(" ", name_start + 1)
		if name_end > name_start:
			var expected_name = anchor.substr(name_start, name_end - name_start).strip_edges()
			# Check if NPC refers to self by different name
			if "my name is" in response_lower:
				var stated_name_start = response_lower.find("my name is ") + 11
				var stated_name_end = response_lower.find(" ", stated_name_start)
				if stated_name_end == -1:
					stated_name_end = response_lower.length()
				var stated_name = response_lower.substr(stated_name_start, stated_name_end - stated_name_start)
				if expected_name.to_lower() not in stated_name:
					result.found = true
					result.detail = "Name contradiction: expected %s, stated %s" % [expected_name, stated_name]

	return result

## Check if vocabulary matches expected level
func _check_vocabulary_level(response: String, expected_level: String) -> bool:
	var response_lower = response.to_lower()

	match expected_level:
		"simple":
			# Should not contain overly complex words
			var complex_words = ["henceforth", "indubitably", "notwithstanding", "heretofore"]
			for word in complex_words:
				if word in response_lower:
					return false
		"scholarly":
			# Should contain some sophisticated language
			var scholarly_indicators = ["indeed", "furthermore", "however", "therefore", "thus"]
			var found = false
			for word in scholarly_indicators:
				if word in response_lower:
					found = true
					break
			# Scholarly should use these sometimes, but not required every response
		"street":
			# Should not be overly formal
			var formal_markers = ["good sir", "madam", "i beg your pardon", "if you please"]
			for marker in formal_markers:
				if marker in response_lower:
					return false

	return true

## Check if response contains secret content
func _response_contains_secret(response: String, secret: String) -> bool:
	var response_lower = response.to_lower()
	var secret_lower = secret.to_lower()

	# Extract key phrases from secret (simplified)
	var secret_words = secret_lower.split(" ")
	var significant_words = []
	for word in secret_words:
		if word.length() > 4:  # Only consider significant words
			significant_words.append(word)

	# Check if multiple significant words appear
	var match_count = 0
	for word in significant_words:
		if word in response_lower:
			match_count += 1

	# If 50%+ of significant words match, consider secret revealed
	return match_count >= significant_words.size() * 0.5

## Detect wrong self-references
func _detect_wrong_self_reference(response: String, correct_name: String) -> Array:
	var wrong_names = []
	var self_refs = ["my name is", "i am", "call me"]
	var response_lower = response.to_lower()
	var correct_lower = correct_name.to_lower()

	for ref in self_refs:
		var pos = response_lower.find(ref)
		if pos >= 0:
			var name_start = pos + ref.length() + 1
			var name_end = response_lower.find(" ", name_start)
			if name_end == -1:
				name_end = min(name_start + 20, response_lower.length())
			var stated = response_lower.substr(name_start, name_end - name_start).strip_edges()
			if stated.length() > 0 and correct_lower not in stated and stated not in correct_lower:
				wrong_names.append(stated)

	return wrong_names

## Extract all violations from analysis
func _extract_violations(analysis: Dictionary) -> Array:
	var violations = []

	if not analysis.checks.identity.passed:
		for v in analysis.checks.identity.violations:
			violations.append({"type": "identity", "detail": v})

	if analysis.checks.speech.forbidden_used.size() > 0:
		violations.append({
			"type": "forbidden_phrase",
			"detail": "Used forbidden phrases: %s" % ", ".join(analysis.checks.speech.forbidden_used)
		})

	if not analysis.checks.thresholds.passed:
		for v in analysis.checks.thresholds.violations:
			violations.append({"type": "threshold", "detail": v})

	if not analysis.checks.traits.aligned:
		violations.append({
			"type": "trait_misalignment",
			"detail": "Response doesn't align with personality traits"
		})

	if not analysis.checks.world.passed:
		for v in analysis.checks.world.violations:
			violations.append({"type": "world_accuracy", "detail": v})

	return violations

## Update running session metrics
func _update_session_metrics(analysis: Dictionary) -> void:
	# Metrics are updated in individual check functions
	pass

## Calculate final session metrics
func _calculate_session_metrics() -> Dictionary:
	var m = kpi_data.current_session.metrics

	var identity_rate = 0.0
	if m.identity_adherence.total > 0:
		identity_rate = float(m.identity_adherence.passed) / m.identity_adherence.total * 100

	var speech_violation_rate = 0.0
	var signature_usage_rate = 0.0
	if m.speech_compliance.total_responses > 0:
		speech_violation_rate = float(m.speech_compliance.forbidden_violations) / m.speech_compliance.total_responses * 100
		signature_usage_rate = float(m.speech_compliance.signature_uses) / m.speech_compliance.total_responses * 100

	var threshold_rate = 0.0
	if m.threshold_accuracy.total > 0:
		threshold_rate = float(m.threshold_accuracy.passed) / m.threshold_accuracy.total * 100

	var trait_rate = 0.0
	if m.trait_consistency.total > 0:
		trait_rate = float(m.trait_consistency.aligned) / m.trait_consistency.total * 100

	var world_rate = 0.0
	if m.world_accuracy.total > 0:
		world_rate = float(m.world_accuracy.passed) / m.world_accuracy.total * 100

	return {
		"identity_anchor_adherence": {
			"rate": identity_rate,
			"target": 100.0,
			"passed": identity_rate >= 100.0
		},
		"speech_pattern_compliance": {
			"forbidden_violation_rate": speech_violation_rate,
			"signature_usage_rate": signature_usage_rate,
			"target_violation_rate": 0.0,
			"target_signature_rate": 20.0,
			"passed": speech_violation_rate == 0.0 and signature_usage_rate >= 20.0
		},
		"relationship_threshold_accuracy": {
			"rate": threshold_rate,
			"target": 100.0,
			"passed": threshold_rate >= 100.0
		},
		"personality_trait_consistency": {
			"rate": trait_rate,
			"target": 90.0,
			"passed": trait_rate >= 90.0
		},
		"world_knowledge_accuracy": {
			"rate": world_rate,
			"target": 100.0,
			"passed": world_rate >= 100.0
		},
		"total_responses_analyzed": kpi_data.current_session.responses.size(),
		"total_violations": kpi_data.current_session.violations.size(),
		"overall_health": _calculate_overall_health()
	}

## Calculate overall personality health score
func _calculate_overall_health() -> String:
	var metrics = _calculate_session_metrics()
	var passed_count = 0
	var total_count = 5

	if metrics.identity_anchor_adherence.passed:
		passed_count += 1
	if metrics.speech_pattern_compliance.passed:
		passed_count += 1
	if metrics.relationship_threshold_accuracy.passed:
		passed_count += 1
	if metrics.personality_trait_consistency.passed:
		passed_count += 1
	if metrics.world_knowledge_accuracy.passed:
		passed_count += 1

	var health_percentage = float(passed_count) / total_count * 100

	if health_percentage >= 100:
		return "EXCELLENT"
	elif health_percentage >= 80:
		return "GOOD"
	elif health_percentage >= 60:
		return "FAIR"
	elif health_percentage >= 40:
		return "POOR"
	else:
		return "CRITICAL"

## ============================================================================
## REPORTING
## ============================================================================

## Generate a full report for the current or last session
func generate_report() -> String:
	var session = kpi_data.current_session
	if session == null and kpi_data.sessions.size() > 0:
		session = kpi_data.sessions[-1]

	if session == null:
		return "No session data available"

	var metrics = session.get("final_metrics", _calculate_session_metrics())

	var report = "=" .repeat(60) + "\n"
	report += "PERSONALITY CONSISTENCY KPI REPORT\n"
	report += "NPC: %s\n" % session.npc_id
	report += "=" .repeat(60) + "\n\n"

	report += "OVERALL HEALTH: %s\n\n" % metrics.overall_health

	report += "KPI BREAKDOWN:\n"
	report += "-" .repeat(40) + "\n"

	report += "1. Identity Anchor Adherence\n"
	report += "   Rate: %.1f%% (Target: 100%%)\n" % metrics.identity_anchor_adherence.rate
	report += "   Status: %s\n\n" % ("PASS" if metrics.identity_anchor_adherence.passed else "FAIL")

	report += "2. Speech Pattern Compliance\n"
	report += "   Forbidden Violations: %.1f%% (Target: 0%%)\n" % metrics.speech_pattern_compliance.forbidden_violation_rate
	report += "   Signature Usage: %.1f%% (Target: 20%%+)\n" % metrics.speech_pattern_compliance.signature_usage_rate
	report += "   Status: %s\n\n" % ("PASS" if metrics.speech_pattern_compliance.passed else "FAIL")

	report += "3. Relationship Threshold Accuracy\n"
	report += "   Rate: %.1f%% (Target: 100%%)\n" % metrics.relationship_threshold_accuracy.rate
	report += "   Status: %s\n\n" % ("PASS" if metrics.relationship_threshold_accuracy.passed else "FAIL")

	report += "4. Personality Trait Consistency\n"
	report += "   Rate: %.1f%% (Target: 90%%)\n" % metrics.personality_trait_consistency.rate
	report += "   Status: %s\n\n" % ("PASS" if metrics.personality_trait_consistency.passed else "FAIL")

	report += "5. World Knowledge Accuracy\n"
	report += "   Rate: %.1f%% (Target: 100%%)\n" % metrics.world_knowledge_accuracy.rate
	report += "   Status: %s\n\n" % ("PASS" if metrics.world_knowledge_accuracy.passed else "FAIL")

	report += "-" .repeat(40) + "\n"
	report += "Total Responses Analyzed: %d\n" % metrics.total_responses_analyzed
	report += "Total Violations: %d\n" % metrics.total_violations

	if session.violations.size() > 0:
		report += "\nVIOLATION DETAILS:\n"
		for i in range(min(10, session.violations.size())):
			var v = session.violations[i]
			report += "  - [%s] %s\n" % [v.type, str(v.detail).substr(0, 60)]
		if session.violations.size() > 10:
			report += "  ... and %d more\n" % (session.violations.size() - 10)

	report += "\n" + "=" .repeat(60) + "\n"

	return report

## Get aggregate metrics across all sessions
func get_aggregate_metrics() -> Dictionary:
	if kpi_data.sessions.size() == 0:
		return {}

	var totals = {
		"identity_rates": [],
		"speech_violation_rates": [],
		"signature_rates": [],
		"threshold_rates": [],
		"trait_rates": [],
		"world_rates": []
	}

	for session in kpi_data.sessions:
		var m = session.get("final_metrics", {})
		if m.has("identity_anchor_adherence"):
			totals.identity_rates.append(m.identity_anchor_adherence.rate)
		if m.has("speech_pattern_compliance"):
			totals.speech_violation_rates.append(m.speech_pattern_compliance.forbidden_violation_rate)
			totals.signature_rates.append(m.speech_pattern_compliance.signature_usage_rate)
		if m.has("relationship_threshold_accuracy"):
			totals.threshold_rates.append(m.relationship_threshold_accuracy.rate)
		if m.has("personality_trait_consistency"):
			totals.trait_rates.append(m.personality_trait_consistency.rate)
		if m.has("world_knowledge_accuracy"):
			totals.world_rates.append(m.world_knowledge_accuracy.rate)

	return {
		"sessions_count": kpi_data.sessions.size(),
		"avg_identity_adherence": _average(totals.identity_rates),
		"avg_speech_violation_rate": _average(totals.speech_violation_rates),
		"avg_signature_usage": _average(totals.signature_rates),
		"avg_threshold_accuracy": _average(totals.threshold_rates),
		"avg_trait_consistency": _average(totals.trait_rates),
		"avg_world_accuracy": _average(totals.world_rates)
	}

func _average(arr: Array) -> float:
	if arr.size() == 0:
		return 0.0
	var sum = 0.0
	for v in arr:
		sum += v
	return sum / arr.size()
