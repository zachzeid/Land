extends Node2D
## A gathering node placed in a scene (docs/PLAYER_SYSTEMS.md §4): a tree, outcrop, herb patch, flax or
## someone's stores, from resources/crafting/nodes.json. Crafting keeps its state (depletes per take,
## grows back on the game clock) and records the deeds; this node is where they are seen from, and
## it shows itself bare while depleted, and not at all while its story gate is shut

@export var node_id: String = ""
## Shown while there is something to take; hidden while bare (optional)
@export var full_visual: NodePath
## Shown while bare (optional)
@export var bare_visual: NodePath

func _ready():
	add_to_group("resource_nodes")
	var crafting = _crafting()
	if crafting and node_id != "":
		crafting.register_node(node_id, self)
		crafting.node_changed.connect(_on_node_changed)
	var bus = get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("time_advanced"):
		bus.time_advanced.connect(func(_m, _t, _r): refresh())
	if bus and bus.has_signal("world_flag_changed"):
		bus.world_flag_changed.connect(func(_f, _o, _n): refresh())
	refresh()

func _exit_tree():
	var crafting = _crafting()
	if crafting and node_id != "":
		crafting.unregister_node(node_id, self)

## The player takes from it. Returns Crafting.gather
func interact(_by: Node = null) -> Dictionary:
	var crafting = _crafting()
	if crafting == null:
		return {"ok": false, "item": {}, "qty": 0, "reason": "no crafting"}
	var result = crafting.gather(node_id, self)
	refresh()
	return result

func is_depleted() -> bool:
	var crafting = _crafting()
	return crafting == null or crafting.node_available(node_id) <= 0

## Show the node as it is: gone while story-gated, bare while depleted
func refresh() -> void:
	var crafting = _crafting()
	if crafting == null:
		return
	visible = crafting.node_exists(node_id)
	var bare = is_depleted()
	var full = get_node_or_null(full_visual) if not full_visual.is_empty() else null
	var empty = get_node_or_null(bare_visual) if not bare_visual.is_empty() else null
	if full:
		full.visible = not bare
	if empty:
		empty.visible = bare
	if full == null and empty == null:
		modulate = Color(0.55, 0.55, 0.55) if bare else Color(1, 1, 1)

func _on_node_changed(id: String) -> void:
	if id == node_id:
		refresh()

func _crafting() -> Node:
	return get_node_or_null("/root/Crafting") if is_inside_tree() else null
