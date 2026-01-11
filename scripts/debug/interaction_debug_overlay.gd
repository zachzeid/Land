extends CanvasLayer
## Debug overlay showing interaction zones and available actions
## Toggle with F3 key

var enabled: bool = true
var player: Node2D = null

# UI elements
var debug_label: RichTextLabel = null
var interaction_indicators: Array[Node2D] = []

func _ready():
	layer = 99  # Above most UI
	_create_ui()
	print("[DebugOverlay] Interaction debug overlay ready (F3 to toggle)")

func _create_ui():
	# Create background panel
	var panel = Panel.new()
	panel.name = "DebugPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = 400
	panel.offset_bottom = 300
	panel.modulate.a = 0.85
	add_child(panel)

	# Create label for debug info
	debug_label = RichTextLabel.new()
	debug_label.name = "DebugLabel"
	debug_label.bbcode_enabled = true
	debug_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	debug_label.offset_left = 10
	debug_label.offset_top = 10
	debug_label.offset_right = -10
	debug_label.offset_bottom = -10
	panel.add_child(debug_label)

var memory_dump_pending: bool = false  # Track if we're waiting for memory dump

func _input(event: InputEvent):
	if event.is_action_pressed("ui_page_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_F3):
		enabled = !enabled
		visible = enabled
		print("[DebugOverlay] %s" % ("Enabled" if enabled else "Disabled"))

	# F4 - Dump all NPC memories to console
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		print("[DebugOverlay] F4 pressed - Dumping all NPC memories...")
		_dump_all_npc_memories()

	# F5 - Dump nearest NPC's memories
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		print("[DebugOverlay] F5 pressed - Dumping nearest NPC memories...")
		_dump_nearest_npc_memories()

func _process(_delta):
	if not enabled:
		return

	_find_player()
	_update_debug_info()

func _find_player():
	if player and is_instance_valid(player):
		return

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	else:
		# Try by name
		player = get_tree().current_scene.find_child("Player", true, false) if get_tree().current_scene else null

func _update_debug_info():
	var text = "[b][color=yellow]INTERACTION DEBUG (F3 to hide)[/color][/b]\n\n"

	# Current scene/location
	var scene_name = get_tree().current_scene.name if get_tree().current_scene else "None"
	var location_id = "Unknown"
	if SceneManager and SceneManager.current_location:
		location_id = SceneManager.current_location.location_id
	text += "[b]Scene:[/b] %s\n" % scene_name
	text += "[b]Location:[/b] %s\n\n" % location_id

	# Player info
	if player:
		text += "[b]Player Position:[/b] %s\n" % str(player.global_position)
		text += "[b]Player Groups:[/b] %s\n\n" % str(player.get_groups())
	else:
		text += "[color=red][b]Player NOT FOUND![/b][/color]\n\n"

	# Scene triggers
	text += "[b][color=cyan]SCENE TRIGGERS:[/color][/b]\n"
	var triggers = get_tree().get_nodes_in_group("scene_triggers")
	if triggers.is_empty():
		# Find by class
		triggers = _find_nodes_by_script("SceneTrigger")

	if triggers.is_empty():
		text += "  [color=gray]None found[/color]\n"
	else:
		for trigger in triggers:
			var dist = player.global_position.distance_to(trigger.global_position) if player else 999
			var in_range = trigger.get("player_in_range") if trigger.has_method("get") else false
			var target = trigger.get("target_location") if "target_location" in trigger else "?"
			var color = "green" if in_range else ("yellow" if dist < 100 else "gray")
			text += "  [color=%s]• %s → %s (%.0fpx)[/color]\n" % [color, trigger.name, target, dist]

	text += "\n[b][color=cyan]NPCs:[/color][/b]\n"
	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		text += "  [color=gray]None found[/color]\n"
	else:
		for npc in npcs:
			var dist = player.global_position.distance_to(npc.global_position) if player else 999
			var nearby = npc.get("player_nearby") if "player_nearby" in npc else false
			var in_convo = npc.get("is_in_conversation") if "is_in_conversation" in npc else false
			var npc_name = npc.get("npc_name") if "npc_name" in npc else npc.name
			var color = "green" if nearby else ("yellow" if dist < 100 else "gray")
			var status = " [TALKING]" if in_convo else (" [NEARBY]" if nearby else "")
			text += "  [color=%s]• %s (%.0fpx)%s[/color]\n" % [color, npc_name, dist, status]

	text += "\n[b][color=white]CONTROLS:[/color][/b]\n"
	text += "  [E] - Interact with NPCs/Triggers\n"
	text += "  Arrow Keys - Move\n"
	text += "  F3 - Toggle this overlay\n"
	text += "  F4 - Dump ALL NPC memories\n"
	text += "  F5 - Dump NEAREST NPC memories\n"

	debug_label.text = text

func _find_nodes_by_script(script_name: String) -> Array:
	var results = []
	var scene = get_tree().current_scene
	if scene:
		_find_nodes_recursive(scene, script_name, results)
	return results

func _find_nodes_recursive(node: Node, script_name: String, results: Array):
	if node.get_script():
		var script = node.get_script()
		if script.resource_path.contains(script_name.to_lower()) or node.get_class() == script_name:
			results.append(node)
	for child in node.get_children():
		_find_nodes_recursive(child, script_name, results)

## Dump all NPC memories to console (F4)
func _dump_all_npc_memories():
	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		print("[DebugOverlay] No NPCs found in scene")
		return

	print("\n" + "=".repeat(80))
	print("MEMORY DUMP - ALL NPCs (%d found)" % npcs.size())
	print("=".repeat(80))

	for npc in npcs:
		if npc.has_method("debug_dump_memories"):
			var dump = await npc.debug_dump_memories()
			print(dump)
		elif "rag_memory" in npc and npc.rag_memory and npc.rag_memory.has_method("dump_all_memories"):
			var dump = await npc.rag_memory.dump_all_memories()
			print(dump)
		else:
			var npc_name = npc.get("npc_name") if "npc_name" in npc else npc.name
			print("\n[%s] No memory system available" % npc_name)

	print("\n" + "=".repeat(80))
	print("END MEMORY DUMP")
	print("=".repeat(80) + "\n")

## Dump nearest NPC's memories to console (F5)
func _dump_nearest_npc_memories():
	if not player:
		print("[DebugOverlay] No player found")
		return

	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		print("[DebugOverlay] No NPCs found in scene")
		return

	# Find nearest NPC
	var nearest_npc = null
	var nearest_dist = INF
	for npc in npcs:
		var dist = player.global_position.distance_to(npc.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_npc = npc

	if nearest_npc == null:
		print("[DebugOverlay] Could not find nearest NPC")
		return

	var npc_name = nearest_npc.get("npc_name") if "npc_name" in nearest_npc else nearest_npc.name
	print("\n" + "=".repeat(80))
	print("MEMORY DUMP - %s (%.0fpx away)" % [npc_name, nearest_dist])
	print("=".repeat(80))

	if nearest_npc.has_method("debug_dump_memories"):
		var dump = await nearest_npc.debug_dump_memories()
		print(dump)
	elif "rag_memory" in nearest_npc and nearest_npc.rag_memory and nearest_npc.rag_memory.has_method("dump_all_memories"):
		var dump = await nearest_npc.rag_memory.dump_all_memories()
		print(dump)
	else:
		print("[%s] No memory system available" % npc_name)

	# Also print relationship state if available
	if nearest_npc.has_method("debug_print_state"):
		print("\n--- RELATIONSHIP STATE ---")
		await nearest_npc.debug_print_state()

	print("\n" + "=".repeat(80))
	print("END MEMORY DUMP")
	print("=".repeat(80) + "\n")
