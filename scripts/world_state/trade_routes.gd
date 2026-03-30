extends Node
class_name TradeRouteManager
## TradeRouteManager - Manages trade routes connecting settlements
##
## Trade routes define how goods flow between settlements. Each route has a
## safety rating, traffic volume, travel time, and commodity list.
## When bandits raid, safety drops, supply decreases at destinations, and prices rise.
## When trade flourishes, supply increases and prices stabilize.

signal route_safety_changed(route_id: String, old_safety: float, new_safety: float)
signal route_disrupted(route_id: String, reason: String)
signal route_restored(route_id: String)
signal trade_shipment_arrived(route_id: String, destination: String, goods: Dictionary)

## All trade routes {route_id: TradeRoute data}
var routes: Dictionary = {}

func _ready():
	_register_default_routes()
	EventBus.world_flag_changed.connect(_on_flag_changed)
	print("[TradeRouteManager] Initialized with %d routes" % routes.size())

# =============================================================================
# TRADE ROUTE DATA STRUCTURE
# =============================================================================

## Register a trade route
func register_route(data: Dictionary):
	var id = data.get("route_id", "")
	if id == "":
		push_error("[TradeRouteManager] Route missing 'route_id'")
		return

	routes[id] = {
		"route_id": id,
		"display_name": data.get("display_name", id),
		"from_settlement": data.get("from_settlement", ""),
		"to_settlement": data.get("to_settlement", ""),
		"safety": data.get("safety", 0.8),
		"traffic_volume": data.get("traffic_volume", 1.0),  # 0.0-2.0 multiplier
		"travel_days": data.get("travel_days", 2),  # Game-days between settlements
		"commodities": data.get("commodities", {}),  # {item_id: base_flow_per_day}
		"is_disrupted": data.get("is_disrupted", false),
		"disruption_reason": "",
		"days_since_last_shipment": 0,
		"bandit_threat": data.get("bandit_threat", 0.0),  # 0.0-1.0
	}

## Get a route by ID
func get_route(route_id: String) -> Dictionary:
	return routes.get(route_id, {})

## Get all routes connecting to a settlement
func get_routes_for_settlement(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in routes:
		var r = routes[id]
		if r.from_settlement == settlement_id or r.to_settlement == settlement_id:
			result.append(r)
	return result

# =============================================================================
# SIMULATION — called each game-day by WorldSimulation
# =============================================================================

## Tick all routes for one game-day. Returns an array of shipment events.
func tick_routes(settlements: Dictionary) -> Array[Dictionary]:
	var shipment_events: Array[Dictionary] = []

	for route_id in routes:
		var route = routes[route_id]
		route.days_since_last_shipment += 1

		# Skip disrupted routes
		if route.is_disrupted:
			continue

		# Check if a shipment arrives (based on travel days)
		if route.days_since_last_shipment >= route.travel_days:
			route.days_since_last_shipment = 0

			# Calculate actual goods delivered
			var delivered_goods: Dictionary = {}
			for item_id in route.commodities:
				var base_flow = route.commodities[item_id]
				# Actual flow = base * traffic * safety factor
				var safety_factor = 0.5 + route.safety * 0.5  # At safety=0, half the goods get through
				var actual = base_flow * route.traffic_volume * safety_factor
				if actual > 0.01:
					delivered_goods[item_id] = actual

			if not delivered_goods.is_empty():
				# Deliver to destination settlement
				var dest = route.to_settlement
				if settlements.has(dest):
					for item_id in delivered_goods:
						settlements[dest].add_supply(item_id, delivered_goods[item_id])

				var event = {
					"route_id": route_id,
					"destination": dest,
					"goods": delivered_goods,
					"safety": route.safety,
				}
				shipment_events.append(event)
				trade_shipment_arrived.emit(route_id, dest, delivered_goods)

			# Bidirectional: also send goods back from destination
			var return_goods: Dictionary = {}
			var source = route.from_settlement
			if settlements.has(route.to_settlement):
				var dest_settlement: Settlement = settlements[route.to_settlement]
				for item_id in dest_settlement.produces:
					# Only export surplus
					var surplus = dest_settlement.supply_levels.get(item_id, 0.0) - dest_settlement.demands.get(item_id, 0.0) * 3.0
					if surplus > 0:
						var export_amount = min(surplus * 0.2, route.traffic_volume * 2.0) * (0.5 + route.safety * 0.5)
						if export_amount > 0.01:
							return_goods[item_id] = export_amount
							dest_settlement.remove_supply(item_id, export_amount)

			if not return_goods.is_empty() and settlements.has(source):
				for item_id in return_goods:
					settlements[source].add_supply(item_id, return_goods[item_id])

		# Natural safety recovery (very slow)
		if route.safety < 0.8 and route.bandit_threat < 0.3:
			route.safety = minf(route.safety + 0.02, 0.9)

		# Bandit raids reduce safety
		if route.bandit_threat > 0.5 and randf() < route.bandit_threat * 0.3:
			_raid_route(route_id)

	return shipment_events

# =============================================================================
# DISRUPTION / RESTORATION
# =============================================================================

## Disrupt a route (bandit raid, natural disaster, etc.)
func disrupt_route(route_id: String, reason: String):
	if not routes.has(route_id):
		return

	var route = routes[route_id]
	route.is_disrupted = true
	route.disruption_reason = reason
	route.traffic_volume = max(route.traffic_volume * 0.3, 0.0)

	route_disrupted.emit(route_id, reason)
	print("[TradeRouteManager] Route '%s' disrupted: %s" % [route.display_name, reason])

	# Create an InfoPacket about the disruption
	if GossipManager:
		GossipManager.create_info(
			"The %s trade route has been disrupted! %s" % [route.display_name, reason],
			"system",
			"warning",
			0.9,
			["trade_route_disrupted"],
			["trade", route.from_settlement, route.to_settlement]
		)

## Restore a disrupted route
func restore_route(route_id: String):
	if not routes.has(route_id):
		return

	var route = routes[route_id]
	route.is_disrupted = false
	route.disruption_reason = ""
	route.traffic_volume = max(route.traffic_volume, 0.5)  # Doesn't fully recover instantly

	route_restored.emit(route_id)
	print("[TradeRouteManager] Route '%s' restored" % route.display_name)

## Simulate a bandit raid on a route
func _raid_route(route_id: String):
	if not routes.has(route_id):
		return

	var route = routes[route_id]
	var old_safety = route.safety
	route.safety = maxf(route.safety - randf_range(0.05, 0.15), 0.1)
	route.traffic_volume = maxf(route.traffic_volume - 0.1, 0.1)

	if route.safety != old_safety:
		route_safety_changed.emit(route_id, old_safety, route.safety)

	# If safety drops too low, disrupt entirely
	if route.safety < 0.2:
		disrupt_route(route_id, "Bandit activity has made the route impassable")

## Set the bandit threat level on a route
func set_bandit_threat(route_id: String, threat: float):
	if routes.has(route_id):
		routes[route_id].bandit_threat = clampf(threat, 0.0, 1.0)

## Modify safety directly (from faction actions, player quests, etc.)
func adjust_safety(route_id: String, delta: float, reason: String = ""):
	if not routes.has(route_id):
		return

	var route = routes[route_id]
	var old_safety = route.safety
	route.safety = clampf(route.safety + delta, 0.0, 1.0)

	if route.safety != old_safety:
		route_safety_changed.emit(route_id, old_safety, route.safety)
		if reason != "":
			print("[TradeRouteManager] Route '%s' safety: %.2f -> %.2f (%s)" % [
				route.display_name, old_safety, route.safety, reason])

## Boost traffic (from merchant activity, festivals, etc.)
func adjust_traffic(route_id: String, delta: float):
	if routes.has(route_id):
		routes[route_id].traffic_volume = clampf(routes[route_id].traffic_volume + delta, 0.0, 3.0)

# =============================================================================
# REACT TO WORLD FLAGS
# =============================================================================

func _on_flag_changed(flag_name: String, _old_value, new_value):
	if not new_value:
		return

	match flag_name:
		"trade_route_disrupted":
			# Generic flag — disrupt the northern route
			disrupt_route("northern_trade_road", "Bandit ambushes have been reported")
		"resistance_forming":
			# Military activity increases traffic on safe routes
			for route_id in routes:
				if routes[route_id].safety > 0.6:
					adjust_traffic(route_id, 0.2)
		"iron_hollow_defeated":
			# Defeating bandits clears threats
			for route_id in routes:
				routes[route_id].bandit_threat = maxf(routes[route_id].bandit_threat - 0.3, 0.0)
				adjust_safety(route_id, 0.2, "Iron Hollow bandits cleared")
				if routes[route_id].is_disrupted:
					restore_route(route_id)

# =============================================================================
# DEFAULT ROUTES
# =============================================================================

func _register_default_routes():
	# Thornhaven <-> Millhaven (main trade road)
	register_route({
		"route_id": "northern_trade_road",
		"display_name": "Northern Trade Road",
		"from_settlement": "thornhaven",
		"to_settlement": "millhaven",
		"safety": 0.7,
		"traffic_volume": 1.0,
		"travel_days": 2,
		"commodities": {
			"grain": 3.0,
			"timber": 2.0,
			"herbs": 1.5,
			"iron_ore": 2.0,
			"leather": 1.0,
		},
		"bandit_threat": 0.3,
	})

	# Millhaven <-> The Capital (major highway)
	register_route({
		"route_id": "kings_highway",
		"display_name": "King's Highway",
		"from_settlement": "millhaven",
		"to_settlement": "the_capital",
		"safety": 0.9,
		"traffic_volume": 1.5,
		"travel_days": 5,
		"commodities": {
			"iron_ore": 4.0,
			"grain": 5.0,
			"leather": 3.0,
			"timber": 3.0,
		},
		"bandit_threat": 0.1,
	})

	# Thornhaven <-> Iron Hollow (dangerous path)
	register_route({
		"route_id": "hollow_path",
		"display_name": "Hollow Path",
		"from_settlement": "thornhaven",
		"to_settlement": "iron_hollow",
		"safety": 0.3,
		"traffic_volume": 0.3,
		"travel_days": 1,
		"commodities": {
			"iron_ore": 1.0,  # Stolen goods flowing back
			"leather": 0.5,
		},
		"bandit_threat": 0.7,
	})

	# Iron Hollow <-> Millhaven (smuggling route)
	register_route({
		"route_id": "smugglers_trail",
		"display_name": "Smuggler's Trail",
		"from_settlement": "iron_hollow",
		"to_settlement": "millhaven",
		"safety": 0.4,
		"traffic_volume": 0.4,
		"travel_days": 3,
		"commodities": {
			"iron_ore": 1.5,
			"leather": 1.0,
		},
		"bandit_threat": 0.5,
	})
