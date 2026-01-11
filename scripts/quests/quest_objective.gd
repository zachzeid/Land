class_name QuestObjective
extends Resource
## Defines a single objective within a quest
## Objectives complete based on observable game state, not dialogue choices

@export var objective_id: String = ""
@export var description: String = ""  # Player-facing description

# =============================================================================
# COMPLETION CONDITIONS (any can trigger completion)
# =============================================================================

## World flag that completes this objective when set to true
@export var complete_on_flag: String = ""

## Intent type detected in conversation (from IntentDetector)
@export var complete_on_intent: String = ""

## Relationship threshold: {"npc_id": min_value}
@export var complete_on_relationship: Dictionary = {}

## Memory tag - completes when NPC stores memory with this tag
@export var complete_on_memory_tag: String = ""

## Location - completes when player enters this area
@export var complete_on_location: String = ""

## Topics discussed - completes when these topics come up in conversation
@export var complete_on_topics: Array[String] = []

# =============================================================================
# CONSTRAINTS
# =============================================================================

## If set, this specific NPC must be involved for completion
@export var requires_npc: String = ""

## Is this objective optional for quest completion?
@export var optional: bool = false

## Order hint (lower numbers should typically be completed first)
@export var order: int = 0

# =============================================================================
# STATE (runtime, not saved in resource)
# =============================================================================

var is_completed: bool = false
var completed_at: float = 0.0  # Engine time when completed
var completed_by: String = ""  # What triggered completion (flag name, npc_id, etc.)

# =============================================================================
# METHODS
# =============================================================================

func check_flag_condition(flag_name: String, flag_value: bool) -> bool:
	if complete_on_flag.is_empty():
		return false
	return flag_name == complete_on_flag and flag_value == true

func check_relationship_condition(npc_id: String, relationship_value: float) -> bool:
	if complete_on_relationship.is_empty():
		return false
	if not complete_on_relationship.has(npc_id):
		return false
	return relationship_value >= complete_on_relationship[npc_id]

func check_intent_condition(intent_type: String, npc_id: String = "") -> bool:
	if complete_on_intent.is_empty():
		return false
	if not requires_npc.is_empty() and npc_id != requires_npc:
		return false
	return intent_type == complete_on_intent

func check_location_condition(location_id: String) -> bool:
	if complete_on_location.is_empty():
		return false
	return location_id == complete_on_location

func check_memory_condition(memory_tag: String, npc_id: String = "") -> bool:
	if complete_on_memory_tag.is_empty():
		return false
	if not requires_npc.is_empty() and npc_id != requires_npc:
		return false
	return memory_tag == complete_on_memory_tag

func check_topics_condition(topics: Array) -> bool:
	if complete_on_topics.is_empty():
		return false
	for topic in complete_on_topics:
		if topic in topics:
			return true
	return false

func mark_completed(completed_by_trigger: String = ""):
	is_completed = true
	completed_at = Time.get_unix_time_from_system()
	completed_by = completed_by_trigger

func reset():
	is_completed = false
	completed_at = 0.0
	completed_by = ""

func get_save_data() -> Dictionary:
	return {
		"objective_id": objective_id,
		"is_completed": is_completed,
		"completed_at": completed_at,
		"completed_by": completed_by
	}

func load_save_data(data: Dictionary):
	is_completed = data.get("is_completed", false)
	completed_at = data.get("completed_at", 0.0)
	completed_by = data.get("completed_by", "")
