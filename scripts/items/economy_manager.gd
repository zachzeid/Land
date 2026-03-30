extends Node
class_name EconomyManager
## EconomyManager - Dynamic pricing and NPC trade management
##
## Prices are opinions, not facts. An NPC's asking price reflects their
## inventory, desperation, relationship with the buyer, and goals.
## NPCs own real inventories — there is no abstract "shop stock."
##
## Multi-settlement extension: tracks per-settlement supply/demand,
## connects to trade routes for supply flow, and generates economic
## ripple events when significant price changes occur.

signal price_changed(item_id: String, old_price: int, new_price: int, location: String)
signal trade_completed(buyer: String, seller: String, item_id: String, price: int)
signal economic_ripple(settlement_id: String, item_id: String, price_change: float, reason: String)

## NPC inventories {npc_id: Inventory}
var npc_inventories: Dictionary = {}

## Supply modifiers per settlement {location: {commodity: modifier}}
var supply_modifiers: Dictionary = {
	"thornhaven": {
		"iron_ore": 1.0,
		"grain": 1.0,
		"leather": 1.0,
		"timber": 1.0,
		"herbs": 1.0,
	}
}

## Price history for ripple detection {settlement_id: {item_id: [last_5_prices]}}
var _price_history: Dictionary = {}

## Threshold for triggering an economic ripple event (50% change)
const RIPPLE_THRESHOLD := 0.5

func _ready():
	# Listen for economic ripple effects
	EventBus.world_flag_changed.connect(_on_flag_changed)
	_setup_npc_inventories()

	# Deferred: sync supply modifiers with settlements once WorldSimulation is ready
	call_deferred("_sync_settlement_prices")
	print("[EconomyManager] Initialized")

## Calculate the price an NPC would charge for an item
func get_npc_price(npc_id: String, item: ItemData, is_buying: bool, buyer_trust: float = 0.0, settlement_id: String = "thornhaven") -> int:
	var base = item.get_sell_value()

	# Supply modifier (based on settlement economic state)
	var supply_mod = _get_supply_modifier(item, settlement_id)

	# Relationship discount/markup
	var trust_mod = 1.0
	if buyer_trust > 60:
		trust_mod = 0.85  # 15% discount for trusted friends
	elif buyer_trust > 30:
		trust_mod = 0.95  # 5% discount for acquaintances
	elif buyer_trust < -20:
		trust_mod = 1.2   # 20% markup for distrusted people

	# NPC personality markup
	var personality_mod = _get_personality_markup(npc_id)

	# Scarcity bonus (if NPC has few of this item)
	var scarcity_mod = 1.0
	if is_buying:
		# Player is buying from NPC
		var npc_inv = npc_inventories.get(npc_id)
		if npc_inv and npc_inv.has_item(item.item_id):
			var qty = npc_inv.items[item.item_id].quantity
			if qty <= 2:
				scarcity_mod = 1.3  # Scarce = expensive

	var final_price = int(base * supply_mod * trust_mod * personality_mod * scarcity_mod)

	if not is_buying:
		# Player is selling to NPC — NPC pays less
		final_price = int(final_price * 0.5)

	return max(final_price, 1)  # Minimum 1 silver

## Execute a trade
func execute_trade(buyer_id: String, seller_id: String, item_id: String, quantity: int = 1) -> Dictionary:
	var item_reg = get_node_or_null("/root/ItemRegistry")
	if item_reg == null:
		return {"success": false, "error": "ItemRegistry not found"}

	var item = item_reg.create_item(item_id)
	if item == null:
		return {"success": false, "error": "Unknown item: %s" % item_id}

	var seller_inv = _get_inventory(seller_id)
	var buyer_inv = _get_inventory(buyer_id)

	if seller_inv == null or buyer_inv == null:
		return {"success": false, "error": "Inventory not found"}

	if not seller_inv.has_item(item_id, quantity):
		return {"success": false, "error": "Seller doesn't have enough %s" % item.display_name}

	# Calculate price
	var buyer_trust = 0.0  # TODO: get from relationship system
	var price = get_npc_price(seller_id, item, true, buyer_trust) * quantity

	if not buyer_inv.spend_silver(price):
		return {"success": false, "error": "Not enough silver (%d needed)" % price}

	# Execute transfer
	seller_inv.remove_item(item_id, quantity)
	buyer_inv.add_item(item, quantity)
	seller_inv.earn_silver(price)

	trade_completed.emit(buyer_id, seller_id, item_id, price)
	print("[EconomyManager] Trade: %s bought %dx %s from %s for %d silver" % [
		buyer_id, quantity, item.display_name, seller_id, price])

	return {"success": true, "price": price}

## Get supply modifier for an item based on world state and settlement
func _get_supply_modifier(item: ItemData, settlement_id: String = "thornhaven") -> float:
	var base_mod = supply_modifiers.get(settlement_id, {}).get(item.item_id, 1.0)

	# Pull settlement price data from WorldSimulation if available
	var world_sim = get_node_or_null("/root/WorldSimulation")
	if world_sim:
		var settlement = world_sim.get_settlement(settlement_id)
		if settlement:
			var settlement_price = settlement.get_price_multiplier(item.item_id)
			base_mod *= settlement_price

	# Dynamic adjustments from world state
	var flags = WorldState.get_flags()

	# If trade route is disrupted, materials are scarce
	if flags.get("trade_route_disrupted", false):
		if item.category == ItemData.ItemCategory.MATERIAL:
			base_mod *= 1.5  # 50% price increase on materials

	# If resistance is forming, weapons are in demand
	if flags.get("resistance_forming", false):
		if item.category == ItemData.ItemCategory.WEAPON:
			base_mod *= 1.3

	# If tavern is closed, food prices rise
	if flags.get("tavern_closed", false):
		if item.item_id in ["bread", "ale"]:
			base_mod *= 1.4

	return base_mod

## Get personality-based price markup for an NPC
func _get_personality_markup(npc_id: String) -> float:
	match npc_id:
		"gregor_merchant_001":
			# Gregor charges fair prices normally, but more when saving for Elena
			if WorldState.get_world_flag("gregor_gold_secret_revealed"):
				return 1.0  # Normal once secret is out
			return 1.1  # Slight markup (he's saving)
		"bjorn_blacksmith_001":
			# Bjorn is honest, charges fairly
			return 1.0
		_:
			return 1.0

## Get an inventory by ID (player or NPC)
func _get_inventory(entity_id: String) -> Inventory:
	if entity_id == "player":
		# Player inventory is on the Player node
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_node("Inventory"):
			return player.get_node("Inventory")
		return null
	return npc_inventories.get(entity_id)

## Set up initial NPC inventories with realistic stock
func _setup_npc_inventories():
	var item_reg = get_node_or_null("/root/ItemRegistry")
	if item_reg == null:
		await get_tree().process_frame
		item_reg = get_node_or_null("/root/ItemRegistry")
		if item_reg == null:
			push_warning("[EconomyManager] ItemRegistry not ready — skipping inventory setup")
			return

	# Gregor's shop inventory
	var gregor_inv = Inventory.new()
	gregor_inv.max_weight = 200.0
	gregor_inv.silver = 150
	_stock_inventory(gregor_inv, item_reg, {
		"iron_ore": 5, "leather": 8, "timber": 3, "grain": 10,
		"herbs": 6, "bread": 5, "ale": 8, "rope": 2,
		"health_potion": 3, "hunting_knife": 2,
	})
	npc_inventories["gregor_merchant_001"] = gregor_inv

	# Bjorn's forge inventory
	var bjorn_inv = Inventory.new()
	bjorn_inv.max_weight = 300.0
	bjorn_inv.silver = 80
	_stock_inventory(bjorn_inv, item_reg, {
		"iron_sword": 3, "hunting_knife": 4, "wooden_club": 2,
		"leather_vest": 2, "iron_ore": 10,
	})
	npc_inventories["bjorn_blacksmith_001"] = bjorn_inv

	# Mira's tavern inventory
	var mira_inv = Inventory.new()
	mira_inv.max_weight = 100.0
	mira_inv.silver = 60
	_stock_inventory(mira_inv, item_reg, {
		"bread": 10, "ale": 15, "herbs": 4,
	})
	npc_inventories["mira_tavern_keeper_001"] = mira_inv

	print("[EconomyManager] Stocked %d NPC inventories" % npc_inventories.size())

func _stock_inventory(inv: Inventory, item_reg: Node, stock: Dictionary):
	for item_id in stock:
		var item = item_reg.create_item(item_id)
		if item:
			inv.add_item(item, stock[item_id])

## React to flag changes that affect economy
func _on_flag_changed(flag_name: String, _old, new_value):
	if not new_value:
		return

	match flag_name:
		"tavern_closed":
			_apply_settlement_modifier("thornhaven", "bread", 1.4, "Tavern closed")
			_apply_settlement_modifier("thornhaven", "ale", 2.0, "Tavern closed")
			print("[EconomyManager] Tavern closed — food prices rising")
		"resistance_forming":
			_apply_settlement_modifier("thornhaven", "iron_ore", 1.3, "Resistance forming")
			# Weapons demand ripples to Millhaven too
			_apply_settlement_modifier("millhaven", "iron_ore", 1.1, "Regional unrest")
			print("[EconomyManager] Resistance forming — weapon material demand up")
		"trade_route_disrupted":
			# Prices rise at both ends of disrupted route
			_apply_settlement_modifier("thornhaven", "iron_ore", 1.5, "Trade route disrupted")
			_apply_settlement_modifier("thornhaven", "leather", 1.3, "Trade route disrupted")
			_apply_settlement_modifier("millhaven", "grain", 1.3, "Trade route disrupted")
			_apply_settlement_modifier("millhaven", "timber", 1.3, "Trade route disrupted")
			print("[EconomyManager] Trade route disrupted — prices rising at both ends")

# =============================================================================
# MULTI-SETTLEMENT ECONOMY
# =============================================================================

## Initialize supply modifiers for all settlements
func _sync_settlement_prices():
	var world_sim = get_node_or_null("/root/WorldSimulation")
	if not world_sim:
		return

	for s_id in world_sim.settlements:
		if not supply_modifiers.has(s_id):
			supply_modifiers[s_id] = {}
		var settlement: Settlement = world_sim.settlements[s_id]
		# Base modifiers from settlement production
		for item_id in settlement.produces:
			supply_modifiers[s_id][item_id] = supply_modifiers[s_id].get(item_id, 1.0)
		for item_id in settlement.demands:
			supply_modifiers[s_id][item_id] = supply_modifiers[s_id].get(item_id, 1.0)

	print("[EconomyManager] Synced supply modifiers for %d settlements" % supply_modifiers.size())

## Apply a price modifier to a settlement and check for ripple events
func _apply_settlement_modifier(settlement_id: String, item_id: String, multiplier: float, reason: String):
	if not supply_modifiers.has(settlement_id):
		supply_modifiers[settlement_id] = {}

	var old_mod = supply_modifiers[settlement_id].get(item_id, 1.0)
	supply_modifiers[settlement_id][item_id] = old_mod * multiplier

	# Track price history for ripple detection
	if not _price_history.has(settlement_id):
		_price_history[settlement_id] = {}
	if not _price_history[settlement_id].has(item_id):
		_price_history[settlement_id][item_id] = [1.0]

	var history: Array = _price_history[settlement_id][item_id]
	history.append(supply_modifiers[settlement_id][item_id])
	if history.size() > 5:
		history.pop_front()

	# Check for economic ripple
	var first_price = history[0]
	var current_price = history[history.size() - 1]
	if first_price > 0.01:
		var change_ratio = abs(current_price - first_price) / first_price
		if change_ratio >= RIPPLE_THRESHOLD:
			_trigger_economic_ripple(settlement_id, item_id, change_ratio, reason)

## Trigger an economic ripple event (significant price change)
func _trigger_economic_ripple(settlement_id: String, item_id: String, change_ratio: float, reason: String):
	var direction = "surged" if supply_modifiers.get(settlement_id, {}).get(item_id, 1.0) > 1.5 else "collapsed"
	var desc = "%s prices have %s in %s (%s)" % [item_id.capitalize(), direction, settlement_id.capitalize(), reason]

	economic_ripple.emit(settlement_id, item_id, change_ratio, reason)
	print("[EconomyManager] ECONOMIC RIPPLE: %s" % desc)

	# Add to settlement events
	var world_sim = get_node_or_null("/root/WorldSimulation")
	if world_sim:
		var settlement = world_sim.get_settlement(settlement_id)
		if settlement:
			settlement.add_event(desc)

	# Create gossip about the price change
	if GossipManager:
		GossipManager.create_info(desc, "system", "fact", 0.85,
			[], ["economy", item_id, settlement_id])

	# Propagate ripple to connected settlements (dampened)
	var trade_mgr = get_node_or_null("/root/TradeRouteManager")
	if trade_mgr:
		var routes = trade_mgr.get_routes_for_settlement(settlement_id)
		for route in routes:
			var other = route.to_settlement if route.from_settlement == settlement_id else route.from_settlement
			if other != settlement_id:
				# Dampened ripple (30% of the original effect)
				var dampened = 1.0 + (supply_modifiers.get(settlement_id, {}).get(item_id, 1.0) - 1.0) * 0.3
				if not supply_modifiers.has(other):
					supply_modifiers[other] = {}
				supply_modifiers[other][item_id] = supply_modifiers[other].get(item_id, 1.0) * (dampened / supply_modifiers[other].get(item_id, 1.0))

## Get supply modifier for a specific settlement and item (public API)
func get_settlement_supply_modifier(settlement_id: String, item_id: String) -> float:
	return supply_modifiers.get(settlement_id, {}).get(item_id, 1.0)

## Let a Tier 2 merchant NPC affect prices at a settlement
func apply_merchant_influence(merchant_npc_id: String, settlement_id: String, item_id: String, influence: float):
	## influence > 0 means merchant is buying (increases price), < 0 means selling (decreases price)
	var modifier = 1.0 + influence * 0.1  # Each point of influence = 10% price effect
	_apply_settlement_modifier(settlement_id, item_id, modifier,
		"Merchant %s activity" % merchant_npc_id)

## Get a price comparison across all settlements for an item
func get_price_comparison(item_id: String) -> Dictionary:
	var comparison: Dictionary = {}
	for settlement_id in supply_modifiers:
		comparison[settlement_id] = supply_modifiers[settlement_id].get(item_id, 1.0)
	return comparison
