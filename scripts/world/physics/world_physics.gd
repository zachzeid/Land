extends Node
## WorldPhysics - fire, water, wind, weight, rope, metal, light: systemic rules on components
## docs/PLAYER_SYSTEMS.md. Phase 0 stub: the contract (signatures other systems call) and save hooks;
## the owning build agent fills in the rest. Deeds go through PlayerEvents.record, never NPC state

signal fire_started(node: Node, by: String)
signal burned(node: Node, owner_key: String)

func ignite(node: Node, by: String = "") -> bool:
	return false

func douse(node: Node) -> bool:
	return false

func get_wind() -> Vector2:
	return Vector2.ZERO

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	pass
