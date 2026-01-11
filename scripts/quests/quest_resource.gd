class_name QuestResource
extends Resource
## Defines a quest structure that observes game state rather than controlling dialogue
## Quests are discovered and progress through natural conversation and world exploration

@export var quest_id: String = ""
@export var title: String = ""
@export var description: String = ""  # For player journal

# =============================================================================
# AVAILABILITY CONDITIONS (when quest can be discovered)
# =============================================================================

## World flags that must be true for this quest to be available
@export var required_flags: Array[String] = []

## World flags that block this quest if true
@export var blocked_by_flags: Array[String] = []

## Minimum relationship required with specific NPCs: {"npc_id": min_trust}
@export var min_relationship: Dictionary = {}

## Memory tags that must exist in any NPC's memory
@export var required_memories: Array[String] = []

## Other quests that must be completed first
@export var required_quests: Array[String] = []

# =============================================================================
# DISCOVERY TRIGGERS (what makes the quest start)
# =============================================================================

## Intent types that can trigger discovery (from IntentDetector)
@export var discovery_intents: Array[String] = []

## Topics in conversation that can trigger discovery
@export var discovery_topics: Array[String] = []

## Which NPC can reveal/start this quest (empty = any)
@export var discovery_npc: String = ""

## If true, quest auto-starts when conditions are met (no discovery needed)
@export var auto_start: bool = false

# =============================================================================
# OBJECTIVES
# =============================================================================

## Quest objectives - stored as array of QuestObjective resources
@export var objectives: Array[Resource] = []

# =============================================================================
# CONTEXT HINTS (injected into NPC prompts when quest is active)
# =============================================================================

## NPC-specific context hints: {"npc_id": "context string"}
@export var npc_context_hints: Dictionary = {}

## Global context added to all NPCs when quest is active
@export var global_context_hint: String = ""

# =============================================================================
# COMPLETION
# =============================================================================

## Flags to set when quest is completed
@export var completion_flags: Array[String] = []

## Quest IDs to unlock when this quest completes
@export var unlocks_quests: Array[String] = []

## Multiple valid endings: {"ending_id": "description"}
@export var possible_endings: Dictionary = {}

# =============================================================================
# METADATA
# =============================================================================

## Story arc this quest belongs to
@export var story_arc: String = ""

## Priority for display/sorting (higher = more important)
@export var priority: int = 0

## Is this a main story quest or side quest?
@export var is_main_quest: bool = false

# =============================================================================
# RUNTIME STATE
# =============================================================================

enum QuestState { UNAVAILABLE, AVAILABLE, ACTIVE, COMPLETED, FAILED }

var state: QuestState = QuestState.UNAVAILABLE
var started_at: float = 0.0
var completed_at: float = 0.0
var ending_id: String = ""  # Which ending was achieved
var failed_reason: String = ""

# =============================================================================
# METHODS
# =============================================================================

func is_available() -> bool:
	return state == QuestState.AVAILABLE

func is_active() -> bool:
	return state == QuestState.ACTIVE

func is_completed() -> bool:
	return state == QuestState.COMPLETED

func is_failed() -> bool:
	return state == QuestState.FAILED

func can_become_available(world_state) -> bool:
	# Check required flags
	for flag in required_flags:
		if not world_state.get_world_flag(flag):
			return false

	# Check blocking flags
	for flag in blocked_by_flags:
		if world_state.get_world_flag(flag):
			return false

	# Check required quests
	for quest_id_req in required_quests:
		if not world_state.is_quest_completed(quest_id_req):
			return false

	# Check relationship requirements
	for npc_id in min_relationship:
		var required = min_relationship[npc_id]
		var current = world_state.get_npc_relationship(npc_id)
		if current < required:
			return false

	return true

func check_discovery_conditions(npc_id: String, intents: Array, topics: Array) -> bool:
	# If discovery_npc is set, must match
	if not discovery_npc.is_empty() and npc_id != discovery_npc:
		return false

	# Check intent matches
	for intent in discovery_intents:
		if intent in intents:
			return true

	# Check topic matches
	for topic in discovery_topics:
		if topic in topics:
			return true

	# If no discovery conditions set but we have auto_start, that's handled elsewhere
	return false

func start():
	state = QuestState.ACTIVE
	started_at = Time.get_unix_time_from_system()

func complete(ending: String = "default"):
	state = QuestState.COMPLETED
	completed_at = Time.get_unix_time_from_system()
	ending_id = ending

func fail(reason: String = ""):
	state = QuestState.FAILED
	failed_reason = reason

func reset():
	state = QuestState.UNAVAILABLE
	started_at = 0.0
	completed_at = 0.0
	ending_id = ""
	failed_reason = ""
	for objective in objectives:
		objective.reset()

func get_active_objectives() -> Array:
	var active: Array = []
	for objective in objectives:
		if not objective.is_completed:
			active.append(objective)
	return active

func get_completed_objectives() -> Array:
	var completed: Array = []
	for objective in objectives:
		if objective.is_completed:
			completed.append(objective)
	return completed

func get_required_objectives() -> Array:
	var required: Array = []
	for objective in objectives:
		if not objective.optional:
			required.append(objective)
	return required

func are_required_objectives_complete() -> bool:
	for objective in objectives:
		if not objective.optional and not objective.is_completed:
			return false
	return true

func get_progress() -> float:
	if objectives.is_empty():
		return 0.0
	var completed_count = 0
	for objective in objectives:
		if objective.is_completed:
			completed_count += 1
	return float(completed_count) / float(objectives.size())

func get_context_for_npc(npc_id: String) -> String:
	var context = ""

	if not global_context_hint.is_empty():
		context += global_context_hint + "\n"

	if npc_context_hints.has(npc_id):
		context += npc_context_hints[npc_id]

	return context.strip_edges()

func get_save_data() -> Dictionary:
	var objective_data = []
	for objective in objectives:
		objective_data.append(objective.get_save_data())

	return {
		"quest_id": quest_id,
		"state": state,
		"started_at": started_at,
		"completed_at": completed_at,
		"ending_id": ending_id,
		"failed_reason": failed_reason,
		"objectives": objective_data
	}

func load_save_data(data: Dictionary):
	state = data.get("state", QuestState.UNAVAILABLE)
	started_at = data.get("started_at", 0.0)
	completed_at = data.get("completed_at", 0.0)
	ending_id = data.get("ending_id", "")
	failed_reason = data.get("failed_reason", "")

	var objective_data = data.get("objectives", [])
	for i in range(min(objective_data.size(), objectives.size())):
		objectives[i].load_save_data(objective_data[i])
