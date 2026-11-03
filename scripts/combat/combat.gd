extends Node
## Combat - attacks, damage types, poise, durability, morale, NPC fight decisions, creatures
## docs/PLAYER_SYSTEMS.md. Phase 0 stub: the contract (signatures other systems call) and save hooks;
## the owning build agent fills in the rest. Deeds go through PlayerEvents.record, never NPC state

signal hit_landed(info: Dictionary)
signal fight_ended(info: Dictionary)

## action: light | heavy | block | parry | dodge | shoot. Returns the resolved hit or {} for a miss
func attack(attacker: Node, target: Node, action: String) -> Dictionary:
	return {}

## Returns {damage, type, staggered, killed}
func resolve_hit(attacker: Node, target: Node, weapon: Dictionary, action: String) -> Dictionary:
	return {"damage": 0.0, "type": "blunt", "staggered": false, "killed": false}

## Never targets a minor (WorldRegistry.is_minor): docs/PLAYER_SYSTEMS.md §1.4
func can_target(target_key: String) -> bool:
	var registry = get_node_or_null("/root/WorldRegistry")
	return not (registry and registry.has_method("is_minor") and registry.is_minor(target_key))

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	pass
