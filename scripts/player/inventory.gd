extends Node
## Inventory - items, equipment, coin (pennies), weight, provenance, the pack dropped on death
## docs/PLAYER_SYSTEMS.md. Phase 0 stub: the contract (signatures other systems call) and save hooks;
## the owning build agent fills in the rest. Deeds go through PlayerEvents.record, never NPC state

signal changed()

## Item records: {id, qty, quality, durability, maker, provenance}
func add(item_id: String, qty: int = 1, props: Dictionary = {}) -> bool:
	return false

func remove(item_id: String, qty: int = 1) -> bool:
	return false

func has(item_id: String, qty: int = 1) -> bool:
	return false

func equip(item_id: String, slot: String) -> bool:
	return false

func get_equipped(slot: String) -> Dictionary:
	return {}

func get_items() -> Array:
	return []

func get_coin() -> int:
	return 0

func add_coin(pennies: int) -> void:
	pass

## Wear an equipped item (durability). Returns {broke}
func wear(slot: String, amount: float = 1.0) -> Dictionary:
	return {"broke": false}

## Every death drops the whole inventory here as a pack (docs/PLAYER_SYSTEMS.md §2). Returns the pack
func drop_all_at(scene_root: Node, position: Vector2) -> Node:
	return null

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	pass
