extends Node
class_name WorldSimulation
## WorldSimulation - Singleton that runs the world simulation once per game-day
##
## Each game-day tick simulates:
##   1. Tier 2 NPC decisions (abstract Assess -> Choose)
##   2. Tier 3 faction actions (strength, morale, resources)
##   3. Trade route updates (safety, traffic, shipments)
##   4. Settlement economy updates (supply/demand from trade + local production)
##   5. Off-screen event generation (raids, festivals, political changes)
##   6. InfoPacket generation for local NPCs
##
## All simulation is rule-based with no Claude calls.

signal simulation_tick_completed(day: int, events: Array)
signal faction_action_taken(faction_id: String, action: Dictionary)
signal off_screen_event(event: Dictionary)

## All settlements {settlement_id: Settlement}
var settlements: Dictionary = {}

## Tier 2 NPC profiles {npc_id: Tier2Profile dict}
var tier2_profiles: Dictionary = {}

## Tier 3 faction profiles {faction_id: FactionProfile dict}
var faction_profiles: Dictionary = {}

## History of simulation events (last 30 days)
var event_history: Array[Dictionary] = []

## Current simulation day (synced from GameClock)
var _current_day: int = 0

func _ready():
	# Connect to game clock for daily ticks
	var game_clock = get_node_or_null("/root/GameClock")
	if game_clock:
		game_clock.new_day.connect(_on_new_day)

	# Initialize world data
	_register_settlements()
	_register_tier2_npcs()
	_register_factions()

	# Generate Tier 1 NPCs for all settlements
	_populate_settlements()

	print("[WorldSimulation] Initialized — %d settlements, %d Tier 2 NPCs, %d factions" % [
		settlements.size(), tier2_profiles.size(), faction_profiles.size()])

# =============================================================================
# DAILY TICK — The core simulation loop
# =============================================================================

func _on_new_day(day_number: int):
	_current_day = day_number
	print("[WorldSimulation] === Day %d Simulation ===" % day_number)

	var tick_events: Array[Dictionary] = []

	# 1. Tier 2 NPC decisions
	var npc_events = _simulate_tier2_npcs()
	tick_events.append_array(npc_events)

	# 2. Tier 3 faction actions
	var faction_events = _simulate_factions()
	tick_events.append_array(faction_events)

	# 3. Trade route updates + shipments
	var trade_route_mgr = get_node_or_null("/root/TradeRouteManager")
	if trade_route_mgr:
		var shipment_events = trade_route_mgr.tick_routes(settlements)
		for se in shipment_events:
			tick_events.append({
				"type": "trade_shipment",
				"description": "Goods arrived at %s via %s" % [se.destination, se.route_id],
				"settlement": se.destination,
				"data": se,
			})

	# 4. Settlement economy ticks
	for s_id in settlements:
		settlements[s_id].tick_economy()

	# 5. Off-screen event generation
	var generated = _generate_off_screen_events()
	tick_events.append_array(generated)

	# 6. Propagate events as InfoPackets
	_propagate_events_as_info(tick_events)

	# Store in history
	for event in tick_events:
		event["day"] = day_number
	event_history.append_array(tick_events)
	# Trim history
	while event_history.size() > 100:
		event_history.pop_front()

	simulation_tick_completed.emit(day_number, tick_events)
	print("[WorldSimulation] Day %d complete — %d events generated" % [day_number, tick_events.size()])

# =============================================================================
# TIER 2 NPC SIMULATION (Abstract: Assess -> Choose)
# =============================================================================

func _simulate_tier2_npcs() -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	for npc_id in tier2_profiles:
		var profile = tier2_profiles[npc_id]
		profile.last_action_tick = _current_day

		# ASSESS: Look at current state
		var settlement = settlements.get(profile.location, null)
		var faction = faction_profiles.get(profile.faction, null)

		# CHOOSE: Based on tendencies and current agenda
		var action = _tier2_choose_action(profile, settlement, faction)
		if action.is_empty():
			continue

		# Apply action effects
		var event = _apply_tier2_action(profile, action, settlement)
		if not event.is_empty():
			events.append(event)

	return events

func _tier2_choose_action(profile: Dictionary, settlement, faction) -> Dictionary:
	var agenda = profile.get("current_agenda", "")
	var progress = profile.get("agenda_progress", 0.0)
	var tendencies: Array = profile.get("tendencies", [])

	# Progress the current agenda
	var progress_rate = 0.05 + randf_range(0.0, 0.05)  # 5-10% per day
	profile.agenda_progress = minf(progress + progress_rate, 1.0)

	# If agenda completes, choose a new one
	if profile.agenda_progress >= 1.0:
		var action = {
			"type": "agenda_completed",
			"agenda": agenda,
			"npc_id": profile.npc_id,
		}
		# Pick new agenda based on tendencies
		profile.current_agenda = _select_new_agenda(tendencies, settlement, faction)
		profile.agenda_progress = 0.0
		return action

	# Reactive decisions based on world state
	if settlement and settlement.safety < 0.4 and "anti_bandit" in tendencies:
		return {"type": "increase_defenses", "npc_id": profile.npc_id, "target": settlement.settlement_id}

	if settlement and settlement.morale < 0.3 and "populist" in tendencies:
		return {"type": "rally_populace", "npc_id": profile.npc_id, "target": settlement.settlement_id}

	if faction and faction.resources < 30.0 and "greedy" in tendencies:
		return {"type": "acquire_resources", "npc_id": profile.npc_id, "faction": profile.faction}

	# Chance of doing something notable (20% per day)
	if randf() < 0.2:
		var possible_actions = ["send_message", "trade_deal", "political_move", "patrol_order"]
		return {"type": possible_actions[randi() % possible_actions.size()], "npc_id": profile.npc_id}

	return {}

func _select_new_agenda(tendencies: Array, settlement, faction) -> String:
	var agendas_pool = [
		"maintain_order", "increase_trade", "build_defenses", "gather_intelligence",
		"recruit_allies", "accumulate_wealth", "strengthen_position",
	]

	# Weight agendas by tendencies
	if "aggressive_expansionist" in tendencies:
		agendas_pool.append_array(["expand_territory", "raid_rivals", "recruit_fighters"])
	if "cautious_diplomat" in tendencies:
		agendas_pool.append_array(["negotiate_peace", "form_alliance", "send_envoy"])
	if "tax_raiser" in tendencies:
		agendas_pool.append_array(["raise_taxes", "collect_debts"])
	if "anti_bandit" in tendencies:
		agendas_pool.append_array(["raise_militia", "patrol_roads"])

	return agendas_pool[randi() % agendas_pool.size()]

func _apply_tier2_action(profile: Dictionary, action: Dictionary, settlement) -> Dictionary:
	var action_type = action.get("type", "")
	var event: Dictionary = {
		"type": "tier2_action",
		"npc_id": profile.npc_id,
		"npc_name": profile.display_name,
		"action": action_type,
		"settlement": profile.location,
	}

	match action_type:
		"agenda_completed":
			event["description"] = "%s completed their agenda: %s. Now pursuing: %s" % [
				profile.display_name, action.agenda, profile.current_agenda]

		"increase_defenses":
			if settlement:
				settlement.adjust_safety(0.05, "%s ordered increased patrols" % profile.display_name)
			event["description"] = "%s ordered increased defenses in %s" % [
				profile.display_name, profile.location]

		"rally_populace":
			if settlement:
				settlement.adjust_morale(0.08, "%s gave a rousing speech" % profile.display_name)
			event["description"] = "%s rallied the people of %s" % [
				profile.display_name, profile.location]

		"acquire_resources":
			var faction = faction_profiles.get(profile.faction)
			if faction:
				faction.resources = minf(faction.resources + 5.0, 100.0)
			event["description"] = "%s acquired resources for %s" % [
				profile.display_name, profile.faction]

		"send_message":
			event["description"] = "%s sent a message from %s" % [
				profile.display_name, profile.location]

		"trade_deal":
			if settlement:
				settlement.prosperity = minf(settlement.prosperity + 0.02, 1.0)
			event["description"] = "%s brokered a trade deal in %s" % [
				profile.display_name, profile.location]

		"political_move":
			event["description"] = "%s made a political maneuver in %s" % [
				profile.display_name, profile.location]

		_:
			event["description"] = "%s took action: %s" % [profile.display_name, action_type]

	return event

# =============================================================================
# TIER 3 FACTION SIMULATION (Evaluate goals -> Strategic action)
# =============================================================================

func _simulate_factions() -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	for faction_id in faction_profiles:
		var faction = faction_profiles[faction_id]
		var action = _faction_choose_action(faction)
		if action.is_empty():
			continue

		var event = _apply_faction_action(faction, action)
		if not event.is_empty():
			events.append(event)
			faction_action_taken.emit(faction_id, action)

	return events

func _faction_choose_action(faction: Dictionary) -> Dictionary:
	var goals: Array = faction.get("goals", [])
	var faction_type = faction.get("type", "")
	var strength = faction.get("strength", 50.0)
	var morale_val = faction.get("morale", 50.0)
	var resources = faction.get("resources", 50.0)

	# Natural decay/recovery
	faction.morale = clampf(morale_val + randf_range(-1.0, 1.0), 0.0, 100.0)
	faction.resources = clampf(resources - 0.5, 0.0, 100.0)  # Resources slowly drain

	# Check if faction can act (need minimum morale and resources)
	if morale_val < 15.0 or resources < 10.0:
		return {}  # Too weak to act

	# Weighted random action based on goals and faction type
	var action_weights: Dictionary = faction.get("event_weights", {})
	if action_weights.is_empty():
		action_weights = _default_action_weights(faction_type)

	# Modify weights based on state
	if strength > 70.0 and morale_val > 60.0:
		# Strong and bold — favor aggressive actions
		action_weights["raid"] = action_weights.get("raid", 0) + 2
		action_weights["expand"] = action_weights.get("expand", 0) + 1
	elif strength < 30.0 or morale_val < 30.0:
		# Weak — favor defensive actions
		action_weights["recruit"] = action_weights.get("recruit", 0) + 3
		action_weights["defend"] = action_weights.get("defend", 0) + 2
		action_weights["raid"] = max(action_weights.get("raid", 0) - 2, 0)

	# Select an action (30% chance of doing something each day)
	if randf() > 0.3:
		return {}

	var total_weight = 0
	for w in action_weights.values():
		total_weight += w
	if total_weight <= 0:
		return {}

	var roll = randi() % total_weight
	var cumulative = 0
	for action_type in action_weights:
		cumulative += action_weights[action_type]
		if roll < cumulative:
			return {"type": action_type, "faction_id": faction.faction_id}

	return {}

func _default_action_weights(faction_type: String) -> Dictionary:
	match faction_type:
		"bandit":
			return {"raid": 4, "recruit": 2, "extort": 3, "scout": 2, "rest": 1}
		"trade_guild":
			return {"trade_deal": 4, "recruit": 1, "lobby": 3, "expand": 2, "rest": 1}
		"military":
			return {"patrol": 3, "train": 2, "recruit": 2, "defend": 2, "raid": 1}
		"government":
			return {"legislate": 3, "tax": 2, "patrol": 2, "diplomacy": 2, "rest": 1}
		"civilian":
			return {"trade_deal": 2, "celebrate": 2, "petition": 2, "rest": 3}
		_:
			return {"rest": 3, "recruit": 1, "trade_deal": 1}

func _apply_faction_action(faction: Dictionary, action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	var faction_id = faction.faction_id
	var base_location = faction.get("base_location", "")
	var settlement = settlements.get(base_location)

	var event: Dictionary = {
		"type": "faction_action",
		"faction_id": faction_id,
		"faction_name": faction.display_name,
		"action": action_type,
		"settlement": base_location,
	}

	match action_type:
		"raid":
			# Bandits raid a trade route or settlement
			faction.resources = minf(faction.resources + randf_range(3.0, 8.0), 100.0)
			faction.strength = maxf(faction.strength - 1.0, 0.0)  # Raids cost manpower

			# Affect a random connected route
			var trade_mgr = get_node_or_null("/root/TradeRouteManager")
			if trade_mgr:
				var routes = trade_mgr.get_routes_for_settlement(base_location)
				if not routes.is_empty():
					var target_route = routes[randi() % routes.size()]
					trade_mgr.adjust_safety(target_route.route_id, -randf_range(0.05, 0.15),
						"%s raided the route" % faction.display_name)

			# Affect target settlement safety
			var targets = _get_faction_targets(faction)
			if not targets.is_empty():
				var target = targets[randi() % targets.size()]
				if settlements.has(target):
					settlements[target].adjust_safety(-0.05, "%s bandits struck" % faction.display_name)

			event["description"] = "%s conducted a raid" % faction.display_name

		"recruit":
			faction.strength = minf(faction.strength + randf_range(2.0, 5.0), 100.0)
			faction.resources = maxf(faction.resources - 3.0, 0.0)
			event["description"] = "%s recruited new members" % faction.display_name

		"extort":
			faction.resources = minf(faction.resources + randf_range(2.0, 6.0), 100.0)
			if settlement:
				settlement.adjust_morale(-0.05, "Extortion by %s" % faction.display_name)
			event["description"] = "%s extorted local businesses" % faction.display_name

		"trade_deal":
			faction.resources = minf(faction.resources + randf_range(1.0, 4.0), 100.0)
			if settlement:
				settlement.prosperity = minf(settlement.prosperity + 0.01, 1.0)
			event["description"] = "%s brokered a trade deal" % faction.display_name

		"patrol":
			if settlement:
				settlement.adjust_safety(0.03, "%s patrols the area" % faction.display_name)
			faction.resources = maxf(faction.resources - 1.0, 0.0)
			event["description"] = "%s patrolled the region" % faction.display_name

		"train":
			faction.strength = minf(faction.strength + 1.5, 100.0)
			faction.morale = minf(faction.morale + 1.0, 100.0)
			event["description"] = "%s conducted training exercises" % faction.display_name

		"defend":
			if settlement:
				settlement.adjust_safety(0.05, "%s fortified defenses" % faction.display_name)
			faction.resources = maxf(faction.resources - 2.0, 0.0)
			event["description"] = "%s strengthened defenses" % faction.display_name

		"expand":
			faction.strength = maxf(faction.strength - 2.0, 0.0)
			faction.resources = maxf(faction.resources - 5.0, 0.0)
			event["description"] = "%s expanded their influence" % faction.display_name

		"legislate":
			if settlement:
				settlement.tax_rate = clampf(settlement.tax_rate + randf_range(-0.01, 0.02), 0.0, 0.3)
			event["description"] = "%s passed new legislation" % faction.display_name

		"tax":
			faction.resources = minf(faction.resources + randf_range(3.0, 7.0), 100.0)
			if settlement:
				settlement.adjust_morale(-0.03, "Tax collection by %s" % faction.display_name)
			event["description"] = "%s collected taxes" % faction.display_name

		"celebrate":
			if settlement:
				settlement.adjust_morale(0.08, "Festival organized by %s" % faction.display_name)
			faction.resources = maxf(faction.resources - 3.0, 0.0)
			event["description"] = "%s organized a celebration" % faction.display_name

		"diplomacy":
			# Improve relations with a random other faction
			var other_factions = faction.get("disposition", {}).keys()
			if not other_factions.is_empty():
				var target_faction = other_factions[randi() % other_factions.size()]
				faction.disposition[target_faction] = minf(
					faction.disposition.get(target_faction, 0.0) + 5.0, 100.0)
			event["description"] = "%s engaged in diplomatic efforts" % faction.display_name

		"lobby":
			event["description"] = "%s lobbied for favorable policies" % faction.display_name

		"scout":
			event["description"] = "%s sent scouts to gather intelligence" % faction.display_name

		"rest":
			faction.morale = minf(faction.morale + 2.0, 100.0)
			event["description"] = "%s rested and regrouped" % faction.display_name

		"petition":
			event["description"] = "%s petitioned the authorities" % faction.display_name

		_:
			event["description"] = "%s took action: %s" % [faction.display_name, action_type]

	# Update faction reputations in WorldState
	WorldState.faction_reputations[faction_id] = {
		"strength": faction.strength,
		"morale": faction.morale,
		"resources": faction.resources,
	}

	return event

func _get_faction_targets(faction: Dictionary) -> Array:
	var targets: Array = []
	var dispositions: Dictionary = faction.get("disposition", {})
	for other_faction in dispositions:
		if dispositions[other_faction] < -30.0:
			# Find settlements associated with enemy factions
			for f_id in faction_profiles:
				if f_id == other_faction:
					var loc = faction_profiles[f_id].get("base_location", "")
					if loc != "" and loc != faction.base_location:
						targets.append(loc)
	return targets

# =============================================================================
# OFF-SCREEN EVENT GENERATION
# =============================================================================

func _generate_off_screen_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# Random world events (10% chance per day for each category)

	# Weather / natural events
	if randf() < 0.08:
		var weather_events = [
			{"description": "A heavy storm battered the region", "effect": "storm",
			 "settlements": ["thornhaven", "millhaven"]},
			{"description": "An unusually warm spell boosted crop growth", "effect": "good_harvest",
			 "settlements": ["thornhaven"]},
			{"description": "Flooding damaged farmlands near Millhaven", "effect": "flood",
			 "settlements": ["millhaven"]},
		]
		var weather = weather_events[randi() % weather_events.size()]
		events.append({"type": "natural_event", "description": weather.description,
			"settlement": weather.settlements[0], "data": weather})

		# Apply effects
		match weather.effect:
			"storm":
				for s_id in weather.settlements:
					if settlements.has(s_id):
						settlements[s_id].adjust_morale(-0.05, "Storm damage")
						var trade_mgr = get_node_or_null("/root/TradeRouteManager")
						if trade_mgr:
							var routes = trade_mgr.get_routes_for_settlement(s_id)
							for route in routes:
								trade_mgr.adjust_safety(route.route_id, -0.05, "Storm damage")
			"good_harvest":
				for s_id in weather.settlements:
					if settlements.has(s_id):
						settlements[s_id].add_supply("grain", 10.0)
						settlements[s_id].adjust_morale(0.05, "Good harvest")
			"flood":
				for s_id in weather.settlements:
					if settlements.has(s_id):
						settlements[s_id].remove_supply("grain", 5.0)
						settlements[s_id].adjust_morale(-0.08, "Flood damage")

	# Political events (from The Capital)
	if randf() < 0.05:
		var political = [
			"The Crown has announced a new tax on trade goods",
			"A royal envoy is traveling through the region",
			"The Crown has offered a bounty on bandit leaders",
			"New trade regulations have been announced from the capital",
		]
		var desc = political[randi() % political.size()]
		events.append({"type": "political_event", "description": desc,
			"settlement": "the_capital"})

	# Traveling NPCs / merchants
	if randf() < 0.1:
		var travelers = [
			"A traveling merchant arrived with exotic wares",
			"A wandering bard is performing in the square",
			"A group of pilgrims passed through heading north",
			"A mysterious stranger was seen asking about the old ruins",
		]
		var target_settlements = ["thornhaven", "millhaven"]
		var target = target_settlements[randi() % target_settlements.size()]
		var desc = travelers[randi() % travelers.size()]
		events.append({"type": "traveler_event", "description": desc,
			"settlement": target})

		if settlements.has(target):
			settlements[target].add_event(desc)

	return events

# =============================================================================
# EVENT -> INFOPACKET PROPAGATION
# =============================================================================

func _propagate_events_as_info(events: Array):
	if not GossipManager:
		return

	for event in events:
		var desc = event.get("description", "")
		if desc == "":
			continue

		var event_type = event.get("type", "")
		var settlement_id = event.get("settlement", "")
		var category = "rumor"
		var confidence = 0.7

		match event_type:
			"faction_action":
				category = "rumor"
				confidence = 0.6
			"tier2_action":
				category = "rumor"
				confidence = 0.65
			"natural_event":
				category = "fact"
				confidence = 0.9
			"political_event":
				category = "rumor"
				confidence = 0.5  # Distant political news is vague
			"trade_shipment":
				category = "fact"
				confidence = 0.85
			"traveler_event":
				category = "gossip"
				confidence = 0.7

		# Create info packet and give to NPCs in the relevant settlement
		var packet = GossipManager.create_info(
			desc, "system", category, confidence,
			[], [settlement_id, event_type]
		)

		# Give to Tier 0 NPCs in the settlement
		if settlements.has(settlement_id):
			var s = settlements[settlement_id]
			for npc_id in s.tier0_npcs:
				GossipManager.give_info_to_npc(npc_id, packet)

			# Give to some Tier 1 NPCs based on gossip tendency
			var template_gen = get_node_or_null("/root/NPCTemplateGenerator")
			if template_gen:
				for npc_id in s.tier1_npcs:
					var profile = template_gen.get_profile(npc_id)
					if not profile.is_empty():
						var gossip = profile.get("gossip_tendency", 0.3)
						if randf() < gossip:
							template_gen.give_rumor(npc_id, packet.id)

# =============================================================================
# PUBLIC API
# =============================================================================

## Get a settlement by ID
func get_settlement(settlement_id: String) -> Settlement:
	return settlements.get(settlement_id)

## Get a Tier 2 profile
func get_tier2_profile(npc_id: String) -> Dictionary:
	return tier2_profiles.get(npc_id, {})

## Get a faction profile
func get_faction(faction_id: String) -> Dictionary:
	return faction_profiles.get(faction_id, {})

## Get all factions
func get_all_factions() -> Dictionary:
	return faction_profiles

## Get events for a settlement from recent history
func get_settlement_events(settlement_id: String, max_count: int = 10) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in event_history:
		if event.get("settlement", "") == settlement_id:
			result.append(event)
			if result.size() >= max_count:
				break
	return result

## Debug: print world state summary
func debug_print_world():
	print("\n[WorldSimulation] === World State Summary ===")
	print("  Day: %d" % _current_day)
	print("\n  SETTLEMENTS:")
	for s_id in settlements:
		var s = settlements[s_id]
		print("    %s (%s) — pop: %d, safety: %.2f, morale: %.2f, prosperity: %.2f" % [
			s.display_name, ["village", "town", "bandit_camp", "city"][s.size],
			s.population, s.safety, s.morale, s.prosperity])
		print("      T0 NPCs: %d, T1 NPCs: %d, T2 NPCs: %d" % [
			s.tier0_npcs.size(), s.tier1_npcs.size(), s.tier2_npcs.size()])

	print("\n  FACTIONS:")
	for f_id in faction_profiles:
		var f = faction_profiles[f_id]
		print("    %s — str: %.0f, morale: %.0f, resources: %.0f" % [
			f.display_name, f.strength, f.morale, f.resources])

	print("\n  TIER 2 NPCs:")
	for npc_id in tier2_profiles:
		var p = tier2_profiles[npc_id]
		print("    %s (%s) — agenda: %s (%.0f%%)" % [
			p.display_name, p.title, p.current_agenda, p.agenda_progress * 100])
	print("")

# =============================================================================
# INITIALIZATION — Define the 4 settlements, Tier 2 NPCs, and factions
# =============================================================================

func _register_settlements():
	# 1. Thornhaven (Village) — the player's starting base
	settlements["thornhaven"] = Settlement.create({
		"settlement_id": "thornhaven",
		"display_name": "Thornhaven",
		"size": Settlement.SettlementSize.VILLAGE,
		"population": 150,
		"culture": "thornhaven",
		"description": "A small trading village on the northern trade route",
		"produces": {
			"grain": 4.0,
			"timber": 2.0,
			"herbs": 1.5,
		},
		"demands": {
			"iron_ore": 2.0,
			"leather": 1.5,
			"grain": 2.0,
			"ale": 1.0,
		},
		"tax_rate": 0.05,
		"safety": 0.7,
		"morale": 0.55,
		"prosperity": 0.45,
		"tier0_npcs": [
			"gregor_merchant_001", "elena_daughter_001", "mira_tavern_keeper_001",
			"bjorn_blacksmith_001", "aldric_peacekeeper_001", "elder_mathias_001",
			"varn_bandit_001",
		],
		"establishments": {
			"gregor_shop": {"name": "Gregor's General Goods", "type": "shop", "owner": "gregor_merchant_001"},
			"tavern": {"name": "The Rusty Nail", "type": "tavern", "owner": "mira_tavern_keeper_001"},
			"blacksmith": {"name": "Bjorn's Forge", "type": "blacksmith", "owner": "bjorn_blacksmith_001"},
		},
	})

	# 2. Millhaven (Town) — larger trade hub
	settlements["millhaven"] = Settlement.create({
		"settlement_id": "millhaven",
		"display_name": "Millhaven",
		"size": Settlement.SettlementSize.TOWN,
		"population": 600,
		"culture": "millhaven",
		"description": "A prosperous trade town at the crossroads of the northern and eastern routes",
		"produces": {
			"iron_ore": 5.0,
			"leather": 3.0,
			"ale": 4.0,
		},
		"demands": {
			"grain": 5.0,
			"timber": 3.0,
			"herbs": 2.0,
		},
		"tax_rate": 0.08,
		"safety": 0.85,
		"morale": 0.65,
		"prosperity": 0.7,
		"establishments": {
			"millhaven_market": {"name": "Millhaven Grand Market", "type": "market", "owner": ""},
			"millhaven_tavern": {"name": "The Silver Tankard", "type": "tavern", "owner": ""},
			"millhaven_guild_hall": {"name": "Merchant Guild Hall", "type": "guild_hall", "owner": ""},
			"millhaven_smithy": {"name": "Ironmont Forge", "type": "blacksmith", "owner": ""},
			"millhaven_inn": {"name": "The Weary Wanderer Inn", "type": "inn", "owner": ""},
		},
	})

	# 3. Iron Hollow (Bandit Camp) — hostile, black market
	settlements["iron_hollow"] = Settlement.create({
		"settlement_id": "iron_hollow",
		"display_name": "Iron Hollow",
		"size": Settlement.SettlementSize.BANDIT_CAMP,
		"population": 45,
		"culture": "iron_hollow",
		"description": "A hidden bandit encampment in the rocky hills, home to the Iron Hollow Gang",
		"produces": {
			"leather": 1.0,   # Hunting
			"iron_ore": 0.5,  # Scavenged
		},
		"demands": {
			"grain": 2.0,
			"ale": 2.0,
			"iron_ore": 1.5,
		},
		"tax_rate": 0.0,
		"safety": 0.3,
		"morale": 0.5,
		"prosperity": 0.35,
		"establishments": {
			"hollow_fence": {"name": "The Rat's Nest", "type": "black_market", "owner": ""},
			"hollow_camp": {"name": "Iron Hollow Camp", "type": "camp", "owner": ""},
		},
	})

	# 4. The Capital (City) — distant political power
	settlements["the_capital"] = Settlement.create({
		"settlement_id": "the_capital",
		"display_name": "The Capital",
		"size": Settlement.SettlementSize.CITY,
		"population": 5000,
		"culture": "the_capital",
		"description": "The seat of royal power, a great walled city far to the south",
		"produces": {
			"iron_ore": 8.0,
			"leather": 5.0,
			"grain": 3.0,
			"ale": 6.0,
			"timber": 4.0,
		},
		"demands": {
			"grain": 10.0,
			"timber": 6.0,
			"herbs": 4.0,
			"iron_ore": 5.0,
			"leather": 4.0,
		},
		"tax_rate": 0.12,
		"safety": 0.95,
		"morale": 0.6,
		"prosperity": 0.8,
		"establishments": {
			"royal_palace": {"name": "The Royal Palace", "type": "palace", "owner": ""},
			"capital_market": {"name": "The Grand Bazaar", "type": "market", "owner": ""},
			"capital_guild": {"name": "Imperial Merchant Guild", "type": "guild_hall", "owner": ""},
		},
	})

	# Register trade route connections
	settlements["thornhaven"].trade_route_ids = ["northern_trade_road", "hollow_path"]
	settlements["millhaven"].trade_route_ids = ["northern_trade_road", "kings_highway", "smugglers_trail"]
	settlements["iron_hollow"].trade_route_ids = ["hollow_path", "smugglers_trail"]
	settlements["the_capital"].trade_route_ids = ["kings_highway"]

	# Register local story threads
	settlements["thornhaven"].local_threads = [
		"merchants_bargain", "grieving_widow", "daughters_awakening",
		"failing_watch", "unwitting_accomplice", "paralyzed_council",
	]
	settlements["iron_hollow"].local_threads = ["bandit_expansion"]

func _register_tier2_npcs():
	tier2_profiles["mayor_aldwin_millhaven"] = {
		"npc_id": "mayor_aldwin_millhaven",
		"display_name": "Mayor Aldwin",
		"title": "Mayor of Millhaven",
		"location": "millhaven",
		"faction": "millhaven_council",
		"tendencies": ["cautious_diplomat", "tax_raiser", "anti_bandit"],
		"current_agenda": "increase_trade",
		"agenda_progress": 0.3,
		"relationships_abstract": {"iron_hollow_gang": -60.0, "thornhaven_council": 40.0, "the_crown": 50.0, "merchant_guild": 60.0},
		"last_action_tick": 0,
	}

	tier2_profiles["captain_reeve_millhaven"] = {
		"npc_id": "captain_reeve_millhaven",
		"display_name": "Captain Reeve",
		"title": "Captain of the Millhaven Guard",
		"location": "millhaven",
		"faction": "millhaven_council",
		"tendencies": ["anti_bandit", "aggressive_expansionist"],
		"current_agenda": "patrol_roads",
		"agenda_progress": 0.1,
		"relationships_abstract": {"iron_hollow_gang": -80.0, "thornhaven_council": 30.0},
		"last_action_tick": 0,
	}

	tier2_profiles["guildmaster_harlow"] = {
		"npc_id": "guildmaster_harlow",
		"display_name": "Guildmaster Harlow",
		"title": "Head of the Merchant Guild",
		"location": "millhaven",
		"faction": "merchant_guild",
		"tendencies": ["greedy", "cautious_diplomat", "trade_focused"],
		"current_agenda": "accumulate_wealth",
		"agenda_progress": 0.5,
		"relationships_abstract": {"millhaven_council": 50.0, "the_crown": 30.0, "iron_hollow_gang": -20.0},
		"last_action_tick": 0,
	}

	tier2_profiles["warlord_krag_iron_hollow"] = {
		"npc_id": "warlord_krag_iron_hollow",
		"display_name": "Warlord Krag",
		"title": "Leader of the Iron Hollow Gang",
		"location": "iron_hollow",
		"faction": "iron_hollow_gang",
		"tendencies": ["aggressive_expansionist", "greedy", "cunning"],
		"current_agenda": "expand_territory",
		"agenda_progress": 0.4,
		"relationships_abstract": {"millhaven_council": -50.0, "thornhaven_council": -40.0, "the_crown": -70.0, "merchant_guild": -10.0},
		"last_action_tick": 0,
	}

	tier2_profiles["lieutenant_vera_iron_hollow"] = {
		"npc_id": "lieutenant_vera_iron_hollow",
		"display_name": "Lieutenant Vera",
		"title": "Krag's Second-in-Command",
		"location": "iron_hollow",
		"faction": "iron_hollow_gang",
		"tendencies": ["cunning", "cautious_diplomat"],
		"current_agenda": "gather_intelligence",
		"agenda_progress": 0.2,
		"relationships_abstract": {"millhaven_council": -30.0, "thornhaven_council": -20.0},
		"last_action_tick": 0,
	}

	tier2_profiles["royal_magistrate_pemberton"] = {
		"npc_id": "royal_magistrate_pemberton",
		"display_name": "Magistrate Pemberton",
		"title": "Royal Magistrate of the Northern Region",
		"location": "the_capital",
		"faction": "the_crown",
		"tendencies": ["bureaucratic", "cautious_diplomat", "tax_raiser"],
		"current_agenda": "collect_debts",
		"agenda_progress": 0.6,
		"relationships_abstract": {"millhaven_council": 40.0, "iron_hollow_gang": -90.0, "merchant_guild": 20.0},
		"last_action_tick": 0,
	}

	tier2_profiles["traveling_merchant_sable"] = {
		"npc_id": "traveling_merchant_sable",
		"display_name": "Sable",
		"title": "Traveling Merchant",
		"location": "millhaven",
		"faction": "merchant_guild",
		"tendencies": ["trade_focused", "well_traveled", "cautious_diplomat"],
		"current_agenda": "increase_trade",
		"agenda_progress": 0.15,
		"relationships_abstract": {"thornhaven_council": 30.0, "millhaven_council": 45.0},
		"last_action_tick": 0,
	}

	# Register Tier 2 NPCs in their settlements
	for npc_id in tier2_profiles:
		var loc = tier2_profiles[npc_id].location
		if settlements.has(loc):
			settlements[loc].add_npc(npc_id, 2)

func _register_factions():
	faction_profiles["iron_hollow_gang"] = {
		"faction_id": "iron_hollow_gang",
		"display_name": "The Iron Hollow Gang",
		"type": "bandit",
		"base_location": "iron_hollow",
		"strength": 55.0,
		"morale": 60.0,
		"resources": 45.0,
		"goals": ["control_trade_route", "extort_thornhaven", "expand_territory"],
		"disposition": {
			"millhaven_council": -50.0,
			"thornhaven_council": -40.0,
			"the_crown": -70.0,
			"merchant_guild": -10.0,
		},
		"event_weights": {"raid": 4, "recruit": 2, "extort": 3, "scout": 2, "rest": 1},
		"active_effects": [],
	}

	faction_profiles["millhaven_council"] = {
		"faction_id": "millhaven_council",
		"display_name": "Millhaven Town Council",
		"type": "government",
		"base_location": "millhaven",
		"strength": 40.0,
		"morale": 55.0,
		"resources": 65.0,
		"goals": ["maintain_trade_routes", "defeat_bandits", "collect_taxes"],
		"disposition": {
			"iron_hollow_gang": -60.0,
			"thornhaven_council": 40.0,
			"the_crown": 50.0,
			"merchant_guild": 60.0,
		},
		"event_weights": {"legislate": 3, "tax": 2, "patrol": 2, "diplomacy": 2, "rest": 1},
		"active_effects": [],
	}

	faction_profiles["the_crown"] = {
		"faction_id": "the_crown",
		"display_name": "The Crown",
		"type": "government",
		"base_location": "the_capital",
		"strength": 90.0,
		"morale": 65.0,
		"resources": 85.0,
		"goals": ["maintain_order", "collect_taxes", "expand_influence"],
		"disposition": {
			"iron_hollow_gang": -80.0,
			"millhaven_council": 40.0,
			"thornhaven_council": 20.0,
			"merchant_guild": 30.0,
		},
		"event_weights": {"legislate": 3, "tax": 3, "patrol": 2, "diplomacy": 3, "rest": 1},
		"active_effects": [],
	}

	faction_profiles["merchant_guild"] = {
		"faction_id": "merchant_guild",
		"display_name": "The Merchant Guild",
		"type": "trade_guild",
		"base_location": "millhaven",
		"strength": 25.0,
		"morale": 70.0,
		"resources": 75.0,
		"goals": ["monopolize_trade", "protect_trade_routes", "increase_profits"],
		"disposition": {
			"iron_hollow_gang": -30.0,
			"millhaven_council": 50.0,
			"the_crown": 30.0,
			"thornhaven_council": 35.0,
		},
		"event_weights": {"trade_deal": 4, "lobby": 3, "expand": 2, "recruit": 1, "rest": 1},
		"active_effects": [],
	}

	faction_profiles["thornhaven_council"] = {
		"faction_id": "thornhaven_council",
		"display_name": "Thornhaven Village Council",
		"type": "civilian",
		"base_location": "thornhaven",
		"strength": 15.0,
		"morale": 45.0,
		"resources": 30.0,
		"goals": ["protect_village", "maintain_trade", "resist_bandits"],
		"disposition": {
			"iron_hollow_gang": -60.0,
			"millhaven_council": 40.0,
			"the_crown": 20.0,
			"merchant_guild": 30.0,
		},
		"event_weights": {"trade_deal": 2, "petition": 3, "celebrate": 2, "rest": 3},
		"active_effects": [],
	}

func _populate_settlements():
	var template_gen = get_node_or_null("/root/NPCTemplateGenerator")
	if not template_gen:
		push_warning("[WorldSimulation] NPCTemplateGenerator not found — skipping Tier 1 generation")
		return

	# Generate Tier 1 NPCs for each settlement
	for s_id in settlements:
		var s = settlements[s_id]
		var size_name = ""
		match s.size:
			Settlement.SettlementSize.VILLAGE: size_name = "village"
			Settlement.SettlementSize.TOWN: size_name = "town"
			Settlement.SettlementSize.BANDIT_CAMP: size_name = "bandit_camp"
			Settlement.SettlementSize.CITY: size_name = "city"

		var generated = template_gen.generate_settlement_npcs(s_id, size_name)
		for profile in generated:
			s.add_npc(profile.npc_id, 1)
