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
var quest_state := {}  # Loaded QuestManager state (it autoloads after us)
## Player systems (docs/PLAYER_SYSTEMS.md §8): each autoload's save(), restored once they are ready
const PLAYER_SYSTEMS = ["PlayerStats", "Inventory", "Crafting", "Combat", "WorldPhysics", "Puzzles", "Taverns"]
var player_systems_state := {}
var player_location := ""  # Where the player stood when the game was saved ("" = a new game)

const SAVE_PATH = "user://game_save.json"
const SAVE_BACKUP_PATH = "user://game_save.bak.json"  # the previous good save, kept in case a write is cut short
var save_path: String = SAVE_PATH            # tests point these at their own files
var save_backup_path: String = SAVE_BACKUP_PATH
signal game_saved(path: String, reason: String)

## Autosave: what the player does is remembered, so the world saves as it goes, not only on a death
## Requests are coalesced (one write per AUTOSAVE_DELAY_SECONDS) and the idle clock saves every
## AUTOSAVE_IDLE_SECONDS of unpaused play. Off in headless runs (tests, boot checks) unless --autosave
const AUTOSAVE_DELAY_SECONDS = 2.0
const AUTOSAVE_IDLE_SECONDS = 300.0
var autosave_enabled: bool = true
var _autosave_timer: Timer = null
var _idle_save_timer: Timer = null
var _save_reason: String = ""

## Game clock: minutes since midnight of day 1. A new game starts at world.json calendar.start
## (The Tithe Night: day 1, 20:00, the drawing). START_MINUTE is the fallback when world.json has none
const START_MINUTE = 20 * 60
const MINUTES_PER_DAY = 24 * 60
const IDLE_CLOCK_SECONDS = 60.0  # real seconds per idle clock tick (Config.game_minutes_per_real_minute)

var game_minutes: int = START_MINUTE
var start_minute: int = START_MINUTE   # world.json calendar.start, as minutes since day 1 00:00

## Calendar fixed points (world.json "calendar.flags"): the world sets each flag true when the clock
## reaches it, in order and exactly once, whatever the player does. World-caused: no witnesses
var _calendar: Array = []              # [{"flag", "base_minute", "description", "movable", "shift_rules"}] world.json order
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
	_read_save_path_arg()
	load_game()  # Auto-load on startup
	_setup_autosave()
	# QuestManager and SceneManager autoload after us: restore their part once everyone is ready
	call_deferred("_apply_late_save_state")
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
# Movable fixed points (docs/WORLD_SCHEMA.md §11): a point with "movable": true can be delayed
# (negative days bring it earlier) or cancelled, by its world.json shift_rules (applied once each,
# when the rule's `when` flag turns true; StorylineDirector calls apply_shift_rules) or by the
# shift_fixed_point effect (StorylineDirector.shift_fixed_point). A point that fired never moves.
# A cancelled point never fires; <point>_cancelled turns true instead (a world change, like a firing)
# =============================================================================

## A fixed point moved: info = {"point", "action": "delay"|"cancel", "days", "from", "to", "reason", "actor", "rule"}
signal calendar_point_shifted(point: String, info: Dictionary)
## A movable point's eve passed (<point>_eve, 24 game hours before the point's current time)
signal calendar_eve_passed(point: String, eve_flag: String, at_minute: int)
## An advance was refused whole by the world-only cap (info: point, days asked, reason, actor, rule)
signal calendar_shift_clamped(point: String, info: Dictionary)

## Without the player in their causal chain, shifts may bring a point at most this many days earlier
## in total (delays and cancels are not capped; the player's own advances keep only the -3 per shift clamp)
const WORLD_ADVANCE_CAP_DAYS = -1

const EVE_MINUTES = 24 * 60
var _eves_fired: Dictionary = {}       # point -> minute its <point>_eve fell (saved)

const MAX_RULE_SHIFT_DAYS = 30
var _calendar_shifts: Dictionary = {}  # point -> {"days": int, "cancelled": bool, "rules_applied": [int], "history": [...]} (saved)

## Read world.json calendar from WorldRegistry (or a dict, for tests). Registers flag descriptions
## (each point's flag, and <point>_cancelled for movable points)
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
			var rules: Array = []
			for rule in entry.get("shift_rules", []) if entry.get("shift_rules") is Array else []:
				if rule is Dictionary and str(rule.get("when", "")) != "" and str(rule.get("action", "")) in ["delay", "cancel"]:
					rules.append({"when": str(rule.when), "action": str(rule.action),
						"days": clampi(int(rule.get("days", 0)), -MAX_RULE_SHIFT_DAYS, MAX_RULE_SHIFT_DAYS), "reason": str(rule.get("reason", ""))})
			var description = str(entry.get("description", ""))
			var movable = entry.get("movable", false) == true
			descriptions[str(flag_name)] = description
			_calendar.append({"flag": str(flag_name), "base_minute": _calendar_minute(entry), "description": description,
				"movable": movable, "shift_rules": rules})
	refresh_calendar_descriptions()

## {"day", "hour", "minute"} -> minutes since day 1, 00:00
func _calendar_minute(entry: Dictionary) -> int:
	return (maxi(int(entry.get("day", 1)), 1) - 1) * MINUTES_PER_DAY + int(entry.get("hour", 0)) * 60 + int(entry.get("minute", 0))

## The flag a cancelled point sets instead of firing
func cancelled_flag(point: String) -> String:
	return point + "_cancelled"

## The flag set 24 game hours before a movable point's current time (it moves with the point)
func eve_flag(point: String) -> String:
	return point + "_eve"

## <point>_cancelled / <point>_eve of a movable point: set only by the calendar, never by an effect
func is_derived_calendar_flag(flag_name: String) -> bool:
	for entry in _calendar:
		if entry.movable and (flag_name == cancelled_flag(entry.flag) or flag_name == eve_flag(entry.flag)):
			return true
	return false

func _eve_description(description: String) -> String:
	var d = description.strip_edges().trim_suffix(".")
	# Read as canon by NPCs, so phrase it as what people knew that day, not as a timestamp
	return "The eve came; within a day, this would come to pass: %s." % d if d != "" else "The eve of an appointed hour came."

## Register every calendar flag's canon text with StoryFlags: each point, and for movable points
## <point>_cancelled (the reason it was called off, once it was) and <point>_eve. A derived flag a
## storyline declares itself keeps the storyline's text (it is not registered as a calendar flag then)
## StorylineDirector calls this again after loading storylines
func refresh_calendar_descriptions() -> void:
	var descriptions: Dictionary = {}
	for entry in _calendar:
		descriptions[entry.flag] = entry.description
		if not entry.movable:
			continue
		var why = ""
		for item in _calendar_shifts.get(entry.flag, {}).get("history", []):
			if item is Dictionary and str(item.get("action", "")) == "cancel":
				why = str(item.get("reason", ""))
		for derived in [[cancelled_flag(entry.flag), _cancelled_description(entry.description, why)], [eve_flag(entry.flag), _eve_description(entry.description)]]:
			if not StoryFlags._registered_descriptions.has(derived[0]):
				descriptions[derived[0]] = derived[1]
	StoryFlags.register_calendar_flags(descriptions)

func _cancelled_description(description: String, reason: String) -> String:
	if reason.strip_edges() != "":
		return reason.strip_edges()
	return "It never came to pass: %s." % description.strip_edges().trim_suffix(".") if description.strip_edges() != "" else "An appointed hour was called off and never came."

## When a point falls now, shifts included
func _effective_minute(entry: Dictionary) -> int:
	return int(entry.base_minute) + int(_calendar_shifts.get(entry.flag, {}).get("days", 0)) * MINUTES_PER_DAY

func _is_cancelled(point: String) -> bool:
	return _calendar_shifts.get(point, {}).get("cancelled", false) == true

## The fixed points in clock order (shifts included; ties keep world.json order):
## [{"flag", "minute" (when it falls now), "base_minute" (world.json), "shift_days", "cancelled",
##   "movable", "fired", "description", "shifts": [history]}]
func get_calendar() -> Array:
	var result: Array = []
	for entry in _sorted_calendar():
		var shift: Dictionary = _calendar_shifts.get(entry.flag, {})
		result.append({"flag": entry.flag, "minute": _effective_minute(entry), "base_minute": int(entry.base_minute),
			"shift_days": int(shift.get("days", 0)), "cancelled": shift.get("cancelled", false) == true,
			"movable": entry.movable, "fired": _calendar_fired.has(entry.flag), "description": entry.description,
			"shifts": shift.get("history", []).duplicate(true)})
	return result

func _sorted_calendar() -> Array:
	var order: Array = []
	for i in _calendar.size():
		order.append([_effective_minute(_calendar[i]), i])
	order.sort()
	var sorted: Array = []
	for pair in order:
		sorted.append(_calendar[pair[1]])
	return sorted

func _calendar_entry(point: String) -> Dictionary:
	for entry in _calendar:
		if entry.flag == point:
			return entry
	return {}

## One point as get_calendar() reports it ({} when unknown)
func get_calendar_point(point: String) -> Dictionary:
	for entry in get_calendar():
		if entry.flag == point:
			return entry
	return {}

func is_calendar_flag(flag_name: String) -> bool:
	return not _calendar_entry(flag_name).is_empty()

func is_movable_point(point: String) -> bool:
	return _calendar_entry(point).get("movable", false) == true

func is_point_cancelled(point: String) -> bool:
	return _is_cancelled(point)

func has_calendar_fired(flag_name: String) -> bool:
	return _calendar_fired.has(flag_name)

## Every point that moved: point -> {"days", "cancelled", "rules_applied", "history"}
func get_calendar_shifts() -> Dictionary:
	return _calendar_shifts.duplicate(true)

## Minute of a day's morning (06:00, when the tn_day_N flags fall)
func get_morning_minute(day: int) -> int:
	return (maxi(day, 1) - 1) * MINUTES_PER_DAY + 6 * 60

## Why a point cannot move now ("" when it can)
func get_shift_denial(point: String) -> String:
	var entry = _calendar_entry(point)
	if entry.is_empty():
		return "'%s' is not a calendar fixed point" % point
	if entry.movable != true:
		return "'%s' is a fixed point that cannot move" % point
	if _calendar_fired.has(point):
		return "'%s' has already come and gone" % point
	if _is_cancelled(point):
		return "'%s' was already called off" % point
	return ""

## Move a point: days (+ later, - earlier) or cancel. Use StorylineDirector.shift_fixed_point for
## gameplay (it checks, chronicles and makes it canon); this is the calendar mechanics only
## player_caused: the player is in the shift's causal chain. Otherwise advances (negative days) are
## capped in total at WORLD_ADVANCE_CAP_DAYS per point: the excess is clamped ("clamped_from" says
## what was asked) and an advance with nothing left is refused (calendar_shift_clamped)
## Returns {"ok", "reason", "point", "action", "days", "from", "to", "player_caused", "clamped_from"}
func shift_calendar_point(point: String, days: int, cancel: bool = false, reason: String = "", actor: String = "", rule: int = -1, player_caused: bool = false) -> Dictionary:
	var result = {"ok": false, "reason": get_shift_denial(point), "point": point, "action": "cancel" if cancel else "delay", "days": 0, "from": -1, "to": -1}
	if result.reason != "":
		return result
	if not cancel and days == 0:
		result.reason = "a shift of 0 days moves nothing"
		return result
	var entry = _calendar_entry(point)
	var shift: Dictionary = _calendar_shifts.get(point, {"days": 0, "cancelled": false, "rules_applied": [], "history": []})
	result["player_caused"] = player_caused
	result["clamped_from"] = 0
	if not cancel and days < 0 and not player_caused:
		var used = int(shift.get("world_advance", 0))
		var allowed = maxi(days, WORLD_ADVANCE_CAP_DAYS - used)
		if allowed >= 0:
			result.reason = "clamped: without the player, %s comes at most %d day early in all (already %d)" % [point, -WORLD_ADVANCE_CAP_DAYS, -used]
			print("[WorldState] Calendar: %s advance %+d refused (%s)" % [point, days, result.reason])
			calendar_shift_clamped.emit(point, {"point": point, "days": days, "reason": reason, "clamp": result.reason, "actor": actor, "rule": rule})
			return result
		if allowed != days:
			result.clamped_from = days
			days = allowed
		shift["world_advance"] = used + days
	elif not cancel and days < 0:
		shift["player_advance"] = int(shift.get("player_advance", 0)) + days
	result.from = _effective_minute(entry)
	if cancel:
		shift["cancelled"] = true
	else:
		shift["days"] = int(shift.get("days", 0)) + days
		result.days = days
	shift["history"].append({"action": result.action, "days": days if not cancel else 0, "reason": reason, "actor": actor,
		"rule": rule, "at": game_minutes, "player_caused": player_caused, "clamped_from": result.clamped_from})
	_calendar_shifts[point] = shift
	result.to = -1 if cancel else _effective_minute(entry)
	result.ok = true
	print("[WorldState] Calendar: %s %s (%s)" % [point, "cancelled" if cancel else "%+d day(s), now %s" % [days, _minute_string(result.to)], reason])
	if cancel:
		refresh_calendar_descriptions()
		_world_change_depth += 1
		set_world_flag(cancelled_flag(point), true)
		_world_change_depth -= 1
	calendar_point_shifted.emit(point, result.merged({"reason": reason, "actor": actor, "rule": rule}, true))
	if not cancel:
		fire_due_calendar_flags()  # brought earlier than now: it falls at once
	return result

## Apply every shift rule whose `when` flag is true, once each, to points that have not fired or been
## cancelled. turned_true limits it to rules on that flag ("" checks every rule). Returns the shifts made
## player_chain: flag -> true when the player is in the causal chain of its turning true (the Director's
## tracking); a rule shift is player-caused when its `when` flag is
func apply_shift_rules(turned_true: String = "", player_chain: Dictionary = {}) -> Array:
	var made: Array = []
	for entry in _calendar:
		if entry.movable != true:
			continue
		for i in entry.shift_rules.size():
			if get_shift_denial(entry.flag) != "":
				break
			var rule: Dictionary = entry.shift_rules[i]
			if turned_true != "" and rule.when != turned_true:
				continue
			var shift: Dictionary = _calendar_shifts.get(entry.flag, {})
			if i in shift.get("rules_applied", []) or not get_world_flag(rule.when):
				continue
			if not _calendar_shifts.has(entry.flag):
				_calendar_shifts[entry.flag] = {"days": 0, "cancelled": false, "rules_applied": [], "history": []}
			_calendar_shifts[entry.flag]["rules_applied"].append(i)
			var result = shift_calendar_point(entry.flag, int(rule.days), rule.action == "cancel", rule.reason, "rule:" + rule.when, i, player_chain.get(rule.when, false) == true)
			if result.ok:
				made.append(result.merged({"reason": rule.reason, "when": rule.when, "rule": i}, true))
	return made

func _minute_string(minute: int) -> String:
	if minute < 0:
		return "never"
	return "Day %d, %02d:%02d" % [floori(minute / float(MINUTES_PER_DAY)) + 1, floori((minute % MINUTES_PER_DAY) / 60.0), minute % 60]

## Set every fixed point the clock has reached and that has not fired yet, earliest first, once each
## Cancelled points never fire. Safe to re-enter (a listener that moves the clock or shifts a point):
## each pass picks the earliest point due now, so anything newly due is picked up
func fire_due_calendar_flags() -> Array:
	var fired: Array = []
	if _firing_calendar:
		return fired
	_firing_calendar = true
	while true:
		# The earliest thing due: a point, or a movable point's eve (an eve goes before its point)
		var next: Dictionary = {}
		var next_at = 0
		var next_is_eve = false
		for entry in _calendar:
			if _is_cancelled(entry.flag):
				continue
			var candidates: Array = []
			if entry.movable and not _eves_fired.has(entry.flag):
				candidates.append([_effective_minute(entry) - EVE_MINUTES, true])
			if not _calendar_fired.has(entry.flag):
				candidates.append([_effective_minute(entry), false])
			for c in candidates:
				if int(c[0]) > game_minutes:
					continue
				if next.is_empty() or int(c[0]) < next_at or (int(c[0]) == next_at and c[1] and not next_is_eve):
					next = entry
					next_at = int(c[0])
					next_is_eve = c[1]
		if next.is_empty():
			break
		if next_is_eve:
			_eves_fired[next.flag] = next_at
			print("[WorldState] Calendar: %s (%s)" % [eve_flag(next.flag), get_time_string()])
			_world_change_depth += 1
			set_world_flag(eve_flag(next.flag), true)
			_world_change_depth -= 1
			calendar_eve_passed.emit(next.flag, eve_flag(next.flag), next_at)
			continue
		if not _eves_fired.has(next.flag) and next.movable:
			_eves_fired[next.flag] = next_at  # (unreachable: an eve always falls first)
		var at = _effective_minute(next)
		_calendar_fired[next.flag] = at
		fired.append(next.flag)
		print("[WorldState] Calendar: %s (%s)" % [next.flag, get_time_string()])
		_world_change_depth += 1
		set_world_flag(next.flag, true)
		_world_change_depth -= 1
		EventBus.calendar_flag_fired.emit(next.flag, at)
	_firing_calendar = false
	return fired

## True while the world itself (a calendar fixed point) is changing a flag. EventPropagator and
## StorylineDirector ask: nobody witnesses such a change, though gossip rules still apply
func is_world_change() -> bool:
	return _world_change_depth > 0

## Forget which fixed points fired and every shift (tests and new games); flags already set stay as they are
func reset_calendar(minutes: int = -1) -> void:
	_calendar_fired.clear()
	_calendar_shifts.clear()
	_eves_fired.clear()
	refresh_calendar_descriptions()
	if minutes >= 0:
		game_minutes = minutes

## Saved shifts (calendar_shifts in the save file)
func _load_calendar_shifts(data: Dictionary) -> void:
	_calendar_shifts.clear()
	var saved = data.get("calendar_shifts", {})
	if saved is Dictionary:
		for point in saved:
			var s = saved[point]
			if not s is Dictionary or _calendar_entry(str(point)).is_empty():
				continue
			var applied: Array = []
			for i in s.get("rules_applied", []):
				applied.append(int(i))
			_calendar_shifts[str(point)] = {"days": int(s.get("days", 0)), "cancelled": s.get("cancelled", false) == true,
				"rules_applied": applied, "history": s.get("history", []).duplicate(true) if s.get("history") is Array else [],
				"world_advance": int(s.get("world_advance", 0)), "player_advance": int(s.get("player_advance", 0))}
	_eves_fired.clear()
	var eves = data.get("calendar_eves_fired", {})
	if eves is Dictionary:
		for point in eves:
			_eves_fired[str(point)] = int(eves[point])
	# Saves from before eves existed: a point already fired, or an eve flag already true, counts as passed
	for entry in _calendar:
		if entry.movable and not _eves_fired.has(entry.flag):
			var fired = data.get("calendar_fired", {})
			if (fired is Dictionary and fired.has(entry.flag)) or (data.get("world_flags", {}) is Dictionary and data.get("world_flags", {}).get(eve_flag(entry.flag), false) == true):
				_eves_fired[entry.flag] = _effective_minute(entry) - EVE_MINUTES
	refresh_calendar_descriptions()

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
	request_save("npc_death")
	print("[WorldState] NPC death registered: %s" % npc_id)

## An NPC at a gathering the world holds them to (the Tithe drawing's congregation) acts where they
## stand but does not leave until it ends. Each marker is an npc_states key its owner clears
const ATTENDING_MARKERS = ["at_drawing"]

func is_npc_attending(npc_id: String) -> bool:
	var state = npc_states.get(npc_id, {})
	return state is Dictionary and ATTENDING_MARKERS.any(func(m): return state.has(m))

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
		# --- BEGIN director engine save (movable fixed points, inner voice) ---
		"calendar_shifts": _calendar_shifts.duplicate(true),
		"calendar_eves_fired": _eves_fired.duplicate(),
		"inner_voice": _get_inner_voice_state(),
		# --- END director engine save ---
		# --- BEGIN events engine save (player events: WORLD_SCHEMA §10) ---
		"player_events": _get_player_events_state(),
		# --- END events engine save ---
		"event_propagation": _get_event_propagation_state(),
		"storylines": _get_storyline_state(),
		"generics": _get_generics_state(),
		"quests": _get_quest_state(),
		"player_systems": _get_player_systems_state(),
		"player_location": _get_player_location()
	}

func _get_player_systems_state() -> Dictionary:
	var out = player_systems_state.duplicate(true)
	for name in PLAYER_SYSTEMS:
		var system = get_node_or_null("/root/" + name)
		if system and system.has_method("save"):
			out[name] = system.save()
	return out

func _apply_player_systems_state() -> void:
	for name in PLAYER_SYSTEMS:
		var system = get_node_or_null("/root/" + name)
		if system and system.has_method("load_from_dict") and player_systems_state.get(name) is Dictionary:
			system.load_from_dict(player_systems_state[name])

func _get_quest_state() -> Dictionary:
	var quests = get_node_or_null("/root/QuestManager")
	return quests.get_save_data() if quests and quests.has_method("get_save_data") else quest_state

func _get_player_location() -> String:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("get_current_location_id"):
		var id = str(scene_manager.get_current_location_id())
		if id != "" and id != "none":
			return id
	return player_location

func _apply_late_save_state() -> void:
	if not loaded_from_save:
		return
	_apply_player_systems_state()
	var quests = get_node_or_null("/root/QuestManager")
	if quests and quests.has_method("load_save_data") and not quest_state.is_empty():
		quests.load_save_data(quest_state)
	var scene_manager = get_node_or_null("/root/SceneManager")
	if player_location != "" and scene_manager and scene_manager.has_method("restore_location"):
		scene_manager.restore_location(player_location)

# --- BEGIN director engine save helpers (inner voice: the player's intentions, for the epilogue) ---
var inner_voice_state := {}  # loaded InnerVoice state (kept until InnerVoice is ready)

func _get_inner_voice_state() -> Dictionary:
	var inner_voice = get_node_or_null("/root/InnerVoice")
	return inner_voice.save() if inner_voice and inner_voice.has_method("save") else inner_voice_state

func _apply_inner_voice_state(data: Dictionary) -> void:
	inner_voice_state = data.get("inner_voice", {}) if data.get("inner_voice") is Dictionary else {}
	var inner_voice = get_node_or_null("/root/InnerVoice")
	if inner_voice and inner_voice.has_method("load_from_dict"):
		inner_voice.load_from_dict(inner_voice_state)
# --- END director engine save helpers ---

# --- BEGIN events engine save helpers (PlayerEvents autoloads after us) ---
var player_events_state := {}  # loaded PlayerEvents state (kept until PlayerEvents is ready)

func _get_player_events_state() -> Dictionary:
	var player_events = get_node_or_null("/root/PlayerEvents")
	return player_events.save() if player_events and player_events.has_method("save") else player_events_state

func _apply_player_events_state(data: Dictionary) -> void:
	player_events_state = data.get("player_events", {}) if data.get("player_events") is Dictionary else {}
	var player_events = get_node_or_null("/root/PlayerEvents")
	if player_events and player_events.has_method("load_from_dict"):
		player_events.load_from_dict(player_events_state)
# --- END events engine save helpers ---

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
	quest_state = data.get("quests", {}) if data.get("quests") is Dictionary else {}
	player_location = str(data.get("player_location", ""))
	player_systems_state = data.get("player_systems", {}) if data.get("player_systems") is Dictionary else {}
	npc_relationships = data.get("npc_relationships", {})
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	world_flags = data.get("world_flags", {})
	npc_states = data.get("npc_states", {})
	game_minutes = int(data.get("game_minutes", start_minute))
	# --- BEGIN director engine load (movable fixed points, inner voice) ---
	_load_calendar_shifts(data)
	_apply_inner_voice_state(data)
	# --- END director engine load ---
	_load_calendar_fired(data)
	_apply_event_propagation_state(data)
	_apply_storyline_state(data)
	_apply_generics_state(data)
	# --- BEGIN events engine load ---
	_apply_player_events_state(data)
	# --- END events engine load ---
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
			_calendar_fired[entry.flag] = _effective_minute(entry)

## Save game to disk. Written beside the save, then moved over it, so a crash mid-write never leaves
## a half file; the save it replaces is kept as save_backup_path. Returns true on success
func save_game() -> bool:
	var tmp_path = save_path + ".tmp"
	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[WorldState] Failed to save game")
		return false
	file.store_string(JSON.stringify(save(), "\t"))
	file.close()
	var dir = DirAccess.open(save_path.get_base_dir())
	if dir == null:
		push_error("[WorldState] Failed to save game")
		return false
	if dir.file_exists(save_path.get_file()):
		if dir.file_exists(save_backup_path.get_file()):
			dir.remove(save_backup_path.get_file())
		dir.rename(save_path.get_file(), save_backup_path.get_file())
	if dir.rename(tmp_path.get_file(), save_path.get_file()) != OK:
		push_error("[WorldState] Failed to save game")
		return false
	print("[WorldState] Game saved to: %s%s" % [save_path, " (%s)" % _save_reason if _save_reason != "" else ""])
	game_saved.emit(save_path, _save_reason)
	_save_reason = ""
	return true

## Ask for an autosave. Many requests in a burst (a conversation ending, a round, a flag) make one write
func request_save(reason: String = "") -> void:
	if not autosave_enabled or _autosave_timer == null or _save_held():
		return
	if _save_reason == "":
		_save_reason = reason
	if _autosave_timer.is_stopped():
		_autosave_timer.start()

## Not mid-opening (the drawing is the game's first moment; a save there would skip it) and not
## once the story has ended (the epilogue is the last word)
func _save_held() -> bool:
	var scene_manager = get_node_or_null("/root/SceneManager")
	var opening = scene_manager.opening if scene_manager and "opening" in scene_manager else null
	if opening and "playing" in opening and opening.playing:
		return true
	for ui in get_tree().get_nodes_in_group("player_ui"):
		if "story_over" in ui and ui.story_over:
			return true
	return false

## --save-path=user://somewhere.json (after --): play from, and save to, another file (dev runs, QA)
func _read_save_path_arg() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-path="):
			save_path = arg.substr("--save-path=".length())
			save_backup_path = save_path.get_basename() + ".bak.json"
			print("[WorldState] Save file: %s" % save_path)

func _setup_autosave() -> void:
	var args = OS.get_cmdline_user_args()
	autosave_enabled = "--no-autosave" not in args and (DisplayServer.get_name() != "headless" or "--autosave" in args)
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY_SECONDS
	_autosave_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_autosave_timer.timeout.connect(func(): if autosave_enabled and not _save_held(): save_game())
	add_child(_autosave_timer)
	_idle_save_timer = Timer.new()
	_idle_save_timer.wait_time = AUTOSAVE_IDLE_SECONDS
	_idle_save_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_idle_save_timer.timeout.connect(func(): request_save("idle"))
	add_child(_idle_save_timer)
	_idle_save_timer.start()
	EventBus.time_advanced.connect(func(_m, _total, reason): if reason != "idle": request_save(reason))
	EventBus.calendar_flag_fired.connect(func(flag_name, _at): request_save(flag_name))
	EventBus.quest_started.connect(func(_id, _data): request_save("quest"))
	EventBus.quest_completed.connect(func(_id, _npc, _outcome): request_save("quest"))
	call_deferred("_connect_late_autosave")

## Signals of autoloads that come after us
func _connect_late_autosave() -> void:
	var director = get_node_or_null("/root/StorylineDirector")
	if director and director.has_signal("round_completed"):
		director.round_completed.connect(func(_n, _reason, _entries): request_save("round"))
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_signal("scene_transition_completed"):
		scene_manager.scene_transition_completed.connect(func(location): request_save("arrived " + str(location)))

## Closing the window saves at once (no timer to wait for)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave_enabled and not _save_held():
		_save_reason = "quit"
		save_game()

## Load game from disk. A save that is missing or will not parse falls back to the previous one
func load_game():
	for path in [save_path, save_backup_path]:
		if not FileAccess.file_exists(path):
			continue
		var data = _read_save(path)
		if data.is_empty():
			push_error("[WorldState] Failed to read save file: %s" % path)
			continue
		load_from_dict(data)
		loaded_from_save = true
		print("[WorldState] Game loaded from: %s" % path)
		print("[WorldState] Loaded %d NPC states" % npc_states.size())
		if is_node_ready():
			_apply_late_save_state()  # mid-session: the player systems are up, restore them now (startup defers it)
		return
	print("[WorldState] No save file found, starting fresh")

func _read_save(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var ok = json.parse(file.get_as_text()) == OK and json.data is Dictionary
	file.close()
	return json.data if ok else {}

func load_state(data: Dictionary):
	faction_reputations = data.get("faction_reputations", {})
	quest_state = data.get("quests", {}) if data.get("quests") is Dictionary else {}
	player_location = str(data.get("player_location", ""))
	player_systems_state = data.get("player_systems", {}) if data.get("player_systems") is Dictionary else {}
	npc_relationships = data.get("npc_relationships", {})
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	world_flags = data.get("world_flags", {})
	game_minutes = int(data.get("game_minutes", game_minutes))
	# --- BEGIN director engine load (movable fixed points, inner voice) ---
	_load_calendar_shifts(data)
	_apply_inner_voice_state(data)
	# --- END director engine load ---
	_load_calendar_fired(data)
	_apply_event_propagation_state(data)
	_apply_storyline_state(data)
	_apply_generics_state(data)
	# --- BEGIN events engine load ---
	_apply_player_events_state(data)
	# --- END events engine load ---
