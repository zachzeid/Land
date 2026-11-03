extends Node
## Taverns - rooms let by the night, who sleeps in them, and the back rooms where a house keeps them
## (docs/WORLD_SCHEMA.md "Taverns"). A tavern is a world.json location with a `tavern` block:
## {"keeper": <npc key or generic id>, "rooms": n, "rent_copper": c, "brothel": bool}. Its scene holds
## the rooms: one Bed node each (bed.gd), with its own spawn marker; a room's id is that spawn point
## - renting: from the keeper in conversation (StorylineDirector trade action `rent_room`) or at the
##   bed. A rented room is the player's until the morning's checkout; others' rooms are locked, and
##   walking into one is a `trespass` deed (room_door.gd). A keeper who thinks badly enough of the
##   player (Reputation) will not let them a room at all
## - lodgers: of an evening, travellers present at a tavern take its free rooms, one to a room. A
##   child is never given a room, so never shares one with an adult stranger
## - back rooms (brothel: true): adult companions (archetype house_companion) keep them by the
##   keeper's leave. The player may ask one for company in conversation (trade action `company`);
##   the companion decides. It costs coin, the scene fades to black and is never described, and it is
##   a deed others may learn of and judge by their own nature (judgement()). The back rooms are shut
##   while any child is in the house. Companions hear what the lodgers say, and word travels on
## Should be the autoload "Taverns" (save()/load_from_dict() through WorldState's player systems)

signal room_rented(info: Dictionary)
signal company_kept(info: Dictionary)

const BED_SCRIPT = "res://scripts/world/bed.gd"
const COMPANION_ARCHETYPE = "house_companion"
## Generic archetypes who are on the road and so take a room for the night
const TRAVELLER_ARCHETYPES = ["courier", "pilgrim", "carter"]
const LODGE_FROM_HOUR = 21     # travellers go up to their rooms
const CHECKOUT_HOUR = 10       # a night's rent runs to this hour of the next morning
const REFUSE_BELOW = -30.0     # a keeper's opinion of the player under which no room is let
const COMPANY_COPPER = 15      # a companion's usual fee (about a day and a half's labour)
const COMPANY_MINUTES = 60
const COMPANY_REFUSE_BELOW = -20.0
const PILLOW_TALK_VIA = "talk in the back rooms"
const PILLOW_TALK_MAX = 3      # events a night's talk carries on
## How each person judges a visit to the back rooms is in data: resources/characters/judgement.json
## (judge()). The faith rules there weigh DISAPPROVAL
const JUDGEMENT_PATH = "res://resources/characters/judgement.json"
const PERSONALITY_DIR = "res://resources/npc_personalities"
const DISAPPROVAL = -6.0       # what a devout soul weighs a visit at (Reputation points)

## Seams (null = autoloads); tests pin the clock and the rooms
var now_override: int = -1
var rooms_override: Dictionary = {}     # location -> [{room, rent, back_room}]
var present_override: Dictionary = {}   # location -> [who]

var _rentals: Dictionary = {}           # location -> {room, until, paid, minute, how}
var _talk_days: Dictionary = {}         # location -> the day the back rooms last passed talk on
var _room_cache: Dictionary = {}        # location -> [{room, rent, back_room}] read from its scene
var _souls: Dictionary = {}             # npc_id -> NPCPersonality (read once)
var _judgement_rules: Dictionary = {}   # judgement.json "morals" (read once)

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("time_advanced"):
		bus.time_advanced.connect(_on_time_advanced)
	var scenes = get_node_or_null("/root/SceneManager")
	if scenes and scenes.has_signal("scene_transition_completed"):
		scenes.scene_transition_completed.connect(_on_arrived)

func reset() -> void:
	_rentals = {}
	_talk_days = {}

# =============================================================================
# TAVERNS AND ROOMS
# =============================================================================

## The location's tavern block ({} when it is not a tavern)
func tavern(location: String) -> Dictionary:
	var registry = _node("WorldRegistry")
	if registry == null or location == "" or not registry.has_location(location):
		return {}
	var t = registry.get_location(location).get("tavern", {})
	return t if t is Dictionary else {}

func is_tavern(location: String) -> bool:
	return not tavern(location).is_empty()

func tavern_ids() -> Array:
	var registry = _node("WorldRegistry")
	return registry.get_location_ids().filter(func(id): return is_tavern(id)) if registry else []

func rent_of(location: String) -> int:
	return int(tavern(location).get("rent_copper", 0))

## True when this one is the keeper of this tavern (an npc key, npc id, generic id or its archetype)
func is_keeper(who: String, location: String) -> bool:
	var keeper = str(tavern(location).get("keeper", ""))
	if keeper == "" or who == "":
		return false
	if who == keeper or _who(who) == _who(keeper):
		return true
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.has_method("get_instance") else null
	return inst != null and str(inst.archetype_id) == keeper

## Every room in the tavern's scene: [{room (its spawn point), rent, back_room}]
func rooms(location: String) -> Array:
	if rooms_override.has(location):
		return rooms_override[location]
	if _room_cache.has(location):
		return _room_cache[location]
	var registry = _node("WorldRegistry")
	var path = str(registry.get_location(location).get("scene", "")) if registry and registry.has_location(location) else ""
	var found: Array = []
	var packed = load(path) if path != "" and ResourceLoader.exists(path) else null
	if packed is PackedScene:
		var state: SceneState = packed.get_state()
		for i in state.get_node_count():
			var props = {}
			for j in state.get_node_property_count(i):
				props[state.get_node_property_name(i, j)] = state.get_node_property_value(i, j)
			var script = props.get("script")
			if script is Script and script.resource_path == BED_SCRIPT:
				found.append({"room": str(props.get("spawn_point", "bed")), "rent": int(props.get("rent", 0)),
					"back_room": bool(props.get("back_room", false))})
	_room_cache[location] = found
	return found

## Rooms let to lodgers (not the back rooms, and with a rent)
func lettable(location: String) -> Array:
	return rooms(location).filter(func(r): return not r.back_room and int(r.rent) > 0).map(func(r): return str(r.room))

func back_rooms(location: String) -> Array:
	return rooms(location).filter(func(r): return r.back_room).map(func(r): return str(r.room))

## The player's room here tonight ({} when none): {room, until, paid, minute, how}
func my_room(location: String) -> Dictionary:
	var r: Dictionary = _rentals.get(location, {})
	if r.is_empty() or _now() >= int(r.until):
		return {}
	return r.duplicate()

## Who sleeps in which room tonight: {room: who}. Of an evening, travellers present here (not the
## keeper, not the companions, never a child) take the free rooms in order, one to a room
func lodgers(location: String) -> Dictionary:
	var out: Dictionary = {}
	if not is_tavern(location) or not _is_lodging_hour():
		return out
	var mine = str(my_room(location).get("room", ""))
	var free: Array = lettable(location).filter(func(r): return r != mine)
	var travellers: Array = _present(location).filter(func(w): return _is_traveller(str(w), location))
	travellers.sort()
	for i in mini(free.size(), travellers.size()):
		out[free[i]] = travellers[i]
	return out

## "yours" | "free" | "taken" (a lodger's) | "back_room" | "none" (no such room)
func room_status(location: String, room: String) -> String:
	if room in back_rooms(location):
		return "back_room"
	if not room in lettable(location):
		return "none"
	if str(my_room(location).get("room", "")) == room:
		return "yours"
	return "taken" if lodgers(location).has(room) else "free"

func free_rooms(location: String) -> Array:
	return lettable(location).filter(func(r): return room_status(location, r) == "free")

## Why the keeper will not let the player a room ("" when they will): what they know of the player
func refusal(location: String, keeper: String = "") -> String:
	var who = keeper if keeper != "" else str(tavern(location).get("keeper", ""))
	if _opinion(who) < REFUSE_BELOW:
		return "%s will not let you a room" % _name(who)
	return ""

## Take a room for tonight. room "" = the first free one; price < 0 = the house rent. how: bed | keeper
## Returns {ok, reason, room, paid, until}
func rent(location: String, room: String = "", price: int = -1, how: String = "bed") -> Dictionary:
	var out = {"ok": false, "reason": "", "room": room, "paid": 0, "until": 0}
	if not is_tavern(location):
		out.reason = "no rooms are let here"
		return out
	var held = my_room(location)
	if not held.is_empty() and (room == "" or room == str(held.room)):
		out.merge({"ok": true, "reason": "already yours", "room": held.room, "until": held.until}, true)
		return out
	out.reason = refusal(location)
	if out.reason != "":
		return out
	if room == "":
		var free = free_rooms(location)
		if free.is_empty():
			out.reason = "every room is taken tonight"
			return out
		room = str(free[0])
	match room_status(location, room):
		"taken":
			out.reason = "someone else has that room tonight"
			return out
		"back_room", "none":
			out.reason = "that room is not let to lodgers"
			return out
	var cost = rent_of(location) if price < 0 else price
	if cost > 0:
		var inv = _node("Inventory")
		if inv == null or not inv.spend_coin(cost):
			out.reason = "you cannot pay for the room"
			return out
	var now = _now()
	_rentals[location] = {"room": room, "until": checkout_after(now), "paid": cost, "minute": now, "how": how}
	out.merge({"ok": true, "reason": "", "room": room, "paid": cost, "until": _rentals[location].until}, true)
	print("[Taverns] The player took %s at %s for %d copper" % [room, location, cost])
	room_rented.emit(out.merged({"location": location}))
	return out

## The checkout minute for a night that includes minute m: the next morning's CHECKOUT_HOUR (before
## dawn it is still last night's)
func checkout_after(m: int) -> int:
	var day = floori(m / 1440.0)
	var hour = floori((m % 1440) / 60.0)
	return (day if hour < 6 else day + 1) * 1440 + CHECKOUT_HOUR * 60

# =============================================================================
# THE BACK ROOMS
# =============================================================================

func is_brothel(location: String) -> bool:
	return tavern(location).get("brothel", false) == true

## Open only when the house keeps them and there is no child anywhere in the house
func brothel_open(location: String) -> bool:
	if not is_brothel(location):
		return false
	return not _present(location).any(func(w): return _is_minor(str(w)))

func is_companion(who: String) -> bool:
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.has_method("get_instance") else null
	return inst != null and str(inst.archetype_id) == COMPANION_ARCHETYPE and not _is_minor(who)

## Companions in the house now
func companions(location: String) -> Array:
	return _present(location).filter(func(w): return is_companion(str(w)))

## Why this companion cannot be asked here ("" when they can): not a companion, not in a house that
## keeps back rooms, a child in the house, or what they know of the player
func company_denial(who: String, location: String) -> String:
	if not is_companion(who):
		return "not a companion of the back rooms"
	if not is_brothel(location):
		return "this house keeps no back rooms"
	if not brothel_open(location):
		return "the back rooms are shut while a child is in the house"
	if not who in _present(location):
		return "not here"
	if _opinion(who) < COMPANY_REFUSE_BELOW:
		return "%s wants nothing to do with you" % _name(who)
	return ""

## The companion has said yes (their own `company` action in conversation). Coin, an hour behind a
## door that the story never opens, and a deed for whoever saw the stranger go through it.
## Returns {ok, reason, paid, minutes, deed}
func company(who: String, location: String, price: int = -1) -> Dictionary:
	var out = {"ok": false, "reason": company_denial(who, location), "paid": 0, "minutes": COMPANY_MINUTES, "deed": ""}
	if out.reason != "":
		return out
	var cost = COMPANY_COPPER if price < 0 else price
	if cost > 0:
		var inv = _node("Inventory")
		if inv == null or not inv.spend_coin(cost):
			out.reason = "you cannot pay"
			return out
	out.paid = cost
	var events = _node("PlayerEvents")
	if events:
		# Seen going through to the back rooms: weightless for most, judged by those whose nature
		# disapproves (judgement; Reputation reads `morals`)
		out.deed = events.record("seen_at", "went through to the back rooms at %s with one of the companions" % _place(location),
			[who], {"location": location, "morals": "company", "spread": false})
	var ws = _node("WorldState")
	if ws and ws.has_method("advance_time"):
		ws.advance_time(COMPANY_MINUTES, "company")
	_narrate("The door of the back room closes behind you. Later, you come back down to the common room.")
	out.ok = true
	out.reason = "company"
	print("[Taverns] The player kept company with %s at %s" % [who, location])
	company_kept.emit(out.merged({"who": who, "location": location}))
	return out

## What a party makes of a deed people weigh by their own nature (Reputation's `morals`): the mean of
## judge() over its people (a faction or region: its members; children are not asked)
func judgement(parties: Array, morals: String = "company") -> float:
	var total = 0.0
	var counted = 0
	for p in parties:
		var j = judge(str(p), morals)
		if j.stance == "child":
			continue
		total += float(j.weight)
		counted += 1
	return total / counted if counted > 0 else 0.0

## How one person judges a deed of this kind, read from their own data by the rules in
## resources/characters/judgement.json. Returns {weight (Reputation points, in the rules' range),
## stance: "disapproves" | "indifferent" | "approves" | "hurt" | "child", reason, feels, rules: [ids]}.
## feels is their view in their own words ("" for a child or an unknown deed)
func judge(who: String, morals: String = "company") -> Dictionary:
	var out = {"weight": 0.0, "stance": "indifferent", "reason": "", "feels": "", "rules": []}
	var rules: Dictionary = _judgement().get(morals, {})
	if rules.is_empty() or who == "":
		return out
	who = _who(who)
	if _is_minor(who):
		out.stance = "child"
		return out
	var n = _nature(who)
	var best: Dictionary = {}       # group -> strongest rule that holds
	var tone: Dictionary = {}
	for rule in rules.get("rules", []):
		if not _rule_holds(rule, n, who):
			continue
		if rule.get("tone", false):
			tone = rule
			continue
		var g = str(rule.get("group", rule.get("id", "")))
		if not best.has(g) or absf(float(rule.weight)) > absf(float(best[g].weight)):
			best[g] = rule
	var held: Array = best.values()
	held.sort_custom(func(a, b): return absf(float(a.weight)) > absf(float(b.weight)))
	var w = 0.0
	for rule in held:
		w += float(rule.weight)
		out.rules.append(str(rule.id))
	var reasons: Array = held.map(func(r): return str(r.get("reason", r.id)))
	var feels = str(held[0].get("feels", "")) if not held.is_empty() else ""
	var hurt = _courting_weight(n, rules.get("courting", {}))
	if hurt < 0.0:
		# Courting the player outweighs everything else they think of it
		w = minf(w, hurt)
		reasons.push_front(str(rules.courting.get("reason", "courting")))
		feels = str(rules.courting.get("feels", feels))
		out.rules.push_front("courting")
		out.stance = "hurt"
	elif not tone.is_empty() and w < 0.0:
		feels = str(tone.get("feels", feels))
		reasons.append(str(tone.get("reason", tone.id)))
		out.rules.append(str(tone.id))
	var span: Array = rules.get("range", [-12, 3])
	out.weight = clampf(w, float(span[0]), float(span[1]))
	if out.stance != "hurt":
		out.stance = "disapproves" if out.weight < 0.0 else ("approves" if out.weight > 0.0 else "indifferent")
	var dflt: Dictionary = rules.get("default", {})
	out.reason = "; ".join(reasons) if not reasons.is_empty() else str(dflt.get("reason", ""))
	out.feels = feels if feels != "" else str(dflt.get("feels", ""))
	return out

## Their view of the deed in their own words, for what they know of it ("" when it is no such deed)
func reaction(who: String, morals: String = "company") -> String:
	return str(judge(who, morals).feels)

## True when a faith rule holds for them (judgement.json group "faith")
func is_pious(who: String) -> bool:
	var rules: Dictionary = _judgement().get("company", {})
	var n = _nature(_who(who))
	for rule in rules.get("rules", []):
		if str(rule.get("group", "")) == "faith" and _rule_holds(rule, n, _who(who)):
			return true
	return false

## judgement.json's "morals" block (read once)
func _judgement() -> Dictionary:
	if _judgement_rules.is_empty():
		var f = FileAccess.open(JUDGEMENT_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text()) if f else null
		_judgement_rules = data.get("morals", {}) if data is Dictionary else {}
		if _judgement_rules.is_empty():
			push_warning("[Taverns] No judgement rules at %s" % JUDGEMENT_PATH)
	return _judgement_rules

## What the rules read of someone: {scope: main|generic|"", key, soul, values, dislikes, interests,
## roles, archetype, voice, traits (Big Five)}
func _nature(who: String) -> Dictionary:
	var n = {"scope": "", "key": "", "soul": null, "values": [], "dislikes": [], "interests": [], "roles": [],
		"archetype": "", "voice": "", "traits": {}}
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.has_method("get_instance") else null
	if inst != null:
		n.scope = "generic"
		n.archetype = str(inst.archetype_id)
		var arch = gm.get_archetype(n.archetype) if gm.has_method("get_archetype") else null
		if arch and int(inst.voice_variant) >= 0 and int(inst.voice_variant) < arch.voice_variants.size():
			n.voice = str(arch.voice_variants[int(inst.voice_variant)])
		for t in ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]:
			n.traits[t] = inst.get_trait(t)
		return n
	var registry = _node("WorldRegistry")
	var key = registry.get_npc_key(who) if registry else ""
	if key == "":
		return n
	n.scope = "main"
	n.key = key
	n.roles = [str(registry.get_npc(key).get("role", ""))]
	var soul = _soul(str(registry.get_npc_id(key)))
	if soul:
		n.soul = soul
		n.values = Array(soul.core_values)
		n.dislikes = Array(soul.dislikes)
		n.interests = Array(soul.interests)
		for t in ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"]:
			n.traits[t] = int(soul.get("trait_" + t))
	return n

## Every condition of a rule holds for them (word lists: any word inside any entry, lower case)
func _rule_holds(rule: Dictionary, n: Dictionary, who: String) -> bool:
	if n.scope == "":
		return false
	if rule.has("scope") and str(rule.scope) != n.scope:
		return false
	for field in ["values", "dislikes", "interests", "roles"]:
		if rule.has(field) and not _words_in(rule[field], n[field]):
			return false
	if rule.has("archetypes") and not n.archetype in rule.archetypes:
		return false
	if rule.has("voices") and not _words_in(rule.voices, [n.voice]):
		return false
	for f in rule.get("flags", {}):
		if n.soul == null or bool(n.soul.get(f)) != bool(rule.flags[f]):
			return false
	for t in rule.get("traits", {}):
		var span: Array = rule.traits[t]
		if not n.traits.has(t) or int(n.traits[t]) < int(span[0]) or int(n.traits[t]) > int(span[1]):
			return false
	if rule.get("keeps_back_rooms", false) and not tavern_ids().any(func(loc): return is_brothel(loc) and is_keeper(who, loc)):
		return false
	return true

func _words_in(words: Array, entries: Array) -> bool:
	var text = " | ".join(entries.map(func(e): return str(e))).to_lower()
	return words.any(func(w): return text.contains(str(w).to_lower()))

## How much it hurts someone courting the player (0 when they are not): a main NPC who could love the
## player and has the romance (a flag, or their soul's thresholds met) weighs their style's weight;
## one growing fond (affection near their own threshold), budding_scale of it
func _courting_weight(n: Dictionary, c: Dictionary) -> float:
	var soul = n.soul
	if c.is_empty() or n.scope != "main" or soul == null or not soul.is_romantic_available:
		return 0.0
	if str(soul.orientation) in c.get("never", []):
		return 0.0
	var style = float(c.get("styles", {}).get(str(soul.relationship_style), 0.0))
	if style >= 0.0:
		return 0.0
	var ws = _node("WorldState")
	for f in c.get("flags", []):
		if ws and ws.has_method("get_world_flag") and ws.get_world_flag(str(f).format({"key": n.key})):
			return style
	var director = _node("StorylineDirector")
	var dims: Dictionary = director.get_relationship_dims(n.key) if director and director.has_method("get_relationship_dims") else {}
	var trust = float(dims.get("trust", 0.0))
	var affection = float(dims.get("affection", 0.0))
	if soul.is_romance_unlocked(trust, affection, float(dims.get("familiarity", 0.0))):
		return style
	if affection > 0.0 and affection >= float(c.get("affection_share", 0.75)) * float(soul.romance_affection_threshold):
		return style * float(c.get("budding_scale", 0.67))
	return 0.0

## Of a night, the companions hear what the lodgers know of the stranger, and it travels on from them
## (PlayerEvents.spread). Once a night per house. Returns the event ids passed on
func pillow_talk(location: String) -> Array:
	var passed: Array = []
	if not brothel_open(location):
		return passed
	var day = floori(_now() / 1440.0)
	if int(_talk_days.get(location, -1)) == day:
		return passed
	var hearers = companions(location)
	var talkers = lodgers(location).values()
	var events = _node("PlayerEvents")
	if hearers.is_empty() or talkers.is_empty() or events == null:
		return passed
	_talk_days[location] = day
	var known: Dictionary = events.knowledge_of(talkers)
	var ids: Array = known.keys()
	ids.sort_custom(func(a, b): return int(known[a].event.get("minute", 0)) > int(known[b].event.get("minute", 0)))
	for id in ids.slice(0, PILLOW_TALK_MAX):
		var r: Dictionary = events.spread(str(id), hearers, PILLOW_TALK_VIA)
		if r.get("ok", false):
			passed.append(id)
	return passed

# =============================================================================
# THE SCENE: lodgers go up to their rooms
# =============================================================================

## Put tonight's lodgers in this scene at their rooms' spawn markers
func settle(scene_root: Node, location: String) -> int:
	if scene_root == null or not is_tavern(location):
		return 0
	var placed = 0
	var spawns = scene_root.find_child("SpawnPoints", true, false)
	var by_room: Dictionary = lodgers(location)
	for room in by_room:
		var marker = spawns.get_node_or_null(str(room)) if spawns else null
		if not marker is Node2D:
			continue
		for npc in scene_root.get_tree().get_nodes_in_group("npcs"):
			if npc is Node2D and scene_root.is_ancestor_of(npc) and _body_who(npc) == str(by_room[room]):
				npc.global_position = marker.global_position
				placed += 1
	return placed

func _on_arrived(location: String) -> void:
	if is_tavern(location):
		call_deferred("_settle_current", location)

func _settle_current(location: String) -> void:
	var tree = get_tree()
	if tree and tree.current_scene:
		settle(tree.current_scene, location)

func _on_time_advanced(_minutes: int, _total: int, _reason: String) -> void:
	if not _is_lodging_hour():
		return
	for location in tavern_ids():
		if is_brothel(location):
			pillow_talk(location)
	var scenes = _node("SceneManager")
	var here = str(scenes.get_current_location_id()) if scenes and scenes.has_method("get_current_location_id") else ""
	if is_tavern(here):
		_settle_current(here)

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {"rentals": _rentals.duplicate(true), "talk_days": _talk_days.duplicate()}

func load_from_dict(data: Dictionary) -> void:
	reset()
	var rentals = data.get("rentals", {})
	if rentals is Dictionary:
		for loc in rentals:
			var r = rentals[loc]
			if r is Dictionary and r.has("room") and r.has("until"):
				_rentals[str(loc)] = {"room": str(r.room), "until": int(r.until), "paid": int(r.get("paid", 0)),
					"minute": int(r.get("minute", 0)), "how": str(r.get("how", "bed"))}
	var talk = data.get("talk_days", {})
	if talk is Dictionary:
		for loc in talk:
			_talk_days[str(loc)] = int(talk[loc])

# =============================================================================
# HELPERS
# =============================================================================

func _is_lodging_hour() -> bool:
	var hour = floori((_now() % 1440) / 60.0)
	return hour >= LODGE_FROM_HOUR or hour < 6

## A traveller here for the night: a road archetype, or a roster NPC whose home is elsewhere. Never
## the keeper, a companion, or a child
func _is_traveller(who: String, location: String) -> bool:
	if who == "" or is_keeper(who, location) or is_companion(who) or _is_minor(who):
		return false
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.has_method("get_instance") else null
	if inst != null:
		return str(inst.archetype_id) in TRAVELLER_ARCHETYPES
	var registry = _node("WorldRegistry")
	return registry != null and registry.get_npc_key(who) != "" and registry.get_npc_home(registry.get_npc_key(who)) != location

func _present(location: String) -> Array:
	if present_override.has(location):
		return present_override[location]
	var events = _node("PlayerEvents")
	return events.get_present(location) if events and events.has_method("get_present") else []

func _opinion(who: String) -> float:
	if who == "":
		return 0.0
	var rep = load("res://scripts/world_state/reputation.gd")
	return float(rep.of("npc", who)) if rep else 0.0

func _is_minor(who: String) -> bool:
	var registry = _node("WorldRegistry")
	return registry != null and registry.has_method("is_minor") and registry.is_minor(who)

func _who(x: String) -> String:
	var events = _node("PlayerEvents")
	return str(events._who(x)) if events and events.has_method("_who") else x

func _body_who(npc: Node) -> String:
	if npc.has_meta("generic_id"):
		return str(npc.get_meta("generic_id"))
	return _who(str(npc.get("npc_id"))) if npc.get("npc_id") != null else ""

func _name(who: String) -> String:
	var registry = _node("WorldRegistry")
	var key = registry.get_npc_key(who) if registry else ""
	if key != "":
		return str(registry.get_npc_name(key))
	return "the keeper" if who == "" else "they"

func _place(location: String) -> String:
	var registry = _node("WorldRegistry")
	return str(registry.get_location_name(location)) if registry and registry.has_location(location) else location

## The personality resource with this npc_id (every soul read once)
func _soul(npc_id: String):
	if _souls.is_empty():
		var dir = DirAccess.open(PERSONALITY_DIR)
		if dir:
			for f in dir.get_files():
				if f.ends_with(".tres"):
					var res = load("%s/%s" % [PERSONALITY_DIR, f])
					if res and "npc_id" in res and "core_values" in res:
						_souls[str(res.npc_id)] = res
		_souls["_read"] = null
	return _souls.get(npc_id)

## A line of narration in the scene's dialogue UI (as StoryItem does), else the log
func _narrate(text: String) -> void:
	print("[Taverns] " + text)
	var tree = get_tree()
	var ui = tree.current_scene.find_child("DialogueUI", true, false) if tree and tree.current_scene else null
	if ui and ui.has_method("show_narration"):
		ui.show_narration(text)

func _now() -> int:
	if now_override >= 0:
		return now_override
	var ws = _node("WorldState")
	return int(ws.get_game_minutes()) if ws and ws.has_method("get_game_minutes") else 0

func _generics() -> Node:
	var registry = _node("DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry and registry.generics else null

func _node(n: String) -> Node:
	return get_node_or_null("/root/" + n)
