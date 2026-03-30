extends Node
class_name GameClock
## GameClock - Manages the game's day/night cycle and time progression
##
## Time periods: dawn, morning, noon, evening, night
## Each period lasts a configurable number of real seconds.
## NPCs use time periods to follow daily schedules.

signal time_period_changed(new_period: String, old_period: String)
signal new_day(day_number: int)

## Time period duration in real seconds (total day = 5 * period_duration)
@export var period_duration: float = 120.0  # 2 min per period = 10 min day

## Whether time advances automatically
@export var auto_advance: bool = true

## Current state
var current_day: int = 1
var current_period_index: int = 1  # Start at morning
var _elapsed: float = 0.0
var _paused: bool = false

const PERIODS: Array[String] = ["dawn", "morning", "noon", "evening", "night"]

func _ready():
	print("[GameClock] Initialized — Day %d, %s (period: %.0fs)" % [current_day, get_current_period(), period_duration])

func _process(delta: float):
	if not auto_advance or _paused:
		return
	if get_tree().paused:
		return

	_elapsed += delta
	if _elapsed >= period_duration:
		_elapsed -= period_duration
		_advance_period()

func _advance_period():
	var old_period = get_current_period()
	current_period_index += 1

	if current_period_index >= PERIODS.size():
		current_period_index = 0
		current_day += 1
		new_day.emit(current_day)
		print("[GameClock] === New Day: %d ===" % current_day)

	var new_period = get_current_period()
	time_period_changed.emit(new_period, old_period)
	print("[GameClock] Time: %s → %s (Day %d)" % [old_period, new_period, current_day])

## Get the current time period name
func get_current_period() -> String:
	return PERIODS[current_period_index]

## Get the current day number
func get_current_day() -> int:
	return current_day

## Get progress through current period (0.0 to 1.0)
func get_period_progress() -> float:
	return _elapsed / period_duration

## Force set time (for debug or story events)
func set_time(day: int, period: String):
	var old_period = get_current_period()
	current_day = day
	current_period_index = PERIODS.find(period)
	if current_period_index == -1:
		current_period_index = 0
	_elapsed = 0.0
	time_period_changed.emit(get_current_period(), old_period)
	print("[GameClock] Time set to Day %d, %s" % [current_day, get_current_period()])

## Advance to next period immediately (for debug)
func skip_period():
	_elapsed = 0.0
	_advance_period()

## Pause/resume time
func pause_time():
	_paused = true

func resume_time():
	_paused = false

func is_paused() -> bool:
	return _paused

## Get a human-readable time string
func get_time_string() -> String:
	return "Day %d, %s" % [current_day, get_current_period().capitalize()]
