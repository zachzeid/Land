extends SceneTree

# Tests ContextBuilder (scripts/dialogue/context_builder.gd) with a plain system prompt:
# - build_context: response format first, base prompt, legacy relationship, tiered memories, world state,
#   roleplay instructions, and the conversation history mapped to Claude roles
# - estimate_token_count, trim_to_token_limit (oldest dropped first, the player's input kept)
# - _describe_relationship bands, build_greeting_context, build_reaction_context
# No API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_context_builder.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const PROMPT = "You are Aldric, a gruff but kind blacksmith. You speak in short sentences and distrust outsiders initially."

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "CONTEXT BUILDER TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 CONTEXT BUILDER TEST")
	print("============================================================\n")
	var builder = load("res://scripts/dialogue/context_builder.gd").new()

	print("build_context")
	var context = builder.build_context({
		"system_prompt": PROMPT,
		"tiered_memories": {
			"pinned": ["[DEFINING MOMENT] The player saved my forge from the fire."],
			"important": ["[Memory - witnessed_crime, importance: 9] I saw the player steal bread. I'm disappointed."],
			"relevant": ["[Memory - conversation, importance: 7] Player asked about magical swords."]
		},
		"relationship_status": 35.0,
		"world_state": {"active_quests": ["find_lost_sword"], "world_flags": {"village_under_threat": true}},
		"conversation_history": [
			{"speaker": "user", "message": "Hello, can you help me?"},
			{"speaker": "npc", "message": "Maybe. Depends what you need."}
		],
		"player_input": "I need a weapon for the bandits."
	})
	var prompt: String = context.system_prompt
	_check("Returns system_prompt and messages", context.has("system_prompt") and context.has("messages"))
	_check("Response format comes first", prompt.find("CRITICAL: Response Format") >= 0 and prompt.find("CRITICAL: Response Format") < prompt.find(PROMPT))
	_check("Base prompt included", PROMPT in prompt)
	_check("Legacy relationship described (35 = Positive)", "## Current Relationship with Player" in prompt and "Positive (35/100)" in prompt)
	_check("Pinned memory included", "saved my forge" in prompt)
	_check("Important memory included", "steal bread" in prompt)
	_check("Relevant memory included", "magical swords" in prompt)
	_check("World state: active quest", "find_lost_sword" in prompt)
	_check("World state: flag", "Village Under Threat is happening" in prompt)
	_check("Roleplay instructions included", "## Roleplay Instructions" in prompt)
	var roles = context.messages.map(func(m): return m.role)
	_check("History maps to user/assistant/user", roles == ["user", "assistant", "user"])
	_check("Player input is the last message", context.messages[-1].content == "I need a weapon for the bandits.")

	print("\nToken estimation and trimming")
	var tokens = builder.estimate_token_count(context)
	_check("Token estimate is about chars / 4", tokens > 0 and abs(tokens - (prompt.length() + _content_chars(context)) / 4) <= 1)
	var history = []
	for i in range(50):
		history.append({"speaker": "user", "message": "Test message %d with some padding to make it longer" % i})
	var large = builder.build_context({"system_prompt": PROMPT, "conversation_history": history, "player_input": "Current question"})
	var budget = builder.estimate_token_count({"system_prompt": large.system_prompt}) + 100
	var trimmed = builder.trim_to_token_limit(large, budget)
	_check("Large context starts over budget", builder.estimate_token_count(large) > budget)
	_check("Trimmed context fits the budget", builder.estimate_token_count(trimmed) <= budget)
	_check("Trimming drops the oldest messages first", trimmed.messages.size() < large.messages.size() and trimmed.messages[0].content != large.messages[0].content)
	_check("Trimming keeps the player's input", trimmed.messages[-1].content == "Current question")
	_check("Trimming leaves the original untouched", large.messages.size() == 51)
	_check("A context under budget is returned as is", builder.trim_to_token_limit(context, 100000) == context)

	print("\nRelationship bands")
	var bands = {100: "Trusted friend", 60: "Friendly", 30: "Positive", 0: "Neutral", -30: "Wary", -60: "Distrustful", -90: "Hostile"}
	for value in bands:
		_check("%d → %s" % [value, bands[value]], builder._describe_relationship(value) == bands[value])

	print("\nHelpers")
	var greeting = builder.build_greeting_context(PROMPT, "", 50.0)
	_check("Greeting: player approaches", greeting.messages[-1].content == "(Player approaches you)")
	_check("Greeting: relationship 50 = Friendly", "Friendly (50/100)" in greeting.system_prompt)
	var reaction = builder.build_reaction_context(PROMPT, "", "The player attacks a guard")
	_check("Reaction: asks how the NPC reacts to the event", reaction.messages[-1].content == "You witness: The player attacks a guard. How do you react?")

	builder.free()
	_finish()

func _content_chars(context: Dictionary) -> int:
	var total = 0
	for m in context.messages:
		total += m.content.length()
	return total

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
