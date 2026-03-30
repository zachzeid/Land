extends Node
class_name ConsequenceGraph
## Consequence Graph - Rule-based engine for cascading world state changes
##
## When a world flag changes, the ConsequenceGraph evaluates registered rules
## and executes effects that cascade through the world. This is the connective
## tissue between NPC actions and world reactions.
##
## Usage:
##   ConsequenceGraph registers rules at startup.
##   When WorldState.set_world_flag() fires, EventBus.world_flag_changed triggers evaluation.
##   Matching rules execute their effects (set more flags, modify factions, notify NPCs, create ripples).
##   Effects can cascade — a rule's output flag can trigger another rule.

signal consequence_triggered(rule_id: String, trigger_flag: String, effects: Array)
signal cascade_completed(trigger_flag: String, total_effects: int)

## Maximum cascade depth to prevent infinite loops
const MAX_CASCADE_DEPTH := 10

## All registered consequence rules
var rules: Array[Dictionary] = []

## Track which rules have fired this cascade to prevent re-triggering
var _cascade_fired: Dictionary = {}
var _cascade_depth: int = 0

func _ready():
	EventBus.world_flag_changed.connect(_on_flag_changed)
	_register_core_rules()
	print("[ConsequenceGraph] Initialized with %d rules" % rules.size())

## Register a consequence rule
## rule format:
## {
##   "id": String,                    # Unique rule identifier
##   "trigger_flag": String,          # Flag that triggers this rule
##   "trigger_value": bool,           # Value that activates (default true)
##   "conditions": Dictionary,        # Additional flags that must be true/false
##   "effects": Array[Dictionary],    # Actions to take when triggered
##   "delay_days": int,               # Game-days to wait before executing (0 = immediate)
##   "once_only": bool,               # Only fire once per game (default true)
##   "description": String,           # Human-readable description for debugging
## }
##
## effect format:
## {
##   "type": "set_flag" | "modify_faction" | "notify_npc" | "create_event" | "modify_economy",
##   "target": String,                # Flag name, faction ID, NPC ID, etc.
##   "value": Variant,                # Value to set/add
##   "description": String,           # What this effect represents
## }
func register_rule(rule: Dictionary):
	if not rule.has("id") or not rule.has("trigger_flag") or not rule.has("effects"):
		push_error("[ConsequenceGraph] Rule missing required fields: id, trigger_flag, effects")
		return
	if not rule.has("trigger_value"):
		rule["trigger_value"] = true
	if not rule.has("conditions"):
		rule["conditions"] = {}
	if not rule.has("delay_days"):
		rule["delay_days"] = 0
	if not rule.has("once_only"):
		rule["once_only"] = true
	rules.append(rule)

## Called when any world flag changes
func _on_flag_changed(flag_name: String, old_value, new_value):
	if _cascade_depth == 0:
		_cascade_fired.clear()

	_cascade_depth += 1
	if _cascade_depth > MAX_CASCADE_DEPTH:
		push_warning("[ConsequenceGraph] Max cascade depth reached for flag: %s" % flag_name)
		_cascade_depth -= 1
		return

	var total_effects := 0

	for rule in rules:
		if rule.trigger_flag != flag_name:
			continue
		if new_value != rule.trigger_value:
			continue
		if rule.id in _cascade_fired and rule.once_only:
			continue
		if not _check_conditions(rule.conditions):
			continue

		# Rule matches — execute effects
		_cascade_fired[rule.id] = true
		var effects_applied := _execute_effects(rule)
		total_effects += effects_applied

		consequence_triggered.emit(rule.id, flag_name, rule.effects)
		print("[ConsequenceGraph] Rule '%s' triggered by flag '%s' → %d effects" % [rule.id, flag_name, effects_applied])

	if _cascade_depth == 1 and total_effects > 0:
		cascade_completed.emit(flag_name, total_effects)
		print("[ConsequenceGraph] Cascade from '%s' complete: %d total effects" % [flag_name, total_effects])

	_cascade_depth -= 1

## Check if additional conditions are met
func _check_conditions(conditions: Dictionary) -> bool:
	for flag_name in conditions:
		var required_value = conditions[flag_name]
		var actual_value = WorldState.get_world_flag(flag_name)
		if actual_value != required_value:
			return false
	return true

## Execute all effects for a triggered rule
func _execute_effects(rule: Dictionary) -> int:
	var count := 0
	for effect in rule.effects:
		match effect.type:
			"set_flag":
				WorldState.set_world_flag(effect.target, effect.value)
				count += 1
			"modify_faction":
				var current = WorldState.get_faction_reputation(effect.target)
				WorldState.faction_reputations[effect.target] = clamp(current + effect.value, -100, 100)
				EventBus.faction_reputation_changed.emit(effect.target, current, current + effect.value)
				count += 1
			"notify_npc":
				EventBus.npc_witnessed_event.emit(effect.target, {
					"event_type": effect.get("event_type", "world_change"),
					"description": effect.get("description", "Something happened in the world"),
					"source_rule": rule.id,
					"importance": effect.get("importance", 5),
				})
				count += 1
			"create_event":
				EventBus.world_event.emit({
					"event_type": effect.get("event_type", "consequence"),
					"description": effect.get("description", ""),
					"source_rule": rule.id,
					"location": effect.get("location", "thornhaven"),
				})
				count += 1
			_:
				push_warning("[ConsequenceGraph] Unknown effect type: %s" % effect.type)
	return count

## Get all rules that would trigger for a given flag
func get_rules_for_flag(flag_name: String) -> Array:
	return rules.filter(func(r): return r.trigger_flag == flag_name)

## Debug: print all registered rules
func debug_print_rules():
	print("[ConsequenceGraph] === Registered Rules ===")
	for rule in rules:
		var desc = rule.get("description", "no description")
		print("  [%s] on '%s'=%s → %d effects — %s" % [
			rule.id, rule.trigger_flag, rule.trigger_value, rule.effects.size(), desc])

# =============================================================================
# CORE STORY CONSEQUENCE RULES
# =============================================================================

func _register_core_rules():
	# --- LEDGER FOUND ---
	register_rule({
		"id": "ledger_found_gregor_panic",
		"trigger_flag": "ledger_found",
		"description": "Gregor panics when ledger is found — his evidence is exposed",
		"effects": [
			{"type": "notify_npc", "target": "gregor_merchant_001",
			 "event_type": "personal_crisis", "importance": 9,
			 "description": "Someone found the secret ledger in your shop. Your evidence of bandit payments is exposed."},
		]
	})

	# --- WEAPONS TRACED ---
	register_rule({
		"id": "weapons_traced_bjorn_learns",
		"trigger_flag": "weapons_traced_to_bjorn",
		"description": "When weapons are traced, Bjorn can be informed",
		"effects": [
			{"type": "notify_npc", "target": "bjorn_blacksmith_001",
			 "event_type": "revelation", "importance": 8,
			 "description": "Weapons bearing your maker's mark have been found in the hands of bandits."},
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "evidence_discovered", "importance": 7,
			 "description": "Bandit weapons have been traced to the local blacksmith's forge."},
		]
	})

	# --- GREGOR CONFRONTED ---
	register_rule({
		"id": "gregor_confronted_village_alert",
		"trigger_flag": "gregor_confronted",
		"description": "Confronting Gregor sends shockwaves through the village",
		"effects": [
			{"type": "notify_npc", "target": "elena_daughter_001",
			 "event_type": "family_crisis", "importance": 10,
			 "description": "Someone confronted your father about serious accusations."},
			{"type": "notify_npc", "target": "mira_tavern_keeper_001",
			 "event_type": "political_shift", "importance": 7,
			 "description": "Gregor has been confronted about his dealings. The situation is escalating."},
			{"type": "notify_npc", "target": "elder_mathias_001",
			 "event_type": "political_shift", "importance": 8,
			 "description": "The merchant Gregor has been confronted about possible bandit connections."},
		]
	})

	# --- GREGOR EXPOSED PUBLICLY ---
	register_rule({
		"id": "gregor_exposed_cascade",
		"trigger_flag": "gregor_exposed",
		"description": "Public exposure of Gregor triggers massive village-wide consequences",
		"effects": [
			{"type": "set_flag", "target": "resistance_forming", "value": true,
			 "description": "Village begins to organize resistance now that the informant is known"},
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "authorization_granted", "importance": 10,
			 "description": "The informant has been exposed. You now have justification to act against the bandits."},
			{"type": "notify_npc", "target": "elena_daughter_001",
			 "event_type": "family_devastation", "importance": 10,
			 "description": "Your father has been publicly exposed as the village traitor. Everyone knows."},
			{"type": "modify_faction", "target": "iron_hollow_gang", "value": -20.0,
			 "description": "Bandits lose their inside man — their grip on Thornhaven weakens"},
			{"type": "create_event", "event_type": "major_revelation",
			 "description": "Gregor Stoneheart exposed as the bandit informant",
			 "location": "thornhaven"},
		]
	})

	# --- RESISTANCE FORMING ---
	register_rule({
		"id": "resistance_forming_aldric_acts",
		"trigger_flag": "resistance_forming",
		"description": "Resistance forming triggers Aldric to begin preparations",
		"effects": [
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "call_to_action", "importance": 9,
			 "description": "The resistance is forming. It's time to reveal the weapon cache and begin training."},
			{"type": "notify_npc", "target": "bjorn_blacksmith_001",
			 "event_type": "call_to_action", "importance": 7,
			 "description": "The village is organizing resistance. Your forge skills are needed."},
			{"type": "modify_faction", "target": "thornhaven_peacekeepers", "value": 15.0,
			 "description": "Peacekeepers gain strength as village rallies"},
		]
	})

	# --- BJORN LEARNS TRUTH ---
	register_rule({
		"id": "bjorn_truth_redemption",
		"trigger_flag": "bjorn_truth_revealed",
		"description": "Bjorn learning the truth transforms him into active resistance",
		"effects": [
			{"type": "set_flag", "target": "bjorn_knows_about_weapons", "value": true,
			 "description": "Bjorn now knows where his weapons have been going"},
			{"type": "notify_npc", "target": "bjorn_blacksmith_001",
			 "event_type": "moral_crisis", "importance": 10,
			 "description": "You have learned the terrible truth: your weapons have been arming the bandits who terrorize your village."},
		]
	})

	# --- ELENA LEARNS ABOUT FATHER ---
	register_rule({
		"id": "elena_devastation",
		"trigger_flag": "elena_knows_about_father",
		"description": "Elena learning about her father's crimes devastates her",
		"effects": [
			{"type": "notify_npc", "target": "elena_daughter_001",
			 "event_type": "family_devastation", "importance": 10,
			 "description": "You now know the truth about your father. He is the village informant working with bandits."},
			{"type": "notify_npc", "target": "gregor_merchant_001",
			 "event_type": "personal_crisis", "importance": 10,
			 "description": "Elena knows. Your daughter has learned what you've done."},
		]
	})

	# --- ALDRIC RECEIVES EVIDENCE ---
	register_rule({
		"id": "aldric_evidence_preparation",
		"trigger_flag": "aldric_has_evidence",
		"description": "Aldric with evidence begins formal preparations",
		"effects": [
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "evidence_received", "importance": 9,
			 "description": "You now have the evidence you've been waiting for. Time to take this to the council."},
			{"type": "notify_npc", "target": "elder_mathias_001",
			 "event_type": "political_shift", "importance": 8,
			 "description": "Captain Aldric has obtained evidence against the suspected informant."},
		]
	})

	# --- MATHIAS INFORMED ---
	register_rule({
		"id": "mathias_council_action",
		"trigger_flag": "mathias_informed",
		"conditions": {"aldric_has_evidence": true},
		"description": "Mathias with evidence AND Aldric's support authorizes action",
		"effects": [
			{"type": "set_flag", "target": "resistance_forming", "value": true,
			 "description": "Council authorizes resistance with evidence in hand"},
			{"type": "create_event", "event_type": "political_decision",
			 "description": "Elder Mathias and the council have authorized action against the bandits",
			 "location": "thornhaven"},
		]
	})

	# --- MIRA BOSS REVEALED ---
	register_rule({
		"id": "mira_boss_revealed_cascade",
		"trigger_flag": "mira_boss_revealed",
		"description": "The biggest twist — Mira is The Boss. Everything changes.",
		"effects": [
			{"type": "notify_npc", "target": "gregor_merchant_001",
			 "event_type": "revelation", "importance": 10,
			 "description": "The Boss — the one you've been dealing with through Varn — is Mira. The tavern keeper. She orchestrated everything."},
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "revelation", "importance": 10,
			 "description": "Mira Hearthwood, the tavern keeper, is The Boss of Iron Hollow. Her grief was a cover."},
			{"type": "modify_faction", "target": "iron_hollow_gang", "value": -30.0,
			 "description": "With The Boss exposed, the gang's leadership is compromised"},
			{"type": "create_event", "event_type": "major_revelation",
			 "description": "Mira Hearthwood revealed as the mastermind behind Iron Hollow",
			 "location": "thornhaven"},
		]
	})

	# --- VARN CONFRONTED ---
	register_rule({
		"id": "varn_confronted_escalation",
		"trigger_flag": "varn_confronted",
		"description": "Confronting Varn escalates bandit tensions",
		"effects": [
			{"type": "modify_faction", "target": "iron_hollow_gang", "value": 10.0,
			 "description": "Bandits become more aggressive after their lieutenant is challenged"},
			{"type": "notify_npc", "target": "aldric_peacekeeper_001",
			 "event_type": "threat_escalation", "importance": 7,
			 "description": "Someone confronted the bandit lieutenant. The bandits may retaliate."},
		]
	})

	# --- GREGOR REDEMPTION PATH ---
	register_rule({
		"id": "gregor_redemption_begins",
		"trigger_flag": "gregor_redemption_path",
		"description": "Gregor choosing redemption begins to undermine the bandit operation from within",
		"effects": [
			{"type": "modify_faction", "target": "iron_hollow_gang", "value": -10.0,
			 "description": "Gregor begins feeding false intelligence to the bandits"},
			{"type": "notify_npc", "target": "elena_daughter_001",
			 "event_type": "hope", "importance": 7,
			 "description": "Your father is trying to make things right. He's working to undo the damage he caused."},
		]
	})
