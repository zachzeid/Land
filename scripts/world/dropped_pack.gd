extends Interactable
class_name DroppedPack
## DroppedPack - everything the player carried, where they fell (docs/PLAYER_SYSTEMS.md §2)
## The contents live in Inventory.packs (saved, by location and position), not on this node: the node is
## only how the pack shows in a loaded scene. Interacting takes it all back

@export var pack_id: String = ""

func _ready():
	super._ready()
	add_to_group("dropped_packs")
	interaction_name = "Take back your pack"

func _on_interact():
	var inventory = get_node_or_null("/root/Inventory")
	if inventory and inventory.take_pack(pack_id):
		interacted.emit(self)
		return
	queue_free()  # nothing left to take: an NPC got there first

## What the pack holds (Inventory.get_pack: {items, coin, state, ...}; {} once taken)
func get_contents() -> Dictionary:
	var inventory = get_node_or_null("/root/Inventory")
	return inventory.get_pack(pack_id) if inventory else {}
