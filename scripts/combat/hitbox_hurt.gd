extends Area2D
## A fighter's hurtbox (docs/PLAYER_SYSTEMS.md §3): the area blows and shots find. Put it on the
## body's own layer (player 1, npc 2) as a child of the fighter; Combat.fighter_of() maps it back.
## Projectiles ray against it, melee arcs list its owner among Combat.fighters()

## The fighter this hurtbox belongs to (default: the parent)
@export var fighter_path: NodePath = NodePath("..")

func _ready() -> void:
	add_to_group("hurtboxes")
	monitoring = false
	monitorable = true

func fighter() -> Node:
	return get_node_or_null(fighter_path)
