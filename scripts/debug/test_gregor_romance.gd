extends SceneTree

# Tests an NPC growing from stranger to romance through action memories (Gregor, structured personality),
# in in-memory mode: nine recorded actions raise trust and affection past Gregor's romance thresholds,
# every action is remembered, and raw recall returns them with their event types
# Fakes only: no API calls, no ChromaDB, no save file written
# Run: godot --headless --path . -s res://scripts/debug/test_gregor_romance.gd

const Support = preload("res://scripts/debug/legacy_test_support.gd")
const ACTS = [
	["quest_accepted", "The player agreed to help me deal with the bandits raiding our supply wagons.", 9, "hopeful"],
	["quest_completed", "The player defeated the bandits and got them arrested. Our supply wagons are safe now.", 10, "grateful"],
	["helped", "The player carried crates to my shop and refused any coin for it.", 7, "warm"],
	["shared_secret", "I told the player about the bandit informant. I trust them enough to share this.", 9, "trusting"],
	["shared_danger", "The player stood with me when the bandits came back for revenge.", 10, "bonded"],
	["emotional_support", "The player listened to my worries about my daughter without judging.", 8, "vulnerable"],
	["gift_received", "The player brought a book about horses for my daughter. They remembered she loves horses.", 9, "touched"],
	["shared_secret", "We talked late into the evening. I told them things I have told no one.", 8, "attracted"],
	["protected", "The player stepped between me and a drunk with a knife at the tavern.", 10, "safe"],
]

var failures: int = 0

func _init():
	await process_frame
	await process_frame
	Support.start_watchdog(self, "GREGOR ROMANCE GROWTH TEST")
	Support.guard_save(self)
	print("============================================================")
	print("🧪 GREGOR ROMANCE GROWTH TEST")
	print("============================================================\n")
	var personality = load("res://resources/npc_personalities/gregor_merchant.tres")
	var gregor = load("res://scripts/npcs/base_npc.gd").new()
	gregor.npc_name = "Gregor"
	gregor.personality_resource = personality
	root.add_child(gregor)
	_check("Gregor initializes in-memory from his personality resource", await gregor.initialize(false))
	_check("His system prompt comes from the resource", gregor.system_prompt.length() > 100 and "Gregor" in gregor.system_prompt)
	_check("Romance starts locked", not personality.is_romance_unlocked(gregor.relationship_trust, gregor.relationship_affection, gregor.relationship_familiarity))

	var last_affection = gregor.relationship_affection
	var all_rose = true
	for act in ACTS:
		await gregor.record_player_action(act[0], act[1], act[2], act[3])
		all_rose = all_rose and gregor.relationship_affection >= last_affection
		last_affection = gregor.relationship_affection
	_check("Affection never falls across positive acts", all_rose)
	_check("Trust, affection and familiarity end high", gregor.relationship_trust >= 50 and gregor.relationship_affection >= 60 and gregor.relationship_familiarity >= 40)
	_check("Romance unlocks", personality.is_romance_unlocked(gregor.relationship_trust, gregor.relationship_affection, gregor.relationship_familiarity))
	_check("Every act is remembered", gregor.rag_memory.memory_cache.size() == ACTS.size())

	var recalled = await gregor.rag_memory.retrieve_relevant_raw("player bandits daughter secret", {"limit": 10})
	_check("Raw recall returns the acts", recalled.size() == ACTS.size())
	_check("Raw recall carries event types", recalled.all(func(m): return m.event_type in ACTS.map(func(a): return a[0])))
	print("\n  Final: trust %d, affection %d, familiarity %d, fear %d" % [gregor.relationship_trust, gregor.relationship_affection, gregor.relationship_familiarity, gregor.relationship_fear])

	gregor.queue_free()
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
