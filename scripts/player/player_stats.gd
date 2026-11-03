extends Node
## PlayerStats - health, stamina, poise, skills (use-based), level (derived), perks, difficulty, death
## docs/PLAYER_SYSTEMS.md §2-3. Skills and perks are data (resources/player/{skills,perks}.json).
## Deeds go through PlayerEvents.record, never NPC state: a death is a `fell` deed, a skill seen past
## 25/50/75 a `feat`; respect from a feat in a witness's own trade is an adjust_relationship effect
## applied through StorylineDirector as that witness. Teaching lives in teaching.gd (get_teaching())

const Witnesses = preload("res://scripts/world/witnesses.gd")
const Teaching = preload("res://scripts/player/teaching.gd")

const SKILLS_PATH = "res://resources/player/skills.json"
const PERKS_PATH = "res://resources/player/perks.json"
const RESPAWN_PATH = "res://resources/player/respawn.json"

const BASE_HEALTH = 100.0
const BASE_STAMINA = 100.0
const PER_LEVEL = 5.0                 # max health and stamina per derived level
const ATHLETICS_STAMINA = 0.5         # extra max stamina per athletics point (§3 "+ athletics")
const MAX_LEVEL = 20
const SKILL_CAP = 100.0
const GAIN_CURVE = 110.0              # gain x (1 - level/110): fast early, slow mastery (Valheim)
const MAX_POISE = 100.0
const BLUNT_POISE = 1.5               # blunt hits drain poise faster
const STAMINA_DELAY = 1.0             # seconds after spending before stamina returns
const STAMINA_REGEN = 25.0            # per second, scaled up by athletics
const HEALTH_DELAY = 10.0             # seconds out of harm before health returns
const HEALTH_REGEN = 0.5              # per second
const POISE_REGEN = 20.0              # per second
## Death: normal loses (deaths)% to 25%; hard doubles each death (1, 2, 4...) to 50% (lead's ruling)
const NORMAL_LOSS_CAP = 25.0
const HARD_LOSS_CAP = 50.0
const WAKE_MINUTES = 240              # the player wakes some hours after falling
const FEAT_RESPECT = {25: 3, 50: 5, 75: 8}

signal skill_raised(skill: String, level: float, milestone: int)
signal died(info: Dictionary)

var difficulty: String = "normal"   # "normal" | "hard", chosen at a new game (docs/PLAYER_SYSTEMS.md §2)

## Seams for tests and other scenes (null = the autoloads / the "player" group)
var inventory = null
var director = null
var body: Node2D = null
var move_on_respawn: bool = true     # false in headless tests: report the respawn, do not change scene

var _skill_defs: Dictionary = {}     # id -> definition
var _skill_order: Array = []
var _perk_defs: Array = []
var _inns: Array = []
var _milestones: Array = [25, 50, 75, 100]
var _feat_milestones: Array = [25, 50, 75]

var _skills: Dictionary = {}         # id -> 0..100
var _perks: Array = []
var _feats: Dictionary = {}          # skill -> [milestones already shown to someone]
var _training: Dictionary = {}       # skill -> {multiplier, until} (game minutes)
var _health: float = BASE_HEALTH
var _stamina: float = BASE_STAMINA
var _poise: float = MAX_POISE
var _deaths: int = 0
var _respawn: Dictionary = {}        # {location, spawn_point}: the last bed
var _since_spend: float = 999.0
var _since_hurt: float = 999.0
var _teaching = null

func _ready():
	load_content()
	reset()

func load_content() -> void:
	var data = _read_json(SKILLS_PATH)
	_skill_defs.clear()
	_skill_order.clear()
	for s in data.get("skills", []):
		_skill_defs[str(s.id)] = s
		_skill_order.append(str(s.id))
	if data.get("milestones") is Array:
		_milestones = data.milestones.map(func(m): return int(m))
	if data.get("feat_milestones") is Array:
		_feat_milestones = data.feat_milestones.map(func(m): return int(m))
	_perk_defs = _read_json(PERKS_PATH).get("perks", [])
	_inns = _read_json(RESPAWN_PATH).get("inns", [])

## A new game: every skill at 0, full health and stamina, no deaths
func reset() -> void:
	_skills.clear()
	for id in _skill_order:
		_skills[id] = 0.0
	_perks.clear()
	_feats.clear()
	_training.clear()
	_deaths = 0
	_respawn = {}
	_poise = MAX_POISE
	_since_spend = 999.0
	_since_hurt = 999.0
	_health = get_max_health()
	_stamina = get_max_stamina()

func get_skill_ids() -> Array:
	return _skill_order.duplicate()

func get_skill_def(skill: String) -> Dictionary:
	return _skill_defs.get(skill, {})

## "normal" or "hard"; anything else is refused (returns false)
func set_difficulty(value: String) -> bool:
	if value not in ["normal", "hard"]:
		push_warning("[PlayerStats] Unknown difficulty '%s'" % value)
		return false
	difficulty = value
	return true

# =============================================================================
# SKILLS
# =============================================================================

## Use a skill: gain = base_xp x difficulty x (1 - level/110). difficulty_factor 0 = the action could
## not fail (no gain). context: {witnessed_by: [ids], scene_root, position, about: [], feat_summary,
## base_xp}. With no witnessed_by but a scene_root and position, witnesses are found by line of sight.
## Returns {gained, level, milestone}
func use_skill(skill: String, difficulty_factor: float = 1.0, context: Dictionary = {}) -> Dictionary:
	if not _skills.has(skill):
		push_warning("[PlayerStats] Unknown skill '%s'" % skill)
		return {"gained": 0.0, "level": 0.0, "milestone": 0}
	var before: float = _skills[skill]
	var gained = 0.0
	if difficulty_factor > 0.0 and before < SKILL_CAP:
		var base_xp = float(context.get("base_xp", _skill_defs[skill].get("base_xp", 1.0)))
		gained = base_xp * difficulty_factor * (1.0 - before / GAIN_CURVE) * training_multiplier(skill)
		gained = clampf(gained, 0.0, SKILL_CAP - before)
	var level_before = get_level()
	_skills[skill] = before + gained
	var milestone = 0
	for m in _milestones:
		if before < m and _skills[skill] >= m:
			milestone = m
			_unlock_perks(skill, m)
	if gained > 0.0 and (floori(_skills[skill]) > floori(before) or milestone > 0):
		skill_raised.emit(skill, _skills[skill], milestone)
	_on_level_changed(level_before)
	_maybe_feat(skill, context)
	return {"gained": gained, "level": _skills[skill], "milestone": milestone}

func get_skill(skill: String) -> float:
	return float(_skills.get(skill, 0.0))

## Set directly (load, tests, story grants). Unlocks perks for milestones reached; no feat
func set_skill(skill: String, value: float) -> void:
	if not _skills.has(skill):
		return
	var level_before = get_level()
	_skills[skill] = clampf(value, 0.0, SKILL_CAP)
	for m in _milestones:
		if _skills[skill] >= m:
			_unlock_perks(skill, m)
	_on_level_changed(level_before)

## level = floor(sum of the top six skills / 30), 0-20
func get_level() -> int:
	var values: Array = _skills.values()
	values.sort()
	values.reverse()
	var total = 0.0
	for i in mini(6, values.size()):
		total += float(values[i])
	return clampi(floori(total / 30.0), 0, MAX_LEVEL)

func has_perk(perk_id: String) -> bool:
	return perk_id in _perks

func get_perks() -> Array:
	return _perks.duplicate()

func _unlock_perks(skill: String, milestone: int) -> void:
	for p in _perk_defs:
		if str(p.skill) == skill and int(p.milestone) == milestone and not str(p.id) in _perks:
			_perks.append(str(p.id))

func _on_level_changed(level_before: int) -> void:
	var delta = get_level() - level_before
	if delta > 0:
		# A new level fills the added headroom
		_health = minf(_health + delta * PER_LEVEL, get_max_health())
		_stamina = minf(_stamina + delta * PER_LEVEL, get_max_stamina())
	else:
		_health = minf(_health, get_max_health())
		_stamina = minf(_stamina, get_max_stamina())

# --- training (teaching.gd) ---------------------------------------------------

## A teacher's lesson multiplies gain for this skill until the game minute `until`
func add_training(skill: String, multiplier: float, until_minute: int) -> void:
	_training[skill] = {"multiplier": multiplier, "until": until_minute}

func training_multiplier(skill: String) -> float:
	var t = _training.get(skill)
	if t == null:
		return 1.0
	if _now() >= int(t.until):
		_training.erase(skill)
		return 1.0
	return float(t.multiplier)

func get_teaching():
	if _teaching == null:
		_teaching = Teaching.new(self)
	return _teaching

# --- feats (§2 "How the world sees skill") ------------------------------------

## The first time a skill is seen past 25/50/75: a `feat` deed, and respect from witnesses whose
## trade it is. Unwitnessed use never counts; the feat waits for someone to see it
func _maybe_feat(skill: String, context: Dictionary) -> void:
	var level: float = _skills[skill]
	var done: Array = _feats.get(skill, [])
	var tier = 0
	for m in _feat_milestones:
		if level >= m and not m in done:
			tier = m
	if tier == 0:
		return
	var witnesses = _witnesses_for(context)
	if witnesses.is_empty():
		return
	for m in _feat_milestones:
		if m <= tier and not m in done:
			done.append(m)
	_feats[skill] = done
	var summary = str(context.get("feat_summary", ""))
	if summary == "":
		summary = str(_skill_defs[skill].get("feat", {}).get(str(tier), "showed real skill at %s" % skill))
	var events = _node("PlayerEvents")
	var event_id = ""
	if events:
		event_id = events.record("feat", summary, context.get("about", []), {"witnesses": witnesses})
	_respect_from_trade(skill, tier, witnesses, event_id)

func get_feats() -> Dictionary:
	return _feats.duplicate(true)

func _witnesses_for(context: Dictionary) -> Array:
	var given = context.get("witnessed_by", [])
	if given is Array and not given.is_empty():
		return given.duplicate()
	var scene = context.get("scene_root")
	if scene is Node and context.get("position") is Vector2:
		return Witnesses.in_sight(scene, context.position, {"stealth": get_skill("stealth")})
	return []

## Witnesses whose own trade is this skill respect it more (Bjorn watching a true weld)
func _respect_from_trade(skill: String, tier: int, witnesses: Array, event_id: String) -> void:
	var dir = _director()
	if dir == null or not dir.has_method("apply_situation_effects"):
		return
	var teaching = get_teaching()
	for w in witnesses:
		var key = teaching.npc_key(str(w))
		if key == "" or not skill in teaching.trades_of(key):
			continue
		var effect = {"type": "adjust_relationship", "npc": key, "dimension": "respect", "delta": int(FEAT_RESPECT.get(tier, 3))}
		dir.apply_situation_effects(key, {"effects": [effect]}, {"feat": event_id, "skill": skill})

# =============================================================================
# HEALTH, STAMINA, POISE
# =============================================================================

func get_health() -> float:
	return _health

func get_max_health() -> float:
	return BASE_HEALTH + PER_LEVEL * get_level()

func get_stamina() -> float:
	return _stamina

func get_max_stamina() -> float:
	return BASE_STAMINA + PER_LEVEL * get_level() + ATHLETICS_STAMINA * get_skill("athletics")

func get_poise() -> float:
	return _poise

func heal(amount: float) -> void:
	if amount > 0.0 and _health > 0.0:
		_health = minf(_health + amount, get_max_health())

## Every action spends stamina; without enough, the action does not happen
func spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _stamina < amount:
		return false
	_stamina -= amount
	_since_spend = 0.0
	return true

func restore_stamina(amount: float) -> void:
	_stamina = minf(_stamina + maxf(amount, 0.0), get_max_stamina())

## Returns {health, staggered, dead} (and death: the died info when it killed). Hits drain poise,
## blunt ones faster; at zero the player staggers and poise refills
func damage(amount: float, damage_type: String = "blunt", source: String = "") -> Dictionary:
	if amount <= 0.0 or _health <= 0.0:
		return {"health": _health, "staggered": false, "dead": _health <= 0.0}
	_since_hurt = 0.0
	_health = maxf(_health - amount, 0.0)
	_poise -= amount * (BLUNT_POISE if damage_type == "blunt" else 1.0)
	var staggered = false
	if _poise <= 0.0:
		staggered = true
		_poise = MAX_POISE
	if _health <= 0.0:
		var info = die({"source": source, "damage_type": damage_type})
		return {"health": _health, "staggered": staggered, "dead": true, "death": info}
	return {"health": _health, "staggered": staggered, "dead": false}

func _process(delta: float) -> void:
	tick(delta)

## Regeneration: stamina quickly once not spent for a moment, poise steadily, health slowly out of harm
func tick(delta: float) -> void:
	if _health <= 0.0:
		return
	_since_spend += delta
	_since_hurt += delta
	if _since_spend >= STAMINA_DELAY and _stamina < get_max_stamina():
		var rate = STAMINA_REGEN * (1.0 + get_skill("athletics") / 100.0)
		_stamina = minf(_stamina + rate * delta, get_max_stamina())
	if _poise < MAX_POISE:
		_poise = minf(_poise + POISE_REGEN * delta, MAX_POISE)
	if _since_hurt >= HEALTH_DELAY and _health < get_max_health():
		_health = minf(_health + HEALTH_REGEN * delta, get_max_health())

# =============================================================================
# DEATH
# =============================================================================

## Percent of every skill's level lost by this death (1-based count)
static func loss_percent(death_number: int, mode: String) -> float:
	if death_number <= 0:
		return 0.0
	if mode == "hard":
		return minf(pow(2.0, death_number - 1), HARD_LOSS_CAP)
	return minf(float(death_number), NORMAL_LOSS_CAP)

func get_deaths() -> int:
	return _deaths

func get_death_count() -> int:
	return _deaths

## The last bed: where the player wakes after a death
func set_respawn(location_id: String, spawn_point: String = "default") -> void:
	_respawn = {"location": location_id, "spawn_point": spawn_point}

func get_respawn() -> Dictionary:
	return _respawn.duplicate()

## Death: skills fall, the pack drops where the player fell, those with line of sight remember a
## `fell` deed, and the player wakes at the last bed or the nearest inn. opts: scene_root, position, source
func die(opts: Dictionary = {}) -> Dictionary:
	_deaths += 1
	var pct = loss_percent(_deaths, difficulty)
	var level_before = get_level()
	for id in _skills:
		_skills[id] = maxf(0.0, float(_skills[id]) * (1.0 - pct / 100.0))
	var who = _body()
	var scene: Node = opts.get("scene_root", null)
	if scene == null:
		scene = _scene_of(who)
	var at: Vector2 = opts.get("position", who.global_position if who else Vector2.ZERO)
	var inv = inventory if inventory != null else _node("Inventory")
	var pack = inv.drop_all_at(scene, at) if inv and inv.has_method("drop_all_at") else null
	var witnesses: Array = Witnesses.in_sight(scene, at, {"stealth": get_skill("stealth")}) if scene else []
	var events = _node("PlayerEvents")
	var deed = ""
	var src = str(opts.get("source", ""))
	if events:
		var about: Array = [src] if src != "" and _is_npc(src) else []
		deed = events.record("fell", "fell, and lay still", about, {"witnesses": witnesses})
	var wake = _respawn.duplicate() if not _respawn.is_empty() else nearest_inn(_current_location())
	var info = {"deaths": _deaths, "loss_percent": pct, "difficulty": difficulty, "source": src,
		"position": at, "witnesses": witnesses, "deed": deed, "pack": pack, "respawn": wake}
	_on_level_changed(level_before)
	_health = get_max_health()
	_stamina = get_max_stamina()
	_poise = MAX_POISE
	_since_hurt = 999.0
	var world_state = _node("WorldState")
	if world_state and world_state.has_method("advance_time"):
		world_state.advance_time(WAKE_MINUTES, "fell")
	died.emit(info)
	if move_on_respawn and not wake.is_empty():
		var scenes = _node("SceneManager")
		if scenes and scenes.has_method("transition_to"):
			scenes.transition_to(str(wake.location), str(wake.get("spawn_point", "default")))
	return info

## The inn reached soonest by the routes graph from here (the first one when here is unknown)
func nearest_inn(from_location: String) -> Dictionary:
	if _inns.is_empty():
		return {}
	var registry = _node("WorldRegistry")
	var best: Dictionary = _inns[0]
	var best_minutes = INF
	for inn in _inns:
		if str(inn.location) == from_location:
			return {"location": str(inn.location), "spawn_point": str(inn.get("spawn_point", "default"))}
		if registry and from_location != "" and registry.is_reachable(from_location, str(inn.location)):
			var m = registry.travel_minutes(from_location, str(inn.location))
			if m >= 0 and m < best_minutes:
				best_minutes = m
				best = inn
	return {"location": str(best.location), "spawn_point": str(best.get("spawn_point", "default"))}

# =============================================================================
# HELPERS
# =============================================================================

## The player body reports itself here (else the "player" group is used)
func set_body(node: Node2D) -> void:
	body = node

func _body() -> Node2D:
	if is_instance_valid(body):
		return body
	if is_inside_tree():
		var p = get_tree().get_first_node_in_group("player")
		if p is Node2D:
			return p
	return null

func _scene_of(who: Node) -> Node:
	if not is_inside_tree():
		return null
	var current = get_tree().current_scene
	if who == null:
		return current
	if current and current.is_ancestor_of(who):
		return current
	return who.get_parent()

func _current_location() -> String:
	var scenes = _node("SceneManager")
	if scenes and scenes.has_method("get_current_location_id"):
		var id = str(scenes.get_current_location_id())
		if id != "" and id != "none":
			return id
	var world_state = _node("WorldState")
	return str(world_state.player_location) if world_state and "player_location" in world_state else ""

func _is_npc(who: String) -> bool:
	var registry = _node("WorldRegistry")
	return registry != null and (registry.has_npc(who) or registry.get_npc_key(who) != "")

func _director():
	return director if director != null else _node("StorylineDirector")

func _now() -> int:
	var world_state = _node("WorldState")
	return world_state.get_game_minutes() if world_state else 0

func _node(node_name: String) -> Node:
	return get_node_or_null("/root/" + node_name) if is_inside_tree() else null

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[PlayerStats] Missing %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {"difficulty": difficulty, "skills": _skills.duplicate(), "perks": _perks.duplicate(),
		"feats": _feats.duplicate(true), "training": _training.duplicate(true), "deaths": _deaths,
		"respawn": _respawn.duplicate(), "health": _health, "stamina": _stamina}

func load_from_dict(data: Dictionary) -> void:
	reset()
	difficulty = "hard" if str(data.get("difficulty", "normal")) == "hard" else "normal"
	var skills = data.get("skills", {})
	if skills is Dictionary:
		for id in skills:
			if _skills.has(str(id)):
				_skills[str(id)] = clampf(float(skills[id]), 0.0, SKILL_CAP)
	for p in data.get("perks", []):
		if not str(p) in _perks:
			_perks.append(str(p))
	var feats = data.get("feats", {})
	if feats is Dictionary:
		for id in feats:
			_feats[str(id)] = feats[id].map(func(m): return int(m)) if feats[id] is Array else []
	var training = data.get("training", {})
	if training is Dictionary:
		for id in training:
			if training[id] is Dictionary:
				_training[str(id)] = {"multiplier": float(training[id].get("multiplier", 1.0)), "until": int(training[id].get("until", 0))}
	_deaths = int(data.get("deaths", 0))
	var r = data.get("respawn", {})
	_respawn = {"location": str(r.location), "spawn_point": str(r.get("spawn_point", "default"))} if r is Dictionary and r.has("location") else {}
	_health = clampf(float(data.get("health", get_max_health())), 1.0, get_max_health())
	_stamina = clampf(float(data.get("stamina", get_max_stamina())), 0.0, get_max_stamina())
