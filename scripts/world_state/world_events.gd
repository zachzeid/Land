extends Node
# WorldEvents - Canonical log of events that actually happened in the game world
# Provides the "shared story" that all NPCs can reference consistently
# Also validates NPC memories before storage to prevent hallucination persistence

## Event categories
enum EventCategory {
	PLAYER_ACTION,      # Things the player did
	NPC_INTERACTION,    # Conversations, meetings
	WORLD_CHANGE,       # Weather, time, location changes
	QUEST_PROGRESS,     # Quest-related events
	COMMERCE,           # Trades, purchases
	COMBAT,             # Fights, deaths
	RUMOR               # Things NPCs heard (may be uncertain)
}

## Canonical event log - things that ACTUALLY happened
## Format: {id: {timestamp, category, description, participants, location, verified}}
var canonical_events: Dictionary = {}
var event_counter: int = 0

## Player facts - verified information about the player character
var player_facts: Dictionary = {
	"name": null,           # Player's stated name (null = unknown)
	"occupation": null,     # What they claim to do
	"origin": null,         # Where they claim to be from
	"notable_facts": [],    # Other things NPCs learned
	"first_seen": 0.0,      # Timestamp of first interaction
	"interactions": []      # List of NPC IDs player has talked to
}

## Forbidden terms - names that should NEVER appear in memories
## These are common hallucination patterns (specific fake establishment names)
var forbidden_establishment_names: Array = [
	"weary wanderer",
	"weary traveler",
	"golden goose",
	"silver spoon",
	"dancing dragon",
	"prancing pony",
	"wandering merchant",
	"traveler's rest",
	# Note: "the inn", "old inn", "village tavern" removed - too generic and cause false positives
	# NPCs naturally say "at the inn" or "the village tavern" when referring to The Rusty Nail
]

## Forbidden NPC names - hallucinated characters that don't exist
## These will cause memory rejection if found
var forbidden_npc_names: Array = [
	"marta",      # Common hallucination - no such NPC
	"thomas",     # Common hallucination
	"sarah",      # Common hallucination
	"john",       # Common hallucination
	"mary",       # Common hallucination
	"william",    # Common hallucination
	"elizabeth",  # Common hallucination
	"james",      # Common hallucination
	"margaret",   # Common hallucination
	"robert",     # Common hallucination
	# Add more as they appear in testing
]

## Register a canonical event that actually happened
func register_event(category: EventCategory, description: String, participants: Array = [], location: String = "") -> String:
	event_counter += 1
	var event_id = "event_%d_%d" % [Time.get_unix_time_from_system(), event_counter]

	canonical_events[event_id] = {
		"timestamp": Time.get_unix_time_from_system(),
		"category": category,
		"description": description,
		"participants": participants,
		"location": location,
		"verified": true
	}

	print("[WorldEvents] Registered: %s - %s" % [event_id, description])
	return event_id

## Register player information learned during conversation
func register_player_info(info_type: String, value: String, source_npc: String):
	match info_type:
		"name":
			if player_facts.name == null:
				player_facts.name = value
				print("[WorldEvents] Player name learned: %s (from %s)" % [value, source_npc])
				register_event(EventCategory.NPC_INTERACTION,
					"Player introduced themselves as '%s' to %s" % [value, source_npc],
					["player", source_npc])
		"occupation":
			if player_facts.occupation == null:
				player_facts.occupation = value
				print("[WorldEvents] Player occupation learned: %s (from %s)" % [value, source_npc])
		"origin":
			if player_facts.origin == null:
				player_facts.origin = value
				print("[WorldEvents] Player origin learned: %s (from %s)" % [value, source_npc])
		_:
			if value not in player_facts.notable_facts:
				player_facts.notable_facts.append(value)
				print("[WorldEvents] Player fact learned: %s (from %s)" % [value, source_npc])

## Get player's known name (for NPCs to use)
func get_player_name() -> String:
	if player_facts.name != null:
		return player_facts.name
	return "stranger"

## Check if player has been introduced
func is_player_known() -> bool:
	return player_facts.name != null

## Validate a memory string before storage
## Returns: {valid: bool, issues: Array, sanitized: String}
func validate_memory(memory_text: String, npc_id: String) -> Dictionary:
	var result = {
		"valid": true,
		"issues": [],
		"sanitized": memory_text
	}

	var lower_text = memory_text.to_lower()

	# Check for forbidden establishment names (hallucinations)
	for forbidden in forbidden_establishment_names:
		if forbidden in lower_text:
			result.valid = false
			result.issues.append("Contains forbidden name: '%s'" % forbidden)
			# Try to sanitize by removing the hallucinated content
			# This is aggressive but prevents persistence of hallucinations

	# Check for establishment names that don't exist
	var mentioned_establishments = _extract_quoted_names(memory_text)
	for name in mentioned_establishments:
		if not WorldKnowledge.is_valid_establishment_name(name):
			# Check if it's close to a valid name (typo tolerance)
			var valid_names = WorldKnowledge.get_all_establishment_names()
			var found_match = false
			for valid_name in valid_names:
				if _is_similar(name, valid_name):
					found_match = true
					result.issues.append("'%s' corrected to '%s'" % [name, valid_name])
					result.sanitized = result.sanitized.replace(name, valid_name)
					break

			if not found_match and name.length() > 3:  # Ignore very short strings
				result.valid = false
				result.issues.append("Unknown establishment: '%s'" % name)

	# Validate NPC names mentioned
	var npc_names_mentioned = _extract_npc_names(memory_text)
	for name in npc_names_mentioned:
		# Check if it's a known hallucination pattern
		if name.to_lower() in forbidden_npc_names:
			result.valid = false
			result.issues.append("Contains hallucinated NPC: '%s'" % name)
		elif not _is_valid_npc_name(name):
			result.issues.append("Unknown NPC name: '%s' (may be hallucinated)" % name)
			# Don't invalidate for unknown names - could be player's name or legitimate new character

	# Check for location inconsistencies
	if "king's castle" in lower_text or "capital" in lower_text:
		var npc_scope = WorldKnowledge.get_knowledge_scope_for_location(npc_id, "kings_castle")
		if npc_scope == WorldKnowledge.KnowledgeScope.DISTANT or npc_scope == WorldKnowledge.KnowledgeScope.UNKNOWN:
			if "i visited" in lower_text or "i went to" in lower_text or "i was at" in lower_text:
				result.valid = false
				result.issues.append("NPC claims to have visited distant location they couldn't know")

	if result.issues.size() > 0:
		print("[WorldEvents] Memory validation for %s: %s" % [npc_id, result.issues])

	return result

## Extract quoted names from text (potential establishment/place names)
func _extract_quoted_names(text: String) -> Array:
	var names = []

	# First, remove dialogue content to avoid false positives
	# Pattern: "Player said: "..." or "I responded: "..."
	var cleaned_text = text
	var dialogue_regex = RegEx.new()
	dialogue_regex.compile('Player said:\\s*"[^"]*"')
	cleaned_text = dialogue_regex.sub(cleaned_text, "", true)
	dialogue_regex.compile('I responded:\\s*"[^"]*"')
	cleaned_text = dialogue_regex.sub(cleaned_text, "", true)
	# Also remove roleplay asterisk content
	dialogue_regex.compile('\\*[^*]+\\*')
	cleaned_text = dialogue_regex.sub(cleaned_text, "", true)

	var regex = RegEx.new()
	# Match "The X Y" patterns (establishment names like "The Rusty Nail")
	# Only look for short, establishment-like names (2-4 words max)
	regex.compile('[Tt]he ([A-Z][a-z]+(?:\\s+[A-Z][a-z]+){1,3})')
	var matches = regex.search_all(cleaned_text)
	for m in matches:
		var captured = m.get_string(1)
		if captured != "" and captured.length() < 50:  # Reasonable establishment name length
			names.append("The " + captured)

	return names

## Check if two strings are similar (for typo tolerance)
func _is_similar(a: String, b: String) -> bool:
	var a_lower = a.to_lower()
	var b_lower = b.to_lower()

	# Exact match
	if a_lower == b_lower:
		return true

	# One contains the other
	if a_lower in b_lower or b_lower in a_lower:
		return true

	# Simple edit distance check (allow 2 character difference for short strings)
	if abs(a.length() - b.length()) <= 2:
		var matches = 0
		for i in range(min(a_lower.length(), b_lower.length())):
			if a_lower[i] == b_lower[i]:
				matches += 1
		if float(matches) / max(a_lower.length(), b_lower.length()) > 0.7:
			return true

	return false

## Common words that are NOT NPC names (sentence starters, pronouns, etc.)
const COMMON_NON_NAME_WORDS = [
	# Articles and conjunctions
	"the", "and", "but", "for", "with", "this", "that", "from", "into",
	# Pronouns
	"you", "your", "yours", "yourself", "him", "her", "his", "hers", "its",
	"they", "them", "their", "theirs", "who", "whom", "whose", "which",
	# Common sentence starters
	"what", "when", "where", "why", "how", "will", "would", "could", "should",
	"can", "may", "might", "must", "shall", "have", "has", "had", "been",
	"are", "was", "were", "being", "did", "does", "done", "come", "came",
	"going", "gone", "went", "know", "knew", "known", "think", "thought",
	"take", "took", "taken", "make", "made", "let", "get", "got", "see",
	"saw", "seen", "look", "looked", "find", "found", "give", "gave", "given",
	"tell", "told", "say", "said", "ask", "asked", "want", "wanted", "need",
	# Common dialogue words
	"yes", "yeah", "yep", "no", "nope", "not", "never", "always", "maybe",
	"perhaps", "please", "thanks", "thank", "sorry", "okay", "alright",
	"well", "now", "then", "here", "there", "just", "only", "also", "too",
	"very", "really", "quite", "rather", "still", "already", "yet", "ever",
	"player",  # The player reference
	# Contractions (when split)
	"i'll", "i'm", "i've", "i'd", "you'll", "you're", "you've", "you'd",
	"he's", "she's", "it's", "we're", "we've", "we'll", "they're", "they've",
	"that's", "there's", "here's", "what's", "who's", "don't", "doesn't",
	"didn't", "won't", "wouldn't", "can't", "couldn't", "shouldn't", "isn't",
	"aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
	# Common adjectives/adverbs at sentence start
	"good", "bad", "great", "fine", "nice", "sure", "right", "wrong",
	"first", "last", "next", "every", "some", "any", "all", "most", "many",
	"much", "few", "several", "both", "each", "other", "another", "such",
	# Time/action words
	"wait", "stop", "watch", "listen", "hear", "heard", "feel", "felt",
	"stay", "leave", "left", "keep", "kept", "hold", "held", "put", "set",
	# Greetings and farewells
	"hello", "hi", "hey", "greetings", "farewell", "fare", "goodbye", "bye",
	"welcome", "morning", "evening", "night", "friend", "stranger", "traveler",
	# Common verbs that might appear capitalized
	"forgive", "remember", "forget", "believe", "trust", "hope", "wish",
	"bless", "curse", "pray", "help", "save", "protect", "guide",
	# Tavern/inn related words
	"rusty", "golden", "silver", "iron", "wooden", "old", "new", "red", "blue",
	"tankard", "mug", "ale", "mead", "wine", "bread", "stew", "coin", "coins",
	"nail", "hammer", "sword", "shield", "armor", "weapon",
	# Location words
	"village", "town", "city", "square", "market", "shop", "inn", "tavern",
	"church", "temple", "castle", "tower", "gate", "road", "path", "forest",
	# More adjectives that might appear capitalized at sentence start
	"safe", "smart", "quick", "slow", "hard", "soft", "warm", "cold", "dark", "light",
	"tall", "short", "long", "small", "large", "big", "little", "young", "old",
	"true", "false", "real", "fake", "open", "closed", "free", "full", "empty",
	"simple", "easy", "difficult", "strange", "odd", "weird", "normal", "usual",
	"certain", "clear", "plain", "obvious", "honest", "fair", "kind", "gentle",
	# Prepositions and connectors that might be capitalized
	"between", "among", "within", "without", "before", "after", "during", "since",
	"until", "through", "across", "above", "below", "under", "over", "beside",
	"beyond", "behind", "around", "toward", "towards", "along", "against",
	# Building/craft terms that might appear
	"dovetail", "joint", "beam", "plank", "timber", "stone", "brick", "mortar",
	# Emotes and roleplay markers
	"*voice", "*touches", "*watches", "*reaches", "*gestures", "*calls",
	"*takes", "*looks", "*barely", "*softer", "*voice", "*turns"
]

## Extract potential NPC names from text
func _extract_npc_names(text: String) -> Array:
	var names = []
	# Look for capitalized words that might be names
	var words = text.split(" ")
	for i in range(words.size()):
		var word = words[i].strip_edges()
		# Remove punctuation and emote markers
		word = word.trim_prefix("*").trim_suffix(",").trim_suffix(".").trim_suffix("!").trim_suffix("?").trim_suffix("*")
		# Skip words inside asterisks (roleplay actions)
		if "*" in words[i]:
			continue
		if word.length() > 2 and word[0] == word[0].to_upper() and word[0] != word[0].to_lower():
			# Skip common words that are NOT names
			if word.to_lower() not in COMMON_NON_NAME_WORDS:
				names.append(word)
	return names

## Check if a name is a valid NPC
func _is_valid_npc_name(name: String) -> bool:
	var lower_name = name.to_lower()

	# "Player" is always valid
	if lower_name == "player":
		return true

	for npc_id in WorldKnowledge.world_facts.npcs:
		var npc = WorldKnowledge.world_facts.npcs[npc_id]
		# Check both short name and full name
		if npc.name.to_lower() == lower_name or npc.full_name.to_lower() == lower_name:
			return true
		# Also check if it's part of the NPC's name (e.g., "Mathias" from "Elder Mathias")
		if lower_name in npc.full_name.to_lower() or lower_name in npc.name.to_lower():
			return true

	# Also check if it's the player's name
	if player_facts.name != null and player_facts.name.to_lower() == lower_name:
		return true

	return false

## Get events relevant to a specific NPC (for memory injection)
func get_events_for_npc(npc_id: String, limit: int = 10) -> Array:
	var relevant = []
	for event_id in canonical_events:
		var event = canonical_events[event_id]
		if npc_id in event.participants or "all" in event.participants:
			relevant.append(event)

	# Sort by timestamp descending
	relevant.sort_custom(func(a, b): return a.timestamp > b.timestamp)

	return relevant.slice(0, limit)

## Get shared world events (things everyone in a location would know)
func get_local_events(location: String, limit: int = 5) -> Array:
	var local = []
	for event_id in canonical_events:
		var event = canonical_events[event_id]
		if event.location == location or event.location == "":  # Empty = global
			local.append(event)

	local.sort_custom(func(a, b): return a.timestamp > b.timestamp)
	return local.slice(0, limit)

## Debug: Print all stored events
func debug_print_events():
	print("\n=== CANONICAL WORLD EVENTS ===")
	for event_id in canonical_events:
		var e = canonical_events[event_id]
		print("[%s] %s: %s (participants: %s)" % [
			event_id,
			EventCategory.keys()[e.category],
			e.description,
			e.participants
		])
	print("\n=== PLAYER FACTS ===")
	print("Name: %s" % [player_facts.name if player_facts.name else "Unknown"])
	print("Occupation: %s" % [player_facts.occupation if player_facts.occupation else "Unknown"])
	print("Origin: %s" % [player_facts.origin if player_facts.origin else "Unknown"])
	print("Notable facts: %s" % [player_facts.notable_facts])
	print("================================\n")

## Debug: Dump all NPC memories (requires access to RAGMemory instances)
## Call this from a scene that has access to NPCs
func debug_dump_all_memories(npcs: Array) -> String:
	var output = "\n=== NPC MEMORY DUMP ===\n"
	for npc in npcs:
		if npc.has_method("get") and npc.get("rag_memory"):
			output += "\n--- %s (%s) ---\n" % [npc.npc_name, npc.npc_id]
			# This would need RAGMemory to expose a dump method
			output += "(Memory dump requires RAGMemory.dump_all_memories())\n"
	output += "========================\n"
	return output

## Clear all hallucinated memories from an NPC (nuclear option)
## Returns count of removed memories
func purge_hallucinated_memories(rag_memory: Node) -> int:
	# This would need RAGMemory to expose memory iteration
	# For now, log that it was called
	print("[WorldEvents] Purge requested - would remove invalid memories")
	return 0
