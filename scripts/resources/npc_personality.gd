extends Resource
class_name NPCPersonality
## NPCPersonality - Structured personality definition for AI-driven NPCs
## Ensures consistent character behavior across all Claude interactions

## ============================================================================
## CORE IDENTITY (Always injected, never pushed out by context)
## ============================================================================

@export_group("Core Identity")
## Unique identifier matching npc_id in WorldKnowledge
@export var npc_id: String = ""
## Display name used in dialogue
@export var display_name: String = ""
## One-sentence character summary (injected every prompt)
@export_multiline var core_identity: String = ""
## 3-5 immutable facts about this character (always in context)
@export var identity_anchors: Array[String] = []

## ============================================================================
## PERSONALITY TRAITS (Structured for impact calculations)
## ============================================================================

@export_group("Personality Traits")

## Primary traits that define character behavior (-100 to 100 scale)
## These modify how interactions affect relationship dimensions
@export_subgroup("Core Traits")
@export_range(-100, 100) var trait_openness: int = 0          ## Curious vs Traditional
@export_range(-100, 100) var trait_conscientiousness: int = 0 ## Organized vs Spontaneous
@export_range(-100, 100) var trait_extraversion: int = 0      ## Outgoing vs Reserved
@export_range(-100, 100) var trait_agreeableness: int = 0     ## Compassionate vs Competitive
@export_range(-100, 100) var trait_neuroticism: int = 0       ## Sensitive vs Resilient

## Character-specific traits that influence behavior
@export_subgroup("Character Traits")
@export var is_romantic_available: bool = false
@export var is_flirtatious: bool = false
@export var is_secretive: bool = false
@export var is_protective: bool = false
@export var is_ambitious: bool = false
@export var is_fearful: bool = false
@export var is_trusting: bool = false
@export var is_humorous: bool = false

## Values this NPC holds dear (affects respect/trust gains)
@export var core_values: Array[String] = []
## Things this NPC fears (affects fear dimension)
@export var fears: Array[String] = []
## Topics NPC loves discussing (affects affection gains)
@export var interests: Array[String] = []
## Topics NPC avoids or dislikes
@export var dislikes: Array[String] = []

## ============================================================================
## SPEECH PATTERNS (Enforced in every response)
## ============================================================================

@export_group("Speech Patterns")
## Vocabulary level: "simple", "educated", "scholarly", "street", "archaic"
@export_enum("simple", "educated", "scholarly", "street", "archaic") var vocabulary_level: String = "simple"
## Speaking style: "formal", "casual", "warm", "cold", "nervous", "confident"
@export_enum("formal", "casual", "warm", "cold", "nervous", "confident") var speaking_style: String = "casual"
## Signature phrases this character uses often
@export var signature_phrases: Array[String] = []
## Words/phrases this character NEVER uses
@export var forbidden_phrases: Array[String] = []
## Verbal tics or habits (e.g., "clears throat", "laughs nervously")
@export var verbal_tics: Array[String] = []
## How they address the player initially: "stranger", "friend", "customer", etc.
@export var default_player_address: String = "stranger"

## ============================================================================
## RELATIONSHIP & ROMANCE
## ============================================================================

@export_group("Relationship Settings")
## Sexual/romantic orientation for appropriate responses
@export_enum("player_sexual", "heterosexual", "homosexual", "bisexual", "asexual", "demisexual") var orientation: String = "player_sexual"
## Relationship style preference
@export_enum("monogamous", "polyamorous", "aromantic", "casual_only", "romance_only") var relationship_style: String = "monogamous"
## Minimum affection for romantic interest to show
@export_range(0, 100) var romance_affection_threshold: int = 50
## Minimum trust for romantic interest to show
@export_range(0, 100) var romance_trust_threshold: int = 40
## Minimum familiarity before romance possible
@export_range(0, 100) var romance_familiarity_threshold: int = 30

## ============================================================================
## SECRETS & HIDDEN INFORMATION
## ============================================================================

@export_group("Secrets")
## Secrets this NPC knows (with unlock conditions)
## Format: {"secret": "text", "unlock_trust": 60, "unlock_affection": 50}
@export var secrets: Array[Dictionary] = []
## Information NPC will NEVER reveal (even under duress)
@export var unbreakable_secrets: Array[String] = []

## ============================================================================
## BEHAVIORAL MODIFIERS (Affect impact calculations)
## ============================================================================

@export_group("Impact Modifiers")
## Multiplier for trust gains/losses (1.0 = normal)
@export_range(0.5, 2.0) var trust_sensitivity: float = 1.0
## Multiplier for respect gains/losses
@export_range(0.5, 2.0) var respect_sensitivity: float = 1.0
## Multiplier for affection gains/losses
@export_range(0.5, 2.0) var affection_sensitivity: float = 1.0
## Multiplier for fear gains/losses
@export_range(0.5, 2.0) var fear_sensitivity: float = 1.0
## How quickly this NPC forgives (-100 to 100, higher = more forgiving)
@export_range(-100, 100) var forgiveness_tendency: int = 0
## How easily intimidated (higher = more easily scared)
@export_range(0, 100) var intimidation_susceptibility: int = 50

## ============================================================================
## DYNAMIC STATE (Modified at runtime, not saved in resource)
## ============================================================================

## Current emotional state (set by game events, not exported)
var current_mood: String = "neutral"
## Recent emotional triggers (for context)
var recent_triggers: Array[String] = []

## ============================================================================
## FULL SYSTEM PROMPT GENERATION
## ============================================================================

## The detailed personality prompt (for backward compatibility and complex scenarios)
@export_group("Legacy")
@export_multiline var full_system_prompt: String = ""

## ============================================================================
## HELPER METHODS
## ============================================================================

## Generate core identity block for context injection
func get_core_identity_block() -> String:
	var block = "## CORE IDENTITY (Never contradict these facts)\n"
	block += "You are %s.\n" % display_name
	block += "%s\n\n" % core_identity

	if identity_anchors.size() > 0:
		block += "**Immutable Facts About You:**\n"
		for anchor in identity_anchors:
			block += "- %s\n" % anchor
		block += "\n"

	return block

## Generate speech pattern instructions
func get_speech_pattern_block() -> String:
	var block = "## SPEECH PATTERNS (Follow these strictly)\n"
	block += "- Vocabulary: %s level\n" % vocabulary_level
	block += "- Style: %s\n" % speaking_style

	if signature_phrases.size() > 0:
		block += "- Use these phrases naturally: %s\n" % ", ".join(signature_phrases)

	if forbidden_phrases.size() > 0:
		block += "- NEVER say: %s\n" % ", ".join(forbidden_phrases)

	if verbal_tics.size() > 0:
		block += "- Verbal habits: %s\n" % ", ".join(verbal_tics)

	block += "\n"
	return block

## Generate personality trait summary for Claude
func get_personality_summary() -> String:
	var summary = "## YOUR PERSONALITY\n"

	# Translate Big Five into natural language
	if trait_openness > 50:
		summary += "- You're curious and open to new experiences\n"
	elif trait_openness < -50:
		summary += "- You prefer tradition and familiar routines\n"

	if trait_extraversion > 50:
		summary += "- You're outgoing and energized by social interaction\n"
	elif trait_extraversion < -50:
		summary += "- You're reserved and prefer smaller, quieter interactions\n"

	if trait_agreeableness > 50:
		summary += "- You're compassionate and cooperative\n"
	elif trait_agreeableness < -50:
		summary += "- You're competitive and sometimes challenging\n"

	if trait_neuroticism > 50:
		summary += "- You're emotionally sensitive and feel things deeply\n"
	elif trait_neuroticism < -50:
		summary += "- You're emotionally resilient and hard to rattle\n"

	# Character traits
	var traits = []
	if is_flirtatious: traits.append("flirtatious when comfortable")
	if is_secretive: traits.append("keeps secrets close")
	if is_protective: traits.append("fiercely protective of loved ones")
	if is_ambitious: traits.append("driven by ambition")
	if is_fearful: traits.append("prone to anxiety")
	if is_trusting: traits.append("quick to trust")
	if is_humorous: traits.append("uses humor to connect")

	if traits.size() > 0:
		summary += "- You are: %s\n" % ", ".join(traits)

	if core_values.size() > 0:
		summary += "- You value: %s\n" % ", ".join(core_values)

	if fears.size() > 0:
		summary += "- You fear: %s\n" % ", ".join(fears)

	summary += "\n"
	return summary

## Get secrets that should be revealed based on current relationship
func get_unlocked_secrets(trust: float, affection: float) -> Array[String]:
	var unlocked: Array[String] = []
	for secret_data in secrets:
		var required_trust = secret_data.get("unlock_trust", 100)
		var required_affection = secret_data.get("unlock_affection", 100)
		if trust >= required_trust and affection >= required_affection:
			unlocked.append(secret_data.get("secret", ""))
	return unlocked

## Check if romance is available based on thresholds
func is_romance_unlocked(trust: float, affection: float, familiarity: float) -> bool:
	if not is_romantic_available:
		return false
	return trust >= romance_trust_threshold and \
		   affection >= romance_affection_threshold and \
		   familiarity >= romance_familiarity_threshold

## Apply personality modifiers to relationship impacts
func apply_personality_modifiers(impacts: Dictionary) -> Dictionary:
	var modified = impacts.duplicate()

	modified["trust"] = int(modified.get("trust", 0) * trust_sensitivity)
	modified["respect"] = int(modified.get("respect", 0) * respect_sensitivity)
	modified["affection"] = int(modified.get("affection", 0) * affection_sensitivity)
	modified["fear"] = int(modified.get("fear", 0) * fear_sensitivity)

	# Forgiveness affects negative trust/affection recovery
	if forgiveness_tendency > 50 and modified.get("trust", 0) < 0:
		modified["trust"] = int(modified["trust"] * 0.7)  # Reduced penalty
	elif forgiveness_tendency < -50 and modified.get("trust", 0) < 0:
		modified["trust"] = int(modified["trust"] * 1.3)  # Increased penalty

	# Intimidation susceptibility affects fear gains
	if modified.get("fear", 0) > 0:
		var fear_multiplier = 0.5 + (intimidation_susceptibility / 100.0)
		modified["fear"] = int(modified["fear"] * fear_multiplier)

	return modified

## Generate complete system prompt from structured data
func generate_system_prompt() -> String:
	var prompt = get_core_identity_block()
	prompt += get_personality_summary()
	prompt += get_speech_pattern_block()

	# Add full system prompt for complex scenarios if provided
	if full_system_prompt != "":
		prompt += "\n## ADDITIONAL CONTEXT\n"
		prompt += full_system_prompt
		prompt += "\n"

	return prompt
