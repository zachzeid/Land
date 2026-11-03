extends "res://scripts/world/physics/physics_component.gd"
## Weight - how heavy a thing is: a crate, a stone, a sack (docs/PLAYER_SYSTEMS.md §5.1)
## Resting inside a pressure plate it presses with its mass; hanging from a rope it does not (top
## down: it is above the plate until the rope parts). A hanging weight that `counters` a plate is a
## counterweight: it holds that plate up by its mass. Light things (drifts) blow along in the wind.
## The player and NPC bodies weigh without a component (WorldPhysics.weight_of)

## Mass in the same units as PressurePlate.weight_needed (a grown person is 70)
@export var mass: float = 20.0
## Hangs from a rope (set by the rope; set here for a weight held some other way)
@export var hanging: bool = false
## Light enough for the wind to carry (a sack of feathers, a paper lantern, dry leaves)
@export var drifts: bool = false
## A plate this weight holds up while it hangs (a counterweight)
@export var counters: NodePath

func kind() -> String:
	return "weight"

func countered_plate() -> Node:
	return get_node_or_null(counters) if not counters.is_empty() else null

func get_state() -> Dictionary:
	var s = {"hanging": hanging}
	var t = thing()
	if t and t.is_inside_tree():
		s["pos"] = [t.global_position.x, t.global_position.y]
	return s

func apply_state(state: Dictionary) -> void:
	hanging = bool(state.get("hanging", hanging))
	var pos = state.get("pos", null)
	var t = thing()
	if pos is Array and pos.size() == 2 and t and t.is_inside_tree():
		t.global_position = Vector2(float(pos[0]), float(pos[1]))
