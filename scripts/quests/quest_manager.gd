extends Node
## QuestManager - Central coordinator for the natural language quest system
## Observes game events and updates quest state based on conditions, not dialogue scripts

# Preload quest classes to ensure they're available
const QuestResourceScript = preload("res://scripts/quests/quest_resource.gd")
const IntentDetectorScript = preload("res://scripts/quests/intent_detector.gd")

# Intent detector for analyzing NPC responses
var intent_detector: RefCounted

# Signals for quest state changes
signal quest_available(quest_id: String)
signal quest_discovered(quest_id: String)
signal quest_objective_completed(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String, ending: String)
signal quest_failed(quest_id: String, reason: String)

# Quest storage by state (using Variant for compatibility)
var quest_definitions: Dictionary = {}  # quest_id -> quest (all loaded quests)
var available_quests: Dictionary = {}   # quest_id -> quest (can be discovered)
var active_quests: Dictionary = {}      # quest_id -> quest (in progress)
var completed_quests: Dictionary = {}   # quest_id -> quest
var failed_quests: Dictionary = {}      # quest_id -> quest

# Quest definition directory
const QUEST_DIR = "res://resources/quests/"

# Quest state enum (mirrored from QuestResource for access without loading)
enum QuestState { UNAVAILABLE, AVAILABLE, ACTIVE, COMPLETED, FAILED }

func _ready():
	intent_detector = IntentDetectorScript.new()
	_load_quest_definitions()
	_connect_to_game_events()
	print("[QuestManager] Initialized with %d quest definitions" % quest_definitions.size())

# =============================================================================
# INITIALIZATION
# =============================================================================

func _load_quest_definitions():
	# Load all quest resources from directory
	var dir = DirAccess.open(QUEST_DIR)
	if not dir:
		print("[QuestManager] No quest directory found at %s" % QUEST_DIR)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var quest = load(QUEST_DIR + file_name)
			if quest and "quest_id" in quest and not quest.quest_id.is_empty():
				quest_definitions[quest.quest_id] = quest
				print("[QuestManager] Loaded quest: %s" % quest.quest_id)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Evaluate initial availability
	_evaluate_quest_availability()

func _connect_to_game_events():
	# Connect to EventBus signals
	if EventBus:
		# Response analysis - main hook for natural language detection
		if EventBus.has_signal("npc_response_generated"):
			EventBus.npc_response_generated.connect(_on_npc_response)

		# World flag changes
		if EventBus.has_signal("world_flag_changed"):
			EventBus.world_flag_changed.connect(_on_flag_changed)

		# Relationship changes
		EventBus.npc_relationship_changed.connect(_on_relationship_changed)

		# Memory events
		EventBus.npc_memory_stored.connect(_on_memory_stored)

		# Location events
		if EventBus.has_signal("player_entered_area"):
			EventBus.player_entered_area.connect(_on_area_entered)

# =============================================================================
# QUEST STATE MANAGEMENT
# =============================================================================

func _evaluate_quest_availability():
	for quest_id in quest_definitions:
		var quest = quest_definitions[quest_id]
		if quest.state == QuestState.UNAVAILABLE:
			if quest.can_become_available(WorldState):
				quest.state = QuestState.AVAILABLE
				available_quests[quest_id] = quest
				quest_available.emit(quest_id)
				print("[QuestManager] Quest now available: %s" % quest_id)

				# Auto-start if configured
				if quest.auto_start:
					_start_quest(quest_id)

func _start_quest(quest_id: String):
	if not available_quests.has(quest_id):
		if quest_definitions.has(quest_id):
			var quest = quest_definitions[quest_id]
			if quest.can_become_available(WorldState):
				available_quests[quest_id] = quest
			else:
				print("[QuestManager] Quest %s not available yet" % quest_id)
				return
		else:
			print("[QuestManager] Unknown quest: %s" % quest_id)
			return

	var quest = available_quests[quest_id]
	available_quests.erase(quest_id)
	quest.start()
	active_quests[quest_id] = quest

	# Also notify WorldState for legacy compatibility
	WorldState.start_quest(quest_id, {"title": quest.title})

	quest_discovered.emit(quest_id)
	print("[QuestManager] Quest started: %s - %s" % [quest_id, quest.title])

func _complete_quest(quest_id: String, ending: String = "default"):
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]
	active_quests.erase(quest_id)
	quest.complete(ending)
	completed_quests[quest_id] = quest

	# Set completion flags
	for flag in quest.completion_flags:
		WorldState.set_world_flag(flag, true)

	# Unlock dependent quests
	for unlock_id in quest.unlocks_quests:
		if quest_definitions.has(unlock_id):
			var unlock_quest = quest_definitions[unlock_id]
			if unlock_quest.can_become_available(WorldState):
				unlock_quest.state = QuestState.AVAILABLE
				available_quests[unlock_id] = unlock_quest
				quest_available.emit(unlock_id)

	# Notify WorldState for legacy compatibility
	WorldState.complete_quest(quest_id, ending)

	quest_completed.emit(quest_id, ending)
	print("[QuestManager] Quest completed: %s (ending: %s)" % [quest_id, ending])

	# Re-evaluate availability after completion
	_evaluate_quest_availability()

func _fail_quest(quest_id: String, reason: String = ""):
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]
	active_quests.erase(quest_id)
	quest.fail(reason)
	failed_quests[quest_id] = quest

	quest_failed.emit(quest_id, reason)
	print("[QuestManager] Quest failed: %s (reason: %s)" % [quest_id, reason])

func _complete_objective(quest_id: String, objective_id: String, trigger: String):
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]
	for objective in quest.objectives:
		if objective.objective_id == objective_id and not objective.is_completed:
			objective.mark_completed(trigger)
			quest_objective_completed.emit(quest_id, objective_id)
			print("[QuestManager] Objective completed: %s/%s (by %s)" % [quest_id, objective_id, trigger])

			# Check if quest is now complete
			if quest.are_required_objectives_complete():
				_complete_quest(quest_id)
			break

# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_npc_response(npc_id: String, response_data: Dictionary):
	# Use IntentDetector to analyze the response
	var analysis = intent_detector.analyze_response(response_data)

	var intents = analysis.intents
	var topics = analysis.topics
	var interaction_type = response_data.get("interaction_type", "")

	# Add interaction_type to intents for matching
	if not interaction_type.is_empty() and interaction_type not in intents:
		intents.append(interaction_type)

	# Debug logging if quest-relevant
	if analysis.quest_relevant:
		print("[QuestManager] Quest-relevant response from %s: %s" % [
			npc_id, intent_detector.get_analysis_summary(analysis)
		])

	# Check for quest discovery
	for quest_id in available_quests.keys():
		var quest = available_quests[quest_id]
		if quest.check_discovery_conditions(npc_id, intents, topics):
			_start_quest(quest_id)

	# Check for objective completion
	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		for objective in quest.get_active_objectives():
			# Check intent conditions
			if objective.check_intent_condition(interaction_type, npc_id):
				_complete_objective(quest_id, objective.objective_id, "intent:" + interaction_type)

			# Check topic conditions
			if objective.check_topics_condition(topics):
				_complete_objective(quest_id, objective.objective_id, "topic:" + str(topics))

			# Check revelation conditions
			if not analysis.revelations.is_empty():
				for revelation in analysis.revelations:
					if objective.check_intent_condition(revelation, npc_id):
						_complete_objective(quest_id, objective.objective_id, "revelation:" + revelation)

func _on_flag_changed(flag_name: String, old_value, new_value):
	# Re-evaluate availability
	_evaluate_quest_availability()

	# Check objective completion
	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		for objective in quest.get_active_objectives():
			if objective.check_flag_condition(flag_name, new_value):
				_complete_objective(quest_id, objective.objective_id, "flag:" + flag_name)

func _on_relationship_changed(event_data: Dictionary):
	# Re-evaluate availability
	_evaluate_quest_availability()

	# Extract npc_id and relationship values from event data
	var npc_id = event_data.get("npc_id", "")
	var new_dimensions = event_data.get("new_dimensions", {})

	# Check objective completion using the new trust value as primary metric
	var trust_value = new_dimensions.get("trust", 0)

	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		for objective in quest.get_active_objectives():
			if objective.check_relationship_condition(npc_id, trust_value):
				_complete_objective(quest_id, objective.objective_id, "relationship:" + npc_id)

func _on_memory_stored(npc_id: String, memory: Dictionary):
	var tags = memory.get("tags", [])
	for tag in tags:
		for quest_id in active_quests.keys():
			var quest = active_quests[quest_id]
			for objective in quest.get_active_objectives():
				if objective.check_memory_condition(tag, npc_id):
					_complete_objective(quest_id, objective.objective_id, "memory:" + tag)

func _on_area_entered(area_id: String):
	for quest_id in active_quests.keys():
		var quest = active_quests[quest_id]
		for objective in quest.get_active_objectives():
			if objective.check_location_condition(area_id):
				_complete_objective(quest_id, objective.objective_id, "location:" + area_id)

# =============================================================================
# CONTEXT INJECTION (for NPC prompts)
# =============================================================================

func get_quest_context_for_npc(npc_id: String) -> String:
	var contexts: Array[String] = []

	for quest_id in active_quests:
		var quest = active_quests[quest_id]
		var context = quest.get_context_for_npc(npc_id)
		if not context.is_empty():
			contexts.append(context)

	return "\n".join(contexts)

func get_active_quests_for_npc(npc_id: String) -> Array:
	var relevant: Array = []
	for quest_id in active_quests:
		var quest = active_quests[quest_id]
		if quest.npc_context_hints.has(npc_id) or quest.discovery_npc == npc_id:
			relevant.append(quest)
	return relevant

# =============================================================================
# PUBLIC API
# =============================================================================

func get_quest(quest_id: String):
	if quest_definitions.has(quest_id):
		return quest_definitions[quest_id]
	return null

func is_quest_available(quest_id: String) -> bool:
	return available_quests.has(quest_id)

func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return completed_quests.has(quest_id)

func is_quest_failed(quest_id: String) -> bool:
	return failed_quests.has(quest_id)

func get_all_quests() -> Dictionary:
	return quest_definitions.duplicate()

func get_available_quest_ids() -> Array:
	return available_quests.keys()

func get_active_quest_ids() -> Array:
	return active_quests.keys()

func get_completed_quest_ids() -> Array:
	return completed_quests.keys()

## Force start a quest (for debugging)
func force_start_quest(quest_id: String):
	if quest_definitions.has(quest_id):
		var quest = quest_definitions[quest_id]
		quest.state = QuestState.AVAILABLE
		available_quests[quest_id] = quest
		_start_quest(quest_id)

## Force complete a quest (for debugging)
func force_complete_quest(quest_id: String, ending: String = "debug"):
	if active_quests.has(quest_id):
		_complete_quest(quest_id, ending)
	elif quest_definitions.has(quest_id):
		# Quest not active, force it through
		var quest = quest_definitions[quest_id]
		quest.start()
		active_quests[quest_id] = quest
		_complete_quest(quest_id, ending)

## Force complete an objective (for debugging)
func force_complete_objective(quest_id: String, objective_id: String):
	_complete_objective(quest_id, objective_id, "debug")

## Reset a quest (for debugging)
func reset_quest(quest_id: String):
	if quest_definitions.has(quest_id):
		var quest = quest_definitions[quest_id]

		# Remove from all state dictionaries
		available_quests.erase(quest_id)
		active_quests.erase(quest_id)
		completed_quests.erase(quest_id)
		failed_quests.erase(quest_id)

		# Reset the quest itself
		quest.reset()

		# Re-evaluate availability
		_evaluate_quest_availability()
		print("[QuestManager] Quest reset: %s" % quest_id)

## Register a quest programmatically (for dynamic quests)
func register_quest(quest):
	if quest.quest_id.is_empty():
		push_error("[QuestManager] Cannot register quest with empty ID")
		return

	quest_definitions[quest.quest_id] = quest
	if quest.can_become_available(WorldState):
		quest.state = QuestState.AVAILABLE
		available_quests[quest.quest_id] = quest
		quest_available.emit(quest.quest_id)

# =============================================================================
# SAVE/LOAD
# =============================================================================

func get_save_data() -> Dictionary:
	var data = {
		"available": [],
		"active": {},
		"completed": {},
		"failed": {}
	}

	for quest_id in available_quests:
		data.available.append(quest_id)

	for quest_id in active_quests:
		data.active[quest_id] = active_quests[quest_id].get_save_data()

	for quest_id in completed_quests:
		data.completed[quest_id] = completed_quests[quest_id].get_save_data()

	for quest_id in failed_quests:
		data.failed[quest_id] = failed_quests[quest_id].get_save_data()

	return data

func load_save_data(data: Dictionary):
	# Clear current state
	available_quests.clear()
	active_quests.clear()
	completed_quests.clear()
	failed_quests.clear()

	# Restore available
	for quest_id in data.get("available", []):
		if quest_definitions.has(quest_id):
			var quest = quest_definitions[quest_id]
			quest.state = QuestState.AVAILABLE
			available_quests[quest_id] = quest

	# Restore active
	for quest_id in data.get("active", {}):
		if quest_definitions.has(quest_id):
			var quest = quest_definitions[quest_id]
			quest.load_save_data(data.active[quest_id])
			quest.state = QuestState.ACTIVE
			active_quests[quest_id] = quest

	# Restore completed
	for quest_id in data.get("completed", {}):
		if quest_definitions.has(quest_id):
			var quest = quest_definitions[quest_id]
			quest.load_save_data(data.completed[quest_id])
			quest.state = QuestState.COMPLETED
			completed_quests[quest_id] = quest

	# Restore failed
	for quest_id in data.get("failed", {}):
		if quest_definitions.has(quest_id):
			var quest = quest_definitions[quest_id]
			quest.load_save_data(data.failed[quest_id])
			quest.state = QuestState.FAILED
			failed_quests[quest_id] = quest

	print("[QuestManager] Loaded: %d available, %d active, %d completed, %d failed" % [
		available_quests.size(), active_quests.size(), completed_quests.size(), failed_quests.size()
	])
