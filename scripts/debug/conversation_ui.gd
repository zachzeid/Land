extends Control
# Test UI for live NPC conversation
# Updated to use structured NPCPersonality resources and tiered memory system

@onready var conversation_history = $MarginContainer/VBoxContainer/ConversationHistory
@onready var player_input = $MarginContainer/VBoxContainer/InputContainer/PlayerInput
@onready var send_button = $MarginContainer/VBoxContainer/InputContainer/SendButton
@onready var start_button = $MarginContainer/VBoxContainer/ButtonContainer/StartButton
@onready var end_button = $MarginContainer/VBoxContainer/ButtonContainer/EndButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
@onready var npc_info = $MarginContainer/VBoxContainer/NPCInfo
@onready var npc_container = $NPC

var npc: Node2D
var is_waiting_for_response = false

## Set to true to use ChromaDB, false for in-memory only (faster testing)
@export var use_chromadb: bool = false

func _ready():
	_update_status("Initializing NPC...")
	_log("[color=gray]Starting NPC initialization...[/color]")

	# Create NPC with personality
	var BaseNPCScript = load("res://scripts/npcs/base_npc.gd")
	npc = BaseNPCScript.new()

	# Configure NPC - try to load structured personality, fallback to legacy
	npc.npc_id = "gregor_merchant_001"
	npc.npc_name = "Gregor"

	# Try to load structured personality resource
	var personality_path = "res://resources/npc_personalities/gregor_merchant.tres"
	if ResourceLoader.exists(personality_path):
		npc.personality_resource = load(personality_path)
		_log("[color=green]Loaded structured personality: gregor_merchant.tres[/color]")
	else:
		# Fallback to legacy system prompt
		_log("[color=yellow]No personality resource found, using legacy prompt[/color]")
		npc.system_prompt = _get_legacy_system_prompt()

	npc_container.add_child(npc)

	# Connect NPC signals
	npc.dialogue_started.connect(_on_npc_dialogue_started)
	npc.dialogue_response_ready.connect(_on_npc_response_ready)
	npc.dialogue_ended.connect(_on_npc_dialogue_ended)

	# Initialize NPC (this sets up RAGMemory, ContextBuilder, etc.)
	_log("[color=gray]Calling npc.initialize(use_chromadb=%s)...[/color]" % use_chromadb)
	var init_success = await npc.initialize(use_chromadb, false)

	if init_success:
		_update_status("Ready - Click 'Start Conversation'")
		_log("[color=green]NPC initialized successfully![/color]")
		_log("[color=gray]Memory mode: %s[/color]" % ("ChromaDB" if use_chromadb else "In-Memory"))
		_log("[color=gray]Tiered memory system: ACTIVE[/color]")
	else:
		_update_status("ERROR: NPC initialization failed")
		_log("[color=red]NPC initialization failed![/color]")

func _get_legacy_system_prompt() -> String:
	return """You are Gregor, a cautious merchant who runs a small shop selling adventuring supplies in the village of Thornhaven.

Personality traits:
- Formal and business-minded - you always think about profit margins
- Suspicious of strangers initially, but warm to paying customers
- Nervous about the recent bandit attacks on trade caravans
- Protective of your inventory and wary of thieves
- Become friendly when discussing commerce and trade

Speech patterns:
You speak formally with occasional merchant jargon ("fine wares," "fair price," "good coin"). You often mention your concerns about bandits and security. You're polite but reserved until trust is earned.

Your goals:
- Make sales and protect your profit margins
- Keep your shop safe from bandits and thieves
- Build relationships with trustworthy customers

SECRET: You know the bandits have an inside informant in the village, but you're too afraid to speak up about it unless you deeply trust someone.

When interacting with the player:
- Start cautious and business-focused
- Warm up if they show genuine interest in your wares or concerns
- Become nervous if they ask about bandits directly
- Remember previous conversations and adjust your opinion based on their actions"""

func _check_chroma() -> bool:
	# Quick check if ChromaDB is accessible
	return npc.rag_memory.chroma_client != null

func _update_status(text: String):
	status_label.text = "Status: " + text

func _update_npc_info():
	# Show 5D relationship dimensions
	var trust = int(npc.relationship_trust)
	var respect = int(npc.relationship_respect)
	var affection = int(npc.relationship_affection)
	var fear = int(npc.relationship_fear)
	var familiarity = int(npc.relationship_familiarity)

	npc_info.text = "%s | T:%d R:%d A:%d F:%d Fam:%d" % [
		npc.npc_name, trust, respect, affection, fear, familiarity
	]

func _log(message: String):
	conversation_history.append_text(message + "\n\n")

func _on_start_button_pressed():
	start_button.disabled = true
	end_button.disabled = false
	send_button.disabled = false
	is_waiting_for_response = true
	
	_update_status("Starting conversation...")
	_log("[color=yellow]--- Conversation Started ---[/color]")
	
	# Start conversation (NPC generates greeting)
	npc.start_conversation()

func _on_end_button_pressed():
	start_button.disabled = false
	end_button.disabled = true
	send_button.disabled = true
	player_input.editable = false
	
	npc.end_conversation()

func _on_send_button_pressed():
	_send_message()

func _on_player_input_text_submitted(_text: String):
	_send_message()

func _send_message():
	if is_waiting_for_response:
		_log("[color=orange]Wait for NPC response...[/color]")
		return
	
	var message = player_input.text.strip_edges()
	if message.is_empty():
		return
	
	# Display player message
	_log("[color=cyan][b]You:[/b][/color] " + message)
	
	# Clear input
	player_input.text = ""
	
	# Disable input while waiting
	is_waiting_for_response = true
	send_button.disabled = true
	player_input.editable = false
	_update_status("NPC is thinking...")
	
	# Send to NPC
	npc.respond_to_player(message)

func _on_npc_dialogue_started(npc_id: String):
	_update_status("Conversation active")
	_update_npc_info()

func _on_npc_response_ready(npc_id: String, response: String):
	# Display NPC response
	_log("[color=lightgreen][b]%s:[/b][/color] %s" % [npc.npc_name, response])
	
	# Re-enable input
	is_waiting_for_response = false
	send_button.disabled = false
	player_input.editable = true
	player_input.grab_focus()
	_update_status("Your turn")
	_update_npc_info()

func _on_npc_dialogue_ended(npc_id: String):
	_log("[color=yellow]--- Conversation Ended ---[/color]")
	_update_status("Conversation ended")
	is_waiting_for_response = false
