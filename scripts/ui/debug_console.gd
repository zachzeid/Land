extends Control
## Debug console with command input for testing NPC behavior and story progression
## Toggle with backtick (`) key, drag header to move, drag corner to resize
## Now includes real-time gameplay monitoring: conversations, API usage, voice, memories

@onready var console_text = $Panel/VBoxContainer/ConsoleText
@onready var toggle_button = $ToggleButton
@onready var command_input = $Panel/VBoxContainer/CommandInput
@onready var panel = $Panel
@onready var drag_header = $Panel/DragHeader
@onready var resize_handle = $Panel/ResizeHandle
@onready var close_button = $Panel/DragHeader/CloseButton

var is_visible_console = false
var max_lines = 50
var max_lines_memory = 500  # Larger buffer for memory dumps
var console_lines: Array[String] = []
var command_history: Array[String] = []
var history_index: int = -1

# Drag and resize state
var is_dragging: bool = false
var is_resizing: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var min_size: Vector2 = Vector2(400, 250)

# Live tracking state
var current_conversation_npc: String = ""
var conversation_turn_count: int = 0
var last_player_message: String = ""
var last_npc_response: String = ""
var voice_status: String = "idle"
var tracked_npcs: Dictionary = {}  # npc_id -> node reference

func _ready():
	panel.visible = false

	# Connect to EventBus for global events
	if EventBus:
		EventBus.connect("npc_relationship_changed", _on_relationship_changed)
		EventBus.connect("quest_started", _on_quest_started)
		EventBus.connect("quest_completed", _on_quest_completed)

	# Connect to VoiceManager if available
	var voice_manager = get_node_or_null("/root/VoiceManager")
	if voice_manager:
		if voice_manager.has_signal("voice_started"):
			voice_manager.voice_started.connect(_on_voice_started)
		if voice_manager.has_signal("voice_finished"):
			voice_manager.voice_finished.connect(_on_voice_finished)
		if voice_manager.has_signal("voice_error"):
			voice_manager.voice_error.connect(_on_voice_error)

	toggle_button.pressed.connect(_on_toggle_pressed)

	# Connect command input
	if command_input and not command_input.text_submitted.is_connected(_on_command_submitted):
		command_input.text_submitted.connect(_on_command_submitted)

	# Connect drag header
	if drag_header:
		drag_header.gui_input.connect(_on_drag_header_input)

	# Connect resize handle
	if resize_handle:
		resize_handle.gui_input.connect(_on_resize_handle_input)

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_toggle_pressed)

	# Show help on start
	log_message("Debug Console ready. Type 'help' for commands.", Color.GREEN)
	log_message("Live tracking: conversations, API, voice, memories", Color.GRAY)

	# Defer NPC tracking setup to allow scene to fully load
	call_deferred("_setup_npc_tracking")

func _input(event):
	# Toggle with backtick key
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_on_toggle_pressed()
		get_viewport().set_input_as_handled()

	# Handle drag/resize release
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = false
		is_resizing = false

	# Handle drag/resize motion
	if event is InputEventMouseMotion:
		if is_dragging:
			panel.position = get_global_mouse_position() - drag_offset
			_clamp_panel_position()
		elif is_resizing:
			var new_size = get_global_mouse_position() - panel.global_position + Vector2(8, 8)
			panel.size = Vector2(max(new_size.x, min_size.x), max(new_size.y, min_size.y))

	# Command history navigation
	if is_visible_console and command_input and command_input.has_focus():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_UP:
				_navigate_history(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_navigate_history(1)
				get_viewport().set_input_as_handled()

func _navigate_history(direction: int):
	if command_history.is_empty():
		return
	history_index = clamp(history_index + direction, 0, command_history.size() - 1)
	command_input.text = command_history[history_index]
	command_input.caret_column = command_input.text.length()

func _on_toggle_pressed():
	is_visible_console = not is_visible_console
	panel.visible = is_visible_console

	if is_visible_console:
		toggle_button.text = "Console (`)"
		# Focus command input when opening
		if command_input:
			command_input.grab_focus()
	else:
		toggle_button.text = "Console (`)"

func _on_drag_header_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_offset = get_global_mouse_position() - panel.position
		else:
			is_dragging = false

func _on_resize_handle_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_resizing = true
		else:
			is_resizing = false

func _clamp_panel_position():
	# Allow panel to be dragged partially off-screen
	# Keep at least 100px visible horizontally and the header (30px) visible vertically
	var viewport_size = get_viewport_rect().size
	var min_visible_x = 100  # Minimum horizontal visibility
	var min_visible_y = 30   # Keep header visible for dragging back

	# Allow dragging left until only min_visible_x remains on screen
	# Allow dragging right until only min_visible_x remains on screen
	panel.position.x = clamp(panel.position.x, -panel.size.x + min_visible_x, viewport_size.x - min_visible_x)
	# Allow dragging up until header is at top edge
	# Allow dragging down until only header is visible
	panel.position.y = clamp(panel.position.y, 0, viewport_size.y - min_visible_y)

func log_message(message: String, color: Color = Color.WHITE, use_expanded_buffer: bool = false, skip_timestamp: bool = false):
	var formatted: String
	if skip_timestamp:
		formatted = message
	else:
		var timestamp = Time.get_time_string_from_system()
		formatted = "[%s] %s" % [timestamp, message]

	console_lines.append(formatted)

	# Keep only last N lines (use larger buffer for memory dumps)
	var current_max = max_lines_memory if use_expanded_buffer else max_lines
	if console_lines.size() > current_max:
		console_lines.remove_at(0)

	# Update display
	_refresh_console()

func log_analysis(npc_name: String, analysis: Dictionary):
	log_message("=== NPC Analysis: %s ===" % npc_name, Color.YELLOW)
	log_message("  Player Tone: %s" % analysis.get("player_tone", "?"), Color.CYAN)
	log_message("  Emotional Impact: %s" % analysis.get("emotional_impact", "?"), Color.CYAN)
	log_message("  Interaction Type: %s" % analysis.get("interaction_type", "?"), Color.CYAN)
	log_message("  Dimension Changes: T%+d R%+d A%+d F%+d Fam%+d" % [
		analysis.get("trust_change", 0),
		analysis.get("respect_change", 0),
		analysis.get("affection_change", 0),
		analysis.get("fear_change", 0),
		analysis.get("familiarity_change", 0)
	], Color.GREEN)

func log_dimensions(npc_name: String, trust: int, respect: int, affection: int, fear: int, familiarity: int):
	log_message("Current Dimensions [%s]: T:%d R:%d A:%d F:%d Fam:%d" % 
		[npc_name, trust, respect, affection, fear, familiarity], Color.LIGHT_BLUE)

func _refresh_console():
	if not console_text:
		return
	
	console_text.clear()
	
	for line in console_lines:
		console_text.add_text(line + "\n")
	
	# Scroll to bottom
	console_text.scroll_to_line(console_lines.size())

func _on_relationship_changed(event_data: Dictionary):
	var npc_id = event_data.get("npc_id", "unknown")
	var changes = event_data.get("dimension_changes", {})
	var interaction_type = event_data.get("interaction_type", "")

	# Build change string, only show non-zero changes
	var change_parts = []
	if changes.get("trust", 0) != 0:
		change_parts.append("T%+d" % changes.get("trust", 0))
	if changes.get("respect", 0) != 0:
		change_parts.append("R%+d" % changes.get("respect", 0))
	if changes.get("affection", 0) != 0:
		change_parts.append("A%+d" % changes.get("affection", 0))
	if changes.get("fear", 0) != 0:
		change_parts.append("F%+d" % changes.get("fear", 0))
	if changes.get("familiarity", 0) != 0:
		change_parts.append("Fam%+d" % changes.get("familiarity", 0))

	if change_parts.is_empty():
		return  # No actual changes

	var changes_str = " ".join(change_parts)
	var type_str = " (%s)" % interaction_type if not interaction_type.is_empty() else ""

	log_message("❤️ %s%s: %s" % [npc_id, type_str, changes_str], Color.ORANGE)

# =============================================================================
# COMMAND SYSTEM
# =============================================================================

func _on_command_submitted(command_text: String):
	if command_text.strip_edges().is_empty():
		return

	# Add to history
	command_history.append(command_text)
	history_index = command_history.size()

	# Echo command
	log_message("> " + command_text, Color.YELLOW)

	# Clear input
	command_input.clear()

	# Parse and execute
	var parts = command_text.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var cmd = parts[0].to_lower()
	var args = parts.slice(1)

	match cmd:
		"help":
			_cmd_help()
		"list_npcs", "npcs":
			_cmd_list_npcs()
		"show_npc", "npc":
			_cmd_show_npc(args)
		"set_trust":
			_cmd_set_relationship(args, "trust")
		"set_respect":
			_cmd_set_relationship(args, "respect")
		"set_affection":
			_cmd_set_relationship(args, "affection")
		"set_fear":
			_cmd_set_relationship(args, "fear")
		"set_familiarity":
			_cmd_set_relationship(args, "familiarity")
		"set_flag":
			_cmd_set_flag(args)
		"list_flags", "flags":
			_cmd_list_flags()
		"clear":
			_cmd_clear()
		"reset_npc":
			_cmd_reset_npc(args)
		"show_memories", "memories":
			_cmd_show_memories(args)
		"memory_stats":
			_cmd_memory_stats(args)
		"has_met", "met":
			_cmd_has_met(args)
		"status", "s":
			_cmd_status()
		"api":
			_show_api_stats()
		# Quest commands
		"list_quests", "quests":
			_cmd_list_quests()
		"quest_info", "quest":
			_cmd_quest_info(args)
		"quest_start":
			_cmd_quest_start(args)
		"quest_complete":
			_cmd_quest_complete(args)
		"quest_reset":
			_cmd_quest_reset(args)
		"objective_complete":
			_cmd_objective_complete(args)
		"reset_game", "reset_all":
			_cmd_reset_game(args)
		"clear_memories":
			_cmd_clear_memories(args)
		"dump_prompt", "prompt":
			_cmd_dump_prompt(args)
		_:
			log_message("Unknown command: " + cmd, Color.RED)
			log_message("Type 'help' for available commands", Color.GRAY)

func _cmd_help():
	# Helper to log without timestamp for cleaner help output
	var h = func(msg: String, color: Color = Color.WHITE):
		log_message(msg, color, false, true)  # skip_timestamp = true

	log_message("=== Debug Commands ===", Color.CYAN)
	h.call("")
	h.call("NPC Commands:", Color.YELLOW)
	h.call("  list_npcs                   List all NPCs in scene")
	h.call("  show_npc <id>               Show NPC's current state")
	h.call("  set_trust <id> <val>        Set trust (0-100)")
	h.call("  set_respect <id> <val>      Set respect (0-100)")
	h.call("  set_affection <id> <val>    Set affection (0-100)")
	h.call("  set_fear <id> <val>         Set fear (0-100)")
	h.call("  set_familiarity <id> <val>  Set familiarity (0-100)")
	h.call("  reset_npc <id>              Reset NPC to initial state")
	h.call("")
	h.call("Memory Commands:", Color.YELLOW)
	h.call("  show_memories <id> [n]      Show n memories (default 10)")
	h.call("  memory_stats <id>           Show memory statistics")
	h.call("  has_met <id>                Check if player met NPC before")
	h.call("  clear_memories <id>         Clear NPC's memories")
	h.call("")
	h.call("Quest Commands:", Color.YELLOW)
	h.call("  list_quests                 Show all quests by state")
	h.call("  quest_info <id>             Show quest details")
	h.call("  quest_start <id>            Force start a quest")
	h.call("  quest_complete <id> [end]   Force complete quest")
	h.call("  quest_reset <id>            Reset quest state")
	h.call("  objective_complete <q> <o>  Complete objective")
	h.call("")
	h.call("World Commands:", Color.YELLOW)
	h.call("  set_flag <name> <0|1>       Set world flag")
	h.call("  list_flags                  Show all world flags")
	h.call("")
	h.call("Debug Commands:", Color.YELLOW)
	h.call("  dump_prompt <id>            Show full Claude prompt for NPC")
	h.call("  status (s)                  Show live status summary")
	h.call("  api                         Show Claude API token usage")
	h.call("")
	h.call("Reset Commands:", Color.YELLOW)
	h.call("  reset_game confirm          Reset ALL game state")
	h.call("")
	h.call("Other:", Color.YELLOW)
	h.call("  clear                       Clear console")
	h.call("  help                        Show this help")
	h.call("")
	h.call("Auto-logged: conversations, voice, memories, quests", Color.GRAY)

func _cmd_list_npcs():
	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		log_message("No NPCs found in scene", Color.ORANGE)
		return

	log_message("=== NPCs in Scene (%d) ===" % npcs.size(), Color.CYAN)
	for npc in npcs:
		var npc_id = "unknown"
		var display_name = npc.name
		if npc.has_method("get_npc_id"):
			npc_id = npc.get_npc_id()
		elif "npc_id" in npc:
			npc_id = npc.npc_id
		if "display_name" in npc:
			display_name = npc.display_name

		log_message("  %s [%s]" % [display_name, npc_id], Color.WHITE)

func _cmd_show_npc(args: Array):
	if args.is_empty():
		log_message("Usage: show_npc <npc_id>", Color.RED)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name

	log_message("=== %s ===" % display_name, Color.CYAN)

	# Show relationship values
	if "relationship_trust" in npc:
		log_message("  Trust:       %d" % npc.relationship_trust, Color.WHITE)
		log_message("  Respect:     %d" % npc.relationship_respect, Color.WHITE)
		log_message("  Affection:   %d" % npc.relationship_affection, Color.WHITE)
		log_message("  Fear:        %d" % npc.relationship_fear, Color.WHITE)
		log_message("  Familiarity: %d" % npc.relationship_familiarity, Color.WHITE)

	# Show unlockable secrets status if available
	if "personality" in npc and npc.personality:
		var secrets = npc.personality.secrets if "secrets" in npc.personality else []
		if not secrets.is_empty():
			log_message("  Secrets (%d total):" % secrets.size(), Color.YELLOW)
			for secret_data in secrets:
				var trust_needed = secret_data.get("unlock_trust", 0)
				var affection_needed = secret_data.get("unlock_affection", 0)
				var unlocked = npc.relationship_trust >= trust_needed and npc.relationship_affection >= affection_needed
				var status = "[UNLOCKED]" if unlocked else "[locked T>=%d A>=%d]" % [trust_needed, affection_needed]
				var secret_preview = secret_data.get("secret", "").substr(0, 40)
				log_message("    %s %s..." % [status, secret_preview], Color.GRAY if not unlocked else Color.GREEN)

func _cmd_set_relationship(args: Array, dimension: String):
	if args.size() < 2:
		log_message("Usage: set_%s <npc_id> <value>" % dimension, Color.RED)
		return

	var target_id = args[0]
	var value = int(args[1])
	value = clamp(value, 0, 100)

	var npc = _find_npc(target_id)
	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var var_name = "relationship_" + dimension
	if not var_name in npc:
		log_message("NPC doesn't have %s property" % var_name, Color.RED)
		return

	var old_value = npc.get(var_name)
	npc.set(var_name, value)

	var display_name = npc.display_name if "display_name" in npc else npc.name
	log_message("%s %s: %d -> %d" % [display_name, dimension, old_value, value], Color.GREEN)

func _cmd_set_flag(args: Array):
	if args.size() < 2:
		log_message("Usage: set_flag <flag_name> <0|1>", Color.RED)
		log_message("Example: set_flag ledger_found 1", Color.GRAY)
		return

	var flag_name = args[0]
	var value = args[1] == "1" or args[1].to_lower() == "true"

	if WorldState:
		WorldState.set_world_flag(flag_name, value)
		log_message("Flag '%s' = %s" % [flag_name, str(value)], Color.GREEN)
	else:
		log_message("WorldState not available", Color.RED)

func _cmd_list_flags():
	if not WorldState:
		log_message("WorldState not available", Color.RED)
		return

	var set_flags = WorldState.get_flags()

	# Load StoryFlags script directly (ClassDB.class_exists doesn't work for GDScript classes)
	var all_story_flags: Array[String] = []
	var story_flags_script = load("res://scripts/world_state/story_flags.gd")
	if story_flags_script:
		all_story_flags = story_flags_script.get_all_flags()

	log_message("", Color.WHITE)
	log_message("=== World Flags ===", Color.CYAN)

	# Count active flags
	var active_count = 0
	for flag in set_flags:
		if set_flags[flag]:
			active_count += 1

	log_message("  Active: %d | Available: %d" % [active_count, all_story_flags.size()], Color.GRAY)
	log_message("", Color.WHITE)

	# Show set flags first (active ones)
	if active_count > 0:
		log_message("SET FLAGS:", Color.GREEN)
		for flag_name in set_flags:
			if set_flags[flag_name]:
				log_message("  [x] %s" % flag_name, Color.GREEN)
		log_message("", Color.WHITE)

	# Show available flags (not set)
	log_message("AVAILABLE FLAGS (not set):", Color.GRAY)
	for flag_name in all_story_flags:
		if not set_flags.get(flag_name, false):
			log_message("  [ ] %s" % flag_name, Color.DIM_GRAY)

	log_message("", Color.WHITE)
	log_message("Use 'set_flag <name> 1' to set a flag", Color.GRAY)

func _cmd_clear():
	console_lines.clear()
	_refresh_console()
	log_message("Console cleared", Color.GRAY)

func _cmd_reset_npc(args: Array):
	if args.is_empty():
		log_message("Usage: reset_npc <npc_id>", Color.RED)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	# Reset relationship values to defaults
	if "relationship_trust" in npc:
		npc.relationship_trust = 30
		npc.relationship_respect = 30
		npc.relationship_affection = 30
		npc.relationship_fear = 0
		npc.relationship_familiarity = 10

	var display_name = npc.display_name if "display_name" in npc else npc.name
	log_message("%s reset to default values" % display_name, Color.GREEN)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

func _find_npc(target_id: String) -> Node:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		# Check by npc_id property
		if "npc_id" in npc and npc.npc_id == target_id:
			return npc
		# Check by partial match on display name
		if "display_name" in npc and target_id.to_lower() in npc.display_name.to_lower():
			return npc
		# Check by node name
		if target_id.to_lower() in npc.name.to_lower():
			return npc
	return null

func _suggest_npcs():
	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		return
	log_message("Available NPCs:", Color.GRAY)
	for npc in npcs:
		var npc_id = npc.npc_id if "npc_id" in npc else npc.name
		log_message("  - " + npc_id, Color.GRAY)

# =============================================================================
# MEMORY COMMANDS
# =============================================================================

func _cmd_show_memories(args: Array):
	if args.is_empty():
		log_message("Usage: show_memories <npc_id> [limit]", Color.RED)
		log_message("  limit: max memories to show (default: 10)", Color.GRAY)
		return

	var target_id = args[0]
	var limit = 10
	if args.size() > 1 and args[1].is_valid_int():
		limit = int(args[1])

	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name

	# Check if NPC has rag_memory
	if not "rag_memory" in npc or npc.rag_memory == null:
		log_message("NPC %s has no memory system" % display_name, Color.ORANGE)
		return

	# Use expanded buffer for memory dumps (they can be large)
	var mem_buf = true

	log_message("", Color.WHITE, mem_buf)
	log_message("╔══════════════════════════════════════════════════════════════╗", Color.CYAN, mem_buf)
	log_message("║  MEMORIES: %s" % display_name.to_upper(), Color.CYAN, mem_buf)
	log_message("╚══════════════════════════════════════════════════════════════╝", Color.CYAN, mem_buf)

	# Get memories from rag_memory - handle both ChromaDB and in-memory modes
	var rag = npc.rag_memory
	var memories = []

	# Try to get all memories using the proper async method
	if rag.has_method("get_all_memories_raw"):
		memories = await rag.get_all_memories_raw()
	elif "use_chromadb" in rag and rag.use_chromadb:
		# ChromaDB mode - query for all memories
		log_message("  (Querying ChromaDB...)", Color.GRAY, mem_buf)
		var tiered = await rag.retrieve_tiered("memory conversation player")
		for mem in tiered.get("pinned", []):
			memories.append(mem)
		for mem in tiered.get("important", []):
			memories.append(mem)
		for mem in tiered.get("relevant", []):
			memories.append(mem)
	elif "memory_cache" in rag:
		# In-memory mode fallback
		memories = rag.memory_cache.duplicate()

	if memories.is_empty():
		log_message("  No memories stored yet.", Color.ORANGE, mem_buf)
		log_message("  (This NPC hasn't had any conversations with the player)", Color.GRAY, mem_buf)
		return

	# Sort by timestamp (newest first)
	memories.sort_custom(func(a, b):
		var time_a = a.get("metadata", {}).get("timestamp", 0)
		var time_b = b.get("metadata", {}).get("timestamp", 0)
		return time_a > time_b
	)

	var total = memories.size()
	var showing = min(limit, total)

	log_message("  Total: %d memories | Showing: %d (newest first)" % [total, showing], Color.GRAY, mem_buf)
	log_message("", Color.WHITE, mem_buf)

	for i in range(showing):
		var mem = memories[i]
		var text = mem.get("document", mem.get("text", "[no text]"))
		var meta = mem.get("metadata", {})

		# Extract metadata
		var event_type = meta.get("event_type", "unknown")
		var importance = meta.get("importance", 5)
		var timestamp = meta.get("timestamp", 0)
		var topics = meta.get("topics", [])
		var intent = meta.get("intent", "")
		var player_input = meta.get("player_input", "")

		# Format timestamp
		var time_str = "unknown"
		if timestamp > 0:
			var dt = Time.get_datetime_dict_from_unix_time(int(timestamp))
			time_str = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

		# Importance indicator
		var imp_color = Color.GRAY
		var imp_label = "LOW"
		if importance >= 8:
			imp_color = Color.RED
			imp_label = "HIGH"
		elif importance >= 5:
			imp_color = Color.YELLOW
			imp_label = "MED"

		# Memory header
		log_message("┌─ Memory #%d ─────────────────────────────────────────────────" % (i + 1), Color.DIM_GRAY, mem_buf)
		log_message("│ Time: %s  |  Type: %s  |  Importance: %s (%d)" % [time_str, event_type.to_upper(), imp_label, importance], imp_color, mem_buf)

		# Topics if present
		if topics is Array and topics.size() > 0:
			var topics_str = ", ".join(topics)
			log_message("│ Topics: %s" % topics_str, Color.MEDIUM_PURPLE, mem_buf)
		elif topics is String and not topics.is_empty():
			log_message("│ Topics: %s" % topics, Color.MEDIUM_PURPLE, mem_buf)

		# Intent if present
		if not intent.is_empty():
			log_message("│ Intent: %s" % intent, Color.DODGER_BLUE, mem_buf)

		# Player said (if available)
		if not player_input.is_empty():
			var player_short = player_input.substr(0, 60)
			if player_input.length() > 60:
				player_short += "..."
			log_message("│ Player: \"%s\"" % player_short, Color.GREEN, mem_buf)

		# Memory content
		log_message("│", Color.DIM_GRAY, mem_buf)
		# Word wrap the memory text
		var wrapped = _wrap_text(text, 60)
		for line in wrapped:
			log_message("│ %s" % line, Color.WHITE, mem_buf)

		log_message("└──────────────────────────────────────────────────────────────", Color.DIM_GRAY, mem_buf)
		log_message("", Color.WHITE, mem_buf)

	if total > showing:
		log_message("  ... and %d more memories. Use 'show_memories %s %d' to see more." % [total - showing, target_id, total], Color.GRAY, mem_buf)

## Helper to wrap text at specified width
func _wrap_text(text: String, width: int) -> Array:
	var lines = []
	var words = text.split(" ")
	var current_line = ""

	for word in words:
		if current_line.length() + word.length() + 1 <= width:
			if current_line.is_empty():
				current_line = word
			else:
				current_line += " " + word
		else:
			if not current_line.is_empty():
				lines.append(current_line)
			current_line = word

	if not current_line.is_empty():
		lines.append(current_line)

	if lines.is_empty():
		lines.append(text)

	return lines

func _cmd_has_met(args: Array):
	if args.is_empty():
		log_message("Usage: has_met <npc_id>", Color.RED)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name
	var mem_buf = true  # Use expanded buffer

	log_message("", Color.WHITE, mem_buf)
	log_message("╔══════════════════════════════════════════════════════════════╗", Color.CYAN, mem_buf)
	log_message("║  MEETING STATUS: %s" % display_name.to_upper(), Color.CYAN, mem_buf)
	log_message("╚══════════════════════════════════════════════════════════════╝", Color.CYAN, mem_buf)

	# Check familiarity (relationship stat that tracks how well they know you)
	var familiarity = 0.0
	if "familiarity" in npc:
		familiarity = npc.familiarity

	# Check memory count - handle both ChromaDB and in-memory modes
	var memory_count = 0
	var first_memory_time = ""
	var last_memory_time = ""

	if "rag_memory" in npc and npc.rag_memory != null:
		var rag = npc.rag_memory
		var memories = []

		# Get memories from appropriate storage
		if "use_chromadb" in rag and rag.use_chromadb:
			log_message("  (Checking ChromaDB...)", Color.GRAY, mem_buf)
			var tiered = await rag.retrieve_tiered("memory conversation player")
			for mem in tiered.get("pinned", []):
				memories.append(mem)
			for mem in tiered.get("important", []):
				memories.append(mem)
			for mem in tiered.get("relevant", []):
				memories.append(mem)
		elif "memory_cache" in rag:
			memories = rag.memory_cache

		memory_count = memories.size()

		if memory_count > 0:
			# Find earliest and latest timestamps
			var earliest_ts = INF
			var latest_ts = 0
			for mem in memories:
				var ts = mem.get("metadata", {}).get("timestamp", 0)
				if ts > 0:
					if ts < earliest_ts:
						earliest_ts = ts
					if ts > latest_ts:
						latest_ts = ts
			if earliest_ts < INF:
				var dt = Time.get_datetime_dict_from_unix_time(int(earliest_ts))
				first_memory_time = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]
			if latest_ts > 0:
				var dt = Time.get_datetime_dict_from_unix_time(int(latest_ts))
				last_memory_time = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

	# Determine meeting status
	var has_met_before = memory_count > 0 or familiarity > 10

	if has_met_before:
		log_message("  Player HAS talked to %s before" % display_name, Color.GREEN, mem_buf)
		log_message("", Color.WHITE, mem_buf)
		log_message("  Conversations recorded: %d" % memory_count, Color.WHITE, mem_buf)
		if not first_memory_time.is_empty():
			log_message("  First interaction: %s" % first_memory_time, Color.GRAY, mem_buf)
		if not last_memory_time.is_empty():
			log_message("  Last interaction: %s" % last_memory_time, Color.GRAY, mem_buf)
		log_message("  Familiarity level: %.1f" % familiarity, Color.WHITE, mem_buf)
	else:
		log_message("  Player has NEVER talked to %s" % display_name, Color.RED, mem_buf)
		log_message("", Color.WHITE, mem_buf)
		log_message("  This is a FIRST MEETING - NPC should NOT reference:", Color.ORANGE, mem_buf)
		log_message("    - Prior conversations", Color.GRAY, mem_buf)
		log_message("    - \"What we discussed\"", Color.GRAY, mem_buf)
		log_message("    - \"Good to see you again\"", Color.GRAY, mem_buf)
		log_message("    - Any past shared experiences", Color.GRAY, mem_buf)
		log_message("", Color.WHITE, mem_buf)
		log_message("  Familiarity: %.1f (should be 0 for strangers)" % familiarity, Color.WHITE, mem_buf)

	log_message("", Color.WHITE, mem_buf)

func _cmd_memory_stats(args: Array):
	if args.is_empty():
		log_message("Usage: memory_stats <npc_id>", Color.RED)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name

	# Check if NPC has rag_memory
	if not "rag_memory" in npc or npc.rag_memory == null:
		log_message("NPC %s has no memory system" % display_name, Color.ORANGE)
		return

	log_message("=== Memory Stats for %s ===" % display_name, Color.CYAN)

	# Use get_memory_stats method if available
	if npc.has_method("get_memory_stats"):
		var stats = await npc.get_memory_stats()
		if stats:
			log_message("  Total: %d" % stats.get("total", 0), Color.WHITE)
			log_message("  Pinned: %d" % stats.get("pinned", 0), Color.GREEN)
			log_message("  Important: %d" % stats.get("important", 0), Color.YELLOW)
			log_message("  Regular: %d" % stats.get("regular", 0), Color.GRAY)

			var by_type = stats.get("by_type", {})
			if by_type.size() > 0:
				log_message("  By Type:", Color.WHITE)
				for event_type in by_type:
					log_message("    %s: %d" % [event_type, by_type[event_type]], Color.GRAY)
	else:
		# Fallback: Access rag_memory directly
		var rag = npc.rag_memory
		if rag.has_method("get_memory_stats"):
			var stats = await rag.get_memory_stats()
			log_message("  Total: %d" % stats.get("total", 0), Color.WHITE)
			log_message("  Pinned: %d" % stats.get("pinned", 0), Color.GREEN)
			log_message("  Important: %d" % stats.get("important", 0), Color.YELLOW)
			log_message("  Regular: %d" % stats.get("regular", 0), Color.GRAY)
		elif "memory_cache" in rag:
			log_message("  Total memories: %d" % rag.memory_cache.size(), Color.WHITE)
		else:
			log_message("Could not retrieve memory stats", Color.ORANGE)

# =============================================================================
# LIVE TRACKING SYSTEM
# =============================================================================

## Setup NPC tracking - connect to dialogue signals on all NPCs
func _setup_npc_tracking():
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		_track_npc(npc)

	# Also watch for new NPCs added to the scene
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	# Check if newly added node is an NPC
	if node.is_in_group("npcs"):
		call_deferred("_track_npc", node)

func _track_npc(npc: Node):
	var npc_id = npc.npc_id if "npc_id" in npc else npc.name

	if tracked_npcs.has(npc_id):
		return  # Already tracking

	tracked_npcs[npc_id] = npc

	# Connect to NPC's dialogue signals
	if npc.has_signal("dialogue_started"):
		npc.dialogue_started.connect(_on_npc_dialogue_started)
	if npc.has_signal("dialogue_response_ready"):
		npc.dialogue_response_ready.connect(_on_npc_dialogue_response)
	if npc.has_signal("dialogue_ended"):
		npc.dialogue_ended.connect(_on_npc_dialogue_ended)

	# Connect to memory signals if NPC has rag_memory
	if "rag_memory" in npc and npc.rag_memory:
		var rag = npc.rag_memory
		if rag.has_signal("memory_added"):
			rag.memory_added.connect(_on_memory_added.bind(npc_id))
		if rag.has_signal("memories_recalled"):
			rag.memories_recalled.connect(_on_memories_recalled.bind(npc_id))
		if rag.has_signal("milestone_created"):
			rag.milestone_created.connect(_on_milestone_created.bind(npc_id))

# =============================================================================
# CONVERSATION EVENT HANDLERS
# =============================================================================

func _on_npc_dialogue_started(npc_id: String):
	current_conversation_npc = npc_id
	conversation_turn_count = 0
	log_message("💬 CONVERSATION STARTED: %s" % npc_id, Color.CYAN)

func _on_npc_dialogue_response(npc_id: String, response: String):
	conversation_turn_count += 1
	last_npc_response = response

	# Truncate for display
	var preview = response.substr(0, 60) + "..." if response.length() > 60 else response
	log_message("  [Turn %d] %s: %s" % [conversation_turn_count, npc_id, preview], Color.WHITE)

func _on_npc_dialogue_ended(npc_id: String):
	log_message("💬 CONVERSATION ENDED: %s (%d turns)" % [npc_id, conversation_turn_count], Color.CYAN)

	# Show Claude API stats if available
	_show_api_stats()

	current_conversation_npc = ""
	conversation_turn_count = 0

# =============================================================================
# VOICE EVENT HANDLERS
# =============================================================================

func _on_voice_started(npc_id: String):
	voice_status = "playing"
	log_message("🔊 Voice: %s speaking..." % npc_id, Color.LIGHT_BLUE)

func _on_voice_finished(npc_id: String):
	voice_status = "idle"
	log_message("🔊 Voice: %s finished" % npc_id, Color.GRAY)

func _on_voice_error(npc_id: String, error: String):
	voice_status = "error"
	log_message("🔊 Voice ERROR [%s]: %s" % [npc_id, error], Color.RED)

# =============================================================================
# MEMORY EVENT HANDLERS
# =============================================================================

func _on_memory_added(memory_id: String, npc_id: String):
	log_message("🧠 Memory stored [%s]: %s" % [npc_id, memory_id.substr(0, 40)], Color.PURPLE)

func _on_memories_recalled(count: int, npc_id: String):
	log_message("🧠 Memories recalled [%s]: %d memories" % [npc_id, count], Color.PURPLE)

func _on_milestone_created(milestone_type: String, npc_id: String):
	log_message("⭐ MILESTONE [%s]: %s" % [npc_id, milestone_type], Color.YELLOW)

# =============================================================================
# QUEST EVENT HANDLERS
# =============================================================================

func _on_quest_started(quest_id: String, quest_data: Dictionary):
	log_message("📜 Quest STARTED: %s" % quest_id, Color.GREEN)

func _on_quest_completed(quest_id: String, npc_id: String, outcome: String):
	log_message("📜 Quest COMPLETED: %s (%s)" % [quest_id, outcome], Color.GREEN)

# =============================================================================
# API STATS DISPLAY
# =============================================================================

func _show_api_stats():
	var claude_client = get_node_or_null("/root/ClaudeClient")
	if not claude_client:
		# Try to find it via autoload name
		if has_node("/root/ClaudeClient"):
			claude_client = get_node("/root/ClaudeClient")

	if claude_client and claude_client.has_method("get_usage_stats"):
		var stats = claude_client.get_usage_stats()
		log_message("📊 API: %d in / %d out tokens ($%.4f)" % [
			stats.get("total_input_tokens", 0),
			stats.get("total_output_tokens", 0),
			stats.get("estimated_cost_usd", 0.0)
		], Color.ORANGE)

# =============================================================================
# STATUS COMMAND
# =============================================================================

func _cmd_status():
	log_message("=== Live Status ===", Color.CYAN)

	# Conversation status
	if current_conversation_npc.is_empty():
		log_message("  Conversation: None active", Color.GRAY)
	else:
		log_message("  Conversation: %s (turn %d)" % [current_conversation_npc, conversation_turn_count], Color.WHITE)

	# Voice status
	log_message("  Voice: %s" % voice_status, Color.WHITE)

	# API stats
	_show_api_stats()

	# NPC count
	log_message("  Tracked NPCs: %d" % tracked_npcs.size(), Color.WHITE)

	# World flags count
	if WorldState:
		var flags = WorldState.get_flags()
		var active_count = 0
		for flag in flags:
			if flags[flag]:
				active_count += 1
		log_message("  World flags: %d active" % active_count, Color.WHITE)

	# Active quests (use QuestManager if available)
	if QuestManager:
		log_message("  Available quests: %d" % QuestManager.get_available_quest_ids().size(), Color.WHITE)
		log_message("  Active quests: %d" % QuestManager.get_active_quest_ids().size(), Color.WHITE)
		log_message("  Completed quests: %d" % QuestManager.get_completed_quest_ids().size(), Color.WHITE)
	elif WorldState:
		var quests = WorldState.get_active_quests()
		log_message("  Active quests: %d" % quests.size(), Color.WHITE)

# =============================================================================
# QUEST COMMANDS
# =============================================================================

func _cmd_list_quests():
	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var all_quests = QuestManager.get_all_quests()
	if all_quests.is_empty():
		log_message("No quests defined", Color.ORANGE)
		return

	log_message("=== Quests ===", Color.CYAN)

	# Available
	var available = QuestManager.get_available_quest_ids()
	if not available.is_empty():
		log_message("Available (%d):" % available.size(), Color.GREEN)
		for quest_id in available:
			var quest = QuestManager.get_quest(quest_id)
			log_message("  [%s] %s" % [quest_id, quest.title], Color.GREEN)

	# Active
	var active = QuestManager.get_active_quest_ids()
	if not active.is_empty():
		log_message("Active (%d):" % active.size(), Color.YELLOW)
		for quest_id in active:
			var quest = QuestManager.get_quest(quest_id)
			var progress = quest.get_progress() * 100
			log_message("  [%s] %s (%.0f%%)" % [quest_id, quest.title, progress], Color.YELLOW)

	# Completed
	var completed = QuestManager.get_completed_quest_ids()
	if not completed.is_empty():
		log_message("Completed (%d):" % completed.size(), Color.GRAY)
		for quest_id in completed:
			var quest = QuestManager.get_quest(quest_id)
			log_message("  [%s] %s" % [quest_id, quest.title], Color.GRAY)

	# Unavailable (not shown but counted)
	var unavailable_count = all_quests.size() - available.size() - active.size() - completed.size()
	if unavailable_count > 0:
		log_message("Unavailable: %d (conditions not met)" % unavailable_count, Color.DARK_GRAY)

func _cmd_quest_info(args: Array):
	if args.is_empty():
		log_message("Usage: quest_info <quest_id>", Color.RED)
		return

	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var quest_id = args[0]
	var quest = QuestManager.get_quest(quest_id)

	if not quest:
		log_message("Quest not found: %s" % quest_id, Color.RED)
		_suggest_quests()
		return

	log_message("=== Quest: %s ===" % quest.title, Color.CYAN)
	log_message("  ID: %s" % quest.quest_id, Color.WHITE)
	log_message("  Description: %s" % quest.description, Color.WHITE)

	# State
	var state_names = ["UNAVAILABLE", "AVAILABLE", "ACTIVE", "COMPLETED", "FAILED"]
	var state_colors = [Color.DARK_GRAY, Color.GREEN, Color.YELLOW, Color.CYAN, Color.RED]
	log_message("  State: %s" % state_names[quest.state], state_colors[quest.state])

	# Progress
	if quest.is_active():
		log_message("  Progress: %.0f%%" % (quest.get_progress() * 100), Color.WHITE)

	# Objectives
	if not quest.objectives.is_empty():
		log_message("  Objectives:", Color.WHITE)
		for obj in quest.objectives:
			var status = "[x]" if obj.is_completed else "[ ]"
			var opt = " (optional)" if obj.optional else ""
			var color = Color.GREEN if obj.is_completed else Color.GRAY
			log_message("    %s %s%s" % [status, obj.description, opt], color)

	# Requirements
	if not quest.required_flags.is_empty():
		log_message("  Required flags: %s" % ", ".join(quest.required_flags), Color.GRAY)
	if not quest.required_quests.is_empty():
		log_message("  Required quests: %s" % ", ".join(quest.required_quests), Color.GRAY)

func _cmd_quest_start(args: Array):
	if args.is_empty():
		log_message("Usage: quest_start <quest_id>", Color.RED)
		return

	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var quest_id = args[0]
	QuestManager.force_start_quest(quest_id)
	log_message("Quest force-started: %s" % quest_id, Color.GREEN)

func _cmd_quest_complete(args: Array):
	if args.is_empty():
		log_message("Usage: quest_complete <quest_id> [ending]", Color.RED)
		return

	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var quest_id = args[0]
	var ending = args[1] if args.size() > 1 else "debug"

	QuestManager.force_complete_quest(quest_id, ending)
	log_message("Quest force-completed: %s (ending: %s)" % [quest_id, ending], Color.GREEN)

func _cmd_quest_reset(args: Array):
	if args.is_empty():
		log_message("Usage: quest_reset <quest_id>", Color.RED)
		return

	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var quest_id = args[0]
	QuestManager.reset_quest(quest_id)
	log_message("Quest reset: %s" % quest_id, Color.GREEN)

func _cmd_objective_complete(args: Array):
	if args.size() < 2:
		log_message("Usage: objective_complete <quest_id> <objective_id>", Color.RED)
		return

	if not QuestManager:
		log_message("QuestManager not available", Color.RED)
		return

	var quest_id = args[0]
	var objective_id = args[1]

	QuestManager.force_complete_objective(quest_id, objective_id)
	log_message("Objective completed: %s/%s" % [quest_id, objective_id], Color.GREEN)

func _suggest_quests():
	if not QuestManager:
		return

	var all_quests = QuestManager.get_all_quests()
	if all_quests.is_empty():
		log_message("No quests defined", Color.GRAY)
		return

	log_message("Available quest IDs:", Color.GRAY)
	for quest_id in all_quests:
		log_message("  - %s" % quest_id, Color.GRAY)

# =============================================================================
# RESET COMMANDS
# =============================================================================

func _cmd_reset_game(args: Array):
	# Require confirmation to prevent accidental resets
	if args.is_empty() or args[0] != "confirm":
		log_message("", Color.WHITE)
		log_message("╔══════════════════════════════════════════════════════════════╗", Color.RED)
		log_message("║  WARNING: This will reset ALL game state!                    ║", Color.RED)
		log_message("╚══════════════════════════════════════════════════════════════╝", Color.RED)
		log_message("", Color.WHITE)
		log_message("  This will clear:", Color.ORANGE)
		log_message("    - All NPC relationships (trust, affection, etc.)", Color.GRAY)
		log_message("    - All NPC memories (conversations, events)", Color.GRAY)
		log_message("    - All world flags", Color.GRAY)
		log_message("    - All quest progress", Color.GRAY)
		log_message("", Color.WHITE)
		log_message("  Type 'reset_game confirm' to proceed", Color.YELLOW)
		return

	log_message("", Color.WHITE)
	log_message("Resetting game state...", Color.YELLOW)

	var npcs_reset = 0
	var memories_cleared = 0
	var flags_cleared = 0
	var quests_reset = 0

	# Reset all NPCs in current scene (relationships only)
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		# Reset relationship values
		if "relationship_trust" in npc:
			npc.relationship_trust = 30
			npc.relationship_respect = 30
			npc.relationship_affection = 30
			npc.relationship_fear = 0
			npc.relationship_familiarity = 0
			npcs_reset += 1

		# Clear local memory cache
		if "rag_memory" in npc and npc.rag_memory != null:
			var rag = npc.rag_memory
			if "memory_cache" in rag:
				rag.memory_cache.clear()

	# Clear ALL NPC memories from ChromaDB (including NPCs in other scenes)
	var chroma = preload("res://scripts/memory/chroma_client.gd").new()
	add_child(chroma)  # Need to add to tree for signals to work
	var collections = chroma.list_collections()
	log_message("  Found %d ChromaDB collections" % collections.size(), Color.GRAY)
	for collection_name in collections:
		if collection_name.begins_with("npc_"):
			chroma.delete_collection(collection_name)
			memories_cleared += 1
			log_message("    Deleted: %s" % collection_name, Color.GRAY)
	chroma.queue_free()

	# Clear world flags
	if WorldState:
		var flags = WorldState.get_flags()
		for flag_name in flags.keys():
			WorldState.set_world_flag(flag_name, false)
			flags_cleared += 1

		# Clear quest tracking in WorldState
		if "active_quests" in WorldState:
			WorldState.active_quests.clear()
		if "completed_quests" in WorldState:
			WorldState.completed_quests.clear()

	# Reset all quests
	if QuestManager:
		var all_quests = QuestManager.get_all_quests()
		for quest_id in all_quests:
			QuestManager.reset_quest(quest_id)
			quests_reset += 1

	# Delete the save file to prevent auto-load restoring state
	var save_deleted = false
	var save_path = "user://game_save.json"
	if FileAccess.file_exists(save_path):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove("game_save.json")
			save_deleted = true
			log_message("  Deleted save file", Color.GRAY)

	log_message("", Color.WHITE)
	log_message("╔══════════════════════════════════════════════════════════════╗", Color.GREEN)
	log_message("║  GAME STATE RESET COMPLETE                                   ║", Color.GREEN)
	log_message("╚══════════════════════════════════════════════════════════════╝", Color.GREEN)
	log_message("", Color.WHITE)
	log_message("  NPCs reset: %d (current scene)" % npcs_reset, Color.WHITE)
	log_message("  Memory collections deleted: %d" % memories_cleared, Color.WHITE)
	log_message("  Flags cleared: %d" % flags_cleared, Color.WHITE)
	log_message("  Quests reset: %d" % quests_reset, Color.WHITE)
	if save_deleted:
		log_message("  Save file deleted: Yes", Color.WHITE)
	log_message("", Color.WHITE)
	log_message("  Game is now in initial state. All NPCs are strangers.", Color.GRAY)
	log_message("  Reloading game in 1 second...", Color.YELLOW)

	# Close the console and reload the scene
	await get_tree().create_timer(1.0).timeout
	_on_toggle_pressed()  # Close console before reload
	get_tree().reload_current_scene()

func _cmd_clear_memories(args: Array):
	if args.is_empty():
		log_message("Usage: clear_memories <npc_id>", Color.RED)
		log_message("  Clears all memories for a specific NPC", Color.GRAY)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name

	if not "rag_memory" in npc or npc.rag_memory == null:
		log_message("NPC %s has no memory system" % display_name, Color.ORANGE)
		return

	var rag = npc.rag_memory
	var cleared = false

	if rag.has_method("clear_all_memories"):
		await rag.clear_all_memories()
		cleared = true
	elif "memory_cache" in rag:
		rag.memory_cache.clear()
		cleared = true

	if cleared:
		# Also reset familiarity since they've "forgotten" the player
		if "relationship_familiarity" in npc:
			npc.relationship_familiarity = 0

		log_message("Cleared all memories for %s" % display_name, Color.GREEN)
		log_message("  Familiarity reset to 0 (stranger)", Color.GRAY)
	else:
		log_message("Could not clear memories for %s" % display_name, Color.RED)

func _cmd_dump_prompt(args: Array):
	if args.is_empty():
		log_message("Usage: dump_prompt <npc_id>", Color.RED)
		log_message("  Shows the full system prompt sent to Claude for an NPC", Color.GRAY)
		return

	var target_id = args[0]
	var npc = _find_npc(target_id)

	if not npc:
		log_message("NPC not found: " + target_id, Color.RED)
		_suggest_npcs()
		return

	var display_name = npc.display_name if "display_name" in npc else npc.name
	log_message("=== PROMPT FOR %s ===" % display_name.to_upper(), Color.CYAN)

	# Get personality (check both property names)
	var personality = null
	if "personality_resource" in npc and npc.personality_resource != null:
		personality = npc.personality_resource
	elif "personality" in npc and npc.personality != null:
		personality = npc.personality

	if not personality:
		log_message("No personality resource found for this NPC", Color.RED)
		log_message("Check that personality_resource is assigned in the scene", Color.GRAY)
		return

	# Build relationship dimensions
	var dimensions = {
		"trust": npc.relationship_trust if "relationship_trust" in npc else 0,
		"respect": npc.relationship_respect if "relationship_respect" in npc else 0,
		"affection": npc.relationship_affection if "relationship_affection" in npc else 0,
		"fear": npc.relationship_fear if "relationship_fear" in npc else 0,
		"familiarity": npc.relationship_familiarity if "relationship_familiarity" in npc else 0,
		"memory_count": 0
	}

	# Get memories if available
	var tiered_memories = {"pinned": [], "important": [], "relevant": []}
	if "rag_memory" in npc and npc.rag_memory:
		tiered_memories = npc.rag_memory.get_tiered_memories("test query") if npc.rag_memory.has_method("get_tiered_memories") else tiered_memories

	# Build world state
	var world_state = {}
	if WorldState:
		world_state = {
			"world_flags": WorldState.world_flags if "world_flags" in WorldState else {},
			"active_quests": WorldState.active_quests if "active_quests" in WorldState else [],
			"npc_id": npc.npc_id if "npc_id" in npc else ""
		}

	# Use ContextBuilder to build the prompt
	var context_builder = preload("res://scripts/dialogue/context_builder.gd").new()
	var context = context_builder.build_context({
		"personality": personality,
		"npc_id": npc.npc_id if "npc_id" in npc else "",
		"tiered_memories": tiered_memories,
		"relationship_dimensions": dimensions,
		"world_state": world_state,
		"conversation_history": [],
		"player_input": "(Debug prompt dump)"
	})

	# Output the system prompt
	var prompt = context.get("system_prompt", "No prompt generated")

	# Split into lines and output with line limit per message
	log_message("--- SYSTEM PROMPT START ---", Color.YELLOW)
	var lines = prompt.split("\n")
	for line in lines:
		# Truncate very long lines, skip timestamps for cleaner output
		if line.length() > 500:
			log_message(line.substr(0, 500) + "...", Color.WHITE, false, true)
		else:
			log_message(line, Color.WHITE, false, true)
	log_message("--- SYSTEM PROMPT END ---", Color.YELLOW, false, true)
	log_message("Total length: %d characters (~%d tokens)" % [prompt.length(), prompt.length() / 4], Color.GRAY, false, true)
