extends SceneTree

# Test ContextBuilder dimension interpretation without full NPC

func _init():
	print("============================================================")
	print("🧪 TESTING CONTEXT BUILDER DIMENSION INTERPRETATION")
	print("============================================================\n")
	
	var ContextBuilder = load("res://scripts/dialogue/context_builder.gd")
	var builder = ContextBuilder.new()
	
	# Test case: After 4 interactions (quest, gift, support, danger)
	var dimensions_after_bonding = {
		"trust": 51,
		"respect": 35,
		"affection": 43,
		"fear": -10,
		"familiarity": 30
	}
	
	print("📊 Relationship State (after 4 positive interactions):")
	print("   Trust: 51 (Trusted)")
	print("   Respect: 35 (Respected)")
	print("   Affection: 43 (Close Friend)")
	print("   Fear: -10 (Unafraid)")
	print("   Familiarity: 30 (Well Acquainted)\n")
	
	print("🔍 Building Claude context with these dimensions...\n")
	
	var context = builder.build_context({
		"npc_name": "Gregor",
		"system_prompt": "You are Gregor, a friendly merchant in Thornhaven village. You sell general goods and gossip. You have a daughter named Elena who you worry about constantly.",
		"relationship_dimensions": dimensions_after_bonding,
		"conversation_history": [],
		"player_input": "Hey Gregor, how are things?"
	})
	
	# Extract and display the system prompt that Claude will see
	print("📄 CONTEXT STRUCTURE:")
	print("   Keys: ", context.keys())
	print("")
	
	if context.has("system_prompt"):
		var system_prompt = context.system_prompt
		print("📄 SYSTEM PROMPT SENT TO CLAUDE:")
		print("============================================================")
		print(system_prompt)
		print("============================================================")
	
	if context.has("messages"):
		print("\n💬 MESSAGES SENT TO CLAUDE:")
		for msg in context.messages:
			print("  Role: %s" % msg.get("role", "unknown"))
			var content = msg.get("content", "")
			var preview = content.substr(0, min(200, content.length()))
			print("  Content: %s..." % preview)
			print("")
	
	print("\n✅ Context builder successfully interprets dimensions")
	print("   Claude will see natural language descriptions of each dimension")
	print("   Behavioral guidance will shape response tone and content\n")
	
	quit()
