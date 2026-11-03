extends SceneTree

# Tests BaseNPC.record_interaction evolving the five relationship dimensions over four interactions
# (quest, thoughtful gift, emotional support, shared danger) in in-memory mode:
# dimensions move the right way, each interaction is remembered with its impacts, EventBus hears each change,
# and the prompt Claude would see changes from stranger to friend
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_dimension_evolution.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")

var failures: int = 0
var changes: Array = []

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "DIMENSION EVOLUTION TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 DIMENSION EVOLUTION TEST")
	print("============================================================\n")
	root.get_node("EventBus").npc_relationship_changed.connect(func(data): if data.get("npc_id") == "test_gregor_dimensions": changes.append(data))
	var npc = load("res://scripts/npcs/base_npc.gd").new()
	npc.npc_id = "test_gregor_dimensions"
	npc.npc_name = "Gregor"
	npc.system_prompt = "You are Gregor, a cautious merchant. You're professional but guarded with strangers."
	root.add_child(npc)
	_check("NPC initializes in-memory", await npc.initialize(false))
	var stranger_prompt = _prompt(npc)

	await npc.record_interaction("quest_completed", {"description": "Player defeated bandits raiding my supply wagons.", "importance": 10, "emotion": "grateful"})
	_check("Quest: trust, respect and affection rise", npc.relationship_trust > 0 and npc.relationship_respect > 0 and npc.relationship_affection > 0)
	_check("Quest: a stranger's trust gain is dampened (15 x 0.7 = 10)", int(npc.relationship_trust) == 10)
	var after_quest = npc.relationship_affection
	await npc.record_interaction("gift_received", {"description": "Player gave me a rare book about horses for Elena.", "importance": 9, "emotion": "deeply_touched", "thoughtfulness": "high"})
	_check("Thoughtful gift: affection +15", int(npc.relationship_affection - after_quest) == 15)
	await npc.record_interaction("emotional_support", {"description": "Player listened to my worries about Elena.", "importance": 8, "emotion": "vulnerable"})
	await npc.record_interaction("shared_danger", {"description": "Player fought alongside me when bandits attacked.", "importance": 10, "emotion": "bonded"})
	_check("Shared danger: fear drops below zero", npc.relationship_fear < 0)
	_check("Familiarity sums 5 + 10 + 5 + 15 = 35", int(npc.relationship_familiarity) == 35)
	_check("All dimensions stay in range", abs(npc.relationship_trust) <= 100 and abs(npc.relationship_affection) <= 100 and npc.relationship_familiarity >= 0)
	_check("Legacy status follows the dimensions", npc.relationship_status > 0)

	var cache: Array = npc.rag_memory.memory_cache
	_check("Each interaction is remembered", cache.size() == 4)
	_check("Memories carry their impacts", cache.size() == 4 and cache[3].metadata.get("impact_fear") == -10 and cache[3].metadata.get("event_type") == "shared_danger")
	_check("EventBus heard 4 relationship changes", changes.size() == 4)
	_check("The last change reports the new dimensions", changes.size() == 4 and is_equal_approx(changes[3].new_dimensions.familiarity, npc.relationship_familiarity))

	var friend_prompt = _prompt(npc)
	_check("The prompt changes from stranger to friend", friend_prompt != stranger_prompt)
	_check("The stranger was treated formally, the friend is not", "Formal, asking basic questions" in stranger_prompt and not "Formal, asking basic questions" in friend_prompt)

	npc.queue_free()
	await process_frame
	_finish()

func _prompt(npc) -> String:
	return npc.context_builder.build_context({
		"system_prompt": npc.system_prompt,
		"relationship_dimensions": {"trust": npc.relationship_trust, "respect": npc.relationship_respect, "affection": npc.relationship_affection, "fear": npc.relationship_fear, "familiarity": npc.relationship_familiarity},
		"player_input": "Hello"
	}).system_prompt

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1

func _finish():
	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)
