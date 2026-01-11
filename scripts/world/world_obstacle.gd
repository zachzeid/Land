extends StaticBody2D
class_name WorldObstacle
## WorldObstacle - Partial world blockers (trees, rocks, fences)
## Blocks movement but has smaller collision than visual (e.g., tree trunk only)

## Collision layer constants
const LAYER_WORLD_OBSTACLE = 4

func _ready():
	# Set collision layer to world_obstacle (layer 4)
	collision_layer = 1 << (LAYER_WORLD_OBSTACLE - 1)
	# Collide with player (1) and npc (2)
	collision_mask = (1 << 0) | (1 << 1)
