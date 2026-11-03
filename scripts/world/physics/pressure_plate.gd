extends "res://scripts/world/physics/physics_component.gd"
## PressurePlate - a plate that presses under enough weight (docs/PLAYER_SYSTEMS.md §5.1)
## Everything resting inside its rectangle presses it: the player, NPC bodies (living or dead),
## Weight things that are not hanging, full basins. It needs weight_needed plus any counterweight
## (the counterweight export, and hanging Weights that counter it). pressed(on) when that changes.
## A latching plate stays down once pressed

signal pressed(on: bool)

## How much weight presses it (a grown person is 70; a crate is 20)
@export var weight_needed: float = 50.0
## The plate's rectangle, centred on it (pixels)
@export var size: Vector2 = Vector2(48, 48)
## Weight on the other end of its chain, holding it up
@export var counterweight: float = 0.0
## Stays down once pressed
@export var latch: bool = false

var is_pressed: bool = false
var load_weight: float = 0.0

func kind() -> String:
	return "plate"

func rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)

## WorldPhysics sets this each step
func set_pressed(on: bool) -> void:
	if latch and is_pressed and not on:
		return
	if on == is_pressed:
		return
	is_pressed = on
	pressed.emit(on)

func get_state() -> Dictionary:
	return {"pressed": is_pressed}

func apply_state(state: Dictionary) -> void:
	# Quietly: the plate was already down before the save; nothing new happened
	is_pressed = bool(state.get("pressed", is_pressed))
