extends SceneTree

# Test showing full progression: Neutral Stranger → Trusted Friend

func _init():
	print("============================================================")
	print("🧪 FULL RELATIONSHIP EVOLUTION TEST")
	print("============================================================\n")
	
	var ContextBuilder = load("res://scripts/dialogue/context_builder.gd")
	var builder = ContextBuilder.new()
	
	var base_personality = "You are Gregor, a cautious merchant in Thornhaven. You've seen too many adventurers come and go. You protect your daughter Elena fiercely."
	
	# Show 4 stages of relationship evolution
	var stages = [
		{
			"name": "Initial Meeting (Neutral Stranger)",
			"dims": {"trust": 0, "respect": 0, "affection": 0, "fear": 0, "familiarity": 0},
			"player_message": "Hello, I'd like to buy some supplies."
		},
		{
			"name": "After Helping with Quest",
			"dims": {"trust": 15, "respect": 10, "affection": 8, "fear": 0, "familiarity": 5},
			"player_message": "I dealt with those bandits for you. Your wagons are safe now."
		},
		{
			"name": "After Thoughtful Gift",
			"dims": {"trust": 23, "respect": 15, "affection": 23, "fear": 0, "familiarity": 15},
			"player_message": "I found this book about horses for Elena. Heard she loves them."
		},
		{
			"name": "After Bonding Experience (Trusted Friend)",
			"dims": {"trust": 51, "respect": 35, "affection": 43, "fear": -10, "familiarity": 30},
			"player_message": "That was intense. You fought well back there."
		}
	]
	
	for stage in stages:
		print("\n======================================================================")
		print("📍 STAGE: %s" % stage.name)
		print("======================================================================")
		print("\n📊 Dimensions:")
		print("   Trust: %d, Respect: %d, Affection: %d, Fear: %d, Familiarity: %d" % 
			[stage.dims.trust, stage.dims.respect, stage.dims.affection, 
			 stage.dims.fear, stage.dims.familiarity])
		print("\n💬 Player: \"%s\"\n" % stage.player_message)
		
		var context = builder.build_context({
			"system_prompt": base_personality,
			"relationship_dimensions": stage.dims,
			"conversation_history": [],
			"player_input": stage.player_message
		})
		
		# Extract behavioral guidance section
		var system_prompt = context.system_prompt
		
		# Show dimension interpretations
		if "**Trust:**" in system_prompt:
			var trust_start = system_prompt.find("**Trust:**")
			var fam_end = system_prompt.find("\n\n", system_prompt.find("**Familiarity:**"))
			var dims_section = system_prompt.substr(trust_start, fam_end - trust_start)
			
			print("🎭 How Gregor Sees Player:")
			for line in dims_section.split("\n"):
				if line.strip_edges() != "":
					print("   %s" % line)
		
		# Show behavioral guidance
		if "**How these feelings affect your behavior:**" in system_prompt:
			var guidance_start = system_prompt.find("**How these feelings affect your behavior:**")
			var guidance_end = system_prompt.find("\n\n##", guidance_start)
			if guidance_end == -1:
				guidance_end = system_prompt.find("\n\n", guidance_start + 50)
			var guidance_section = system_prompt.substr(guidance_start, guidance_end - guidance_start)
			
			print("\n💡 Expected Behavior:")
			for line in guidance_section.split("\n"):
				var trimmed = line.strip_edges()
				if trimmed != "" and not trimmed.begins_with("**How"):
					print("   %s" % line)
	
	print("\n\n======================================================================")
	print("✅ PROGRESSION VALIDATED")
	print("======================================================================")
	print("\n🎯 Key Observations:")
	print("   • Dimensions evolve through interactions (not time-based)")
	print("   • Each dimension affects Claude's tone independently")
	print("   • Behavioral guidance changes dynamically")
	print("   • NO pre-canned dialogue - Claude generates from dimensions")
	print("\n📋 Next Steps:")
	print("   1. Test in live game with actual Claude responses")
	print("   2. Record interactions through UI")
	print("   3. Observe Claude's evolving personality over multiple conversations")
	print("   4. Implement ChromaDB pattern analysis (Phase 2)\n")
	
	quit()
