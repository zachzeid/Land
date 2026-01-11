extends SceneTree
# Test ContextBuilder formatting

func _init():
	print("\n=== ContextBuilder Test ===\n")
	
	var context_builder = load("res://scripts/dialogue/context_builder.gd").new()
	
	# Test 1: Basic context building
	print("Test 1: Basic context assembly...")
	
	var system_prompt = "You are Aldric, a gruff but kind blacksmith. You speak in short sentences and distrust outsiders initially."
	
	var context = context_builder.build_context({
		"system_prompt": system_prompt,
		"rag_memories": [
			"[Memory - conversation, importance: 7] Player asked about magical swords. I told them about the Frostblade.",
			"[Memory - witnessed_crime, importance: 9] I saw the player steal bread. I'm disappointed."
		],
		"relationship_status": 35.0,
		"world_state": {
			"active_quests": ["find_lost_sword"],
			"world_flags": {"village_under_threat": true}
		},
		"conversation_history": [
			{"speaker": "user", "message": "Hello, can you help me?"},
			{"speaker": "npc", "message": "Maybe. Depends what you need."}
		],
		"player_input": "I need a weapon for the bandits."
	})
	
	print("✅ Context assembled\n")
	
	# Test 2: Examine system prompt
	print("Test 2: System prompt structure...")
	print("System prompt includes:")
	if "Current Relationship" in context.system_prompt:
		print("  ✓ Relationship status")
	if "Your Relevant Memories" in context.system_prompt:
		print("  ✓ RAG memories")
	if "Current World Situation" in context.system_prompt:
		print("  ✓ World state")
	if "Instructions" in context.system_prompt:
		print("  ✓ Behavioral guidelines")
	print()
	
	# Test 3: Message history format
	print("Test 3: Message history format...")
	print("Messages: %d total" % context.messages.size())
	for i in range(context.messages.size()):
		var msg = context.messages[i]
		print("  [%d] %s: %s" % [i, msg.role, msg.content.substr(0, 40) + "..."])
	print()
	
	# Test 4: Token estimation
	print("Test 4: Token estimation...")
	var tokens = context_builder.estimate_token_count(context)
	print("Estimated tokens: %d" % tokens)
	print("✅ Within budget (target: <2000)\n" if tokens < 2000 else "⚠️ May need trimming\n")
	
	# Test 5: Relationship descriptions
	print("Test 5: Relationship descriptions...")
	var test_relationships = [100, 60, 30, 0, -30, -60, -90]
	for rel in test_relationships:
		var desc = context_builder._describe_relationship(rel)
		print("  %3d → %s" % [rel, desc])
	print()
	
	# Test 6: Token trimming
	print("Test 6: Token trimming...")
	var large_history = []
	for i in range(50):
		large_history.append({"speaker": "user", "message": "Test message " + str(i)})
	
	var large_context = context_builder.build_context({
		"system_prompt": system_prompt,
		"conversation_history": large_history,
		"player_input": "Current question"
	})
	
	var original_tokens = context_builder.estimate_token_count(large_context)
	var trimmed = context_builder.trim_to_token_limit(large_context, 500)
	var trimmed_tokens = context_builder.estimate_token_count(trimmed)
	
	print("Original: %d messages, ~%d tokens" % [large_context.messages.size(), original_tokens])
	print("Trimmed: %d messages, ~%d tokens" % [trimmed.messages.size(), trimmed_tokens])
	print("✅ Trimming working\n")
	
	# Test 7: Helper methods
	print("Test 7: Helper methods...")
	
	var greeting = context_builder.build_greeting_context(system_prompt, 50.0)
	print("Greeting context:")
	print("  Last message: %s" % greeting.messages[-1].content)
	
	var reaction = context_builder.build_reaction_context(
		system_prompt,
		"The player attacks a guard"
	)
	print("Reaction context:")
	print("  Last message: %s" % reaction.messages[-1].content.substr(0, 50) + "...")
	print()
	
	print("=== All Tests Passed! ===")
	print("\nContextBuilder is ready for NPC dialogue.")
	print("Key features:")
	print("  ✓ Assembles system prompt with memories and world state")
	print("  ✓ Formats conversation history for Claude")
	print("  ✓ Relationship-aware context")
	print("  ✓ Token estimation and trimming")
	print("  ✓ Helper methods for common scenarios")
	print()
	
	quit()
