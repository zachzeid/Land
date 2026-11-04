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
const SETTLED_META = "tavern_settled_from"  # where a lodger's body stood before it went up
const REFUSE_BELOW = -30.0     # a keeper's opinion of the player under which no room is let
const COMPANY_COPPER = 15      # a companion's usual fee (about a day and a half's labour)
const COMPANY_MINUTES = 60
const FADE_SECONDS = 0.6       # the back room's fade to black, each way
const COMPANY_REFUSE_BELOW = -20.0
const PILLOW_TALK_VIA = "talk in the back rooms"
const PILLOW_TALK_MAX = 3      # events a night's talk carries on
## Who disapproves of the back rooms, by their own nature: a soul whose values hold one of these
## (npc_personalities core_values), whose calling is the church (world.json role), or a devout
## archetype (generics). Everyone else does not care
const PIOUS_VALUES = ["faith", "piety", "prayer", "devotion", "chastity", "virtue", "the dawn"]
const PIOUS_CALLINGS = ["cathedral", "abbey", "chapel", "priest", "monk", "nun", "acolyte"]
const PIOUS_ARCHETYPES = ["cathedral_acolyte", "novice_monk", "pilgrim"]
const PERSONALITY_DIR = "res://resources/npc_personalities"
const DISAPPROVAL = -6.0       # what a disapproving soul weighs a visit at (Reputation points)

## Seams (null = autoloads); tests pin the clock and the rooms
var now_override: int = -1
var rooms_override: Dictionary = {}     # location -> [{room, rent, back_room}]
var present_override: Dictionary = {}   # location -> [who]

var _rentals: Dictionary = {}           # location -> {room, until, paid, minute, how}
var _talk_days: Dictionary = {}         # location -> the day the back rooms last passed talk on
var _room_cache: Dictionary = {}        # location -> [{room, rent, back_room}] read from its scene
var _values_cache: Dictionary = {}      # npc_id -> core_values

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
	_fade_to_black()
	_narrate("The door of the back room closes behind you. Later, you come back down to the common room.")
	out.ok = true
	out.reason = "company"
	print("[Taverns] The player kept company with %s at %s" % [who, location])
	company_kept.emit(out.merged({"who": who, "location": location}))
	return out

## What a party makes of a visit to the back rooms, by their own nature: DISAPPROVAL for the pious,
## 0 for everyone else (a faction or region: the mean of its people). For Reputation's `morals`
func judgement(parties: Array, morals: String = "company") -> float:
	if morals != "company" or parties.is_empty():
		return 0.0
	var total = 0.0
	for p in parties:
		total += DISAPPROVAL if is_pious(str(p)) else 0.0
	return total / parties.size()

func is_pious(who: String) -> bool:
	var gm = _generics()
	var inst = gm.get_instance(who) if gm and gm.has_method("get_instance") else null
	if inst != null:
		return str(inst.archetype_id) in PIOUS_ARCHETYPES
	var registry = _node("WorldRegistry")
	var key = registry.get_npc_key(who) if registry else ""
	if key == "":
		return false
	var role = str(registry.get_npc(key).get("role", "")).to_lower()
	if PIOUS_CALLINGS.any(func(w): return role.contains(w)):
		return true
	var values = " ".join(_core_values(str(registry.get_npc_id(key)))).to_lower()
	return PIOUS_VALUES.any(func(w): return values.contains(w))

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

## Put tonight's lodgers in this scene at their rooms' spawn markers; out of the lodging hours (or
## no longer a lodger) a body settle moved goes back to where it stood before it went up. Returns
## how many bodies stand in a room
func settle(scene_root: Node, location: String) -> int:
	if scene_root == null or not is_tavern(location):
		return 0
	var placed = 0
	var spawns = scene_root.find_child("SpawnPoints", true, false)
	var by_room: Dictionary = lodgers(location)
	var room_of: Dictionary = {}  # who -> room
	for room in by_room:
		room_of[str(by_room[room])] = str(room)
	for npc in scene_root.get_tree().get_nodes_in_group("npcs"):
		if not (npc is Node2D and scene_root.is_ancestor_of(npc)):
			continue
		var who = _body_who(npc)
		var marker = spawns.get_node_or_null(room_of[who]) if spawns and room_of.has(who) else null
		if marker is Node2D:
			if not npc.has_meta(SETTLED_META):
				npc.set_meta(SETTLED_META, npc.global_position)
			npc.global_position = marker.global_position
			placed += 1
		elif npc.has_meta(SETTLED_META):
			npc.global_position = npc.get_meta(SETTLED_META)  # morning: down from the room again
			npc.remove_meta(SETTLED_META)
	return placed

func _on_arrived(location: String) -> void:
	if is_tavern(location):
		call_deferred("_settle_current", location)

func _settle_current(location: String) -> void:
	var tree = get_tree()
	if tree and tree.current_scene:
		settle(tree.current_scene, location)

func _on_time_advanced(_minutes: int, _total: int, _reason: String) -> void:
	if _is_lodging_hour():
		for location in tavern_ids():
			if is_brothel(location):
				pillow_talk(location)
	# Settle every hour of the day: by night lodgers go up, by morning they come down again
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

## core_values of the personality resource with this npc_id (read once)
func _core_values(npc_id: String) -> Array:
	if _values_cache.is_empty():
		var dir = DirAccess.open(PERSONALITY_DIR)
		if dir:
			for f in dir.get_files():
				if f.ends_with(".tres"):
					var res = load("%s/%s" % [PERSONALITY_DIR, f])
					if res and "npc_id" in res and "core_values" in res:
						_values_cache[str(res.npc_id)] = Array(res.core_values)
		_values_cache["_read"] = []
	return _values_cache.get(npc_id, [])

## The screen goes dark for the hour and comes back (SceneManager's fade overlay); nothing is shown
func _fade_to_black() -> void:
	var scenes = _node("SceneManager")
	if scenes == null or not scenes.has_method("_fade_out") or scenes.get("fade_overlay") == null or not is_inside_tree():
		return
	await scenes._fade_out(FADE_SECONDS)
	await get_tree().create_timer(FADE_SECONDS * 2.0).timeout
	await scenes._fade_in(FADE_SECONDS)

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
