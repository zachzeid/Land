extends CharacterBody2D
class_name Creature
## Creature - a wolf, boar, adder, rat or bear (resources/combat/creatures.json; docs/PLAYER_SYSTEMS.md §3)
## Simple behaviour, no soul: stalk (close in slowly, strike in reach), charge (rush, strike, fall back,
## rush again), flee_when_hurt (run below flee_below of health, out of sense, then settle). It hunts
## the player only, strikes through Combat.attack with its natural weapon (get_weapon), and takes hits
## like a person (take_hit). Killing one is not a deed (it mattered to nobody), but it drops item ids
## (hide, meat, tusk) to its killer's Inventory
## Indoors is not theirs (docs/WORLD_SCHEMA.md "Buildings"): a creature never steps into a doorway
## (any SceneTrigger, or an Area2D in the "building_zones" group), so it never takes a scene
## transition; a target who stands in a door that leads into a building is out of its reach: it
## loiters outside, then loses interest and walks back to where it was placed. Shoved or fled into
## a doorway, it steps back out first

signal died(info: Dictionary)
signal state_changed(state: String)

const DATA_PATH = "res://resources/combat/creatures.json"
const SETTLE_FACTOR = 1.5    # a fleeing creature settles this many sense-lengths away
const STALK_FACTOR = 0.6     # stalking pace, of speed
const RECOIL_SECONDS = 0.8   # a charger falls back this long after a strike
const DOOR_MARGIN = 30.0     # keeps a body (the bear's half-width) clear of a doorway's edge
const LOITER_SECONDS = 4.0   # how long it waits outside the door its quarry went in by
const FORGET_SECONDS = 30.0  # after giving up, it ignores that quarry this long (unless struck)
const HOME_RADIUS = 16.0     # close enough to its spot to settle
const ZONES_REFRESH = 2.0    # seconds between rescans of its scene's doorways
const WORLD_PATH = "res://resources/world/world.json"
const ZONE_GROUP = "building_zones"

@export var creature_id: String = ""
## Seed for drops (the spawner sets it per spawn; tests fix it)
@export var drop_seed: int = 0

var def: Dictionary = {}
var max_health: float = 1.0
var health: float = 1.0
var is_alive: bool = true
var state: String = "idle"          # idle | stalk | charge | recoil | flee | loiter | return | dead
var target: Node2D = null
var last_attacker = null
var drops: Array = []               # [{item, qty}] rolled on death
var home: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _recoil: float = 0.0
var staggered_until_ms: int = 0
## The node its doorways are read from (the spawner sets the scene root; else its parent)
var zone_root: Node = null
var _zones: Array = []              # [{rect, indoors, name}] in global space (see door_zones)
var _zones_age: float = INF
var _loiter: float = 0.0
var _ignored: Node2D = null         # the quarry it gave up on at a door
var _ignored_until_ms: int = 0

static var _defs: Dictionary = {}
static var _locations: Dictionary = {}

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
	if collision_layer & 1:
		# a bare body starts on the player layer, where doors and travel points listen: move it to the
		# npc layer, blocked by walls and props like the scene bodies (scenes/creatures/*.tscn)
		collision_layer = 2
		collision_mask = 12
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
	if attacker is Node2D and (target == null or state in ["loiter", "return"]):
		target = attacker  # struck from outside its sense (or from a doorway): now it knows where you are
		_ignored = null
		if state in ["loiter", "return"]:
			_set_state("idle")
	if _should_flee():
		_set_state("flee")
	return {"health": health, "staggered": is_staggered(), "dead": false, "state": state}

func _should_flee() -> bool:
	return has("flee_when_hurt") and health < max_health * float(def.get("flee_below", 0.0))

## One step of behaviour: picks the state and returns the velocity (tests call it directly). Whatever
## the state, the step is kept out of doorways (_keep_out)
func think(delta: float) -> Vector2:
	if not is_alive or def.is_empty():
		return Vector2.ZERO
	_zones_age += delta
	if _zones_age >= ZONES_REFRESH:
		refresh_zones()
	return _keep_out(_decide(delta), delta)

func _decide(delta: float) -> Vector2:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if is_staggered():
		return Vector2.ZERO
	var sense = float(def.get("sense", 200.0))
	var speed = float(def.get("speed", 60.0))
	if target == null or not is_instance_valid(target) or target.get("is_alive") == false:
		target = _find_target(sense)
	if target == null:
		if state == "return":
			return _walk_home(speed)
		_set_state("idle")
		return Vector2.ZERO
	# Its quarry went in at a door: it cannot follow, so it waits outside, then gives up
	if state != "flee" and zone_at(target.global_position, true).size() > 0:
		if state != "loiter":
			_loiter = LOITER_SECONDS
			_set_state("loiter")
		_loiter -= delta
		if _loiter <= 0.0:
			give_up()
			return _walk_home(speed)
		var at_door: Vector2 = target.global_position - global_position
		if at_door.length() > float(def.get("reach", 32.0)) * 1.5:
			return at_door.normalized() * speed * STALK_FACTOR  # up to the door; _keep_out holds it outside
		return Vector2.ZERO
	if state == "loiter":
		_set_state("stalk")  # it came back out before the creature lost interest
	var to: Vector2 = target.global_position - global_position
	var dist = to.length()
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

## Loses interest in its quarry (gone in at a door): ignores it a while and walks back to its spot
func give_up() -> void:
	if target is Node2D:
		_ignored = target
		_ignored_until_ms = Time.get_ticks_msec() + int(FORGET_SECONDS * 1000.0)
	target = null
	_set_state("return")

func _walk_home(speed: float) -> Vector2:
	var to_home = _home_global() - global_position
	if to_home.length() <= HOME_RADIUS:
		_set_state("idle")
		return Vector2.ZERO
	return to_home.normalized() * speed * STALK_FACTOR

## home is in its parent's space (the spawner sets position and home together)
func _home_global() -> Vector2:
	var parent = get_parent()
	return parent.to_global(home) if parent is Node2D else home

func _find_target(sense: float) -> Node2D:
	if not is_inside_tree():
		return null
	for p in get_tree().get_nodes_in_group("player"):
		if not (p is Node2D) or not p.is_visible_in_tree() or p.global_position.distance_to(global_position) > sense:
			continue
		if p == _ignored and Time.get_ticks_msec() < _ignored_until_ms:
			continue
		if zone_at(p.global_position, true).size() > 0:
			continue  # in a doorway: indoors is out of its reach
		return p
	return null

# =============================================================================
# DOORWAYS (no creature goes indoors or through a scene transition)
# =============================================================================

## Whether a world.json location is a built structure creatures never enter: its `building` field,
## else true for kind "interior" and false otherwise. A location not (yet) in world.json is taken as
## a building, so a door added before its location is never a way in
static func is_building(location_id: String) -> bool:
	if _locations.is_empty():
		var file = FileAccess.open(WORLD_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				for loc in parsed.get("locations", []):
					if loc is Dictionary:
						_locations[str(loc.get("id", ""))] = loc
	if not _locations.has(location_id):
		return true
	return location_is_building(_locations[location_id])

static func location_is_building(loc: Dictionary) -> bool:
	if loc.get("building") is bool:
		return loc.building
	return str(loc.get("kind", "")) == "interior"

## Every doorway under `scene_root`: SceneTriggers (any scene transition) and Area2Ds in the
## "building_zones" group (a building's walkable footprint), each [{rect, indoors, name}], the rect in
## global space (scene_root's own space when it is not in the tree) and grown by `margin`. indoors:
## the door leads into a building (is_building) or the zone is one
static func door_zones(scene_root: Node, margin: float = DOOR_MARGIN) -> Array:
	var out: Array = []
	if scene_root == null:
		return out
	for area in scene_root.find_children("*", "Area2D", true, false):
		var leads = area.get("target_location")
		var zone = area.is_in_group(ZONE_GROUP) or area.has_meta(ZONE_GROUP)
		if leads == null and not zone:
			continue
		var indoors = zone or is_building(str(leads))
		for cs in area.get_children():
			if cs is CollisionShape2D and cs.shape and not cs.disabled:
				var rect = xform(cs, scene_root) * cs.shape.get_rect()
				out.append({"rect": rect.grow(margin), "indoors": indoors, "name": str(area.name)})
	return out

## node's transform in global space, or relative to `scene_root` when the scene is not in the tree
static func xform(node: Node, scene_root: Node) -> Transform2D:
	if node.is_inside_tree() and node is CanvasItem:
		return node.get_global_transform()
	var t = Transform2D.IDENTITY
	var n = node
	while n != null and n != scene_root:
		if n is Node2D:
			t = n.transform * t
		n = n.get_parent()
	return t

func refresh_zones() -> void:
	_zones_age = 0.0
	var root_ = zone_root if is_instance_valid(zone_root) else get_parent()
	_zones = door_zones(root_) if root_ else []

## The doorways at a global point (only those that lead indoors when `indoors_only`)
func zone_at(p: Vector2, indoors_only: bool = false) -> Array:
	if _zones_age >= ZONES_REFRESH:
		refresh_zones()
	return _zones.filter(func(z): return z.rect.has_point(p) and (z.indoors or not indoors_only))

## A step that would enter a doorway slides along it or stops; a creature already in one (shoved,
## fled or placed there) steps straight back out the nearest side
func _keep_out(v: Vector2, delta: float) -> Vector2:
	var here = global_position
	var inside = zone_at(here)
	if not inside.is_empty():
		var r: Rect2 = inside[0].rect
		var out = [Vector2(r.position.x - here.x, 0), Vector2(r.end.x - here.x, 0), Vector2(0, r.position.y - here.y), Vector2(0, r.end.y - here.y)]
		out.sort_custom(func(a, b): return a.length() < b.length())
		return out[0].normalized() * maxf(float(def.get("speed", 60.0)), v.length())
	if v == Vector2.ZERO:
		return v
	var step = maxf(delta, 1.0 / 60.0)
	if zone_at(here + v * step).is_empty():
		return v
	for slide in [Vector2(v.x, 0), Vector2(0, v.y)]:
		if slide != Vector2.ZERO and zone_at(here + slide * step).is_empty():
			return slide
	return Vector2.ZERO

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
