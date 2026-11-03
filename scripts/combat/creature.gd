extends CharacterBody2D
class_name Creature
## Creature - a wolf, boar, adder, rat or bear (resources/combat/creatures.json; docs/PLAYER_SYSTEMS.md §3)
## Simple behaviour, no soul: stalk (close in slowly, strike in reach), charge (rush, strike, fall back,
## rush again), flee_when_hurt (run below flee_below of health, out of sense, then settle). It hunts
## the player only, strikes through Combat.attack with its natural weapon (get_weapon), and takes hits
## like a person (take_hit). Killing one is not a deed (it mattered to nobody), but it drops item ids
## (hide, meat, tusk) to its killer's Inventory

signal died(info: Dictionary)
signal state_changed(state: String)

const DATA_PATH = "res://resources/combat/creatures.json"
const SETTLE_FACTOR = 1.5    # a fleeing creature settles this many sense-lengths away
const STALK_FACTOR = 0.6     # stalking pace, of speed
const RECOIL_SECONDS = 0.8   # a charger falls back this long after a strike

@export var creature_id: String = ""
## Seed for drops (the spawner sets it per spawn; tests fix it)
@export var drop_seed: int = 0

var def: Dictionary = {}
var max_health: float = 1.0
var health: float = 1.0
var is_alive: bool = true
var state: String = "idle"          # idle | stalk | charge | recoil | flee | dead
var target: Node2D = null
var last_attacker = null
var drops: Array = []               # [{item, qty}] rolled on death
var home: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _recoil: float = 0.0
var staggered_until_ms: int = 0

static var _defs: Dictionary = {}

## Every creature definition by id (loaded once)
static func definitions() -> Dictionary:
	if _defs.is_empty():
		var file = FileAccess.open(DATA_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				for c in parsed.get("creatures", []):
					if c is Dictionary and str(c.get("id", "")) != "":
						_defs[str(c.id)] = c
	return _defs

static func definition(id: String) -> Dictionary:
	return definitions().get(id, {})

func _ready() -> void:
	add_to_group("creatures")
	if def.is_empty():
		setup(creature_id)

## Bind to a definition (safe before entering the tree)
func setup(id: String) -> void:
	creature_id = id
	def = definition(id)
	if def.is_empty():
		push_warning("[Creature] Unknown creature '%s'" % id)
		return
	max_health = float(def.get("health", 1.0))
	health = max_health
	home = position
	if name == "" or name.begins_with("@"):
		name = "Creature_" + id

func has(behaviour: String) -> bool:
	return behaviour in def.get("behaviour", [])

## The natural weapon Combat resolves its strikes with, in weapons.json's shape (damage by type)
func get_weapon() -> Dictionary:
	var dtype = str(def.get("damage_type", "cut"))
	return {"id": creature_id + "_natural", "name": str(def.get("name", creature_id)), "kind": "melee",
		"damage": {dtype: float(def.get("damage", 0.0))}, "type": dtype, "reach": float(def.get("reach", 32.0)),
		"arc": 90, "speed": 1.0 / maxf(float(def.get("attack_seconds", 1.0)), 0.1), "poise": float(def.get("poise", 0.0)) * 0.3,
		"stamina": {"light": 0, "heavy": 0}, "durability_per_hit": 0, "skill": "", "block": 0.0, "natural": true}

## What Combat resolves hits with (scripts/combat/combat.gd get_combat_profile)
func get_combat_profile() -> Dictionary:
	return {"weapon": get_weapon(), "armour": [], "resist": get_resistances(), "poise": float(def.get("poise", 0.0)),
		"health": max_health, "skills": {}, "difficulty": clampf(max_health / 50.0, 0.2, 3.0), "minor": false}

## Combat.apply_hit_to's entry point
func take_combat_hit(result: Dictionary, attacker) -> Dictionary:
	return take_hit(result, attacker)

func on_staggered(seconds: float) -> void:
	staggered_until_ms = maxi(staggered_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))

## Creatures spend no stamina (their pace is their attack time)
func spend_stamina(_amount: float) -> bool:
	return true

func get_stamina() -> float:
	return 100.0

func get_resistances() -> Dictionary:
	return def.get("resist", {}).duplicate()

func is_staggered() -> bool:
	return Time.get_ticks_msec() < staggered_until_ms

## A resolved hit {damage, type, staggered, killed}. Returns {health, staggered, dead, state}
func take_hit(result: Dictionary, attacker) -> Dictionary:
	if not is_alive:
		return {"refused": true, "reason": "dead"}
	last_attacker = attacker
	health = maxf(health - maxf(float(result.get("damage", 0.0)), 0.0), 0.0)
	if bool(result.get("staggered", false)):
		staggered_until_ms = Time.get_ticks_msec() + 600
	if bool(result.get("killed", false)) or health <= 0.0:
		_die(attacker)
		return {"health": 0.0, "staggered": false, "dead": true, "state": state}
	if attacker is Node2D and target == null:
		target = attacker  # struck from outside its sense: now it knows where you are
	if _should_flee():
		_set_state("flee")
	return {"health": health, "staggered": is_staggered(), "dead": false, "state": state}

func _should_flee() -> bool:
	return has("flee_when_hurt") and health < max_health * float(def.get("flee_below", 0.0))

## One step of behaviour: picks the state and returns the velocity (tests call it directly)
func think(delta: float) -> Vector2:
	if not is_alive or def.is_empty():
		return Vector2.ZERO
	_cooldown = maxf(_cooldown - delta, 0.0)
	if is_staggered():
		return Vector2.ZERO
	var sense = float(def.get("sense", 200.0))
	if target == null or not is_instance_valid(target) or target.get("is_alive") == false:
		target = _find_target(sense)
	if target == null:
		_set_state("idle")
		return Vector2.ZERO
	var to: Vector2 = target.global_position - global_position
	var dist = to.length()
	var speed = float(def.get("speed", 60.0))
	if _should_flee():
		_set_state("flee")
	if state == "flee":
		if dist > sense * SETTLE_FACTOR:
			target = null
			_set_state("idle")
			return Vector2.ZERO
		return -to.normalized() * speed * 1.3
	if dist > sense * SETTLE_FACTOR:
		target = null
		_set_state("idle")
		return Vector2.ZERO
	if state == "recoil":
		_recoil -= delta
		if _recoil > 0.0:
			return -to.normalized() * speed
	var reach = float(def.get("reach", 32.0))
	if dist <= reach:
		if _cooldown <= 0.0:
			_strike()
		return Vector2.ZERO
	if has("charge"):
		_set_state("charge")
		return to.normalized() * float(def.get("charge_speed", speed * 2.0))
	_set_state("stalk")
	return to.normalized() * speed * STALK_FACTOR

func _physics_process(delta: float) -> void:
	velocity = think(delta)
	if velocity != Vector2.ZERO:
		move_and_slide()

func _find_target(sense: float) -> Node2D:
	if not is_inside_tree():
		return null
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node2D and p.is_visible_in_tree() and p.global_position.distance_to(global_position) <= sense:
			return p
	return null

func _strike() -> void:
	_cooldown = float(def.get("attack_seconds", 1.5))
	var combat = get_node_or_null("/root/Combat") if is_inside_tree() else null
	if combat and combat.has_method("attack") and target:
		combat.attack(self, target, "light")
	if has("charge"):
		_recoil = RECOIL_SECONDS
		_set_state("recoil")

func _set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)

## Rolls its drops (seeded) and hands them to the player who killed it
func _die(killer) -> void:
	is_alive = false
	drops = roll_drops(def, drop_seed)
	var by_player = killer is Node and killer.is_in_group("player")
	var inventory = get_node_or_null("/root/Inventory") if is_inside_tree() else null
	if by_player and inventory and inventory.has_method("add"):
		for d in drops:
			inventory.add(str(d.item), int(d.qty), {"provenance": {"from": creature_id, "stolen": false, "owner": ""}})
	_set_state("dead")
	died.emit({"creature": creature_id, "drops": drops.duplicate(true), "by_player": by_player})
	visible = false
	set_physics_process(false)
	if is_inside_tree():
		queue_free.call_deferred()

static func roll_drops(definition_: Dictionary, seed_value: int) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for d in definition_.get("drops", []):
		var qty: Array = d.get("qty", [1, 1])
		var n = rng.randi_range(int(qty[0]), int(qty[1]))
		if rng.randf() < float(d.get("chance", 1.0)) and n > 0:
			out.append({"item": str(d.item), "qty": n})
	return out
