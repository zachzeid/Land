extends "res://scripts/world/physics/physics_component.gd"
## Lamp - a lamp, lantern, torch or brazier (docs/PLAYER_SYSTEMS.md §5.1)
## Lit by WorldPhysics.ignite, or by fire within reach (a burning flammable, another open flame).
## Put out by WorldPhysics.douse, and by rain when it is an open flame outdoors. A lit lamp lights
## the ground around it (WorldPhysics.darkness_at): it reveals what shadows hide. An open flame (a
## torch, a brazier) also heats flammables near it; a shuttered lantern does not

signal lit_changed(on: bool)

@export var lit: bool = false
## A naked flame: lights hay it is held to, and rain puts it out
@export var open_flame: bool = true
## How far its light reaches (pixels)
@export var light_radius: float = 160.0
## How near a fire must come to light it, and how far an open flame heats (pixels)
@export var reach: float = 40.0

func kind() -> String:
	return "lamp"

func set_lit(on: bool) -> bool:
	if on == lit:
		return false
	lit = on
	var t = thing()
	if t:
		t.modulate = Color(1.3, 1.15, 0.8) if lit else Color(1, 1, 1)
	lit_changed.emit(lit)
	return true

func get_state() -> Dictionary:
	return {"wetness": wetness, "lit": lit}

func apply_state(state: Dictionary) -> void:
	super.apply_state(state)
	set_lit(bool(state.get("lit", lit)))
