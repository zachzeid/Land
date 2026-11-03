extends Interactable
## RoomAction - the player's hands in a puzzle room (docs/PLAYER_SYSTEMS.md §5.3): cut a rope, put a
## flame to something, roll a weight onto a plate. The components keep their own rules (WorldPhysics
## spreads the fire, the plate weighs what rests on it, the rope lets go); this only lets the player
## start them, so every way through a room is the player's choice and every mistake is theirs.
## - cut: target is a rope; needs an item tagged `needs_tag` (a blade) in the Inventory
## - ignite: target is a flammable or a lamp; needs an item tagged `needs_tag` (fire), or the flame of
##   a lit lamp in the room (`light_from`). WorldPhysics records the fire as a deed by the player
## - push: target is a thing (with a Weight); it rolls between where it stands and `destination`.
##   Where it stands saves in the room's state under `state_key`
## The text it says comes from the scene; a verb that cannot be done says why, in the world

@export_enum("cut", "ignite", "push") var verb: String = "cut"
## The component (rope, flammable, lamp) or, for push, the thing that moves
@export var target: NodePath
## push: the node whose position the thing moves to (a pressure plate, a mark)
@export var destination: NodePath
## An Inventory item tag the verb needs ("blade", "fire"); "" needs nothing
@export var needs_tag: String = ""
## ignite: a lamp whose flame can be borrowed when it is lit
@export var light_from: NodePath
## push: room state key that is true while the thing stands at its destination
@export var state_key: String = ""
## push: the prompt once the thing has been moved (moving it back)
@export var back_name: String = ""
## Said when the verb cannot be done for want of a tool or a flame
@export_multiline var lacking_text: String = ""
## Said when it is done
@export_multiline var done_text: String = ""

var _home: Vector2 = Vector2.ZERO
var _forward_name: String = ""

func _ready():
	super._ready()
	add_to_group("room_actions")
	_forward_name = interaction_name
	var t = _thing()
	if t:
		_home = t.position
	# After the room's own _ready (it restores the saved state this reads)
	call_deferred("_restore")

## Do the verb. Returns {ok, reason}; the text is also said in the world
func perform() -> Dictionary:
	var out: Dictionary
	match verb:
		"cut":
			out = _cut()
		"ignite":
			out = _ignite()
		"push":
			out = _push()
		_:
			out = {"ok": false, "reason": "unknown_verb"}
	return out

func _on_interact():
	var out = perform()
	var text = str(out.get("text", ""))
	if text != "":
		_say(text)
	interacted.emit(self)

func _cut() -> Dictionary:
	var rope = get_node_or_null(target)
	if rope == null or not rope.has_method("sever"):
		return {"ok": false, "reason": "no_rope"}
	if rope.get("is_cut"):
		return {"ok": false, "reason": "already_cut"}
	if needs_tag != "" and not has_tool(needs_tag):
		return {"ok": false, "reason": "no_" + needs_tag, "text": lacking_text}
	rope.sever("player")
	enabled = false
	_show_prompt(false)
	return {"ok": true, "reason": "cut", "text": done_text}

func _ignite() -> Dictionary:
	var node = get_node_or_null(target)
	var physics = get_node_or_null("/root/WorldPhysics")
	if node == null or physics == null:
		return {"ok": false, "reason": "no_physics"}
	if not _has_flame():
		return {"ok": false, "reason": "no_flame", "text": lacking_text}
	if not physics.ignite(node, "player"):
		return {"ok": false, "reason": "will_not_catch", "text": "It will not catch."}
	return {"ok": true, "reason": "lit", "text": done_text}

func _push() -> Dictionary:
	var t = _thing()
	var dest = get_node_or_null(destination)
	if t == null or not dest is Node2D:
		return {"ok": false, "reason": "nothing_to_move"}
	var moved = not at_destination()
	_place(moved)
	_put_state(moved)
	return {"ok": true, "reason": "moved" if moved else "moved_back", "text": done_text if moved else ""}

## The thing stands at its destination now
func at_destination() -> bool:
	var t = _thing()
	var dest = get_node_or_null(destination)
	return t != null and dest is Node2D and t.global_position.distance_to(dest.global_position) < 4.0

func _place(at_dest: bool) -> void:
	var t = _thing()
	var dest = get_node_or_null(destination)
	if t == null or not dest is Node2D:
		return
	if at_dest:
		t.global_position = dest.global_position
	else:
		t.position = _home
	interaction_name = back_name if at_dest and back_name != "" else _forward_name
	if player_in_range:
		_show_prompt(true)

func _restore() -> void:
	if verb == "push" and state_key != "":
		var room = _room()
		if room and room.has_method("state") and room.state(state_key, false):
			_place(true)
	elif verb == "cut":
		var rope = get_node_or_null(target)
		if rope and rope.get("is_cut"):
			enabled = false

func _put_state(on: bool) -> void:
	var room = _room()
	if state_key != "" and room and room.has_method("put_state"):
		room.put_state(state_key, on)

## An item in the Inventory carries this tag (a blade to cut with, a torch for fire)
func has_tool(tag: String) -> bool:
	var inv = get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("get_items"):
		return false
	for rec in inv.get_items():
		var def: Dictionary = inv.get_definition(str(rec.get("id", "")))
		if tag in def.get("tags", []):
			return true
	return false

func _has_flame() -> bool:
	if needs_tag == "" or has_tool(needs_tag):
		return true
	var lamp = get_node_or_null(light_from)
	return lamp != null and bool(lamp.get("lit"))

func _thing() -> Node2D:
	var t = get_node_or_null(target)
	return t if t is Node2D else null

func _room() -> Node:
	var n = get_parent()
	while n and not ("room_id" in n):
		n = n.get_parent()
	return n

## A line said in the world (a narration line, else a short-lived panel; nothing headless)
func _say(text: String) -> void:
	print("[RoomAction] %s: %s" % [name, text])
	if not is_inside_tree():
		return
	var dialogue_ui = get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("show_narration"):
		dialogue_ui.show_narration(text)
		return
	var scene = get_tree().current_scene
	if scene == null or DisplayServer.get_name() == "headless":
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	var panel = PanelContainer.new()
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	panel.add_child(label)
	canvas.add_child(panel)
	scene.add_child(canvas)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 220.0, 40.0)
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(canvas):
			canvas.queue_free())
