class_name IntentDetector
extends RefCounted
## Analyzes NPC responses to extract quest-relevant intents and topics
## Used by QuestManager to trigger quest discovery and objective completion

# Intent categories that can trigger quest events
const REVELATION_INTENTS = ["revelation", "confession", "secret_shared", "information"]
const QUEST_INTENTS = ["quest_hint", "task_given", "request", "plea"]
const RELATIONSHIP_INTENTS = ["trust_gained", "bonding", "friendship", "romance_hint"]
const CONFLICT_INTENTS = ["accusation", "confrontation", "threat", "warning"]

# Topic keywords that map to story elements
const TOPIC_KEYWORDS = {
	"bandits": ["bandit", "bandits", "raiders", "thieves", "outlaws"],
	"weapons": ["weapon", "weapons", "sword", "swords", "arms", "armory", "smithy"],
	"ledger": ["ledger", "book", "records", "accounts", "documents"],
	"conspiracy": ["conspiracy", "plot", "scheme", "secret dealings"],
	"gregor": ["gregor", "merchant", "trader"],
	"elena": ["elena", "daughter", "girl"],
	"mira": ["mira", "boss", "resistance", "underground"],
	"marcus": ["marcus", "execution", "death", "killed"],
	"varn": ["varn", "enforcer", "guard captain"],
	"iron_hollow": ["iron hollow", "bandit camp", "hideout"],
}

## Analyze a Claude response and extract intents
func analyze_response(response_data: Dictionary) -> Dictionary:
	var result = {
		"intents": [],              # Detected intent types
		"topics": [],               # Topics discussed
		"revelations": [],          # Secrets or information revealed
		"emotional_shift": "",      # trust_gained, trust_lost, neutral
		"relationship_implication": "", # ally, enemy, neutral, romantic
		"quest_relevant": false     # Whether this might affect quests
	}

	# Extract from Claude's structured response
	var interaction_type = response_data.get("interaction_type", "")
	var player_tone = response_data.get("player_tone", "")
	var emotional_impact = response_data.get("emotional_impact", "")
	var topics_discussed = response_data.get("topics_discussed", [])
	var npc_response = response_data.get("response", "")

	# Add interaction_type as an intent
	if not interaction_type.is_empty():
		result.intents.append(interaction_type)

	# Categorize the interaction type
	if interaction_type in REVELATION_INTENTS:
		result.revelations.append(interaction_type)
		result.quest_relevant = true

	if interaction_type in QUEST_INTENTS:
		result.quest_relevant = true

	# Process topics from Claude's analysis
	for topic in topics_discussed:
		if topic not in result.topics:
			result.topics.append(topic)

	# Extract additional topics from response text
	var detected_topics = _extract_topics_from_text(npc_response)
	for topic in detected_topics:
		if topic not in result.topics:
			result.topics.append(topic)
			result.quest_relevant = true

	# Determine emotional shift
	result.emotional_shift = _determine_emotional_shift(
		response_data.get("trust_change", 0),
		response_data.get("affection_change", 0),
		response_data.get("fear_change", 0)
	)

	# Determine relationship implication
	result.relationship_implication = _determine_relationship_implication(
		interaction_type, player_tone, emotional_impact
	)

	return result

## Extract topic keywords from response text
func _extract_topics_from_text(text: String) -> Array:
	var found_topics: Array = []
	var lower_text = text.to_lower()

	for topic_name in TOPIC_KEYWORDS:
		for keyword in TOPIC_KEYWORDS[topic_name]:
			if keyword in lower_text:
				if topic_name not in found_topics:
					found_topics.append(topic_name)
				break

	return found_topics

## Determine if trust/affection changed positively or negatively
func _determine_emotional_shift(trust_change: int, affection_change: int, fear_change: int) -> String:
	var positive = trust_change + affection_change
	var negative = fear_change - trust_change - affection_change

	if positive > 5:
		return "trust_gained"
	elif negative > 5:
		return "trust_lost"
	elif fear_change > 5:
		return "fear_induced"
	else:
		return "neutral"

## Determine relationship trajectory
func _determine_relationship_implication(interaction_type: String, player_tone: String, emotional_impact: String) -> String:
	# Ally indicators
	if interaction_type in ["revelation", "confession", "bonding", "trust_building"]:
		return "ally"
	if player_tone in ["friendly", "supportive", "empathetic"]:
		return "ally"

	# Enemy indicators
	if interaction_type in ["accusation", "threat", "confrontation"]:
		if emotional_impact in ["angry", "hostile", "defensive"]:
			return "enemy"

	# Romantic indicators
	if interaction_type in ["flirtation", "romance_hint", "intimate"]:
		return "romantic"

	return "neutral"

## Check if response contains specific revelation types
func check_for_revelation(response_data: Dictionary, revelation_type: String) -> bool:
	var interaction_type = response_data.get("interaction_type", "")
	var topics = response_data.get("topics_discussed", [])

	# Direct match
	if interaction_type == revelation_type:
		return true

	# Check if topic matches revelation type
	if revelation_type in topics:
		return true

	return false

## Check if specific topics were discussed
func check_topics(response_data: Dictionary, required_topics: Array) -> bool:
	var discussed = response_data.get("topics_discussed", [])

	# Also check extracted topics from text
	var text_topics = _extract_topics_from_text(response_data.get("response", ""))
	for topic in text_topics:
		if topic not in discussed:
			discussed.append(topic)

	# Check if any required topic was discussed
	for topic in required_topics:
		if topic in discussed:
			return true

	return false

## Get a summary for debugging
func get_analysis_summary(analysis: Dictionary) -> String:
	var parts: Array = []

	if not analysis.intents.is_empty():
		parts.append("Intents: " + ", ".join(analysis.intents))

	if not analysis.topics.is_empty():
		parts.append("Topics: " + ", ".join(analysis.topics))

	if not analysis.revelations.is_empty():
		parts.append("Revelations: " + ", ".join(analysis.revelations))

	if analysis.emotional_shift != "neutral":
		parts.append("Shift: " + analysis.emotional_shift)

	if analysis.relationship_implication != "neutral":
		parts.append("Relation: " + analysis.relationship_implication)

	if parts.is_empty():
		return "No significant intents detected"

	return " | ".join(parts)
