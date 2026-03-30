extends Node
class_name ThreadManager
## ThreadManager - Tracks story thread tensions and drives emergent narrative
##
## Story threads are ongoing narrative tensions driven by NPC goals.
## Each thread has a tension value (0.0-1.0) that rises through NPC actions,
## world events, and time passage. Threads escalate through states:
##   simmering (0.0-0.3) → escalating (0.3-0.6) → crisis (0.6-0.8) → breaking (0.8-1.0)
##
## When tension crosses thresholds, QuestEmergenceEngine creates quests.
## When tension reaches breaking point, NPCs take drastic action.

signal thread_state_changed(thread_id: String, old_state: String, new_state: String)
signal thread_tension_changed(thread_id: String, tension: float, reason: String)
signal thread_resolved(thread_id: String, resolution: String)

## All active story threads {thread_id: StoryThread data}
var threads: Dictionary = {}

## Tension state thresholds
const SIMMERING_MAX := 0.3
const ESCALATING_MAX := 0.6
const CRISIS_MAX := 0.8
# Above 0.8 = breaking point

## Passive tension rise per game-day (things get worse over time)
const PASSIVE_TENSION_RATE := 0.02

func _ready():
	# Listen for flag changes (primary tension driver)
	EventBus.world_flag_changed.connect(_on_flag_changed)

	# Listen for NPC actions (agent loop output)
	if EventBus.has_signal("npc_action_taken"):
		EventBus.npc_action_taken.connect(_on_npc_action)

	# Listen for relationship changes
	EventBus.npc_relationship_changed.connect(_on_relationship_changed)

	# Listen for new days (passive tension rise)
	var game_clock = get_node_or_null("/root/GameClock")
	if game_clock:
		game_clock.new_day.connect(_on_new_day)

	# Register core threads
	_register_core_threads()

	print("[ThreadManager] Initialized with %d threads" % threads.size())

## Register a story thread
func register_thread(data: Dictionary):
	var id = data.get("id", "")
	if id == "":
		push_error("[ThreadManager] Thread missing 'id'")
		return

	threads[id] = {
		"id": id,
		"name": data.get("name", id),
		"description": data.get("description", ""),
		"driving_npcs": data.get("driving_npcs", []),
		"tension": data.get("tension", 0.1),
		"state": "simmering",
		"key_flags": data.get("key_flags", []),
		"intersects_with": data.get("intersects_with", []),
		"passive_rise": data.get("passive_rise", true),
		"resolved": false,
		"resolution": "",
	}

## Get current tension of a thread
func get_tension(thread_id: String) -> float:
	if thread_id in threads:
		return threads[thread_id].tension
	return 0.0

## Get current state of a thread
func get_state(thread_id: String) -> String:
	if thread_id in threads:
		return threads[thread_id].state
	return "unknown"

## Manually adjust tension (from quests, NPC actions, or external events)
func adjust_tension(thread_id: String, delta: float, reason: String = ""):
	if thread_id not in threads:
		return

	var thread = threads[thread_id]
	if thread.resolved:
		return

	var old_tension = thread.tension
	thread.tension = clampf(thread.tension + delta, 0.0, 1.0)

	if thread.tension != old_tension:
		thread_tension_changed.emit(thread_id, thread.tension, reason)
		_update_thread_state(thread_id)

## Resolve a thread (narrative conclusion reached)
func resolve_thread(thread_id: String, resolution: String):
	if thread_id not in threads:
		return

	threads[thread_id].resolved = true
	threads[thread_id].resolution = resolution
	threads[thread_id].tension = 0.0
	thread_resolved.emit(thread_id, resolution)
	print("[ThreadManager] Thread '%s' resolved: %s" % [thread_id, resolution])

## Get all threads in a specific state
func get_threads_in_state(state: String) -> Array:
	return threads.values().filter(func(t): return t.state == state and not t.resolved)

## Get all active (unresolved) threads
func get_active_threads() -> Array:
	return threads.values().filter(func(t): return not t.resolved)

## Update thread state based on tension thresholds
func _update_thread_state(thread_id: String):
	var thread = threads[thread_id]
	var old_state = thread.state

	if thread.tension <= SIMMERING_MAX:
		thread.state = "simmering"
	elif thread.tension <= ESCALATING_MAX:
		thread.state = "escalating"
	elif thread.tension <= CRISIS_MAX:
		thread.state = "crisis"
	else:
		thread.state = "breaking"

	if old_state != thread.state:
		thread_state_changed.emit(thread_id, old_state, thread.state)
		print("[ThreadManager] Thread '%s' changed: %s → %s (tension: %.2f)" % [
			thread.name, old_state, thread.state, thread.tension])

## Handle world flag changes → update thread tensions
func _on_flag_changed(flag_name: String, _old_value, new_value):
	if not new_value:
		return  # Only react to flags being set (not unset)

	# Map flags to thread tension changes
	var flag_impacts: Dictionary = {
		# Thread 1: Merchant's Bargain
		"ledger_found": {"merchants_bargain": 0.20, "daughters_awakening": 0.10, "failing_watch": 0.10},
		"gregor_bandit_meeting_known": {"merchants_bargain": 0.25, "daughters_awakening": 0.15},
		"gregor_confession_heard": {"merchants_bargain": 0.30, "daughters_awakening": 0.20},
		"gregor_confronted": {"merchants_bargain": 0.25, "grieving_widow": 0.10, "failing_watch": 0.10},
		"gregor_exposed": {"merchants_bargain": 0.30, "failing_watch": 0.20},
		"gregor_redemption_path": {"merchants_bargain": -0.15},  # Tension reduces if redemption
		# Thread 2: Grieving Widow
		"marcus_death_learned": {"grieving_widow": 0.15},
		"mira_testimony_given": {"grieving_widow": 0.20, "merchants_bargain": 0.10},
		"mira_trusts_player": {"grieving_widow": 0.10},
		"mira_boss_revealed": {"grieving_widow": 0.40, "bandit_expansion": 0.20},
		# Thread 3: Daughter's Awakening
		"elena_knows_about_father": {"daughters_awakening": 0.30, "merchants_bargain": 0.15},
		"elena_shown_proof": {"daughters_awakening": 0.25},
		"elena_romance_started": {"daughters_awakening": 0.05},
		# Thread 4: Failing Watch
		"aldric_has_evidence": {"failing_watch": 0.20},
		"aldric_ally": {"failing_watch": 0.15},
		"resistance_forming": {"failing_watch": 0.25, "bandit_expansion": 0.15},
		# Thread 5: Unwitting Accomplice (Bjorn)
		"weapons_traced_to_bjorn": {"unwitting_accomplice": 0.25, "merchants_bargain": 0.10},
		"bjorn_truth_revealed": {"unwitting_accomplice": 0.30, "failing_watch": 0.10},
		"bjorn_allied": {"unwitting_accomplice": -0.10, "failing_watch": 0.10},
		# Thread 6: Paralyzed Council
		"mathias_informed": {"paralyzed_council": 0.20, "failing_watch": 0.10},
		# Thread 7: Bandit Expansion
		"varn_confronted": {"bandit_expansion": 0.15},
		"iron_hollow_visited": {"bandit_expansion": 0.10},
	}

	if flag_name in flag_impacts:
		var impacts = flag_impacts[flag_name]
		for thread_id in impacts:
			if thread_id in threads:
				adjust_tension(thread_id, impacts[thread_id],
					"Flag '%s' set" % flag_name)

## Handle NPC actions → update thread tensions
func _on_npc_action(npc_id: String, action_data: Dictionary):
	# NPC actions from the agent loop affect thread tensions
	var action_type = action_data.get("type", "")

	# Any NPC action slightly raises tension of their associated threads
	for thread_id in threads:
		var thread = threads[thread_id]
		if npc_id in thread.driving_npcs:
			adjust_tension(thread_id, 0.02, "%s took action: %s" % [npc_id, action_type])

## Handle relationship changes → update relevant threads
func _on_relationship_changed(event_data: Dictionary):
	var npc_id = event_data.get("npc_id", "")
	var trust_change = event_data.get("impacts", {}).get("trust", 0)

	# Building trust with key NPCs affects their threads
	if npc_id == "gregor_merchant_001" and trust_change > 5:
		adjust_tension("merchants_bargain", 0.05, "Player building trust with Gregor")
	if npc_id == "elena_daughter_001" and trust_change > 5:
		adjust_tension("daughters_awakening", 0.05, "Player building trust with Elena")
	if npc_id == "mira_tavern_keeper_001" and trust_change > 5:
		adjust_tension("grieving_widow", 0.05, "Player building trust with Mira")
	if npc_id == "aldric_peacekeeper_001" and trust_change > 5:
		adjust_tension("failing_watch", 0.05, "Player building trust with Aldric")

## Passive tension rise each game-day
func _on_new_day(day_number: int):
	for thread_id in threads:
		var thread = threads[thread_id]
		if thread.resolved or not thread.passive_rise:
			continue
		adjust_tension(thread_id, PASSIVE_TENSION_RATE,
			"Day %d — situation worsens" % day_number)

## Debug: print all thread states
func debug_print_threads():
	print("[ThreadManager] === Active Story Threads ===")
	for thread_id in threads:
		var t = threads[thread_id]
		var bar = "█".repeat(int(t.tension * 20)) + "░".repeat(20 - int(t.tension * 20))
		print("  [%s] %s |%s| %.2f (%s)%s" % [
			thread_id, t.name, bar, t.tension, t.state,
			" [RESOLVED: %s]" % t.resolution if t.resolved else ""])

# =============================================================================
# CORE STORY THREADS
# =============================================================================

func _register_core_threads():
	register_thread({
		"id": "merchants_bargain",
		"name": "The Merchant's Bargain",
		"description": "Gregor's deal with the bandits — weapons and intelligence for Elena's safety",
		"driving_npcs": ["gregor_merchant_001", "varn_bandit_001"],
		"tension": 0.10,
		"key_flags": ["ledger_found", "gregor_bandit_meeting_known", "gregor_confession_heard",
					   "gregor_confronted", "gregor_exposed", "gregor_redemption_path"],
		"intersects_with": ["daughters_awakening", "unwitting_accomplice", "failing_watch"],
	})

	register_thread({
		"id": "grieving_widow",
		"name": "The Grieving Widow",
		"description": "Mira knows Gregor is the informant but is 'too afraid' to speak. In truth, she is The Boss.",
		"driving_npcs": ["mira_tavern_keeper_001"],
		"tension": 0.08,
		"key_flags": ["marcus_death_learned", "mira_testimony_given", "mira_trusts_player", "mira_boss_revealed"],
		"intersects_with": ["merchants_bargain", "bandit_expansion"],
	})

	register_thread({
		"id": "daughters_awakening",
		"name": "The Daughter's Awakening",
		"description": "Elena suspects her father but can't face it. Caught between loyalty and truth.",
		"driving_npcs": ["elena_daughter_001"],
		"tension": 0.05,
		"key_flags": ["elena_knows_about_father", "elena_shown_proof", "elena_romance_started"],
		"intersects_with": ["merchants_bargain"],
	})

	register_thread({
		"id": "failing_watch",
		"name": "The Failing Watch",
		"description": "Aldric has weapons, patrol routes, and a plan — but lacks proof, authorization, and numbers.",
		"driving_npcs": ["aldric_peacekeeper_001"],
		"tension": 0.12,
		"key_flags": ["aldric_has_evidence", "aldric_ally", "resistance_forming"],
		"intersects_with": ["merchants_bargain", "paralyzed_council"],
	})

	register_thread({
		"id": "unwitting_accomplice",
		"name": "The Unwitting Accomplice",
		"description": "Bjorn's weapons bear his mark. They're being used against the people he cares about.",
		"driving_npcs": ["bjorn_blacksmith_001"],
		"tension": 0.05,
		"key_flags": ["weapons_traced_to_bjorn", "bjorn_truth_revealed", "bjorn_allied"],
		"intersects_with": ["merchants_bargain", "failing_watch"],
		"passive_rise": false,  # Only escalates when evidence surfaces
	})

	register_thread({
		"id": "paralyzed_council",
		"name": "The Paralyzed Council",
		"description": "Mathias leads a council frozen by fear. Needs proof to authorize action.",
		"driving_npcs": ["elder_mathias_001"],
		"tension": 0.08,
		"key_flags": ["mathias_informed"],
		"intersects_with": ["failing_watch"],
	})

	register_thread({
		"id": "bandit_expansion",
		"name": "The Bandit Expansion",
		"description": "The Iron Hollow Gang grows bolder. Varn is ambitious. The arrangement is unstable.",
		"driving_npcs": ["varn_bandit_001"],
		"tension": 0.15,
		"key_flags": ["varn_confronted", "iron_hollow_visited"],
		"intersects_with": ["merchants_bargain", "grieving_widow"],
	})
