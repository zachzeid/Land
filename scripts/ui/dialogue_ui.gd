extends CanvasLayer
# In-game dialogue UI overlay

@onready var dialogue_panel = $DialoguePanel
@onready var npc_name_label = $DialoguePanel/VBoxContainer/NPCName
@onready var dialogue_text = $DialoguePanel/VBoxContainer/DialogueText
@onready var player_input = $DialoguePanel/VBoxContainer/InputContainer/PlayerInput
@onready var send_button = $DialoguePanel/VBoxContainer/InputContainer/SendButton
@onready var debug_panel = get_node_or_null("DebugInteractionPanel")

var active_npc: Node = null

func _ready():
	# Allow UI to process during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	dialogue_panel.visible = false
	
	# Connect to all NPCs in scene
	await get_tree().process_frame  # Wait for scene to load
	for npc in get_tree().get_nodes_in_group("npcs"):
		# Only connect to NPCs that have the required signals (skip placeholders)
		if npc.has_signal("dialogue_started"):
			npc.dialogue_started.connect(_on_npc_dialogue_started)
			npc.dialogue_response_ready.connect(_on_npc_response_ready)
			npc.dialogue_ended.connect(_on_npc_dialogue_ended)
		else:
			push_warning("[DialogueUI] Skipping NPC without dialogue signals: %s" % npc.name)

func _on_npc_dialogue_started(npc_id: String):
	print("[DialogueUI] NPC dialogue started: ", npc_id)
	# Find the NPC node
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.npc_id == npc_id:
			active_npc = npc
			break
	
	if active_npc:
		print("[DialogueUI] Found NPC: ", active_npc.npc_name)
		dialogue_panel.visible = true
		npc_name_label.text = active_npc.npc_name
		dialogue_text.clear()
		dialogue_text.append_text("[color=gray]Conversation started...[/color]\n\n")
		player_input.editable = true
		get_tree().paused = true  # Pause game during dialogue
		
		# Show debug panel with this NPC
		if debug_panel:
			debug_panel.set_npc(active_npc)
		
		# Focus input after a brief delay to ensure UI is ready
		await get_tree().create_timer(0.1, true, false, true).timeout
		player_input.grab_focus()
	else:
		print("[DialogueUI] ERROR: Could not find NPC with ID: ", npc_id)

func _on_npc_response_ready(npc_id: String, response: String):
	print("[DialogueUI] NPC response ready: ", npc_id, " - ", response.substr(0, 50))
	if active_npc and active_npc.npc_id == npc_id:
		dialogue_text.append_text("[color=yellow][b]%s:[/b][/color] %s\n\n" % [active_npc.npc_name, response])
		player_input.editable = true
		player_input.grab_focus()

		# Generate and play voice for NPC response
		if VoiceManager and VoiceManager.is_available():
			VoiceManager.speak(npc_id, response)
	else:
		print("[DialogueUI] WARNING: Response from inactive NPC or mismatch")

func _on_npc_dialogue_ended(npc_id: String):
	dialogue_panel.visible = false
	active_npc = null
	dialogue_text.clear()
	player_input.text = ""
	get_tree().paused = false

	# Stop any playing voice
	if VoiceManager:
		VoiceManager.stop()

func _on_send_button_pressed():
	_send_message()

func _on_player_input_text_submitted(_text: String):
	_send_message()

func _send_message():
	if not active_npc:
		return
	
	var message = player_input.text.strip_edges()
	if message.is_empty():
		return
	
	# Display player message
	dialogue_text.append_text("[color=cyan][b]You:[/b][/color] %s\n\n" % message)
	
	# Clear input and disable
	player_input.text = ""
	player_input.editable = false
	
	# Send to NPC
	active_npc.respond_to_player(message)

func _on_end_button_pressed():
	if active_npc:
		active_npc.end_conversation()
	
	# Hide debug panel
	if debug_panel:
		debug_panel.hide()
