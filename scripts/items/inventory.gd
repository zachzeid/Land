extends Node
class_name Inventory
## Inventory - Weight-based inventory system for player and NPCs
##
## Items are stored as {item_id: {item: ItemData, quantity: int}} entries.
## Weight capacity limits what can be carried.
## Evidence items are tracked separately for quick access.

signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_full(item_id: String)
signal evidence_acquired(item_id: String, evidence_tags: Array)

## Maximum carry weight in "stones"
@export var max_weight: float = 50.0

## Current contents {item_id: {item: ItemData, quantity: int}}
var items: Dictionary = {}

## Equipped items {slot: ItemData}
var equipped: Dictionary = {}

## Currency
var silver: int = 20  # Starting silver

## Computed properties
var current_weight: float = 0.0

## Add item to inventory (returns true if successful)
func add_item(item: ItemData, quantity: int = 1) -> bool:
	var added_weight = item.weight * quantity
	if current_weight + added_weight > max_weight:
		inventory_full.emit(item.item_id)
		return false

	if item.item_id in items:
		if item.is_stackable:
			var current = items[item.item_id].quantity
			var max_stack = item.max_stack_size
			if current + quantity > max_stack:
				return false
			items[item.item_id].quantity += quantity
		else:
			# Non-stackable: create unique entry
			var unique_id = "%s_%d" % [item.item_id, Time.get_unix_time_from_system()]
			items[unique_id] = {"item": item, "quantity": 1}
	else:
		items[item.item_id] = {"item": item, "quantity": quantity}

	current_weight += added_weight
	item_added.emit(item.item_id, quantity)

	# Track evidence items
	if item.is_evidence:
		evidence_acquired.emit(item.item_id, item.evidence_tags)

	return true

## Remove item from inventory
func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id not in items:
		return false

	var entry = items[item_id]
	if entry.quantity < quantity:
		return false

	entry.quantity -= quantity
	current_weight -= entry.item.weight * quantity

	if entry.quantity <= 0:
		items.erase(item_id)

	item_removed.emit(item_id, quantity)
	return true

## Check if player has an item
func has_item(item_id: String, quantity: int = 1) -> bool:
	if item_id in items:
		return items[item_id].quantity >= quantity
	return false

## Get all items of a category
func get_items_by_category(category: ItemData.ItemCategory) -> Array:
	var result := []
	for id in items:
		if items[id].item.category == category:
			result.append(items[id])
	return result

## Get all evidence items the player has
func get_evidence_items() -> Array:
	var result := []
	for id in items:
		if items[id].item.is_evidence:
			result.append(items[id])
	return result

## Get evidence flags (for context injection into NPC dialogues)
func get_evidence_flags() -> Array[String]:
	var flags: Array[String] = []
	for id in items:
		var item = items[id].item
		if item.is_evidence:
			flags.append_array(item.evidence_tags)
	return flags

## Get evidence items presentable to a specific NPC
func get_presentable_evidence(npc_id: String) -> Array:
	var result := []
	for id in items:
		var item = items[id].item
		if item.is_evidence and npc_id in item.presentable_to:
			result.append(item)
	return result

## Equip an item (returns previously equipped item or null)
func equip_item(item_id: String) -> ItemData:
	if item_id not in items:
		return null

	var item = items[item_id].item
	if item.equipment_slot == "":
		return null

	var previous = equipped.get(item.equipment_slot, null)
	equipped[item.equipment_slot] = item
	return previous

## Spend silver (returns true if affordable)
func spend_silver(amount: int) -> bool:
	if silver < amount:
		return false
	silver -= amount
	return true

## Earn silver
func earn_silver(amount: int):
	silver += amount

## Get weight percentage
func get_weight_percentage() -> float:
	return current_weight / max_weight

## Serialize for save/load
func to_dict() -> Dictionary:
	var items_data := {}
	for id in items:
		items_data[id] = {
			"item_id": items[id].item.item_id,
			"quantity": items[id].quantity,
		}
	return {
		"items": items_data,
		"silver": silver,
		"equipped": {},  # TODO: serialize equipped items
	}
