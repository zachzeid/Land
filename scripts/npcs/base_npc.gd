extends CharacterBody2D
const LlmTelemetry = preload("res://scripts/core/llm_telemetry.gd")
# BaseNPC - Foundation class for AI-driven NPCs
# Combines personality, memory (RAG), and Claude dialogue into character AI agent
# Now supports structured NPCPersonality resources for consistent character behavior

## Signals
signal dialogue_started(npc_id: String)
signal dialogue_response_ready(npc_id: String, response: String)
signal dialogue_ended(npc_id: String)

## NPC Identity
@export var npc_id: String = ""
@export var npc_name: String = "NPC"
@export var personality_resource_path: String = ""  # Path to .tres with system prompt (legacy)
@export var personality_resource: Resource = null   # NEW: Structured NPCPersonality resource

## Visual Appearance (for AI asset generation)
@export_multiline var appearance_prompt: String = ""  # Describes how NPC looks for image generation

## Location System
@export var home_location: String = ""  # Location ID where NPC spawns/lives
var current_location: String = ""        # Where NPC currently is (can change with schedules)

## NPC State
var is_alive: bool = true
var death_cause: String = ""
var killed_by: String = ""  # Who killed the NPC (player, bandit, guard, etc.)
var death_timestamp: float = 0.0

## Multi-Dimensional Relationship Tracking
# NPCs evolve across multiple axes based on player interactions
var relationship_trust: float = 0.0       # -100 to 100: Reliability, honesty, promise-keeping
var relationship_respect: float = 0.0     # -100 to 100: Admiration for capabilities
var relationship_affection: float = 0.0   # -100 to 100: Personal liking (platonic/romantic)
var relationship_fear: float = 0.0        # -100 to 100: Intimidation, wariness
var relationship_familiarity: float = 0.0 # 0 to 100: How well they know the player

## Legacy single score (calculated from dimensions for backward compatibility)
var relationship_status: float = 0.0

## Cross-NPC Awareness System
# Automatically tracks other NPCs this NPC knows about
# {npc_id: {type: "family"|"friend"|"enemy"|"acquaintance", importance: int, last_interaction: float}}
var known_npcs: Dictionary = {}
const MAX_KNOWN_NPCS: int = 50  # Limit to prevent performance issues

## Conversation state
var is_in_conversation: bool = false
var current_conversation_history: Array = []

## AI Components
var rag_memory: Node  # RAGMemory instance
var context_builder: Node  # ContextBuilder instance
var claude_client: Node  # ClaudeClient instance

## KPI Tracking (optional)
var kpi_tracker: Node = null  # PersonalityKPITracker instance

## System prompt loaded from personality resource
var system_prompt: String = ""

## Initialization state tracking
var _is_initialized: bool = false
var _is_initializing: bool = false

func _ready():
	# Don't auto-initialize in _ready for NPCs created in code
	# Call initialize() manually after creation
	pass

## Initialize NPC manually (call this after creating NPC in code)
## use_chromadb: Whether to use ChromaDB or in-memory storage
## enable_kpi_tracking: Whether to track personality consistency KPIs
func initialize(use_chromadb: bool = true, enable_kpi_tracking: bool = false) -> bool:
	# Prevent double initialization
	if _is_initialized:
		print("[%s] Already initialized, skipping" % npc_name)
		return true
	if _is_initializing:
		print("[%s] Initialization already in progress, waiting..." % npc_name)
		# Wait for initialization to complete
		while _is_initializing:
			await get_tree().process_frame
		return _is_initialized

	_is_initializing = true
	print("[%s] Initializing NPC..." % npc_name)

	# Initialize AI components first
	_setup_ai_components()

	# Load personality from structured resource (preferred) or legacy path
	if personality_resource != null:
		_load_structured_personality()
	elif personality_resource_path != "":
		_load_personality()

	# Initialize KPI tracking if enabled
	if enable_kpi_tracking:
		_setup_kpi_tracking()
	
	# Initialize RAG memory for this NPC
	if rag_memory:
		if use_chromadb:
			print("[%s] Initializing RAG memory with ChromaDB..." % npc_name)
		else:
			print("[%s] Initializing RAG memory in-memory mode (no persistence)..." % npc_name)
		
		var result = await rag_memory.initialize(npc_id, null, use_chromadb)
		if result:
			print("[%s] RAG memory initialized successfully" % npc_name)
		else:
			push_warning("[%s] RAG memory initialization failed - continuing without memory" % npc_name)
			_is_initializing = false
			return false
	
	# Check if NPC should be dead (load from ChromaDB)
	await _load_death_state_from_chroma()
	
	# If dead, hide NPC and skip further initialization
	if not is_alive:
		print("[%s] NPC is dead, hiding from world" % npc_name)
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		_is_initialized = true
		_is_initializing = false
		return true  # Initialization successful, just dead
	
	# Connect interaction area signals if they exist
	if has_node("InteractionArea"):
		var interaction_area = get_node("InteractionArea")
		if not interaction_area.body_entered.is_connected(_on_interaction_area_body_entered):
			interaction_area.body_entered.connect(_on_interaction_area_body_entered)
		if not interaction_area.body_exited.is_connected(_on_interaction_area_body_exited):
			interaction_area.body_exited.connect(_on_interaction_area_body_exited)
		print("[%s] Interaction area signals connected" % npc_name)
	else:
		push_warning("[%s] No InteractionArea node found - NPC won't be interactable" % npc_name)
	
	# Discover nearby NPCs automatically (proximity-based relationships)
	await _discover_nearby_npcs()
	
	# Check states of known NPCs (async)
	await _check_known_npc_states()

	_is_initialized = true
	_is_initializing = false
	print("%s ready (ID: %s)" % [npc_name, npc_id])

	# Feelings toward the player persist (and fade per day apart) in the shared relationship ledger
	var ledger = _relationship_ledger()
	if ledger:
		ledger.apply_to_npc(self)

	# Learn any story events that reached this NPC while it wasn't loaded
	var propagator = get_node_or_null("/root/EventPropagator")
	if propagator:
		propagator.deliver_pending(self)
	# And any feelings storyline NPCs changed while it wasn't loaded
	var director = get_node_or_null("/root/StorylineDirector")
	if director:
		director.deliver_pending(self)
	return true

## Setup AI component instances
func _setup_ai_components():
	# Load and instantiate RAGMemory
	var RAGMemoryScript = load("res://scripts/npcs/rag_memory.gd")
	rag_memory = RAGMemoryScript.new()
	add_child(rag_memory)
	
	# Load and instantiate ContextBuilder
	var ContextBuilderScript = load("res://scripts/dialogue/context_builder.gd")
	context_builder = ContextBuilderScript.new()
	add_child(context_builder)
	
	# Load and instantiate ClaudeClient
	var ClaudeClientScript = load("res://scripts/dialogue/claude_client.gd")
	claude_client = ClaudeClientScript.new()
	add_child(claude_client)

## Load personality from resource file (legacy)
func _load_personality():
	if not ResourceLoader.exists(personality_resource_path):
		push_error("Personality resource not found: %s" % personality_resource_path)
		return

	var resource = load(personality_resource_path)
	if resource and resource.has("system_prompt"):
		system_prompt = resource.system_prompt
		print("%s personality loaded (legacy)" % npc_name)
	else:
		push_error("Invalid personality resource format")

## Load personality from structured NPCPersonality resource (preferred)
func _load_structured_personality():
	if personality_resource == null:
		push_error("No personality resource assigned")
		return

	# Extract key info from structured resource
	if personality_resource.npc_id != "":
		npc_id = personality_resource.npc_id
	if personality_resource.display_name != "":
		npc_name = personality_resource.display_name

	# Generate system prompt from structured data
	system_prompt = personality_resource.generate_system_prompt()

	print("[%s] Structured personality loaded (ID: %s)" % [npc_name, npc_id])
	print("  - Identity anchors: %d" % personality_resource.identity_anchors.size())
	print("  - Signature phrases: %d" % personality_resource.signature_phrases.size())
	print("  - Secrets: %d" % personality_resource.secrets.size())

## Setup KPI tracking for personality consistency
func _setup_kpi_tracking():
	if personality_resource == null:
		push_warning("[%s] KPI tracking requires structured personality resource" % npc_name)
		return

	var KPITrackerScript = load("res://scripts/debug/personality_kpi_tracker.gd")
	if KPITrackerScript:
		kpi_tracker = KPITrackerScript.new()
		add_child(kpi_tracker)
		kpi_tracker.start_session(npc_id, personality_resource)
		print("[%s] KPI tracking enabled" % npc_name)

## Check if NPC can interact (not dead)
func can_interact() -> bool:
	return is_alive

## Load death state from ChromaDB
func _load_death_state_from_chroma():
	if not rag_memory:
		print("[%s] No RAG memory, skipping death state check" % npc_name)
		return
	
	print("[%s] Querying ChromaDB for death state..." % npc_name)
	var state = await rag_memory.get_npc_state()
	print("[%s] Death state query result: %s" % [npc_name, JSON.stringify(state)])
	
	if not state.get("is_alive", true):
		is_alive = false
		death_cause = state.get("death_cause", "unknown")
		killed_by = state.get("killed_by", "unknown")
		death_timestamp = state.get("death_timestamp", 0.0)
		print("[%s] Loaded death state from ChromaDB: %s by %s" % [npc_name, death_cause, killed_by])
	else:
		print("[%s] NPC is alive according to ChromaDB" % npc_name)

## Kill the NPC (permanent state change)
## cause: How they died (e.g., "sword wound", "poison", "burned alive")
## killer: Who killed them (e.g., "player", "bandit_chief", "guard_marcus")
func die(cause: String = "unknown", killer: String = "unknown"):
	if not is_alive:
		return  # Already dead
	
	is_alive = false
	death_cause = cause
	killed_by = killer
	death_timestamp = Time.get_unix_time_from_system()
	
	print("[%s] NPC has died: %s (killed by: %s)" % [npc_name, cause, killer])
	combat_state = ""
	# WorldState is what storylines, emergence and the spawner read (a combat death registered it already)
	var world_state = get_node_or_null("/root/WorldState") if is_inside_tree() else null
	if world_state and npc_id != "" and world_state.is_npc_alive(npc_id):
		world_state.register_npc_death(npc_id, {"cause": cause, "killed_by": killer})

	# Store death state in ChromaDB (replaces old state)
	if rag_memory:
		await rag_memory.store_npc_state(false, {
			"cause": death_cause,
			"killed_by": killed_by,
			"timestamp": death_timestamp
		})
	
	# Hide NPC from world
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	
	# End any active conversation
	if is_in_conversation:
		end_conversation()
	
	# Store death memory for context/AI
	if rag_memory:
		await rag_memory.store({
			"text": "I died. Killed by: %s. Cause: %s. My last thoughts were of %s." % [
				killer,
				cause,
				_get_death_final_thoughts()
			],
			"importance": 10,  # Death is maximum importance
			"emotion": "terror",
			"event_type": "death",
			"killed_by": killer
		})
	
	# Emit signal for game world to handle (play death animation, etc.)
	# You can add: signal npc_died(npc_id: String, cause: String, killer: String)

## Get NPC's final thoughts based on relationship with player
func _get_death_final_thoughts() -> String:
	# Only reference player if they're the killer
	if killed_by == "player":
		if relationship_affection > 50:
			return "the player I had grown to care for - why did they do this?"
		elif relationship_trust > 50:
			return "the player I trusted - they betrayed me"
		elif relationship_fear > 50:
			return "my fear of the player - I knew this would happen"
		elif relationship_respect < -50:
			return "my contempt for the player who ended my life"
		else:
			return "the player who killed me without reason"
	else:
		return "those I cared about, and my life cut short"

## Start conversation with player
func start_conversation():
	# Check if NPC is alive
	if not is_alive:
		dialogue_started.emit(npc_id)
		var corpse_message = _get_corpse_interaction_message()
		dialogue_response_ready.emit(npc_id, corpse_message)
		return

	if is_in_conversation:
		return

	# Guard: Lazy initialization if not yet initialized
	if not rag_memory:
		print("[%s] Lazy initialization triggered by conversation..." % npc_name)
		var init_success = await initialize(true, false)
		if not init_success or not rag_memory:
			push_error("[%s] Failed to initialize NPC for conversation" % npc_name)
			dialogue_started.emit(npc_id)
			dialogue_response_ready.emit(npc_id, "*%s seems unresponsive...*" % npc_name)
			return

	# Add player to known NPCs (they're interacting with us)
	add_known_npc("player", "stranger", 7)  # Will upgrade based on relationship
	# Speaking with the player is contact: relationship decay restarts from now
	var ledger = _relationship_ledger()
	if ledger:
		ledger.note_contact(npc_id)

	print("[%s] Starting conversation..." % npc_name)
	is_in_conversation = true
	current_conversation_history = []
	dialogue_started.emit(npc_id)

	# CRITICAL: Retrieve memories BEFORE generating greeting
	# This allows the NPC to recognize returning players and remember their name
	print("[%s] Retrieving memories for greeting context..." % npc_name)
	var tiered_memories = await rag_memory.retrieve_tiered("player greeting meeting conversation")
	var formatted_tiered = rag_memory.format_tiered_memories(tiered_memories)

	# Check if we have any memories of the player (determines first meeting vs. returning)
	var has_player_memories = tiered_memories.pinned.size() > 0 or tiered_memories.important.size() > 0 or tiered_memories.relevant.size() > 0
	print("[%s] Has player memories: %s (pinned: %d, important: %d, relevant: %d)" % [
		npc_name, has_player_memories,
		tiered_memories.pinned.size(),
		tiered_memories.important.size(),
		tiered_memories.relevant.size()
	])

	# Build greeting prompt that includes memories
	var greeting_prompt = "(Player approaches you)"
	if has_player_memories:
		greeting_prompt = "(Player approaches you. You have met them before - check your memories for their name and past interactions.)"
	else:
		greeting_prompt = "(A stranger approaches you. This is your first time meeting them.)"

	# Calculate total memory count for first-meeting detection
	var total_memory_count = tiered_memories.pinned.size() + tiered_memories.important.size() + tiered_memories.relevant.size()

	# Generate greeting using full context builder WITH memories
	var greeting_context = context_builder.build_context({
		"system_prompt": system_prompt,
		"npc_id": npc_id,
		"tiered_memories": formatted_tiered,
		"relationship_status": relationship_status,
		"relationship_dimensions": {
			"trust": relationship_trust,
			"respect": relationship_respect,
			"affection": relationship_affection,
			"fear": relationship_fear,
			"familiarity": relationship_familiarity,
			"memory_count": total_memory_count
		},
		"conversation_history": [],
		"player_input": greeting_prompt
	})

	
	print("[%s] Sending greeting request to Claude..." % npc_name)
	# Get greeting from Claude
	var response = await request_checked_reply(
		greeting_context.messages,
		greeting_context.get("system_blocks", greeting_context.system_prompt),
		"greeting"
	)
	
	print("[%s] Received response: %s" % [npc_name, "text" if response.ok else "error"])
	if response.ok:
		# Parsed JSON (greeting also uses analysis format), already held to the world's rules
		var parsed_response = response
		var greeting = parsed_response.response
		var analysis = parsed_response.analysis

		# SANITIZE GREETING: Fix hallucinated establishment names BEFORE display
		greeting = _sanitize_response_hallucinations(greeting)

		print("[%s] Greeting: %s" % [npc_name, greeting.substr(0, 80)])
		
		# Apply dimension changes from greeting analysis (if any)
		if analysis:
			print("[%s] Greeting analysis: tone=%s, impact=%s" % 
				[npc_name, analysis.get("player_tone", "neutral"), 
				 analysis.get("emotional_impact", "neutral")])
			
			if analysis.has("familiarity_change"):
				relationship_familiarity += analysis.familiarity_change
				relationship_familiarity = clamp(relationship_familiarity, 0, 100)
			
			# Log to debug console
			var debug_console = get_tree().root.find_child("DebugConsole", true, false)
			if debug_console and debug_console.has_method("log_analysis"):
				debug_console.log_analysis(npc_name + " (greeting)", analysis)
		
		_add_to_history("assistant", greeting)
		_mark_storyline_agendas_raised()
		
		# Store memory of conversation start
		rag_memory.store_conversation(
			"npc",
			greeting,
			{
				"emotion": _infer_emotion(),
				"importance": 5
			}
		)
		
		print("[%s] Emitting dialogue_response_ready signal" % npc_name)
		dialogue_response_ready.emit(npc_id, greeting)
	else:
		# Fallback greeting if Claude fails
		var error_msg = response.get("error", "Unknown error")
		var fallback = "..."  # Use default taciturn response
		push_warning("Claude API error in greeting: " + error_msg)
		dialogue_response_ready.emit(npc_id, fallback)

## Process player message and generate response
func respond_to_player(player_message: String):
	print("[%s] respond_to_player called with: %s" % [npc_name, player_message])
	
	# Check if NPC is alive
	if not is_alive:
		var corpse_message = _get_corpse_interaction_message()
		dialogue_response_ready.emit(npc_id, corpse_message)
		return
	
	if not is_in_conversation:
		push_warning("Not in conversation - call start_conversation() first")
		return
	
	# Check if player is trying to kill the NPC
	if _is_lethal_action(player_message):
		_handle_lethal_action(player_message)
		return
	
	print("[%s] Adding player message to history" % npc_name)
	# Add player message to history
	_add_to_history("user", player_message)
	
	print("[%s] Getting relevant memories (tiered)..." % npc_name)
	# Get tiered memories for this context - pinned, important, and relevant
	var tiered_memories = await rag_memory.retrieve_tiered(player_message)
	# Format for context builder
	var formatted_tiered = rag_memory.format_tiered_memories(tiered_memories)
	
	print("[%s] Building context..." % npc_name)
	# Calculate total memory count for first-meeting detection
	var total_memory_count = tiered_memories.pinned.size() + tiered_memories.important.size() + tiered_memories.relevant.size()

	# Build full context with tiered memories for AI agent growth
	# Pass multi-dimensional relationship for Claude to generate appropriate responses
	# Use structured personality if available (preferred) or legacy system prompt
	var context_params = {
		"npc_id": npc_id,  # For world knowledge injection
		"tiered_memories": formatted_tiered,  # Tiered: pinned, important, relevant
		"relationship_status": relationship_status,  # Legacy
		"relationship_dimensions": {
			"trust": relationship_trust,
			"respect": relationship_respect,
			"affection": relationship_affection,
			"fear": relationship_fear,
			"familiarity": relationship_familiarity,
			"memory_count": total_memory_count
		},
		"world_state": _get_world_state(),
		"conversation_history": current_conversation_history,
		"player_input": player_message
	}

	# Use structured personality if available (enables core identity injection)
	if personality_resource != null:
		context_params["personality"] = personality_resource
	else:
		context_params["system_prompt"] = system_prompt

	var context = context_builder.build_context(context_params)
	
	print("[%s] Sending message to Claude..." % npc_name)
	# Get response from Claude
	var response = await request_checked_reply(
		context.messages,
		context.get("system_blocks", context.system_prompt),
		"dialogue"
	)
	
	print("[%s] Received response: %s" % [npc_name, "text" if response.ok else "error"])
	if response.ok:
		# Parsed JSON, already held to the world's rules (forbidden concepts regenerated, then sanitised)
		var parsed_response = response
		var npc_response = parsed_response.response
		var analysis = parsed_response.analysis

		# SANITIZE RESPONSE: Fix hallucinated establishment names BEFORE display
		npc_response = _sanitize_response_hallucinations(npc_response)

		print("[%s] NPC response: %s" % [npc_name, npc_response.substr(0, 50)])
		if analysis:
			print("[%s] Analysis: tone=%s, impact=%s, type=%s" % 
				[npc_name, analysis.get("player_tone", "?"), 
				 analysis.get("emotional_impact", "?"), 
				 analysis.get("interaction_type", "?")])
			print("[%s] Dimension changes: T%+d R%+d A%+d F%+d" % 
				[npc_name, analysis.get("trust_change", 0), 
				 analysis.get("respect_change", 0),
				 analysis.get("affection_change", 0),
				 analysis.get("fear_change", 0)])
			
			# Log to debug console if available
			var debug_console = get_tree().root.find_child("DebugConsole", true, false)
			if debug_console and debug_console.has_method("log_analysis"):
				debug_console.log_analysis(npc_name, analysis)

		# Track response with KPI system if enabled
		if kpi_tracker != null:
			var kpi_context = {
				"trust": relationship_trust,
				"affection": relationship_affection,
				"familiarity": relationship_familiarity
			}
			var kpi_analysis = kpi_tracker.analyze_response(npc_response, kpi_context)
			if kpi_analysis.has("checks"):
				var violations = []
				if not kpi_analysis.checks.identity.passed:
					violations.append("identity")
				if kpi_analysis.checks.speech.forbidden_used.size() > 0:
					violations.append("speech")
				if not kpi_analysis.checks.thresholds.passed:
					violations.append("thresholds")
				if violations.size() > 0:
					print("[%s] KPI VIOLATIONS: %s" % [npc_name, ", ".join(violations)])

		_add_to_history("assistant", npc_response)
		_mark_storyline_agendas_raised()

		# The NPC may act on what was said (docs/WORLD_SCHEMA.md §6); the Director enforces plausibility
		_apply_conversation_actions(parsed_response, player_message, npc_response)
		# What the player claimed, promised, threatened... becomes player events this NPC (and anyone here) witnessed
		_record_player_utterances(parsed_response)

		# Automatically record interaction based on Claude's analysis
		if analysis and analysis.has("interaction_type"):
			# Phase 5: Validate interaction type against allowed values
			var interaction_type = analysis.interaction_type
			if rag_memory:
				interaction_type = rag_memory.validate_interaction_type(interaction_type)

			# Phase 5: Clamp delta values to prevent importance saturation
			var clamped_deltas = _clamp_relationship_deltas(analysis)

			# Apply clamped dimension changes from analysis
			relationship_trust += clamped_deltas.get("trust_change", 0)
			relationship_respect += clamped_deltas.get("respect_change", 0)
			relationship_affection += clamped_deltas.get("affection_change", 0)
			relationship_fear += clamped_deltas.get("fear_change", 0)
			relationship_familiarity += clamped_deltas.get("familiarity_change", 0)

			# Clamp final values to valid range
			relationship_trust = clamp(relationship_trust, -100, 100)
			relationship_respect = clamp(relationship_respect, -100, 100)
			relationship_affection = clamp(relationship_affection, -100, 100)
			relationship_fear = clamp(relationship_fear, -100, 100)
			relationship_familiarity = clamp(relationship_familiarity, 0, 100)
			
			_update_legacy_relationship_status()

			# Process and store learned player information
			if analysis.has("learned_about_player"):
				await _store_learned_player_info(analysis.learned_about_player)

			# Extract topics and intent BEFORE storing (needed for sentiment-driven reactions)
			var topics = _extract_topics_from_messages([player_message, npc_response])
			var player_intent = _infer_player_intent(player_message)
			var player_sentiment = _infer_player_sentiment(player_message)

			# Store analyzed interaction in memory (single unified storage)
			# Includes topics/intent/sentiment for personality-driven NPC reactions
			await record_interaction(interaction_type, {
				"description": "Player said: \"%s\". I responded: \"%s\"" % [player_message, npc_response],
				"importance": _calculate_importance_from_impact(analysis.emotional_impact),
				"emotion": analysis.get("player_tone", "neutral"),
				"player_message": player_message,
				"npc_response": npc_response,
				"auto_analyzed": true,
				"topics": topics,
				"player_intent": player_intent,
				"player_sentiment": player_sentiment
			})

			# Emit for quest system - include full analysis for intent detection
			EventBus.npc_response_generated.emit(npc_id, {
				"response": npc_response,
				"interaction_type": interaction_type,
				"player_tone": analysis.get("player_tone", "neutral"),
				"emotional_impact": analysis.get("emotional_impact", "neutral"),
				"trust_change": analysis.get("trust_change", 0),
				"respect_change": analysis.get("respect_change", 0),
				"affection_change": analysis.get("affection_change", 0),
				"fear_change": analysis.get("fear_change", 0),
				"topics_discussed": topics,
				"player_intent": player_intent
			})
		else:
			# Non-analyzed path: still extract topics/intent/sentiment for memory
			var topics = _extract_topics_from_messages([player_message, npc_response])
			var player_intent = _infer_player_intent(player_message)
			var player_sentiment = _infer_player_sentiment(player_message)
			var emotion = _infer_emotion()

			# Store conversation with unified storage (default to "conversation" type)
			await record_interaction("conversation", {
				"description": "Player said: \"%s\". I responded: \"%s\"" % [player_message, npc_response],
				"importance": 6,
				"emotion": emotion,
				"player_message": player_message,
				"npc_response": npc_response,
				"topics": topics,
				"player_intent": player_intent,
				"player_sentiment": player_sentiment
			})

			# Emit for quest system (non-analyzed path)
			EventBus.npc_response_generated.emit(npc_id, {
				"response": npc_response,
				"topics_discussed": topics,
				"player_intent": player_intent,
				"interaction_type": "conversation"
			})

		dialogue_response_ready.emit(npc_id, npc_response)
	else:
		# Fallback response
		var error_msg = response.get("error", "Unknown error")
		var fallback = "I don't know what to say."
		push_warning("Claude API error in response: " + error_msg)
		dialogue_response_ready.emit(npc_id, fallback)

## End conversation
func end_conversation():
	if not is_in_conversation:
		return

	is_in_conversation = false
	var ledger = _relationship_ledger()
	if ledger:
		ledger.sync_from_npc(self)

	# Storyline agendas this NPC had in its prompt during the conversation are now done
	var director = get_node_or_null("/root/StorylineDirector")
	if director:
		director.complete_raised_agendas(npc_id)
		if director.has_method("finish_conversation"):
			director.finish_conversation(npc_id)  # moves decided while talking set off now
		director.request_round("conversation_ended")  # the story clock ticks after each conversation

	# Generate KPI report if tracking enabled
	if kpi_tracker != null:
		var kpi_report = kpi_tracker.generate_report()
		print("\n" + kpi_report)
		var final_metrics = kpi_tracker.end_session()
		print("[%s] KPI Session ended - Health: %s" % [npc_name, final_metrics.get("overall_health", "UNKNOWN")])

	# Store summary of full conversation
	var summary = "Had a conversation with the player. Topics discussed: %s" % _extract_topics()
	rag_memory.store({
		"text": summary,
		"event_type": "conversation_summary",
		"importance": 6,
		"emotion": _infer_emotion()
	})
	
	dialogue_ended.emit(npc_id)

## Record player interaction with automatic relationship dimension updates
## This is the PRIMARY way player actions affect NPC personality
## NO pre-canned dialogue - dimensions influence Claude's response generation
func record_interaction(interaction_type: String, context: Dictionary) -> void:
	"""
	Universal method for recording ANY player interaction.
	Automatically calculates multi-dimensional relationship impacts.
	
	Args:
		interaction_type: Type of interaction (conversation_topic, witnessed_kindness, 
			gift_received, helped, shared_danger, etc.)
		context: Dictionary with interaction details:
			- description: String (what happened from NPC's perspective)
			- importance: int 1-10
			- emotion: String (NPC's emotional reaction)
			- Optional: thoughtfulness, duration, witnesses, location, etc.
	"""
	
	# Build memory from NPC's perspective
	var memory_text = context.get("description", "Something happened with the player")
	var importance = context.get("importance", 5)
	var emotion = context.get("emotion", "neutral")
	
	# Calculate multi-dimensional impact
	var impacts = _calculate_relationship_impacts(interaction_type, context)
	
	# Update relationship dimensions
	relationship_trust += impacts.trust
	relationship_respect += impacts.respect
	relationship_affection += impacts.affection
	relationship_fear += impacts.fear
	relationship_familiarity += impacts.familiarity
	
	# Clamp values
	relationship_trust = clamp(relationship_trust, -100, 100)
	relationship_respect = clamp(relationship_respect, -100, 100)
	relationship_affection = clamp(relationship_affection, -100, 100)
	relationship_fear = clamp(relationship_fear, -100, 100)
	relationship_familiarity = clamp(relationship_familiarity, 0, 100)
	
	# Update legacy relationship_status (weighted average)
	_update_legacy_relationship_status()
	
	print("[%s] Interaction recorded: %s" % [npc_name, interaction_type])
	print("  Impacts: Trust %+d, Respect %+d, Affection %+d, Fear %+d, Familiarity %+d" % 
		[impacts.trust, impacts.respect, impacts.affection, impacts.fear, impacts.familiarity])
	print("  New totals: T:%d R:%d A:%d F:%d Fam:%d" % 
		[relationship_trust, relationship_respect, relationship_affection, relationship_fear, relationship_familiarity])
	
	# Store in RAG memory with dimension impacts (flattened for ChromaDB compatibility)
	if rag_memory:
		var memory_data = {
			"text": memory_text,
			"event_type": interaction_type,
			"importance": importance,
			"emotion": emotion,
			# Flatten dimension impacts for ChromaDB metadata
			"impact_trust": impacts.trust,
			"impact_respect": impacts.respect,
			"impact_affection": impacts.affection,
			"impact_fear": impacts.fear,
			"impact_familiarity": impacts.familiarity,
			# Flatten relationship snapshot
			"current_trust": relationship_trust,
			"current_respect": relationship_respect,
			"current_affection": relationship_affection,
			"current_fear": relationship_fear,
			"current_familiarity": relationship_familiarity
		}
		# Add sentiment analysis fields if provided (for personality-driven reactions)
		if context.has("topics"):
			memory_data["topics"] = context.topics
		if context.has("player_intent"):
			memory_data["player_intent"] = context.player_intent
		if context.has("player_sentiment"):
			memory_data["player_sentiment"] = context.player_sentiment
		if context.has("player_message"):
			memory_data["player_message"] = context.player_message
		if context.has("npc_response"):
			memory_data["npc_response"] = context.npc_response

		await rag_memory.store(memory_data)
	
	# Emit event for world state tracking
	EventBus.emit_signal("npc_relationship_changed", {
		"npc_id": npc_id,
		"interaction_type": interaction_type,
		"impacts": impacts,
		"new_dimensions": {
			"trust": relationship_trust,
			"respect": relationship_respect,
			"affection": relationship_affection,
			"fear": relationship_fear,
			"familiarity": relationship_familiarity
		}
	})

	# Detect NPC references in dialogue for dynamic NPC generation
	_detect_npc_references_in_dialogue(memory_text, context)

## Legacy method - kept for backward compatibility, redirects to record_interaction
## DEPRECATED: Use record_interaction() instead
func record_player_action(action_type: String, description: String, importance: int = 8, emotion: String = ""):
	await record_interaction(action_type, {
		"description": description,
		"importance": importance,
		"emotion": emotion if emotion != "" else "neutral"
	})


## Store learned player information as high-importance pinned memories
## This ensures the NPC remembers the player's name, occupation, etc.
## Also registers with WorldEvents for village-wide awareness (shared knowledge)
func _store_learned_player_info(player_info: Dictionary) -> void:
	if player_info == null or player_info.is_empty():
		return

	# Store player's name as a pinned memory (highest importance)
	var player_name = player_info.get("name")
	if player_name != null and player_name is String and not player_name.is_empty():
		print("[%s] Learned player's name: %s" % [npc_name, player_name])

		# REGISTER WITH WORLD EVENTS (shared across village)
		if WorldEvents:
			WorldEvents.register_player_info("name", player_name, npc_id)

		await rag_memory.store({
			"text": "The player told me their name is %s." % player_name,
			"event_type": "player_info",
			"importance": 10,  # Maximum importance - always remember names
			"pinned": true,  # Pin this memory so it's always included
			"info_type": "player_name",
			"player_name": player_name
		})

	# Store player's occupation
	var occupation = player_info.get("occupation")
	if occupation != null and occupation is String and not occupation.is_empty():
		print("[%s] Learned player's occupation: %s" % [npc_name, occupation])

		# REGISTER WITH WORLD EVENTS (shared across village)
		if WorldEvents:
			WorldEvents.register_player_info("occupation", occupation, npc_id)

		await rag_memory.store({
			"text": "The player is a %s." % occupation,
			"event_type": "player_info",
			"importance": 9,
			"pinned": true,
			"info_type": "player_occupation",
			"player_occupation": occupation
		})

	# Store player's origin
	var origin = player_info.get("origin")
	if origin != null and origin is String and not origin.is_empty():
		print("[%s] Learned player's origin: %s" % [npc_name, origin])

		# REGISTER WITH WORLD EVENTS (shared across village)
		if WorldEvents:
			WorldEvents.register_player_info("origin", origin, npc_id)

		await rag_memory.store({
			"text": "The player comes from %s." % origin,
			"event_type": "player_info",
			"importance": 8,
			"pinned": true,
			"info_type": "player_origin",
			"player_origin": origin
		})

	# Store notable facts
	var notable_facts = player_info.get("notable_facts", [])
	if notable_facts is Array and notable_facts.size() > 0:
		for fact in notable_facts:
			if fact is String and not fact.is_empty():
				print("[%s] Learned about player: %s" % [npc_name, fact])

				# REGISTER WITH WORLD EVENTS (shared across village)
				if WorldEvents:
					WorldEvents.register_player_info("fact", fact, npc_id)

				await rag_memory.store({
					"text": "I learned that the player %s" % fact,
					"event_type": "player_info",
					"importance": 7,
					"info_type": "player_fact"
				})


## Retrieve relevant memories from RAG for current context
func _get_relevant_memories(query: String) -> Array:
	return await rag_memory.retrieve_relevant(query, {"limit": 5})  # Top 5 memories

## Retrieve raw memory objects with metadata for AI agent growth
## This allows context builder to categorize actions vs conversations vs events
func _get_relevant_memories_raw(query: String) -> Array:
	return await rag_memory.retrieve_relevant_raw(query, {"limit": 8})  # Slightly more for categorization

## Get current world state relevant to this NPC
func _get_world_state() -> Dictionary:
	var world_state = {}

	# Include this NPC's ID so context_builder can check if they're implicated
	world_state["npc_id"] = npc_id

	if has_node("/root/WorldState"):
		var ws = get_node("/root/WorldState")
		if ws.has_method("get_active_quests"):
			world_state["active_quests"] = ws.get_active_quests()
		if ws.has_method("get_flags"):
			world_state["world_flags"] = ws.get_flags()

	# Add quest context hints for this specific NPC
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		if qm.has_method("get_quest_context_for_npc"):
			var quest_context = qm.get_quest_context_for_npc(npc_id)
			if not quest_context.is_empty():
				world_state["quest_context"] = quest_context

	# What their craft tells them where they stand (a ranger's creatures, herbs and weather). Generics
	# get it in their GenericManager prompt block
	var craft = [] if is_in_group("generics") else CharacterTypesScript.craft_lines(character_kind(), get_current_location(), _game_minute())
	if not craft.is_empty():
		var lore = "What your craft tells you here: %s" % " ".join(craft)
		world_state["quest_context"] = (str(world_state.get("quest_context", "")) + "\n" + lore).strip_edges()

	# Add scene awareness - who else is present in this location
	world_state["present_npcs"] = _get_present_npcs()
	world_state["present_npc_names"] = _get_present_npc_names()

	return world_state

func _game_minute() -> int:
	var ws = get_node_or_null("/root/WorldState")
	return int(ws.game_minutes) if ws and "game_minutes" in ws else 0

## Get list of NPC IDs currently present in the same scene
func _get_present_npcs() -> Array:
	var present = []
	var npcs_in_scene = get_tree().get_nodes_in_group("npcs")
	for npc in npcs_in_scene:
		if npc != self and npc.has_method("get_npc_id"):
			var other_id = npc.get_npc_id()
			if not other_id.is_empty():
				present.append(other_id)
		elif npc != self and "npc_id" in npc:
			if not npc.npc_id.is_empty():
				present.append(npc.npc_id)
	return present

## Get display names of NPCs currently present (for natural language context)
func _get_present_npc_names() -> Array:
	var names = []
	var npcs_in_scene = get_tree().get_nodes_in_group("npcs")
	for npc in npcs_in_scene:
		if npc != self:
			var display_name = ""
			if "npc_name" in npc and not npc.npc_name.is_empty():
				display_name = npc.npc_name
			elif npc.has_method("get_display_name"):
				display_name = npc.get_display_name()
			elif "name" in npc:
				display_name = npc.name
			if not display_name.is_empty():
				names.append(display_name)
	return names

## Add message to conversation history
func _add_to_history(speaker: String, message: String):
	current_conversation_history.append({
		"speaker": speaker,
		"message": message
	})
	
	# Keep history manageable (last 20 turns)
	if current_conversation_history.size() > 20:
		current_conversation_history.pop_front()

## Extract topics from conversation for memory storage
func _extract_topics() -> String:
	# Simple keyword extraction (could be enhanced with Claude)
	var topics = []
	var keywords = ["quest", "sword", "rebellion", "village", "bandits", "family", "magic"]
	
	for turn in current_conversation_history:
		var msg = turn.message.to_lower()
		for keyword in keywords:
			if keyword in msg and keyword not in topics:
				topics.append(keyword)
	
	return ", ".join(topics) if topics.size() > 0 else "casual conversation"

## Extract topics from specific messages (for individual turn storage)
func _extract_topics_from_messages(messages: Array) -> Array:
	var topics = []
	var keywords = ["quest", "sword", "rebellion", "village", "bandits", "family", "magic", 
					"help", "trouble", "guard", "merchant", "supplies", "gold", "weapon"]
	
	for message in messages:
		var msg = message.to_lower()
		for keyword in keywords:
			if keyword in msg and keyword not in topics:
				topics.append(keyword)
	
	return topics

## Infer player's intent from their message
func _infer_player_intent(message: String) -> String:
	var msg = message.to_lower()
	
	# Question patterns
	if msg.begins_with("what") or msg.begins_with("who") or msg.begins_with("where") or \
	   msg.begins_with("why") or msg.begins_with("how") or "?" in msg:
		if "help" in msg or "quest" in msg:
			return "asking_for_help"
		else:
			return "asking_question"
	
	# Agreement/acceptance
	if "yes" in msg or "sure" in msg or "okay" in msg or "i'll help" in msg or "accept" in msg:
		return "agreeing"
	
	# Refusal
	if "no" in msg or "not interested" in msg or "refuse" in msg or "can't help" in msg:
		return "refusing"
	
	# Gratitude
	if "thank" in msg or "appreciate" in msg:
		return "thanking"
	
	# Greeting
	if "hello" in msg or "hi" in msg or "greet" in msg:
		return "greeting"
	
	# Default
	return "conversing"

## Infer player's emotional/social sentiment from their message
## Used for personality-driven NPC reactions (e.g., guard who dislikes flirty behavior)
func _infer_player_sentiment(message: String) -> String:
	var msg = message.to_lower()

	# Flirty/romantic indicators
	var flirty_patterns = ["handsome", "beautiful", "pretty", "cute", "lovely",
		"wink", ";)", "sweetheart", "darling", "dear", "gorgeous", "charming",
		"buy you a drink", "come here often", "your place or mine", "my place",
		"fancy", "attractive", "good looking", "nice eyes", "nice smile"]
	for pattern in flirty_patterns:
		if pattern in msg:
			return "flirty"

	# Aggressive/threatening indicators
	var aggressive_patterns = ["kill", "hurt", "attack", "fight", "destroy",
		"threaten", "warning", "die", "dead", "punch", "hit", "smash",
		"make you pay", "regret", "sorry you", "watch your", "i'll find you"]
	for pattern in aggressive_patterns:
		if pattern in msg:
			return "aggressive"

	# Dismissive/rude indicators
	var dismissive_patterns = ["whatever", "don't care", "shut up", "go away",
		"leave me", "not interested", "boring", "waste of time", "idiot",
		"fool", "stupid", "useless", "pathetic"]
	for pattern in dismissive_patterns:
		if pattern in msg:
			return "dismissive"

	# Respectful/formal indicators
	var respectful_patterns = ["sir", "ma'am", "madam", "your honor", "your grace",
		"my lord", "my lady", "please", "if you would", "may i", "pardon",
		"excuse me", "with respect", "humbly", "kindly"]
	for pattern in respectful_patterns:
		if pattern in msg:
			return "respectful"

	# Friendly/warm indicators
	var friendly_patterns = ["friend", "buddy", "pal", "mate", "nice to meet",
		"good to see", "happy to", "glad to", "wonderful", "great to"]
	for pattern in friendly_patterns:
		if pattern in msg:
			return "friendly"

	# Curious/inquisitive
	if msg.count("?") >= 2 or "tell me more" in msg or "curious" in msg:
		return "curious"

	# Default neutral
	return "neutral"

## Detect references to NPC types in dialogue for dynamic NPC generation
## Registers references with DynamicNPCRegistry for later asset generation
func _detect_npc_references_in_dialogue(dialogue_text: String, context: Dictionary) -> void:
	# Get reference to DynamicNPCRegistry autoload
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	if not registry:
		return  # Registry not available

	var lower_text = dialogue_text.to_lower()

	# NPC type keywords to detect
	var npc_keywords = {
		"bandit": ["bandit", "bandits", "outlaw", "outlaws", "raider", "raiders", "highwayman", "robber", "robbers"],
		"guard": ["guard", "guards", "watchman", "watchmen", "sentry", "sentries", "patrol"],
		"soldier": ["soldier", "soldiers", "knight", "knights", "warrior", "warriors", "army"],
		"thief": ["thief", "thieves", "pickpocket", "burglar", "cutpurse"],
		"merchant": ["merchant", "merchants", "trader", "traders", "peddler", "caravaner"],
		"bard": ["bard", "bards", "minstrel", "performer", "entertainer"],
		"noble": ["noble", "nobles", "lord", "lady", "duke", "baron", "count"],
		"assassin": ["assassin", "assassins", "killer", "hired blade"],
		"mage": ["mage", "mages", "wizard", "sorcerer", "witch"],
		"priest": ["priest", "priests", "cleric", "monk", "acolyte"]
	}

	# Context from NPC response too
	var npc_response = context.get("npc_response", "")
	var full_text = lower_text + " " + npc_response.to_lower()

	# Track what types we've found to avoid duplicates
	var found_types = []

	for npc_type in npc_keywords:
		if npc_type in found_types:
			continue

		for keyword in npc_keywords[npc_type]:
			if keyword in full_text:
				# Register this reference
				var dialogue_context = "Mentioned during conversation with %s: %s" % [npc_name, dialogue_text.left(100)]
				registry.register_dialogue_reference(npc_type, npc_id, dialogue_context)
				found_types.append(npc_type)
				print("[%s] Detected NPC reference: %s (keyword: %s)" % [npc_name, npc_type, keyword])
				break  # Only register once per type

## Infer emotional state from conversation
func _infer_emotion() -> String:
	# Simple sentiment (could be enhanced)
	if relationship_status > 50:
		return "friendly"
	elif relationship_status > 0:
		return "neutral"
	elif relationship_status > -50:
		return "cautious"
	else:
		return "hostile"

## React to witnessed event (called by world event system)
## event_type is kept for callers; witnessed memories are stored as "witnessed_event"
func witness_event(event_description: String, _event_type: String, importance: int):
	# Store in RAG memory
	await rag_memory.store_witnessed_event(event_description, importance, _infer_emotion())
	
	# If in conversation, generate immediate reaction
	if is_in_conversation:
		var memories = await _get_relevant_memories(event_description)
		var reaction_context = context_builder.build_reaction_context(
			system_prompt,
			npc_id,
			event_description,
			memories
		)
		
		var response = await LlmTelemetry.send(claude_client, reaction_context.messages,
			reaction_context.get("system_blocks", reaction_context.system_prompt), {"purpose": "reaction", "npc": npc_id})
		
		if response.has("text"):
			dialogue_response_ready.emit(npc_id, response.text)

## Storyline agendas in this reply's prompt count as raised (done when the conversation ends)
func _mark_storyline_agendas_raised() -> void:
	var director = get_node_or_null("/root/StorylineDirector")
	if director:
		director.mark_agendas_raised(npc_id)

## Change one relationship dimension directly (storyline adjust_relationship effects)
## dimension: trust|respect|affection|fear|familiarity; delta is clamped like the analysis path
func apply_relationship_delta(dimension: String, delta: float) -> void:
	var var_name = "relationship_" + dimension
	if not (var_name in self):
		return
	var low = 0.0 if dimension == "familiarity" else -100.0
	set(var_name, clamp(get(var_name) + delta, low, 100.0))
	_update_legacy_relationship_status()
	print("[%s] Storyline changed %s by %+d (now %d)" % [npc_name, dimension, delta, get(var_name)])
	EventBus.npc_relationship_changed.emit({
		"npc_id": npc_id,
		"interaction_type": "storyline_effect",
		"impacts": {dimension: delta},
		"new_dimensions": {
			"trust": relationship_trust,
			"respect": relationship_respect,
			"affection": relationship_affection,
			"fear": relationship_fear,
			"familiarity": relationship_familiarity
		}
	})

## Update relationship status (called by reputation system)
func adjust_relationship(delta: float):
	relationship_status = clamp(relationship_status + delta, -100.0, 100.0)
	
	# Store significant relationship changes
	if abs(delta) >= 10:
		var description = "My opinion of the player changed significantly. "
		if delta > 0:
			description += "They're earning my trust."
		else:
			description += "I'm losing faith in them."
		
		rag_memory.store({
			"text": description,
			"event_type": "relationship_change",
			"importance": 7,
			"emotion": _infer_emotion()
		})

## Player interaction handling (for game scenes)
var player_nearby: bool = false

func _on_interaction_area_body_entered(body):
	print("[%s] body_entered: %s (groups: %s)" % [npc_name, body.name, body.get_groups()])
	if body.name == "Player" or body.is_in_group("player"):
		print("[%s] PLAYER NEARBY - showing prompt" % npc_name)
		player_nearby = true
		_show_interaction_prompt(true)

func _on_interaction_area_body_exited(body):
	print("[%s] body_exited: %s" % [npc_name, body.name])
	if body.name == "Player" or body.is_in_group("player"):
		print("[%s] PLAYER LEFT" % npc_name)
		player_nearby = false
		_show_interaction_prompt(false)

func _show_interaction_prompt(show: bool):
	if has_node("InteractionPrompt"):
		get_node("InteractionPrompt").visible = show

func _unhandled_input(event):
	# Check for both interact action (E key) and ui_accept (Enter/Space) for flexibility
	if player_nearby and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		print("[%s] Interaction key pressed! In convo: %s" % [npc_name, is_in_conversation])
		if not is_in_conversation:
			# Emit signal for DialogueUI to handle
			print("[%s] Starting conversation..." % npc_name)
			dialogue_started.emit(npc_id)
			start_conversation()

## Calculate relationship dimension impacts from interaction
## Returns: { trust: int, respect: int, affection: int, fear: int, familiarity: int }
func _calculate_relationship_impacts(interaction_type: String, context: Dictionary) -> Dictionary:
	var impacts = { "trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0 }
	
	# Base familiarity - almost everything increases it
	impacts.familiarity = 2
	
	match interaction_type:
		"emotional_support":
			impacts.trust = 8
			impacts.affection = 10
			impacts.familiarity = 5
			
		"emotional_dismissal":
			impacts.trust = -3
			impacts.affection = -5
			
		"remembered_detail":
			var days_since = context.get("time_since_mentioned", 1)
			impacts.affection = min(15, 5 + days_since)  # More impressive if long ago
			impacts.familiarity = 3
			impacts.trust = 2
			
		"witnessed_kindness":
			impacts.respect = 7
			impacts.affection = 5
			impacts.trust = 3
			
		"witnessed_cruelty":
			impacts.respect = -10
			impacts.affection = -8
			impacts.fear = 5
			impacts.trust = -5
			
		"witnessed_combat":
			var style = context.get("style", "normal")
			if style == "non_lethal":
				impacts.respect = 12
				impacts.affection = 5
				impacts.fear = -3
			elif style == "brutal":
				impacts.respect = 5
				impacts.affection = -10
				impacts.fear = 15
				impacts.trust = -3
			else:
				impacts.respect = 8
				impacts.fear = 5
				
		"gift_received":
			var thoughtfulness = context.get("thoughtfulness", "medium")
			if thoughtfulness == "high":
				impacts.affection = 15
				impacts.trust = 8
				impacts.familiarity = 10
			elif thoughtfulness == "medium":
				impacts.affection = 5
				impacts.familiarity = 3
			else:
				impacts.affection = 2
				
		"helped", "unrequested_help":
			var payment_offered = context.get("payment_offered", "none")
			if payment_offered == "refused":
				impacts.trust = 10
				impacts.affection = 8
				impacts.respect = 5
			else:
				impacts.trust = 5
				impacts.affection = 3
				
		"quest_accepted":
			impacts.trust = 5
			impacts.affection = 3
			impacts.familiarity = 3
			
		"quest_completed":
			impacts.trust = 15
			impacts.respect = 10
			impacts.affection = 8
			impacts.familiarity = 5
			
		"quest_refused":
			impacts.trust = -5
			impacts.affection = -3
			
		"quest_failed":
			impacts.trust = -10
			impacts.respect = -8
			impacts.affection = -5
			
		"promise_kept":
			impacts.trust = 12
			impacts.affection = 5
			
		"promise_broken":
			impacts.trust = -20
			impacts.affection = -15
			
		"shared_danger":
			impacts.trust = 20
			impacts.respect = 15
			impacts.affection = 10
			impacts.familiarity = 15
			impacts.fear = -10
			
		"abandoned":
			impacts.trust = -25
			impacts.respect = -20
			impacts.affection = -15
			
		"protected":
			impacts.trust = 12
			impacts.affection = 10
			impacts.respect = 8
			impacts.fear = -5
			
		"value_contradiction":
			impacts.trust = -15
			impacts.respect = -5
			impacts.familiarity = 5  # Know player better, but negatively
			
		"shared_secret":
			impacts.trust = 15
			impacts.affection = 12
			impacts.familiarity = 10
			
		"conversation_topic":
			var depth = context.get("depth", "surface")
			if depth == "personal":
				impacts.affection = 5
				impacts.familiarity = 5
				impacts.trust = 2
			else:
				impacts.familiarity = 2
				
		_:  # Unknown interaction type
			impacts.familiarity = 1

	# Apply personality modifiers from structured resource (preferred)
	if personality_resource != null:
		impacts = personality_resource.apply_personality_modifiers(impacts)
	# Fallback: Apply personality modifiers (if implemented in subclass)
	elif has_method("_apply_personality_modifiers"):
		impacts = call("_apply_personality_modifiers", impacts, interaction_type, context)

	# Apply relationship context (existing relationships affect impact)
	impacts = _apply_relationship_context(impacts, interaction_type)

	return impacts

## Existing relationship affects how new interactions are perceived
func _apply_relationship_context(impacts: Dictionary, interaction_type: String) -> Dictionary:
	var modified = impacts.duplicate()
	
	# High trust magnifies positive affection gains
	if relationship_trust > 50 and modified.affection > 0:
		modified.affection = int(modified.affection * 1.5)
		
	# High fear reduces trust gains
	if relationship_fear > 50 and modified.trust > 0:
		modified.trust = int(modified.trust * 0.5)
		
	# Low familiarity means more cautious trust changes
	if relationship_familiarity < 30:
		modified.trust = int(modified.trust * 0.7)
		
	# High affection makes betrayals hurt more
	if relationship_affection > 60 and modified.trust < -5:
		modified.affection += modified.trust * 2  # Double the affection loss
	
	return modified

## Phase 5: Clamp relationship deltas from Claude to prevent importance saturation
func _clamp_relationship_deltas(analysis: Dictionary) -> Dictionary:
	if rag_memory:
		return rag_memory.clamp_relationship_deltas(analysis)

	# Fallback clamping if no rag_memory available
	return {
		"trust_change": clampi(analysis.get("trust_change", 0), -15, 15),
		"affection_change": clampi(analysis.get("affection_change", 0), -10, 10),
		"fear_change": clampi(analysis.get("fear_change", 0), -10, 10),
		"respect_change": clampi(analysis.get("respect_change", 0), -10, 10),
		"familiarity_change": clampi(analysis.get("familiarity_change", 0), -5, 5)
	}

## Update legacy single relationship score from dimensions
func _update_legacy_relationship_status():
	# Weighted average favoring trust and affection, penalized by fear
	var weighted = (relationship_trust * 0.4) + (relationship_affection * 0.4) + \
				   (relationship_respect * 0.2) - (relationship_fear * 0.3)
	relationship_status = clamp(weighted, -100, 100)

## Last conversation-agency result ({applied, dropped, entry}) for debugging
var last_conversation_actions: Dictionary = {}

## Ask Claude for a reply and hold it to the world's rules (docs/WORLD_SCHEMA.md §6, rule 6):
## speech or action text naming a forbidden concept is regenerated once with a correction note,
## then sanitised if it still fails. Returns the parsed reply plus
## {"ok": bool, "error": String, "regenerated": bool, "sanitised": Array of words replaced}
## system_prompt: a String, or ContextBuilder's system_blocks (cached prefix); purpose labels telemetry
func request_checked_reply(messages: Array, system_prompt, purpose: String = "dialogue") -> Dictionary:
	var response = await LlmTelemetry.send(claude_client, messages, system_prompt, {"purpose": purpose, "npc": npc_id})
	if not response is Dictionary or not response.has("text"):
		return {"ok": false, "error": str(response.get("error", "Unknown error")) if response is Dictionary else "bad response",
			"response": "", "analysis": null, "actions": [], "commitments": [], "utterances": [], "regenerated": false, "sanitised": []}
	var parsed = _parse_npc_response(str(response.text))
	var found = _forbidden_in_reply(parsed)
	var regenerated = false
	if not found.is_empty():
		regenerated = true
		print("[%s] Reply used forbidden concepts %s; regenerating once" % [npc_name, found])
		var note = "\n\n## CORRECTION (your previous reply was rejected)\n"
		note += "It used words that cannot exist in this world: %s. This realm has no such things. " % ", ".join(found)
		note += "Write the whole reply again in-world, in the same JSON format, without them or anything like them.\n"
		# The note goes after the prompt (after the cached blocks, which stay intact)
		var retry_prompt = system_prompt + note if system_prompt is String else system_prompt + [{"text": note, "cache": false}]
		var retry = await LlmTelemetry.send(claude_client, messages, retry_prompt, {"purpose": purpose + "_retry", "npc": npc_id})
		if retry is Dictionary and retry.has("text"):
			parsed = _parse_npc_response(str(retry.text))
			found = _forbidden_in_reply(parsed)
	var sanitised: Array = []
	if not found.is_empty():
		sanitised = found
		var registry = get_node_or_null("/root/WorldRegistry")
		if registry:
			parsed.response = registry.sanitize_forbidden(str(parsed.response))
			for action in parsed.actions:
				if action is Dictionary:
					for field in ["text", "via"]:
						if action.has(field):
							action[field] = registry.sanitize_forbidden(str(action[field]))
		print("[%s] Still forbidden after regenerating; sanitised %s" % [npc_name, found])
	parsed["ok"] = true
	parsed["error"] = ""
	parsed["regenerated"] = regenerated
	parsed["sanitised"] = sanitised
	return parsed

## Forbidden concepts in a parsed reply's speech and action text (lowercase words)
func _forbidden_in_reply(parsed: Dictionary) -> Array:
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry == null:
		return []
	var text = str(parsed.get("response", ""))
	for action in parsed.get("actions", []):
		if action is Dictionary:
			text += "\n" + str(action.get("text", "")) + "\n" + str(action.get("via", ""))
	return registry.find_forbidden_concepts(text)

## Hand the reply's actions and commitments to the StorylineDirector (plausibility rules 1-7)
func _apply_conversation_actions(reply: Dictionary, player_message: String, npc_response: String) -> void:
	var actions: Array = reply.get("actions", [])
	var commitments: Array = reply.get("commitments", [])
	if actions.is_empty() and commitments.is_empty():
		return
	var config = get_node_or_null("/root/Config")
	if config and "conversation_agency" in config and not config.conversation_agency:
		print("[%s] Conversation agency is off (CONVERSATION_AGENCY); ignoring %d action(s)" % [npc_name, actions.size()])
		return
	var director = get_node_or_null("/root/StorylineDirector")
	if director == null or not director.has_method("apply_conversation_actions"):
		return
	last_conversation_actions = director.apply_conversation_actions(npc_id, actions, commitments, {"said": npc_response, "player": player_message})
	var debug_console = get_tree().root.find_child("DebugConsole", true, false) if is_inside_tree() else null
	if debug_console and debug_console.has_method("log_conversation_actions"):
		debug_console.log_conversation_actions(npc_name, last_conversation_actions)

## The reply's utterances become player events (PlayerEvents validates kinds, caps the count, and
## takes this NPC plus everyone present at its location as witnesses). Returns the event ids
func _record_player_utterances(reply: Dictionary) -> Array:
	var utterances = reply.get("utterances", [])
	if not utterances is Array or utterances.is_empty():
		return []
	var player_events = get_node_or_null("/root/PlayerEvents")
	if player_events == null or not player_events.has_method("record_utterances"):
		return []
	return player_events.record_utterances(npc_id, utterances, get_current_location())

## Parse NPC response JSON with fallback to plain text
func _parse_npc_response(raw_text: String) -> Dictionary:
	var result = {"response": "", "analysis": null, "actions": [], "commitments": [], "utterances": []}
	
	# Try to extract JSON from response (Claude might wrap it in markdown)
	var json_start = raw_text.find("{")
	var json_end = raw_text.rfind("}") + 1
	
	if json_start >= 0 and json_end > json_start:
		var json_str = raw_text.substr(json_start, json_end - json_start)
		var json = JSON.new()
		var parse_error = json.parse(json_str)
		
		if parse_error == OK:
			var data = json.data
			if data is Dictionary:
				if data.has("response"):
					result.response = data.response
				if data.has("analysis") and data.analysis is Dictionary:
					result.analysis = data.analysis
				# Optional conversation agency (docs/WORLD_SCHEMA.md §6)
				if data.get("actions") is Array:
					result.actions = data.actions
				if data.get("commitments") is Array:
					result.commitments = data.commitments.map(func(c): return str(c))
				# What the player said, as this NPC heard it (docs/WORLD_SCHEMA.md §10): analysis.utterances
				if result.analysis is Dictionary and result.analysis.get("utterances") is Array:
					result.utterances = result.analysis.utterances
				elif data.get("utterances") is Array:
					result.utterances = data.utterances
				
				# Return successfully parsed JSON
				if result.response != "":
					return result
	
	# Fallback: treat entire response as dialogue (no analysis)
	result.response = raw_text.strip_edges()
	result.analysis = null
	print("[%s] Warning: Could not parse JSON analysis, using raw response" % npc_name)
	return result

## Sanitize Claude's response to fix hallucinated establishment names BEFORE display
## This catches hallucinations that slipped past prompt instructions
func _sanitize_response_hallucinations(response_text: String) -> String:
	if not WorldKnowledge or not WorldEvents:
		return response_text

	var sanitized = response_text
	var corrections_made = []

	# Get valid establishment names for replacement suggestions
	var valid_names = WorldKnowledge.get_all_establishment_names()

	# Common hallucination patterns and their correct replacements
	var hallucination_replacements = {
		# Tavern hallucinations -> The Rusty Nail
		"weary wanderer": "The Rusty Nail",
		"the weary wanderer": "The Rusty Nail",
		"wanderer's rest": "The Rusty Nail",
		"golden goose": "The Rusty Nail",
		"the golden goose": "The Rusty Nail",
		"silver spoon": "The Rusty Nail",
		"the silver spoon": "The Rusty Nail",
		"dancing dragon": "The Rusty Nail",
		"the dancing dragon": "The Rusty Nail",
		"prancing pony": "The Rusty Nail",
		"the prancing pony": "The Rusty Nail",
		"traveler's rest": "The Rusty Nail",
		"old inn": "The Rusty Nail",
		"the old inn": "The Rusty Nail",
		"village tavern": "The Rusty Nail",
		"the village tavern": "The Rusty Nail",
		"local tavern": "The Rusty Nail",
		"the local tavern": "The Rusty Nail",
		"local inn": "The Rusty Nail",
		"the local inn": "The Rusty Nail",
		# Blacksmith hallucinations -> Bjorn's Forge
		"village smithy": "Bjorn's Forge",
		"the village smithy": "Bjorn's Forge",
		"local blacksmith": "Bjorn's Forge",
		"the local blacksmith": "Bjorn's Forge",
		"village forge": "Bjorn's Forge",
		"the village forge": "Bjorn's Forge",
		# Shop hallucinations -> Gregor's General Goods
		"general store": "Gregor's General Goods",
		"the general store": "Gregor's General Goods",
		"village shop": "Gregor's General Goods",
		"the village shop": "Gregor's General Goods",
		"local shop": "Gregor's General Goods",
		"the local shop": "Gregor's General Goods",
	}

	# Case-insensitive replacement
	var lower_response = sanitized.to_lower()
	for hallucination in hallucination_replacements:
		if hallucination in lower_response:
			# Find the actual case used in the response
			var start_idx = lower_response.find(hallucination)
			if start_idx >= 0:
				var original_text = sanitized.substr(start_idx, hallucination.length())
				var replacement = hallucination_replacements[hallucination]
				sanitized = sanitized.replace(original_text, replacement)
				corrections_made.append("%s -> %s" % [original_text, replacement])
				# Update lower_response for next iteration
				lower_response = sanitized.to_lower()

	# Log corrections
	if corrections_made.size() > 0:
		print("[%s] HALLUCINATION FIXED: %s" % [npc_name, ", ".join(corrections_made)])

	return sanitized

## Calculate importance score from emotional impact string
func _calculate_importance_from_impact(impact: String) -> int:
	match impact:
		"very_positive":
			return 9
		"positive":
			return 7
		"neutral":
			return 5
		"negative":
			return 7
		"very_negative":
			return 9
		_:
			return 5

## Check if player message contains lethal action TARGETING this NPC
## Must detect "I stab you" but NOT "bandits killed merchants"
func _is_lethal_action(message: String) -> bool:
	var lower_message = message.to_lower()

	# Action verbs that indicate violence
	var action_verbs = [
		"stab", "kill", "murder", "attack", "thrust", "slice",
		"shoot", "poison", "strangle", "choke", "slit", "behead",
		"execute", "assassinate", "slaughter"
	]

	# First-person action patterns that target the NPC
	# These indicate the player is actively doing something to the NPC
	var first_person_patterns = [
		"i stab", "i kill", "i murder", "i attack", "i shoot",
		"i poison", "i strangle", "i choke", "i slice", "i thrust",
		"i slit", "i behead", "i execute", "i assassinate", "i slaughter"
	]

	# Patterns that target "you" (the NPC) directly
	var targeting_patterns = [
		"stab you", "kill you", "murder you", "attack you", "shoot you",
		"poison you", "strangle you", "choke you", "slice you", "thrust at you",
		"slit your", "behead you", "execute you", "assassinate you", "slaughter you",
		"stabs you", "kills you", "murders you", "attacks you", "shoots you"
	]

	# Patterns targeting the NPC by name
	var npc_name_lower = npc_name.to_lower()
	var name_patterns = []
	for verb in action_verbs:
		name_patterns.append(verb + " " + npc_name_lower)
		name_patterns.append(verb + "s " + npc_name_lower)

	# Imperative/action patterns (drawing weapons with intent)
	var imperative_patterns = [
		"draw my sword", "draw my blade", "draw my dagger", "draw my knife",
		"unsheathe my", "pull out my sword", "pull out my dagger",
		"raise my sword", "swing my sword", "swing at you", "lunge at you"
	]

	# Check first-person actions
	for pattern in first_person_patterns:
		if pattern in lower_message:
			return true

	# Check targeting patterns
	for pattern in targeting_patterns:
		if pattern in lower_message:
			return true

	# Check name-targeted patterns
	for pattern in name_patterns:
		if pattern in lower_message:
			return true

	# Check imperative/weapon-drawing patterns
	for pattern in imperative_patterns:
		if pattern in lower_message:
			return true

	return false

## Handle lethal action from player
func _handle_lethal_action(player_message: String):
	# Extract weapon/method from message
	var method = "violence"
	if "sword" in player_message.to_lower():
		method = "sword wound"
	elif "stab" in player_message.to_lower():
		method = "stabbing"
	elif "shoot" in player_message.to_lower():
		method = "arrow/gunshot"
	elif "poison" in player_message.to_lower():
		method = "poison"
	elif "strangle" in player_message.to_lower() or "choke" in player_message.to_lower():
		method = "strangulation"
	elif "burn" in player_message.to_lower() or "fire" in player_message.to_lower():
		method = "burns"
	
	# Generate final dying words based on relationship
	var dying_words = _get_dying_words()
	
	# Kill the NPC (player is the killer)
	die(method, "player")
	
	# Send dying words as final response
	dialogue_response_ready.emit(npc_id, dying_words)
	
	# End conversation
	is_in_conversation = false

## Get NPC's dying words based on relationship
func _get_dying_words() -> String:
	if relationship_affection > 50:
		return "*stumbles back, hand clutching the wound* Why...? I thought... we had something... *collapses* Please... don't let this be... how it ends..."
	elif relationship_trust > 50:
		return "*eyes wide with shock and betrayal* You... I trusted you... How could... *falls to knees* Everything I believed... was a lie..."
	elif relationship_fear > 50:
		return "*backing away in terror* No... please... I knew you were dangerous... *voice weakening* This is how... it was always... going to end..."
	elif relationship_respect < -50:
		return "*spits blood* Go to hell... you bastard... *defiant to the end* You'll pay... for this... they all will... *collapses*"
	else:
		return "*gasps in pain and shock* You... killed me... *struggles to speak* Why...? *breathing stops*"

## Get message when trying to interact with corpse
func _get_corpse_interaction_message() -> String:
	var time_since_death = Time.get_unix_time_from_system() - death_timestamp
	
	var killer_text = ""
	if killed_by == "player":
		killer_text = "You killed them."
	elif killed_by != "unknown":
		killer_text = "Killed by: %s." % killed_by
	
	if time_since_death < 60:  # Just died (less than 1 minute ago)
		return "%s lies motionless on the ground, blood pooling around the body. They died moments ago from %s. %s" % [npc_name, death_cause, killer_text]
	elif time_since_death < 3600:  # Recent (less than 1 hour)
		return "%s's corpse lies cold on the ground. Cause of death: %s. %s There is nothing more to say to the dead." % [npc_name, death_cause, killer_text]
	else:  # Old death
		return "The remains of %s. They have been dead for some time. Cause: %s. %s" % [npc_name, death_cause, killer_text]

## Cross-NPC Awareness: Check another NPC's state
## other_npc_id: ID of NPC to check (e.g., "gregor_merchant_001")
## Returns: Dictionary {is_alive, death_cause, killed_by, death_timestamp}
func check_other_npc_state(other_npc_id: String) -> Dictionary:
	if not rag_memory:
		push_error("RAGMemory not initialized - cannot check NPC states")
		return {"is_alive": true}
	
	return await rag_memory.check_npc_state(other_npc_id)

## React to another NPC's death (stores memory and updates relationship)
## other_npc_id: NPC who died
## other_npc_name: Display name
## relationship_type: "family", "friend", "enemy", "stranger"
func react_to_npc_death(other_npc_id: String, other_npc_name: String, relationship_type: String = "stranger") -> String:
	var state = await check_other_npc_state(other_npc_id)
	
	if state.is_alive:
		return ""  # NPC is alive, no reaction needed
	
	print("[%s] Reacting to %s's death (relationship: %s)" % [npc_name, other_npc_name, relationship_type])
	
	# Generate awareness memory based on relationship
	var awareness_text = ""
	var reaction_emotion = "sad"
	var importance = 8
	
	match relationship_type:
		"family":
			awareness_text = "My %s, %s, is dead. They were killed by %s. I can't believe they're gone. My heart is shattered." % [
				"family member",
				other_npc_name,
				state.killed_by
			]
			reaction_emotion = "devastated"
			importance = 10
			
			# Massive relationship shift if player killed family
			if state.killed_by == "player":
				relationship_trust = -100
				relationship_affection = -100
				relationship_respect = -80
				relationship_fear = 90
				await rag_memory.store({"text": "The player murdered my family. I will never forgive them.", "event_type": "relationship_change", "importance": 10})
		
		"friend":
			awareness_text = "I learned that %s is dead. They were killed by %s. We were friends. This hurts." % [
				other_npc_name,
				state.killed_by
			]
			reaction_emotion = "grieving"
			importance = 8
			
			if state.killed_by == "player":
				relationship_trust -= 60
				relationship_affection -= 70
				relationship_respect -= 40
				await rag_memory.store({"text": "The player killed my friend %s. I'm devastated and angry." % other_npc_name, "event_type": "relationship_change", "importance": 9})
		
		"enemy":
			awareness_text = "I heard %s is dead. Killed by %s. Good riddance - we were never on good terms." % [
				other_npc_name,
				state.killed_by
			]
			reaction_emotion = "satisfied"
			importance = 6
			
			if state.killed_by == "player":
				relationship_respect += 20  # Respect for eliminating enemy
				relationship_fear += 30     # But also fear of their capability
				await rag_memory.store({"text": "The player killed my enemy %s. I respect their strength but fear their ruthlessness." % other_npc_name, "event_type": "relationship_change", "importance": 7})
		
		_:  # stranger
			awareness_text = "I heard that %s died. Killed by %s, apparently. I didn't know them well." % [
				other_npc_name,
				state.killed_by
			]
			reaction_emotion = "concerned"
			importance = 5
			
			if state.killed_by == "player":
				relationship_fear += 15
				relationship_trust -= 10
				await rag_memory.store({"text": "The player killed %s. I need to be careful around them." % other_npc_name, "event_type": "relationship_change", "importance": 6})
	
	# Store awareness memory
	await rag_memory.store_npc_awareness(other_npc_id, awareness_text, importance)
	
	# Return reaction text for potential dialogue use
	return awareness_text

## Automatically discover nearby NPCs (proximity-based relationships)
func _discover_nearby_npcs():
	print("[%s] Discovering nearby NPCs..." % npc_name)
	
	# Find all NPCs in the scene
	var nearby_npcs = get_tree().get_nodes_in_group("npcs")
	var discovered_count = 0
	
	for node in nearby_npcs:
		if node == self:
			continue
		
		# Check if node has NPC methods
		if not node.has_method("get_npc_id"):
			continue
		
		var other_id = node.get_npc_id()
		if other_id == npc_id or other_id == "":
			continue
		
		# Check proximity (same scene = acquaintance)
		var distance = global_position.distance_to(node.global_position)
		if distance < 1000:  # Within reasonable distance = same area
			add_known_npc(other_id, "acquaintance", 3)
			discovered_count += 1
	
	print("[%s] Discovered %d nearby NPCs" % [npc_name, discovered_count])

## Check states of all known NPCs (called on initialization)
func _check_known_npc_states():
	if known_npcs.is_empty():
		return
	
	print("[%s] Checking states of %d known NPCs..." % [npc_name, known_npcs.size()])
	
	for other_npc_id in known_npcs.keys():
		var relationship = known_npcs[other_npc_id]
		var state = await check_other_npc_state(other_npc_id)

		if not state.get("is_alive", true):
			# React to death based on relationship type
			await react_to_npc_death(other_npc_id, other_npc_id, relationship.get("type", "acquaintance"))

## Add NPC to known registry (with auto-pruning if > MAX_KNOWN_NPCS)
func add_known_npc(other_npc_id: String, relationship_type: String = "acquaintance", importance: int = 5):
	# Skip if already known
	if known_npcs.has(other_npc_id):
		# Update last interaction time
		known_npcs[other_npc_id].last_interaction = Time.get_unix_time_from_system()
		return
	
	known_npcs[other_npc_id] = {
		"type": relationship_type,
		"importance": importance,
		"last_interaction": Time.get_unix_time_from_system()
	}
	
	print("[%s] Added %s to known NPCs (%s, importance: %d)" % [npc_name, other_npc_id, relationship_type, importance])
	
	# Auto-prune if exceeds limit
	if known_npcs.size() > MAX_KNOWN_NPCS:
		_prune_least_important_relationships()

## Remove least important/oldest relationships to maintain MAX_KNOWN_NPCS limit
func _prune_least_important_relationships():
	var sorted_npcs = []
	
	for other_npc_id in known_npcs.keys():
		var data = known_npcs[other_npc_id]
		
		# Never prune family (importance >= 10)
		if data.importance >= 10:
			continue
		
		# Score = importance - recency_penalty
		var time_since_interaction = Time.get_unix_time_from_system() - data.last_interaction
		var recency_penalty = time_since_interaction / 86400.0  # Days since last interaction
		var score = data.importance - recency_penalty
		
		sorted_npcs.append({"id": other_npc_id, "score": score})
	
	# Sort by score (lowest first)
	sorted_npcs.sort_custom(func(a, b): return a.score < b.score)
	
	# Calculate how many to remove
	var to_remove = known_npcs.size() - MAX_KNOWN_NPCS
	
	# Remove lowest-scored NPCs
	for i in range(min(to_remove, sorted_npcs.size())):
		var npc_id_to_forget = sorted_npcs[i].id
		known_npcs.erase(npc_id_to_forget)
		print("[%s] Forgot about %s (low importance/old)" % [npc_name, npc_id_to_forget])

## The generic NPC system's relationship ledger (decay, last contact) for every NPC, or null
func _relationship_ledger() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry") if is_inside_tree() else null
	return registry.generics if registry and "generics" in registry and registry.generics else null

## Get NPC ID (used by other NPCs during discovery)
func get_npc_id() -> String:
	return npc_id

## Location System Methods

## Check if NPC is at a specific location
func is_at_location(location_id: String) -> bool:
	var effective_location = current_location if current_location != "" else home_location
	return effective_location == location_id

## Move NPC to a different location (for schedules, quests)
func move_to_location(location_id: String):
	current_location = location_id
	print("[%s] Moved to location: %s" % [npc_name, location_id])

## Get NPC's current effective location
func get_current_location() -> String:
	return current_location if current_location != "" else home_location

## ==============================================================================
## DEBUG: MEMORY & STATE INSPECTION
## ==============================================================================

## Dump all memories for this NPC (for debugging)
func debug_dump_memories() -> String:
	if rag_memory:
		return await rag_memory.dump_all_memories()
	return "[No RAGMemory instance]"

## Get memory statistics
func debug_get_memory_stats() -> Dictionary:
	if rag_memory:
		return await rag_memory.get_memory_stats()
	return {}

## Print full NPC state for debugging
func debug_print_state():
	print("\n=== NPC STATE: %s (%s) ===" % [npc_name, npc_id])
	print("Location: %s (home: %s)" % [get_current_location(), home_location])
	print("Alive: %s" % is_alive)
	if not is_alive:
		print("  Death cause: %s, killed by: %s" % [death_cause, killed_by])
	print("\nRelationship Dimensions:")
	print("  Trust: %.1f" % relationship_trust)
	print("  Respect: %.1f" % relationship_respect)
	print("  Affection: %.1f" % relationship_affection)
	print("  Fear: %.1f" % relationship_fear)
	print("  Familiarity: %.1f" % relationship_familiarity)
	print("  Legacy Status: %.1f" % relationship_status)
	print("\nKnown NPCs: %d" % known_npcs.size())
	for known_id in known_npcs:
		var info = known_npcs[known_id]
		print("  - %s (%s, importance: %d)" % [known_id, info.get("type", "?"), info.get("importance", 0)])

	# Print memory stats
	if rag_memory:
		var stats = await rag_memory.get_memory_stats()
		print("\nMemory Stats:")
		print("  Total: %d (Pinned: %d, Important: %d, Regular: %d)" % [
			stats.total, stats.pinned, stats.important, stats.regular
		])
		print("  By type: %s" % stats.by_type)

	# Print WorldEvents player facts
	if WorldEvents:
		print("\nWorldEvents Player Facts:")
		print("  Player name: %s" % WorldEvents.get_player_name())
		print("  Is known: %s" % WorldEvents.is_player_known())

	print("=== END STATE ===\n")

# =============================================================================
# COMBAT IN THE WORLD (docs/PLAYER_SYSTEMS.md §3): health, morale, being hit, staggering, yielding,
# dying. Combat resolves a hit and its hitbox calls take_hit(result, attacker); what the person does
# next is their soul's choice (CombatAI.decide). Endings become the player's deeds through CombatAI
# =============================================================================

signal combat_state_changed(npc_id: String, state: String)
signal called_for_help(npc_id: String, foe_key: String)

const CombatAIScript = preload("res://scripts/combat/combat_ai.gd")
const LoadoutsScript = preload("res://scripts/combat/loadouts.gd")
const CharacterTypesScript = preload("res://scripts/npcs/character_types.gd")
const BASE_HEALTH = 100.0
const STAGGER_MS = 800
const SPARE_MS = 8000              # a yielded person left unhit this long has been let go
const CALM_MS = 10000              # talk / call for help: unhit this long, the fight is over
const FIGHT_LEAVE_DISTANCE = 700.0 # the player this far from someone still fighting them has fled
const COMBAT_SPEED = 90.0
const COMBAT_REACH = 48.0
const NPC_ATTACK_SECONDS = 1.4

const BASE_POISE = 40.0
## Combat (scripts/combat/combat.gd) reads get_combat_profile: a weapons.json id and armour.json ids
@export var combat_weapon: String = "fists"
@export var combat_armour: Array = []
var max_health: float = BASE_HEALTH
var health: float = BASE_HEALTH
var morale: float = CombatAIScript.BASE_MORALE
## "" (not fighting) | fight | yield | flee | call_for_help | talk
var combat_state: String = ""
var combat_foe: Node = null         # whom they fight, flee or yielded to
var combat_side: String = ""        # an onlooker's side: defend | join
var last_combat_decision: Dictionary = {}
var staggered_until_ms: int = 0
var _fight: Dictionary = {}         # {foe_key, band, harm_recorded, help_recorded, last_hit_ms}
var _deciding: bool = false
var _attack_cooldown: float = 0.0
## Ranged fighting: arrows left (-1 = not yet counted out from the loadout), and whether the sidearm
## is drawn (a bow is no use at arm's length or with an empty quiver)
var arrows: int = -1
var wielding_sidearm: bool = false
const SIDEARM_BACK_OFF = 1.8       # the bow comes back out once the foe is this many close_ranges away
const MINOR_IN_LINE = 20.0         # pixels: a child this near the line of a shot holds the shot

## Combat key: npc key for the roster ("bjorn"), the instance id for generics
func combat_key() -> String:
	return CombatAIScript.key_of(self)

## Resistances by damage type (fraction shrugged off); Combat reads them when it resolves a hit
func get_resistances() -> Dictionary:
	return {}

func is_staggered() -> bool:
	return Time.get_ticks_msec() < staggered_until_ms

## What Combat resolves hits on this body with (weapon, armour, resistances, poise, health, minor).
## Weapon and armour: the scene body's own when set, else the loadout (resources/combat/loadouts.json);
## a minor's are always empty
## The weapon in hand is the sidearm once it is drawn (closed on, or out of arrows); skills come from
## the character type (resources/characters/character_types.json), ordinary folk have none
func get_combat_profile() -> Dictionary:
	var minor = CombatAIScript.is_minor(combat_key())
	var kit = combat_loadout(minor)
	var own = not minor  # a child carries nothing, whatever the body was given
	var main = combat_weapon if own and combat_weapon != "fists" else str(kit.weapon)
	var kind = character_kind() if own else CharacterTypesScript.neutral()
	return {"weapon": sidearm_id() if own and wielding_sidearm else main, "main_weapon": main,
		"armour": combat_armour.duplicate() if own and not combat_armour.is_empty() else kit.armour.duplicate(),
		"resist": get_resistances(), "poise": BASE_POISE, "health": max_health, "skills": kind.skills.duplicate(),
		"difficulty": 1.0, "minor": minor}

## What kind of person this is (CharacterTypes): a main NPC by world.json key. GenericNPC answers by
## its archetype's type
func character_kind() -> Dictionary:
	return CharacterTypesScript.of_key(combat_key())

## The melee weapon drawn when the bow is no use (loadout `sidearm`, else fists)
func sidearm_id() -> String:
	var s = str(combat_loadout(CombatAIScript.is_minor(combat_key())).get("sidearm", ""))
	return s if s != "" else "fists"

## Arrows left for the bow (Combat asks before a shot and spends one after it)
func arrows_left() -> int:
	if arrows < 0:
		arrows = int(combat_loadout(CombatAIScript.is_minor(combat_key())).get("arrows", 0))
	return arrows

func spend_arrow() -> void:
	arrows = maxi(arrows_left() - 1, 0)

## The main weapon is a bow or sling (weapons.json kind ranged)
func has_ranged_weapon() -> bool:
	var combat = get_node_or_null("/root/Combat") if is_inside_tree() else null
	if combat == null or not combat.has_method("get_weapon_def"):
		return false
	return str(combat.get_weapon_def(str(get_combat_profile().get("main_weapon", "fists"))).get("kind", "")) == "ranged"

## This person's loadout by roster key (GenericNPC answers by archetype). Minors carry nothing
func combat_loadout(minor: bool = false) -> Dictionary:
	return LoadoutsScript.for_npc(combat_key(), minor)

## Combat.apply_hit_to's entry point. Combat records the harm deed itself, so this one does not
func take_combat_hit(result: Dictionary, attacker) -> Dictionary:
	return take_hit(result, attacker, true)

## Combat staggered this body (poise broken, a parry, a guard given way)
func on_staggered(seconds: float) -> void:
	staggered_until_ms = maxi(staggered_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))

## A resolved hit lands: result {damage, type, staggered, killed} from Combat.resolve_hit.
## from_combat: it came through Combat, which records the harm deed and closes its own fight record.
## Returns {health, staggered, dead, state} or {refused, reason} (a child struck by anyone but the
## player, the dead)
func take_hit(result: Dictionary, attacker, from_combat: bool = false) -> Dictionary:
	if not is_alive:
		return {"refused": true, "reason": "dead"}
	var key = combat_key()
	var foe_key = CombatAIScript.key_of(attacker)
	if not CombatAIScript.can_target(key, foe_key):
		return {"refused": true, "reason": "never a target (a child)"}
	var now = Time.get_ticks_msec()
	var by_player = foe_key == CombatAIScript.PLAYER
	var first = _fight.is_empty()
	if first:
		_fight = {"foe_key": foe_key, "band": "", "harm_recorded": false, "help_recorded": false}
	_fight["last_hit_ms"] = now
	health = maxf(health - maxf(float(result.get("damage", 0.0)), 0.0), 0.0)
	if bool(result.get("staggered", false)):
		staggered_until_ms = now + STAGGER_MS
	# Struck while fighting someone else: the player has stood up for that someone
	if by_player and combat_state == "fight" and is_instance_valid(combat_foe) and combat_foe != attacker and not _fight.help_recorded:
		_fight.help_recorded = true
		CombatAIScript.record_help(CombatAIScript.key_of(combat_foe), key, _scene_root(), global_position,
			{"witnesses": [CombatAIScript.key_of(combat_foe), key], "location": get_current_location()})
	if bool(result.get("killed", false)) or health <= 0.0:
		_die_in_combat(attacker, foe_key, result, from_combat)
		return {"health": 0.0, "staggered": false, "dead": true, "state": ""}
	if by_player and not _fight.harm_recorded:
		_fight.harm_recorded = true
		if not from_combat:
			CombatAIScript.record_harm(key, _scene_root(), global_position, {"witnesses": [key], "location": get_current_location()})
	if first:
		_tell_onlookers(attacker)
	react_to_hit(attacker)
	return {"health": health, "staggered": is_staggered(), "dead": false, "state": combat_state}

## Morale after this hit; the soul decides again when it falls into a new band (steady, wavering, broken)
func react_to_hit(attacker) -> void:
	var situation = {"kind": "attacked", "attacker": CombatAIScript.key_of(attacker),
		"health_fraction": health / maxf(max_health, 1.0), "allies_down": _allies_down(attacker)}
	morale = CombatAIScript.morale_for(combat_key(), situation)
	var b = CombatAIScript.band(morale)
	if _deciding or (b == str(_fight.get("band", "")) and combat_state != ""):
		return
	_fight["band"] = b
	_deciding = true
	situation["morale"] = morale
	var d: Dictionary = await CombatAIScript.decide_full(combat_key(), situation)
	_deciding = false
	if is_alive:
		_set_combat_state(d, attacker)

## An onlooker sees `attacker` strike `victim` (bodies: the player, an NPC)
func see_fight(attacker, victim) -> void:
	if not is_alive or combat_state != "" or _deciding or attacker == self or victim == self:
		return
	var situation = {"kind": "witness", "attacker": CombatAIScript.key_of(attacker), "victim": CombatAIScript.key_of(victim),
		"health_fraction": health / maxf(max_health, 1.0)}
	_deciding = true
	var d: Dictionary = await CombatAIScript.decide_full(combat_key(), situation)
	_deciding = false
	if not is_alive:
		return
	_fight = {"foe_key": "", "band": str(d.band), "harm_recorded": false, "help_recorded": false, "last_hit_ms": Time.get_ticks_msec()}
	var foe = attacker if str(d.side) != "join" else victim
	_set_combat_state(d, foe)

## The player lets a yielded person go: `spared`. False when they had not yielded
func spare(by = null) -> bool:
	if not is_alive or combat_state != "yield":
		return false
	var by_key = CombatAIScript.key_of(by if by != null else combat_foe)
	if by_key == CombatAIScript.PLAYER:
		CombatAIScript.record_spared(combat_key(), _scene_root(), global_position, {"witnesses": [combat_key()], "location": get_current_location()})
	end_fight("spared")
	return true

## how: spared | fled | yielded | talked_down | killed | over. tell_combat: close Combat's own record of
## the fight (it emits fight_ended), false when Combat is the one closing it
func end_fight(how: String = "over", tell_combat: bool = true) -> void:
	var info = {"npc": combat_key(), "foe": str(_fight.get("foe_key", CombatAIScript.key_of(combat_foe))), "how": how, "state": combat_state}
	var foe = combat_foe if is_instance_valid(combat_foe) else null
	combat_state = ""
	combat_foe = null
	combat_side = ""
	_fight = {}
	wielding_sidearm = false  # the bow goes back on the shoulder; the quiver stays as it is
	velocity = Vector2.ZERO
	morale = maxf(morale, CombatAIScript.WAVER)
	combat_state_changed.emit(npc_id, "")
	var combat = get_node_or_null("/root/Combat") if is_inside_tree() else null
	if not tell_combat or combat == null:
		return
	if combat.has_method("end_fight") and foe != null:
		combat.end_fight(self, foe, how, info)
	elif combat.has_signal("fight_ended") and not combat.has_method("end_fight"):
		combat.fight_ended.emit(info)

func _set_combat_state(d: Dictionary, foe) -> void:
	last_combat_decision = d
	combat_state = str(d.action)
	combat_side = str(d.get("side", ""))
	combat_foe = foe
	combat_state_changed.emit(npc_id, combat_state)
	if combat_state == "call_for_help" or bool(d.get("cry", false)):
		called_for_help.emit(npc_id, CombatAIScript.key_of(foe))
	if bool(d.get("cry", false)) and foe is Node:
		CombatAIScript.raise_cry(self, foe)  # a child's scream: grown-ups in earshot decide whether to come

## Combat records no kill and calls no die(): both are this body's (a killing blow through Combat ends
## Combat's fight record with reason "killed" itself)
func _die_in_combat(attacker, foe_key: String, result: Dictionary, from_combat: bool = false) -> void:
	var key = combat_key()
	var cause = "%s wounds from a fight" % str(result.get("type", "")) if str(result.get("type", "")) != "" else "wounds from a fight"
	if foe_key == CombatAIScript.PLAYER:
		CombatAIScript.record_kill(key, _scene_root(), global_position, {"location": get_current_location(), "cause": cause})
	else:
		CombatAIScript.register_death(key, cause, foe_key if foe_key != "" else "unknown")
	if not _fight.is_empty():
		end_fight("killed", not from_combat)
	die(cause, foe_key if foe_key != "" else "unknown")

## Everyone who can see this body is drawn into the fight (once, on its first blow)
func _tell_onlookers(attacker) -> void:
	var root = _scene_root()
	if root == null:
		return
	var ids = CombatAIScript.Witnesses.in_sight(root, global_position, {"exclude": [npc_id]})
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc != self and npc != attacker and str(npc.get("npc_id")) in ids and npc.has_method("see_fight"):
			npc.see_fight(attacker, self)

## People on this side of the fight who are down (dead or yielded) to the same foe
func _allies_down(foe) -> int:
	if not is_inside_tree() or foe == null:
		return 0
	var n = 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc != self and npc.get("combat_foe") == foe and (npc.get("is_alive") == false or npc.get("combat_state") == "yield"):
			n += 1
	return n

## The loaded scene this body stands in (the topmost node under the tree root)
func _scene_root() -> Node:
	if not is_inside_tree():
		return null
	var node: Node = self
	while node.get_parent() and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node

func _physics_process(delta: float) -> void:
	if combat_state == "" or not is_alive:
		return
	combat_tick(delta)

## One step of a fight: close and strike, run, or stand yielded; and notice how it ends
func combat_tick(delta: float) -> void:
	var now = Time.get_ticks_msec()
	if not is_instance_valid(combat_foe) or combat_foe.get("is_alive") == false:
		end_fight("over")
		return
	var foe_key = CombatAIScript.key_of(combat_foe)
	var to_foe: Vector2 = combat_foe.global_position - global_position
	var quiet_ms = now - int(_fight.get("last_hit_ms", now))
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	velocity = Vector2.ZERO
	match combat_state:
		"fight":
			if foe_key == CombatAIScript.PLAYER and to_foe.length() > FIGHT_LEAVE_DISTANCE:
				CombatAIScript.record_fled([combat_key()], _scene_root(), global_position, {"witnesses": [combat_key()], "location": get_current_location()})
				end_fight("fled")
				return
			if is_staggered():
				pass
			elif has_ranged_weapon():
				ranged_step(to_foe, foe_key)
			else:
				_melee_step(to_foe, foe_key)
		"flee":
			if to_foe.length() > FIGHT_LEAVE_DISTANCE:
				end_fight("fled")
				return
			velocity = -to_foe.normalized() * COMBAT_SPEED * 1.2
		"yield":
			if foe_key == CombatAIScript.PLAYER and (quiet_ms >= SPARE_MS or to_foe.length() > FIGHT_LEAVE_DISTANCE):
				spare(combat_foe)
				return
		_:
			if quiet_ms >= CALM_MS:
				end_fight("talked_down" if combat_state == "talk" else "parted")
				return
	if velocity != Vector2.ZERO and is_inside_tree():
		move_and_slide()

## Close and strike with what is in hand
func _melee_step(to_foe: Vector2, foe_key: String) -> void:
	if to_foe.length() > COMBAT_REACH:
		velocity = to_foe.normalized() * COMBAT_SPEED
	elif _attack_cooldown <= 0.0 and CombatAIScript.can_target(foe_key):
		_attack_cooldown = NPC_ATTACK_SECONDS
		var combat = get_node_or_null("/root/Combat")
		if combat and combat.has_method("attack"):
			combat.attack(self, combat_foe, "light")

## One step of a fight with a bow (tactics from the character type, CharacterTypes.DEFAULT_TACTICS
## for anyone else): hold the foe between keep_range[0] and keep_range[1], close in to get a clear
## line (walls on world_solid block it), loose when the draw is ready, never with a child in the line
## of the shot; draw the sidearm when closed on (close_range) or the quiver is empty, and put it away
## again once there is room. Returns what it did: shoot | hold | close | back_off | draw_sidearm |
## draw_bow | melee | wait
func ranged_step(to_foe: Vector2, foe_key: String) -> String:
	var kind = character_kind()
	var t = CharacterTypesScript.tactics(kind)
	var d = to_foe.length()
	var close = float(t.close_range)
	if wielding_sidearm:
		if arrows_left() > 0 and d > close * SIDEARM_BACK_OFF:
			wielding_sidearm = false
			_attack_cooldown = maxf(_attack_cooldown, float(t.switch_seconds))
			return "draw_bow"
		_melee_step(to_foe, foe_key)
		return "melee"
	if d <= close or arrows_left() <= 0:
		wielding_sidearm = true
		_attack_cooldown = maxf(_attack_cooldown, float(t.switch_seconds))
		return "draw_sidearm"
	var combat = get_node_or_null("/root/Combat") if is_inside_tree() else null
	var keep: Array = t.keep_range
	var reach = float(combat.get_weapon_def(str(get_combat_profile().main_weapon)).get("reach", 400)) if combat else 400.0
	var clear = combat != null and combat.has_method("has_line_of_sight") and combat.has_line_of_sight(self, combat_foe)
	var did = "wait"
	if not clear or d > minf(float(keep[1]), reach):
		velocity = to_foe.normalized() * COMBAT_SPEED
		did = "close"
	elif d < float(keep[0]) and CharacterTypesScript.has_trait(kind, "keeps_distance"):
		velocity = -to_foe.normalized() * COMBAT_SPEED  # give ground while drawing
		did = "back_off"
	if not clear or d > reach or _attack_cooldown > 0.0 or not CombatAIScript.can_target(foe_key):
		return did
	if combat.has_method("minor_in_line") and combat.minor_in_line(self, combat_foe, MINOR_IN_LINE):
		return "hold"  # a child between them and the foe: no shot is worth that
	var shot = combat.attack(self, combat_foe, "shoot")
	if shot.has("projectile"):
		_attack_cooldown = CharacterTypesScript.shoot_seconds(kind)
		return "shoot"
	if str(shot.get("refused", "")) == "no_ammo":
		wielding_sidearm = true
		return "draw_sidearm"
	return did
