extends RefCounted
# GenericInstance - One generic NPC (gen_<archetype>_<n>): its seed, its rolls and the layers
# every interaction adds on top of its archetype (docs/WORLD_SCHEMA.md §9)
# Relationship dimensions live in the shared RelationshipLedger (every NPC decays the same way)

const MAX_LAYERS = 16          # layers kept per instance; the lowest-ranked fall off
const PROMPT_LAYERS = 6        # layers shown in a conversation prompt
const MAX_LAYER_CHARS = 140
const MAX_TRAIT_NUDGE = 20
const MAX_WANT_NUDGE = 3
const TRAITS = ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]
const KINDS = ["learned", "moment", "gossip", "witnessed", "residue", "acquaintance"]

var id: String = ""
var archetype_id: String = ""
var seed_value: int = 0
var name: String = ""
var home: String = ""
var region: String = ""
var location: String = ""       # "" = home
var hours: Array = []           # [start_hour, end_hour) present at home; [] = always
var voice_variant: int = 0
var rolled_wants: Dictionary = {}   # want_id -> rolled weight (fixed by the seed)
var rolled_traits: Dictionary = {}  # Big Five, rolled from the seed (-40..40)
var trait_nudges: Dictionary = {}   # trait -> small drift from interactions
var want_nudges: Dictionary = {}    # want_id -> small drift from interactions
var layers: Array = []          # [{kind, text, importance, minute, count, pinned, tag, flag}]
var tier: String = "generic"    # generic | promoted
var promotions: int = 0
var significance: float = 0.0
var rounds_at_threshold: int = 0
var witnessed: int = 0
var gossip_heard: int = 0
var interactions: int = 0
var history: Array = []         # [{event, minute, day, significance}]
var soul_text: String = ""
var soul_path: String = ""      # user://souls/<id>/SOUL.md while promoted
var memory_mode: String = "layers"   # layers (in-memory, residue only) | chroma (own collection)
var memory_collection: String = ""

# =============================================================================
# LAYERS
# =============================================================================

## Add (or reinforce) a layer. Same kind+text reinforces: count +1, newest minute, max importance
## Returns the layer
func add_layer(kind: String, text: String, importance: int, minute: int, extra: Dictionary = {}) -> Dictionary:
	var clean = text.strip_edges().replace("\n", " ")
	if clean.length() > MAX_LAYER_CHARS:
		clean = clean.substr(0, MAX_LAYER_CHARS - 3) + "..."
	var tag = str(extra.get("tag", ""))
	for layer in layers:
		if layer.kind == kind and (layer.text == clean or (tag != "" and layer.get("tag", "") == tag)):
			layer.text = clean
			layer.count = int(layer.count) + 1
			layer.minute = maxi(int(layer.minute), minute)
			layer.importance = maxi(int(layer.importance), clampi(importance, 1, 10))
			return layer
	var layer = {"kind": kind, "text": clean, "importance": clampi(importance, 1, 10), "minute": minute, "count": 1,
		"pinned": bool(extra.get("pinned", false)), "tag": tag, "flag": str(extra.get("flag", ""))}
	layers.append(layer)
	_cap_layers(minute)
	return layer

## Rank: importance dominates, recency and repetition break ties, pinned (the player's name) always first
static func layer_score(layer: Dictionary, now_minute: int) -> float:
	var age_days = max(now_minute - int(layer.get("minute", 0)), 0) / 1440.0
	var score = float(layer.get("importance", 1)) * 10.0
	score += 20.0 * exp(-age_days / 7.0)
	score += min(int(layer.get("count", 1)) - 1, 5) * 2.0
	if layer.get("pinned", false):
		score += 100.0
	return score

## Layers best first
func ranked_layers(now_minute: int) -> Array:
	var ranked = layers.duplicate()
	ranked.sort_custom(func(a, b): return layer_score(a, now_minute) > layer_score(b, now_minute))
	return ranked

func top_layers(count: int, now_minute: int) -> Array:
	return ranked_layers(now_minute).slice(0, count)

func _cap_layers(now_minute: int) -> void:
	if layers.size() <= MAX_LAYERS:
		return
	layers = ranked_layers(now_minute).slice(0, MAX_LAYERS)

## Importance of the strongest layers, faded with age (an old moment still counts half)
func layer_weight(now_minute: int, count: int = 5) -> float:
	var weights: Array = []
	for layer in layers:
		var age_days = max(now_minute - int(layer.minute), 0) / 1440.0
		weights.append(float(layer.importance) * (0.5 + 0.5 * exp(-age_days / 14.0)))
	weights.sort()
	weights.reverse()
	var total = 0.0
	for w in weights.slice(0, count):
		total += w
	return total

func has_layer_tag(tag: String) -> bool:
	for layer in layers:
		if layer.get("tag", "") == tag:
			return true
	return false

# =============================================================================
# NUDGES
# =============================================================================

func nudge_trait(trait_name: String, delta: int) -> void:
	if trait_name not in TRAITS or delta == 0:
		return
	trait_nudges[trait_name] = clampi(int(trait_nudges.get(trait_name, 0)) + delta, -MAX_TRAIT_NUDGE, MAX_TRAIT_NUDGE)

func nudge_want(want_id: String, delta: int) -> void:
	if not rolled_wants.has(want_id) or delta == 0:
		return
	want_nudges[want_id] = clampi(int(want_nudges.get(want_id, 0)) + delta, -MAX_WANT_NUDGE, MAX_WANT_NUDGE)

func get_trait(trait_name: String) -> int:
	return clampi(int(rolled_traits.get(trait_name, 0)) + int(trait_nudges.get(trait_name, 0)), -100, 100)

## Rolled weight plus nudges, clamped 1-10
func get_want_weight(want_id: String) -> int:
	return clampi(int(rolled_wants.get(want_id, 0)) + int(want_nudges.get(want_id, 0)), 1, 10)

## Want ids by current weight, archetype order breaking ties
func wants_by_weight(order: Array) -> Array:
	var ids = order.filter(func(w): return rolled_wants.has(w))
	ids.sort_custom(func(a, b):
		var wa = get_want_weight(a)
		var wb = get_want_weight(b)
		return wa > wb if wa != wb else order.find(a) < order.find(b))
	return ids

## Demotion halves every nudge (toward zero)
func halve_nudges() -> void:
	for key in trait_nudges.keys():
		trait_nudges[key] = int(trait_nudges[key] / 2)
	for key in want_nudges.keys():
		want_nudges[key] = int(want_nudges[key] / 2)

# =============================================================================
# STATE
# =============================================================================

func get_location() -> String:
	return location if location != "" else home

func note_history(event: String, minute: int, extra: Dictionary = {}) -> void:
	var entry = {"event": event, "minute": minute, "day": floori(minute / 1440.0) + 1, "significance": snappedf(significance, 0.1)}
	entry.merge(extra)
	history.append(entry)
	if history.size() > 40:
		history = history.slice(history.size() - 40)

func to_dict() -> Dictionary:
	return {
		"id": id, "archetype": archetype_id, "seed": seed_value, "name": name, "home": home, "region": region,
		"location": location, "hours": hours, "voice_variant": voice_variant,
		"rolled_wants": rolled_wants, "rolled_traits": rolled_traits,
		"trait_nudges": trait_nudges, "want_nudges": want_nudges, "layers": layers,
		"tier": tier, "promotions": promotions, "significance": significance,
		"rounds_at_threshold": rounds_at_threshold, "witnessed": witnessed, "gossip_heard": gossip_heard,
		"interactions": interactions, "history": history, "soul_text": soul_text, "soul_path": soul_path,
		"memory_mode": memory_mode, "memory_collection": memory_collection,
	}

static func from_dict(data: Dictionary):
	var inst = load("res://scripts/generics/generic_instance.gd").new()
	inst.id = str(data.get("id", ""))
	inst.archetype_id = str(data.get("archetype", ""))
	inst.seed_value = int(data.get("seed", 0))
	inst.name = str(data.get("name", ""))
	inst.home = str(data.get("home", ""))
	inst.region = str(data.get("region", ""))
	inst.location = str(data.get("location", ""))
	inst.hours = data.get("hours").map(func(h): return int(h)) if data.get("hours") is Array else []
	inst.voice_variant = int(data.get("voice_variant", 0))
	inst.rolled_wants = _int_dict(data.get("rolled_wants", {}))
	inst.rolled_traits = _int_dict(data.get("rolled_traits", {}))
	inst.trait_nudges = _int_dict(data.get("trait_nudges", {}))
	inst.want_nudges = _int_dict(data.get("want_nudges", {}))
	inst.layers = []
	for layer in data.get("layers", []):
		if layer is Dictionary:
			var l = layer.duplicate()
			l.importance = int(l.get("importance", 1))
			l.minute = int(l.get("minute", 0))
			l.count = int(l.get("count", 1))
			l.pinned = bool(l.get("pinned", false))
			inst.layers.append(l)
	inst.tier = str(data.get("tier", "generic"))
	inst.promotions = int(data.get("promotions", 0))
	inst.significance = float(data.get("significance", 0.0))
	inst.rounds_at_threshold = int(data.get("rounds_at_threshold", 0))
	inst.witnessed = int(data.get("witnessed", 0))
	inst.gossip_heard = int(data.get("gossip_heard", 0))
	inst.interactions = int(data.get("interactions", 0))
	inst.history = []
	for h in data.get("history", []) if data.get("history") is Array else []:
		if h is Dictionary:
			var entry = h.duplicate()
			for key in ["minute", "day"]:
				if entry.has(key):
					entry[key] = int(entry[key])
			inst.history.append(entry)
	inst.soul_text = str(data.get("soul_text", ""))
	inst.soul_path = str(data.get("soul_path", ""))
	inst.memory_mode = str(data.get("memory_mode", "layers"))
	inst.memory_collection = str(data.get("memory_collection", ""))
	return inst

static func _int_dict(value) -> Dictionary:
	var out = {}
	if value is Dictionary:
		for key in value:
			out[str(key)] = int(value[key])
	return out
