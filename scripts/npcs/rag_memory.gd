extends Node
# RAGMemory - High-level NPC memory wrapper for ChromaDB
# Simplifies storing and retrieving NPC experiences with semantic search
# Phase 2: Now supports tiered memory hierarchy for consistent recall
# Uses MemoryConfig resource for data-driven configuration

var chroma_client: Node
var npc_id: String
var collection_name: String
var use_chromadb: bool = true  # Set to false for in-memory fallback
var memory_cache: Array = []  # In-memory fallback storage

## Memory configuration resource (data-driven, no hardcoding)
var memory_config: Resource = null
const DEFAULT_CONFIG_PATH = "res://resources/memory_config.tres"

## Memory Tier Constants (kept for type safety, values from config)
enum MemoryTier {
	PINNED = 0,     # Always included (relationship-defining moments)
	IMPORTANT = 1,  # High priority (significant events)
	REGULAR = 2     # Normal semantic retrieval
}

signal memory_added(memory_id: String)
signal memories_recalled(count: int)
signal milestone_created(milestone_type: String)

func _ready():
	# Load memory config if not already set
	_load_config()

## Load memory configuration resource
func _load_config() -> void:
	if memory_config != null:
		return

	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		memory_config = load(DEFAULT_CONFIG_PATH)
		print("[RAGMemory] Loaded memory config from %s" % DEFAULT_CONFIG_PATH)
	else:
		push_warning("[RAGMemory] No memory config found, using defaults")
		# Create default config in memory
		memory_config = load("res://scripts/resources/memory_config.gd").new()

## Set custom memory config (for per-NPC overrides)
func set_config(config: Resource) -> void:
	memory_config = config
	print("[RAGMemory] Custom memory config set")

## Get current config values (with fallbacks)
func _get_max_pinned() -> int:
	if memory_config:
		return memory_config.max_pinned_memories
	return 5

func _get_max_important() -> int:
	if memory_config:
		return memory_config.max_important_memories
	return 3

func _get_max_regular() -> int:
	if memory_config:
		return memory_config.max_regular_memories
	return 5

func _get_max_chars() -> int:
	if memory_config:
		return memory_config.max_memory_chars
	return 3000

## Find existing player_info memory by info_type (for deduplication)
## Returns the memory dict if found, null otherwise
func _find_player_info_memory(info_type: String) -> Variant:
	if not use_chromadb:
		# In-memory search
		for mem in memory_cache:
			var meta = mem.get("metadata", {})
			if meta.get("event_type") == "player_info" and meta.get("info_type") == info_type:
				return mem
		return null

	# ChromaDB: Query all player_info memories and filter by info_type
	if chroma_client == null:
		return null

	var result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "player info " + info_type,  # Semantic hint
		"limit": 10,  # Get several to filter
		"min_importance": 1  # Include all
	})

	if result is Array:
		for mem in result:
			var meta = mem.get("metadata", {})
			if meta.get("event_type") == "player_info" and meta.get("info_type") == info_type:
				return mem

	return null

## Initialize RAG memory for a specific NPC
## npc_identifier: Unique NPC ID like "aldric_blacksmith"
func initialize(npc_identifier: String, chroma_client_instance: Node = null, use_db: bool = true) -> bool:
	_load_config()
	npc_id = npc_identifier
	collection_name = "npc_%s_memories" % npc_id.to_lower().replace(" ", "_")
	use_chromadb = use_db
	
	if not use_chromadb:
		print("RAGMemory initialized for NPC: %s (IN-MEMORY MODE - no persistence)" % npc_id)
		return true
	
	# Use provided ChromaClient or create new one
	if chroma_client_instance:
		chroma_client = chroma_client_instance
	else:
		chroma_client = load("res://scripts/memory/chroma_client.gd").new()
		add_child(chroma_client)
	
	# Create collection for this NPC
	print("[RAGMemory] Creating collection: %s" % collection_name)
	var result = await chroma_client.create_collection(collection_name)
	
	print("[RAGMemory] Collection creation result: %s" % JSON.stringify(result))
	
	if result.has("error") and not "already exists" in result.error.to_lower():
		push_warning("ChromaDB failed, falling back to in-memory: " + result.error)
		use_chromadb = false
		return true
	
	print("RAGMemory initialized for NPC: %s (collection: %s)" % [npc_id, collection_name])
	return true

## Store a memory from the NPC's perspective
## memory_data: {
##   text: String - What the NPC remembers (from their POV)
##   event_type: String - "conversation", "witnessed_crime", "quest_completed", etc.
##   importance: int - 1-10 scale for retrieval priority
##   emotion: String - NPC's emotional reaction (optional)
##   participants: Array - Who was involved (optional)
##   location: String - Where it happened (optional)
##   memory_tier: int - 0=pinned, 1=important, 2=regular (auto-detected if not set)
##   is_milestone: bool - Whether this is a relationship milestone (auto-detected)
##   milestone_type: String - Type of milestone if applicable
##   info_type: String - For player_info: "player_name", "player_origin", etc. (for deduplication)
## }
## custom_id: Optional custom ID (for state updates that should replace previous state)
## skip_validation: Skip WorldEvents validation (use for system memories only)
func store(memory_data: Dictionary, custom_id: String = "", skip_validation: bool = false) -> bool:
	if not memory_data.has("text"):
		push_error("Memory must have 'text' field")
		return false

	# DEDUPLICATION: For player_info memories with info_type, check if already stored
	var event_type = memory_data.get("event_type", "general")
	var info_type = memory_data.get("info_type", "")
	if event_type == "player_info" and not info_type.is_empty():
		var existing = await _find_player_info_memory(info_type)
		if existing != null:
			var existing_text = existing.get("document", existing.get("text", ""))
			if existing_text == memory_data.text:
				print("[RAGMemory] DEDUP: Skipping duplicate player_info (%s): %s" % [info_type, memory_data.text.substr(0, 50)])
				return true  # Already stored, skip
			else:
				# Info changed, update by using existing ID
				print("[RAGMemory] DEDUP: Updating player_info (%s): %s -> %s" % [info_type, existing_text.substr(0, 30), memory_data.text.substr(0, 30)])
				custom_id = existing.get("id", "")

	# VALIDATION: Check memory for hallucinations before storing
	if not skip_validation and WorldEvents:
		var validation = WorldEvents.validate_memory(memory_data.text, npc_id)
		if not validation.valid:
			push_warning("[RAGMemory] Memory REJECTED for %s: %s" % [npc_id, validation.issues])
			print("[RAGMemory] Rejected memory text: %s" % memory_data.text.substr(0, 100))
			return false

		# Use sanitized version if corrections were made
		if validation.sanitized != memory_data.text:
			print("[RAGMemory] Memory sanitized: %s" % validation.issues)
			memory_data.text = validation.sanitized

	# Generate unique memory ID (or use custom for state updates)
	var memory_id = custom_id
	if memory_id == "":
		var timestamp = Time.get_unix_time_from_system()
		memory_id = "%s_%d_%s" % [npc_id, timestamp, event_type]

	# Auto-detect memory tier and milestones
	var importance = memory_data.get("importance", 5)
	var detected_tier = _detect_memory_tier(event_type, importance, memory_data)
	var detected_milestone = _detect_milestone_type(event_type, memory_data)

	# Build metadata - include ALL fields from memory_data
	var metadata = {
		"event_type": event_type,
		"importance": importance,
		"timestamp": Time.get_unix_time_from_system(),
		"npc_id": npc_id,
		# Phase 2: Memory hierarchy metadata
		"memory_tier": memory_data.get("memory_tier", detected_tier),
		"is_milestone": detected_milestone != "",
		"milestone_type": detected_milestone
	}

	# Add all custom fields from memory_data to metadata
	for key in memory_data.keys():
		if key != "text" and not metadata.has(key):
			var value = memory_data[key]
			# Convert arrays to comma-separated strings for ChromaDB
			if value is Array:
				metadata[key] = ",".join(value)
			else:
				metadata[key] = value

	# Emit milestone signal if detected
	if detected_milestone != "":
		milestone_created.emit(detected_milestone)
		print("[RAGMemory] MILESTONE detected: %s" % detected_milestone)

	# Phase 4: Generate dual representations (short + full forms)
	var full_text = memory_data.text
	var short_text = full_text
	if _use_dual_representation():
		short_text = _summarize_to_short(full_text, event_type)
		if short_text != full_text:
			print("[RAGMemory] Dual rep: full=%d chars, short=%d chars" % [full_text.length(), short_text.length()])

	# Store in memory
	if not use_chromadb:
		# In-memory fallback
		var mem_entry = {
			"id": memory_id,
			"document": short_text,  # Default to short form for backwards compat
			"metadata": metadata
		}
		# Store both forms if dual representation enabled
		if _use_dual_representation():
			mem_entry["document_short"] = short_text
			mem_entry["document_full"] = full_text
		memory_cache.append(mem_entry)
		memory_added.emit(memory_id)
		print("[RAGMemory IN-MEMORY] Stored: %s" % short_text.substr(0, 50))
		return true

	# Store in ChromaDB
	print("[RAGMemory] Storing memory in ChromaDB: %s" % memory_id)
	var store_data = {
		"collection": collection_name,
		"id": memory_id,
		"document": short_text,  # Default to short form for embedding
		"metadata": metadata
	}
	# Store both forms in metadata if dual representation enabled
	if _use_dual_representation():
		store_data["document_short"] = short_text
		store_data["document_full"] = full_text
	var result = await chroma_client.add_memory(store_data)
	
	print("[RAGMemory] ChromaDB store result: %s" % JSON.stringify(result))
	
	if result.has("error"):
		push_error("Failed to store memory: " + result.error)
		return false
	
	memory_added.emit(memory_id)
	print("[RAGMemory] Memory stored successfully: %s" % memory_data.text.substr(0, 60))
	return true

## Retrieve relevant memories based on current context
## context: String - Current situation or conversation topic
## options: {
##   limit: int - Max memories to retrieve (default: 5)
##   min_importance: int - Filter out low-importance memories (default: 4)
##   event_filter: String - Only retrieve specific event types (optional)
## }
## Returns: Array of memory strings formatted for Claude context
func retrieve_relevant(context: String, options: Dictionary = {}) -> Array[String]:
	var limit = options.get("limit", 5)
	var min_importance = options.get("min_importance", 4)
	
	# In-memory fallback
	if not use_chromadb:
		print("[RAGMemory IN-MEMORY] Retrieving memories (total: %d)" % memory_cache.size())
		var formatted_memories: Array[String] = []
		
		# Simple keyword matching (not semantic, but works for demo)
		var context_lower = context.to_lower()
		var scored_memories = []
		
		for mem in memory_cache:
			if mem.metadata.importance < min_importance:
				continue
			
			# Simple relevance scoring based on keyword overlap
			var mem_lower = mem.document.to_lower()
			var score = 0.0
			
			# Split context into words and count matches
			for word in context_lower.split(" "):
				if word.length() > 3 and word in mem_lower:
					score += 1.0
			
			# Boost recent and important memories
			var recency = Time.get_unix_time_from_system() - mem.metadata.timestamp
			score += mem.metadata.importance * 0.5
			score += max(0, (3600 - recency) / 3600.0)  # Recent boost (within last hour)
			
			scored_memories.append({"memory": mem, "score": score})
		
		# Sort by score descending
		scored_memories.sort_custom(func(a, b): return a.score > b.score)
		
		# Take top N and format
		for i in range(min(limit, scored_memories.size())):
			var mem = scored_memories[i].memory
			var meta = mem.metadata
			
			var formatted = "[Memory - %s, importance: %d" % [
				meta.get("event_type", "unknown"),
				meta.get("importance", 5)
			]
			
			if meta.has("emotion"):
				formatted += ", felt: %s" % meta.emotion
			
			formatted += "] %s" % mem.document
			formatted_memories.append(formatted)
		
		print("[RAGMemory IN-MEMORY] Returning %d relevant memories" % formatted_memories.size())
		memories_recalled.emit(formatted_memories.size())
		return formatted_memories
	
	# Query ChromaDB with semantic search
	var query_params = {
		"collection": collection_name,
		"query": context,
		"limit": limit,
		"min_importance": min_importance
	}
	
	print("[RAGMemory] Querying ChromaDB for memories...")
	var raw_memories = await chroma_client.query_memories(query_params)
	print("[RAGMemory] Retrieved %d memories" % raw_memories.size())
	
	# Format memories for Claude context
	var formatted_memories: Array[String] = []
	
	for memory in raw_memories:
		var text = memory.document
		var meta = memory.metadata
		
		# Add context markers for Claude
		var formatted = "[Memory - %s, importance: %d" % [
			meta.get("event_type", "unknown"),
			meta.get("importance", 5)
		]
		
		if meta.has("emotion"):
			formatted += ", felt: %s" % meta.emotion
		
		formatted += "] " + text
		formatted_memories.append(formatted)
	
	memories_recalled.emit(formatted_memories.size())
	return formatted_memories

## Retrieve relevant memories with full metadata for AI agent growth
## Returns raw memory objects for categorization in context building
## This allows NPCs to "grow" as they reference different types of experiences
func retrieve_relevant_raw(context: String, options: Dictionary = {}) -> Array:
	var limit = options.get("limit", 5)
	var min_importance = options.get("min_importance", 4)
	var raw_memories = []
	
	# ChromaDB path
	if use_chromadb:
		print("[RAGMemory] Querying ChromaDB for raw memories...")
		var result = chroma_client.query_memories({
			"collection": collection_name,
			"query": context,
			"limit": limit,
			"min_importance": min_importance
		})
		
		if result.has("memories"):
			for mem in result.memories:
				raw_memories.append({
					"document": mem.get("document", ""),
					"event_type": mem.get("metadata", {}).get("event_type", "unknown"),
					"importance": mem.get("metadata", {}).get("importance", 5),
					"emotion": mem.get("metadata", {}).get("emotion", ""),
					"timestamp": mem.get("metadata", {}).get("timestamp", 0),
					"distance": mem.get("distance", 0.0)
				})
	else:
		# In-memory fallback with scoring
		var scored_memories = []
		var context_lower = context.to_lower()
		
		for mem in memory_cache:
			if mem.metadata.importance < min_importance:
				continue
			
			var mem_lower = mem.document.to_lower()
			var score = 0.0
			
			for word in context_lower.split(" "):
				if word.length() > 3 and word in mem_lower:
					score += 1.0
			
			score += mem.metadata.importance * 0.5
			var recency = Time.get_unix_time_from_system() - mem.metadata.timestamp
			score += max(0, (3600 - recency) / 3600.0)
			
			scored_memories.append({"memory": mem, "score": score})
		
		scored_memories.sort_custom(func(a, b): return a.score > b.score)
		
		for i in range(min(limit, scored_memories.size())):
			var mem = scored_memories[i].memory
			raw_memories.append({
				"document": mem.document,
				"event_type": mem.metadata.get("event_type", "unknown"),
				"importance": mem.metadata.get("importance", 5),
				"emotion": mem.metadata.get("emotion", ""),
				"timestamp": mem.metadata.get("timestamp", 0)
			})
	
	return raw_memories

## Get recent memories (chronological, not semantic)
## count: Number of recent memories to retrieve
## min_importance: Optional importance filter
func get_recent(count: int = 5, min_importance: int = 0) -> Array[String]:
	# Use generic query to get all, then sort by timestamp
	var query_params = {
		"collection": collection_name,
		"query": "recent events interactions",  # Generic query
		"limit": count * 2  # Get more than needed for filtering
	}
	
	if min_importance > 0:
		query_params["min_importance"] = min_importance
	
	var raw_memories = await chroma_client.query_memories(query_params)
	
	# Sort by timestamp (newest first)
	raw_memories.sort_custom(func(a, b):
		var timestamp_a = a.metadata.get("timestamp", 0)
		var timestamp_b = b.metadata.get("timestamp", 0)
		return timestamp_a > timestamp_b
	)
	
	# Take only requested count
	raw_memories = raw_memories.slice(0, min(count, raw_memories.size()))
	
	# Format for Claude
	var formatted: Array[String] = []
	for memory in raw_memories:
		formatted.append(memory.document)
	
	return formatted

## Get memory count for this NPC
func get_memory_count() -> int:
	return await chroma_client.get_collection_count(collection_name)

## Clear all memories (use with caution!)
func clear_all_memories() -> bool:
	# Clear in-memory cache regardless of mode
	memory_cache.clear()

	if use_chromadb and chroma_client:
		var result = await chroma_client.delete_collection(collection_name)
		if not result.has("error"):
			# Recreate empty collection
			await chroma_client.create_collection(collection_name)
			print("[RAGMemory] Cleared all memories for %s (ChromaDB)" % npc_id)
			return true
		return false
	else:
		print("[RAGMemory] Cleared all memories for %s (in-memory)" % npc_id)
		return true

## Helper: Store a conversation turn with rich context
## speaker: "player" or "npc"
## message: The actual message text
## context: Optional dictionary with:
##   - emotion: How the NPC felt (string)
##   - topics: Array of discussed topics (e.g., ["bandits", "quest"])
##   - intent: Player's intent (e.g., "asking_for_help", "refusing", "thanking")
##   - importance: Override default importance (int 1-10)
func store_conversation(speaker: String, message: String, context: Dictionary = {}) -> bool:
	var memory_text = ""
	var emotion = context.get("emotion", "")
	var topics = context.get("topics", [])
	var intent = context.get("intent", "")
	var importance = context.get("importance", 6)
	
	if speaker == "player":
		# Store from NPC's perspective
		memory_text = "Player said: \"%s\"" % message
		
		if topics.size() > 0:
			memory_text += " (discussing: %s)" % ", ".join(topics)
		
		if intent:
			memory_text += " [Player seemed to be %s]" % intent
		
		if emotion:
			memory_text += " I felt %s about this." % emotion
	else:
		# Store NPC's own words
		memory_text = "I told the player: \"%s\"" % message
		
		if topics.size() > 0:
			memory_text += " (about: %s)" % ", ".join(topics)
	
	# Build metadata
	var metadata_dict = {
		"text": memory_text,
		"event_type": "conversation",
		"importance": importance,
		"participants": ["player", npc_id]
	}
	
	if emotion:
		metadata_dict["emotion"] = emotion
	
	# Store topics as searchable metadata
	if topics.size() > 0:
		metadata_dict["topics"] = topics
	
	if intent:
		metadata_dict["player_intent"] = intent
	
	return await store(metadata_dict)

## Helper: Store a witnessed event
func store_witnessed_event(event_description: String, importance: int = 7, emotion: String = "surprised") -> bool:
	return await store({
		"text": "I witnessed: " + event_description,
		"event_type": "witnessed_event",
		"importance": importance,
		"emotion": emotion,
		"participants": ["player"]
	})

## Helper: Store a player action (quest acceptance, item giving, etc.)
## action_type: "quest_accepted", "quest_refused", "item_given", "item_received", "helped", "refused_help"
## description: What happened from NPC's perspective
## importance: How significant (1-10, default 8 for actions)
## emotion: How NPC feels about the action
func store_player_action(action_type: String, description: String, importance: int = 8, emotion: String = "") -> bool:
	var memory_text = description
	
	return await store({
		"text": memory_text,
		"event_type": action_type,
		"importance": importance,
		"emotion": emotion if emotion else _default_emotion_for_action(action_type),
		"participants": ["player", npc_id]
	})

## Default emotions for different action types
func _default_emotion_for_action(action_type: String) -> String:
	match action_type:
		"quest_accepted": return "hopeful"
		"quest_refused": return "disappointed"
		"quest_completed": return "grateful"
		"quest_failed": return "frustrated"
		"item_given": return "grateful"
		"item_received": return "pleased"
		"helped": return "grateful"
		"refused_help": return "disappointed"
		_: return "neutral"

## Helper: Store a quest-related memory
func store_quest_memory(quest_id: String, outcome: String, importance: int = 8) -> bool:
	var memory_text = "Quest '%s' %s" % [quest_id, outcome]
	
	return await store({
		"text": memory_text,
		"event_type": "quest_completed",
		"importance": importance,
		"participants": ["player", npc_id]
	})

## ==============================================================================
## NPC STATE PERSISTENCE (Life/Death, Relationships)
## ==============================================================================

## Store NPC's current alive/dead state
func store_npc_state(is_alive: bool, death_data: Dictionary = {}) -> bool:
	var state_id = "npc_state_%s" % npc_id
	var memory_text = ""
	
	if is_alive:
		memory_text = "I am alive and well."
	else:
		memory_text = "I died. Killed by: %s. Cause: %s." % [
			death_data.get("killed_by", "unknown"),
			death_data.get("cause", "unknown")
		]
	
	return await store({
		"text": memory_text,
		"event_type": "npc_state",
		"importance": 10,
		"is_alive": is_alive,
		"death_cause": death_data.get("cause", "") if not is_alive else "",
		"killed_by": death_data.get("killed_by", "") if not is_alive else "",
		"death_timestamp": death_data.get("timestamp", 0.0) if not is_alive else 0.0
	}, state_id)

## Retrieve NPC's current state (alive/dead)
func get_npc_state() -> Dictionary:
	print("[RAGMemory] get_npc_state called for NPC: %s" % npc_id)
	
	if not use_chromadb:
		print("[RAGMemory] Using in-memory mode")
		# Check in-memory cache for state
		for memory in memory_cache:
			if memory.metadata.get("event_type") == "npc_state":
				return {
					"is_alive": memory.metadata.get("is_alive", true),
					"death_cause": memory.metadata.get("death_cause", ""),
					"killed_by": memory.metadata.get("killed_by", ""),
					"death_timestamp": memory.metadata.get("death_timestamp", 0.0)
				}
		return {"is_alive": true}
	
	# Get state memory by ID (direct lookup, not semantic search)
	var state_id = "npc_state_%s" % npc_id
	print("[RAGMemory] Looking up state by ID: %s" % state_id)
	var result = await chroma_client.get_memory_by_id(collection_name, state_id)
	print("[RAGMemory] Query result: %s" % JSON.stringify(result))
	
	if result != null and result.has("metadata"):
		var meta = result.metadata
		print("[RAGMemory] Found state metadata: is_alive=%s" % meta.get("is_alive", true))
		return {
			"is_alive": meta.get("is_alive", true),
			"death_cause": meta.get("death_cause", ""),
			"killed_by": meta.get("killed_by", ""),
			"death_timestamp": meta.get("death_timestamp", 0.0)
		}
	
	# Default: alive if no state found
	print("[RAGMemory] No state found, defaulting to alive")
	return {"is_alive": true}

## Store relationship state with another NPC or faction
func store_relationship(with_entity: String, relationship_data: Dictionary) -> bool:
	var rel_id = "relationship_%s_%s" % [npc_id, with_entity]
	var memory_text = "My relationship with %s: Trust=%d, Respect=%d, Affection=%d" % [
		with_entity,
		relationship_data.get("trust", 0),
		relationship_data.get("respect", 0),
		relationship_data.get("affection", 0)
	]
	
	return await store({
		"text": memory_text,
		"event_type": "relationship_state",
		"importance": 7,
		"with_entity": with_entity,
		"trust": relationship_data.get("trust", 0),
		"respect": relationship_data.get("respect", 0),
		"affection": relationship_data.get("affection", 0),
		"fear": relationship_data.get("fear", 0),
		"familiarity": relationship_data.get("familiarity", 0)
	}, rel_id)

## Get relationship state with another NPC/faction
func get_relationship(with_entity: String) -> Dictionary:
	if not use_chromadb:
		# Check in-memory cache
		for memory in memory_cache:
			var meta = memory.metadata
			if meta.get("event_type") == "relationship_state" and meta.get("with_entity") == with_entity:
				return {
					"trust": meta.get("trust", 0),
					"respect": meta.get("respect", 0),
					"affection": meta.get("affection", 0),
					"fear": meta.get("fear", 0),
					"familiarity": meta.get("familiarity", 0)
				}
		return {}
	
	# Query ChromaDB
	var result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": "relationship with " + with_entity,
		"limit": 1
	})
	
	if result.size() > 0:
		var meta = result[0].get("metadata", {})
		if meta.get("event_type") == "relationship_state" and meta.get("with_entity") == with_entity:
			return {
				"trust": meta.get("trust", 0),
				"respect": meta.get("respect", 0),
				"affection": meta.get("affection", 0),
				"fear": meta.get("fear", 0),
				"familiarity": meta.get("familiarity", 0)
			}
	
	return {}

## Check another NPC's state (death, alive, etc.) - Cross-NPC awareness
## other_npc_id: ID of NPC to check (e.g., "gregor_merchant_001")
## Returns: Dictionary {is_alive: bool, death_cause: String, killed_by: String, death_timestamp: float}
func check_npc_state(other_npc_id: String) -> Dictionary:
	var other_collection = "npc_%s_memories" % other_npc_id.to_lower().replace(" ", "_")
	var state_id = "npc_state_%s" % other_npc_id
	
	print("[RAGMemory] %s checking state of %s" % [npc_id, other_npc_id])
	
	if not use_chromadb:
		print("[RAGMemory] ChromaDB disabled - cannot check other NPC states")
		return {"is_alive": true}  # Assume alive in memory-only mode
	
	var result = await chroma_client.get_memory_by_id(other_collection, state_id)
	
	if result.has("error") or result.is_empty() or not result.has("metadata"):
		print("[RAGMemory] No state found for %s - assuming alive" % other_npc_id)
		return {"is_alive": true}

	var metadata = result.get("metadata", {})
	if metadata == null or typeof(metadata) != TYPE_DICTIONARY:
		print("[RAGMemory] Invalid metadata for %s - assuming alive" % other_npc_id)
		return {"is_alive": true}

	var state = {
		"is_alive": metadata.get("is_alive", true),
		"death_cause": metadata.get("death_cause", ""),
		"killed_by": metadata.get("killed_by", ""),
		"death_timestamp": metadata.get("death_timestamp", 0.0)
	}
	
	print("[RAGMemory] %s state: alive=%s, cause=%s, killer=%s" % [
		other_npc_id,
		state["is_alive"],
		state["death_cause"],
		state["killed_by"]
	])
	
	return state

## Store awareness of another NPC's state change (for cross-NPC reactions)
## other_npc_id: NPC whose state changed
## event_description: What this NPC learned/witnessed
## importance: 1-10 (death of loved one = 10)
func store_npc_awareness(other_npc_id: String, event_description: String, importance: int = 8) -> bool:
	var memory_data = {
		"text": event_description,
		"event_type": "npc_awareness",
		"importance": importance,
		"related_npc": other_npc_id,
		"emotion": "shocked"  # Can be overridden
	}

	print("[RAGMemory] %s storing awareness: %s" % [npc_id, event_description])
	return await store(memory_data)

## ==============================================================================
## PHASE 2: MEMORY HIERARCHY SYSTEM
## ==============================================================================

## Detect memory tier based on event type and importance
## Now uses MemoryConfig for data-driven rules
func _detect_memory_tier(event_type: String, importance: int, memory_data: Dictionary) -> int:
	# Check for explicit milestone markers
	if memory_data.get("is_milestone", false):
		return MemoryTier.PINNED

	# Get Claude's interaction type if available (from response analysis)
	var claude_interaction = memory_data.get("interaction_type", "")

	# Use config for tier detection
	if memory_config:
		return memory_config.get_tier_for_event(event_type, importance, claude_interaction)

	# Fallback if no config (shouldn't happen)
	if importance >= 8:
		return MemoryTier.IMPORTANT
	return MemoryTier.REGULAR

## Detect if this memory represents a relationship milestone
## Uses MemoryConfig for milestone type definitions
func _detect_milestone_type(event_type: String, memory_data: Dictionary) -> String:
	# Explicit milestone type
	if memory_data.has("milestone_type") and memory_data.milestone_type != "":
		return memory_data.milestone_type

	# Check for first-time events
	var is_first = memory_data.get("is_first", false)
	if is_first:
		match event_type:
			"conversation": return "first_meeting"
			"gift_received": return "first_gift"
			"quest_accepted", "quest_completed": return "first_quest"

	# Check if event type is a defined milestone in config
	if memory_config and event_type in memory_config.milestone_event_types:
		return event_type

	# Special case: detect family death from text content
	if event_type == "npc_awareness":
		var text_lower = memory_data.get("text", "").to_lower()
		if "died" in text_lower or "killed" in text_lower or "dead" in text_lower:
			return "family_death"

	return ""

## ==============================================================================
## SCORE-BASED SELECTION (Phase 1 Implementation)
## ==============================================================================

## Calculate memory score for selection priority
## Higher score = more likely to be included in context
## Formula: tier_weight × importance × recency × relevance × supersession_mult
func _calculate_memory_score(memory: Dictionary, query_context: String = "") -> float:
	var meta = memory.get("metadata", memory)

	# Tier weight (signal, not guarantee)
	var tier = meta.get("memory_tier", MemoryTier.REGULAR)
	var tier_weight = 1.0
	if memory_config and memory_config.tier_weights.size() > tier:
		tier_weight = memory_config.tier_weights[tier]
	else:
		tier_weight = [3.0, 2.0, 1.0][mini(tier, 2)]

	# Importance (1-10 normalized)
	var importance = meta.get("importance", 5) / 10.0

	# Recency decay with configurable half-life
	var half_life = memory_config.recency_half_life_days if memory_config else 7.0
	var recency_floor = memory_config.recency_floor if memory_config else 0.3
	var age_seconds = Time.get_unix_time_from_system() - meta.get("timestamp", 0)
	var age_days = age_seconds / 86400.0
	# Exponential decay: e^(-age * ln(2) / half_life)
	var recency = recency_floor + (1.0 - recency_floor) * exp(-age_days * 0.693 / half_life)

	# Semantic relevance (from ChromaDB distance, converted to similarity)
	var relevance_floor = memory_config.relevance_floor if memory_config else 0.3
	var distance = memory.get("distance", 0.5)
	var similarity = 1.0 - clamp(distance, 0.0, 1.0)
	var relevance = relevance_floor + (1.0 - relevance_floor) * similarity

	# Supersession penalty (history preserved but deprioritized)
	var supersession_mult = 1.0
	if meta.get("superseded_by", "") != "":
		supersession_mult = memory_config.superseded_score_multiplier if memory_config else 0.1

	var score = tier_weight * importance * recency * relevance * supersession_mult
	return score

## Check if score-based selection is enabled
func _use_score_based_selection() -> bool:
	if memory_config:
		return memory_config.use_score_based_selection
	return true  # Default to new behavior

## Check if bounded collection is enabled
func _use_bounded_collection() -> bool:
	if memory_config:
		return memory_config.use_bounded_collection
	return true  # Default to new behavior

## ==============================================================================
## BOUNDED CANDIDATE COLLECTION (Phase 2 Implementation)
## ==============================================================================

## Retrieve memories using bounded collection strategy
## Returns: Array of scored memory candidates within token budget
## Three sources: protected → high-signal recent → semantic top-K
func retrieve_scored(context: String, token_budget: int = -1) -> Array:
	if token_budget < 0:
		token_budget = memory_config.memory_token_budget if memory_config else 2500

	var all_candidates: Array = []
	var seen_ids: Dictionary = {}

	print("[RAGMemory] retrieve_scored: Starting bounded collection for '%s'" % context.substr(0, 50))

	# Source 1: Protected slot-based memories (always include, not scored)
	var protected = await _get_protected_memories()
	for mem in protected:
		var mem_id = mem.get("id", "")
		if mem_id != "":
			seen_ids[mem_id] = true
		mem["_protected"] = true
		mem["_score"] = 999.0  # Ensure protected always sorts first
		all_candidates.append(mem)
	print("[RAGMemory]   Source 1 (protected): %d memories" % protected.size())

	# Source 2: High-signal recent events (last N days)
	var recency_days = memory_config.high_signal_recency_days if memory_config else 7
	var high_signal_types = memory_config.high_signal_event_types if memory_config else [
		"betrayal", "life_saved", "secret_revealed", "promise_made", "promise_broken"
	]
	var high_signal_limit = memory_config.high_signal_limit if memory_config else 10

	var recent_high_signal = await _get_recent_by_types(high_signal_types, recency_days, high_signal_limit)
	var added_high_signal = 0
	for mem in recent_high_signal:
		var mem_id = mem.get("id", "")
		if mem_id != "" and not seen_ids.has(mem_id):
			seen_ids[mem_id] = true
			mem["_score"] = _calculate_memory_score(mem, context)
			all_candidates.append(mem)
			added_high_signal += 1
	print("[RAGMemory]   Source 2 (high-signal recent): %d memories" % added_high_signal)

	# Source 3: Top-K semantic search
	var top_k = memory_config.semantic_top_k if memory_config else 15
	var semantic = await _get_semantic_top_k(context, top_k)
	var added_semantic = 0
	for mem in semantic:
		var mem_id = mem.get("id", "")
		if mem_id != "" and not seen_ids.has(mem_id):
			seen_ids[mem_id] = true
			mem["_score"] = _calculate_memory_score(mem, context)
			all_candidates.append(mem)
			added_semantic += 1
	print("[RAGMemory]   Source 3 (semantic top-K): %d memories" % added_semantic)

	# Sort by score (protected first via high score, then by calculated score)
	all_candidates.sort_custom(func(a, b):
		return a.get("_score", 0) > b.get("_score", 0)
	)

	# Fill token budget
	var result = _fill_token_budget(all_candidates, token_budget)
	print("[RAGMemory] retrieve_scored: Selected %d memories within %d token budget" % [result.size(), token_budget])

	return result

## Get protected memories (slot-based, always included)
## Phase 3: Relationship header is generated on-the-fly, not stored
func _get_protected_memories() -> Array:
	var results: Array = []
	var protected_types = memory_config.protected_slot_types if memory_config else [
		"relationship_header", "player_name", "npc_death_status"
	]

	# Always include relationship header (generated, not stored)
	# This is a compact state blob, not a narrative memory
	var header = await generate_relationship_header()
	results.append(header)
	print("[RAGMemory] Generated relationship header: %s" % header.get("document", ""))

	# Get other protected slot types from storage
	var stored_types = protected_types.filter(func(t): return t != "relationship_header")

	if not use_chromadb:
		# In-memory: find by slot_type metadata
		for mem in memory_cache:
			var slot_type = mem.get("metadata", {}).get("slot_type", "")
			if slot_type in stored_types:
				results.append(mem)
		return results

	# ChromaDB: query for each protected slot type (except relationship_header)
	for slot_type in stored_types:
		var query_result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": slot_type,  # Minimal query, metadata filter is key
			"limit": 3,
			"metadata_filter": {"slot_type": slot_type}
		})

		var memories = []
		if query_result is Array:
			memories = query_result
		elif query_result.has("memories"):
			memories = query_result.memories

		results.append_array(memories)

	return results

## Get recent memories by event types (high-signal events from last N days)
func _get_recent_by_types(event_types: Array, days: int, limit: int) -> Array:
	var cutoff = Time.get_unix_time_from_system() - (days * 86400)
	var results: Array = []

	if not use_chromadb:
		# In-memory: filter by event type and timestamp
		for mem in memory_cache:
			var meta = mem.get("metadata", mem)
			var event_type = meta.get("event_type", "")
			var timestamp = meta.get("timestamp", 0)
			if event_type in event_types and timestamp >= cutoff:
				results.append(mem)
		# Sort by timestamp descending
		results.sort_custom(func(a, b):
			var ts_a = a.get("metadata", a).get("timestamp", 0)
			var ts_b = b.get("metadata", b).get("timestamp", 0)
			return ts_a > ts_b
		)
		return results.slice(0, mini(limit, results.size()))

	# ChromaDB: query for each event type
	for event_type in event_types:
		var query_result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": event_type,
			"limit": limit,
			"metadata_filter": {"event_type": event_type}
		})

		var memories = []
		if query_result is Array:
			memories = query_result
		elif query_result.has("memories"):
			memories = query_result.memories

		for mem in memories:
			var meta = mem.get("metadata", {})
			if meta.get("timestamp", 0) >= cutoff:
				results.append(mem)

	# Sort by timestamp descending and limit
	results.sort_custom(func(a, b):
		var ts_a = a.get("metadata", a).get("timestamp", 0)
		var ts_b = b.get("metadata", b).get("timestamp", 0)
		return ts_a > ts_b
	)
	return results.slice(0, mini(limit, results.size()))

## Get top-K semantically similar memories
func _get_semantic_top_k(context: String, limit: int) -> Array:
	if not use_chromadb:
		# In-memory: basic keyword matching
		var scored = []
		var context_lower = context.to_lower()
		for mem in memory_cache:
			var mem_lower = mem.get("document", "").to_lower()
			var score = 0.0
			for word in context_lower.split(" "):
				if word.length() > 3 and word in mem_lower:
					score += 1.0
			scored.append({"memory": mem, "score": score})
		scored.sort_custom(func(a, b): return a.score > b.score)
		var results = []
		for i in range(mini(limit, scored.size())):
			results.append(scored[i].memory)
		return results

	# ChromaDB: semantic search
	var query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": context,
		"limit": limit,
		"min_importance": 3  # Don't fetch trivial memories
	})

	if query_result is Array:
		return query_result
	elif query_result.has("memories"):
		return query_result.memories
	return []

## Fill token budget with highest-scoring memories
## Phase 4: Uses relevance-based form selection (short vs full)
## Returns array of memories that fit within budget, with _rendered_text set
func _fill_token_budget(memories: Array, budget: int) -> Array:
	var result: Array = []
	var remaining = budget
	var threshold = _get_high_relevance_threshold()
	var use_dual = _use_dual_representation()

	for mem in memories:
		# Phase 4: Relevance-based form selection
		var text: String
		if use_dual:
			# Calculate similarity from distance (ChromaDB returns distance, lower = more similar)
			var distance = mem.get("distance", 0.5)
			var similarity = 1.0 - clamp(distance, 0.0, 1.0)

			# Use full form only for highly relevant memories (primary topic)
			# This prevents non-deterministic tone shifts based on budget fluctuations
			if similarity >= threshold:
				text = mem.get("document_full", mem.get("document", mem.get("text", "")))
				mem["_used_form"] = "full"
			else:
				text = mem.get("document_short", mem.get("document", mem.get("text", "")))
				mem["_used_form"] = "short"
		else:
			# Legacy: use document field directly
			text = mem.get("document", mem.get("text", ""))

		# Store rendered text for later use
		mem["_rendered_text"] = text

		# Conservative token estimate: 3 chars/token for structured content
		var tokens = ceili(text.length() / 3.0)

		if tokens <= remaining:
			result.append(mem)
			remaining -= tokens
		elif mem.get("_protected", false):
			# Protected memories always included, even if over budget
			result.append(mem)
			remaining -= tokens
			print("[RAGMemory] Warning: Protected memory exceeded budget, continuing anyway")

	# Log form selection summary in debug
	if use_dual:
		var full_count = 0
		var short_count = 0
		for mem in result:
			if mem.get("_used_form") == "full":
				full_count += 1
			elif mem.get("_used_form") == "short":
				short_count += 1
		if full_count > 0 or short_count > 0:
			print("[RAGMemory] Form selection: %d full, %d short (threshold=%.2f)" % [full_count, short_count, threshold])

	return result

## ==============================================================================
## PROTECTED RELATIONSHIP HEADERS (Phase 3 Implementation)
## ==============================================================================

## Reference to the NPC's relationship state (set by base_npc.gd)
var _relationship_state: Dictionary = {}

## Set relationship state reference (called by base_npc.gd)
func set_relationship_state(state: Dictionary) -> void:
	_relationship_state = state

## Generate compact relationship header for protected injection
## Returns a memory-like dictionary with the header as document
func generate_relationship_header() -> Dictionary:
	var days_known = 0

	# Calculate days since first meeting
	var first_meeting = await _get_memory_by_event_type("first_meeting")
	if first_meeting:
		var first_ts = first_meeting.get("metadata", {}).get("timestamp", 0)
		if first_ts > 0:
			days_known = int((Time.get_unix_time_from_system() - first_ts) / 86400.0)

	# Get current relationship values (from cached state or defaults)
	var trust = _relationship_state.get("trust", 50)
	var affection = _relationship_state.get("affection", 0)
	var fear = _relationship_state.get("fear", 0)
	var respect = _relationship_state.get("respect", 50)
	var familiarity = _relationship_state.get("familiarity", 0)

	var status_label = _get_status_label(trust, affection, fear, familiarity)

	var header_text = "[Met=%s, Days=%d, Trust=%d, Affection=%d, Fear=%d, Respect=%d, Status=%s]" % [
		"yes" if days_known > 0 or familiarity > 0 else "no",
		days_known,
		trust,
		affection,
		fear,
		respect,
		status_label
	]

	return {
		"id": "%s_relationship_header" % npc_id,
		"document": header_text,
		"metadata": {
			"slot_type": "relationship_header",
			"timestamp": Time.get_unix_time_from_system(),
			"npc_id": npc_id,
			"memory_tier": MemoryTier.PINNED
		}
	}

## Get a human-readable status label based on relationship values
func _get_status_label(trust: int, affection: int, fear: int, familiarity: int) -> String:
	# Check for extreme states first
	if fear > 70:
		return "terrified"
	if trust < 15:
		return "hostile" if affection < 0 else "distrustful"

	# Calculate overall disposition
	if trust < 30:
		return "wary"
	elif trust < 45:
		return "cautious"
	elif trust < 55:
		if affection > 30:
			return "friendly_acquaintance"
		return "neutral"
	elif trust < 70:
		if affection > 50:
			return "close_friend"
		elif affection > 20:
			return "friend"
		return "trusted"
	else:
		# High trust (70+)
		if affection > 70:
			return "beloved"
		elif affection > 40:
			return "trusted_ally"
		return "respected"

## Get a memory by event type (for first_meeting lookup)
func _get_memory_by_event_type(event_type: String) -> Variant:
	if not use_chromadb:
		# In-memory search
		for mem in memory_cache:
			if mem.get("metadata", {}).get("event_type") == event_type:
				return mem
		return null

	# ChromaDB query
	var query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": event_type,
		"limit": 1,
		"metadata_filter": {"event_type": event_type}
	})

	var memories = []
	if query_result is Array:
		memories = query_result
	elif query_result.has("memories"):
		memories = query_result.memories

	if memories.size() > 0:
		return memories[0]
	return null

## Get a memory by slot type (for player_name, npc_death_status)
func _get_memory_by_slot(slot_type: String) -> Variant:
	if not use_chromadb:
		# In-memory search
		for mem in memory_cache:
			if mem.get("metadata", {}).get("slot_type") == slot_type:
				return mem
		return null

	# ChromaDB query
	var query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": slot_type,
		"limit": 1,
		"metadata_filter": {"slot_type": slot_type}
	})

	var memories = []
	if query_result is Array:
		memories = query_result
	elif query_result.has("memories"):
		memories = query_result.memories

	if memories.size() > 0:
		return memories[0]
	return null

## ==============================================================================
## DUAL REPRESENTATION STORAGE (Phase 4 Implementation)
## ==============================================================================

## Check if dual representation is enabled
func _use_dual_representation() -> bool:
	if memory_config:
		return memory_config.use_dual_representation
	return true  # Default to new behavior

## Get high relevance threshold for full form selection
func _get_high_relevance_threshold() -> float:
	if memory_config:
		return memory_config.high_relevance_threshold
	return 0.85

## Get target length for short summaries
func _get_short_summary_target() -> int:
	if memory_config:
		return memory_config.short_summary_target_length
	return 80

## Get max length for short summaries
func _get_short_summary_max() -> int:
	if memory_config:
		return memory_config.short_summary_max_length
	return 100

## Generate short summary from full memory text
## Target: 50-80 characters, preserving key information
## Uses intelligent truncation that respects sentence boundaries
func _summarize_to_short(full_text: String, event_type: String = "") -> String:
	var target = _get_short_summary_target()
	var max_len = _get_short_summary_max()

	# If already short enough, return as-is
	if full_text.length() <= target:
		return full_text

	# Try to find first complete sentence
	var first_period = full_text.find(".")
	if first_period > 0 and first_period < max_len:
		var first_sentence = full_text.substr(0, first_period + 1)
		# If first sentence is reasonably short, use it
		if first_sentence.length() <= max_len:
			return first_sentence

	# Look for other sentence endings
	var endings = [".", "!", "?"]
	var best_end = -1
	for ending in endings:
		var pos = full_text.find(ending)
		if pos > 0 and pos < max_len:
			if best_end == -1 or pos < best_end:
				best_end = pos

	if best_end > 0 and best_end < max_len:
		return full_text.substr(0, best_end + 1)

	# No good sentence break found - truncate at word boundary
	var truncated = full_text.substr(0, target - 3)  # Leave room for "..."
	var last_space = truncated.rfind(" ")

	# Ensure we keep at least half the target length
	if last_space > target / 2:
		return truncated.substr(0, last_space) + "..."

	# Last resort: hard truncate
	return truncated + "..."

## ==============================================================================
## SCHEMA CONSTRAINTS + DELTA CLAMPING (Phase 5 Implementation)
## ==============================================================================

## Validate interaction type from Claude's response
## Delegates to MemoryConfig for validation logic
func validate_interaction_type(claude_type: String) -> String:
	if memory_config:
		return memory_config.validate_interaction_type(claude_type)
	# Fallback if no config loaded
	var valid_types = [
		"casual_conversation", "quest_related", "gift_given",
		"emotional_support", "romantic_gesture", "threat_made",
		"secret_shared", "betrayal", "life_saved", "romance_confession"
	]
	if claude_type in valid_types:
		return claude_type
	push_warning("[RAGMemory] Invalid interaction_type: '%s', defaulting to casual_conversation" % claude_type)
	return "casual_conversation"

## Clamp relationship deltas from Claude's analysis
## Delegates to MemoryConfig for clamping logic
func clamp_relationship_deltas(analysis: Dictionary) -> Dictionary:
	if memory_config:
		return memory_config.clamp_relationship_deltas(analysis)
	# Fallback if no config loaded
	return {
		"trust_change": clampi(analysis.get("trust_change", 0), -15, 15),
		"affection_change": clampi(analysis.get("affection_change", 0), -10, 10),
		"fear_change": clampi(analysis.get("fear_change", 0), -10, 10),
		"respect_change": clampi(analysis.get("respect_change", 0), -10, 10),
		"familiarity_change": clampi(analysis.get("familiarity_change", 0), -5, 5)
	}

## Get the interaction type constraint prompt for inclusion in system prompts
func get_interaction_type_constraint_prompt() -> String:
	if memory_config:
		return memory_config.get_interaction_type_constraint_prompt()
	return """When analyzing the interaction, classify it as ONE of these exact types:
- "casual_conversation" - Normal friendly chat
- "quest_related" - Discussing quests or objectives
- "gift_given" - Player gave something to NPC
- "emotional_support" - Player provided comfort or help
- "romantic_gesture" - Flirting, compliments, romantic interest
- "threat_made" - Hostility or intimidation
- "secret_shared" - Revealing private information
- "betrayal" - Breaking trust or promise
- "life_saved" - Rescue from danger
- "romance_confession" - Declaration of romantic feelings

Do NOT invent new types. Use "casual_conversation" if unsure."""

## ==============================================================================
## CONFLICT RESOLUTION (Phase 6 Implementation)
## ==============================================================================

## Store a memory with conflict detection and resolution
## Handles both slot-based updates (complete replacement) and supersession chains
func store_with_conflict_check(memory_text: String, importance: int, memory_data: Dictionary) -> bool:
	var event_type = memory_data.get("event_type", "")
	var slot_type = memory_data.get("slot_type", "")

	# Handle slot-based updates (complete replacement - only current value matters)
	if _is_slot_type(slot_type):
		print("[RAGMemory] Phase 6: Slot update detected for '%s', replacing old value" % slot_type)
		return await _store_slot_update(slot_type, memory_text, importance, memory_data)

	# Handle supersession chains (history preserved with score penalty)
	var superseded_type = _get_superseded_event_type(event_type)
	if superseded_type != "":
		print("[RAGMemory] Phase 6: Supersession detected - '%s' supersedes '%s'" % [event_type, superseded_type])
		await _mark_superseded(superseded_type)

	# Store normally
	return await store(MemoryData.new(memory_text, importance, memory_data))

## Check if a slot_type requires complete replacement
func _is_slot_type(slot_type: String) -> bool:
	if memory_config:
		return memory_config.is_slot_type(slot_type)
	# Fallback list
	var fallback_slots = ["player_name", "player_allegiance", "npc_belief_about_player", "current_quest_for_npc"]
	return slot_type in fallback_slots

## Get the event type that would be superseded by this event type
func _get_superseded_event_type(event_type: String) -> String:
	if memory_config:
		return memory_config.get_superseded_event_type(event_type)
	# Fallback supersession pairs
	var fallback_pairs = {
		"promise_made": "promise_broken",
		"trust_gained": "trust_lost",
		"alliance_formed": "alliance_broken",
		"secret_kept": "secret_revealed"
	}
	for original in fallback_pairs:
		if fallback_pairs[original] == event_type:
			return original
	return ""

## Store a slot update - replaces any existing memory with the same slot_type
func _store_slot_update(slot_type: String, memory_text: String, importance: int, memory_data: Dictionary) -> bool:
	# Find and delete existing memory with this slot_type
	var existing = await _get_memory_by_slot(slot_type)
	if existing:
		var existing_id = existing.get("id", "")
		if existing_id != "":
			print("[RAGMemory] Phase 6: Deleting old slot value: %s" % existing_id)
			await _delete_memory(existing_id)

	# Store the new value
	memory_data["slot_type"] = slot_type
	return await store(MemoryData.new(memory_text, importance, memory_data))

## Mark all memories of a given event_type as superseded
## Superseded memories get a 0.1x score multiplier but aren't deleted
func _mark_superseded(event_type: String) -> void:
	var old_memories = await _get_memories_by_event_type(event_type)

	for mem in old_memories:
		var mem_id = mem.get("id", "")
		if mem_id == "":
			continue

		# Check if already superseded
		var meta = mem.get("metadata", {})
		if meta.get("superseded_by", "") != "":
			continue  # Already superseded

		print("[RAGMemory] Phase 6: Marking memory as superseded: %s" % mem_id)

		# Update metadata to mark as superseded
		meta["superseded_by"] = "pending"  # Will be updated with new memory ID if needed
		meta["superseded_at"] = Time.get_unix_time_from_system()

		await _update_memory_metadata(mem_id, meta)

## Get all memories with a specific event_type
func _get_memories_by_event_type(event_type: String) -> Array:
	if not use_chromadb:
		# In-memory search
		var results = []
		for mem in memory_cache:
			if mem.get("metadata", {}).get("event_type") == event_type:
				results.append(mem)
		return results

	# ChromaDB query
	var query_result = await chroma_client.query_memories({
		"collection": collection_name,
		"query": event_type,
		"limit": 20,
		"metadata_filter": {"event_type": event_type}
	})

	if query_result is Array:
		return query_result
	elif query_result.has("memories"):
		return query_result.memories
	return []

## Delete a memory by ID
func _delete_memory(memory_id: String) -> bool:
	if not use_chromadb:
		# In-memory: remove from cache
		for i in range(memory_cache.size() - 1, -1, -1):
			if memory_cache[i].get("id", "") == memory_id:
				memory_cache.remove_at(i)
				print("[RAGMemory] In-memory delete: %s" % memory_id)
				return true
		return false

	# ChromaDB delete
	var result = await chroma_client.delete_memory({
		"collection": collection_name,
		"id": memory_id
	})

	if result.has("error"):
		push_error("[RAGMemory] Failed to delete memory: %s" % result.error)
		return false

	print("[RAGMemory] ChromaDB delete: %s" % memory_id)
	return true

## Update metadata for an existing memory
func _update_memory_metadata(memory_id: String, new_metadata: Dictionary) -> bool:
	if not use_chromadb:
		# In-memory: find and update
		for mem in memory_cache:
			if mem.get("id", "") == memory_id:
				mem["metadata"] = new_metadata
				return true
		return false

	# ChromaDB update
	var result = await chroma_client.update_memory({
		"collection": collection_name,
		"id": memory_id,
		"metadata": new_metadata
	})

	if result.has("error"):
		push_error("[RAGMemory] Failed to update memory metadata: %s" % result.error)
		return false

	return true

## Retrieve memories with tiered priority (PHASE 2 main retrieval method)
## Always includes pinned memories, then important, then semantic results
## Respects context budget to prevent overflow
## Uses MemoryConfig for all limits
func retrieve_tiered(context: String, options: Dictionary = {}) -> Dictionary:
	var max_chars = _get_max_chars()
	var result = {
		"pinned": [],     # Always included
		"important": [],  # High priority
		"relevant": [],   # Semantic matches
		"total_chars": 0,
		"budget_remaining": max_chars
	}

	# Step 1: Get ALL pinned memories (these are always included)
	# Pass context for relevance scoring when score-based selection is enabled
	var pinned = await _get_memories_by_tier(MemoryTier.PINNED, context)
	result.pinned = _trim_to_budget(pinned, _get_max_pinned(), result, max_chars)

	# Step 2: Get important memories
	var important = await _get_memories_by_tier(MemoryTier.IMPORTANT, context)
	result.important = _trim_to_budget(important, _get_max_important(), result, max_chars)

	# Step 3: Get semantically relevant regular memories (excluding already included)
	var included_ids = []
	for mem in result.pinned:
		included_ids.append(mem.get("id", ""))
	for mem in result.important:
		included_ids.append(mem.get("id", ""))

	var relevant = await _get_semantic_memories(context, _get_max_regular(), included_ids)
	result.relevant = _trim_to_budget(relevant, _get_max_regular(), result, max_chars)

	var total_count = result.pinned.size() + result.important.size() + result.relevant.size()
	print("[RAGMemory] Tiered retrieval: %d pinned, %d important, %d relevant (%d chars)" % [
		result.pinned.size(), result.important.size(), result.relevant.size(), result.total_chars
	])

	# Detailed memory content logging for debugging (with scores if enabled)
	var show_scores = _use_score_based_selection()
	if result.pinned.size() > 0:
		print("[RAGMemory] === PINNED MEMORIES ===")
		for mem in result.pinned:
			var text = mem.get("document", mem.get("text", "[no text]"))
			var score_str = " (score: %.2f)" % mem.get("_score", 0) if show_scores else ""
			print("[RAGMemory]   • %s%s" % [text.substr(0, 100), score_str])

	if result.important.size() > 0:
		print("[RAGMemory] === IMPORTANT MEMORIES ===")
		for mem in result.important:
			var text = mem.get("document", mem.get("text", "[no text]"))
			var score_str = " (score: %.2f)" % mem.get("_score", 0) if show_scores else ""
			print("[RAGMemory]   • %s%s" % [text.substr(0, 100), score_str])

	if result.relevant.size() > 0:
		print("[RAGMemory] === RELEVANT MEMORIES ===")
		for mem in result.relevant:
			var text = mem.get("document", mem.get("text", "[no text]"))
			var score_str = " (score: %.2f)" % mem.get("_score", 0) if show_scores else ""
			print("[RAGMemory]   • %s%s" % [text.substr(0, 100), score_str])

	memories_recalled.emit(total_count)
	return result

## Get memories by tier (with optional score-based selection)
## query_context: Optional context for relevance scoring
func _get_memories_by_tier(tier: int, query_context: String = "") -> Array:
	var memories: Array = []

	if not use_chromadb:
		# In-memory fallback
		for mem in memory_cache:
			if mem.metadata.get("memory_tier", MemoryTier.REGULAR) == tier:
				memories.append(mem)
	else:
		# Query ChromaDB with tier filter
		var query_result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": query_context if query_context else "relationship milestone important",
			"limit": 30,  # Fetch more for score-based filtering
			"metadata_filter": {"memory_tier": tier}
		})

		if query_result is Array:
			memories = query_result
		elif query_result.has("memories"):
			memories = query_result.memories

	# Apply score-based selection if enabled
	if _use_score_based_selection() and memories.size() > 0:
		# Calculate scores for all memories
		for mem in memories:
			mem["_score"] = _calculate_memory_score(mem, query_context)

		# Sort by score descending
		memories.sort_custom(func(a, b):
			return a.get("_score", 0) > b.get("_score", 0)
		)
	else:
		# Legacy: sort by importance descending
		memories.sort_custom(func(a, b):
			var meta_a = a.get("metadata", a)
			var meta_b = b.get("metadata", b)
			return meta_a.get("importance", 5) > meta_b.get("importance", 5)
		)

	return memories

## Get semantically relevant memories, excluding specific IDs
## Uses score-based selection when enabled
func _get_semantic_memories(context: String, limit: int, exclude_ids: Array) -> Array:
	var min_importance = 4
	var memories: Array = []

	if not use_chromadb:
		# In-memory: filter by tier and importance first
		for mem in memory_cache:
			if mem.id in exclude_ids:
				continue
			if mem.metadata.get("importance", 5) < min_importance:
				continue
			if mem.metadata.get("memory_tier", MemoryTier.REGULAR) != MemoryTier.REGULAR:
				continue  # Skip pinned/important (already included)
			memories.append(mem)
	else:
		# ChromaDB semantic search - fetch extra for filtering
		var query_result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": context,
			"limit": (limit + exclude_ids.size()) * 2,  # Fetch more for score-based filtering
			"min_importance": min_importance
		})

		var raw_memories = query_result if query_result is Array else query_result.get("memories", [])

		# Filter out excluded IDs and non-regular tier
		for mem in raw_memories:
			var mem_id = mem.get("id", "")
			if mem_id in exclude_ids:
				continue
			var meta = mem.get("metadata", {})
			if meta.get("memory_tier", MemoryTier.REGULAR) != MemoryTier.REGULAR:
				continue
			memories.append(mem)

	# Apply score-based selection if enabled
	if _use_score_based_selection() and memories.size() > 0:
		# Calculate scores for all memories
		for mem in memories:
			mem["_score"] = _calculate_memory_score(mem, context)

		# Sort by score descending
		memories.sort_custom(func(a, b):
			return a.get("_score", 0) > b.get("_score", 0)
		)
	else:
		# Legacy: simple keyword scoring
		var context_lower = context.to_lower()
		for mem in memories:
			var mem_lower = mem.get("document", "").to_lower()
			var score = 0.0
			for word in context_lower.split(" "):
				if word.length() > 3 and word in mem_lower:
					score += 1.0
			var meta = mem.get("metadata", mem)
			score += meta.get("importance", 5) * 0.3
			var recency = Time.get_unix_time_from_system() - meta.get("timestamp", 0)
			score += max(0, (3600 - recency) / 3600.0)
			mem["_score"] = score

		memories.sort_custom(func(a, b): return a.get("_score", 0) > b.get("_score", 0))

	# Return top N
	return memories.slice(0, mini(limit, memories.size()))

## Trim memories to fit within character budget
## max_chars: Character budget from config (data-driven)
func _trim_to_budget(memories: Array, max_count: int, result: Dictionary, max_chars: int) -> Array:
	var trimmed = []
	var count = 0

	for mem in memories:
		if count >= max_count:
			break

		var text = mem.get("document", mem.get("text", ""))
		var text_length = text.length()

		# Check if adding this memory would exceed budget
		if result.total_chars + text_length > max_chars:
			# Try to fit a truncated version
			var remaining = max_chars - result.total_chars
			if remaining > 100:  # Only truncate if we have meaningful space
				mem["document"] = text.substr(0, remaining - 20) + "... [truncated]"
				result.total_chars += remaining
				trimmed.append(mem)
			break

		result.total_chars += text_length
		result.budget_remaining = max_chars - result.total_chars
		trimmed.append(mem)
		count += 1

	return trimmed

## Format tiered memories for context injection
## Returns formatted strings ready for Claude context
func format_tiered_memories(tiered_result: Dictionary) -> Dictionary:
	var formatted = {
		"pinned": [],
		"important": [],
		"relevant": []
	}

	for mem in tiered_result.pinned:
		formatted.pinned.append(_format_single_memory(mem, "MILESTONE"))

	for mem in tiered_result.important:
		formatted.important.append(_format_single_memory(mem, "IMPORTANT"))

	for mem in tiered_result.relevant:
		formatted.relevant.append(_format_single_memory(mem, ""))

	return formatted

## Format a single memory with metadata
func _format_single_memory(mem: Dictionary, prefix: String) -> String:
	var text = mem.get("document", mem.get("text", ""))
	var meta = mem.get("metadata", mem)
	var event_type = meta.get("event_type", "memory")
	var importance = meta.get("importance", 5)
	var emotion = meta.get("emotion", "")
	var milestone = meta.get("milestone_type", "")

	var formatted = ""
	if prefix != "":
		formatted = "[%s - %s" % [prefix, event_type]
	else:
		formatted = "[%s" % event_type

	if milestone != "":
		formatted += ", milestone: %s" % milestone

	formatted += ", importance: %d" % importance

	if emotion != "":
		formatted += ", felt: %s" % emotion

	formatted += "] %s" % text
	return formatted

## Store a milestone memory (convenience method)
## Uses MemoryConfig for valid milestone types
func store_milestone(milestone_type: String, description: String, emotion: String = "significant") -> bool:
	# Validate against config's milestone types
	if memory_config and milestone_type not in memory_config.milestone_event_types:
		push_warning("Unknown milestone type: %s (not in config)" % milestone_type)

	return await store({
		"text": description,
		"event_type": milestone_type,
		"importance": 10,
		"emotion": emotion,
		"memory_tier": MemoryTier.PINNED,
		"is_milestone": true,
		"milestone_type": milestone_type
	})

## Pin an existing memory (upgrade to pinned tier)
func pin_memory(memory_id: String) -> bool:
	# For ChromaDB, we'd need to update the metadata
	# For now, store a reference
	if not use_chromadb:
		for mem in memory_cache:
			if mem.id == memory_id:
				mem.metadata["memory_tier"] = MemoryTier.PINNED
				print("[RAGMemory] Pinned memory: %s" % memory_id)
				return true
		return false

	# ChromaDB update would go here
	push_warning("ChromaDB memory pinning not yet implemented")
	return false

## Get count of pinned memories
func get_pinned_count() -> int:
	var count = 0
	if not use_chromadb:
		for mem in memory_cache:
			if mem.metadata.get("memory_tier", MemoryTier.REGULAR) == MemoryTier.PINNED:
				count += 1
		return count

	# ChromaDB count would go here
	return count

## Consolidate old conversation memories into summaries
## This prevents context bloat from many small conversation turns
## Uses MemoryConfig for consolidation settings
func consolidate_old_conversations(days_old: int = -1) -> bool:
	# Use config value if not explicitly provided
	var actual_days = days_old
	if actual_days < 0 and memory_config:
		actual_days = memory_config.consolidation_age_days
	elif actual_days < 0:
		actual_days = 7  # Fallback default

	var min_count = 3
	if memory_config:
		min_count = memory_config.consolidation_min_count

	var cutoff_time = Time.get_unix_time_from_system() - (actual_days * 24 * 60 * 60)
	var old_conversations = []
	var to_remove = []

	if not use_chromadb:
		# Find old conversation memories
		for mem in memory_cache:
			var meta = mem.metadata
			if meta.get("event_type") == "conversation" and meta.get("timestamp", 0) < cutoff_time:
				if meta.get("memory_tier", MemoryTier.REGULAR) == MemoryTier.REGULAR:
					old_conversations.append(mem)
					to_remove.append(mem)

		if old_conversations.size() < min_count:
			return false  # Not enough to consolidate

		# Create summary
		var summary_text = "Over the past week, we had %d conversations. " % old_conversations.size()
		var topics = []
		for mem in old_conversations:
			var mem_topics = mem.metadata.get("topics", "")
			if mem_topics != "":
				for t in mem_topics.split(","):
					if t not in topics:
						topics.append(t)

		if topics.size() > 0:
			summary_text += "Topics discussed: %s." % ", ".join(topics)

		# Store consolidated memory
		await store({
			"text": summary_text,
			"event_type": "conversation_summary",
			"importance": 6,
			"memory_tier": MemoryTier.IMPORTANT,
			"conversations_count": old_conversations.size()
		})

		# Remove old memories
		for mem in to_remove:
			memory_cache.erase(mem)

		print("[RAGMemory] Consolidated %d old conversations into summary" % old_conversations.size())
		return true

	# ChromaDB consolidation would go here
	push_warning("ChromaDB consolidation not yet implemented")
	return false

## ==============================================================================
## DEBUG: MEMORY INSPECTION
## ==============================================================================

## Dump all memories for debugging - returns formatted string
func dump_all_memories() -> String:
	var output = "\n=== MEMORY DUMP FOR %s ===\n" % npc_id
	output += "Collection: %s\n" % collection_name
	output += "Using ChromaDB: %s\n\n" % use_chromadb

	var all_memories = []

	if not use_chromadb:
		all_memories = memory_cache.duplicate()
	else:
		# Query all memories from ChromaDB
		var result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": "memory conversation event player",  # Broad query
			"limit": 100  # Get up to 100 memories
		})
		if result is Array:
			all_memories = result
		elif result.has("memories"):
			all_memories = result.memories

	# Sort by timestamp (newest first)
	all_memories.sort_custom(func(a, b):
		var ts_a = a.get("metadata", a).get("timestamp", 0)
		var ts_b = b.get("metadata", b).get("timestamp", 0)
		return ts_a > ts_b
	)

	output += "Total memories: %d\n\n" % all_memories.size()

	# Group by tier
	var pinned = []
	var important = []
	var regular = []

	for mem in all_memories:
		var meta = mem.get("metadata", mem)
		var tier = meta.get("memory_tier", MemoryTier.REGULAR)
		match tier:
			MemoryTier.PINNED:
				pinned.append(mem)
			MemoryTier.IMPORTANT:
				important.append(mem)
			_:
				regular.append(mem)

	output += "--- PINNED MEMORIES (%d) ---\n" % pinned.size()
	for mem in pinned:
		output += _format_memory_for_dump(mem) + "\n"

	output += "\n--- IMPORTANT MEMORIES (%d) ---\n" % important.size()
	for mem in important:
		output += _format_memory_for_dump(mem) + "\n"

	output += "\n--- REGULAR MEMORIES (%d) ---\n" % regular.size()
	for mem in regular:
		output += _format_memory_for_dump(mem) + "\n"

	output += "\n=== END DUMP ===\n"
	return output

## Format a single memory for dump output
func _format_memory_for_dump(mem: Dictionary) -> String:
	var meta = mem.get("metadata", mem)
	var text = mem.get("document", mem.get("text", "[no text]"))
	var event_type = meta.get("event_type", "unknown")
	var importance = meta.get("importance", 0)
	var timestamp = meta.get("timestamp", 0)
	var emotion = meta.get("emotion", "")

	var time_str = ""
	if timestamp > 0:
		var dt = Time.get_datetime_dict_from_unix_time(int(timestamp))
		time_str = "%02d:%02d" % [dt.hour, dt.minute]

	var line = "[%s] (%s, imp:%d" % [time_str, event_type, importance]
	if emotion != "":
		line += ", %s" % emotion
	line += ") %s" % text.substr(0, 100)
	if text.length() > 100:
		line += "..."
	return line

## Get memory statistics
func get_memory_stats() -> Dictionary:
	var stats = {
		"total": 0,
		"pinned": 0,
		"important": 0,
		"regular": 0,
		"by_type": {}
	}

	var all_memories = memory_cache if not use_chromadb else []
	if use_chromadb:
		var result = await chroma_client.query_memories({
			"collection": collection_name,
			"query": "memory",
			"limit": 100
		})
		if result is Array:
			all_memories = result
		elif result.has("memories"):
			all_memories = result.memories

	stats.total = all_memories.size()

	for mem in all_memories:
		var meta = mem.get("metadata", mem)
		var tier = meta.get("memory_tier", MemoryTier.REGULAR)
		var event_type = meta.get("event_type", "unknown")

		match tier:
			MemoryTier.PINNED:
				stats.pinned += 1
			MemoryTier.IMPORTANT:
				stats.important += 1
			_:
				stats.regular += 1

		if not stats.by_type.has(event_type):
			stats.by_type[event_type] = 0
		stats.by_type[event_type] += 1

	return stats
