extends "res://scripts/world/physics/physics_component.gd"
## Basin - a trough, cistern, bucket or font that holds water (docs/PLAYER_SYSTEMS.md §5.1)
## Rain fills it outdoors; fill_with() fills it by hand. pour() empties it over everything within
## reach: fire is put out and things are soaked. drop_in(node): metal sinks to the bottom, a burning
## thing is put out. Its water has weight, so a full basin on a plate presses it

signal filled(full: bool)

## 0 empty .. 1 full
@export var fill: float = 0.0
## How far poured water reaches (pixels)
@export var reach: float = 56.0
## What it weighs when full (on a pressure plate)
@export var water_mass: float = 40.0

var sunk: Array = []   # physics keys of metal at the bottom

func kind() -> String:
	return "basin"

func is_full() -> bool:
	return fill >= 0.999

func fill_with(amount: float) -> void:
	var was_full = is_full()
	fill = clampf(fill + amount, 0.0, 1.0)
	if is_full() != was_full:
		filled.emit(is_full())

## Pour it out over its reach (douses fire there). Returns how many fires it put out
func pour(by: String = "player") -> int:
	if fill <= 0.0:
		return 0
	var was_full = is_full()
	fill = 0.0
	if was_full:
		filled.emit(false)
	var physics = get_node_or_null("/root/WorldPhysics")
	return physics.douse_area(at(), reach, by) if physics else 0

## Put something in the water: metal sinks, fire goes out, everything gets wet
func drop_in(node: Node, by: String = "player") -> bool:
	if fill <= 0.0:
		return false
	var physics = get_node_or_null("/root/WorldPhysics")
	return physics.into_water(node, self, by) if physics else false

func get_state() -> Dictionary:
	return {"fill": fill, "sunk": sunk.duplicate()}

func apply_state(state: Dictionary) -> void:
	fill = float(state.get("fill", fill))
	sunk = Array(state.get("sunk", sunk))
