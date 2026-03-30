extends RefCounted
class_name Settlement
## Settlement - Data structure representing a settlement in the game world
##
## Tracks local economy, resident NPCs, trade routes, story threads,
## and settlement-wide modifiers. Each settlement produces and demands
## specific commodities, creating the foundation for inter-settlement trade.

## Settlement size categories
enum SettlementSize {
	VILLAGE,     # 50-200 people, 1-3 establishments
	TOWN,        # 200-1000 people, 5-10 establishments
	BANDIT_CAMP, # 20-80 people, informal structures
	CITY,        # 1000+ people, many districts and establishments
}

# =============================================================================
# IDENTITY
# =============================================================================

## Unique settlement identifier (e.g. "thornhaven", "millhaven")
var settlement_id: String = ""
## Display name
var display_name: String = ""
## Settlement size category
var size: SettlementSize = SettlementSize.VILLAGE
## Base population count
var population: int = 100
## Cultural group (determines name pools, architecture, etc.)
var culture: String = "northern"
## Short description
var description: String = ""

# =============================================================================
# ECONOMY
# =============================================================================

## Commodities this settlement produces locally {item_id: production_rate_per_day}
var produces: Dictionary = {}
## Commodities this settlement demands {item_id: demand_per_day}
var demands: Dictionary = {}
## Current local prices {item_id: price_multiplier} (1.0 = base price)
var local_prices: Dictionary = {}
## Current supply levels {item_id: float} (units available)
var supply_levels: Dictionary = {}
## Tax rate applied to all transactions (0.0 to 0.5)
var tax_rate: float = 0.05

# =============================================================================
# RESIDENTS
# =============================================================================

## Tier 0 NPC IDs residing here
var tier0_npcs: Array[String] = []
## Tier 1 NPC IDs residing here
var tier1_npcs: Array[String] = []
## Tier 2 NPC IDs associated with this location
var tier2_npcs: Array[String] = []

# =============================================================================
# CONNECTIONS
# =============================================================================

## Trade route IDs connecting to other settlements
var trade_route_ids: Array[String] = []

# =============================================================================
# NARRATIVE
# =============================================================================

## Local story thread IDs
var local_threads: Array[String] = []
## Recent local events (for NPC context)
var recent_events: Array[String] = []

# =============================================================================
# MODIFIERS
# =============================================================================

## Safety level (0.0 = very dangerous, 1.0 = very safe)
var safety: float = 0.8
## Morale of the populace (0.0 = despair, 1.0 = jubilant)
var morale: float = 0.6
## Prosperity indicator (0.0 = impoverished, 1.0 = thriving)
var prosperity: float = 0.5

# =============================================================================
# ESTABLISHMENTS
# =============================================================================

## Named establishments {est_id: {name, type, owner_npc_id, description}}
var establishments: Dictionary = {}

# =============================================================================
# METHODS
# =============================================================================

## Create a settlement with initial data
static func create(data: Dictionary) -> Settlement:
	var s = Settlement.new()
	s.settlement_id = data.get("settlement_id", "")
	s.display_name = data.get("display_name", s.settlement_id.capitalize())
	s.size = data.get("size", SettlementSize.VILLAGE)
	s.population = data.get("population", 100)
	s.culture = data.get("culture", "northern")
	s.description = data.get("description", "")
	s.produces = data.get("produces", {})
	s.demands = data.get("demands", {})
	s.tax_rate = data.get("tax_rate", 0.05)
	s.safety = data.get("safety", 0.8)
	s.morale = data.get("morale", 0.6)
	s.prosperity = data.get("prosperity", 0.5)
	s.tier0_npcs = data.get("tier0_npcs", [])
	s.establishments = data.get("establishments", {})

	# Initialize supply levels from production
	for item_id in s.produces:
		s.supply_levels[item_id] = s.produces[item_id] * 5.0  # 5 days of stock
	# Initialize prices at base
	for item_id in s.produces:
		s.local_prices[item_id] = 0.9  # Locally produced = slightly cheap
	for item_id in s.demands:
		if item_id not in s.local_prices:
			s.local_prices[item_id] = 1.2  # Imported/demanded = slightly expensive

	return s

## Update economy for one game-day tick
func tick_economy():
	# Local production adds to supply
	for item_id in produces:
		supply_levels[item_id] = supply_levels.get(item_id, 0.0) + produces[item_id]

	# Local demand consumes supply
	for item_id in demands:
		var consumed = min(demands[item_id], supply_levels.get(item_id, 0.0))
		supply_levels[item_id] = supply_levels.get(item_id, 0.0) - consumed

	# Update prices based on supply vs demand
	_recalculate_prices()

	# Clamp supply (no infinite accumulation)
	for item_id in supply_levels:
		supply_levels[item_id] = clampf(supply_levels[item_id], 0.0, 1000.0)

## Add supply (from trade route imports)
func add_supply(item_id: String, amount: float):
	supply_levels[item_id] = supply_levels.get(item_id, 0.0) + amount

## Remove supply (from trade route exports or events)
func remove_supply(item_id: String, amount: float):
	supply_levels[item_id] = max(supply_levels.get(item_id, 0.0) - amount, 0.0)

## Get the current price multiplier for an item
func get_price_multiplier(item_id: String) -> float:
	return local_prices.get(item_id, 1.0)

## Recalculate prices based on supply/demand balance
func _recalculate_prices():
	var all_items: Dictionary = {}
	for item_id in produces:
		all_items[item_id] = true
	for item_id in demands:
		all_items[item_id] = true

	for item_id in all_items:
		var supply = supply_levels.get(item_id, 0.0)
		var demand = demands.get(item_id, 0.0)
		var production = produces.get(item_id, 0.0)

		var price_mult = 1.0

		if demand > 0.01:
			# Supply/demand ratio drives price
			var ratio = supply / (demand * 5.0)  # Compare supply to 5 days of demand
			if ratio < 0.5:
				price_mult = 1.5 + (0.5 - ratio) * 2.0  # Scarcity: prices up to 2.5x
			elif ratio < 1.0:
				price_mult = 1.0 + (1.0 - ratio) * 0.5  # Slight scarcity
			elif ratio > 2.0:
				price_mult = 0.7  # Glut: prices drop
			else:
				price_mult = 1.0 - (ratio - 1.0) * 0.15  # Mild oversupply
		elif production > 0:
			# Only produced, not demanded locally — export goods, cheap locally
			price_mult = 0.8

		# Apply safety and prosperity modifiers
		if safety < 0.5:
			price_mult *= 1.0 + (0.5 - safety) * 0.4  # Danger increases prices
		if prosperity > 0.7:
			price_mult *= 0.95  # Prosperous = slightly cheaper

		local_prices[item_id] = clampf(price_mult, 0.3, 3.0)

## Apply a morale change (clamped 0-1)
func adjust_morale(delta: float, reason: String = ""):
	var old = morale
	morale = clampf(morale + delta, 0.0, 1.0)
	if reason != "" and abs(delta) > 0.05:
		recent_events.append("%s (morale %s)" % [reason, "rose" if delta > 0 else "fell"])
		if recent_events.size() > 20:
			recent_events.pop_front()

## Apply a safety change
func adjust_safety(delta: float, reason: String = ""):
	var old = safety
	safety = clampf(safety + delta, 0.0, 1.0)
	if reason != "" and abs(delta) > 0.05:
		recent_events.append("%s (safety %s)" % [reason, "improved" if delta > 0 else "worsened"])
		if recent_events.size() > 20:
			recent_events.pop_front()

## Add an NPC to this settlement
func add_npc(npc_id: String, tier: int):
	match tier:
		0:
			if npc_id not in tier0_npcs:
				tier0_npcs.append(npc_id)
		1:
			if npc_id not in tier1_npcs:
				tier1_npcs.append(npc_id)
		2:
			if npc_id not in tier2_npcs:
				tier2_npcs.append(npc_id)

## Remove an NPC from this settlement
func remove_npc(npc_id: String):
	tier0_npcs.erase(npc_id)
	tier1_npcs.erase(npc_id)
	tier2_npcs.erase(npc_id)

## Get total NPC count
func get_npc_count() -> int:
	return tier0_npcs.size() + tier1_npcs.size()

## Add a recent event for NPC context
func add_event(event_description: String):
	recent_events.push_front(event_description)
	if recent_events.size() > 20:
		recent_events.pop_back()

## Serialize to dictionary
func to_dict() -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"display_name": display_name,
		"size": size,
		"population": population,
		"culture": culture,
		"description": description,
		"produces": produces,
		"demands": demands,
		"local_prices": local_prices,
		"supply_levels": supply_levels,
		"tax_rate": tax_rate,
		"safety": safety,
		"morale": morale,
		"prosperity": prosperity,
		"tier0_npcs": tier0_npcs,
		"tier1_npcs": tier1_npcs,
		"tier2_npcs": tier2_npcs,
		"trade_route_ids": trade_route_ids,
		"local_threads": local_threads,
		"recent_events": recent_events,
		"establishments": establishments,
	}

## Deserialize from dictionary
static func from_dict(data: Dictionary) -> Settlement:
	var s = Settlement.create(data)
	s.local_prices = data.get("local_prices", s.local_prices)
	s.supply_levels = data.get("supply_levels", s.supply_levels)
	s.tier1_npcs = data.get("tier1_npcs", [])
	s.tier2_npcs = data.get("tier2_npcs", [])
	s.trade_route_ids = data.get("trade_route_ids", [])
	s.local_threads = data.get("local_threads", [])
	s.recent_events = data.get("recent_events", [])
	return s
