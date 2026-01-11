extends Node
# ContextBuilder - Assembles context for Claude API from NPC state
# Formats system prompt, RAG memories, world state, and conversation history into Claude messages
# Now supports structured NPCPersonality resources for consistent character behavior

## Build complete context for an NPC's response
## params: {
##   system_prompt: String - NPC's personality/character definition (legacy)
##   personality: NPCPersonality - Structured personality resource (preferred)
##   npc_id: String - NPC's ID for world knowledge lookup
##   tiered_memories: Dictionary - {pinned: [], important: [], relevant: []} from RAG
##   relationship_status: float - DEPRECATED legacy score
##   relationship_dimensions: Dictionary - Multi-dimensional relationship (trust, respect, affection, fear, familiarity)
##   world_state: Dictionary - Relevant world flags and events
##   conversation_history: Array - Recent dialogue turns
##   player_input: String - Current player message
## }
## Returns: Dictionary ready for ClaudeClient.send_message()
func build_context(params: Dictionary) -> Dictionary:
	var system_prompt = params.get("system_prompt", "")
	var personality = params.get("personality", null)  # Structured personality
	var npc_id = params.get("npc_id", "")
	var tiered_memories = params.get("tiered_memories", {"pinned": [], "important": [], "relevant": []})
	var relationship = params.get("relationship_status", 0.0)  # Legacy
	var dimensions = params.get("relationship_dimensions", {})  # Multi-dimensional
	var world_state = params.get("world_state", {})
	var conversation_history = params.get("conversation_history", [])
	var player_input = params.get("player_input", "")

	# Build enhanced system prompt with current context
	var enhanced_system: String
	if personality != null:
		# Use new structured personality system with tiered memories
		enhanced_system = _build_system_prompt_from_personality(
			personality,
			tiered_memories,
			dimensions,
			world_state
		)
	else:
		# Fallback to legacy system prompt
		enhanced_system = _build_system_prompt(
			system_prompt,
			npc_id,
			tiered_memories,
			relationship,
			dimensions,
			world_state
		)

	# Build message history for Claude
	var messages = _build_message_history(conversation_history, player_input)

	return {
		"system_prompt": enhanced_system,
		"messages": messages
	}

## Build system prompt from structured NPCPersonality resource
## PRIORITY ORDER: Critical sections at top survive truncation
## Response Format MUST be first - without it, Claude won't return valid JSON
func _build_system_prompt_from_personality(personality: Resource, tiered_memories: Dictionary, dimensions: Dictionary, world_state: Dictionary) -> String:
	var prompt = ""

	# =========================================================================
	# SECTION 1: RESPONSE FORMAT (CRITICAL - Must be first, never truncated)
	# Without this, Claude returns plain text instead of JSON
	# =========================================================================
	prompt += _build_response_format_section()

	# =========================================================================
	# SECTION 2: CORE IDENTITY (Essential for character consistency)
	# =========================================================================
	prompt += personality.get_core_identity_block()

	# =========================================================================
	# SECTION 3: CANONICAL WORLD FACTS (Prevents hallucination)
	# =========================================================================
	if WorldKnowledge and not personality.npc_id.is_empty():
		prompt += WorldKnowledge.get_world_facts_for_npc(personality.npc_id)

	# =========================================================================
	# SECTION 4: PERSONALITY TRAITS & SPEECH PATTERNS
	# =========================================================================
	prompt += personality.get_personality_summary()
	prompt += personality.get_speech_pattern_block()

	# =========================================================================
	# SECTION 5: RELATIONSHIP STATE
	# =========================================================================
	if dimensions.size() > 0:
		prompt += _build_relationship_section(dimensions, personality)

	# =========================================================================
	# SECTION 6: UNLOCKED SECRETS (Based on relationship thresholds)
	# =========================================================================
	var trust = dimensions.get("trust", 0)
	var affection = dimensions.get("affection", 0)
	var unlocked_secrets = personality.get_unlocked_secrets(trust, affection)
	if unlocked_secrets.size() > 0:
		prompt += "## SECRETS YOU MAY REVEAL\n"
		prompt += "Based on your trust in the player, you may share these if appropriate:\n"
		for secret in unlocked_secrets:
			prompt += "- %s\n" % secret
		prompt += "\n"

	# =========================================================================
	# SECTION 7: MEMORIES (Tiered: Pinned → Important → Relevant)
	# =========================================================================
	prompt += _build_tiered_memories_section(tiered_memories)

	# =========================================================================
	# SECTION 8: WORLD STATE
	# =========================================================================
	if world_state.size() > 0:
		prompt += _build_world_state_section(world_state)

	# =========================================================================
	# SECTION 9: BEHAVIORAL GUIDANCE (Lowest priority - OK to truncate)
	# =========================================================================
	prompt += _build_behavioral_section(dimensions, personality)

	return prompt

## Build relationship section with personality-aware interpretation
func _build_relationship_section(dimensions: Dictionary, personality: Resource) -> String:
	var section = "## Your Multi-Dimensional Relationship with the Player\n"

	var trust = dimensions.get("trust", 0)
	var respect = dimensions.get("respect", 0)
	var affection = dimensions.get("affection", 0)
	var fear = dimensions.get("fear", 0)
	var familiarity = dimensions.get("familiarity", 0)
	var memory_count = dimensions.get("memory_count", 0)

	# CRITICAL: First meeting detection
	var is_first_meeting = familiarity < 10 and memory_count == 0
	if is_first_meeting:
		section += "### ⚠️ FIRST MEETING - THIS IS A STRANGER ⚠️\n"
		section += "You have NEVER met this person before. This is your FIRST interaction.\n"
		section += "DO NOT reference:\n"
		section += "- Previous conversations (there were none)\n"
		section += "- \"Good to see you again\" or similar (you haven't met)\n"
		section += "- \"What we discussed\" (you haven't discussed anything)\n"
		section += "- Any shared history (there is none)\n\n"
		section += "Treat them as a complete stranger approaching you for the first time.\n\n"

	section += "Your feelings are complex, not a single number:\n\n"

	section += "**Trust:** %d/100 - %s\n" % [trust, _interpret_dimension("trust", trust)]
	section += "**Respect:** %d/100 - %s\n" % [respect, _interpret_dimension("respect", respect)]
	section += "**Affection:** %d/100 - %s\n" % [affection, _interpret_dimension("affection", affection)]
	section += "**Fear:** %d/100 - %s\n" % [fear, _interpret_dimension("fear", fear)]
	section += "**Familiarity:** %d/100 - %s\n\n" % [familiarity, _interpret_dimension("familiarity", familiarity)]

	# Check romance availability
	if personality != null and personality.is_romance_unlocked(trust, affection, familiarity):
		section += "**ROMANCE AVAILABLE**: Your feelings have grown strong enough that romantic interaction is possible.\n\n"

	return section

## Build memories section from tiered memories (Pinned → Important → Relevant)
## tiered_memories: {pinned: [], important: [], relevant: []} - formatted strings
func _build_tiered_memories_section(tiered_memories: Dictionary) -> String:
	var section = ""
	var pinned = tiered_memories.get("pinned", [])
	var important = tiered_memories.get("important", [])
	var relevant = tiered_memories.get("relevant", [])

	# Pinned memories - relationship-defining moments (ALWAYS shown)
	if pinned.size() > 0:
		section += "## DEFINING MOMENTS (Never Forget)\n"
		section += "These experiences fundamentally shaped your relationship:\n"
		for memory in pinned:
			section += "- %s\n" % memory
		section += "\n"

	# Important memories - significant events
	if important.size() > 0:
		section += "## Significant Memories\n"
		section += "Important events that influence how you see the player:\n"
		for memory in important:
			section += "- %s\n" % memory
		section += "\n"

	# Relevant memories - contextually retrieved
	if relevant.size() > 0:
		section += "## Recent & Relevant Memories\n"
		section += "Things you recall based on the current conversation:\n"
		for memory in relevant:
			section += "- %s\n" % memory
		section += "\n"

	if section == "":
		section = "## Memories\nYou have no significant memories of this person yet.\n\n"

	return section

## Build memories section from categorized memories (LEGACY - kept for backward compatibility)
func _build_memories_section(categorized: Dictionary) -> String:
	var section = ""

	if categorized.actions.size() > 0:
		section += "## How You've Changed Through Your Experiences\n"
		section += "Recent significant events that shaped your view of the player:\n"
		for action in categorized.actions:
			section += "- %s\n" % action
		section += "\nLet these experiences inform your current attitude and responses.\n\n"

	if categorized.conversations.size() > 0:
		section += "## Past Conversations\n"
		section += "Previous discussions with the player:\n"
		for conv in categorized.conversations:
			section += "- %s\n" % conv
		section += "\n"

	if categorized.events.size() > 0:
		section += "## Things You've Witnessed\n"
		for event in categorized.events:
			section += "- %s\n" % event
		section += "\n"

	return section

## Build world state section
func _build_world_state_section(world_state: Dictionary) -> String:
	var section = "## Current World Situation\n"

	# CRITICAL: Scene awareness - who is physically present right now
	# This prevents hallucination about people being "missing" when they're here
	if world_state.has("present_npc_names") and world_state.present_npc_names.size() > 0:
		section += "### WHO IS HERE RIGHT NOW (CANONICAL FACT)\n"
		section += "The following people are physically present in this location with you:\n"
		for npc_name in world_state.present_npc_names:
			section += "- %s is HERE, standing nearby\n" % npc_name
		section += "IMPORTANT: Do NOT claim anyone listed above is missing, kidnapped, or elsewhere. They are HERE.\n\n"

	# Quest-specific context and guidance for this NPC
	if world_state.has("quest_context") and not world_state.quest_context.is_empty():
		section += "### ACTIVE QUEST GUIDANCE\n"
		section += "The player is involved in quests that may affect your interactions:\n"
		section += world_state.quest_context + "\n"
		section += "Use this context to guide your responses - hint at information if trust is high enough, or deflect if the player hasn't earned your confidence yet.\n\n"

	if world_state.has("active_quests") and world_state.active_quests.size() > 0:
		section += "Active quests involving you: %s\n" % ", ".join(world_state.active_quests)

	if world_state.has("world_flags"):
		var npc_id = world_state.get("npc_id", "")
		var story_flags_script = load("res://scripts/world_state/story_flags.gd")

		for flag in world_state.world_flags:
			if world_state.world_flags[flag]:
				# Check if this NPC is directly implicated by this flag
				var implicated_desc = ""
				var general_desc = ""

				if story_flags_script:
					implicated_desc = story_flags_script.get_implicated_npc_description(flag, npc_id)
					general_desc = story_flags_script.get_flag_description(flag)

				if implicated_desc != "":
					# This NPC is the one implicated - give them the strong warning
					section += "\n### ⚠️ CRITICAL STORY SITUATION ⚠️\n"
					section += implicated_desc + "\n\n"
				elif general_desc != "":
					# General awareness of the flag
					section += "- %s\n" % general_desc
				else:
					# Fallback to generic formatting
					section += "- %s\n" % flag.replace("_", " ").capitalize()

	section += "\n"
	return section

## Build behavioral guidance section with personality awareness
func _build_behavioral_section(dimensions: Dictionary, personality: Resource) -> String:
	var section = "## Roleplay Instructions\n"

	# Core instructions
	section += "- Stay in character - these dimensions shape your personality, not scripts\n"
	section += "- Generate ALL dialogue based on your feelings (dimensions + memories)\n"
	section += "- Reference memories naturally - weave them into conversation organically\n"
	section += "- Let your emotional state guide tone: high affection = warmth, high fear = caution\n"
	section += "- Keep responses concise (2-4 sentences unless player asks for details)\n"
	section += "- Speak like a character in a JRPG world\n"
	section += "- NEVER use pre-written dialogue - every response is unique to this relationship\n"

	# Speech pattern enforcement
	if personality != null:
		if personality.forbidden_phrases.size() > 0:
			section += "- NEVER use these words/phrases: %s\n" % ", ".join(personality.forbidden_phrases)
		if personality.signature_phrases.size() > 0:
			section += "- Naturally incorporate your signature phrases when appropriate\n"

	section += "\n"

	# Dynamic behavioral guidance
	section += _generate_behavioral_guidance(dimensions)
	section += "\n"

	return section

## Build response format section
## Phase 5: Uses constrained interaction types to prevent prompt drift
func _build_response_format_section() -> String:
	var section = "## CRITICAL: Response Format\n"
	section += "You MUST respond with valid JSON in this exact format:\n"
	section += '{\n'
	section += '  "response": "Your in-character dialogue here",\n'
	section += '  "analysis": {\n'
	section += '    "player_tone": "friendly|hostile|flirtatious|threatening|neutral|empathetic|dismissive",\n'
	section += '    "emotional_impact": "very_positive|positive|neutral|negative|very_negative",\n'
	section += '    "interaction_type": "<see allowed types below>",\n'
	section += '    "trust_change": 0,\n'
	section += '    "respect_change": 0,\n'
	section += '    "affection_change": 0,\n'
	section += '    "fear_change": 0,\n'
	section += '    "familiarity_change": 1,\n'
	section += '    "learned_about_player": {\n'
	section += '      "name": null,\n'
	section += '      "occupation": null,\n'
	section += '      "origin": null,\n'
	section += '      "notable_facts": []\n'
	section += '    }\n'
	section += '  }\n'
	section += '}\n\n'

	# Phase 5: Add constrained interaction types from config
	section += "### ALLOWED interaction_type VALUES (use EXACTLY one of these):\n"
	section += "- \"casual_conversation\" - General chat, small talk\n"
	section += "- \"quest_related\" - Discussion about quests or tasks\n"
	section += "- \"gift_given\" - Player gave you something\n"
	section += "- \"emotional_support\" - Comforting, encouraging words\n"
	section += "- \"romantic_gesture\" - Flirtation, romantic interest\n"
	section += "- \"threat_made\" - Intimidation, threats\n"
	section += "- \"secret_shared\" - Revealing private information\n"
	section += "- \"betrayal\" - Breaking trust, deception revealed\n"
	section += "- \"life_saved\" - Player saved your life or vice versa\n"
	section += "- \"romance_confession\" - Declaring romantic feelings\n"
	section += "- \"promise_made\" - Committing to something\n"
	section += "- \"promise_broken\" - Failed to keep a commitment\n"
	section += "- \"defended_player\" - Stood up for the player\n"
	section += "- \"information_shared\" - Providing useful knowledge\n"
	section += "DO NOT invent new types. Use \"casual_conversation\" if unsure.\n\n"

	section += "The analysis reflects how YOU (the NPC) perceive the player's message.\n"
	section += "Dimension changes should be SMALL for most interactions (-5 to +5). Only use larger values (-15 to +15) for significant moments.\n"
	section += "IMPORTANT: If the player reveals their name, occupation, where they're from, or any notable facts about themselves, record it in learned_about_player. Use null if not mentioned.\n\n"
	section += "## Dialogue Tone Notation\n"
	section += "Use [brackets] to indicate tone, emotion, or action at the START of your response. Examples:\n"
	section += "- [warmly] It's good to see you again.\n"
	section += "- [nervously glancing around] Keep your voice down...\n"
	section += "- [sarcastically] Oh, you're an expert now?\n"
	section += "- [with a sad smile] Some things can't be undone.\n"
	section += "This helps convey HOW you're speaking, not just WHAT you're saying.\n"
	return section

## Build enhanced system prompt with RAG memories and current state (LEGACY)
## Now uses tiered_memories dictionary instead of separate arrays
## PRIORITY ORDER: Response Format first to survive truncation
func _build_system_prompt(base_prompt: String, npc_id: String, tiered_memories: Dictionary, relationship: float, dimensions: Dictionary, world_state: Dictionary) -> String:
	var prompt = ""

	# =========================================================================
	# SECTION 1: RESPONSE FORMAT (CRITICAL - Must be first)
	# =========================================================================
	prompt += _build_response_format_section()

	# =========================================================================
	# SECTION 2: BASE PROMPT (NPC identity)
	# =========================================================================
	prompt += base_prompt + "\n\n"

	# =========================================================================
	# SECTION 3: CANONICAL WORLD FACTS (prevents hallucination)
	# =========================================================================
	if WorldKnowledge and not npc_id.is_empty():
		prompt += WorldKnowledge.get_world_facts_for_npc(npc_id)

	# =========================================================================
	# SECTION 4: RELATIONSHIP STATE
	# =========================================================================
	if dimensions.size() > 0:
		prompt += "## Your Multi-Dimensional Relationship with the Player\n"
		prompt += "Your feelings are complex, not a single number:\n\n"

		var trust = dimensions.get("trust", 0)
		var respect = dimensions.get("respect", 0)
		var affection = dimensions.get("affection", 0)
		var fear = dimensions.get("fear", 0)
		var familiarity = dimensions.get("familiarity", 0)

		prompt += "**Trust:** %d/100 - %s\n" % [trust, _interpret_dimension("trust", trust)]
		prompt += "**Respect:** %d/100 - %s\n" % [respect, _interpret_dimension("respect", respect)]
		prompt += "**Affection:** %d/100 - %s\n" % [affection, _interpret_dimension("affection", affection)]
		prompt += "**Fear:** %d/100 - %s\n" % [fear, _interpret_dimension("fear", fear)]
		prompt += "**Familiarity:** %d/100 - %s\n\n" % [familiarity, _interpret_dimension("familiarity", familiarity)]
	else:
		# Fallback to legacy single relationship score
		prompt += "## Current Relationship with Player\n"
		var relationship_desc = _describe_relationship(relationship)
		prompt += "Your current opinion of the player: %s (%d/100)\n\n" % [relationship_desc, int(relationship)]

	# =========================================================================
	# SECTION 5: MEMORIES (Tiered)
	# =========================================================================
	prompt += _build_tiered_memories_section(tiered_memories)

	# =========================================================================
	# SECTION 6: WORLD STATE
	# =========================================================================
	if world_state.size() > 0:
		prompt += "## Current World Situation\n"

		if world_state.has("active_quests") and world_state.active_quests.size() > 0:
			prompt += "Active quests involving you: %s\n" % ", ".join(world_state.active_quests)

		if world_state.has("world_flags"):
			for flag in world_state.world_flags:
				if world_state.world_flags[flag]:
					prompt += "- %s is happening\n" % flag.replace("_", " ").capitalize()

		prompt += "\n"

	# =========================================================================
	# SECTION 7: BEHAVIORAL GUIDANCE (Lowest priority - OK to truncate)
	# =========================================================================
	if dimensions.size() > 0:
		prompt += _generate_behavioral_guidance(dimensions)
		prompt += "\n"

	prompt += "## Roleplay Instructions\n"
	prompt += "- Stay in character - these dimensions shape your personality, not scripts\n"
	prompt += "- Generate ALL dialogue based on your feelings (dimensions + memories)\n"
	prompt += "- Reference memories naturally - weave them into conversation organically\n"
	prompt += "- Let your emotional state guide tone: high affection = warmth, high fear = caution\n"
	prompt += "- Keep responses concise (2-4 sentences unless player asks for details)\n"
	prompt += "- Speak like a character in a JRPG world\n"
	prompt += "- NEVER use pre-written dialogue - every response is unique to this relationship\n\n"

	return prompt

## Convert conversation history into Claude message format
func _build_message_history(history: Array, current_input: String) -> Array:
	var messages = []
	
	# Add conversation history
	for turn in history:
		if turn.has("speaker") and turn.has("message"):
			var role = "assistant" if turn.speaker == "npc" else "user"
			messages.append({
				"role": role,
				"content": turn.message
			})
	
	# Add current player input
	if not current_input.is_empty():
		messages.append({
			"role": "user",
			"content": current_input
		})
	
	# Ensure messages start with user if empty
	if messages.is_empty():
		messages.append({
			"role": "user",
			"content": "(Player approaches)"
		})
	
	return messages

## Describe relationship value in natural language
func _describe_relationship(value: float) -> String:
	if value >= 75:
		return "Trusted friend"
	elif value >= 50:
		return "Friendly"
	elif value >= 25:
		return "Positive"
	elif value >= -25:
		return "Neutral"
	elif value >= -50:
		return "Wary"
	elif value >= -75:
		return "Distrustful"
	else:
		return "Hostile"

## Categorize memories by event type for structured prompting
## memories: Array of memory strings
## raw_memories: Optional array of memory objects with metadata
func _categorize_memories(memories: Array, raw_memories: Array = []) -> Dictionary:
	var categorized = {
		"actions": [],      # Quest accepted/completed, help given/refused
		"conversations": [], # Dialogue exchanges
		"events": []        # Witnessed events, world changes
	}
	
	# If we have raw memory objects with metadata, use those for better categorization
	if raw_memories.size() > 0:
		for mem in raw_memories:
			var event_type = mem.get("event_type", "conversation")
			var text = mem.get("document", mem.get("text", ""))
			
			# Categorize by event type
			if event_type in ["quest_accepted", "quest_refused", "quest_completed", "quest_failed", 
							  "helped", "refused_help", "item_given", "item_received"]:
				categorized.actions.append(text)
			elif event_type in ["conversation", "conversation_summary"]:
				categorized.conversations.append(text)
			elif event_type in ["witnessed_event", "witnessed_crime"]:
				categorized.events.append(text)
			else:
				# Default to conversation
				categorized.conversations.append(text)
	else:
		# Fallback: categorize by content keywords if no metadata
		for memory in memories:
			var mem_lower = memory.to_lower()
			
			if "quest" in mem_lower or "agreed" in mem_lower or "refused" in mem_lower or \
			   "helped" in mem_lower or "completed" in mem_lower or "given" in mem_lower:
				categorized.actions.append(memory)
			elif "witnessed" in mem_lower or "saw" in mem_lower:
				categorized.events.append(memory)
			else:
				categorized.conversations.append(memory)
	
	# Limit each category to avoid overwhelming the prompt
	categorized.actions = categorized.actions.slice(0, 5)
	categorized.conversations = categorized.conversations.slice(0, 5)
	categorized.events = categorized.events.slice(0, 3)
	
	return categorized

## Estimate token count for context (rough approximation)
## Useful for staying under Claude's limits
func estimate_token_count(context: Dictionary) -> int:
	var total_chars = 0
	
	if context.has("system_prompt"):
		total_chars += context.system_prompt.length()
	
	if context.has("messages"):
		for msg in context.messages:
			total_chars += msg.content.length()
	
	# Rough approximation: 1 token ≈ 4 characters
	return int(total_chars / 4.0)

## Trim conversation history to fit token limit
## max_tokens: Target token budget
## Returns: Trimmed context that fits within budget
func trim_to_token_limit(context: Dictionary, max_tokens: int = 2000) -> Dictionary:
	var current_tokens = estimate_token_count(context)
	
	if current_tokens <= max_tokens:
		return context
	
	# System prompt is essential, don't trim
	# Trim conversation history from oldest first
	var trimmed = context.duplicate(true)
	
	if trimmed.has("messages") and trimmed.messages.size() > 2:
		# Keep current player input (last message) and one NPC response
		while estimate_token_count(trimmed) > max_tokens and trimmed.messages.size() > 2:
			trimmed.messages.remove_at(0)  # Remove oldest message
	
	return trimmed

## Build a simple greeting context (when NPC initiates conversation)
func build_greeting_context(system_prompt: String, npc_id: String, relationship: float) -> Dictionary:
	return build_context({
		"system_prompt": system_prompt,
		"npc_id": npc_id,
		"relationship_status": relationship,
		"player_input": "(Player approaches you)"
	})

## Build context for NPC reaction to witnessed event
func build_reaction_context(system_prompt: String, npc_id: String, event_description: String, memories: Array = []) -> Dictionary:
	return build_context({
		"system_prompt": system_prompt,
		"npc_id": npc_id,
		"rag_memories": memories,
		"player_input": "You witness: %s. How do you react?" % event_description
	})

## Interpret relationship dimension value into natural language
func _interpret_dimension(dimension_name: String, value: float) -> String:
	match dimension_name:
		"trust":
			if value >= 75:
				return "You trust them deeply - they've proven themselves repeatedly"
			elif value >= 50:
				return "You trust them - they seem reliable"
			elif value >= 25:
				return "You're starting to trust them"
			elif value >= -25:
				return "You're cautious - they haven't earned your trust yet"
			elif value >= -50:
				return "You don't trust them - they've been unreliable"
			else:
				return "You absolutely don't trust them - they've betrayed you"
		
		"respect":
			if value >= 75:
				return "You deeply respect their abilities and character"
			elif value >= 50:
				return "You respect them - they're capable"
			elif value >= 25:
				return "You're starting to respect them"
			elif value >= -25:
				return "You're neutral - they haven't impressed you"
			elif value >= -50:
				return "You don't respect them much"
			else:
				return "You have no respect for them"
		
		"affection":
			if value >= 75:
				return "You care deeply about them - possibly love"
			elif value >= 50:
				return "You genuinely like them as a person"
			elif value >= 25:
				return "You're warming up to them"
			elif value >= -25:
				return "You feel neutral toward them personally"
			elif value >= -50:
				return "You dislike them"
			else:
				return "You actively dislike them"
		
		"fear":
			if value >= 75:
				return "You're terrified of them - they're dangerous"
			elif value >= 50:
				return "You fear them - they're intimidating"
			elif value >= 25:
				return "You're wary - they make you nervous"
			elif value >= -25:
				return "You're not afraid of them"
			else:
				return "You feel completely safe around them"
		
		"familiarity":
			if value >= 75:
				return "You know them very well - close relationship"
			elif value >= 50:
				return "You know them fairly well"
			elif value >= 25:
				return "You're getting to know them"
			else:
				return "You barely know them - still a stranger"
	
	return "Unknown"

## Generate dynamic behavioral guidance based on relationship dimensions
func _generate_behavioral_guidance(dimensions: Dictionary) -> String:
	var trust = dimensions.get("trust", 0)
	var respect = dimensions.get("respect", 0)
	var affection = dimensions.get("affection", 0)
	var fear = dimensions.get("fear", 0)
	var familiarity = dimensions.get("familiarity", 0)
	
	var guidance = "**How these feelings affect your behavior:**\n"
	
	# Trust-based behavior
	if trust > 70:
		guidance += "- Share secrets and vulnerabilities - you trust them completely\n"
	elif trust > 30:
		guidance += "- Be open but maintain some boundaries - trust is building\n"
	elif trust < -30:
		guidance += "- Be guarded and skeptical - they've proven untrustworthy\n"
	
	# Respect-based behavior
	if respect > 70:
		guidance += "- Seek their opinion, defer to their expertise in areas they've proven capable\n"
	elif respect < -30:
		guidance += "- Dismissive tone, don't take them seriously\n"
	
	# Affection-based behavior
	if affection > 70:
		guidance += "- Show warmth and genuine care - you deeply like them\n"
	elif affection > 30:
		guidance += "- Friendly and welcoming tone\n"
	elif affection < -30:
		guidance += "- Cold, minimal interaction - you dislike them\n"
	
	# Fear-based behavior
	if fear > 70:
		guidance += "- Submissive, eager to please, avoid conflict at all costs\n"
	elif fear > 30:
		guidance += "- Careful with words, don't provoke them\n"
	elif fear < -30:
		guidance += "- Completely comfortable, no intimidation\n"
	
	# Familiarity-based behavior
	if familiarity > 60:
		guidance += "- Reference shared history, inside jokes, past conversations\n"
	elif familiarity < 20:
		guidance += "- Formal, asking basic questions to learn about them\n"
	
	# Conflicted states (create interesting dynamics)
	if affection > 50 and fear > 50:
		guidance += "- **CONFLICTED**: You're attracted but afraid - show internal struggle\n"
	
	if trust < 20 and respect > 60:
		guidance += "- **CONFLICTED**: You respect but don't trust - acknowledge skill while maintaining distance\n"
	
	if affection > 60 and trust > 60 and familiarity > 50:
		guidance += "- **INTIMATE BOND**: Consider romantic undertones if personality permits\n"
	
	return guidance
