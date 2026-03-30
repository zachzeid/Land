extends Node
class_name QuestEmergenceEngine
## QuestEmergenceEngine - Generates quests from story thread tensions
##
## Instead of hand-authoring dozens of quests, this engine uses reusable
## templates that are filled in based on current world state. When a story
## thread's tension crosses a threshold, emergence rules fire and create
## contextual quests via the existing QuestManager.
##
## Quest templates are patterns: "investigate_npc", "present_evidence",
## "witness_event", "npc_request", "crisis_response". Each generates
## different quests depending on which NPC, which thread, and what the
## player already knows.

signal quest_emerged(quest_id: String, template: String, thread_id: String)

## Reference to ThreadManager
var thread_manager: Node = null

## Emergence rules: conditions → quest generation
var emergence_rules: Array[Dictionary] = []

## Track which rules have fired (prevent duplicate quests)
var _fired_rules: Dictionary = {}

## Check interval
var _check_timer: Timer = null
const CHECK_INTERVAL := 10.0  # Check every 10 seconds

func _ready():
	thread_manager = get_node_or_null("/root/ThreadManager")
	if thread_manager == null:
		push_warning("[QuestEmergence] ThreadManager not found")
		return

	thread_manager.thread_state_changed.connect(_on_thread_state_changed)
	thread_manager.thread_tension_changed.connect(_on_tension_changed)

	# Periodic check for emergence conditions
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVAL
	_check_timer.timeout.connect(_evaluate_all_rules)
	_check_timer.one_shot = false
	add_child(_check_timer)
	_check_timer.start()

	_register_emergence_rules()
	print("[QuestEmergence] Initialized with %d rules" % emergence_rules.size())

## Register an emergence rule
## rule format: {
##   "id": String,
##   "thread_id": String,           # Which thread triggers this
##   "min_tension": float,          # Minimum tension to trigger
##   "min_state": String,           # Minimum thread state ("simmering", "escalating", "crisis", "breaking")
##   "required_flags": Dictionary,  # {flag: true/false} that must be set
##   "blocked_by_flags": Array,     # Flags that prevent this rule
##   "quest_template": String,      # Template to use
##   "quest_params": Dictionary,    # Parameters for the template
##   "once_only": bool,             # Only fire once (default true)
## }
func register_rule(rule: Dictionary):
	emergence_rules.append(rule)

## Evaluate all rules against current state
func _evaluate_all_rules():
	if thread_manager == null:
		return

	for rule in emergence_rules:
		if rule.id in _fired_rules and rule.get("once_only", true):
			continue

		if _check_rule_conditions(rule):
			_fire_rule(rule)

## Check if a rule's conditions are met
func _check_rule_conditions(rule: Dictionary) -> bool:
	var thread_id = rule.get("thread_id", "")
	if thread_id == "" or thread_id not in thread_manager.threads:
		return false

	var thread = thread_manager.threads[thread_id]

	# Check tension threshold
	if thread.tension < rule.get("min_tension", 0.0):
		return false

	# Check state threshold
	var min_state = rule.get("min_state", "simmering")
	var state_order = ["simmering", "escalating", "crisis", "breaking"]
	if state_order.find(thread.state) < state_order.find(min_state):
		return false

	# Check required flags
	for flag in rule.get("required_flags", {}):
		if WorldState.get_world_flag(flag) != rule.required_flags[flag]:
			return false

	# Check blocked flags
	for flag in rule.get("blocked_by_flags", []):
		if WorldState.get_world_flag(flag):
			return false

	return true

## Fire a rule — generate a quest
func _fire_rule(rule: Dictionary):
	_fired_rules[rule.id] = true

	var template = rule.get("quest_template", "")
	var params = rule.get("quest_params", {})
	var thread_id = rule.get("thread_id", "")

	var quest = _generate_quest_from_template(template, params, rule.id)
	if quest == null:
		return

	# Register with QuestManager
	var quest_mgr = get_node_or_null("/root/QuestManager")
	if quest_mgr and quest_mgr.has_method("register_quest"):
		quest_mgr.register_quest(quest)
		quest_emerged.emit(quest.quest_id, template, thread_id)
		print("[QuestEmergence] Quest emerged: '%s' from thread '%s' (template: %s)" % [
			quest.title, thread_id, template])

## React to thread state changes
func _on_thread_state_changed(thread_id: String, _old_state: String, new_state: String):
	# Re-evaluate rules when threads change state
	_evaluate_all_rules()

## React to tension changes
func _on_tension_changed(thread_id: String, tension: float, _reason: String):
	# Only re-evaluate on significant changes
	if int(tension * 10) != int((tension - 0.05) * 10):  # Every 0.1 increment
		_evaluate_all_rules()

# =============================================================================
# QUEST TEMPLATES
# =============================================================================

func _generate_quest_from_template(template: String, params: Dictionary, rule_id: String) -> Resource:
	var QuestResourceScript = load("res://scripts/quests/quest_resource.gd")
	var QuestObjectiveScript = load("res://scripts/quests/quest_objective.gd")

	if QuestResourceScript == null or QuestObjectiveScript == null:
		push_error("[QuestEmergence] Could not load quest scripts")
		return null

	var quest = QuestResourceScript.new()

	match template:
		"investigate_npc":
			quest.quest_id = "emerged_%s" % rule_id
			quest.title = params.get("title", "Something's Not Right")
			quest.description = params.get("description", "Someone seems to be hiding something.")
			quest.story_arc = params.get("story_arc", "investigation")
			quest.is_main_quest = params.get("is_main", false)
			quest.priority = params.get("priority", 50)

			# Objective: Build trust with target NPC
			if params.has("target_npc"):
				var obj1 = QuestObjectiveScript.new()
				obj1.objective_id = "trust_%s" % params.target_npc
				obj1.description = "Earn %s's trust" % params.get("target_name", "their")
				obj1.complete_on_relationship = {params.target_npc: params.get("trust_threshold", 40.0)}
				obj1.order = 1
				quest.objectives.append(obj1)

			# Objective: Discuss relevant topic
			if params.has("topic"):
				var obj2 = QuestObjectiveScript.new()
				obj2.objective_id = "discuss_%s" % params.topic
				obj2.description = "Learn about %s" % params.topic
				obj2.complete_on_topics.append(params.topic)
				if params.has("target_npc"):
					obj2.requires_npc = params.target_npc
				obj2.order = 2
				quest.objectives.append(obj2)

			# Context hints
			if params.has("target_npc") and params.has("npc_hint"):
				quest.npc_context_hints[params.target_npc] = params.npc_hint

		"present_evidence":
			quest.quest_id = "emerged_%s" % rule_id
			quest.title = params.get("title", "Show What You Found")
			quest.description = params.get("description", "Present evidence to someone who can act on it.")
			quest.story_arc = params.get("story_arc", "investigation")
			quest.priority = params.get("priority", 70)

			# Objective: Present evidence to target NPC
			if params.has("target_npc") and params.has("flag"):
				var obj = QuestObjectiveScript.new()
				obj.objective_id = "present_to_%s" % params.target_npc
				obj.description = "Present evidence to %s" % params.get("target_name", "them")
				obj.complete_on_intent = "revelation"
				obj.requires_npc = params.target_npc
				obj.order = 1
				quest.objectives.append(obj)

			if params.has("completion_flag"):
				quest.completion_flags.append(params.completion_flag)

		"crisis_response":
			quest.quest_id = "emerged_%s" % rule_id
			quest.title = params.get("title", "A Crisis Demands Action")
			quest.description = params.get("description", "The situation has become urgent.")
			quest.is_main_quest = true
			quest.priority = params.get("priority", 90)

			# Multiple objectives based on crisis type
			for i in range(params.get("objectives", []).size()):
				var obj_data = params.objectives[i]
				var obj = QuestObjectiveScript.new()
				obj.objective_id = obj_data.get("id", "crisis_obj_%d" % i)
				obj.description = obj_data.get("description", "Act now")
				if obj_data.has("flag"):
					obj.complete_on_flag = obj_data.flag
				if obj_data.has("npc"):
					obj.requires_npc = obj_data.npc
				if obj_data.has("intent"):
					obj.complete_on_intent = obj_data.intent
				obj.order = i + 1
				quest.objectives.append(obj)

		"npc_request":
			quest.quest_id = "emerged_%s" % rule_id
			quest.title = params.get("title", "A Favor Asked")
			quest.description = params.get("description", "Someone needs your help.")
			quest.priority = params.get("priority", 60)

			quest.discovery_npc = params.get("requesting_npc", "")
			quest.discovery_intents.append_array(["request", "plea"])

			if params.has("completion_flag"):
				quest.completion_flags.append(params.completion_flag)

		_:
			push_warning("[QuestEmergence] Unknown template: %s" % template)
			return null

	quest.global_context_hint = params.get("global_hint", "")
	return quest

# =============================================================================
# CORE EMERGENCE RULES
# =============================================================================

func _register_emergence_rules():
	# --- MERCHANT'S BARGAIN THREAD ---

	register_rule({
		"id": "investigate_gregor_early",
		"thread_id": "merchants_bargain",
		"min_tension": 0.15,
		"min_state": "simmering",
		"required_flags": {},
		"blocked_by_flags": ["gregor_confession_heard"],
		"quest_template": "investigate_npc",
		"quest_params": {
			"title": "Something About the Merchant",
			"description": "Gregor seems unusually prosperous for a village under bandit extortion. Why?",
			"target_npc": "gregor_merchant_001",
			"target_name": "Gregor",
			"trust_threshold": 40.0,
			"topic": "ledger",
			"story_arc": "conspiracy",
			"is_main": true,
			"priority": 80,
			"npc_hint": "The player is curious about your success. Be naturally guarded but don't be suspicious — just deflect questions about money and trade patterns.",
		},
	})

	register_rule({
		"id": "present_ledger_to_aldric",
		"thread_id": "failing_watch",
		"min_tension": 0.20,
		"min_state": "simmering",
		"required_flags": {"ledger_found": true},
		"blocked_by_flags": ["aldric_has_evidence"],
		"quest_template": "present_evidence",
		"quest_params": {
			"title": "The Captain Needs Proof",
			"description": "Captain Aldric has long suspected an informant. The ledger could be the proof he needs.",
			"target_npc": "aldric_peacekeeper_001",
			"target_name": "Captain Aldric",
			"flag": "ledger_found",
			"completion_flag": "aldric_has_evidence",
			"story_arc": "conspiracy",
			"priority": 85,
		},
	})

	# --- DAUGHTER'S AWAKENING THREAD ---

	register_rule({
		"id": "elena_confides",
		"thread_id": "daughters_awakening",
		"min_tension": 0.20,
		"min_state": "simmering",
		"required_flags": {},
		"blocked_by_flags": ["elena_knows_about_father"],
		"quest_template": "investigate_npc",
		"quest_params": {
			"title": "Elena's Worry",
			"description": "Elena has noticed her father acting strangely. She might share her concerns with someone she trusts.",
			"target_npc": "elena_daughter_001",
			"target_name": "Elena",
			"trust_threshold": 35.0,
			"topic": "father",
			"story_arc": "elena",
			"priority": 50,
			"npc_hint": "You're worried about your father. If the player seems trustworthy, you might confide your suspicions.",
		},
	})

	# --- GRIEVING WIDOW THREAD ---

	register_rule({
		"id": "mira_drops_hints",
		"thread_id": "grieving_widow",
		"min_tension": 0.25,
		"min_state": "simmering",
		"required_flags": {},
		"blocked_by_flags": ["mira_testimony_given"],
		"quest_template": "investigate_npc",
		"quest_params": {
			"title": "The Tavern Keeper's Grief",
			"description": "Mira lost her husband to bandits. She seems to know more than she lets on.",
			"target_npc": "mira_tavern_keeper_001",
			"target_name": "Mira",
			"trust_threshold": 45.0,
			"topic": "marcus",
			"story_arc": "conspiracy",
			"priority": 65,
			"npc_hint": "The player is showing interest in your past. If trust is building, you might hint that Marcus's death wasn't what everyone thinks.",
		},
	})

	# --- FAILING WATCH THREAD ---

	register_rule({
		"id": "aldric_premature_strike",
		"thread_id": "failing_watch",
		"min_tension": 0.75,
		"min_state": "crisis",
		"required_flags": {},
		"blocked_by_flags": ["resistance_forming"],
		"quest_template": "crisis_response",
		"quest_params": {
			"title": "The Captain's Gambit",
			"description": "Aldric is planning a desperate assault on Iron Hollow. Without proper preparation, his men will die.",
			"story_arc": "conspiracy",
			"priority": 95,
			"objectives": [
				{"id": "talk_aldric", "description": "Talk to Captain Aldric about his plans", "npc": "aldric_peacekeeper_001", "intent": "request"},
				{"id": "prepare_or_stop", "description": "Help prepare the assault OR convince him to wait", "flag": "resistance_forming"},
			],
			"global_hint": "Captain Aldric is growing desperate. He may act rashly if no one intervenes.",
		},
	})

	# --- BANDIT EXPANSION THREAD ---

	register_rule({
		"id": "bandit_raid_warning",
		"thread_id": "bandit_expansion",
		"min_tension": 0.40,
		"min_state": "escalating",
		"required_flags": {},
		"blocked_by_flags": [],
		"quest_template": "npc_request",
		"once_only": true,
		"quest_params": {
			"title": "Bandits on the Road",
			"description": "Reports of increased bandit activity on the northern trade route. The village needs someone to investigate.",
			"requesting_npc": "aldric_peacekeeper_001",
			"priority": 70,
			"global_hint": "Bandit activity is increasing near Thornhaven. Trade is being disrupted.",
		},
	})
