extends "res://scripts/world/physics/physics_component.gd"
## Shadow - shade that hides (under eaves, in an alcove, beneath trees) (docs/PLAYER_SYSTEMS.md §5.1)
## Inside its radius the ground is at least `depth` dark (WorldPhysics.darkness_at), unless a lamp
## or a fire lights it

@export var radius: float = 64.0
## 0 no shade .. 1 black
@export var depth: float = 0.7

func kind() -> String:
	return "shadow"
