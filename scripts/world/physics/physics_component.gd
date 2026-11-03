extends Node2D
## PhysicsComponent - the shared base of the world physics components (docs/PLAYER_SYSTEMS.md §5.1)
## A component is a child of the thing it gives a rule to (a hay bale, a crate, a torch). It registers
## with WorldPhysics, which runs the rules; the component only holds its state and exports.
## thing(): the node the rule acts on (burnt and freed, moved by a lodestone, weighed on a plate):
## thing_path when set, else the parent when the parent is one object, else this node itself.
## A level root (the current scene, a child of the tree root, a BaseInterior, group "physics_room")
## is never a thing, so a component placed straight in a room acts on itself, not on the room

## Stable save key across loads; default: the node path
@export var physics_id: String = ""
## Rain reaches it outdoors. auto: indoors under a BaseInterior or group "indoors"/"physics_room"
## or in a scene file under scenes/puzzles/ or an interior
@export_enum("auto", "outdoors", "indoors") var exposure: String = "auto"
## The node this rule acts on (empty: see thing())
@export var thing_path: NodePath

var wetness: float = 0.0   # 0 dry .. 1 soaked
var _key: String = ""

## "flammable" | "rope" | "lamp" | "basin" | "metal" | "plate" | "weight" | "shadow"
func kind() -> String:
	return ""

func _enter_tree() -> void:
	add_to_group("physics_component")
	add_to_group("physics_" + kind())
	var physics = get_node_or_null("/root/WorldPhysics")
	if physics and physics.has_method("register"):
		physics.register(self)

func _exit_tree() -> void:
	var physics = get_node_or_null("/root/WorldPhysics")
	if physics and physics.has_method("unregister"):
		physics.unregister(self)

func physics_key() -> String:
	if _key == "":
		_key = physics_id if physics_id != "" else (str(get_path()) if is_inside_tree() else name)
	return _key

func thing() -> Node2D:
	if not thing_path.is_empty():
		var t = get_node_or_null(thing_path)
		if t is Node2D:
			return t
	var p = get_parent()
	if p is Node2D and not _is_level(p) and _is_one_object(p):
		return p
	return self

## Where the rule happens (the thing's position)
func at() -> Vector2:
	var t = thing()
	return t.global_position if t and t.is_inside_tree() else global_position

func is_outdoors() -> bool:
	if exposure != "auto":
		return exposure == "outdoors"
	var n: Node = self
	while n:
		if n.is_in_group("indoors") or n.is_in_group("physics_room") or n.get("interior_size") != null:
			return false
		var path = n.scene_file_path
		if path.contains("/puzzles/") or path.contains("interior"):
			return false
		n = n.get_parent()
	return true

func is_wet() -> bool:
	return wetness > 0.2

## Saved state (WorldPhysics keeps it across scene changes and in the save)
func get_state() -> Dictionary:
	return {"wetness": wetness}

func apply_state(state: Dictionary) -> void:
	wetness = float(state.get("wetness", wetness))

func _is_level(n: Node) -> bool:
	if not n.is_inside_tree():
		return false
	var tree = n.get_tree()
	return n == tree.current_scene or n.get_parent() == tree.root or n.is_in_group("physics_room") \
		or n.is_in_group("indoors") or n.get("interior_size") != null

## A parent holding several things (components on sub-nodes, or two of a kind) is a container
func _is_one_object(p: Node) -> bool:
	var kinds := {}
	for c in p.get_children():
		if c.is_in_group("physics_component") or c.has_method("physics_key"):
			var k = c.kind()
			if kinds.has(k):
				return false
			kinds[k] = true
	for c in p.get_children():
		for d in c.find_children("*", "", true, false):
			if d.has_method("physics_key"):
				return false
	return true
