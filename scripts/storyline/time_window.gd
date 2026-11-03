extends RefCounted
## TimeWindow - when in the day an NPC will take a personal step (SOUL.md `| when: <window>`)
## People keep hours: a step with no `when` happens in waking hours, a step at night must say so
## Windows are [from, to) in hours; to < from wraps past midnight ("night" is 21:00 to 05:00)

const WINDOWS = {
	"waking": [6, 22],     # the default: no `when` given
	"dawn": [5, 8],
	"morning": [6, 12],
	"day": [8, 18],
	"afternoon": [12, 17],
	"evening": [17, 22],
	"dark": [19, 5],       # "after dark"
	"night": [21, 5],
	"tonight": [18, 4],    # "tonight": later this evening or this night
	"any": [0, 24],
}
const DEFAULT = "waking"

## "" | a named window | "HH-HH" (e.g. "03-06", "11-14")
static func is_valid(when: String) -> bool:
	return when == "" or WINDOWS.has(when) or not _range(when).is_empty()

static func contains(when: String, hour: int) -> bool:
	var span: Array = WINDOWS.get(when if when != "" else DEFAULT, _range(when))
	if span.is_empty():
		return true  # unreadable: never strand a step (the validator reports it)
	var from = int(span[0])
	var to = int(span[1])
	hour = posmod(hour, 24)
	return (hour >= from and hour < to) if from <= to else (hour >= from or hour < to)

static func _range(when: String) -> Array:
	var parts = when.split("-")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return []
	var from = int(parts[0])
	var to = int(parts[1])
	return [from, to] if from >= 0 and from <= 23 and to >= 1 and to <= 24 and from != to else []

## The first game minute at or after now_minute that falls in the window (now_minute if it is open)
static func next_open(when: String, now_minute: int) -> int:
	for step in 24 * 60:
		var minute = now_minute + step
		if contains(when, floori((minute % (24 * 60)) / 60.0)):
			return minute
	return now_minute

# =============================================================================
# OPENING HOURS (world.json "opening_hours": every place, every NPC, on the game clock)
# =============================================================================

## [open_hour, close_hour) from WorldRegistry; [0, 24] (always open) without one
static func opening_hours() -> Array:
	var tree = Engine.get_main_loop() as SceneTree
	var registry = tree.root.get_node_or_null("WorldRegistry") if tree else null
	return registry.get_opening_hours() if registry and registry.has_method("get_opening_hours") else [0, 24]

static func is_open(minute: int) -> bool:
	var hours = opening_hours()
	return contains("%02d-%02d" % [hours[0], hours[1]], floori((posmod(minute, 24 * 60)) / 60.0)) if hours != [0, 24] else true

## The first minute at or after now_minute inside both the window and the opening hours
## (now_minute itself if both hold). A window that never meets the opening hours: now_minute
static func next_open_and_in(when: String, now_minute: int) -> int:
	for step in 2 * 24 * 60:
		var minute = now_minute + step
		if is_open(minute) and contains(when, floori((minute % (24 * 60)) / 60.0)):
			return minute
	return now_minute

## The earliest departure at or after now_minute that is in opening hours and arrives (after
## travel_minutes) in them too: setting off is acting. A journey too long to fit leaves at opening
static func departure_for_open_arrival(now_minute: int, travel_minutes: int) -> int:
	for step in 2 * 24 * 60:
		var depart = now_minute + step
		if is_open(depart) and is_open(depart + travel_minutes):
			return depart
	for step in 24 * 60:
		if is_open(now_minute + step):
			return now_minute + step
	return now_minute

