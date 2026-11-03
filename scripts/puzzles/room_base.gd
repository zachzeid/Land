extends Node2D
## RoomBase - an authored puzzle room (docs/PLAYER_SYSTEMS.md §5.3) built from WorldPhysics components
## (res://scripts/world/physics/*.gd). The room only listens to what the components report
## (pressure_plate `pressed(on)`, rope `cut`, WorldPhysics `burned(node, owner_key)`) and decides what
## the room's mechanism does with it; fire, weight and water are the components' own rules.
## State lives in the Puzzles autoload so it saves; the reward goes through Puzzles.complete_room

@export var room_id: String = ""

func _ready():
	var physics = get_node_or_null("/root/WorldPhysics")
	if physics and physics.has_signal("burned") and not physics.burned.is_connected(_on_burned):
		physics.burned.connect(_on_burned)
	_wire()
	_restore()

func _exit_tree():
	var physics = get_node_or_null("/root/WorldPhysics")
	if physics and physics.has_signal("burned") and physics.burned.is_connected(_on_burned):
		physics.burned.disconnect(_on_burned)

## Subclasses: connect their components
func _wire() -> void:
	pass

## Subclasses: show the room as its saved state left it
func _restore() -> void:
	pass

func _on_burned(_node: Node, _owner_key: String) -> void:
	pass

## A component by node name, anywhere under the room
func part(node_name: String) -> Node:
	return find_child(node_name, true, false)

## Connect a component's signal if the component and signal exist (a missing part is not a crash)
func listen(node_name: String, signal_name: String, callable: Callable) -> bool:
	var n = part(node_name)
	if n == null or not n.has_signal(signal_name):
		push_warning("[Room %s] %s has no signal %s" % [room_id, node_name, signal_name])
		return false
	if not n.is_connected(signal_name, callable):
		n.connect(signal_name, callable)
	return true

func state(key: String, default = null):
	var p = get_node_or_null("/root/Puzzles")
	return p.get_room_state(room_id).get(key, default) if p else default

func put_state(key: String, value) -> void:
	var p = get_node_or_null("/root/Puzzles")
	if p:
		p.set_room_state(room_id, key, value)

func is_complete() -> bool:
	var p = get_node_or_null("/root/Puzzles")
	return p != null and p.is_solved(room_id)

## The reward reached at `at` (room-local position of whatever was opened): seen by line of sight
func complete(at: Vector2) -> Dictionary:
	var p = get_node_or_null("/root/Puzzles")
	if p == null:
		return {"ok": false, "flag": "", "reason": "no_puzzles"}
	return p.complete_room(room_id, {"scene_root": self, "at": to_global(at)})

## Is `node` this part, or inside it (a component may sit on a child of the thing that burns)
func is_part(node: Node, node_name: String) -> bool:
	var n = part(node_name)
	return n != null and node != null and (node == n or n.is_ancestor_of(node))

## Take a blocker out of the world for good (a burned barricade, a lifted grate)
func remove_part(node_name: String) -> void:
	var n = part(node_name)
	if n:
		n.get_parent().remove_child(n)
		n.queue_free()

func set_part_enabled(node_name: String, on: bool) -> void:
	var n = part(node_name)
	if n == null:
		return
	if "enabled" in n:
		n.enabled = on
	if n is CanvasItem:
		n.visible = on
