extends Resource
class_name MemoryConfig
## MemoryConfig - Data-driven configuration for the memory hierarchy system
## Edit this resource to change memory behavior without touching code

## ============================================================================
## CONTEXT BUDGET (How much memory data can fit in Claude's context)
## ============================================================================

@export_group("Context Budget")
## Maximum characters for all memories combined in a single context
## ~2500 tokens at 4 chars/token - leaves room for personality, system prompt, dialogue
@export var max_memory_chars: int = 10000
## Maximum pinned memories to include (relationship-defining moments)
@export var max_pinned_memories: int = 8
## Maximum important memories to include (significant events)
@export var max_important_memories: int = 5
## Maximum regular memories from semantic search
@export var max_regular_memories: int = 8

## ============================================================================
## SCORE-BASED SELECTION (Phase 1 Implementation)
## ============================================================================

@export_group("Score-Based Selection")
## Enable score-based selection (set false to use legacy tier-only selection)
@export var use_score_based_selection: bool = true
## Tier weights for scoring (PINNED, IMPORTANT, REGULAR)
@export var tier_weights: Array[float] = [3.0, 2.0, 1.0]
## Half-life for recency decay in days
@export var recency_half_life_days: float = 7.0
## Minimum recency factor (prevents total decay)
@export var recency_floor: float = 0.3
## Minimum relevance factor
@export var relevance_floor: float = 0.3
## Score multiplier for superseded memories (history preserved but deprioritized)
@export var superseded_score_multiplier: float = 0.1

## ============================================================================
## DUAL REPRESENTATION (Phase 4 Implementation)
## ============================================================================

@export_group("Dual Representation")
## Enable dual representation storage (short + full forms)
@export var use_dual_representation: bool = true
## High relevance threshold - use full form when similarity >= this value
## Prevents non-deterministic tone shifts by using full form only when memory is primary topic
@export var high_relevance_threshold: float = 0.85
## Target length for short summaries (characters)
@export var short_summary_target_length: int = 80
## Maximum length for short summaries (hard cap)
@export var short_summary_max_length: int = 100

## ============================================================================
## BOUNDED CANDIDATE COLLECTION (Phase 2 Implementation)
## ============================================================================

@export_group("Bounded Collection")
## Enable bounded collection (set false to use legacy tiered retrieval)
@export var use_bounded_collection: bool = true
## Days to look back for high-signal events
@export var high_signal_recency_days: int = 7
## High-signal event types to fetch directly (recent important events)
@export var high_signal_event_types: Array[String] = [
	"betrayal", "life_saved", "secret_revealed", "promise_made", "promise_broken",
	"threat_made", "romance_confession", "quest_completed", "quest_failed"
]
## Maximum high-signal memories to fetch
@export var high_signal_limit: int = 10
## Top-K for semantic search
@export var semantic_top_k: int = 15
## Protected slot types (always included, not scored)
@export var protected_slot_types: Array[String] = [
	"relationship_header", "player_name", "npc_death_status"
]
## Token budget for memory context (conservative: 3 chars/token)
@export var memory_token_budget: int = 2500

## ============================================================================
## MILESTONE DEFINITIONS (Events that get auto-pinned)
## ============================================================================

@export_group("Milestones")
## Event types that are automatically treated as milestones (pinned tier)
## Add new milestone types here - no code changes needed
@export var milestone_event_types: Array[String] = [
	"first_meeting",
	"first_gift",
	"first_quest",
	"betrayal",
	"saved_life",
	"romance_confession",
	"romance_rejection",
	"witnessed_kill",
	"shared_danger",
	"secret_revealed",
	"family_death"
]

## ============================================================================
## TIER DETECTION RULES (What makes a memory important)
## ============================================================================

@export_group("Tier Rules")
## Event types that should be pinned (always included in context)
@export var pinned_event_types: Array[String] = [
	"betrayal",
	"saved_life",
	"romance_confession",
	"romance_rejection",
	"witnessed_kill",
	"shared_danger",
	"secret_revealed",
	"family_death",
	"first_meeting",
	"first_gift",
	"first_quest"
]

## Event types that are important (high priority retrieval)
@export var important_event_types: Array[String] = [
	"quest_completed",
	"quest_failed",
	"defended_npc",
	"gift_received",
	"protected_from_threat",
	"emotional_support",
	"romantic_gesture"
]

## Minimum importance score (1-10) to auto-promote to important tier
@export_range(1, 10) var importance_threshold_for_tier: int = 8

## ============================================================================
## CLAUDE ANALYSIS SETTINGS (Let Claude help determine importance)
## ============================================================================

@export_group("Claude Analysis")
## Whether to use Claude to analyze memory importance
## When true, Claude's analysis.interaction_type determines tier
@export var use_claude_for_tier_detection: bool = true

## Interaction types from Claude analysis that should be pinned
## These come from Claude's JSON response analysis.interaction_type field
@export var claude_pinned_interactions: Array[String] = [
	"betrayal",
	"romance_confession",
	"romance_rejection",
	"life_saved",
	"secret_shared"
]

## Interaction types from Claude that are important
@export var claude_important_interactions: Array[String] = [
	"emotional_support",
	"romantic_gesture",
	"threat_made",
	"gift_given",
	"quest_related"
]

## ============================================================================
## CONSOLIDATION SETTINGS (Preventing memory bloat)
## ============================================================================

@export_group("Memory Consolidation")
## Days after which regular conversation memories are consolidated
@export var consolidation_age_days: int = 7
## Minimum number of old memories before consolidation triggers
@export var consolidation_min_count: int = 3
## Whether to auto-consolidate on session end
@export var auto_consolidate: bool = true

## ============================================================================
## SCHEMA CONSTRAINTS (Phase 5 Implementation)
## ============================================================================

@export_group("Schema Constraints")
## Valid interaction types Claude can return - used for validation
## Claude's response is validated against this list; invalid types default to casual_conversation
@export var valid_interaction_types: Array[String] = [
	"casual_conversation", "quest_related", "gift_given",
	"emotional_support", "romantic_gesture", "threat_made",
	"secret_shared", "betrayal", "life_saved", "romance_confession",
	"promise_made", "promise_broken", "defended_player", "information_shared"
]
## Similarity threshold for fuzzy matching invalid types (debug mode only)
@export var interaction_type_similarity_threshold: float = 0.8

## ============================================================================
## DELTA CLAMPING (Phase 5 Implementation)
## ============================================================================

@export_group("Delta Clamping")
## Maximum relationship delta Claude can propose per interaction
## Prevents importance saturation and ensures gradual relationship progression
@export var max_trust_change: int = 15
@export var max_affection_change: int = 10
@export var max_fear_change: int = 10
@export var max_respect_change: int = 10
@export var max_familiarity_change: int = 5

## ============================================================================
## CONFLICT RESOLUTION (Phase 6 Implementation)
## ============================================================================

@export_group("Conflict Resolution")
## Slot types - memories that get complete replacement (only current value matters)
## When a new memory with this slot_type is stored, the old one is deleted
@export var slot_types: Array[String] = [
	"player_name",           # Only one name at a time
	"player_allegiance",     # Current faction loyalty
	"npc_belief_about_player", # What NPC thinks player is
	"current_quest_for_npc"  # Active quest with this NPC
]

## Supersession pairs - narrative state transitions where history is preserved
## Key = original event type, Value = superseding event type
## When superseding event occurs, original gets 0.1x score penalty but isn't deleted
@export var supersession_pairs: Dictionary = {
	"promise_made": "promise_broken",
	"trust_gained": "trust_lost",
	"alliance_formed": "alliance_broken",
	"secret_kept": "secret_revealed"
}

## ============================================================================
## HELPER METHODS
## ============================================================================

## Check if an event type should be pinned
func is_pinned_event(event_type: String) -> bool:
	return event_type in pinned_event_types or event_type in milestone_event_types

## Check if an event type is important
func is_important_event(event_type: String) -> bool:
	return event_type in important_event_types

## Check if a Claude interaction type should be pinned
func is_claude_pinned(interaction_type: String) -> bool:
	if not use_claude_for_tier_detection:
		return false
	return interaction_type in claude_pinned_interactions

## Check if a Claude interaction type is important
func is_claude_important(interaction_type: String) -> bool:
	if not use_claude_for_tier_detection:
		return false
	return interaction_type in claude_important_interactions

## Determine tier from event type and importance
func get_tier_for_event(event_type: String, importance: int, claude_interaction_type: String = "") -> int:
	# Check Claude analysis first (if enabled)
	if use_claude_for_tier_detection and claude_interaction_type != "":
		if is_claude_pinned(claude_interaction_type):
			return 0  # PINNED
		if is_claude_important(claude_interaction_type):
			return 1  # IMPORTANT

	# Check event type rules
	if is_pinned_event(event_type):
		return 0  # PINNED

	if is_important_event(event_type):
		return 1  # IMPORTANT

	# Check importance threshold
	if importance >= importance_threshold_for_tier:
		return 1  # IMPORTANT

	return 2  # REGULAR

## Add a new milestone type at runtime
func add_milestone_type(milestone_type: String) -> void:
	if milestone_type not in milestone_event_types:
		milestone_event_types.append(milestone_type)
		print("[MemoryConfig] Added new milestone type: %s" % milestone_type)

## Add a new pinned event type at runtime
func add_pinned_event_type(event_type: String) -> void:
	if event_type not in pinned_event_types:
		pinned_event_types.append(event_type)
		print("[MemoryConfig] Added new pinned event type: %s" % event_type)

## ============================================================================
## PHASE 5: SCHEMA VALIDATION METHODS
## ============================================================================

## Validate Claude's interaction_type against allowed values
## Returns the validated type or "casual_conversation" as default
func validate_interaction_type(claude_type: String) -> String:
	if claude_type in valid_interaction_types:
		return claude_type

	# Log invalid values - helps identify prompt drift
	push_warning("[MemoryConfig] Invalid interaction_type from Claude: '%s', defaulting to casual_conversation" % claude_type)

	# Fuzzy matching ONLY in debug builds - helps during development
	if OS.is_debug_build():
		for valid in valid_interaction_types:
			if claude_type.similarity(valid) > interaction_type_similarity_threshold:
				push_warning("[MemoryConfig]   (Would have mapped to: %s)" % valid)

	return "casual_conversation"  # Safe default

## Check if an interaction type is valid
func is_valid_interaction_type(interaction_type: String) -> bool:
	return interaction_type in valid_interaction_types

## Clamp relationship deltas from Claude to prevent importance saturation
## Returns a dictionary with clamped values
func clamp_relationship_deltas(analysis: Dictionary) -> Dictionary:
	return {
		"trust_change": clampi(analysis.get("trust_change", 0), -max_trust_change, max_trust_change),
		"affection_change": clampi(analysis.get("affection_change", 0), -max_affection_change, max_affection_change),
		"fear_change": clampi(analysis.get("fear_change", 0), -max_fear_change, max_fear_change),
		"respect_change": clampi(analysis.get("respect_change", 0), -max_respect_change, max_respect_change),
		"familiarity_change": clampi(analysis.get("familiarity_change", 0), -max_familiarity_change, max_familiarity_change)
	}

## Get the interaction type constraint prompt for Claude
## This should be included in the system prompt to constrain Claude's responses
func get_interaction_type_constraint_prompt() -> String:
	var types_list = ""
	for t in valid_interaction_types:
		types_list += "- \"%s\"\n" % t
	return """When analyzing the interaction, classify it as ONE of these exact types:
%s
Do NOT invent new types. Use "casual_conversation" if unsure.""" % types_list

## ============================================================================
## PHASE 6: CONFLICT RESOLUTION METHODS
## ============================================================================

## Check if a slot_type requires complete replacement (no history)
func is_slot_type(slot_type: String) -> bool:
	return slot_type in slot_types

## Check if an event type can supersede another
## Returns the event type it supersedes, or empty string if none
func get_superseded_event_type(event_type: String) -> String:
	for original in supersession_pairs:
		if supersession_pairs[original] == event_type:
			return original
	return ""

## Check if an event type is a supersession target (can be superseded)
func is_supersession_target(event_type: String) -> bool:
	return event_type in supersession_pairs.keys()

## Check if an event type is a supersession trigger (causes supersession)
func is_supersession_trigger(event_type: String) -> bool:
	return event_type in supersession_pairs.values()

## Get the superseding event type for a given original event type
func get_superseding_event_type(original_type: String) -> String:
	return supersession_pairs.get(original_type, "")
