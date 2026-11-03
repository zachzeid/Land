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

# Game clock and travel (WorldState owns both)
signal time_advanced(minutes: int, total_minutes: int, reason: String)
signal npc_travel_started(npc_id: String, from_location: String, to_location: String, arrive_minute: int)
signal npc_arrived(npc_id: String, location: String)
## A world.json calendar fixed point was reached and its flag set (WorldState; world-caused)
signal calendar_flag_fired(flag_name: String, at_minute: int)

func _ready():
	print("EventBus initialized")
