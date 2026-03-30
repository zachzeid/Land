extends Node
class_name NPCAgentLoop
## NPCAgentLoop - Autonomous decision-making loop for NPCs
##
## Implements the 5-step agent cycle:
##   1. PERCEIVE  — Gather beliefs about the world
##   2. EVALUATE  — Score each goal by urgency
##   3. SELECT    — Pick the highest-utility valid action
##   4. EXECUTE   — Perform the action
##   5. REFLECT   — Store outcome and update priorities
##
## Runs on a timer (configurable tick rate). Simple decisions are rule-based.
## Complex decisions (secrets, alliances, betrayals) escalate to Claude via sidecar.

signal action_taken(npc_id: String, action: Dictionary)
signal goal_changed(npc_id: String, old_goal: String, new_goal: String)

## The NPC this agent loop controls
var npc: Node = null  # BaseNPC reference

## Tick rate in seconds
@export var tick_interval: float = 45.0

## Agent state
var current_goal: Dictionary = {}
var current_action: Dictionary = {}
var _tick_timer: Timer = null
var _is_thinking: bool = false

## Perception cache (refreshed each tick)
var _world_perception: Dictionary = {}

func _ready():
	npc = get_parent()
	if npc == null or not npc.has_method("move_to_position"):
		push_error("[AgentLoop] Must be a child of a BaseNPC node")
		return

	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval + randf_range(-5.0, 5.0)  # Stagger NPC ticks
	_tick_timer.timeout.connect(_on_tick)
	_tick_timer.one_shot = false
	add_child(_tick_timer)

	# Wait for NPC to initialize before starting
	await get_tree().create_timer(2.0).timeout
	_tick_timer.start()
	print("[AgentLoop:%s] Started (tick every %.0fs)" % [_get_npc_name(), _tick_timer.wait_time])

func _on_tick():
	if _is_thinking:
		return  # Skip if still processing previous tick
	if npc == null or not is_instance_valid(npc):
		return
	if not npc.get("is_alive") or not npc.get("_is_initialized"):
		return
	if npc.get("is_in_conversation"):
		return  # Don't think during conversations

	_is_thinking = true
	await _run_agent_cycle()
	_is_thinking = false

## The core 5-step agent cycle
func _run_agent_cycle():
	# 1. PERCEIVE
	_world_perception = _perceive()

	# 2. EVALUATE goals
	var scored_goals = _evaluate_goals()
	if scored_goals.is_empty():
		return

	# 3. SELECT action for highest-priority goal
	var top_goal = scored_goals[0]
	var selected_action: Dictionary = {}

	# Check if this decision needs Claude escalation
	if _needs_claude_escalation(top_goal):
		var possible_actions = _get_possible_actions(top_goal)
		if possible_actions.size() > 1:
			selected_action = await _escalate_to_claude(top_goal, possible_actions)

	# Fall back to rule-based if Claude didn't decide or wasn't needed
	if selected_action.is_empty():
		selected_action = _select_action(top_goal)
	if selected_action.is_empty():
		return

	# Track goal changes
	if current_goal.get("goal", "") != top_goal.get("goal", ""):
		var old = current_goal.get("goal", "none")
		current_goal = top_goal
		goal_changed.emit(npc.npc_id, old, top_goal.goal)

	# 4. EXECUTE
	current_action = selected_action
	await _execute_action(selected_action)

	# 5. REFLECT
	_reflect(selected_action)

# =============================================================================
# STEP 1: PERCEIVE
# =============================================================================

func _perceive() -> Dictionary:
	var perception := {}

	# World flags
	perception["world_flags"] = WorldState.get_flags()

	# Current time
	var game_clock = get_node_or_null("/root/GameClock")
	if game_clock:
		perception["time_period"] = game_clock.get_current_period()
		perception["day"] = game_clock.get_current_day()

	# Active quests
	perception["active_quests"] = WorldState.get_active_quests()

	# Own state
	perception["location"] = npc.current_location
	perception["in_conversation"] = npc.is_in_conversation
	perception["is_moving"] = npc.get("_is_moving")
	perception["trust_with_player"] = npc.relationship_trust
	perception["affection_with_player"] = npc.relationship_affection
	perception["fear"] = npc.relationship_fear

	# Nearby NPCs
	var nearby = []
	for other_npc in get_tree().get_nodes_in_group("npcs"):
		if other_npc == npc or not is_instance_valid(other_npc):
			continue
		if other_npc.global_position.distance_to(npc.global_position) < 300:
			nearby.append({
				"npc_id": other_npc.get("npc_id"),
				"name": other_npc.get("npc_name"),
				"location": other_npc.get("current_location"),
			})
	perception["nearby_npcs"] = nearby

	return perception

# =============================================================================
# STEP 2: EVALUATE GOALS
# =============================================================================

func _evaluate_goals() -> Array:
	var goals: Array = []

	# Get goals from personality resource
	if npc.personality_resource and npc.personality_resource.get("goals"):
		for goal_def in npc.personality_resource.goals:
			var scored = goal_def.duplicate()
			scored["urgency"] = _calculate_goal_urgency(scored)
			goals.append(scored)

	# Add reactive goals from perception
	var reactive = _generate_reactive_goals()
	goals.append_array(reactive)

	# Sort by urgency (highest first)
	goals.sort_custom(func(a, b): return a.urgency > b.urgency)

	return goals

func _calculate_goal_urgency(goal: Dictionary) -> float:
	var base_priority = goal.get("priority", 50) as float
	var urgency = base_priority

	# Modify based on world state
	var flags = _world_perception.get("world_flags", {})

	# If NPC's secret is at risk, protection goals spike
	if flags.get("ledger_found", false) and npc.npc_id == "gregor_merchant_001":
		if goal.get("goal", "") == "protect_secret":
			urgency += 30.0

	# Night time increases "go home" priority
	if _world_perception.get("time_period", "") == "night":
		if goal.get("goal", "") in ["rest", "go_home", "close_shop"]:
			urgency += 20.0

	# Fear increases self-preservation
	var fear = _world_perception.get("fear", 0)
	if fear > 30 and goal.get("goal", "") in ["protect_self", "flee", "hide"]:
		urgency += fear * 0.3

	return urgency

func _generate_reactive_goals() -> Array:
	var reactive := []
	var flags = _world_perception.get("world_flags", {})

	# If there are nearby NPCs and we have gossip, share it
	if not _world_perception.get("nearby_npcs", []).is_empty():
		if npc.personality_resource and npc.personality_resource.gossip_tendency > 0.3:
			reactive.append({
				"goal": "share_gossip",
				"priority": 30,
				"urgency": 30.0 * npc.personality_resource.gossip_tendency,
				"description": "Share what I know with nearby NPCs",
			})

	# Schedule-based: check if NPC should be somewhere
	var game_clock = get_node_or_null("/root/GameClock")
	if game_clock:
		var period = game_clock.get_current_period()
		var scheduled_loc = _get_scheduled_location(period)
		if scheduled_loc != "" and scheduled_loc != npc.current_location:
			reactive.append({
				"goal": "follow_schedule",
				"priority": 60,
				"urgency": 65.0,
				"description": "Go to %s for %s" % [scheduled_loc, period],
				"target_location": scheduled_loc,
			})

	return reactive

func _get_scheduled_location(period: String) -> String:
	if npc.personality_resource and npc.personality_resource.get("daily_schedule"):
		for entry in npc.personality_resource.daily_schedule:
			if entry.get("time_period", "") == period:
				return entry.get("location", "")
	return ""

# =============================================================================
# STEP 3: SELECT ACTION
# =============================================================================

## Generate possible actions for a goal (used by Claude escalation)
func _get_possible_actions(goal: Dictionary) -> Array:
	var actions := []
	var goal_type = goal.get("goal", "")

	match goal_type:
		"share_secret":
			for nearby in _world_perception.get("nearby_npcs", []):
				actions.append({"type": "share_secret", "target": nearby.npc_id,
					"reason": "Share what I know with %s" % nearby.name})
			actions.append({"type": "stay_silent", "reason": "Keep the secret to myself"})

		"protect_secret":
			actions.append({"type": "change_behavior", "behavior": "guarded", "reason": "Become more guarded"})
			actions.append({"type": "move_to", "location": npc.home_location, "reason": "Retreat to safety"})
			actions.append({"type": "idle", "reason": "Act normal, don't draw attention"})

		_:
			# Generic: provide move, gossip, idle options
			actions.append({"type": "move_to", "location": goal.get("target_location", npc.home_location),
				"reason": goal.get("description", "Go somewhere")})
			actions.append({"type": "share_gossip", "reason": "Talk to someone nearby"})
			actions.append({"type": "idle", "reason": "Wait and observe"})

	return actions

func _select_action(goal: Dictionary) -> Dictionary:
	var goal_type = goal.get("goal", "")

	match goal_type:
		"follow_schedule":
			return {"type": "move_to", "location": goal.get("target_location", ""), "reason": goal.description}

		"share_gossip":
			return {"type": "share_info", "reason": "Sharing what I know with nearby NPCs"}

		"protect_secret":
			return {"type": "change_behavior", "behavior": "guarded", "reason": "Must protect my secret"}

		"go_home", "rest", "close_shop":
			return {"type": "move_to", "location": npc.home_location, "reason": goal.description}

		_:
			# Generic: if the goal has a target_location, move there
			if goal.has("target_location"):
				return {"type": "move_to", "location": goal.target_location, "reason": goal.get("description", "")}
			# Otherwise, idle
			return {"type": "idle", "reason": "No clear action for goal: %s" % goal_type}

# =============================================================================
# STEP 4: EXECUTE ACTION
# =============================================================================

func _execute_action(action_to_execute: Dictionary):
	var action_type = action_to_execute.get("type", "idle")

	match action_type:
		"move_to":
			var target_location = action_to_execute.get("location", "")
			if target_location == "":
				return

			# Get position from ScheduleManager
			var schedule_mgr = get_node_or_null("/root/ScheduleManager")
			if schedule_mgr:
				var target_pos = schedule_mgr.location_positions.get(target_location, Vector2.ZERO)
				if target_pos != Vector2.ZERO:
					npc.move_to_position(target_pos)
					npc.current_location = target_location
					print("[AgentLoop:%s] Moving to %s" % [_get_npc_name(), target_location])

		"share_info":
			_share_gossip_with_nearby()

		"change_behavior":
			# For now, just log it. Future: modify NPC's dialogue context
			print("[AgentLoop:%s] Behavior changed to: %s" % [_get_npc_name(), action_to_execute.get("behavior", "")])

		"set_flag":
			var flag_name = action_to_execute.get("flag", "")
			var flag_value = action_to_execute.get("value", true)
			if flag_name != "":
				WorldState.set_world_flag(flag_name, flag_value)
				print("[AgentLoop:%s] Set flag: %s = %s" % [_get_npc_name(), flag_name, flag_value])

		"idle":
			pass  # Do nothing, NPC continues current behavior

	# Emit action for other systems to track
	action_taken.emit(npc.npc_id, action_to_execute)
	EventBus.world_event.emit({
		"event_type": "npc_action",
		"npc_id": npc.npc_id,
		"npc_name": npc.npc_name,
		"action": action_type,
		"description": action_to_execute.get("reason", ""),
		"location": npc.current_location,
	})

func _share_gossip_with_nearby():
	if not npc.has_method("get_shareable_info"):
		return

	for other in _world_perception.get("nearby_npcs", []):
		var other_id = other.get("npc_id", "")
		if other_id == "" or other_id == npc.npc_id:
			continue

		# Simple gossip: emit info packet via EventBus
		EventBus.npc_communicated.emit(npc.npc_id, other_id, {
			"content": "General village gossip from %s" % npc.npc_name,
			"source_npc": npc.npc_id,
			"category": "gossip",
			"confidence": 0.8,
		}) if EventBus.has_signal("npc_communicated") else null

# =============================================================================
# STEP 5: REFLECT
# =============================================================================

func _reflect(completed_action: Dictionary):
	# Store action in NPC's memory
	if npc.get("rag_memory") and npc.rag_memory and npc.rag_memory.has_method("store"):
		var action_description = "I decided to %s because %s" % [
			completed_action.get("type", "idle"),
			completed_action.get("reason", "no particular reason")
		]

		# Only store meaningful actions (not idle)
		if completed_action.get("type", "idle") != "idle":
			npc.rag_memory.store({
				"text": action_description,
				"event_type": "autonomous_action",
				"importance": 3,
				"emotion": "neutral",
				"topics": [completed_action.get("type", "")],
			})

# =============================================================================
# HELPERS
# =============================================================================

func _get_npc_name() -> String:
	if npc and npc.get("npc_name"):
		return npc.npc_name
	return "Unknown"

## Change tick rate (for debugging or dynamic adjustment)
func set_tick_interval(seconds: float):
	tick_interval = seconds
	if _tick_timer:
		_tick_timer.wait_time = seconds

# =============================================================================
# CLAUDE ESCALATION (for complex decisions)
# =============================================================================

## Determine if a decision requires Claude (complex social reasoning)
func _needs_claude_escalation(goal: Dictionary) -> bool:
	var goal_type = goal.get("goal", "")

	# Secret sharing always needs Claude
	if goal_type in ["share_secret", "reveal_information", "confide"]:
		return true

	# Alliance/betrayal decisions need Claude
	if goal_type in ["form_alliance", "betray", "switch_sides"]:
		return true

	# Conflicting goals need Claude
	if goal.get("conflicting", false):
		return true

	# High-stakes decisions (urgency > 80) may need Claude
	if goal.get("urgency", 0) > 80 and goal_type not in ["follow_schedule", "go_home", "rest"]:
		return true

	return false

## Send a decision to Claude via the sidecar for complex reasoning
func _escalate_to_claude(goal: Dictionary, available_actions: Array) -> Dictionary:
	var sidecar_url = "http://127.0.0.1:8080/think"

	# Build a short decision prompt
	var personality_summary = ""
	if npc.personality_resource:
		personality_summary = "%s. %s" % [npc.personality_resource.display_name, npc.personality_resource.core_identity]

	var actions_text = ""
	for i in range(available_actions.size()):
		var a = available_actions[i]
		actions_text += "%d. %s — %s\n" % [i + 1, a.get("type", "unknown"), a.get("reason", "")]

	var system_prompt = "You are an NPC decision engine. Given the character's personality and situation, choose ONE action. Respond with JSON only: {\"action_index\": N, \"reason\": \"brief\"}"

	var user_message = """Character: %s
Current goal: %s (urgency: %.0f)
Situation: %s
Nearby NPCs: %s
Trust with player: %.0f, Fear: %.0f

Available actions:
%s
Choose the action number that best fits this character's personality and goals.""" % [
		personality_summary,
		goal.get("goal", "unknown"),
		goal.get("urgency", 0),
		goal.get("description", ""),
		str(_world_perception.get("nearby_npcs", [])),
		_world_perception.get("trust_with_player", 0),
		_world_perception.get("fear", 0),
		actions_text
	]

	# Call sidecar
	var http = HTTPRequest.new()
	add_child(http)

	var body = JSON.stringify({
		"model": "haiku",  # Use Haiku for NPC decisions (cheaper)
		"system_prompt": system_prompt,
		"messages": [{"role": "user", "content": user_message}],
		"max_tokens": 150,
	})

	var headers = ["Content-Type: application/json"]
	var error = http.request(sidecar_url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		http.queue_free()
		return {}

	var result = await http.request_completed
	http.queue_free()

	var response_code = result[1]
	var response_body = result[3].get_string_from_utf8()

	if response_code != 200:
		push_warning("[AgentLoop:%s] Claude escalation failed: %d" % [_get_npc_name(), response_code])
		return {}

	# Parse Claude's response
	var json = JSON.new()
	var parse_result = json.parse(response_body)
	if parse_result != OK:
		return {}

	var claude_response = json.data
	var response_text = claude_response.get("response", "")

	# Try to parse the action choice from Claude's response
	var inner_json = JSON.new()
	var inner_parse = inner_json.parse(response_text)
	if inner_parse == OK and inner_json.data is Dictionary:
		var action_index = inner_json.data.get("action_index", 1) - 1  # 1-indexed to 0-indexed
		if action_index >= 0 and action_index < available_actions.size():
			var chosen = available_actions[action_index]
			chosen["claude_reason"] = inner_json.data.get("reason", "")
			print("[AgentLoop:%s] Claude chose action %d: %s — %s" % [
				_get_npc_name(), action_index + 1, chosen.type, chosen.get("claude_reason", "")])
			return chosen

	return {}
