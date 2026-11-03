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
