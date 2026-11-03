extends RefCounted
class_name CombatAI
## CombatAI - how people decide in a fight, and what the world does with how it ends
## (docs/PLAYER_SYSTEMS.md §3 "Who fights" and "Endings")
## - decide(npc_key, situation) -> fight | yield | flee | call_for_help | talk. The choice is the soul's:
##   a `react` hook put through StorylineDirector.decide_situation, so Agency, Lines and feelings toward
##   the player decide it (offline appeal or Claude). Options carry harms/aids/crowd so Lines refuse
##   them: harm:<x> never fights x, and will not run from a fight that leaves x hurt; `crowd` never
##   joins a mob
## - morale: fear of the player, wounds, allies down and the soul's own resolve. It decides which
##   options are on the table; people yield when it breaks, they do not fight to the death
## - children are never targets (an engine rule, before any soul is asked): Combat.can_target
## - endings are deeds through PlayerEvents.record with line-of-sight witnesses: kill (and
##   WorldState.register_npc_death), harm, spared, fled, help
## Static: NPC bodies, creatures, tests and other systems call it without an instance

const Witnesses = preload("res://scripts/world/witnesses.gd")

const ACTIONS = ["fight", "yield", "flee", "call_for_help", "talk"]
const PLAYER = "player"
const BASE_MORALE = 60.0
const WAVER = 50.0              # below this a person will think about yielding
const BREAK = 25.0              # below this they will not fight at all
const FEAR_WEIGHT = 0.5         # morale lost per point of fear toward the player
const WOUND_WEIGHT = 50.0       # morale lost at zero health
const ALLY_DOWN_WEIGHT = 15.0   # per ally dead or yielded in this fight
const SHIELD_BONUS = 15.0       # standing over someone their Lines will not let be harmed
const RESOLVE_CAP = 15.0
## The soul's resolve: wants that are worth a fight, fears of one
const BOLD_WORDS = ["protect", "defend", "justice", "fight", "guard", "avenge", "answer for", "blade", "hold the"]
const TIMID_WORDS = ["blade", "fight", "violence", "hurt", "die", "death", "pain", "beaten", "killed", "blood"]

# =============================================================================
# DECISIONS
# =============================================================================

## situation: {kind: attacked | witness | crowd, attacker, victim, target, morale?, health_fraction?,
## allies_down?, crowd?}. attacked: the NPC was struck by `attacker`. witness: the NPC sees `attacker`
## strike `victim`. crowd: the NPC stands in a crowd turning on `target`. Keys are npc keys or "player"
static func decide(npc_key: String, situation: Dictionary) -> String:
	var full: Dictionary = await decide_full(npc_key, situation)
	return str(full.action)

## decide plus why: {action, side (defend|join|""), foe (whom they fight, ""), choice, reason, morale,
## band, decision (the Director's), hook}
static func decide_full(npc_key: String, situation: Dictionary) -> Dictionary:
	var key = npc_key.strip_edges().to_lower()
	var morale = float(situation.morale) if situation.has("morale") else morale_for(key, situation)
	var hook = build_hook(key, situation, morale)
	var director = _node("StorylineDirector")
	var decision: Dictionary = {}
	if director and director.has_method("decide_situation") and not hook.options.is_empty():
		decision = await director.decide_situation(key, hook, str(hook.situation))
	var option: Dictionary = decision.get("option", {}) if decision.get("option") is Dictionary else {}
	var action = str(option.get("action", ""))
	var reason = str(decision.get("reason", "no soul to ask"))
	if action == "" or not action in ACTIONS:
		action = fallback_action(situation, morale)
		reason = "fallback (%s)" % reason
	return {"action": action, "side": str(option.get("side", "")), "foe": str(option.get("foe", "")),
		"choice": str(decision.get("choice", "pass")), "reason": reason, "morale": morale, "band": band(morale),
		"decision": decision, "hook": hook}

## No soul, or none of its options permitted: nobody fights without choosing to
static func fallback_action(situation: Dictionary, morale: float) -> String:
	if str(situation.get("kind", "attacked")) == "attacked" and morale < WAVER:
		return "yield"
	return "flee"

## broken (< BREAK) | wavering (< WAVER) | steady
static func band(morale: float) -> String:
	if morale < BREAK:
		return "broken"
	return "wavering" if morale < WAVER else "steady"

## The react hook put to the soul. Options in the order that wins a tie (the Director's chooser keeps
## the earlier option): morale sets the order and which options exist at all
static func build_hook(npc_key: String, situation: Dictionary, morale: float) -> Dictionary:
	var kind = str(situation.get("kind", "attacked"))
	var attacker = _key(str(situation.get("attacker", "")))
	var victim = _key(str(situation.get("victim", npc_key)))
	var target = _key(str(situation.get("target", "")))
	var b = band(morale)
	var options: Array = []
	var text = ""
	match kind:
		"witness":
			text = "%s strikes %s in front of %s" % [_name(attacker), _name(victim), _name(npc_key)]
			options = _witness_options(attacker, victim, bool(situation.get("crowd", false)))
			options = _ordered(options, {"steady": ["defend", "talk", "call_for_help", "join", "flee"],
				"wavering": ["call_for_help", "talk", "flee", "defend", "join"],
				"broken": ["flee", "call_for_help", "talk"]}[b])
		"crowd":
			text = "The crowd around %s turns on %s" % [_name(npc_key), _name(target)]
			options = _crowd_options(target)
			options = _ordered(options, {"steady": ["join", "talk", "call_for_help", "flee"],
				"wavering": ["talk", "call_for_help", "flee", "join"],
				"broken": ["flee", "call_for_help", "talk"]}[b])
		_:
			text = "%s strikes %s" % [_name(attacker), _name(npc_key)]
			options = _attacked_options(attacker)
			options = _ordered(options, {"steady": ["fight", "talk", "call_for_help", "flee"],
				"wavering": ["yield", "talk", "call_for_help", "flee", "fight"],
				"broken": ["yield", "flee", "talk", "call_for_help"]}[b])
	# Engine rules, before any soul is asked: nobody fights a child, and a child fights nobody
	var child = is_minor(npc_key)
	options = options.filter(func(o):
		if o.action != "fight":
			return true
		return not child and can_target(str(o.foe)))
	return {"id": "combat_%s" % kind, "type": "react", "situation": text, "options": options}

static func _attacked_options(attacker: String) -> Array:
	var p = attacker == PLAYER
	return [
		_opt("fight", "fight", "Fight back", {"fear": -0.6, "affection": -0.4, "trust": -0.2} if p else {}, {"harms": [attacker], "foe": attacker}),
		_opt("yield", "yield", "Yield", {"fear": 0.7, "respect": 0.3} if p else {}),
		_opt("flee", "flee", "Run", {"fear": 0.5, "trust": -0.3} if p else {}),
		_opt("call_for_help", "call_for_help", "Shout for help", {"fear": 0.3, "trust": -0.5} if p else {}),
		_opt("talk", "talk", "Talk them down", {"trust": 0.5, "affection": 0.5, "familiarity": 0.2} if p else {}),
	]

## Running from a fight, or standing by, leaves the victim to it: a soul whose Lines will not let them
## be harmed (harm:<victim>) will not do either, so it defends them, talks or fetches help
static func _witness_options(attacker: String, victim: String, crowd: bool) -> Array:
	var p_attacks = attacker == PLAYER
	var p_victim = victim == PLAYER
	var join_extra = {"harms": [victim], "aids": attacker, "foe": victim, "side": "join"}
	if crowd:
		join_extra["crowd"] = true
	return [
		_opt("defend", "fight", "Stand up for %s" % _name(victim),
			{"affection": -0.5, "trust": -0.4, "fear": -0.5} if p_attacks else ({"affection": 0.5, "trust": 0.4} if p_victim else {}),
			{"harms": [attacker], "aids": victim, "foe": attacker, "side": "defend"}),
		_opt("join", "fight", "Join in against %s" % _name(victim),
			{"affection": 0.4, "trust": 0.3, "fear": 0.2} if p_attacks else ({"affection": -0.5, "trust": -0.4} if p_victim else {}), join_extra),
		_opt("call_for_help", "call_for_help", "Shout for the watch", {"fear": 0.4, "trust": -0.2} if p_attacks else {}, {"aids": victim}),
		_opt("talk", "talk", "Try to stop it with words", {"trust": 0.4, "familiarity": 0.3} if p_attacks or p_victim else {}, {"aids": victim}),
		_opt("flee", "flee", "Get away from it", {"fear": 0.5} if p_attacks else {}, {"harms": [victim]}),
	]

## Mob violence carries crowd: true, which a `crowd` Line refuses
static func _crowd_options(target: String) -> Array:
	var p = target == PLAYER
	return [
		_opt("join", "fight", "Lay hands on %s with the rest" % _name(target), {"affection": -0.5, "trust": -0.5, "fear": -0.3} if p else {},
			{"harms": [target], "crowd": true, "foe": target, "side": "join"}),
		_opt("talk", "talk", "Talk the crowd down", {"trust": 0.4, "affection": 0.3} if p else {}, {"aids": target}),
		_opt("call_for_help", "call_for_help", "Fetch the watch", {}),
		_opt("flee", "flee", "Walk away from it", {"fear": 0.5} if p else {}),
	]

static func _opt(id: String, action: String, label: String, appeal: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var o = {"id": id, "label": label, "action": action, "appeal": appeal, "effects": []}
	o.merge(extra, true)
	return o

static func _ordered(options: Array, order: Array) -> Array:
	var by_id = {}
	for o in options:
		by_id[o.id] = o
	return order.filter(func(id): return by_id.has(id)).map(func(id): return by_id[id])

# =============================================================================
# MORALE
# =============================================================================

## 0-100. situation: health_fraction (0-1), allies_down (int), plus kind/attacker/victim/target
static func morale_for(npc_key: String, situation: Dictionary) -> float:
	var key = _key(npc_key)
	var m = BASE_MORALE
	var foe = _key(str(situation.get("attacker", situation.get("target", ""))))
	if str(situation.get("kind", "attacked")) == "witness" and _key(str(situation.get("victim", ""))) == PLAYER:
		foe = ""  # the player is the one being struck: nothing to fear from them here
	if foe == PLAYER:
		var dims = feelings(key)
		m -= FEAR_WEIGHT * maxf(float(dims.get("fear", 0.0)), 0.0)
	m -= WOUND_WEIGHT * (1.0 - clampf(float(situation.get("health_fraction", 1.0)), 0.0, 1.0))
	m -= ALLY_DOWN_WEIGHT * maxi(int(situation.get("allies_down", 0)), 0)
	m += resolve(key)
	var soul = _soul(key)
	var victim = _key(str(situation.get("victim", "")))
	if soul and str(situation.get("kind", "")) == "witness" and victim != "" and soul._forbidding_rule("harm:" + victim) != "":
		m += SHIELD_BONUS
	return clampf(m, 0.0, 100.0)

## The soul's own resolve (-15..15): wants worth a fight raise it, fears of violence lower it
static func resolve(npc_key: String) -> float:
	var soul = _soul(npc_key)
	if soul == null:
		return 0.0
	var r = 0.0
	for want_id in soul.wants:
		var text = (str(want_id) + " " + str(soul.wants[want_id].get("text", ""))).to_lower().replace("_", " ")
		if BOLD_WORDS.any(func(w): return w in text):
			r += float(soul.get_weight(want_id))
	for fear in soul.fears:
		if TIMID_WORDS.any(func(w): return w in str(fear).to_lower()):
			r -= 4.0
	return clampf(r, -RESOLVE_CAP, RESOLVE_CAP)

static func feelings(npc_key: String) -> Dictionary:
	var director = _node("StorylineDirector")
	if director and director.has_method("get_relationship_dims"):
		return director.get_relationship_dims(npc_key)
	return {}

# =============================================================================
# TARGETS
# =============================================================================

## Children are never targets (docs/PLAYER_SYSTEMS.md §1.4). Creatures and the player always can be
static func can_target(key: String) -> bool:
	if key == "" or key == PLAYER or key.begins_with("creature:"):
		return key != ""
	var combat = _node("Combat")
	if combat and combat.has_method("can_target"):
		return combat.can_target(key)
	return not is_minor(key)

static func is_minor(key: String) -> bool:
	var registry = _node("WorldRegistry")
	return registry != null and registry.has_method("is_minor") and key != PLAYER and registry.is_minor(key)

## A body's combat key: "player", an npc key ("bjorn"), a generic id, "creature:<id>", or ""
static func key_of(node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node is Node and node.is_in_group("player"):
		return PLAYER
	if node.get("creature_id") != null and str(node.get("creature_id")) != "":
		return "creature:" + str(node.get("creature_id"))
	var id = str(node.get("npc_id")) if node.get("npc_id") != null else ""
	return _key(id)

# =============================================================================
# ENDINGS -> DEEDS (only the player's deeds are recorded: PlayerEvents is the player's ledger)
# =============================================================================

## kill: the dead person, line-of-sight witnesses; their death is registered so storylines treat them as dead
static func record_kill(victim_key: String, scene_root: Node, at: Vector2, opts: Dictionary = {}) -> String:
	var key = _key(victim_key)
	var id = _deed("kill", "killed %s in a fight" % _name(key), [key], scene_root, at, opts)
	register_death(key, str(opts.get("cause", "wounds from a fight")), PLAYER)
	return id

static func record_harm(victim_key: String, scene_root: Node, at: Vector2, opts: Dictionary = {}) -> String:
	var key = _key(victim_key)
	return _deed("harm", "wounded %s in a fight" % _name(key), [key], scene_root, at, opts)

## The person yielded and the player let them go
static func record_spared(key: String, scene_root: Node, at: Vector2, opts: Dictionary = {}) -> String:
	var k = _key(key)
	return _deed("spared", "let %s go when they yielded" % _name(k), [k], scene_root, at, opts)

## The player ran from a fight (foes: the keys of whoever they ran from)
static func record_fled(foes: Array, scene_root: Node, at: Vector2, opts: Dictionary = {}) -> String:
	var keys = foes.map(func(f): return _key(str(f))).filter(func(k): return k != "" and k != PLAYER and not k.begins_with("creature:"))
	var whom = " and ".join(keys.map(func(k): return _name(k))) if not keys.is_empty() else "a fight"
	return _deed("fled", "ran from a fight with %s" % whom if not keys.is_empty() else "ran from a fight", keys, scene_root, at, opts)

## The player stood up for someone being attacked
static func record_help(defended_key: String, foe_key: String, scene_root: Node, at: Vector2, opts: Dictionary = {}) -> String:
	var k = _key(defended_key)
	var foe = _key(foe_key)
	var summary = "stood up for %s against %s" % [_name(k), _name(foe)] if foe != "" else "stood up for %s in a fight" % _name(k)
	return _deed("help", summary, [k], scene_root, at, opts)

## Any adult can die (lead's ruling): WorldState keeps it, so storylines, emergence and spawns see it
static func register_death(key: String, cause: String, killer: String) -> void:
	var world_state = _node("WorldState")
	if world_state and world_state.has_method("register_npc_death"):
		world_state.register_npc_death(npc_id_of(key), {"cause": cause, "killed_by": killer})

## opts: witnesses (more ids to add, e.g. the victim), location, stealth, exclude
static func _deed(kind: String, summary: String, about: Array, scene_root: Node, at: Vector2, opts: Dictionary) -> String:
	var events = _node("PlayerEvents")
	if events == null or not events.has_method("record"):
		return ""
	var seen: Array = Witnesses.in_sight(scene_root, at, {"stealth": float(opts.get("stealth", 0.0)), "exclude": opts.get("exclude", [])}) if scene_root else []
	for w in opts.get("witnesses", []):
		var id = npc_id_of(str(w))
		if id != "" and not id in seen and _alive(id):
			seen.append(id)
	var record_opts = {"witnesses": seen}
	if opts.has("location"):
		record_opts["location"] = str(opts.location)
	return events.record(kind, summary, about, record_opts)

# =============================================================================
# HELPERS
# =============================================================================

static func npc_id_of(key: String) -> String:
	var registry = _node("WorldRegistry")
	var id = registry.get_npc_id(key) if registry and registry.has_method("get_npc_id") and registry.has_npc(key) else ""
	return id if id != "" else key

static func _key(id: String) -> String:
	var s = id.strip_edges()
	if s == "" or s == PLAYER or s.begins_with("creature:"):
		return s
	var registry = _node("WorldRegistry")
	var key = registry.get_npc_key(s) if registry and registry.has_method("get_npc_key") else ""
	return key if key != "" else s.to_lower()

static func _alive(id: String) -> bool:
	var world_state = _node("WorldState")
	return world_state == null or not world_state.has_method("is_npc_alive") or world_state.is_npc_alive(id)

static func _soul(key: String):
	var director = _node("StorylineDirector")
	return director.get_soul(key) if director and director.has_method("get_soul") else null

static func _name(key: String) -> String:
	if key == PLAYER:
		return "the stranger"
	if key.begins_with("creature:"):
		return "a " + key.substr(9).replace("_", " ")
	var director = _node("StorylineDirector")
	return director.get_display_name(key) if director and director.has_method("get_display_name") else key.capitalize()

static func _node(path: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(path) if tree else null
