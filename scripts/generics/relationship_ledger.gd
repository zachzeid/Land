extends RefCounted
# RelationshipLedger - Every NPC's feelings toward the player (mains and generics alike), the
# minute it last spoke with the player, and decay toward baseline per game day apart
# (docs/WORLD_SCHEMA.md §9; rates in world.json relationship_decay)
#
# Decay: for each whole game day since last contact not yet applied, every dimension moves toward
# baseline 0 by its rate, never past it. Familiarity stops at the floor once the player has met
# the NPC (a value already below the floor is left alone)

const DIMENSIONS = ["trust", "respect", "affection", "fear", "familiarity"]
const MINUTES_PER_DAY = 1440
const DEFAULT_RATES = {"familiarity": 2.0, "fear": 1.0, "affection": 0.75, "respect": 0.5, "trust": 0.25}
const DEFAULT_FLOOR = 5.0

var rates: Dictionary = DEFAULT_RATES.duplicate()
var familiarity_floor: float = DEFAULT_FLOOR
## npc_id -> {trust, respect, affection, fear, familiarity, met, last_contact, decayed_days}
var entries: Dictionary = {}

func configure(decay: Dictionary) -> void:
	for dim in DIMENSIONS:
		if decay.has(dim):
			rates[dim] = float(decay[dim])
	if decay.has("familiarity_floor_once_met"):
		familiarity_floor = float(decay.familiarity_floor_once_met)

func has_entry(npc_id: String) -> bool:
	return entries.has(npc_id)

## The entry for an NPC, created at baseline (last contact = now) when missing
func ensure(npc_id: String, now_minute: int) -> Dictionary:
	if not entries.has(npc_id):
		entries[npc_id] = {"trust": 0.0, "respect": 0.0, "affection": 0.0, "fear": 0.0, "familiarity": 0.0,
			"met": false, "last_contact": now_minute, "decayed_days": 0}
	return entries[npc_id]

func get_dims(npc_id: String) -> Dictionary:
	var e: Dictionary = entries.get(npc_id, {})
	var out = {}
	for dim in DIMENSIONS:
		out[dim] = float(e.get(dim, 0.0))
	return out

func set_dims(npc_id: String, dims: Dictionary, now_minute: int) -> void:
	var e = ensure(npc_id, now_minute)
	for dim in DIMENSIONS:
		if dims.has(dim):
			var low = 0.0 if dim == "familiarity" else -100.0
			e[dim] = clamp(float(dims[dim]), low, 100.0)

func add_delta(npc_id: String, dimension: String, delta: float, now_minute: int) -> void:
	if dimension not in DIMENSIONS:
		return
	var e = ensure(npc_id, now_minute)
	var low = 0.0 if dimension == "familiarity" else -100.0
	e[dimension] = clamp(float(e[dimension]) + delta, low, 100.0)

## The player spoke with this NPC: decay restarts from now
func note_contact(npc_id: String, now_minute: int) -> void:
	var e = ensure(npc_id, now_minute)
	e.met = true
	e.last_contact = now_minute
	e.decayed_days = 0

func days_apart(npc_id: String, now_minute: int) -> float:
	var e: Dictionary = entries.get(npc_id, {})
	if e.is_empty():
		return 0.0
	return max(now_minute - int(e.last_contact), 0) / float(MINUTES_PER_DAY)

func is_met(npc_id: String) -> bool:
	return bool(entries.get(npc_id, {}).get("met", false))

## Apply every whole day apart not yet applied. Returns {npc_id: days applied} for entries that changed
func decay(now_minute: int) -> Dictionary:
	var changed = {}
	for npc_id in entries:
		var e: Dictionary = entries[npc_id]
		var due = floori(max(now_minute - int(e.last_contact), 0) / float(MINUTES_PER_DAY)) - int(e.decayed_days)
		if due <= 0:
			continue
		e.decayed_days = int(e.decayed_days) + due
		if apply_days(e, due):
			changed[npc_id] = due
	return changed

## Move one entry toward baseline by `days` worth of decay. Returns true if anything moved
func apply_days(e: Dictionary, days: int) -> bool:
	var moved = false
	for dim in DIMENSIONS:
		var value = float(e.get(dim, 0.0))
		var step = float(rates.get(dim, 0.0)) * days
		var target = 0.0
		if dim == "familiarity" and bool(e.get("met", false)):
			if value <= familiarity_floor:
				continue
			target = familiarity_floor
		var next = value
		if value > target:
			next = max(value - step, target)
		elif value < target:
			next = min(value + step, target)
		if not is_equal_approx(next, value):
			e[dim] = next
			moved = true
	return moved

## Relationship strength 0-100: how much this NPC feels about the player either way
func strength(npc_id: String) -> float:
	var d = get_dims(npc_id)
	return 0.3 * abs(d.trust) + 0.3 * abs(d.affection) + 0.15 * abs(d.respect) + 0.15 * abs(d.fear) + 0.1 * d.familiarity

func save() -> Dictionary:
	return entries.duplicate(true)

func load_from_dict(data: Dictionary) -> void:
	entries.clear()
	for npc_id in data:
		var src = data[npc_id]
		if not src is Dictionary:
			continue
		var e = {"met": bool(src.get("met", false)), "last_contact": int(src.get("last_contact", 0)), "decayed_days": int(src.get("decayed_days", 0))}
		for dim in DIMENSIONS:
			e[dim] = float(src.get(dim, 0.0))
		entries[str(npc_id)] = e
