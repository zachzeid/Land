extends Node
# EventBus - Central event system for all game events
# Player actions, world events, and NPC reactions flow through here

# Player action signals
signal player_action(action_data: Dictionary)
signal dialogue_choice_made(npc_id: String, choice: String)
signal item_interacted(item_id: String, action: String)

# Quest signals
signal quest_started(quest_id: String, quest_data: Dictionary)
signal quest_completed(quest_id: String, npc_id: String, outcome: String)
signal quest_objective_completed(quest_id: String, objective_id: String)
signal quest_discovered(quest_id: String)
signal quest_failed(quest_id: String, reason: String)

# World event signals
signal world_event(event_data: Dictionary)
signal world_flag_changed(flag_name: String, old_value, new_value)
signal faction_reputation_changed(faction_id: String, old_value: float, new_value: float)
signal npc_relationship_changed(event_data: Dictionary)

# NPC signals
signal npc_witnessed_event(npc_id: String, event_data: Dictionary)
signal npc_memory_stored(npc_id: String, memory: Dictionary)
signal npc_response_generated(npc_id: String, response_data: Dictionary)

# Location signals
signal player_entered_area(area_id: String)
signal player_exited_area(area_id: String)

# NPC Agent signals (autonomous behavior)
signal npc_action_taken(npc_id: String, action_data: Dictionary)
signal npc_moved(npc_id: String, from_location: String, to_location: String)
signal npc_communicated(from_npc: String, to_npc: String, info_packet: Dictionary)
signal npc_goal_changed(npc_id: String, old_goal: String, new_goal: String)

# Time signals
signal time_period_changed(new_period: String, old_period: String)

func _ready():
	print("EventBus initialized")
