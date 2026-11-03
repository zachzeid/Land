extends Node
## Combat - the mechanics of a fight (docs/PLAYER_SYSTEMS.md §3): stamina-priced actions, damage
## types against armour, poise and stagger, blocks and parries, dodges, weapon wear, hit resolution,
## facing-based melee arcs and simple projectiles. Who fights and why (souls, morale, creatures,
## deaths and endings) is the combat-world slice: it listens to hit_landed / fight_ended and gives its
## bodies a hit through apply_hit_to. Deeds go through PlayerEvents.record, never NPC state
##
## A fighter is any Node2D in a FIGHTER_GROUPS group (or owning a hitbox_hurt.gd hurtbox). The player
## (group "player") draws on PlayerStats and Inventory. Anyone else may expose
## get_combat_profile() -> {weapon, armour: [ids], resist: {type: f}, poise, health, skills: {skill: f},
## difficulty, minor}, take_combat_hit(result, attacker) -> {health, staggered, dead},
## spend_stamina(n) -> bool, get_stamina() -> float; without them Combat keeps a plain pool of health
## and stamina for the body

signal hit_landed(info: Dictionary)
signal fight_ended(info: Dictionary)
## {weapon, item, owner}: an equipped weapon wore through (repairable at a forge later)
signal weapon_broke(info: Dictionary)
## {who, action, reason}: an action held back (stamina, minor, staggered, recovering, no_ammo)
signal action_refused(info: Dictionary)

const Witnesses = preload("res://scripts/world/witnesses.gd")
const Projectile = preload("res://scripts/combat/hitbox_projectile.gd")

const WEAPONS_PATH = "res://resources/combat/weapons.json"
const ARMOUR_PATH = "res://resources/combat/armour.json"
const DAMAGE_TYPES = ["cut", "pierce", "blunt", "fire"]
const FIGHTER_GROUPS = ["player", "npcs", "creatures", "fighters"]
const SOLID_MASK = 4                 # world_solid: walls stop swings and sight
const SLOT_WEAPON = "main_hand"
const SLOT_SHIELD = "off_hand"
const SLOT_ARMOUR = "body"   # Inventory's equipment slots: main_hand, off_hand, body, head, tool
const SLOT_HEAD = "head"

const COST_DODGE = 15.0
const COST_PARRY = 10.0
const COST_SHOOT = 12.0
const COST_SPRINT_PER_SEC = 8.0
const BLOCK_COST = 5.0               # per blocked hit of BLOCK_COST_PER raw damage
const BLOCK_COST_PER = 10.0
const PARRY_WINDOW = 0.25            # seconds after raising the guard
const PARRY_WINDOW_DEFENCE = 0.15    # extra at defence 100
const DODGE_SECONDS = 0.35           # invulnerable
const STAGGER_SECONDS = 1.0
const POISE_BASE = 40.0
const POISE_REGEN = 15.0             # per second, after POISE_REGEN_DELAY without a hit
const POISE_REGEN_DELAY = 2.0
const HEAVY_DAMAGE = 1.8
const HEAVY_POISE = 2.0
const HEAVY_TIME = 1.8
const SKILL_DAMAGE = 0.5             # +50% damage at skill 100
const SKILL_STAMINA = 0.3            # -30% stamina per swing at skill 100
const BLUNT_POISE = 0.5              # +50% poise damage at blunt 100
const DEFENCE_BLOCK = 0.4            # -40% stamina per block at defence 100
const RESIST_CAP = 0.8
const ARC_SLACK = 16.0               # a body's half-width: reach is to its edge
const FIGHT_TIMEOUT = 20.0           # seconds without a blow and a fight is over
const SPRINT_SKILL_EVERY = 1.0       # seconds of sprinting per athletics use
const BODY_HEALTH = 100.0
const BODY_STAMINA = 100.0
const BODY_STAMINA_REGEN = 20.0

## Tests (and later systems) can stand in for the autoloads
var stats_provider: Object = null
var inventory_provider: Object = null

var _weapons: Dictionary = {}
var _armour: Dictionary = {}
var _state: Dictionary = {}          # instance id -> fighter state
var _fights: Dictionary = {}         # "<id>|<id>" -> {aggressor, a, b, names, player, started, last, hits, damage, harmed}
var _first_strikes: Dictionary = {}  # "<id>|<id>" -> {by, at, seen_by, names, player}: who started it
var _clock: float = -1.0

func _ready() -> void:
	load_content()

func load_content(weapons_path: String = WEAPONS_PATH, armour_path: String = ARMOUR_PATH) -> void:
	_weapons = _read_json(weapons_path).get("weapons", {})
	_armour = _read_json(armour_path).get("armour", {})
	if not _weapons.has("fists"):
		_weapons["fists"] = {"name": "bare fists", "kind": "melee", "damage": {"blunt": 4}, "stamina": {"light": 10, "heavy": 25},
			"reach": 40, "arc": 70, "speed": 1.6, "poise": 5, "durability_per_hit": 0, "skill": "blunt", "block": 0.3}

func get_weapon_def(id: String) -> Dictionary:
	return _weapons.get(id, {}).duplicate(true)

func get_armour_def(id: String) -> Dictionary:
	return _armour.get(id, {}).duplicate(true)

# =============================================================================
# CONTRACT
# =============================================================================

## action: light | heavy | shoot (strikes), block | parry (raise the guard; a parry is a guard raised
## in time), dodge. target null: the first fighter in the facing arc (an NPC's swing passes through
## minors; the player's does not, docs/PLAYER_SYSTEMS.md §1.4).
## Returns the resolved hit, {} for a swing that met nothing, {"refused": reason} when held back
## (nothing spent), {"action", "ok"} for block/parry/dodge, {"action": "shoot", "projectile"} for a shot
func attack(attacker: Node, target: Node, action: String) -> Dictionary:
	if attacker == null:
		return {"refused": "no_attacker"}
	match action:
		"block", "parry":
			return {"action": action, "ok": begin_block(attacker)}
		"dodge":
			return {"action": action, "ok": dodge(attacker)}
		"light", "heavy", "shoot":
			pass
		_:
			return {"refused": "unknown_action"}
	var st = _state_of(attacker)
	if is_staggered(attacker):
		return _refuse(attacker, action, "staggered")
	if now() < float(st.ready_at):
		return _refuse(attacker, action, "recovering")
	var weapon = weapon_of(attacker)
	if str(weapon.get("kind", "melee")) == "ranged":
		action = "shoot"
	elif action == "shoot":
		return _refuse(attacker, action, "no_ranged_weapon")
	if target != null and not can_target_node(target, attacker):
		return _refuse(attacker, action, "minor")
	var ammo = str(weapon.get("ammo", ""))
	if action == "shoot" and ammo != "" and _is_player(attacker) and not _inventory_has(ammo):
		return _refuse(attacker, action, "no_ammo")
	# An NPC body that counts its arrows (BaseNPC.arrows_left) shoots only what it carries
	if action == "shoot" and ammo != "" and not _is_player(attacker) and attacker.has_method("arrows_left") and int(attacker.arrows_left()) <= 0:
		return _refuse(attacker, action, "no_ammo")
	if action != "shoot" and target == null:
		var found = targets_in_arc(attacker, weapon)
		var open = found.filter(func(n): return can_target_node(n, attacker))
		if not found.is_empty() and open.is_empty():
			return _refuse(attacker, action, "minor")
		target = open[0] if not open.is_empty() else null
	var cost = stamina_cost(attacker, weapon, action)
	if not _spend(attacker, cost):
		return _refuse(attacker, action, "stamina")
	st.blocking = false
	if target != null:
		_mark_first_strike(attacker, target)  # a swing that misses still starts the fight
	st.ready_at = now() + (1.0 / maxf(float(weapon.get("speed", 1.0)), 0.1)) * (HEAVY_TIME if action == "heavy" else 1.0)
	if action == "shoot":
		if ammo != "" and _is_player(attacker):
			_inventory().remove(ammo, 1)
		elif ammo != "" and attacker.has_method("spend_arrow"):
			attacker.spend_arrow()
		return {"action": "shoot", "stamina": cost, "projectile": shoot(attacker, weapon, target)}
	if target == null or not in_reach(attacker, target, weapon):
		return {}
	var result = resolve_hit(attacker, target, weapon, action)
	result["stamina"] = cost
	return result

## One blow that reached its target: dodge, parry, block, armour, poise, then the hit itself
## (apply_hit_to), wear, skill use, the harm deed and hit_landed. weapon {} = the attacker's own.
## Returns {damage, type, staggered, killed} plus blocked, parried, dodged, guard_broken,
## poise_damage, raw, broke, attacker_staggered, action, weapon
func resolve_hit(attacker: Node, target: Node, weapon: Dictionary, action: String) -> Dictionary:
	if weapon.is_empty():
		weapon = weapon_of(attacker)
	elif not weapon.has("damage"):
		weapon = make_weapon(weapon)  # an item record ({id, durability, ...}): look its stats up
	var by_type = raw_damage(attacker, weapon, action)
	var raw = _sum(by_type)
	var result = {"damage": 0.0, "type": _main_type(by_type), "staggered": false, "killed": false,
		"blocked": false, "parried": false, "dodged": false, "guard_broken": false, "poise_damage": 0.0,
		"raw": raw, "broke": false, "attacker_staggered": false, "action": action, "weapon": str(weapon.get("id", "fists"))}
	if target == null or not can_target_node(target, attacker):
		return result
	var ts = _state_of(target)
	var t = now()
	if t < float(ts.invulnerable_until):
		result.dodged = true
		if _is_player(target):
			_use_skill("athletics", difficulty_of(attacker), {"action": "dodge", "against": fighter_key(attacker)})
		return result
	var poise_dmg = float(weapon.get("poise", 0)) * (HEAVY_POISE if action == "heavy" else 1.0)
	if str(weapon.get("skill", "")) == "blunt":
		poise_dmg *= 1.0 + BLUNT_POISE * _skill(attacker, "blunt") / 100.0
	if ts.blocking:
		if action != "shoot" and t - float(ts.block_started) <= parry_window(target) and _spend(target, COST_PARRY):
			result.parried = true
			result.attacker_staggered = true
			stagger(attacker)
			if _is_player(target):
				_use_skill("defence", difficulty_of(attacker) * 1.5, {"action": "parry", "against": fighter_key(attacker)})
			_note_fight(attacker, target)
			_emit_hit(attacker, target, result)
			return result
		var block_share = block_share_of(target, action)
		var cost = BLOCK_COST * maxf(raw / BLOCK_COST_PER, 0.5) * (1.0 - DEFENCE_BLOCK * _skill(target, "defence") / 100.0)
		if block_share > 0.0 and _spend(target, cost):
			result.blocked = true
			for k in by_type:
				by_type[k] = float(by_type[k]) * (1.0 - block_share)
			poise_dmg *= 1.0 - block_share
			if _is_player(target):
				_use_skill("defence", difficulty_of(attacker), {"action": "block", "against": fighter_key(attacker)})
		elif block_share > 0.0:
			# Out of stamina the guard gives way
			result.guard_broken = true
			ts.blocking = false
			stagger(target)
			result.staggered = true
	var resist = resist_of(target)
	var dealt = 0.0
	for k in by_type:
		dealt += float(by_type[k]) * (1.0 - float(resist.get(k, 0.0)))
	result.damage = snappedf(maxf(dealt, 0.0), 0.1)
	result.poise_damage = snappedf(poise_dmg, 0.1)
	ts.poise = float(ts.poise) - poise_dmg
	ts.poise_hit_at = t
	if float(ts.poise) <= 0.0:
		ts.poise = poise_max_of(target)
		stagger(target)
		result.staggered = true
	var applied = apply_hit_to(target, result, attacker)
	result.killed = bool(applied.get("dead", false))
	if bool(applied.get("staggered", false)) and not result.staggered:
		stagger(target)
		result.staggered = true
	_after_hit(attacker, target, weapon, action, result)
	return result

## docs/PLAYER_SYSTEMS.md §1.4: the player may strike anyone, children included (at the heaviest
## cost: the deed carries victim_minor). NPCs, creatures and crowds never target a minor
## (WorldRegistry.is_minor). attacker_key "" is anyone but the player
func can_target(target_key: String, attacker_key: String = "") -> bool:
	if attacker_key == "player":
		return target_key != "" and target_key != "player"
	return not is_minor_key(target_key)

func is_minor_key(key: String) -> bool:
	var registry = get_node_or_null("/root/WorldRegistry")
	return key != "" and key != "player" and registry != null and registry.has_method("is_minor") and registry.is_minor(key)

## The body itself: alive, and (unless the player is the one striking) not a minor
func can_target_node(node: Node, attacker: Node = null) -> bool:
	if node == null or not is_instance_valid(node) or node.get("is_alive") == false:
		return false
	if _is_player(attacker):
		return node != attacker
	if is_minor_node(node):
		return false
	return can_target(fighter_key(node))

func is_minor_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.get("minor") == true or bool(profile_of(node).get("minor", false)) or is_minor_key(fighter_key(node))

## Give a body a resolved hit. The player's goes to PlayerStats.damage; a body with
## take_combat_hit(result, attacker) handles its own; anyone else uses Combat's plain pool.
## NPC bodies, creatures and world physics may call this with their own result
## ({damage, type, ...}). Returns {health, staggered, dead}
func apply_hit_to(target: Node, result: Dictionary, attacker: Node = null) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {"health": 0.0, "staggered": false, "dead": false}
	var amount = float(result.get("damage", 0.0))
	var type = str(result.get("type", "blunt"))
	if _is_player(target):
		var stats = _stats()
		return stats.damage(amount, type, fighter_key(attacker) if attacker else "") if stats else {"health": 0.0, "staggered": false, "dead": false}
	if target.has_method("take_combat_hit"):
		return target.take_combat_hit(result, attacker)
	if target.has_method("take_hit"):
		return target.take_hit(result, attacker)  # NPC bodies and creatures (combat world)
	var st = _state_of(target)
	st.health = maxf(float(st.health) - amount, 0.0)
	return {"health": st.health, "staggered": false, "dead": float(st.health) <= 0.0}

# =============================================================================
# DEFENSIVE ACTIONS
# =============================================================================

## Raise the guard. Out of stamina there is no guard (§3)
func begin_block(node: Node) -> bool:
	if node == null or is_staggered(node) or _stamina_of(node) <= 0.0:
		return false
	var st = _state_of(node)
	if not st.blocking:
		st.blocking = true
		st.block_started = now()
	return true

func end_block(node: Node) -> void:
	if node:
		_state_of(node).blocking = false

func is_blocking(node: Node) -> bool:
	return node != null and bool(_state_of(node).blocking)

## Wider with defence
func parry_window(node: Node) -> float:
	return PARRY_WINDOW + PARRY_WINDOW_DEFENCE * _skill(node, "defence") / 100.0

## A short invulnerable roll; the body moves itself (player.gd). Returns false when refused
func dodge(node: Node) -> bool:
	if node == null:
		return false
	if is_staggered(node):
		_refuse(node, "dodge", "staggered")
		return false
	if not _spend(node, COST_DODGE):
		_refuse(node, "dodge", "stamina")
		return false
	var st = _state_of(node)
	st.blocking = false
	st.invulnerable_until = now() + DODGE_SECONDS
	if _is_player(node):
		_use_skill("athletics", 0.5, {"action": "dodge"})
	return true

func is_invulnerable(node: Node) -> bool:
	return node != null and now() < float(_state_of(node).invulnerable_until)

## Pay for delta seconds of sprinting. false: out of stamina, walk
func sprint_tick(node: Node, delta: float) -> bool:
	if node == null or delta <= 0.0:
		return false
	if not _spend(node, COST_SPRINT_PER_SEC * delta):
		return false
	if _is_player(node):
		var st = _state_of(node)
		st.sprint_time = float(st.sprint_time) + delta
		while float(st.sprint_time) >= SPRINT_SKILL_EVERY:
			st.sprint_time = float(st.sprint_time) - SPRINT_SKILL_EVERY
			_use_skill("athletics", 0.3, {"action": "sprint"})
	return true

func stagger(node: Node, seconds: float = STAGGER_SECONDS) -> void:
	if node == null:
		return
	var st = _state_of(node)
	st.staggered_until = maxf(float(st.staggered_until), now() + seconds)
	st.blocking = false
	if node.has_method("on_staggered"):
		node.on_staggered(seconds)

func is_staggered(node: Node) -> bool:
	return node != null and now() < float(_state_of(node).staggered_until)

func get_poise(node: Node) -> float:
	return float(_state_of(node).poise)

# =============================================================================
# WEAPONS, ARMOUR, NUMBERS
# =============================================================================

## The weapon a fighter strikes with: the stats of its main-hand item (weapons.json by item id),
## or fists for no weapon, a non-weapon, or a broken one. Adds id, item (the record), broken, was
func weapon_of(node: Node) -> Dictionary:
	if node == null:
		return make_weapon({})
	if _is_player(node):
		var inv = _inventory()
		return make_weapon(inv.get_equipped(SLOT_WEAPON) if inv else {})
	var w = profile_of(node).get("weapon", node.get("combat_weapon"))
	if w is Dictionary and w.get("natural", false):
		return _natural_weapon(w)
	if w is Dictionary:
		return make_weapon(w)
	return make_weapon({"id": str(w)} if w != null else {})

## A creature's teeth, tusks or fangs ({id, name, damage, type, poise_damage, natural}) as a weapon
func _natural_weapon(w: Dictionary) -> Dictionary:
	var fists: Dictionary = _weapons.get("fists", {})
	var weapon = fists.duplicate(true)
	weapon["id"] = str(w.get("id", "natural"))
	weapon["name"] = str(w.get("name", "teeth"))
	var damage = w.get("damage", 0.0)
	weapon["damage"] = damage.duplicate() if damage is Dictionary else {str(w.get("type", "cut")): float(damage)}
	weapon["poise"] = float(w.get("poise_damage", weapon.get("poise", 0.0)))
	weapon["durability_per_hit"] = 0.0
	weapon["skill"] = ""
	weapon["item"] = {}
	weapon["broken"] = false
	return weapon

func make_weapon(record: Dictionary) -> Dictionary:
	var id = str(record.get("id", ""))
	var def: Dictionary = _weapons.get(id, {})
	if def.is_empty():
		id = "fists"
		def = _weapons.fists
	var weapon = def.duplicate(true)
	weapon["id"] = id
	weapon["item"] = record
	weapon["broken"] = false
	if id != "fists" and record.has("durability") and float(record.durability) <= 0.0:
		# A broken weapon hits like fists until it is mended
		weapon = _weapons.fists.duplicate(true)
		weapon["id"] = "fists"
		weapon["item"] = record
		weapon["broken"] = true
		weapon["was"] = id
	return weapon

## Raw damage by type before blocks and armour: weapon x action x the weapon skill
func raw_damage(attacker: Node, weapon: Dictionary, action: String) -> Dictionary:
	var out = {}
	var mult = (HEAVY_DAMAGE if action == "heavy" else 1.0) * (1.0 + SKILL_DAMAGE * _skill(attacker, str(weapon.get("skill", ""))) / 100.0)
	var dmg: Dictionary = weapon.get("damage", {})
	for k in dmg:
		out[k] = float(dmg[k]) * mult
	return out

func stamina_cost(attacker: Node, weapon: Dictionary, action: String) -> float:
	var costs: Dictionary = weapon.get("stamina", {})
	var base = float(costs.get(action, COST_SHOOT if action == "shoot" else (25.0 if action == "heavy" else 10.0)))
	if action == "shoot":
		return base
	return snappedf(base * (1.0 - SKILL_STAMINA * _skill(attacker, str(weapon.get("skill", ""))) / 100.0), 0.01)

## Armour resistances, summed over pieces and the body's own, capped (weakness may go below 0)
func resist_of(node: Node) -> Dictionary:
	var out = {}
	for def in _armour_defs(node):
		var r: Dictionary = def.get("resist", {})
		for k in r:
			out[k] = float(out.get(k, 0.0)) + float(r[k])
	var own: Dictionary = profile_of(node).get("resist", {})
	for k in own:
		out[k] = float(out.get(k, 0.0)) + float(own[k])
	for k in out:
		out[k] = clampf(float(out[k]), -1.0, RESIST_CAP)
	return out

func poise_max_of(node: Node) -> float:
	var p = float(profile_of(node).get("poise", POISE_BASE))
	for def in _armour_defs(node):
		p += float(def.get("poise", 0))
	return p

## A shield's share of a blocked hit, else the weapon's. Arrows only stop on a shield
func block_share_of(node: Node, action: String = "light") -> float:
	for def in _armour_defs(node):
		if str(def.get("slot", "")) == SLOT_SHIELD and def.has("block"):
			return float(def.block)
	return 0.0 if action == "shoot" else float(weapon_of(node).get("block", 0.3))

## Skill gain difficulty from the target: its profile, a practice post a tenth, nothing from the dead
## or the sleeping (a skill only rises when the act could fail)
func difficulty_of(node: Node) -> float:
	if node == null or node.get("is_alive") == false or node.get("asleep") == true:
		return 0.0
	var prof = profile_of(node)
	if prof.has("difficulty"):
		return float(prof.difficulty)
	if node.is_in_group("practice"):
		return 0.1
	return 1.0

# =============================================================================
# REACH: facing arcs and projectiles
# =============================================================================

## Fighters inside the weapon's reach and facing arc, nearest first, not behind a wall
func targets_in_arc(attacker: Node, weapon: Dictionary = {}) -> Array:
	if weapon.is_empty():
		weapon = weapon_of(attacker)
	var found: Array = []
	if not (attacker is Node2D) or not attacker.is_inside_tree():
		return found
	for node in fighters():
		if node != attacker and in_reach(attacker, node, weapon):
			found.append(node)
	var origin: Vector2 = attacker.global_position
	found.sort_custom(func(a, b): return origin.distance_to(a.global_position) < origin.distance_to(b.global_position))
	return found

func in_reach(attacker: Node, target: Node, weapon: Dictionary) -> bool:
	if not (attacker is Node2D and target is Node2D) or target.get("is_alive") == false:
		return false
	var to: Vector2 = target.global_position - attacker.global_position
	if to.length() > float(weapon.get("reach", 40)) + ARC_SLACK:
		return false
	if to.length() > 4.0 and absf(facing_of(attacker).angle_to(to)) > deg_to_rad(float(weapon.get("arc", 90)) / 2.0):
		return false
	if attacker.is_inside_tree():
		var query = PhysicsRayQueryParameters2D.create(attacker.global_position, target.global_position, SOLID_MASK)
		query.collide_with_areas = false
		if not attacker.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true

## Nothing on world_solid (walls, buildings) between two bodies: a shot or a look can pass
func has_line_of_sight(a: Node, b: Node) -> bool:
	if not (a is Node2D and b is Node2D) or not a.is_inside_tree():
		return false
	var query = PhysicsRayQueryParameters2D.create(a.global_position, b.global_position, SOLID_MASK)
	query.collide_with_areas = false
	return a.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## A minor stands within `margin` pixels of the line from shooter to target, between them: an NPC
## holds the shot (the arrow would pass a child by, but nobody looses past a child)
func minor_in_line(shooter: Node, target: Node, margin: float = 20.0) -> bool:
	if not (shooter is Node2D and target is Node2D) or not shooter.is_inside_tree():
		return false
	var from: Vector2 = shooter.global_position
	var to: Vector2 = target.global_position
	for node in fighters():
		if node == shooter or node == target or not is_minor_node(node):
			continue
		var p: Vector2 = node.global_position
		var seg = to - from
		var along = clampf((p - from).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
		if along > 0.0 and along < 1.0 and p.distance_to(from + seg * along) <= margin:
			return true
	return false

func facing_of(node: Node) -> Vector2:
	if node.has_method("get_facing_vector"):
		return node.get_facing_vector()
	var f = node.get("facing")
	return f.normalized() if f is Vector2 and f != Vector2.ZERO else Vector2.DOWN

## Every fighter body in the tree (groups and hurtbox owners)
func fighters() -> Array:
	var out: Array = []
	for g in FIGHTER_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node2D and n.is_visible_in_tree() and not n in out:
				out.append(n)
	for box in get_tree().get_nodes_in_group("hurtboxes"):
		var f = box.fighter() if box.has_method("fighter") else null
		if f is Node2D and f.is_visible_in_tree() and not f in out:
			out.append(f)
	return out

## The fighter a collider belongs to (a hurtbox's owner, or a fighter body itself), else null
func fighter_of(collider: Object) -> Node:
	if collider == null:
		return null
	if collider.has_method("fighter"):
		return collider.fighter()
	if collider is Node:
		for g in FIGHTER_GROUPS:
			if collider.is_in_group(g):
				return collider
	return null

## Loose a shot toward target (or along facing). Returns the projectile, null outside a scene
func shoot(attacker: Node, weapon: Dictionary, target: Node = null) -> Node:
	if not (attacker is Node2D) or not attacker.is_inside_tree():
		return null
	var dir: Vector2 = (target.global_position - attacker.global_position).normalized() if target is Node2D else facing_of(attacker)
	var p = Projectile.new()
	p.shooter = attacker
	p.weapon = weapon
	p.direction = dir if dir != Vector2.ZERO else Vector2.DOWN
	p.speed = float(weapon.get("projectile_speed", 500))
	p.max_distance = float(weapon.get("reach", 400))
	_scene_root_of(attacker).add_child(p)
	p.global_position = attacker.global_position
	return p

# =============================================================================
# FIGHTS AND DEEDS
# =============================================================================

## Combat world ends a fight it decided: reason yielded | fled | spared | talked_down | ...
func end_fight(a: Node, b: Node, reason: String, extra: Dictionary = {}) -> void:
	var key = _fight_key(a, b)
	if _fights.has(key):
		_finish(key, reason, extra)

## The open fight between two bodies ({} when none): names, player, started, last, hits, damage, harmed
func get_fight(a: Node, b: Node) -> Dictionary:
	return _fights.get(_fight_key(a, b), {}).duplicate()

func _after_hit(attacker: Node, target: Node, weapon: Dictionary, action: String, result: Dictionary) -> void:
	var player_struck = _is_player(attacker)
	if player_struck:
		var item: Dictionary = weapon.get("item", {})
		var wear = float(weapon.get("durability_per_hit", 0))
		var inv = _inventory()
		if inv and not bool(weapon.get("broken", false)) and str(weapon.get("id")) != "fists" and wear > 0.0 and not item.is_empty():
			if bool(inv.wear(SLOT_WEAPON, wear).get("broke", false)):
				result.broke = true
				weapon_broke.emit({"weapon": weapon.id, "item": item, "owner": fighter_key(attacker)})
		_use_skill(str(weapon.get("skill", "blunt")), difficulty_of(target), {"action": action, "target": fighter_key(target), "damage": result.damage})
	var fight = _note_fight(attacker, target)
	var tkey = fighter_key(target)
	fight.damage[tkey] = float(fight.damage.get(tkey, 0.0)) + float(result.damage)
	if player_struck and is_person(target) and not fight.harmed.has(tkey):
		fight.harmed[tkey] = _record_harm(attacker, target, weapon)
	_emit_hit(attacker, target, result)
	if result.killed:
		_finish(_fight_key(attacker, target), "killed", {"killed": tkey, "by": fighter_key(attacker)})

## The player struck a person: `harm` about them, seen by whoever has line of sight (and the struck).
## A child carries victim_minor (the heaviest weight); a blow struck back at someone who went for the
## player first carries self_defence, known to whoever saw that first blow (and the one who struck it)
func _record_harm(attacker: Node, target: Node, weapon: Dictionary) -> String:
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe == null:
		return ""
	var key = fighter_key(target)
	var at: Vector2 = target.global_position if target is Node2D else Vector2.ZERO
	var witnesses = Witnesses.in_sight(_scene_root_of(target), at, {"stealth": _skill(attacker, "stealth")})
	if not key in witnesses:
		witnesses.append(key)
	var how = "bare-handed" if str(weapon.get("id")) == "fists" else "with a %s" % str(weapon.get("name", "weapon"))
	var opts = {"witnesses": witnesses, "victim_minor": is_minor_node(target)}
	opts.merge(self_defence_opts(attacker, target), true)
	return pe.record("harm", "struck %s %s" % [display_name(target), how], [key], opts)

## {self_defence, self_defence_seen_by} for the player's deed against `target` ({} when the player
## struck first, or there is no player in it). Children never strike first, so never for a minor
func self_defence_opts(a: Node, b: Node) -> Dictionary:
	var player = a if _is_player(a) else (b if _is_player(b) else null)
	var other = b if player == a else a
	if player == null or other == null or is_minor_node(other):
		return {}
	var first = first_strike(a, b)
	if first.is_empty() or str(first.by) == "player":
		return {}
	var seen: Array = first.get("seen_by", []).duplicate()
	if not str(first.by) in seen:
		seen.append(str(first.by))
	return {"self_defence": true, "self_defence_seen_by": seen}

## The same, by the other fighter's key (CombatAI records kills from an NPC body that only knows keys)
func self_defence_against(opponent_key: String) -> Dictionary:
	for fk in _first_strikes:
		var f: Dictionary = _first_strikes[fk]
		if f.get("player", false) and opponent_key in f.get("names", []):
			if str(f.by) == "player" or is_minor_key(opponent_key):
				return {}
			var seen: Array = f.get("seen_by", []).duplicate()
			if not str(f.by) in seen:
				seen.append(str(f.by))
			return {"self_defence": true, "self_defence_seen_by": seen}
	return {}

## Who struck first between two bodies: {by (fighter key), at, seen_by (npc ids that saw the first
## blow), names, player} or {}
func first_strike(a: Node, b: Node) -> Dictionary:
	return _first_strikes.get(_fight_key(a, b), {}).duplicate(true)

## The first blow (landed or not) between two bodies is remembered with who saw it. A player fight
## asks Witnesses who could see the one who struck it
func _mark_first_strike(attacker: Node, target: Node) -> void:
	var key = _fight_key(attacker, target)
	if _first_strikes.has(key) and (_fights.has(key) or now() - float(_first_strikes[key].at) <= FIGHT_TIMEOUT):
		return
	var player = _is_player(attacker) or _is_player(target)
	var by = fighter_key(attacker)
	# Someone standing up for the player's victim answers the player's violence; they did not start it
	if player and not _is_player(attacker) and str(attacker.get("combat_side")) == "defend":
		by = "player"
	var seen: Array = []
	if player and by != "player" and attacker is Node2D and attacker.is_inside_tree():
		seen = Witnesses.in_sight(_scene_root_of(attacker), attacker.global_position, {"exclude": [fighter_key(attacker)]})
	_first_strikes[key] = {"by": by, "at": now(), "seen_by": seen,
		"names": [fighter_key(attacker), fighter_key(target)], "player": player}

## A person (roster, generic, or an NPC body), not a creature: striking one is a deed
func is_person(node: Node) -> bool:
	if node == null or node.is_in_group("creatures"):
		return false
	var key = fighter_key(node)
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry and registry.has_method("get_npc_key") and registry.get_npc_key(key) != "":
		return true
	var dyn = get_node_or_null("/root/DynamicNPCRegistry")
	var gm = dyn.generics if dyn and "generics" in dyn else null
	return (gm != null and gm.is_generic(key)) or node.is_in_group("npcs")

func display_name(node: Node) -> String:
	var n = node.get("npc_name")
	if n != null and str(n) != "":
		return str(n)
	var registry = get_node_or_null("/root/WorldRegistry")
	var key = registry.get_npc_key(fighter_key(node)) if registry else ""
	return registry.get_npc_name(key) if key != "" else "someone"

func _note_fight(a: Node, b: Node) -> Dictionary:
	var key = _fight_key(a, b)
	if not _fights.has(key):
		_mark_first_strike(a, b)  # a blow that came by another road (a projectile, resolve_hit directly)
		_fights[key] = {"aggressor": str(_first_strikes[key].by), "a": weakref(a), "b": weakref(b), "names": [fighter_key(a), fighter_key(b)],
			"player": _is_player(a) or _is_player(b), "started": now(), "last": now(), "hits": 0, "damage": {}, "harmed": {}}
	var f = _fights[key]
	f.last = now()
	f.hits += 1
	return f

func _finish(key: String, reason: String, extra: Dictionary = {}) -> void:
	var f = _fights[key]
	_fights.erase(key)
	var info = {"participants": f.names, "player": f.player, "reason": reason, "hits": f.hits, "aggressor": str(f.get("aggressor", "")),
		"damage": f.damage, "harm_events": f.harmed.values(), "started": f.started, "ended": now()}
	info.merge(extra, true)
	fight_ended.emit(info)

func _emit_hit(attacker: Node, target: Node, result: Dictionary) -> void:
	var info = result.duplicate()
	info["attacker"] = attacker
	info["target"] = target
	info["attacker_key"] = fighter_key(attacker)
	info["target_key"] = fighter_key(target)
	info["position"] = target.global_position if target is Node2D else Vector2.ZERO
	hit_landed.emit(info)

func _fight_key(a: Node, b: Node) -> String:
	var ids = [a.get_instance_id() if a else 0, b.get_instance_id() if b else 0]
	ids.sort()
	return "%d|%d" % ids

# =============================================================================
# CLOCK, STATE, PROVIDERS
# =============================================================================

## Seconds of real time. Tests pin it with set_test_clock(t); t < 0 restores it
## Seconds of unpaused play (not the wall clock): a pause stops recovery, stagger and block timing,
## and frame-locked runs (--write-movie) keep the same rhythm as real play. Tests pin it
func now() -> float:
	return _clock if _clock >= 0.0 else _play_time

func set_test_clock(t: float) -> void:
	_clock = t

## Forget every fighter's state and every open fight (tests, loads)
func reset() -> void:
	_state.clear()
	_fights.clear()
	_first_strikes.clear()

var _play_time: float = 0.0

func _process(delta: float) -> void:
	_play_time += delta
	var t = now()
	for id in _state.keys():
		var st = _state[id]
		var node = instance_from_id(id)
		if node == null or not is_instance_valid(node):
			_state.erase(id)
			continue
		if t - float(st.poise_hit_at) > POISE_REGEN_DELAY:
			st.poise = minf(float(st.poise) + POISE_REGEN * delta, poise_max_of(node))
		if not _is_player(node) and not node.has_method("spend_stamina"):
			st.stamina = minf(float(st.stamina) + BODY_STAMINA_REGEN * delta, BODY_STAMINA)
	for key in _fights.keys():
		var f = _fights[key]
		var gone = f.a.get_ref() == null or f.b.get_ref() == null
		if gone or t - float(f.last) > FIGHT_TIMEOUT:
			_finish(key, "gone" if gone else "parted")
	for key in _first_strikes.keys():
		if not _fights.has(key) and t - float(_first_strikes[key].at) > FIGHT_TIMEOUT * 2.0:
			_first_strikes.erase(key)

func _state_of(node: Node) -> Dictionary:
	var id = node.get_instance_id()
	if not _state.has(id):
		_state[id] = {"blocking": false, "block_started": -100.0, "invulnerable_until": -100.0,
			"staggered_until": -100.0, "poise": poise_max_of(node), "poise_hit_at": -100.0, "ready_at": -100.0,
			"stamina": BODY_STAMINA, "health": float(profile_of(node).get("health", BODY_HEALTH)), "sprint_time": 0.0}
	return _state[id]

func profile_of(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	if node.has_method("get_combat_profile"):
		var p = node.get_combat_profile()
		return p if p is Dictionary else {}
	# NPC bodies and creatures (combat world) describe themselves piecemeal
	var out: Dictionary = {}
	if node.has_method("get_resistances"):
		out["resist"] = node.get_resistances()
	if node.has_method("get_weapon"):
		out["weapon"] = node.get_weapon()
	if node.get("health") != null:
		out["health"] = float(node.get("health"))
	if node.get("minor") != null:
		out["minor"] = bool(node.get("minor"))
	return out

func fighter_key(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if _is_player(node):
		return "player"
	for prop in ["npc_id", "creature_id"]:
		var v = node.get(prop)
		if v != null and str(v) != "":
			return str(v)
	return str(node.name)

func _is_player(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_in_group("player")

func _armour_defs(node: Node) -> Array:
	var ids: Array = []
	if _is_player(node):
		var inv = _inventory()
		if inv:
			for slot in [SLOT_ARMOUR, SLOT_HEAD, SLOT_SHIELD]:
				var rec: Dictionary = inv.get_equipped(slot)
				# Broken armour still sits on the body but no longer turns a blade
				if not rec.is_empty() and not (rec.has("durability") and float(rec.durability) <= 0.0):
					ids.append(str(rec.get("id", "")))
	else:
		ids = profile_of(node).get("armour", [])
	var out: Array = []
	for id in ids:
		if _armour.has(str(id)):
			out.append(_armour[str(id)])
	return out

func _skill(node: Node, skill: String) -> float:
	if node == null or skill == "":
		return 0.0
	if _is_player(node):
		var stats = _stats()
		return float(stats.get_skill(skill)) if stats else 0.0
	return float(profile_of(node).get("skills", {}).get(skill, 0.0))

func _use_skill(skill: String, difficulty: float, context: Dictionary) -> void:
	var stats = _stats()
	if stats and difficulty > 0.0:
		stats.use_skill(skill, difficulty, context)

func _stamina_of(node: Node) -> float:
	if _is_player(node):
		var stats = _stats()
		return float(stats.get_stamina()) if stats else 0.0
	if node.has_method("get_stamina"):
		return float(node.get_stamina())
	return float(_state_of(node).stamina)

func _spend(node: Node, amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _is_player(node):
		var stats = _stats()
		return stats != null and stats.spend_stamina(amount)
	if node.has_method("spend_stamina"):
		return node.spend_stamina(amount)
	var st = _state_of(node)
	if float(st.stamina) < amount:
		return false
	st.stamina = float(st.stamina) - amount
	return true

func _refuse(node: Node, action: String, reason: String) -> Dictionary:
	action_refused.emit({"who": fighter_key(node), "action": action, "reason": reason})
	return {"refused": reason, "action": action}

func _stats() -> Object:
	return stats_provider if stats_provider else get_node_or_null("/root/PlayerStats")

func _inventory() -> Object:
	return inventory_provider if inventory_provider else get_node_or_null("/root/Inventory")

func _inventory_has(item_id: String) -> bool:
	var inv = _inventory()
	return inv != null and inv.has(item_id, 1)

func _scene_root_of(node: Node) -> Node:
	var n = node
	while n.get_parent() and n.get_parent() != get_tree().root:
		n = n.get_parent()
	return n

func _sum(d: Dictionary) -> float:
	var s = 0.0
	for k in d:
		s += float(d[k])
	return s

func _main_type(d: Dictionary) -> String:
	var best = "blunt"
	var most = -1.0
	for k in d:
		if float(d[k]) > most:
			most = float(d[k])
			best = str(k)
	return best

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[Combat] Missing %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

## A fight does not outlive a save: wear lives on the items (Inventory), skill in PlayerStats
func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	reset()
