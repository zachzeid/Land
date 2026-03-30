extends Resource
class_name ItemData
## ItemData - Base resource for all items in the game
##
## Items are Godot Resources (.tres files) that can be saved, loaded,
## and referenced by GDScript and the save system.

## Item categories
enum ItemCategory {
	MATERIAL,    # Iron ore, leather, herbs, timber, grain
	WEAPON,      # Sword, dagger, bow, club
	ARMOR,       # Leather vest, chain shirt, shield
	CONSUMABLE,  # Health potion, bread, ale, antidote
	TOOL,        # Pickaxe, lockpick, fishing rod
	EVIDENCE,    # Ledger, marked weapon, letter, seal
	QUEST,       # Key to old mill, Mira's locket
}

## Quality tiers
enum ItemQuality {
	CRUDE,       # Poorly made, improvised
	COMMON,      # Standard village quality
	FINE,        # Well-crafted
	SUPERIOR,    # Expert work (requires skilled crafter)
	MASTERWORK,  # Legendary quality (Bjorn's best)
}

# === Identity ===
@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: ItemCategory = ItemCategory.MATERIAL
@export var icon_path: String = ""

# === Physical properties ===
@export var weight: float = 1.0       # In "stones" (abstract unit)
@export var base_value: int = 10      # Reference anchor in silver coins

# === Stacking ===
@export var is_stackable: bool = false
@export var max_stack_size: int = 1

# === Quality ===
@export var quality: ItemQuality = ItemQuality.COMMON

# === Durability (weapons, armor, tools) ===
@export var max_durability: int = 0   # 0 = no durability tracking
var current_durability: int = 0

# === Combat properties ===
@export var damage_bonus: int = 0
@export var defense_bonus: int = 0
@export var equipment_slot: String = ""  # "main_hand", "off_hand", "chest", etc.

# === Consumable properties ===
@export var effect_type: String = ""     # "heal", "buff_strength", etc.
@export var effect_magnitude: int = 0

# === Evidence properties ===
@export var is_evidence: bool = false
@export var evidence_tags: Array[String] = []     # ["gregor_conspiracy", "bandit_weapons"]
@export var presentable_to: Array[String] = []    # NPC IDs who can react to this evidence

# === Crafting ===
@export var crafted_by: String = ""      # NPC who made this (e.g., "bjorn_blacksmith_001")
@export var maker_mark: String = ""      # Maker's mark (e.g., "B" for Bjorn)

func _init():
	if max_durability > 0:
		current_durability = max_durability

## Get quality display name
func get_quality_name() -> String:
	match quality:
		ItemQuality.CRUDE: return "Crude"
		ItemQuality.COMMON: return "Common"
		ItemQuality.FINE: return "Fine"
		ItemQuality.SUPERIOR: return "Superior"
		ItemQuality.MASTERWORK: return "Masterwork"
		_: return "Unknown"

## Get category display name
func get_category_name() -> String:
	match category:
		ItemCategory.MATERIAL: return "Material"
		ItemCategory.WEAPON: return "Weapon"
		ItemCategory.ARMOR: return "Armor"
		ItemCategory.CONSUMABLE: return "Consumable"
		ItemCategory.TOOL: return "Tool"
		ItemCategory.EVIDENCE: return "Evidence"
		ItemCategory.QUEST: return "Quest Item"
		_: return "Unknown"

## Calculate sell value (base adjusted by quality)
func get_sell_value() -> int:
	var quality_mult = [0.3, 1.0, 1.5, 2.5, 5.0]
	return int(base_value * quality_mult[quality])

## Serialize for save/load
func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"category": category,
		"quality": quality,
		"current_durability": current_durability,
		"weight": weight,
		"base_value": base_value,
	}
