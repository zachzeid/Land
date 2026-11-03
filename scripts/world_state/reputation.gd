class_name Reputation
extends RefCounted
# Reputation - What a party thinks of the stranger (docs/WORLD_SCHEMA.md §10), -100..100
# Computed only from the player events that party KNOWS (PlayerEvents witnesses + heard_by),
# weighted by fidelity, recency and kind. Nobody is omniscient
#   Reputation.of("npc", "gregor")           one NPC (key, npc_id or generic id)
#   Reputation.of("faction", "iron_hollow")  world.json factions: members + archetype generics
#   Reputation.of("region", "western_valley") everyone living in the region
# A faction or region knows an event when any of its people do, at the best fidelity among them
#
# score = 100 * tanh(raw / SCALE), raw = sum(kind_weight * fidelity * recency * about)
#   fidelity: the party's best fidelity; an anonymous rumour (< 0.3) cannot be pinned on the player: 0
#   recency: 0.5 ^ (days since the deed or its last change / HALF_LIFE_DAYS), never below RECENCY_FLOOR
#   about: x1.5 when the event concerns the party (x2 for hostile kinds)

const SCALE = 50.0
const HALF_LIFE_DAYS = 7.0
const RECENCY_FLOOR = 0.25
const ANON_BELOW = 0.3
const ABOUT_MULT = 1.5
const ABOUT_MULT_HOSTILE = 2.0
const HOSTILE = ["threat", "insult", "harm", "theft", "kill", "accusation", "lie"]

## Per-event weight (points) by kind; promises and claims depend on status / truth (kind_weight)
const KIND_WEIGHTS = {
	"help": 12.0, "gift": 10.0, "spared": 14.0, "confession": 4.0, "refusal": -4.0,
	"threat": -12.0, "insult": -8.0, "harm": -15.0, "theft": -14.0, "kill": -30.0,
	"accusation": -3.0, "lie": -18.0, "seen_at": 0.0, "kept_company": 1.5,
}
const PROMISE_OPEN = 2.0
const PROMISE_KEPT = 15.0
const PROMISE_BROKEN = -25.0
const LIE_EXPOSED = -22.0      # a claim the world contradicted
const CLAIM_TRUE = 3.0
const CLAIM_BELIEVED = 1.0
const CLAIM_DOUBTED = -4.0

## Hidden membership: Iron Hollow counts Mira only once she is unmasked; until then she is reckoned
## as Thornhaven folk (world.json factions note)
const HIDDEN_MEMBERS = {"mira": {"faction": "iron_hollow", "until": "mira_boss_revealed", "cover": "thornhaven"}}

## Weight of one event (before fidelity, recency and aboutness)
static func kind_weight(ev: Dictionary) -> float:
	if ev.is_empty():
		return 0.0
	var kind = str(ev.get("kind", ""))
	match kind:
		"promise":
			match str(ev.get("status", "open")):
				"kept":
					return PROMISE_KEPT
				"broken":
					return PROMISE_BROKEN
			return PROMISE_OPEN
		"claim":
			if str(ev.get("truth", "")) == "true":
				return CLAIM_TRUE
			return CLAIM_BELIEVED if ev.get("believed", true) != false else CLAIM_DOUBTED
		"lie":
			return LIE_EXPOSED if ev.has("was") else KIND_WEIGHTS.lie
		"kept_company":
			return KIND_WEIGHTS.kept_company * mini(int(ev.get("hours", 1)), 4)
	return float(KIND_WEIGHTS.get(kind, 0.0))

static func recency(ev: Dictionary, now: int) -> float:
	var at = maxi(int(ev.get("minute", 0)), int(ev.get("changed_minute", 0)))
	var days = maxf(now - at, 0) / 1440.0
	return maxf(RECENCY_FLOOR, pow(0.5, days / HALF_LIFE_DAYS))

## -100..100. scope: npc | faction | region. 0 when nothing is known (or nothing matches)
static func of(scope: String, id: String) -> float:
	return float(breakdown(scope, id).score)

## The score and every known event's contribution: {"score", "raw", "parties", "events": [{id, kind,
## status, weight, fidelity, recency, about, points}]}
static func breakdown(scope: String, id: String) -> Dictionary:
	var pe = _pe()
	var result = {"score": 0.0, "raw": 0.0, "parties": [], "events": []}
	if pe == null:
		return result
	var parties = parties_of(scope, id)
	result.parties = parties
	if parties.is_empty():
		return result
	var now: int = pe._now()
	var raw = 0.0
	var known: Dictionary = pe.knowledge_of(parties)
	for event_id in known:
		var k: Dictionary = known[event_id]
		var ev: Dictionary = k.event
		var f = float(k.fidelity)
		if f < ANON_BELOW:
			f = 0.0
		var w = kind_weight(ev)
		var about = 1.0
		for who in ev.get("about", []):
			if who in parties:
				about = ABOUT_MULT_HOSTILE if str(ev.kind) in HOSTILE else ABOUT_MULT
				break
		var r = recency(ev, now)
		var points = w * f * r * about
		raw += points
		result.events.append({"id": event_id, "kind": ev.kind, "status": ev.status, "weight": w, "fidelity": f,
			"recency": snappedf(r, 0.01), "about": about, "points": snappedf(points, 0.01)})
	result.raw = snappedf(raw, 0.01)
	result.score = snappedf(clampf(100.0 * tanh(raw / SCALE), -100.0, 100.0), 0.1)
	return result

## The people a scope stands for (who-keys: roster keys and generic ids)
static func parties_of(scope: String, id: String) -> Array:
	var pe = _pe()
	match scope:
		"npc":
			return [pe._who(id)] if pe and id != "" else []
		"faction":
			return faction_members(id)
		"region":
			return pe.get_people_in_region(id) if pe else []
	return []

## world.json factions: {id: {name, region, members, archetypes}}
static func get_factions() -> Dictionary:
	var registry = _node("WorldRegistry")
	var result: Dictionary = {}
	if registry == null or not "data" in registry:
		return result
	var list = registry.data.get("factions", [])
	if list is Array:
		for f in list:
			if f is Dictionary and str(f.get("id", "")) != "":
				result[str(f.id)] = f
	return result

## Members now: the faction's roster keys (hidden members only once revealed; covers while hidden)
## plus generics of its archetypes living in its region
static func faction_members(faction_id: String) -> Array:
	var factions = get_factions()
	if not factions.has(faction_id):
		return []
	var f: Dictionary = factions[faction_id]
	var result: Array = []
	for key in f.get("members", []):
		var k = str(key)
		if HIDDEN_MEMBERS.has(k) and HIDDEN_MEMBERS[k].faction == faction_id and not _flag(HIDDEN_MEMBERS[k].until):
			continue
		result.append(k)
	for k in HIDDEN_MEMBERS:
		var rule: Dictionary = HIDDEN_MEMBERS[k]
		if rule.cover == faction_id and not _flag(rule.until) and k not in result:
			result.append(k)
	var gm = _generics()
	if gm:
		var archetypes: Array = f.get("archetypes", [])
		var region = str(f.get("region", ""))
		for gid in gm.get_ids():
			var inst = gm.get_instance(gid)
			if inst and str(inst.archetype_id) in archetypes and (region == "" or str(inst.region) == region):
				result.append(gid)
	return result

## The factions someone is reckoned in now (a hidden member: its cover until revealed)
static func factions_of(who: String) -> Array:
	var result: Array = []
	var factions = get_factions()
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.is_generic(who) else null
	for fid in factions:
		var f: Dictionary = factions[fid]
		if inst != null:
			var region = str(f.get("region", ""))
			if str(inst.archetype_id) in f.get("archetypes", []) and (region == "" or str(inst.region) == region):
				result.append(fid)
		elif who in faction_members(fid):
			result.append(fid)
	return result

## Words for a score
static func label(score: float) -> String:
	if score >= 50:
		return "admired"
	if score >= 20:
		return "well thought of"
	if score > -20:
		return "little known" if absf(score) < 5 else "of mixed repute"
	if score > -50:
		return "distrusted"
	return "hated"

## "Among Thornhaven folk the stranger is distrusted (-31)." for an NPC's prompt ("" when unknown)
static func standing_line(who: String) -> String:
	var parts: Array = []
	var factions = get_factions()
	for fid in factions_of(who):
		var b = breakdown("faction", fid)
		if b.events.is_empty():
			continue
		parts.append("among %s the stranger is %s (%d)" % [str(factions[fid].get("name", fid)), label(b.score), roundi(b.score)])
	if parts.is_empty():
		return ""
	var line = "; ".join(parts.slice(0, 2)) + "."
	return line.substr(0, 1).to_upper() + line.substr(1)

static func _flag(name: String) -> bool:
	var world_state = _node("WorldState")
	return world_state != null and world_state.get_world_flag(name)

static func _pe() -> Node:
	return _node("PlayerEvents")

static func _generics() -> Node:
	var registry = _node("DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry and registry.generics else null

static func _node(name: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(name) if tree else null
