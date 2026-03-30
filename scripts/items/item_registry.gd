extends Node
class_name ItemRegistry
## ItemRegistry - Defines all items in the game
##
## Central registry for creating item instances.
## Items are defined here programmatically for now;
## can be migrated to .tres files later.

## All item definitions {item_id: ItemData}
var definitions: Dictionary = {}

func _ready():
	_register_all_items()
	print("[ItemRegistry] Registered %d items" % definitions.size())

## Get a fresh instance of an item by ID
func create_item(item_id: String) -> ItemData:
	if item_id not in definitions:
		push_warning("[ItemRegistry] Unknown item: %s" % item_id)
		return null
	return definitions[item_id].duplicate()

## Check if an item exists
func item_exists(item_id: String) -> bool:
	return item_id in definitions

func _register_all_items():
	# === EVIDENCE ITEMS ===
	_register("secret_ledger", {
		"name": "Secret Ledger",
		"description": "A hidden record of payments from Gregor's shop to unknown recipients. The entries span three years.",
		"category": ItemData.ItemCategory.EVIDENCE,
		"weight": 0.5,
		"value": 0,
		"is_evidence": true,
		"evidence_tags": ["ledger_found", "gregor_conspiracy"],
		"presentable_to": ["aldric_peacekeeper_001", "elena_daughter_001", "elder_mathias_001", "mira_tavern_keeper_001"],
	})

	_register("marked_weapon", {
		"name": "Marked Bandit Sword",
		"description": "A sword recovered from bandits. It bears a 'B' mark on the tang — the same mark Bjorn uses on his work.",
		"category": ItemData.ItemCategory.EVIDENCE,
		"weight": 3.0,
		"value": 15,
		"is_evidence": true,
		"evidence_tags": ["weapons_traced_to_bjorn"],
		"presentable_to": ["bjorn_blacksmith_001", "aldric_peacekeeper_001", "elder_mathias_001"],
		"maker_mark": "B",
	})

	_register("mira_letter", {
		"name": "Mira's Unsent Letter",
		"description": "A letter Mira wrote but never sent, addressed to someone in Millhaven. Its contents are revealing.",
		"category": ItemData.ItemCategory.EVIDENCE,
		"weight": 0.1,
		"value": 0,
		"is_evidence": true,
		"evidence_tags": ["mira_boss_revealed"],
		"presentable_to": ["gregor_merchant_001", "aldric_peacekeeper_001", "varn_bandit_001"],
	})

	# === WEAPONS ===
	_register("iron_sword", {
		"name": "Iron Sword",
		"description": "A serviceable iron sword from Bjorn's forge.",
		"category": ItemData.ItemCategory.WEAPON,
		"weight": 4.0, "value": 25, "damage": 8, "durability": 100,
		"slot": "main_hand", "maker_mark": "B",
	})

	_register("hunting_knife", {
		"name": "Hunting Knife",
		"description": "A sharp knife suitable for skinning game or defending yourself.",
		"category": ItemData.ItemCategory.WEAPON,
		"weight": 1.0, "value": 8, "damage": 4, "durability": 80,
		"slot": "main_hand",
	})

	_register("wooden_club", {
		"name": "Wooden Club",
		"description": "A heavy wooden club. Not elegant, but effective.",
		"category": ItemData.ItemCategory.WEAPON,
		"weight": 3.0, "value": 3, "damage": 5, "durability": 60,
		"slot": "main_hand",
	})

	# === ARMOR ===
	_register("leather_vest", {
		"name": "Leather Vest",
		"description": "A sturdy leather vest that offers basic protection.",
		"category": ItemData.ItemCategory.ARMOR,
		"weight": 5.0, "value": 20, "defense": 5, "durability": 80,
		"slot": "chest",
	})

	# === MATERIALS ===
	_register("iron_ore", {
		"name": "Iron Ore", "description": "Raw iron ore, ready for smelting.",
		"category": ItemData.ItemCategory.MATERIAL,
		"weight": 2.0, "value": 5, "stackable": true, "stack_size": 20,
	})

	_register("leather", {
		"name": "Leather", "description": "Tanned leather, useful for armor and goods.",
		"category": ItemData.ItemCategory.MATERIAL,
		"weight": 1.0, "value": 4, "stackable": true, "stack_size": 20,
	})

	_register("timber", {
		"name": "Timber", "description": "Cut wood for building and crafting.",
		"category": ItemData.ItemCategory.MATERIAL,
		"weight": 3.0, "value": 3, "stackable": true, "stack_size": 10,
	})

	_register("herbs", {
		"name": "Herbs", "description": "Medicinal herbs gathered from the hillsides.",
		"category": ItemData.ItemCategory.MATERIAL,
		"weight": 0.2, "value": 2, "stackable": true, "stack_size": 30,
	})

	_register("grain", {
		"name": "Grain", "description": "A sack of grain for bread and ale.",
		"category": ItemData.ItemCategory.MATERIAL,
		"weight": 2.0, "value": 3, "stackable": true, "stack_size": 15,
	})

	# === CONSUMABLES ===
	_register("bread", {
		"name": "Bread", "description": "Fresh bread from the village baker.",
		"category": ItemData.ItemCategory.CONSUMABLE,
		"weight": 0.3, "value": 1, "stackable": true, "stack_size": 10,
		"effect": "heal", "effect_amount": 15,
	})

	_register("ale", {
		"name": "Ale", "description": "A mug of Mira's brew. Restores spirit if not body.",
		"category": ItemData.ItemCategory.CONSUMABLE,
		"weight": 0.5, "value": 2, "stackable": true, "stack_size": 5,
		"effect": "heal", "effect_amount": 10,
	})

	_register("health_potion", {
		"name": "Health Potion", "description": "A herbal remedy that mends wounds.",
		"category": ItemData.ItemCategory.CONSUMABLE,
		"weight": 0.3, "value": 15, "stackable": true, "stack_size": 5,
		"effect": "heal", "effect_amount": 40,
	})

	_register("antidote", {
		"name": "Antidote", "description": "Cures common poisons.",
		"category": ItemData.ItemCategory.CONSUMABLE,
		"weight": 0.2, "value": 10, "stackable": true, "stack_size": 5,
		"effect": "cure_poison", "effect_amount": 1,
	})

	# === TOOLS ===
	_register("lockpick", {
		"name": "Lockpick Set", "description": "A set of thin metal picks for opening locks.",
		"category": ItemData.ItemCategory.TOOL,
		"weight": 0.2, "value": 12, "durability": 30,
	})

	_register("rope", {
		"name": "Rope", "description": "A length of sturdy rope. Many uses.",
		"category": ItemData.ItemCategory.TOOL,
		"weight": 2.0, "value": 5,
	})

	# === QUEST ITEMS ===
	_register("old_mill_key", {
		"name": "Old Mill Key", "description": "A rusty iron key. It might open the old mill on the village outskirts.",
		"category": ItemData.ItemCategory.QUEST,
		"weight": 0.1, "value": 0,
	})

## Helper to register an item from a simplified dictionary
func _register(id: String, data: Dictionary):
	var item = ItemData.new()
	item.item_id = id
	item.display_name = data.get("name", id)
	item.description = data.get("description", "")
	item.category = data.get("category", ItemData.ItemCategory.MATERIAL)
	item.weight = data.get("weight", 1.0)
	item.base_value = data.get("value", 10)
	item.is_stackable = data.get("stackable", false)
	item.max_stack_size = data.get("stack_size", 1)
	item.damage_bonus = data.get("damage", 0)
	item.defense_bonus = data.get("defense", 0)
	item.equipment_slot = data.get("slot", "")
	item.max_durability = data.get("durability", 0)
	item.current_durability = item.max_durability
	item.effect_type = data.get("effect", "")
	item.effect_magnitude = data.get("effect_amount", 0)
	item.is_evidence = data.get("is_evidence", false)
	item.evidence_tags = data.get("evidence_tags", [])
	item.presentable_to = data.get("presentable_to", [])
	item.crafted_by = data.get("crafted_by", "")
	item.maker_mark = data.get("maker_mark", "")
	definitions[id] = item
