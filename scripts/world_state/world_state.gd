extends Node
# WorldState - Manages global game state, faction relationships, and consequence tracking

var faction_reputations := {}
var npc_relationships := {}
var active_quests := []
var completed_quests := []
var world_flags := {}
var npc_states := {}  # Stores NPC state (alive/dead, location, etc.)

const SAVE_PATH = "user://game_save.json"

func _ready():
	print("WorldState initialized")
	EventBus.player_action.connect(_on_player_action)
	EventBus.faction_reputation_changed.connect(_on_faction_reputation_changed)
	load_game()  # Auto-load on startup

func _on_player_action(action_data: Dictionary):
	# Process player actions and update world state
	pass

func _on_faction_reputation_changed(faction_id: String, old_value: float, new_value: float):
	faction_reputations[faction_id] = new_value

func get_faction_reputation(faction_id: String) -> float:
	return faction_reputations.get(faction_id, 0.0)

func get_npc_relationship(npc_id: String) -> float:
	return npc_relationships.get(npc_id, 0.0)

func set_world_flag(flag_name: String, value: bool):
	var old_value = world_flags.get(flag_name, false)
	world_flags[flag_name] = value
	if old_value != value:
		EventBus.world_flag_changed.emit(flag_name, old_value, value)

func get_world_flag(flag_name: String) -> bool:
	return world_flags.get(flag_name, false)

## Bulk getters for NPC context building
func get_flags() -> Dictionary:
	return world_flags.duplicate()

func get_active_quests() -> Array:
	return active_quests.duplicate()

## Quest Management
func start_quest(quest_id: String, quest_data: Dictionary = {}):
	if quest_id not in active_quests:
		active_quests.append(quest_id)
		EventBus.quest_started.emit(quest_id, quest_data)
		print("[WorldState] Quest started: %s" % quest_id)

func complete_quest(quest_id: String, outcome: String = "success"):
	if quest_id in active_quests:
		active_quests.erase(quest_id)
		completed_quests.append(quest_id)
		EventBus.quest_completed.emit(quest_id, "", outcome)
		print("[WorldState] Quest completed: %s (%s)" % [quest_id, outcome])

func is_quest_active(quest_id: String) -> bool:
	return quest_id in active_quests

func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

## NPC State Management
func register_npc_death(npc_id: String, death_data: Dictionary):
	npc_states[npc_id] = {
		"is_alive": false,
		"death_cause": death_data.get("cause", "unknown"),
		"killed_by": death_data.get("killed_by", "unknown"),
		"death_timestamp": death_data.get("timestamp", Time.get_unix_time_from_system())
	}
	save_game()  # Auto-save on NPC death
	print("[WorldState] NPC death registered: %s" % npc_id)

func is_npc_alive(npc_id: String) -> bool:
	if npc_id in npc_states:
		return npc_states[npc_id].get("is_alive", true)
	return true  # NPCs are alive by default if not in state

func get_npc_state(npc_id: String) -> Dictionary:
	return npc_states.get(npc_id, {"is_alive": true})

func get_relevant_state(npc_id: String) -> Dictionary:
	# Returns world state relevant to a specific NPC
	return {
		"npc_relationship": get_npc_relationship(npc_id),
		"world_flags": world_flags,
		"active_quests": active_quests
	}

func save() -> Dictionary:
	return {
		"faction_reputations": faction_reputations,
		"npc_relationships": npc_relationships,
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"world_flags": world_flags,
		"npc_states": npc_states
	}

func load_from_dict(data: Dictionary):
	faction_reputations = data.get("faction_reputations", {})
	npc_relationships = data.get("npc_relationships", {})
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	world_flags = data.get("world_flags", {})
	npc_states = data.get("npc_states", {})

## Save game to disk
func save_game():
	var save_data = save()
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("[WorldState] Game saved to: %s" % SAVE_PATH)
	else:
		push_error("[WorldState] Failed to save game")

## Load game from disk
func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("[WorldState] No save file found, starting fresh")
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_str)
		
		if parse_result == OK:
			load_from_dict(json.data)
			print("[WorldState] Game loaded from: %s" % SAVE_PATH)
			print("[WorldState] Loaded %d NPC states" % npc_states.size())
		else:
			push_error("[WorldState] Failed to parse save file")
	else:
		push_error("[WorldState] Failed to open save file")

func load_state(data: Dictionary):
	faction_reputations = data.get("faction_reputations", {})
	npc_relationships = data.get("npc_relationships", {})
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	world_flags = data.get("world_flags", {})
