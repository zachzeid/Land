extends Node
## SecretSeeds - Seeds the gossip system with initial NPC knowledge
##
## At game start, each NPC knows certain things. These become InfoPackets
## in the GossipManager that can spread through the social network.
## This bridges the NPCPersonality secret system with the gossip engine.

func _ready():
	# Wait for other systems to initialize
	await get_tree().create_timer(3.0).timeout
	_seed_initial_knowledge()

func _seed_initial_knowledge():
	var gossip = get_node_or_null("/root/GossipManager")
	if gossip == null:
		push_warning("[SecretSeeds] GossipManager not found — skipping secret seeding")
		return

	print("[SecretSeeds] Seeding initial NPC knowledge into gossip system...")

	# === MIRA'S KNOWLEDGE (she knows the most — she's The Boss) ===
	# Public knowledge (she shares freely)
	gossip.create_info(
		"Bandits have been getting bolder on the northern trade route",
		"mira_tavern_keeper_001", "fact", 0.9,
		["bandits"], ["bandits", "trade_route"])

	gossip.create_info(
		"Business has been slow at the tavern lately. Fewer travelers stopping through.",
		"mira_tavern_keeper_001", "gossip", 0.8,
		[], ["tavern", "economy"])

	# Mira's secrets (restricted — only shares with high trust)
	gossip.create_secret(
		"Marcus was executed by bandits, not killed in a robbery",
		"mira_tavern_keeper_001", [],
		["marcus_death_learned"])

	gossip.create_secret(
		"Gregor meets with bandits at the old mill. He's the village informant.",
		"mira_tavern_keeper_001", [],
		["gregor_bandit_meeting_known"])

	gossip.create_secret(
		"Varn — the bandit lieutenant — personally killed Marcus. I saw his face.",
		"mira_tavern_keeper_001", [],
		["varn_killed_marcus_known"])

	# === GREGOR'S KNOWLEDGE ===
	gossip.create_info(
		"Trade has been good for my shop. Supplies keep flowing.",
		"gregor_merchant_001", "gossip", 0.7,
		[], ["trade", "gregor"])

	gossip.create_secret(
		"I've been saving gold for Elena to leave Thornhaven. Enough to start a new life.",
		"gregor_merchant_001", ["elena_daughter_001"],
		["gregor_gold_secret_revealed"])

	gossip.create_secret(
		"The weapons I order from Bjorn go to the bandits. I told him travelers buy them.",
		"gregor_merchant_001", [],
		["weapons_traced_to_bjorn"])

	gossip.create_secret(
		"I made a deal with the Iron Hollow gang three years ago. Elena's safety for my cooperation.",
		"gregor_merchant_001", [],
		["gregor_confession_heard"])

	# === ELENA'S KNOWLEDGE ===
	gossip.create_info(
		"My father has been acting strange lately. Secret meetings, nervous behavior.",
		"elena_daughter_001", "gossip", 0.7,
		[], ["gregor", "elena", "suspicious"])

	gossip.create_secret(
		"I followed my father to the old mill one night. He met a hooded figure there.",
		"elena_daughter_001", [],
		["gregor_bandit_meeting_known"])

	# === ALDRIC'S KNOWLEDGE ===
	gossip.create_info(
		"The peacekeepers are stretched thin. We need more volunteers.",
		"aldric_peacekeeper_001", "fact", 0.9,
		[], ["peacekeepers", "defense"])

	gossip.create_secret(
		"I suspect Gregor is the informant. His prosperity while others suffer — it doesn't add up.",
		"aldric_peacekeeper_001", [],
		[])

	gossip.create_secret(
		"I've been gathering weapons in a cache under the old well. When the time comes, we'll be ready.",
		"aldric_peacekeeper_001", [],
		["aldric_has_evidence"])

	# === BJORN'S KNOWLEDGE ===
	gossip.create_info(
		"Gregor keeps ordering more weapons than a village this size needs. Good for business though.",
		"bjorn_blacksmith_001", "gossip", 0.6,
		[], ["weapons", "gregor"])

	# === MATHIAS'S KNOWLEDGE ===
	gossip.create_info(
		"I've written to the capital for help. No response for two years now.",
		"elder_mathias_001", "fact", 0.8,
		[], ["politics", "capital"])

	gossip.create_secret(
		"I've suspected Gregor for over a year. His father was an honest man. What happened?",
		"elder_mathias_001", [],
		[])

	print("[SecretSeeds] Seeded knowledge for 6 NPCs (%d total packets)" % gossip.all_packets.size())
