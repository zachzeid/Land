extends "res://scripts/world/physics/physics_component.gd"
## Flammable - a thing fire can take: dry grass, hay, wood, rope, cloth (docs/PLAYER_SYSTEMS.md §5.1)
## Heat from fire in reach builds up (faster downwind, not at all while wet) until it catches; it
## burns for burn_seconds and burns out (burned). Then it is destroyed, charred or kept, and any rope
## on the same thing is cut. A burnt thing with an owner_key is a `fire` deed about the owner when the
## player lit the fire (WorldPhysics). Rules live in WorldPhysics; this holds state

signal ignited(by: String)
signal extinguished(by: String)
signal burnt_out

## Whose it is (an NPC key): burning it is a deed about them
@export var owner_key: String = ""
## How long it burns once lit (seconds)
@export var burn_seconds: float = 6.0
## How far its fire reaches to heat other flammables and light lamps (pixels, before wind)
@export var reach: float = 64.0
## What it is, for the deed ("barn", "hay bale"); default: the thing's name
@export var what: String = ""
## What a burnt thing becomes: destroy (freed), char (blackened, stays), keep
@export_enum("destroy", "char", "keep") var on_burnt: String = "destroy"

var burning: bool = false
var burnt: bool = false
var burn_left: float = 0.0
var heat: float = 0.0          # 0..1; catches at 1
var lit_by: String = ""        # who started the fire this is part of ("player", an NPC key, "")
var fire_id: String = ""       # one fire, however far it spreads (one deed per owner per fire)

func kind() -> String:
	return "flammable"

func describe() -> String:
	if what != "":
		return what
	return str(thing().name).capitalize().to_lower()

## WorldPhysics calls this when the fire is out and the thing is spent
func _on_burnt() -> void:
	var t = thing()
	match on_burnt:
		"destroy":
			if t and is_instance_valid(t):
				t.queue_free()
		"char":
			if t:
				t.modulate = Color(0.25, 0.22, 0.2)
	burnt_out.emit()

func _show_fire(on: bool) -> void:
	var t = thing()
	if t and not burnt:
		t.modulate = Color(1.4, 0.8, 0.5) if on else Color(1, 1, 1)

func get_state() -> Dictionary:
	return {"wetness": wetness, "burning": burning, "burnt": burnt, "burn_left": burn_left,
		"heat": heat, "lit_by": lit_by, "fire_id": fire_id}

func apply_state(state: Dictionary) -> void:
	super.apply_state(state)
	burning = bool(state.get("burning", burning))
	burnt = bool(state.get("burnt", burnt))
	burn_left = float(state.get("burn_left", burn_left))
	heat = float(state.get("heat", heat))
	lit_by = str(state.get("lit_by", lit_by))
	fire_id = str(state.get("fire_id", fire_id))
	if burnt:
		_restore_burnt()
	else:
		_show_fire(burning)

## A thing that burnt before the save is burnt again on load (freed or charred, without a deed)
func _restore_burnt() -> void:
	var t = thing()
	if on_burnt == "destroy" and t and is_instance_valid(t):
		t.queue_free()
	elif on_burnt == "char" and t:
		t.modulate = Color(0.25, 0.22, 0.2)
