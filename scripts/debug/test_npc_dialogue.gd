extends SceneTree

# Tests the NPC dialogue pipeline up to (not including) Claude, in in-memory mode:
# BaseNPC → RAGMemory tiers (pinned / important / regular) → retrieve_tiered → format_tiered_memories
# → ContextBuilder prompt sections (DEFINING MOMENTS, Significant Memories, relevant)
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_npc_dialogue.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "NPC DIALOGUE PIPELINE TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 NPC DIALOGUE PIPELINE TEST")
	print("============================================================\n")
	var npc = CharacterBody2D.new()
	npc.set_script(load("res://scripts/npcs/base_npc.gd"))
	npc.npc_id = "test_npc_001"
	npc.npc_name = "Test Merchant"
	root.add_child(npc)
	_check("NPC initializes in-memory, no KPI", await npc.initialize(false, false))
	var rag = npc.rag_memory

	_check("Pinned memory stored", await rag.store({"text": "I met the player for the first time. They seemed friendly.", "event_type": "first_meeting", "importance": 10, "emotion": "curious", "memory_tier": 0, "is_milestone": true}))
	_check("Important memory stored", await rag.store({"text": "The player helped me retrieve stolen goods from bandits.", "event_type": "quest_completed", "importance": 8, "emotion": "grateful", "memory_tier": 1}))
	_check("Regular memory stored", await rag.store({"text": "We discussed the weather and local rumors.", "event_type": "conversation", "importance": 5, "emotion": "neutral", "memory_tier": 2}))

	var tiered = await rag.retrieve_tiered("bandits quest")
	_check("One pinned memory", tiered.pinned.size() == 1 and "first time" in tiered.pinned[0].get("document", ""))
	_check("One important memory", tiered.important.size() == 1 and "stolen goods" in tiered.important[0].get("document", ""))
	_check("The regular memory is relevant, not repeated", tiered.relevant.size() == 1 and "weather" in tiered.relevant[0].get("document", ""))
	_check("Characters are counted against the budget", tiered.total_chars > 0)

	var formatted = rag.format_tiered_memories(tiered)
	_check("Pinned formatted as a MILESTONE", formatted.pinned.size() == 1 and formatted.pinned[0].begins_with("[MILESTONE - first_meeting"))
	_check("Important formatted as IMPORTANT", formatted.important.size() == 1 and formatted.important[0].begins_with("[IMPORTANT - quest_completed"))

	var context = npc.context_builder.build_context({
		"system_prompt": "You are a friendly merchant named Test.",
		"npc_id": npc.npc_id,
		"tiered_memories": formatted,
		"relationship_dimensions": {"trust": 30, "respect": 0, "affection": 20, "fear": 0, "familiarity": 40},
		"world_state": {},
		"conversation_history": [],
		"player_input": "Hello there!"
	})
	var prompt: String = context.system_prompt
	_check("Prompt has DEFINING MOMENTS with the pinned memory", "## DEFINING MOMENTS" in prompt and "first time" in prompt)
	_check("Prompt has Significant Memories with the important one", "## Significant Memories" in prompt and "stolen goods" in prompt)
	_check("Prompt has the relevant memory", "## Recent & Relevant Memories" in prompt and "weather" in prompt)
	_check("Defining moments come before significant memories", prompt.find("## DEFINING MOMENTS") < prompt.find("## Significant Memories"))
	_check("One message: the player's input", context.messages.size() == 1 and context.messages[0].content == "Hello there!")

	var empty = npc.context_builder.build_context({"system_prompt": "x", "relationship_dimensions": {"trust": 1}, "player_input": "Hi"}).system_prompt
	_check("No memories: says so", "You have no significant memories of this person yet." in empty)

	npc.queue_free()
	await process_frame
	_finish()

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
