extends Node
## Crafting - recipes, stations (owner's leave), gathering nodes, quality, maker's mark, repair,
## commissions, and cooking through Herbcraft (docs/PLAYER_SYSTEMS.md §4)
## - Content is data: resources/crafting/{recipes,stations,nodes}.json (tools/validators/crafting.py)
## - Every deed goes through PlayerEvents.record: physical ones (gathering, crafting, theft, trespass,
##   feats) with Witnesses.in_sight witnesses at the live station or node; spoken ones (commissions)
##   with the NPC who heard them. Nothing here writes NPC memories, relationships or reputation
## - An owned station or node is a request: the owner's soul decides leave through
##   StorylineDirector.decide_situation (offline appeal or Claude, under its Agency and Lines)
## - Work takes game time (WorldState.advance_time) and uses the skill (PlayerStats.use_skill)

signal crafted(item: Dictionary)
signal gathered(item: Dictionary, node_id: String)
signal station_opened(station_id: String)
signal recipes_discovered(recipe_ids: Array)
signal node_changed(node_id: String)
signal leave_decided(target_id: String, granted: bool, decision: Dictionary)

const Witnesses = preload("res://scripts/world/witnesses.gd")
const Seasons = preload("res://scripts/world/seasons.gd")

const RECIPES_PATH = "res://resources/crafting/recipes.json"
const STATIONS_PATH = "res://resources/crafting/stations.json"
const NODES_PATH = "res://resources/crafting/nodes.json"
const ITEMS_DIR = "res://resources/items"
const HERBCRAFT_PATH = "res://scripts/crafting/herbcraft.gd"

const FEAT_QUALITY = 85               # a witnessed piece this good is talked about
const YIELD_SKILL_STEP = 35.0          # one more per take for every this much skill
const UNTRAINED_SKILL = 20.0           # recipes with no skill: an untrained hand
const GATHER_STAMINA = 8.0
const LEAVE_MINUTES = 3 * 1440         # leave given lasts three days, then the owner is asked again
const ASK_AGAIN_MINUTES = 1440         # a refusal stands for a day
const COOK_MINUTES = 30
const COOK_STATIONS = ["campfire", "herb_table"]
const MAX_INGREDIENTS = 5
const BUILD_MINUTES = 20
const REPAIR_DIFFICULTY = 0.5
const DEFAULT_MATERIAL_GRADE = 50.0
## The player is in Varn's service: work for him is what Bjorn's ally:varn Line refuses
const SERVES_VARN_FLAG = "hc_player_backed_varn"
const VARN_KEY = "varn"
const PLAYER = "player"
## The smithing 50 perk (resources/player/perks.json): what the player makes carries their mark
const MAKERS_MARK_PERK = "smithing_50_makers_mark"

# Content
var recipes: Dictionary = {}       # id -> recipe
var station_kinds: Dictionary = {} # kind -> {name, buildable, build, grade}
var stations: Dictionary = {}      # id -> station (stations.json plus the player's built ones)
var nodes: Dictionary = {}         # id -> gathering node
var _item_defs: Dictionary = {}    # id -> item definition (agent 2's resources/items), names only

# State (saved)
var known: Dictionary = {}         # recipe id -> how it was learned (discover | taught | found)
var node_state: Dictionary = {}    # node id -> {taken, since}: takes regrow one per regrow_minutes from since
var leave: Dictionary = {}         # station/node id -> {granted, minute, choice, reason}
var commissions: Dictionary = {}   # id -> {id, npc, item, due_day, event, status, minute}
var built: Dictionary = {}         # station id -> the player's own campfires and workbenches
var counter: int = 0

# Live scene nodes (station.gd / resource_node.gd register themselves): where deeds are seen from
var _live_stations: Dictionary = {}
var _live_nodes: Dictionary = {}

## Tests and tools: stand-ins for PlayerStats / Inventory / Herbcraft, and the player's location
var stats_override: Object = null
var inventory_override: Object = null
var herbcraft_override: Object = null
var player_location_override: String = ""

func _ready():
	load_content()
	print("Crafting initialized (%d recipes, %d stations, %d nodes)" % [recipes.size(), stations.size(), nodes.size()])

# =============================================================================
# CONTENT
# =============================================================================

func load_content(recipes_path: String = RECIPES_PATH, stations_path: String = STATIONS_PATH, nodes_path: String = NODES_PATH) -> void:
	recipes.clear()
	station_kinds.clear()
	stations.clear()
	nodes.clear()
	for r in _read_json(recipes_path).get("recipes", []):
		if r is Dictionary and str(r.get("id", "")) != "":
			recipes[str(r.id)] = r
	var sdata = _read_json(stations_path)
	station_kinds = sdata.get("kinds", {}) if sdata.get("kinds") is Dictionary else {}
	for s in sdata.get("stations", []):
		if s is Dictionary and str(s.get("id", "")) != "":
			stations[str(s.id)] = s
	for s in built.values():
		stations[str(s.id)] = s
	for n in _read_json(nodes_path).get("nodes", []):
		if n is Dictionary and str(n.get("id", "")) != "":
			nodes[str(n.id)] = n
	_load_item_defs()

func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {}).duplicate(true)

func get_station(station_id: String) -> Dictionary:
	return stations.get(station_id, {}).duplicate(true)

func get_node_def(node_id: String) -> Dictionary:
	return nodes.get(node_id, {}).duplicate(true)

## Stations and nodes at a location (for scenes that place them, and the UI)
func stations_at(location: String) -> Array:
	return stations.values().filter(func(s): return str(s.get("location", "")) == location).map(func(s): return str(s.id))

func nodes_at(location: String) -> Array:
	return nodes.values().filter(func(n): return str(n.get("location", "")) == location and node_exists(str(n.id))).map(func(n): return str(n.id))

func register_station(station_id: String, node: Node) -> void:
	_live_stations[station_id] = node

func unregister_station(station_id: String, node: Node) -> void:
	if _live_stations.get(station_id) == node:
		_live_stations.erase(station_id)

func register_node(node_id: String, node: Node) -> void:
	_live_nodes[node_id] = node

func unregister_node(node_id: String, node: Node) -> void:
	if _live_nodes.get(node_id) == node:
		_live_nodes.erase(node_id)

# =============================================================================
# RECIPES: discovery, learning, can_craft, craft
# =============================================================================

## Opening a station shows what the player can make there (and discovers recipes whose inputs they hold)
func open_station(station_id: String) -> Array:
	discover(station_id)
	station_opened.emit(station_id)
	return recipes_at(station_id)

## Recipes the player knows at this station: [{id, name, ok, reason}]
func recipes_at(station_id: String) -> Array:
	var kind = str(stations.get(station_id, {}).get("kind", ""))
	var out: Array = []
	for id in recipes:
		if str(recipes[id].get("station", "")) == kind and is_known(id):
			var check = can_craft(id, station_id)
			out.append({"id": id, "name": str(recipes[id].get("name", id)), "ok": check.ok, "reason": check.reason})
	return out

## For the crafting panel: the full recipe dicts the player knows at this station (discovering first),
## each with ok, reason (can_craft) and quality (preview_quality)
func get_recipes(station_id: String) -> Array:
	discover(station_id)
	var kind = str(stations.get(station_id, {}).get("kind", ""))
	var out: Array = []
	for id in recipes:
		if str(recipes[id].get("station", "")) == kind and is_known(id):
			var check = can_craft(id, station_id)
			out.append(recipes[id].duplicate(true).merged({"ok": check.ok, "reason": check.reason, "quality": preview_quality(id, station_id)}, true))
	return out

## The quality this recipe would come out at here, now (0-100; 0 for an unknown recipe or station)
func preview_quality(recipe_id: String, station_id: String) -> int:
	var r: Dictionary = recipes.get(recipe_id, {})
	var s: Dictionary = stations.get(station_id, {})
	if r.is_empty() or s.is_empty():
		return 0
	var skill_name = str(r.get("skill", ""))
	var skill = _skill(skill_name) if skill_name != "" else UNTRAINED_SKILL
	return quality_for(r, skill, float(s.get("grade", 50)), material_grade(r.get("inputs", {})))

## Valheim: holding a recipe's inputs at its station shows it. Returns the newly discovered ids
func discover(station_id: String) -> Array:
	var kind = str(stations.get(station_id, {}).get("kind", ""))
	var found: Array = []
	if kind == "":
		return found
	for id in recipes:
		var r: Dictionary = recipes[id]
		if str(r.get("station", "")) == kind and str(r.get("learn", "discover")) == "discover" and not known.has(id) and _has_inputs(r.get("inputs", {})):
			known[id] = "discover"
			found.append(id)
	if not found.is_empty():
		recipes_discovered.emit(found)
	return found

## A teacher (docs/PLAYER_SYSTEMS.md §2 teach) or a found page. how: taught | found
func learn_recipe(recipe_id: String, how: String = "taught") -> bool:
	if not recipes.has(recipe_id):
		return false
	known[recipe_id] = how
	recipes_discovered.emit([recipe_id])
	return true

func is_known(recipe_id: String) -> bool:
	if known.has(recipe_id):
		return true
	var r: Dictionary = recipes.get(recipe_id, {})
	return str(r.get("learn", "")) == "found" and str(r.get("found_flag", "")) != "" and _flag(str(r.found_flag))

## Returns {ok, reason, leave ("own"|"public"|"granted"|"refused"|"none"), trespass}
func can_craft(recipe_id: String, station_id: String) -> Dictionary:
	var r: Dictionary = recipes.get(recipe_id, {})
	var s: Dictionary = stations.get(station_id, {})
	if r.is_empty():
		return _no("there is no such recipe")
	if s.is_empty():
		return _no("there is no such station")
	if str(r.get("station", "")) != str(s.get("kind", "")):
		return _no("that is made at a %s" % _kind_name(str(r.get("station", ""))))
	var where = _not_here(s)
	if where != "":
		return _no(where)
	var discoverable = str(r.get("learn", "discover")) == "discover" and _has_inputs(r.get("inputs", {}))
	if not is_known(recipe_id) and not discoverable:
		return _no("you do not know how to make that")
	var skill = str(r.get("skill", ""))
	var need = float(r.get("min_level", 0))
	if skill != "" and _skill(skill) < need:
		return _no("that needs %s %d" % [skill, int(need)])
	var missing = _missing(r.get("inputs", {}))
	if missing != "":
		return _no("you need %s" % missing)
	var status = leave_status(station_id)
	return {"ok": true, "reason": "", "leave": status, "trespass": status in ["refused", "none"]}

## Returns {ok, item, reason, quality, events}
func craft(recipe_id: String, station_id: String) -> Dictionary:
	var check = can_craft(recipe_id, station_id)
	if not check.ok:
		return {"ok": false, "item": {}, "reason": check.reason}
	var r: Dictionary = recipes[recipe_id]
	var s: Dictionary = stations[station_id]
	discover(station_id)
	if not known.has(recipe_id) and is_known(recipe_id):
		known[recipe_id] = str(r.get("learn", "discover"))
	var inputs: Dictionary = r.get("inputs", {})
	var material = material_grade(inputs)
	if not _take(inputs):
		return {"ok": false, "item": {}, "reason": "the materials could not be taken"}
	var skill_name = str(r.get("skill", ""))
	var skill = _skill(skill_name) if skill_name != "" else UNTRAINED_SKILL
	var quality = quality_for(r, skill, float(s.get("grade", 50)), material)
	var out: Dictionary = r.get("output", {})
	var props = _made_props(out, quality, station_id)
	if not _give(str(out.get("id", "")), int(out.get("qty", 1)), props):
		_give_back(inputs)
		return {"ok": false, "item": {}, "reason": "you have no room to carry it"}
	_advance(int(r.get("minutes", 0)), "crafting")
	var witnesses = _witnesses_at(_live_stations.get(station_id))
	if skill_name != "":
		_use_skill(skill_name, float(r.get("difficulty", 1.0)), {"witnessed_by": witnesses, "target": recipe_id, "quality": quality})
	var item = props.merged({"id": str(out.get("id", "")), "qty": int(out.get("qty", 1))})
	var what = "%s %s" % [_made_verb(r), _with_article(_quality_word(quality), _item_name(item.id))]
	var events = _work_deeds(s, witnesses, check.trespass, what, quality, skill_name)
	crafted.emit(item.duplicate(true))
	return {"ok": true, "item": item, "reason": "", "quality": quality, "events": events}

## quality = skill x w.skill + station grade x w.station + material grade x w.material, 0-100
func quality_for(recipe: Dictionary, skill: float, station_grade: float, material: float) -> int:
	var w: Dictionary = recipe.get("quality", {})
	var ws = float(w.get("skill", 0.5))
	var wt = float(w.get("station", 0.25))
	var wm = float(w.get("material", 0.25))
	var total = ws + wt + wm
	if total <= 0.0:
		return 50
	return clampi(roundi((ws * skill + wt * station_grade + wm * material) / total), 0, 100)

## Mean quality of the inputs the player would use (the best of each in the pack), weighted by count
func material_grade(inputs: Dictionary) -> float:
	var sum = 0.0
	var count = 0
	var items = _inventory_items()
	for id in inputs:
		var need = int(inputs[id])
		var pool = items.filter(func(it): return str(it.get("id", "")) == str(id))
		pool.sort_custom(func(a, b): return float(a.get("quality", 0)) > float(b.get("quality", 0)))
		for it in pool:
			if need <= 0:
				break
			var n = mini(need, maxi(1, int(it.get("qty", 1))))
			sum += float(it.get("quality", DEFAULT_MATERIAL_GRADE)) * n
			count += n
			need -= n
		if need > 0:
			sum += DEFAULT_MATERIAL_GRADE * need
			count += need
	return sum / count if count > 0 else DEFAULT_MATERIAL_GRADE

# =============================================================================
# REPAIR AND RE-FORGE (durability back; quality, maker and provenance kept)
# =============================================================================

## Mend the most worn `item_id` the player carries; a broken one is re-forged (costs more)
## Returns {ok, item, reason, reforged, events}
func repair(item_id: String, station_id: String) -> Dictionary:
	var record = _most_worn(item_id)
	if record.is_empty():
		return {"ok": false, "item": {}, "reason": "you have nothing of that kind that needs mending"}
	var r = _recipe_for(item_id)
	var fix: Dictionary = r.get("repair", {}) if not r.is_empty() else {}
	if fix.is_empty():
		return {"ok": false, "item": {}, "reason": "that cannot be mended"}
	var s: Dictionary = stations.get(station_id, {})
	if s.is_empty() or str(s.get("kind", "")) != str(fix.get("station", "")):
		return {"ok": false, "item": {}, "reason": "that is mended at a %s" % _kind_name(str(fix.get("station", "")))}
	var where = _not_here(s)
	if where != "":
		return {"ok": false, "item": {}, "reason": where}
	var broken = float(record.get("durability", 0)) <= 0.0 or record.get("broken", false) == true
	var cost: Dictionary = fix.get("reforge", fix.get("inputs", {})) if broken else fix.get("inputs", {})
	var missing = _missing(cost)
	if missing != "":
		return {"ok": false, "item": {}, "reason": "you need %s" % missing}
	var trespass = leave_status(station_id) in ["refused", "none"]
	if not _take(cost):
		return {"ok": false, "item": {}, "reason": "the materials could not be taken"}
	if not _mend(item_id, record):
		_give_back(cost)
		return {"ok": false, "item": {}, "reason": "the item could not be mended"}
	var props: Dictionary = record.duplicate(true)
	for k in ["id", "qty", "broken"]:
		props.erase(k)
	props["durability"] = float(record.get("max_durability", record.get("durability", 1)))
	var minutes = int(fix.get("minutes", 30)) * (2 if broken else 1)
	_advance(minutes, "repair")
	var witnesses = _witnesses_at(_live_stations.get(station_id))
	var skill_name = str(r.get("skill", ""))
	if skill_name != "":
		_use_skill(skill_name, REPAIR_DIFFICULTY * (2.0 if broken else 1.0), {"witnessed_by": witnesses, "target": item_id})
	var item = props.merged({"id": item_id, "qty": 1})
	var what = "%s %s" % ["re-forged" if broken else "mended", _with_article("", _item_name(item_id))]
	var events = _work_deeds(s, witnesses, trespass, what, -1, skill_name)
	crafted.emit(item.duplicate(true))
	return {"ok": true, "item": item, "reason": "", "reforged": broken, "events": events}

# =============================================================================
# COOKING (delegates to Herbcraft.cook, agent 6)
# =============================================================================

## Free combination at a campfire or herb table. Returns {ok, item, reason, events}
func cook(ingredients: Array, station_id: String) -> Dictionary:
	var hc = _herbcraft()
	if hc == null:
		return {"ok": false, "item": {}, "reason": "herbcraft is not built yet"}
	var s: Dictionary = stations.get(station_id, {})
	if s.is_empty() or str(s.get("kind", "")) not in COOK_STATIONS:
		return {"ok": false, "item": {}, "reason": "cooking needs a campfire or an herb table"}
	var where = _not_here(s)
	if where != "":
		return {"ok": false, "item": {}, "reason": where}
	if ingredients.is_empty() or ingredients.size() > MAX_INGREDIENTS:
		return {"ok": false, "item": {}, "reason": "use one to %d ingredients" % MAX_INGREDIENTS}
	var need: Dictionary = {}
	for i in ingredients:
		need[str(i)] = int(need.get(str(i), 0)) + 1
	var missing = _missing(need)
	if missing != "":
		return {"ok": false, "item": {}, "reason": "you need %s" % missing}
	var ids = ingredients.map(func(i): return str(i))
	var result = hc.cook(ids, _skill("herbcraft"))
	if not result is Dictionary or str(result.get("item_id", "")) == "":
		return {"ok": false, "item": {}, "reason": "nothing comes of that"}
	var trespass = leave_status(station_id) in ["refused", "none"]
	if not _take(need):
		return {"ok": false, "item": {}, "reason": "the ingredients could not be taken"}
	var potency = float(result.get("potency", 0.0))
	var quality = clampi(roundi(float(result.get("quality", potency))), 0, 100)
	var props = {"quality": quality, "potency": potency, "effects": result.get("effects", []),
		"dubious": result.get("dubious", false) == true, "maker": PLAYER if _has_mark() else "",
		"provenance": {"from": station_id, "stolen": false, "owner": ""}}
	for k in ["name", "text", "kind"]:
		if result.has(k):
			props[k] = result[k]
	var item_id = str(result.item_id)
	if not _give(item_id, 1, props):
		_give_back(need)
		return {"ok": false, "item": {}, "reason": "you have no room to carry it"}
	_advance(COOK_MINUTES, "cooking")
	var witnesses = _witnesses_at(_live_stations.get(station_id))
	_use_skill("herbcraft", 1.0, {"witnessed_by": witnesses, "target": item_id})
	var item = props.merged({"id": item_id, "qty": 1})
	var events = _work_deeds(s, witnesses, trespass, "cooked %s" % _with_article("", _item_name(item_id)), -1, "herbcraft")
	# A remedy that is a story act (the Grey Fever cure): its flag, the first time, and a feat
	var flag = str(hc.story_flag_for(item_id)) if _hc_has(hc, "story_flag_for") else ""
	if flag != "" and not _flag(flag):
		var ws = get_node_or_null("/root/WorldState")
		if ws:
			ws.set_world_flag(flag, true)
		var deed = str(hc.deed_for(item_id)) if _hc_has(hc, "deed_for") else ""
		var ev = _record("feat", deed if deed != "" else "made %s" % _with_article("", _item_name(item_id)), [], {"witnesses": witnesses, "skill": "herbcraft"})
		if ev != "":
			events.append(ev)
		item["story_flag"] = flag
	crafted.emit(item.duplicate(true))
	return {"ok": true, "item": item, "reason": "", "events": events}

## Herbcraft is a static script: its methods are in the script's method list, not has_method
func _hc_has(hc: Object, method: String) -> bool:
	if hc is Script:
		return (hc as Script).get_script_method_list().any(func(m): return str(m.name) == method)
	return hc.has_method(method)

# =============================================================================
# THE PLAYER'S OWN STATIONS (campfire, workbench: anywhere outdoors)
# =============================================================================

## Returns {ok, station_id, reason}
func build_station(kind: String, location: String = "", position: Vector2 = Vector2.ZERO) -> Dictionary:
	var k: Dictionary = station_kinds.get(kind, {})
	if k.is_empty() or k.get("buildable", false) != true:
		return {"ok": false, "station_id": "", "reason": "you cannot build a %s" % _kind_name(kind)}
	var cost: Dictionary = k.get("build", {})
	var missing = _missing(cost)
	if missing != "":
		return {"ok": false, "station_id": "", "reason": "you need %s" % missing}
	if not _take(cost):
		return {"ok": false, "station_id": "", "reason": "the materials could not be taken"}
	counter += 1
	var id = "player_%s_%d" % [kind, counter]
	var s = {"id": id, "kind": kind, "name": "Your %s" % _kind_name(kind), "location": location if location != "" else _here(),
		"owner": PLAYER, "grade": int(k.get("grade", 30)), "fuel": "", "built": true, "x": position.x, "y": position.y}
	built[id] = s
	stations[id] = s
	_advance(BUILD_MINUTES, "building")
	return {"ok": true, "station_id": id, "reason": ""}

# =============================================================================
# LEAVE: an owned station or node is a request to its owner's soul
# =============================================================================

## "own" (the player's), "public" (nobody's), "granted", "refused" (asked, and not yet asked again), "none"
func leave_status(target_id: String) -> String:
	var owner = _owner_of(target_id)
	if owner == PLAYER:
		return "own"
	if owner == "":
		return "public"
	var l: Dictionary = leave.get(target_id, {})
	if l.is_empty():
		return "none"
	var age = _now() - int(l.get("minute", 0))
	if l.get("granted", false) == true:
		return "granted" if age < LEAVE_MINUTES else "none"
	return "refused" if age < ASK_AGAIN_MINUTES else "none"

## Ask the owner for leave to use a station or take from a node. purpose: {for: npc_key} when the
## work is for someone (work for Varn is tagged aids: varn, and Lines refuse it)
## Returns {granted, choice, reason, decision}
func ask_leave(target_id: String, purpose: Dictionary = {}) -> Dictionary:
	if not stations.has(target_id) and not nodes.has(target_id):
		return {"granted": false, "choice": "", "reason": "there is no such place to ask about", "decision": {}}
	var owner = _owner_of(target_id)
	if owner == "" or owner == PLAYER:
		return {"granted": true, "choice": "public" if owner == "" else "own", "reason": "", "decision": {}}
	var status = leave_status(target_id)
	if status in ["granted", "refused"]:
		var l: Dictionary = leave[target_id]
		return {"granted": status == "granted", "choice": str(l.get("choice", "")), "reason": str(l.get("reason", "")), "decision": {}}
	var director = get_node_or_null("/root/StorylineDirector")
	if director == null or not director.has_method("decide_situation"):
		return {"granted": false, "choice": "pass", "reason": "there is nobody to ask", "decision": {}}
	var hook = leave_hook(target_id, purpose)
	var decision: Dictionary = await director.decide_situation(owner, hook, str(hook.title))
	if director.has_method("apply_situation_effects"):
		director.apply_situation_effects(owner, decision, {"crafting": target_id})
	var choice = str(decision.get("choice", "pass"))
	var granted = choice == "grant"
	var reason = str(decision.get("reason", ""))
	leave[target_id] = {"granted": granted, "minute": _now(), "choice": choice, "reason": reason}
	leave_decided.emit(target_id, granted, decision.duplicate(true))
	return {"granted": granted, "choice": choice, "reason": reason, "decision": decision}

## The situation put to the owner's soul. Refusing comes first, so an owner who feels nothing for the
## player refuses (ties go to the earlier option); respect, trust and affection earn leave
func leave_hook(target_id: String, purpose: Dictionary = {}) -> Dictionary:
	var def: Dictionary = stations.get(target_id, nodes.get(target_id, {}))
	var name = str(def.get("name", target_id))
	var player = _player_name()
	var ask = str(def.get("ask", "The stranger asks leave to use %s." % _lower_first(name)))
	ask = ask.replace("The stranger", _upper_first(player))
	var serves_varn = _flag(SERVES_VARN_FLAG) or str(purpose.get("for", "")) == VARN_KEY
	if serves_varn:
		ask += " The work is for Varn's men."
	var grant = {"id": "grant", "label": "Give leave to use %s" % _lower_first(name),
		"appeal": {"respect": 1.0, "trust": 0.5, "affection": 0.3, "familiarity": 0.2}, "effects": []}
	if serves_varn:
		grant["aids"] = VARN_KEY
	var refuse = {"id": "refuse", "label": "Refuse; %s is not for the asking" % _lower_first(name), "appeal": {}, "effects": []}
	return {"id": "leave_" + target_id, "type": "react", "situation": ask, "title": "Leave to use %s" % _lower_first(name),
		"options": [refuse, grant]}

# =============================================================================
# GATHERING
# =============================================================================

## A node is there to take from (story-gated nodes need one of their flags)
func node_exists(node_id: String) -> bool:
	var n: Dictionary = nodes.get(node_id, {})
	if n.is_empty():
		return false
	var gate: Array = n.get("requires_any_flag", [])
	return gate.is_empty() or gate.any(func(f): return _flag(str(f)))

## Takes left before it is bare
func node_available(node_id: String) -> int:
	var n: Dictionary = nodes.get(node_id, {})
	return maxi(0, int(n.get("charges", 1)) - _taken(node_id)) if not n.is_empty() else 0

## The game minute the next take grows back (-1 when nothing is taken)
func node_regrows_at(node_id: String) -> int:
	if _taken(node_id) == 0:
		return -1
	return int(node_state[node_id].since) + maxi(1, int(nodes[node_id].get("regrow_minutes", 1440)))

## The season a node can be taken in: its own `season`, else (a herb) its ingredient's, else "any"
func node_season(node_id: String):
	var n: Dictionary = nodes.get(node_id, {})
	if n.has("season"):
		return n.season
	if str(n.get("kind", "")) == "herb":
		var hc = _herbcraft()
		var ing: Dictionary = hc.ingredient(str(n.get("item", ""))) if hc else {}
		return str(ing.get("season", Seasons.ANY))
	return Seasons.ANY

## The season now, by the game clock (world.json calendar.seasons)
func season_now() -> String:
	return Seasons.season_at(_now())

## Whether a node grows in the season the clock is in
func node_in_season(node_id: String) -> bool:
	return Seasons.in_season(node_season(node_id), season_now())

## Take from a node. at: the live node (where the deed is seen from; default the registered one)
## Returns {ok, item, qty, reason, stolen, events}
func gather(node_id: String, at: Node = null) -> Dictionary:
	var n: Dictionary = nodes.get(node_id, {})
	if n.is_empty() or not node_exists(node_id):
		return {"ok": false, "item": {}, "qty": 0, "reason": "there is nothing to take here"}
	var where = _not_here(n)
	if where != "":
		return {"ok": false, "item": {}, "qty": 0, "reason": where}
	if not node_in_season(node_id):
		var season = node_season(node_id)
		var when = " or ".join(season) if season is Array else str(season)
		return {"ok": false, "item": {}, "qty": 0, "reason": "nothing grows here in %s; come back in %s" % [season_now(), when]}
	if node_available(node_id) <= 0:
		var hours = ceili(maxf(0.0, node_regrows_at(node_id) - _now()) / 60.0)
		return {"ok": false, "item": {}, "qty": 0, "reason": "it is bare; give it %d hour(s)" % hours}
	var tool = str(n.get("tool", ""))
	if tool != "" and not _inventory().has(tool, 1):
		return {"ok": false, "item": {}, "qty": 0, "reason": "you need %s" % _with_article("", _item_name(tool))}
	if not _stats().spend_stamina(GATHER_STAMINA):
		return {"ok": false, "item": {}, "qty": 0, "reason": "you are too tired"}
	var skill_name = str(n.get("skill", ""))
	var skill = _skill(skill_name) if skill_name != "" else 0.0
	var qty = int(n.get("base_yield", 1)) + (floori(skill / YIELD_SKILL_STEP) if skill_name != "" else 0)
	var quality = clampi(roundi(float(n.get("grade", 50)) + skill * 0.1), 0, 100)
	var owner = str(n.get("owner", ""))
	var stolen = owner != "" and owner != PLAYER and leave_status(node_id) != "granted"
	var props = {"quality": quality, "maker": "", "provenance": {"from": node_id, "stolen": stolen, "owner": owner}}
	var item_id = str(n.get("item", ""))
	if not _give(item_id, qty, props):
		return {"ok": false, "item": {}, "qty": 0, "reason": "you have no room to carry it"}
	_advance(int(n.get("minutes", 10)), "gathering")
	var live = at if at != null else _live_nodes.get(node_id)
	var witnesses = _witnesses_at(live, stolen)
	if skill_name != "" and float(n.get("difficulty", 1.0)) > 0.0:
		_use_skill(skill_name, float(n.get("difficulty", 1.0)), {"witnessed_by": witnesses, "target": node_id})
	if tool != "" and str(_inventory().get_equipped("tool").get("id", "")) == tool:
		_inventory().wear("tool", 1.0)
	var taken = _taken(node_id)
	if taken == 0:
		node_state[node_id] = {"taken": 1, "since": _now()}
	else:
		node_state[node_id].taken = taken + 1
	var events: Array = []
	if stolen:
		var ev = _record("theft", "took %s from %s" % [_amount(qty, item_id), _owned_place(n)], [owner], {"witnesses": witnesses})
		if ev != "":
			events.append(ev)
	var item = props.merged({"id": item_id, "qty": qty})
	gathered.emit(item.duplicate(true), node_id)
	node_changed.emit(node_id)
	return {"ok": true, "item": item, "qty": qty, "reason": "", "stolen": stolen, "events": events}

# =============================================================================
# COMMISSIONS (agent 9's templates ask; the player promises and delivers)
# =============================================================================

## A promise to make something for someone by a day. Returns {ok, commission_id, event_id, reason}
func offer_commission(npc_key: String, item_id: String, due_day: int) -> Dictionary:
	if npc_key == "" or item_id == "":
		return {"ok": false, "commission_id": "", "event_id": "", "reason": "a commission needs someone and something"}
	var summary = "promised %s %s by day %d" % [_npc_name(npc_key), _with_article("", _item_name(item_id)), due_day]
	var ev = _record("promise", summary, [npc_key], {"witnesses": [npc_key], "due": {"day": due_day}})
	counter += 1
	var id = "commission_%d" % counter
	commissions[id] = {"id": id, "npc": npc_key, "item": item_id, "due_day": due_day, "event": ev, "status": "open", "minute": _now()}
	return {"ok": ev != "", "commission_id": id, "event_id": ev, "reason": "" if ev != "" else "the promise could not be recorded"}

## Inventory.repair mends the most worn record (broken first) fully, keeping quality, maker and
## provenance; without it, the record is taken up and put back whole
func _mend(item_id: String, record: Dictionary) -> bool:
	var inv = _inventory()
	if inv and inv.has_method("repair"):
		return inv.repair(item_id, -1.0)
	if not (inv and inv.remove(item_id, 1)):
		return false
	var props: Dictionary = record.duplicate(true)
	for k in ["id", "qty", "uid", "broken", "recognised"]:
		props.erase(k)
	props["durability"] = float(record.get("max_durability", record.get("durability", 1)))
	return _give(item_id, 1, props)

## Give something the player carries to someone: a gift with its quality, and for a weapon or armour
## a help about them too (arming a side: emergence's buyer_for_the_blades reads a help about a Hollow
## member). Returns {ok, reason, quality, events}
func give_item(npc_key: String, item_id: String) -> Dictionary:
	var record = _best(item_id)
	if record.is_empty():
		return {"ok": false, "reason": "you have no %s" % _item_name(item_id), "quality": 0, "events": []}
	if not _inventory().remove(item_id, 1):
		return {"ok": false, "reason": "it could not be handed over", "quality": 0, "events": []}
	var quality = int(record.get("quality", 50))
	var who = _npc_name(npc_key)
	var thing = _with_article(_quality_word(quality), _item_name(item_id))
	var made = " of their own make" if str(record.get("maker", "")) == PLAYER else ""
	var events: Array = [_record("gift", "gave %s %s%s" % [who, thing, made], [npc_key], {"witnesses": [npc_key], "with_present": true})]
	if _item_kind(item_id) in ["weapon", "armour"]:
		events.append(_record("help", "armed %s with %s" % [who, thing], [npc_key], {"witnesses": [npc_key], "with_present": true}))
	return {"ok": true, "reason": "", "quality": quality, "events": events.filter(func(e): return e != "")}

## Hand over the best `item_id` the player carries for an open commission to npc_key: a help and a
## gift with its quality, and the promise kept (unless it already broke). Returns {ok, reason, quality, events}
func deliver_commission(npc_key: String, item_id: String) -> Dictionary:
	var c: Dictionary = {}
	for id in commissions:
		var x: Dictionary = commissions[id]
		if x.npc == npc_key and x.item == item_id and x.status == "open":
			c = x
			break
	if c.is_empty():
		return {"ok": false, "reason": "nobody is waiting on that from them", "quality": 0, "events": []}
	var record = _best(item_id)
	if record.is_empty():
		return {"ok": false, "reason": "you have no %s" % _item_name(item_id), "quality": 0, "events": []}
	if not _inventory().remove(item_id, 1):
		return {"ok": false, "reason": "it could not be handed over", "quality": 0, "events": []}
	var quality = int(record.get("quality", 50))
	var made = " of their own make" if str(record.get("maker", "")) == PLAYER else ""
	var thing = _with_article(_quality_word(quality), _item_name(item_id))
	var who = _npc_name(npc_key)
	var events: Array = []
	events.append(_record("help", "made %s the %s they asked for" % [who, _item_name(item_id)], [npc_key], {"witnesses": [npc_key], "with_present": true}))
	events.append(_record("gift", "gave %s %s%s" % [who, thing, made], [npc_key], {"witnesses": [npc_key], "with_present": true}))
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe and str(c.get("event", "")) != "":
		pe.resolve_promise(str(c.event), "kept", "delivered %s" % thing)
	c.status = "delivered"
	c["quality"] = quality
	return {"ok": true, "reason": "", "quality": quality, "events": events.filter(func(e): return e != "")}

func get_commissions(status: String = "") -> Array:
	return commissions.values().filter(func(c): return status == "" or c.status == status).map(func(c): return c.duplicate(true))

# =============================================================================
# DEEDS
# =============================================================================

## What working at a station says about the player: crafted (always), feat (a witnessed piece that
## stands out), trespass (an owner's station without leave) and theft of fuel (if seen)
func _work_deeds(s: Dictionary, witnesses: Array, trespass: bool, what: String, quality: int, skill_name: String) -> Array:
	var events: Array = []
	var owner = str(s.get("owner", ""))
	var at = _lower_first(str(s.get("name", "a station")))
	var about: Array = [owner] if owner != "" and owner != PLAYER else []
	events.append(_record("crafted", "%s at %s" % [what, at], about, {"witnesses": witnesses}))
	if quality >= FEAT_QUALITY and not witnesses.is_empty():
		events.append(_record("feat", "%s at %s, finer work than most (%s)" % [what, at, skill_name if skill_name != "" else "handcraft"], [], {"witnesses": witnesses, "skill": skill_name}))
	if trespass and not about.is_empty():
		events.append(_record("trespass", "worked %s without leave" % at, about, {"witnesses": witnesses}))
		var fuel = str(s.get("fuel", ""))
		if fuel != "" and not witnesses.is_empty():
			events.append(_record("theft", "burned %s's %s at %s" % [_npc_name(owner), _item_name(fuel), at], about, {"witnesses": witnesses}))
	return events.filter(func(e): return e != "")

func _record(kind: String, summary: String, about: Array, opts: Dictionary) -> String:
	var pe = get_node_or_null("/root/PlayerEvents")
	return pe.record(kind, summary, about, opts) if pe else ""

func _witnesses_at(node, stealthy: bool = false) -> Array:
	if node == null or not is_instance_valid(node) or not node is Node2D or not node.is_inside_tree():
		return []
	var opts: Dictionary = {}
	if stealthy:
		opts["stealth"] = _skill("stealth")
	return Witnesses.in_sight(_scene_root_of(node), node.global_position, opts)

## The scene a node lives in: its ancestor just below the tree root
func _scene_root_of(node: Node) -> Node:
	var at = node
	while at.get_parent() != null and at.get_parent() != get_tree().root:
		at = at.get_parent()
	return at

# =============================================================================
# HELPERS
# =============================================================================

func _stats() -> Object:
	return stats_override if stats_override != null else get_node_or_null("/root/PlayerStats")

func _inventory() -> Object:
	return inventory_override if inventory_override != null else get_node_or_null("/root/Inventory")

## Agent 6's static Herbcraft, once it exists
func _herbcraft() -> Object:
	if herbcraft_override != null:
		return herbcraft_override
	return load(HERBCRAFT_PATH) if ResourceLoader.exists(HERBCRAFT_PATH) else null

func _skill(skill_name: String) -> float:
	var s = _stats()
	return float(s.get_skill(skill_name)) if s and skill_name != "" else 0.0

func _use_skill(skill_name: String, difficulty: float, context: Dictionary) -> Dictionary:
	var s = _stats()
	return s.use_skill(skill_name, difficulty, context) if s else {}

func _has_mark() -> bool:
	var s = _stats()
	return s != null and (s.has_perk(MAKERS_MARK_PERK) or s.has_perk("makers_mark"))

func _inventory_items() -> Array:
	var inv = _inventory()
	return inv.get_items() if inv else []

func _has_inputs(inputs: Dictionary) -> bool:
	return _missing(inputs) == ""

## "" when the player holds everything, else what is missing ("2 steel bar, wood")
func _missing(inputs: Dictionary) -> String:
	var inv = _inventory()
	var lacking: Array = []
	for id in inputs:
		var n = int(inputs[id])
		if n > 0 and not (inv and inv.has(str(id), n)):
			lacking.append(_amount(n, str(id)))
	return ", ".join(lacking)

func _take(inputs: Dictionary) -> bool:
	var inv = _inventory()
	var taken: Dictionary = {}
	for id in inputs:
		var n = int(inputs[id])
		if n <= 0:
			continue
		if not (inv and inv.remove(str(id), n)):
			_give_back(taken)
			return false
		taken[id] = n
	return true

func _give_back(inputs: Dictionary) -> void:
	for id in inputs:
		_give(str(id), int(inputs[id]), {})

func _give(item_id: String, qty: int, props: Dictionary) -> bool:
	var inv = _inventory()
	return inv != null and item_id != "" and qty > 0 and inv.add(item_id, qty, props)

## A made thing: quality, durability scaled by quality (half at 0, one and a half at 100), the maker's mark
func _made_props(out: Dictionary, quality: int, station_id: String) -> Dictionary:
	var props = {"quality": quality, "maker": PLAYER if _has_mark() else "",
		"provenance": {"from": station_id, "stolen": false, "owner": ""}}
	if out.has("durability"):
		var d = roundf(float(out.durability) * (0.5 + quality / 100.0))
		props["durability"] = d
		props["max_durability"] = d
	return props

func _records_of(item_id: String) -> Array:
	return _inventory_items().filter(func(it): return str(it.get("id", "")) == item_id)

func _most_worn(item_id: String) -> Dictionary:
	var pool = _records_of(item_id).filter(func(it): return float(it.get("durability", 0)) < float(it.get("max_durability", 0)) or it.get("broken", false) == true)
	pool.sort_custom(func(a, b): return float(a.get("durability", 0)) < float(b.get("durability", 0)))
	return pool[0].duplicate(true) if not pool.is_empty() else {}

func _best(item_id: String) -> Dictionary:
	var pool = _records_of(item_id)
	pool.sort_custom(func(a, b): return float(a.get("quality", 0)) > float(b.get("quality", 0)))
	return pool[0].duplicate(true) if not pool.is_empty() else {}

func _recipe_for(item_id: String) -> Dictionary:
	for id in recipes:
		if str(recipes[id].get("output", {}).get("id", "")) == item_id:
			return recipes[id]
	return {}

func _owner_of(target_id: String) -> String:
	if stations.has(target_id):
		return str(stations[target_id].get("owner", ""))
	return str(nodes.get(target_id, {}).get("owner", ""))

## Takes still missing from a node, after what has grown back since
func _taken(node_id: String) -> int:
	var st = node_state.get(node_id)
	if st == null:
		return 0
	var regrow = maxi(1, int(nodes.get(node_id, {}).get("regrow_minutes", 1440)))
	var back = floori((_now() - int(st.since)) / float(regrow))
	if back > 0:
		st.taken = maxi(0, int(st.taken) - back)
		st.since = int(st.since) + back * regrow
	if int(st.taken) <= 0:
		node_state.erase(node_id)
		return 0
	return int(st.taken)

## "" when the player is where the thing is (or nobody knows where the player is)
func _not_here(def: Dictionary) -> String:
	var loc = str(def.get("location", ""))
	var here = _here()
	if loc == "" or here == "" or here == "none" or here == loc:
		return ""
	return "that is at %s" % _place_name(loc)

func _here() -> String:
	if player_location_override != "":
		return player_location_override
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe and str(pe.get("player_location_override")) != "":
		return str(pe.player_location_override)
	var sm = get_node_or_null("/root/SceneManager")
	return str(sm.get_current_location_id()) if sm and sm.has_method("get_current_location_id") else ""

func _now() -> int:
	var ws = get_node_or_null("/root/WorldState")
	return ws.get_game_minutes() if ws else 0

func _advance(minutes: int, reason: String) -> void:
	var ws = get_node_or_null("/root/WorldState")
	if ws and minutes > 0:
		ws.advance_time(minutes, reason)

func _flag(flag: String) -> bool:
	var ws = get_node_or_null("/root/WorldState")
	return ws != null and ws.get_world_flag(flag)

func _player_name() -> String:
	var director = get_node_or_null("/root/StorylineDirector")
	return str(director.get_player_name()) if director and director.has_method("get_player_name") else "the stranger"

func _npc_name(key: String) -> String:
	var reg = get_node_or_null("/root/WorldRegistry")
	if reg and reg.has_method("has_npc") and reg.has_npc(key):
		return str(reg.get_npc_name(key))
	return key.capitalize()

func _place_name(location: String) -> String:
	return location.replace("_", " ").capitalize()

func _owned_place(n: Dictionary) -> String:
	var owner = str(n.get("owner", ""))
	var name = _lower_first(str(n.get("name", "")))
	return "%s (%s's)" % [name, _npc_name(owner)] if owner != "" else name

func _kind_name(kind: String) -> String:
	return str(station_kinds.get(kind, {}).get("name", kind.replace("_", " "))).to_lower()

func _item_kind(item_id: String) -> String:
	var inv = _inventory()
	if inv and inv.has_method("get_definition"):
		var def = inv.get_definition(item_id)
		if def is Dictionary and def.has("kind"):
			return str(def.kind)
	return str(_item_defs.get(item_id, {}).get("kind", ""))

func _item_name(item_id: String) -> String:
	var def: Dictionary = _item_defs.get(item_id, {})
	return str(def.get("name", item_id.replace("_", " "))).to_lower()

func _amount(n: int, item_id: String) -> String:
	return "%d %s" % [n, _item_name(item_id)] if n > 1 else _item_name(item_id)

func _made_verb(r: Dictionary) -> String:
	match str(r.get("station", "")):
		"forge":
			return "smelted" if str(r.get("output", {}).get("id", "")) == "steel_bar" else "forged"
		"loom":
			return "wove"
		"campfire":
			return "burned"
	return "made"

func _quality_word(q: int) -> String:
	if q >= 90:
		return "masterwork"
	if q >= FEAT_QUALITY:
		return "fine"
	if q >= 60:
		return "good"
	if q >= 30:
		return "serviceable"
	return "rough"

func _with_article(adjective: String, noun: String) -> String:
	var phrase = (adjective + " " + noun).strip_edges() if adjective != "" else noun
	if adjective == "" and noun.ends_with("s"):
		return phrase   # "arrows", not "an arrows"
	return ("an " if phrase.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + phrase

func _lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if s != "" else s

func _upper_first(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "leave": "", "trespass": false}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

## Names from agent 2's item definitions, whatever the file shape ({items: [...]}, [...] or {id: def})
func _load_item_defs() -> void:
	_item_defs.clear()
	var dir = DirAccess.open(ITEMS_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_DIR + "/" + file))
		var list: Array = []
		if data is Array:
			list = data
		elif data is Dictionary and data.get("items") is Array:
			list = data.items
		elif data is Dictionary:
			for k in data:
				if data[k] is Dictionary:
					list.append(data[k].merged({"id": k}))
		for def in list:
			if def is Dictionary and str(def.get("id", "")) != "":
				_item_defs[str(def.id)] = def

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {"known": known.duplicate(true), "node_state": node_state.duplicate(true), "leave": leave.duplicate(true),
		"commissions": commissions.duplicate(true), "built": built.duplicate(true), "counter": counter}

func load_from_dict(data: Dictionary) -> void:
	reset()
	known = data.get("known", {}).duplicate(true) if data.get("known") is Dictionary else {}
	leave = data.get("leave", {}).duplicate(true) if data.get("leave") is Dictionary else {}
	commissions = data.get("commissions", {}).duplicate(true) if data.get("commissions") is Dictionary else {}
	built = data.get("built", {}).duplicate(true) if data.get("built") is Dictionary else {}
	counter = int(data.get("counter", 0))
	if data.get("node_state") is Dictionary:
		for id in data.node_state:
			var st = data.node_state[id]
			if st is Dictionary:
				node_state[str(id)] = {"taken": int(st.get("taken", 0)), "since": int(st.get("since", 0))}
	for id in built:
		stations[str(id)] = built[id]

func reset() -> void:
	for id in built:
		stations.erase(id)
	known.clear()
	node_state.clear()
	leave.clear()
	commissions.clear()
	built.clear()
	counter = 0
