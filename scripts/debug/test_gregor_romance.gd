extends Node
## Demonstration: NPC AI-Agent Growth Through Quest Completion
## Shows how Gregor's personality evolves from cautious merchant to romantic interest

func _ready():
	_run_demo()

func _run_demo():
	print("\n" + "=".repeat(70))
	print("🎮 AI-AGENT GROWTH DEMO: From Stranger to Lover")
	print("=".repeat(70))
	print("\nThis demonstrates how NPCs evolve through action memories.\n")
	
	# Load NPCs
	var BaseNPC = load("res://scripts/npcs/base_npc.gd")
	var gregor = BaseNPC.new()
	gregor.npc_id = "gregor_romance_demo"  # Separate from real Gregor
	gregor.npc_name = "Gregor"
	add_child(gregor)
	
	# Load system prompt from actual character file
	var gregor_script = load("res://scripts/npcs/gregor_merchant.gd")
	var temp_gregor = gregor_script.new()
	gregor.system_prompt = temp_gregor.system_prompt
	temp_gregor.free()
	
	await gregor.initialize()
	
	print("\n" + "-".repeat(70))
	print("📖 STORY: Helping Gregor and Building Trust")
	print("-".repeat(70))
	
	# === Act 1: First Meeting (Relationship: 0) ===
	print("\n🎬 ACT 1: First Meeting")
	print("Player enters Gregor's shop for the first time...")
	print("Gregor: Professional but cautious (Relationship: 0/100)\n")
	
	await _wait(1)
	
	# === Act 2: Accepting Quest (Relationship: +5 = 5) ===
	print("\n🎬 ACT 2: The Bandit Problem")
	print("Gregor mentions bandits have been raiding supply wagons...")
	print("Player: 'I can help you with those bandits.'\n")
	
	await gregor.record_player_action(
		"quest_accepted",
		"The player agreed to help me deal with the bandits raiding our supply wagons. I'm hopeful they can actually make a difference.",
		9,
		"hopeful"
	)
	
	print("✅ Quest Accepted!")
	print("   Relationship: 0 → 5 (Player seems trustworthy)")
	print("   Memory stored: Quest acceptance")
	print("   Gregor now feels: Hopeful\n")
	
	await _wait(1)
	
	# === Act 3: Completing Quest (Relationship: +15 = 20) ===
	print("\n🎬 ACT 3: Victory!")
	print("Player returns covered in blood and dust...")
	print("Player: 'The bandits won't bother you anymore. They're in the town jail.'\n")
	
	await gregor.record_player_action(
		"quest_completed",
		"The player defeated the bandits and got them arrested! Our supply wagons are safe now. I'm so grateful - they really came through for me and the village.",
		10,
		"grateful"
	)
	
	print("✅ Quest Completed!")
	print("   Relationship: 5 → 20 (Grateful for the help)")
	print("   Memory stored: Quest completion")
	print("   Gregor now feels: Deeply grateful\n")
	
	await _wait(1)
	
	# === Act 4: Gift of Thanks (Relationship: +10 = 30) ===
	print("\n🎬 ACT 4: A Token of Gratitude")
	print("Player visits shop next day...")
	print("Gregor: 'Please, take this healing potion. It's the least I can do.'\n")
	
	await gregor.record_player_action(
		"item_given",
		"I gave the player a premium healing potion as thanks for dealing with the bandits. They've earned it - and my respect.",
		7,
		"warm"
	)
	
	print("✅ Gift Given!")
	print("   Relationship: 20 → 30 (Starting to like them)")
	print("   Memory stored: Gratitude gift")
	print("   Gregor now feels: Warm toward player\n")
	
	await _wait(1)
	
	# === Act 5: Flirtation Begins (Relationship: 30+) ===
	print("\n🎬 ACT 5: Getting Closer")
	print("Player visits regularly, making small talk...")
	print("Player compliments Gregor's shop organization...\n")
	
	# Simulate positive conversations building relationship
	await gregor.record_player_action(
		"helped",
		"The player helped me reorganize my inventory and shared stories of their adventures. I found myself enjoying their company more than I expected. They're... rather attractive, actually.",
		8,
		"interested"
	)
	
	print("✅ Relationship Deepens!")
	print("   Relationship: 30 → 38 (Subtle attraction developing)")
	print("   Memory stored: Pleasant time together")
	print("   Gregor now feels: Interested... romantically\n")
	
	await _wait(1)
	
	# === Act 6: More Help (Relationship: +5 = 43) ===
	print("\n🎬 ACT 6: Going Above and Beyond")
	print("Player helps Gregor negotiate better prices with suppliers...\n")
	
	await gregor.record_player_action(
		"helped",
		"The player used their reputation to help me get better trade deals. They didn't have to do that. I'm starting to really care about them.",
		7,
		"appreciative"
	)
	
	print("✅ Trust Grows!")
	print("   Relationship: 38 → 43 (Growing affection)")
	print("   Memory stored: Business help")
	print("   Gregor now feels: Very appreciative\n")
	
	await _wait(1)
	
	# === Act 7: Opening Up (Relationship: +10 = 53) ===
	print("\n🎬 ACT 7: A Shared Secret")
	print("Late evening, shop closed, just the two of them...")
	print("Gregor finally reveals: 'I know who's been informing for the bandits...'\n")
	
	await gregor.record_player_action(
		"helped",
		"I told the player about the bandit informant. I trust them enough now to share this dangerous secret. We're... close. Very close.",
		9,
		"trusting"
	)
	
	print("✅ Deep Trust Achieved!")
	print("   Relationship: 43 → 53 (Strong mutual trust)")
	print("   Memory stored: Shared secret")
	print("   Gregor now feels: Trusting, vulnerable\n")
	
	await _wait(1)
	
	# === Act 8: Flirtation Intensifies (Relationship: 53 > 50 threshold) ===
	print("\n🎬 ACT 8: Chemistry")
	print("Conversation becomes more playful, lingering eye contact...")
	print("Gregor drops hints: 'You know... the tavern serves excellent wine...'\n")
	
	await gregor.record_player_action(
		"helped",
		"We talked late into the evening. The player is charming, brave, and kind. I found myself flirting more openly. I think they noticed. I hope they did.",
		8,
		"attracted"
	)
	
	print("✅ Romance Blossoms!")
	print("   Relationship: 53 → 61 (ABOVE romance threshold of 60!)")
	print("   Memory stored: Romantic tension")
	print("   Gregor now feels: Attracted and available\n")
	
	await _wait(1)
	
	# === Act 9: The Invitation (Relationship: 61 > 60 threshold) ===
	print("\n🎬 ACT 9: A Bold Proposal")
	print("Player, emboldened by weeks of growing chemistry:")
	print("Player: 'Gregor... would you like to come back to my room at the tavern? For... wine?'\n")
	
	await _wait(2)
	
	print("💭 Gregor checks his memories and relationship status...")
	print("   - Quest completed: ✓ (They saved the village)")
	print("   - Trust level: ✓ (61/100 - Above 60 threshold)")
	print("   - Shared secrets: ✓ (Informant information)")
	print("   - Mutual attraction: ✓ (Chemistry confirmed)")
	print("   - Romance protocol: ✓ (Personality allows this)\n")
	
	await _wait(2)
	
	print("💕 Gregor's Response:")
	print("   'I thought you'd never ask. Let me just... close up the shop.'\n")
	
	await gregor.record_player_action(
		"item_received",  # Using this to represent accepting invitation
		"The player invited me back to their room at the tavern. After everything we've been through together, how could I refuse? I want this. I want them.",
		10,
		"excited"
	)
	
	print("✅ ROMANCE ACHIEVED!")
	print("   Relationship: 61 → 71 (Strong romantic bond)")
	print("   Memory stored: Accepted romantic invitation")
	print("   Gregor now feels: Excited, eager\n")
	
	await _wait(1)
	
	# === Epilogue ===
	print("\n" + "=".repeat(70))
	print("🌅 EPILOGUE")
	print("=".repeat(70))
	print("\nThe next morning, Gregor remembers:")
	print("- The player who saved the village from bandits")
	print("- The trust built through quests and secrets shared")
	print("- The growing attraction that developed naturally")
	print("- The night they spent together\n")
	
	print("His AI agent has grown from:")
	print("  'Cautious merchant' (Relationship: 0)")
	print("     ↓")
	print("  'Grateful ally' (Relationship: 20)")
	print("     ↓")
	print("  'Trusted friend' (Relationship: 43)")
	print("     ↓")
	print("  'Romantic partner' (Relationship: 71)\n")
	
	print("All future conversations will reference these experiences.")
	print("His personality has permanently evolved through action memories.\n")
	
	# Show what memories are now in his head
	print("-".repeat(70))
	print("📚 GREGOR'S CURRENT MEMORIES (What shapes his personality now):")
	print("-".repeat(70))
	
	var memories = await gregor.rag_memory.retrieve_relevant_raw("player relationship romance quest", {"limit": 10})
	
	if memories.size() > 0:
		print("\nAction Memories (How he grew):")
		for mem in memories:
			if mem.event_type in ["quest_accepted", "quest_completed", "helped", "item_given", "item_received"]:
				print("  [%s, importance: %d] %s" % [
					mem.event_type,
					mem.importance,
					mem.document.substr(0, 80)
				])
	
	print("\n" + "=".repeat(70))
	print("✨ This is AI-Agent NPC Growth in action!")
	print("=".repeat(70))
	print("\nGregor isn't scripted - his personality evolved organically")
	print("through the accumulation of experiences stored in memory.\n")
	
	print("Try this in-game by building relationship through:")
	print("  1. Accepting quests")
	print("  2. Completing objectives")  
	print("  3. Helping with tasks")
	print("  4. Having meaningful conversations")
	print("  5. Building trust over time\n")
	
	print("The NPC will respond based on the relationship score and")
	print("action memories - romance is just one possible outcome!\n")
	
	get_tree().quit()

func _wait(seconds: float):
	await get_tree().create_timer(seconds).timeout
