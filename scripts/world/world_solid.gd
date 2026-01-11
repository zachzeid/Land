extends StaticBody2D
class_name WorldSolid
## WorldSolid - Impassable world structure (buildings, walls, cliffs)
## Player and NPCs cannot walk through these objects

## Collision layer constants
const LAYER_WORLD_SOLID = 3

func _ready():
	# Set collision layer to world_solid (layer 3)
	collision_layer = 1 << (LAYER_WORLD_SOLID - 1)
	# Collide with player (1) and npc (2)
	collision_mask = (1 << 0) | (1 << 1)
