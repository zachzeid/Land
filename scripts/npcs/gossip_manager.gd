extends Node
class_name GossipManager
## GossipManager - Handles information propagation between NPCs
##
## Information flows through the NPC social network based on:
## - Proximity (same location)
## - Gossip tendency (extraversion-based)
## - Trust level (for restricted/secret information)
## - Confidence decay (rumors degrade over time)
##
## The tavern keeper (Mira) is a natural gossip hub — she talks to everyone.

signal info_spread(from_npc: String, to_npc: String, packet_id: String)
signal secret_leaked(secret_holder: String, leaked_to: String, content: String)

## All information packets in circulation {packet_id: InfoPacket}
var all_packets: Dictionary = {}

## Per-NPC information buffers {npc_id: Array[InfoPacket]}
var npc_buffers: Dictionary = {}

## How often gossip propagation runs (in seconds)
@export var gossip_tick_interval: float = 30.0

var _gossip_timer: Timer = null

func _ready():
	# Listen for NPC communication events
	if EventBus.has_signal("npc_communicated"):
		EventBus.npc_communicated.connect(_on_npc_communicated)

	# Set up gossip propagation timer
	_gossip_timer = Timer.new()
	_gossip_timer.wait_time = gossip_tick_interval
	_gossip_timer.timeout.connect(_propagate_gossip)
	_gossip_timer.one_shot = false
	add_child(_gossip_timer)
	_gossip_timer.start()

	print("[GossipManager] Initialized (tick every %.0fs)" % gossip_tick_interval)

## Inject an InfoPacket into an NPC's buffer
func give_info_to_npc(npc_id: String, packet: InfoPacket):
	if not npc_buffers.has(npc_id):
		npc_buffers[npc_id] = []

	# Don't give duplicate info
	for existing in npc_buffers[npc_id]:
		if existing.id == packet.id:
			# Reinforce confidence if heard from multiple sources
			existing.confidence = min(existing.confidence + 0.1, 1.0)
			return

	npc_buffers[npc_id].append(packet)
	all_packets[packet.id] = packet

## Create and inject a new piece of information
func create_info(content: String, source_npc: String, category: String = "gossip",
				 confidence: float = 0.8, related_flags: Array = [], related_topics: Array = []) -> InfoPacket:
	var packet = InfoPacket.create(content, source_npc, category, confidence)
	packet.related_flags = related_flags
	packet.related_topics = related_topics
	give_info_to_npc(source_npc, packet)
	return packet

## Create a secret (restricted information)
func create_secret(content: String, holder_npc: String, restricted_to: Array[String] = [],
				   related_flags: Array = []) -> InfoPacket:
	var packet = InfoPacket.create(content, holder_npc, "secret", 1.0)
	packet.restricted_to = restricted_to
	packet.related_flags = related_flags
	give_info_to_npc(holder_npc, packet)
	return packet

## Get all info packets an NPC knows about
func get_npc_info(npc_id: String) -> Array:
	return npc_buffers.get(npc_id, [])

## Get info an NPC would be willing to share with a specific target
func get_shareable_info(holder_npc_id: String, target_npc_id: String, holder_trust: float = 0.0) -> Array:
	var buffer = npc_buffers.get(holder_npc_id, [])
	var shareable := []

	for packet in buffer:
		# Skip if not credible
		if not packet.is_credible():
			continue
		# Skip if restricted and target not allowed
		if not packet.restricted_to.is_empty():
			if not packet.can_receive(target_npc_id):
				# Could share if trust is very high (secret sharing)
				if holder_trust < 60.0:
					continue
		# Skip if this NPC is already in the chain
		if target_npc_id in packet.chain:
			continue
		shareable.append(packet)

	return shareable

## Periodic gossip propagation tick
func _propagate_gossip():
	var npcs = get_tree().get_nodes_in_group("npcs")
	if npcs.is_empty():
		return

	# Build location map {location: [npc]}
	var location_map: Dictionary = {}
	for npc in npcs:
		if not is_instance_valid(npc) or not npc.get("is_alive"):
			continue
		if npc.get("is_in_conversation"):
			continue  # Don't gossip during player conversations
		var loc = npc.get("current_location", "")
		if loc == "":
			loc = npc.get("home_location", "unknown")
		if not location_map.has(loc):
			location_map[loc] = []
		location_map[loc].append(npc)

	# For each location, NPCs may share info with each other
	for location in location_map:
		var local_npcs = location_map[location]
		if local_npcs.size() < 2:
			continue  # Need at least 2 NPCs to gossip

		for npc in local_npcs:
			var npc_id = npc.get("npc_id", "")
			if npc_id == "":
				continue

			# Check gossip tendency
			var gossip_chance = 0.3  # Base 30%
			if npc.personality_resource and npc.personality_resource.get("gossip_tendency"):
				gossip_chance = npc.personality_resource.gossip_tendency

			if randf() > gossip_chance:
				continue  # This NPC doesn't feel like gossiping right now

			# Pick a random NPC at the same location to gossip with
			var targets = local_npcs.filter(func(n): return n != npc)
			if targets.is_empty():
				continue
			var target = targets[randi() % targets.size()]
			var target_id = target.get("npc_id", "")

			# Get shareable info
			var shareable = get_shareable_info(npc_id, target_id)
			if shareable.is_empty():
				continue

			# Share the most confident piece of information
			shareable.sort_custom(func(a, b): return a.confidence > b.confidence)
			var to_share = shareable[0]
			var retold = to_share.retold_by(npc_id)

			give_info_to_npc(target_id, retold)
			info_spread.emit(npc_id, target_id, retold.id)

			# Emit EventBus signal
			EventBus.npc_communicated.emit(npc_id, target_id, retold.to_dict())

			# Check if this was a secret leak
			if to_share.category == "secret":
				secret_leaked.emit(npc_id, target_id, to_share.content)
				print("[GossipManager] SECRET LEAKED: %s told %s: '%s'" % [
					npc.get("npc_name", npc_id),
					target.get("npc_name", target_id),
					to_share.content.substr(0, 60)])
			else:
				print("[GossipManager] %s told %s: '%s' (confidence: %.2f)" % [
					npc.get("npc_name", npc_id),
					target.get("npc_name", target_id),
					retold.content.substr(0, 60),
					retold.confidence])

## Handle external npc_communicated events (from agent loops or other systems)
func _on_npc_communicated(from_npc: String, to_npc: String, info_data: Dictionary):
	var packet = InfoPacket.from_dict(info_data)
	if packet.id != "":
		give_info_to_npc(to_npc, packet)

## Debug: print all info in circulation
func debug_print_info():
	print("[GossipManager] === Information in Circulation ===")
	for npc_id in npc_buffers:
		var buffer = npc_buffers[npc_id]
		print("  %s knows %d things:" % [npc_id, buffer.size()])
		for packet in buffer:
			print("    [%s] '%s' (confidence: %.2f, hops: %d)" % [
				packet.category, packet.content.substr(0, 50), packet.confidence, packet.spread_count])
