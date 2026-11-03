extends Node
## Crafting - recipes, stations (owner's leave), gathering nodes, quality, maker's mark, herbcraft
## docs/PLAYER_SYSTEMS.md. Phase 0 stub: the contract (signatures other systems call) and save hooks;
## the owning build agent fills in the rest. Deeds go through PlayerEvents.record, never NPC state

signal crafted(item: Dictionary)

func can_craft(recipe_id: String, station_id: String) -> Dictionary:
	return {"ok": false, "reason": "crafting is not built yet"}

## Cooking and remedies: delegates to Herbcraft.cook (res://scripts/crafting/herbcraft.gd)
func cook(ingredients: Array, station_id: String) -> Dictionary:
	return {"ok": false, "item": {}, "reason": "herbcraft is not built yet"}

## Returns {ok, item, reason}
func craft(recipe_id: String, station_id: String) -> Dictionary:
	return {"ok": false, "item": {}, "reason": "crafting is not built yet"}

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	pass
