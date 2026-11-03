extends SceneTree

# Tests BaseNPC wiring its AI components in in-memory mode (no ChromaDB):
# initialize creates RAGMemory, ContextBuilder and ClaudeClient; memory storage; context building;
# conversation history (capped at 20 turns); legacy relationship clamping; topic and emotion helpers
# Fakes only: no API calls (ClaudeClient is created, never sent a message), no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_base_npc.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "BASE NPC TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 BASE NPC TEST")
	print("============================================================\n")
	var npc = load("res://scripts/npcs/base_npc.gd").new()
	npc.npc_id = "test_merchant_001"
	npc.npc_name = "Test Merchant"
	npc.system_prompt = "You are a cautious merchant who sells adventuring supplies. You're worried about bandits on the trade roads."
	root.add_child(npc)

	print("Initialization")
	_check("initialize(false) succeeds", await npc.initialize(false))
	_check("RAGMemory created, in-memory", npc.rag_memory != null and not npc.rag_memory.use_chromadb)
	_check("ContextBuilder created", npc.context_builder != null)
	_check("ClaudeClient created", npc.claude_client != null)
	_check("A second initialize is a no-op", await npc.initialize(false))

	print("\nMemory and context")
	_check("Memory stored", await npc.rag_memory.store({"text": "A traveler asked about sword prices. I quoted 50 gold.", "event_type": "conversation", "importance": 5, "emotion": "neutral"}))
	_check("Memory recalled", (await npc.rag_memory.retrieve_relevant("sword prices", {"min_importance": 0})).any(func(m): return "50 gold" in m))
	var context = npc.context_builder.build_context({"system_prompt": npc.system_prompt, "relationship_status": npc.relationship_status, "conversation_history": [], "player_input": "What weapons do you have?"})
	_check("Context has the NPC's prompt and the player's input", npc.system_prompt in context.system_prompt and context.messages[-1].content == "What weapons do you have?")

	print("\nConversation history")
	npc._add_to_history("user", "Hello, any news of the bandits?")
	npc._add_to_history("npc", "Greetings, traveler")
	_check("Two turns recorded", npc.current_conversation_history.size() == 2)
	_check("Topics extracted from the history", npc._extract_topics() == "bandits")
	for i in range(30):
		npc._add_to_history("user", "line %d" % i)
	_check("History is capped at 20 turns", npc.current_conversation_history.size() == 20 and npc.current_conversation_history[-1].message == "line 29")

	print("\nLegacy relationship")
	npc.adjust_relationship(15.0)
	_check("+15 -> 15", is_equal_approx(npc.relationship_status, 15.0))
	npc.adjust_relationship(-30.0)
	_check("-30 -> -15", is_equal_approx(npc.relationship_status, -15.0))
	_check("-15 reads as cautious", npc._infer_emotion() == "cautious")
	npc.adjust_relationship(200.0)
	_check("+200 clamps to 100", is_equal_approx(npc.relationship_status, 100.0))
	_check("100 reads as friendly", npc._infer_emotion() == "friendly")
	npc.adjust_relationship(-500.0)
	_check("-500 clamps to -100", is_equal_approx(npc.relationship_status, -100.0))
	await process_frame
	_check("Big swings are remembered", npc.rag_memory.memory_cache.filter(func(m): return m.metadata.event_type == "relationship_change").size() == 4)

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
