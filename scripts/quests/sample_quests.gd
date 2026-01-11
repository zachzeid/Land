extends Node
## Sample quests for testing the quest system
## Registers test quests programmatically when loaded

const QuestResourceScript = preload("res://scripts/quests/quest_resource.gd")
const QuestObjectiveScript = preload("res://scripts/quests/quest_objective.gd")

func _ready():
	# Wait a frame to ensure QuestManager is initialized
	await get_tree().process_frame
	_register_sample_quests()

func _register_sample_quests():
	print("[SampleQuests] Registering sample quests for testing...")

	# Quest 1: Gregor's Conspiracy
	_create_gregor_conspiracy_quest()

	# Quest 2: Elena's Request
	_create_elena_request_quest()

	print("[SampleQuests] Sample quests registered")

func _create_gregor_conspiracy_quest():
	var quest = QuestResourceScript.new()
	quest.quest_id = "gregor_conspiracy"
	quest.title = "Whispers of Conspiracy"
	quest.description = "The merchant Gregor seems to know something about secret dealings in town. Perhaps gaining his trust will reveal more."
	quest.story_arc = "main_conspiracy"
	quest.is_main_quest = true
	quest.priority = 100

	# Discovery conditions - quest becomes available when talking to Gregor about secrets
	# Use typed arrays
	quest.discovery_intents.append_array(["revelation", "confession", "secret_shared"])
	quest.discovery_topics.append_array(["conspiracy", "ledger", "secret dealings"])
	quest.discovery_npc = "gregor_001"

	# Availability - always available from start (no flags needed)

	# Objectives
	var obj1 = QuestObjectiveScript.new()
	obj1.objective_id = "gain_gregor_trust"
	obj1.description = "Earn Gregor's trust through conversation"
	obj1.complete_on_relationship = {"gregor_001": 60.0}
	obj1.order = 1
	quest.objectives.append(obj1)

	var obj2 = QuestObjectiveScript.new()
	obj2.objective_id = "learn_about_ledger"
	obj2.description = "Learn about the mysterious ledger"
	obj2.complete_on_topics.append("ledger")
	obj2.requires_npc = "gregor_001"
	obj2.order = 2
	quest.objectives.append(obj2)

	var obj3 = QuestObjectiveScript.new()
	obj3.objective_id = "discover_conspiracy"
	obj3.description = "Uncover the conspiracy"
	obj3.complete_on_intent = "revelation"
	obj3.requires_npc = "gregor_001"
	obj3.order = 3
	quest.objectives.append(obj3)

	# Context hints for NPCs when quest is active
	quest.npc_context_hints = {
		"gregor_001": "The player is investigating rumors of conspiracy. If trust is high enough, you might share what you know about the ledger and secret dealings.",
		"elena_001": "You've heard whispers that your father knows something dangerous. You're worried about him."
	}
	quest.global_context_hint = "Tensions are high in town. People speak in hushed tones about secrets."

	# Completion - use append for typed arrays
	quest.completion_flags.append("gregor_conspiracy_revealed")
	quest.unlocks_quests.append("iron_hollow_investigation")
	quest.possible_endings = {
		"full_truth": "Gregor revealed everything about the conspiracy",
		"partial_truth": "Gregor shared some information but held back",
		"refused": "Gregor refused to share his secrets"
	}

	QuestManager.register_quest(quest)
	print("[SampleQuests] Registered quest: %s" % quest.quest_id)

func _create_elena_request_quest():
	var quest = QuestResourceScript.new()
	quest.quest_id = "elena_request"
	quest.title = "Elena's Request"
	quest.description = "Elena is worried about her father Gregor. He's been acting strange lately - secretive meetings, nervous behavior. She wants you to find out what's troubling him."
	quest.story_arc = "elena_storyline"
	quest.is_main_quest = false
	quest.priority = 50

	# Discovery - quest starts when Elena asks for help
	quest.discovery_intents.append_array(["request", "plea", "concern"])
	quest.discovery_topics.append_array(["father", "gregor", "worried", "help"])
	quest.discovery_npc = "elena_daughter_001"

	# Availability - always available from start
	# No blocking flags needed

	# Objectives
	var obj1 = QuestObjectiveScript.new()
	obj1.objective_id = "gain_elena_trust"
	obj1.description = "Earn Elena's trust"
	obj1.complete_on_relationship = {"elena_daughter_001": 40.0}
	obj1.order = 1
	quest.objectives.append(obj1)

	var obj2 = QuestObjectiveScript.new()
	obj2.objective_id = "learn_about_gregor"
	obj2.description = "Learn about Gregor's troubles"
	obj2.complete_on_topics.append_array(["gregor", "secret", "meetings"])
	obj2.requires_npc = "elena_daughter_001"
	obj2.order = 2
	quest.objectives.append(obj2)

	var obj3 = QuestObjectiveScript.new()
	obj3.objective_id = "investigate_gregor"
	obj3.description = "Speak with Gregor about his daughter's concerns"
	obj3.complete_on_topics.append_array(["elena", "daughter", "worried"])
	obj3.requires_npc = "gregor_merchant_001"
	obj3.order = 3
	quest.objectives.append(obj3)

	var obj4 = QuestObjectiveScript.new()
	obj4.objective_id = "report_to_elena"
	obj4.description = "Tell Elena what you've learned"
	obj4.complete_on_intent = "revelation"
	obj4.requires_npc = "elena_daughter_001"
	obj4.order = 4
	quest.objectives.append(obj4)

	# Context hints
	quest.npc_context_hints = {
		"elena_daughter_001": "You're deeply worried about your father. He's been distant, having secret meetings at night. You suspect something is wrong but he won't tell you anything.",
		"gregor_merchant_001": "Your daughter Elena has been asking questions. You want to protect her from the truth about the bandits, but your secrecy is hurting her.",
		"mira_001": "You've noticed Elena looking troubled lately. Poor girl - she doesn't know what her father is mixed up in."
	}

	# Completion
	quest.completion_flags.append("elena_informed")
	quest.possible_endings = {
		"truth_revealed": "Elena learned the truth about her father's situation",
		"protected": "You kept the dangerous truth from Elena to protect her",
		"partial_truth": "Elena learned something is wrong, but not the full story"
	}

	QuestManager.register_quest(quest)
	print("[SampleQuests] Registered quest: %s" % quest.quest_id)
