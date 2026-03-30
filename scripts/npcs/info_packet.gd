extends RefCounted
class_name InfoPacket
## InfoPacket - A discrete piece of information that can flow between NPCs
##
## Information travels through the NPC social network with confidence decay.
## Each retelling reduces confidence and may alter the content.
## Secrets have restricted audiences and higher trust thresholds.

## Unique identifier
var id: String = ""

## The information content (what is being communicated)
var content: String = ""

## Who originally created this information
var source_npc: String = ""

## Category determines how the information is treated
## "fact" — verified truth (high confidence, slow decay)
## "rumor" — unverified (medium confidence, normal decay)
## "gossip" — social chatter (lower confidence, fast decay)
## "secret" — restricted information (high confidence, requires trust to share)
## "warning" — urgent information (high confidence, spreads fast)
var category: String = "gossip"

## How confident the holder is in this information (0.0 to 1.0)
## Degrades with each retelling
var confidence: float = 0.8

## How many times this has been passed along
var spread_count: int = 0

## Chain of NPCs who passed this along (for provenance)
var chain: Array[String] = []

## Timestamp when this info was created
var timestamp: float = 0.0

## NPC IDs who are allowed to know this (empty = public, non-empty = restricted)
var restricted_to: Array[String] = []

## Related story flags or topics (for quest system integration)
var related_flags: Array[String] = []
var related_topics: Array[String] = []

## Whether this info packet has been processed by the receiving NPC
var processed: bool = false

## Create a new InfoPacket
static func create(p_content: String, p_source: String, p_category: String = "gossip", p_confidence: float = 0.8) -> InfoPacket:
	var packet = InfoPacket.new()
	packet.id = "%s_%d_%s" % [p_source, Time.get_unix_time_from_system(), p_category]
	packet.content = p_content
	packet.source_npc = p_source
	packet.category = p_category
	packet.confidence = p_confidence
	packet.timestamp = Time.get_unix_time_from_system()
	packet.chain = [p_source]
	return packet

## Create a copy for retelling (with degraded confidence)
func retold_by(npc_id: String) -> InfoPacket:
	var copy = InfoPacket.new()
	copy.id = id
	copy.source_npc = source_npc
	copy.category = category
	copy.related_flags = related_flags.duplicate()
	copy.related_topics = related_topics.duplicate()
	copy.restricted_to = restricted_to.duplicate()
	copy.timestamp = timestamp
	copy.chain = chain.duplicate()
	copy.chain.append(npc_id)
	copy.spread_count = spread_count + 1

	# Confidence degrades with each retelling
	var decay = _get_confidence_decay()
	copy.confidence = max(confidence - decay, 0.05)

	# Content may be slightly altered after 3+ hops
	if copy.spread_count >= 3:
		copy.content = "I heard that " + content
	else:
		copy.content = content

	return copy

## Get confidence decay per retelling based on category
func _get_confidence_decay() -> float:
	match category:
		"fact": return 0.05       # Facts barely degrade
		"warning": return 0.08    # Warnings degrade slowly
		"secret": return 0.10     # Secrets degrade moderately
		"rumor": return 0.15      # Rumors degrade normally
		"gossip": return 0.20     # Gossip degrades quickly
		_: return 0.15

## Check if an NPC is allowed to receive this information
func can_receive(npc_id: String) -> bool:
	if restricted_to.is_empty():
		return true  # Public information
	return npc_id in restricted_to

## Check if this info is still credible enough to act on
func is_credible() -> bool:
	return confidence >= 0.3

## Serialize to dictionary (for storage/transmission)
func to_dict() -> Dictionary:
	return {
		"id": id,
		"content": content,
		"source_npc": source_npc,
		"category": category,
		"confidence": confidence,
		"spread_count": spread_count,
		"chain": chain,
		"timestamp": timestamp,
		"restricted_to": restricted_to,
		"related_flags": related_flags,
		"related_topics": related_topics,
	}

## Deserialize from dictionary
static func from_dict(data: Dictionary) -> InfoPacket:
	var packet = InfoPacket.new()
	packet.id = data.get("id", "")
	packet.content = data.get("content", "")
	packet.source_npc = data.get("source_npc", "")
	packet.category = data.get("category", "gossip")
	packet.confidence = data.get("confidence", 0.5)
	packet.spread_count = data.get("spread_count", 0)
	packet.chain = data.get("chain", [])
	packet.timestamp = data.get("timestamp", 0.0)
	packet.restricted_to = data.get("restricted_to", [])
	packet.related_flags = data.get("related_flags", [])
	packet.related_topics = data.get("related_topics", [])
	return packet
