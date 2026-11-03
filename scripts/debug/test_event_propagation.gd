extends SceneTree

# Tests EventPropagator: witnesses, gossip, pending delivery, dedup, save/load
# Run: godot --headless --path . -s res://scripts/debug/test_event_propagation.gd

class FakeMemory extends Node:
	var stored: Array = []
	func store(data: Dictionary, _custom_id: String = "", _skip_validation: bool = false) -> bool:
		stored.append(data)
		return true

class FakeNPC extends Node2D:
	var npc_id: String = ""
	var is_alive: bool = true
	var _is_initialized: bool = true
	var rag_memory: Node
	var location: String = ""
	func get_current_location() -> String:
		return location

var propagator: Node
var failures: int = 0
var npcs: Array = []

func _init():
	await process_frame
	propagator = root.get_node("EventPropagator")

	print("============================================================")
	print("🧪 EVENT PROPAGATION TEST")
	print("============================================================\n")

	_test_witness_only_present_npcs()
	_test_no_duplicate_memories()
	_test_gossip_queues_for_unloaded_npc()
	_test_uninitialized_witness_gets_memory_later()
	_test_everyone_gossip()
	_test_save_load_roundtrip()
	await _test_flag_change_triggers_propagation()

	print("\n============================================================")
	print("✅ ALL TESTS PASSED" if failures == 0 else "❌ %d CHECK(S) FAILED" % failures)
	print("============================================================")
	quit(0 if failures == 0 else 1)

# =============================================================================
# TESTS
# =============================================================================

func _test_witness_only_present_npcs():
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	var elena = _spawn("elena_daughter_001", "thornhaven_town_square")
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	_check("Gregor witnessed the ledger discovery", gregor.rag_memory.stored.size() == 1)
	_check("Elena (elsewhere) did not", elena.rag_memory.stored.is_empty())
	var memory = gregor.rag_memory.stored[0] if not gregor.rag_memory.stored.is_empty() else {}
	_check("Implicated witness gets importance 9 / afraid", memory.get("importance") == 9 and memory.get("emotion") == "afraid")
	_check("Memory text is the canonical description", str(memory.get("text", "")) == "I witnessed: " + StoryFlags.get_flag_description("ledger_found"))
	_check("Secret flag does not spread as gossip", propagator.get_pending_count() == 0)

func _test_no_duplicate_memories():
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	_check("Repeated flag stores one memory", gregor.rag_memory.stored.size() == 1)

func _test_gossip_queues_for_unloaded_npc():
	_reset()
	propagator.spread_gossip("varn_confronted")
	_check("News for unloaded Mira is queued", propagator.get_pending_count("mira") == 1)
	var mira = _spawn("mira_tavern_keeper_001", "thornhaven_tavern")
	propagator.deliver_pending(mira)
	_check("Mira receives it when she loads", mira.rag_memory.stored.size() == 1)
	_check("Gossip says how she heard", "bandit runner" in str(mira.rag_memory.stored[0].get("text", "")) if not mira.rag_memory.stored.is_empty() else false)
	_check("Queue is cleared", propagator.get_pending_count("mira") == 0)

func _test_uninitialized_witness_gets_memory_later():
	_reset()
	var bjorn = _spawn("bjorn_blacksmith_001", "thornhaven_blacksmith")
	bjorn._is_initialized = false
	propagator.propagate_flag("bulk_orders_found", "thornhaven_blacksmith")
	_check("Uninitialized Bjorn has nothing stored yet", bjorn.rag_memory.stored.is_empty())
	_check("His memory is queued", propagator.get_pending_count("bjorn") == 1)
	bjorn._is_initialized = true
	propagator.deliver_pending(bjorn)
	_check("Bjorn gets the witnessed memory after initialize", bjorn.rag_memory.stored.size() == 1)
	_check("Non-implicated witness gets importance 7", bjorn.rag_memory.stored[0].get("importance") == 7 if not bjorn.rag_memory.stored.is_empty() else false)

func _test_everyone_gossip():
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	var elena = _spawn("elena_daughter_001", "thornhaven_town_square")
	propagator.spread_gossip("gregor_exposed")
	_check("Loaded NPCs hear public news", gregor.rag_memory.stored.size() == 1 and elena.rag_memory.stored.size() == 1)
	var others = propagator.get_star_keys("western_valley").size() - 2
	_check("The other %d valley NPCs have it queued" % others, others >= 5 and propagator.get_pending_count() == others)
	_check("Gregor hears his own exposure with fear", gregor.rag_memory.stored[0].get("emotion") == "afraid" if not gregor.rag_memory.stored.is_empty() else false)

func _test_save_load_roundtrip():
	_reset()
	var gregor = _spawn("gregor_merchant_001", "thornhaven_gregor_shop")
	propagator.propagate_flag("ledger_found", "thornhaven_gregor_shop")
	propagator.spread_gossip("varn_confronted")
	var saved = JSON.parse_string(JSON.stringify(propagator.save()))
	propagator.load_from_dict({})
	_check("Reset clears state", propagator.get_pending_count() == 0 and not propagator.has_delivered(gregor.npc_id, "ledger_found"))
	propagator.load_from_dict(saved)
	_check("Delivered set survives a JSON save", propagator.has_delivered(gregor.npc_id, "ledger_found"))
	_check("Pending queue survives a JSON save", propagator.get_pending_count("mira") == 1)

func _test_flag_change_triggers_propagation():
	_reset()
	var world_state = root.get_node("WorldState")
	var original = world_state.get_world_flag("elena_shown_proof")
	world_state.world_flags["elena_shown_proof"] = false
	var elena = _spawn("elena_daughter_001", "")
	world_state.set_world_flag("elena_shown_proof", true)
	await process_frame
	_check("WorldState.set_world_flag reaches witnesses via EventBus", elena.rag_memory.stored.size() == 1)
	world_state.world_flags["elena_shown_proof"] = original

# =============================================================================
# HELPERS
# =============================================================================

func _spawn(npc_id: String, location: String) -> FakeNPC:
	var npc = FakeNPC.new()
	npc.npc_id = npc_id
	npc.location = location
	npc.rag_memory = FakeMemory.new()
	npc.add_child(npc.rag_memory)
	npc.add_to_group("npcs")
	root.add_child(npc)
	npcs.append(npc)
	return npc

func _reset():
	for npc in npcs:
		npc.remove_from_group("npcs")
		npc.queue_free()
	npcs.clear()
	propagator.load_from_dict({})

func _check(label: String, passed: bool):
	print("  %s %s" % ["✓" if passed else "✗", label])
	if not passed:
		failures += 1
