extends Node
# WorldState - Manages global game state, faction relationships, and consequence tracking

var faction_reputations := {}
var npc_relationships := {}
var active_quests := []
var completed_quests := []
var world_flags := {}
var npc_states := {}  # Stores NPC state (alive/dead, location, etc.)
var event_propagation_state := {}  # Loaded EventPropagator state (it autoloads after us)
var storyline_state := {}  # Loaded StorylineDirector state (it autoloads after us)
var generics_state := {}  # Loaded generic NPC state (DynamicNPCRegistry.generics autoloads after us)

const SAVE_PATH = "user://game_save.json"

## Game clock: minutes since midnight of day 1. A new game starts at world.json calendar.start
## (The Tithe Night: day 1, 20:00, the drawing). START_MINUTE is the fallback when world.json has none
const START_MINUTE = 20 * 60
const MINUTES_PER_DAY = 24 * 60
const IDLE_CLOCK_SECONDS = 60.0  # real seconds per idle clock tick (Config.game_minutes_per_real_minute)

var game_minutes: int = START_MINUTE
var start_minute: int = START_MINUTE   # world.json calendar.start, as minutes since day 1 00:00

## Calendar fixed points (world.json "calendar.flags"): the world sets each flag true when the clock
## reaches it, in order and exactly once, whatever the player does. World-caused: no witnesses
var _calendar: Array = []              # [{"flag", "minute", "description"}] sorted by minute
var _calendar_fired: Dictionary = {}   # flag -> game minute it fired (saved)
var _world_change_depth: int = 0       # > 0 while the world itself (the calendar) is setting flags
var _firing_calendar: bool = false
var loaded_from_save: bool = false     # true when load_game() restored a save file at startup
var _idle_clock: Timer = null
var _idle_rate: float = 1.0      # game minutes per idle tick (0 = the clock only moves with travel)
var _idle_carry: float = 0.0

func _ready():
	print("WorldState initialized")
	EventBus.player_action.connect(_on_player_action)
	EventBus.faction_reputation_changed.connect(_on_faction_reputation_changed)
	load_calendar()
	game_minutes = start_minute
	load_game()  # Auto-load on startup
	# A save made before a fixed point passed fires it once everyone is listening
	call_deferred("fire_due_calendar_flags")
	# Unpaused real time nudges the clock, so a short walk across the village still ends
	_idle_clock = Timer.new()
	_idle_clock.wait_time = IDLE_CLOCK_SECONDS
	_idle_clock.process_mode = Node.PROCESS_MODE_PAUSABLE
	_idle_clock.timeout.connect(_on_idle_clock)
	add_child(_idle_clock)
	_idle_clock.start()
	call_deferred("_read_clock_config")

func _read_clock_config():
	var config = get_node_or_null("/root/Config")
	if config and "game_minutes_per_real_minute" in config:
		set_idle_clock_rate(float(config.game_minutes_per_real_minute))

## Game minutes added per real minute of unpaused play (0 stops the idle clock)
func set_idle_clock_rate(game_minutes_per_real_minute: float) -> void:
	_idle_rate = max(game_minutes_per_real_minute, 0.0)
	if _idle_clock:
		_idle_clock.paused = _idle_rate <= 0.0

func _on_idle_clock():
	_idle_carry += _idle_rate
	var whole = int(_idle_carry)
	if whole > 0:
		_idle_carry -= whole
		advance_time(whole, "idle")

# =============================================================================
# GAME CLOCK
# =============================================================================

## Move the game clock forward. Travel, walking exits and the idle clock call this
## NPCs whose journeys end meanwhile arrive (EventBus.npc_arrived), then EventBus.time_advanced fires
func advance_time(minutes: int, reason: String = "") -> void:
	if minutes <= 0:
		return
	game_minutes += minutes
	_complete_arrivals()
	fire_due_calendar_flags()
	EventBus.time_advanced.emit(minutes, game_minutes, reason)

## No save file was restored at startup: the opening (the Tithe drawing) plays
func is_new_game() -> bool:
	return not loaded_from_save

func get_game_minutes() -> int:
	return game_minutes

## Day number, starting at 1
func get_day() -> int:
	return floori(game_minutes / float(MINUTES_PER_DAY)) + 1

## Hour of the day, 0-23
func get_hour() -> int:
	return floori((game_minutes % MINUTES_PER_DAY) / 60.0)

## Minute of the hour, 0-59
func get_minute() -> int:
	return game_minutes % 60

## "Day 2, 14:05"
func get_time_string() -> String:
	return "Day %d, %02d:%02d" % [get_day(), get_hour(), get_minute()]

## "morning" | "afternoon" | "evening" | "night"
func get_time_of_day() -> String:
	var hour = get_hour()
	if hour >= 5 and hour < 12:
		return "morning"
	if hour >= 12 and hour < 17:
		return "afternoon"
	if hour >= 17 and hour < 21:
		return "evening"
	return "night"

# =============================================================================
# CALENDAR (world.json "calendar": start + fixed-point flags)
# =============================================================================

## Read world.json calendar from WorldRegistry (or a dict, for tests). Registers flag descriptions
func load_calendar(calendar = null) -> void:
	if calendar == null:
		var registry = get_node_or_null("/root/WorldRegistry")
		calendar = registry.get_calendar() if registry and registry.has_method("get_calendar") else {}
	if not calendar is Dictionary:
		calendar = {}
	var start = calendar.get("start", {})
	start_minute = _calendar_minute(start) if start is Dictionary and not start.is_empty() else START_MINUTE
	_calendar.clear()
	var descriptions: Dictionary = {}
	var flags = calendar.get("flags", {})
	if flags is Dictionary:
		for flag_name in flags:
			var entry = flags[flag_name]
			if not entry is Dictionary:
				continue
			_calendar.append({"flag": str(flag_name), "minute": _calendar_minute(entry), "description": str(entry.get("description", ""))})
			descriptions[str(flag_name)] = str(entry.get("description", ""))
	# Stable by minute; ties keep world.json order
	var order: Array = []
	for i in _calendar.size():
		order.append([_calendar[i].minute, i])
	order.sort()
	var sorted: Array = []
	for pair in order:
		sorted.append(_calendar[pair[1]])
	_calendar = sorted
	StoryFlags.register_calendar_flags(descriptions)

## {"day", "hour", "minute"} -> minutes since day 1, 00:00
func _calendar_minute(entry: Dictionary) -> int:
	return (maxi(int(entry.get("day", 1)), 1) - 1) * MINUTES_PER_DAY + int(entry.get("hour", 0)) * 60 + int(entry.get("minute", 0))

## The fixed points in order: [{"flag", "minute", "description", "fired"}]
func get_calendar() -> Array:
	var result: Array = []
	for entry in _calendar:
		result.append(entry.merged({"fired": _calendar_fired.has(entry.flag)}))
	return result

func is_calendar_flag(flag_name: String) -> bool:
	for entry in _calendar:
		if entry.flag == flag_name:
			return true
	return false

func has_calendar_fired(flag_name: String) -> bool:
	return _calendar_fired.has(flag_name)

## Minute of a day's morning (06:00, when the tn_day_N flags fall)
func get_morning_minute(day: int) -> int:
	return (maxi(day, 1) - 1) * MINUTES_PER_DAY + 6 * 60

## Set every fixed point the clock has reached and that has not fired yet, earliest first, once each
## Safe to re-enter (a listener that moves the clock): the outer loop picks up anything newly due
func fire_due_calendar_flags() -> Array:
	var fired: Array = []
	if _firing_calendar:
		return fired
	_firing_calendar = true
	for entry in _calendar:
		if entry.minute > game_minutes:
			break
		if _calendar_fired.has(entry.flag):
			continue
		_calendar_fired[entry.flag] = entry.minute
		fired.append(entry.flag)
		print("[WorldState] Calendar: %s (%s)" % [entry.flag, get_time_string()])
		_world_change_depth += 1
		set_world_flag(entry.flag, true)
		_world_change_depth -= 1
		EventBus.calendar_flag_fired.emit(entry.flag, entry.minute)
	_firing_calendar = false
	return fired

## True while the world itself (a calendar fixed point) is changing a flag. EventPropagator and
## StorylineDirector ask: nobody witnesses such a change, though gossip rules still apply
func is_world_change() -> bool:
	return _world_change_depth > 0

## Forget which fixed points fired (tests and new games); flags already set stay as they are
func reset_calendar(minutes: int = -1) -> void:
	_calendar_fired.clear()
	if minutes >= 0:
		game_minutes = minutes

# =============================================================================
# NPC LOCATION AND TRAVEL (npc_states[npc_id].location / .travel)
# =============================================================================

## Where an NPC is, or is headed while travelling: its recorded location, else its world.json home
func get_npc_location(npc_id: String) -> String:
	var location = str(npc_states.get(npc_id, {}).get("location", ""))
	if location != "":
		return location
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry.get_npc_home(registry.get_npc_key(npc_id)) if registry else ""

## Record where an NPC is now (no travel time; cancels any journey)
func set_npc_location(npc_id: String, location: String) -> void:
	var state: Dictionary = npc_states.get(npc_id, {"is_alive": true})
	state["location"] = location
	state.erase("travel")
	_note_visited(state, location)
	npc_states[npc_id] = state

## Send an NPC on a journey. It is absent everywhere until the clock reaches the arrival minute
## Returns the arrival minute
func start_npc_travel(npc_id: String, to_location: String, minutes: int, from_location: String = "") -> int:
	if from_location == "":
		from_location = get_npc_location(npc_id)
	var state: Dictionary = npc_states.get(npc_id, {"is_alive": true})
	state["location"] = to_location
	var arrive = game_minutes + maxi(minutes, 0)
	if minutes > 0:
		state["travel"] = {"from": from_location, "to": to_location, "depart": game_minutes, "arrive": arrive}
	else:
		state.erase("travel")
		_note_visited(state, to_location)
	npc_states[npc_id] = state
	EventBus.npc_travel_started.emit(npc_id, from_location, to_location, arrive)
	if minutes <= 0:
		EventBus.npc_arrived.emit(npc_id, to_location)
	return arrive

func is_npc_travelling(npc_id: String) -> bool:
	return npc_states.get(npc_id, {}).has("travel")

## {"from", "to", "depart", "arrive"} while travelling, else {}
func get_npc_travel(npc_id: String) -> Dictionary:
	return npc_states.get(npc_id, {}).get("travel", {}).duplicate()

func get_travelling_npcs() -> Array:
	var result: Array = []
	for npc_id in npc_states:
		if npc_states[npc_id] is Dictionary and npc_states[npc_id].has("travel"):
			result.append(npc_id)
	return result

## Regions an NPC has been in (its home region always counts)
func has_npc_visited_region(npc_id: String, region_id: String) -> bool:
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry and registry.get_region(registry.get_npc_home(registry.get_npc_key(npc_id))) == region_id:
		return true
	return region_id in npc_states.get(npc_id, {}).get("visited_regions", [])

func _complete_arrivals() -> void:
	for npc_id in get_travelling_npcs():
		var state: Dictionary = npc_states[npc_id]
		if int(state.travel.get("arrive", 0)) > game_minutes:
			continue
		var location = str(state.travel.get("to", state.get("location", "")))
		state.erase("travel")
		state["location"] = location
		_note_visited(state, location)
		print("[WorldState] %s arrived at %s (%s)" % [npc_id, location, get_time_string()])
		EventBus.npc_arrived.emit(npc_id, location)

func _note_visited(state: Dictionary, location: String) -> void:
	var registry = get_node_or_null("/root/WorldRegistry")
	var region = registry.get_region(location) if registry else ""
	if region == "":
		return
	var visited: Array = state.get("visited_regions", [])
	if region not in visited:
		visited.append(region)
	state["visited_regions"] = visited

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
	# Merge so other state (e.g. a storyline's move_npc location) survives
	var state: Dictionary = npc_states.get(npc_id, {})
	state.merge({
		"is_alive": false,
		"death_cause": death_data.get("cause", "unknown"),
		"killed_by": death_data.get("killed_by", "unknown"),
		"death_timestamp": death_data.get("timestamp", Time.get_unix_time_from_system())
	}, true)
	npc_states[npc_id] = state
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
		"npc_states": npc_states,
		"game_minutes": game_minutes,
		"calendar_fired": _calendar_fired.duplicate(),
		"event_propagation": _get_event_propagation_state(),
		"storylines": _get_storyline_state(),
		"generics": _get_generics_state()
	}

## Generic instances, layers, tiers, histories, soul texts and every NPC's feelings + last contact
func _get_generics_state() -> Dictionary:
	var generics = _generics()
	return generics.save() if generics else generics_state

func _apply_generics_state(data: Dictionary):
	generics_state = data.get("generics", {})
	var generics = _generics()
	if generics and not generics_state.is_empty():
		generics.load_from_dict(generics_state)  # re-registers names and souls

func _generics() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry and registry.generics else null

func _get_storyline_state() -> Dictionary:
	var director = get_node_or_null("/root/StorylineDirector")
	return director.save() if director else storyline_state

func _apply_storyline_state(data: Dictionary):
	storyline_state = data.get("storylines", {})
	var director = get_node_or_null("/root/StorylineDirector")
	if director:
		director.load_from_dict(storyline_state)

func _get_event_propagation_state() -> Dictionary:
	var propagator = get_node_or_null("/root/EventPropagator")
	return propagator.save() if propagator else event_propagation_state

func _apply_event_propagation_state(data: Dictionary):
	event_propagation_state = data.get("event_propagation", {})
	var propagator = get_node_or_null("/root/EventPropagator")
	if propagator:
		propagator.load_from_dict(event_propagation_state)

func load_from_dict(data: Dictionary):
	faction_reputations = data.get("faction_reputations", {})
	npc_relationships = data.get("npc_relationships", {})
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	world_flags = data.get("world_flags", {})
	npc_states = data.get("npc_states", {})
	game_minutes = int(data.get("game_minutes", start_minute))
	_load_calendar_fired(data)
	_apply_event_propagation_state(data)
	_apply_storyline_state(data)
	_apply_generics_state(data)
	_complete_arrivals()

## Which fixed points already fired. Saves from before the calendar existed carry no record:
## a fixed point whose flag is already true counts as fired; one still due fires on the next check
func _load_calendar_fired(data: Dictionary) -> void:
	_calendar_fired.clear()
	var saved = data.get("calendar_fired", null)
	if saved is Dictionary:
		for flag_name in saved:
			_calendar_fired[str(flag_name)] = int(saved[flag_name])
	elif saved is Array:
		for flag_name in saved:
			_calendar_fired[str(flag_name)] = 0
	for entry in _calendar:
		if not _calendar_fired.has(entry.flag) and world_flags.get(entry.flag, false) == true:
			_calendar_fired[entry.flag] = entry.minute

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
		
		if parse_result == OK and json.data is Dictionary:
			load_from_dict(json.data)
			loaded_from_save = true
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
	game_minutes = int(data.get("game_minutes", game_minutes))
	_load_calendar_fired(data)
	_apply_event_propagation_state(data)
	_apply_storyline_state(data)
	_apply_generics_state(data)
