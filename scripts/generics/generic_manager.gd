extends Node
# GenericManager - The generic NPC system (docs/WORLD_SCHEMA.md §9), owned by DynamicNPCRegistry
# - archetypes + names + population -> seeded instances (gen_<archetype>_<n>), each a rolled soul
#   registered with the StorylineDirector as tier `generic`
# - every interaction layers on the instance (learned facts, moments, nudges, gossip, feelings)
# - relationship decay per game day apart for EVERY NPC, mains included (RelationshipLedger)
# - significance 0-100; promotion (sustained, generated SOUL.md + Life arc, own chroma collection)
#   and demotion (residue, tier generic again) with hysteresis; the 19 mains are anchored
# Calls only the arcs-engine API StorylineDirector.register_soul / unregister_soul / set_soul_tier,
# guarded with has_method so a missing or fake Director is fine

signal instance_created(id: String)
signal layers_changed(id: String)
signal generic_promoted(id: String)
signal generic_demoted(id: String)

const Archetype = preload("res://scripts/generics/archetype.gd")
const GenericInstance = preload("res://scripts/generics/generic_instance.gd")
const SoulBuilder = preload("res://scripts/generics/generic_soul_builder.gd")
const RelationshipLedger = preload("res://scripts/generics/relationship_ledger.gd")

const DEFAULT_ARCHETYPE_DIR = "res://resources/generics/archetypes"
const DEFAULT_NAMES_PATH = "res://resources/generics/names.json"
const DEFAULT_POPULATION_PATH = "res://resources/generics/population.json"
const DEFAULT_SOULS_DIR = "user://souls"
const WORLD_PATH = "res://resources/world/world.json"
const DEFAULT_WORLD_SEED = 7919
const GOSSIP_REGION = "western_valley"
const DEFAULT_TIERS = {"promote_at": 60, "promote_rounds": 3, "demote_at": 30, "demote_days_apart": 7,
	"repromote_bonus": 10, "repromote_floor": 40}
const FALLBACK_GIVEN = ["Alda", "Bren", "Cerys", "Dunstan", "Edda", "Fenn", "Gilda", "Hob", "Isolde", "Jory", "Kestrel", "Lisbet", "Merrow", "Nell", "Osric", "Perrin"]
const FALLBACK_FAMILY = ["Ashby", "Brook", "Cotter", "Dale", "Fletcher", "Hale", "Marsh", "Reed", "Thatcher", "Wold"]

## Moments by interaction type: [text, importance, trait nudges, want nudge (+1 strongest / "safety")]
const MOMENTS = {
	"gift_given": ["The stranger gave me a gift", 7, {"agreeableness": 2}, 1],
	"gift_received": ["The stranger gave me a gift", 7, {"agreeableness": 2}, 1],
	"threat_made": ["The stranger threatened me", 8, {"neuroticism": 3, "agreeableness": -2}, "safety"],
	"secret_shared": ["The stranger trusted me with a secret", 7, {"openness": 2}, 0],
	"emotional_support": ["The stranger comforted me when I needed it", 6, {"agreeableness": 1, "neuroticism": -1}, 1],
	"life_saved": ["The stranger saved my life", 10, {"agreeableness": 3, "neuroticism": -2}, 1],
	"betrayal": ["The stranger broke faith with me", 9, {"agreeableness": -3, "neuroticism": 2}, "safety"],
	"romantic_gesture": ["The stranger flirted with me", 5, {"extraversion": 1}, 0],
	"romance_confession": ["The stranger confessed feelings for me", 8, {"openness": 1}, 0],
	"helped": ["The stranger helped me without being asked", 7, {"agreeableness": 2}, 1],
	"unrequested_help": ["The stranger helped me without being asked", 7, {"agreeableness": 2}, 1],
	"quest_related": ["The stranger asked me about the troubles here", 4, {}, 0],
	"witnessed_cruelty": ["I saw the stranger be cruel", 8, {"neuroticism": 2}, "safety"],
	"witnessed_kindness": ["I saw the stranger be kind", 6, {"agreeableness": 1}, 0],
}
const SAFETY_WORDS = ["safe", "protect", "keep", "survive", "hide", "guard", "shelter", "home"]
const PALETTE = [Color(1, 1, 1), Color(0.92, 0.86, 0.78), Color(0.82, 0.88, 0.92), Color(0.9, 0.82, 0.86), Color(0.84, 0.9, 0.8), Color(0.95, 0.92, 0.8)]

## Sprites by archetype keyword (pregenerated characters, docs: generics reuse existing sprites)
const SPRITE_KEYWORDS = [
	[["smith", "miner", "labourer", "laborer", "dock", "porter", "woodcutter", "quarry", "mason", "carter"], "bjorn_blacksmith"],
	[["merchant", "trader", "pedlar", "peddler", "shopkeep", "clerk", "factor", "baker", "chandler", "fence"], "gregor_merchant"],
	[["woman", "wife", "widow", "maid", "alewife", "washer", "healer", "nun", "sister", "matron", "barmaid", "weaver", "midwife", "herbwife"], "mira_tavern_keeper"],
	[["girl", "child", "urchin", "apprentice", "novice", "page", "youth", "acolyte"], "elena_daughter_001"],
]
const DEFAULT_SPRITE = "villager_male"

var archetype_dir: String = DEFAULT_ARCHETYPE_DIR
var names_path: String = DEFAULT_NAMES_PATH
var population_path: String = DEFAULT_POPULATION_PATH
var souls_dir: String = DEFAULT_SOULS_DIR
var world_seed: int = DEFAULT_WORLD_SEED
var auto_boot: bool = true           # false: tests load fixtures themselves
var use_chromadb: bool = true        # promoted generics get a real collection when the game uses ChromaDB
var write_souls_in_character: bool = true  # Claude mode only; deterministic text otherwise
var soul_writer: Callable = Callable()     # optional (text, instance) -> String; must keep machine lines
var director_override: Node = null   # tests hand in a fake Director
var test_now: int = -1               # tests pin the clock (minutes); -1 = WorldState

var archetypes: Dictionary = {}      # id -> Archetype (valid only)
var archetype_errors: Dictionary = {}  # file -> Array of errors
var name_pools: Dictionary = {}      # region -> {"given": [], "family": []}
var population: Array = []           # [{location, archetype, count, hours}]
var instances: Dictionary = {}       # id -> GenericInstance
var instance_order: Array = []
var ledger = RelationshipLedger.new()
var tiers: Dictionary = DEFAULT_TIERS.duplicate()
var log_lines: Array = []            # last decisions (promotions, demotions, refusals) for debugging

var _registered_names: Dictionary = {}  # instance id -> registered display name
var _presence_cache: Dictionary = {}    # instance id -> present (time-of-day changes refresh the scene)
var _director_connected: bool = false

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.time_advanced.connect(_on_time_advanced)
		bus.npc_relationship_changed.connect(_on_relationship_changed)
	var propagator = get_node_or_null("/root/EventPropagator")
	if propagator and propagator.has_signal("news_spread"):
		propagator.news_spread.connect(on_news_spread)
	load_config()
	if auto_boot:
		boot()
	call_deferred("_connect_director")

## Fresh content + either the saved state (WorldState.generics_state) or a new population
func boot() -> void:
	load_content()
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and "generics_state" in world_state and not world_state.generics_state.is_empty():
		load_from_dict(world_state.generics_state)
	else:
		populate()
	print("[Generics] %d archetypes, %d instances (%d promoted)" % [archetypes.size(), instances.size(), get_promoted_ids().size()])

func _connect_director() -> void:
	var director = _director()
	if director == null:
		return
	if not _director_connected and director.has_signal("round_completed"):
		director.round_completed.connect(_on_round_completed)
		_director_connected = true
	register_all_souls()

# =============================================================================
# CONFIG AND CONTENT
# =============================================================================

## world.json relationship_decay and tiers (WorldRegistry when loaded, else the file)
func load_config(world: Dictionary = {}) -> void:
	if world.is_empty():
		var registry = get_node_or_null("/root/WorldRegistry")
		if registry and "data" in registry and registry.data is Dictionary and not registry.data.is_empty():
			world = registry.data
		else:
			var parsed = _read_json(WORLD_PATH)
			world = parsed if parsed is Dictionary else {}
	ledger.configure(world.get("relationship_decay", {}))
	var t: Dictionary = world.get("tiers", {})
	for key in DEFAULT_TIERS:
		tiers[key] = t.get(key, DEFAULT_TIERS[key])

## Load archetypes, names and population ("" = defaults under res://resources/generics)
func load_content(arch_dir: String = "", names_file: String = "", population_file: String = "") -> void:
	if arch_dir != "":
		archetype_dir = arch_dir
	if names_file != "":
		names_path = names_file
	if population_file != "":
		population_path = population_file
	archetypes.clear()
	archetype_errors.clear()
	var dir = DirAccess.open(archetype_dir)
	if dir:
		var files: Array = []
		for f in dir.get_files():
			if f.ends_with(".md"):
				files.append(f)
		files.sort()
		for f in files:
			var arch = Archetype.load_from_file("%s/%s" % [archetype_dir, f])
			if arch == null:
				continue
			if not arch.is_valid():
				archetype_errors[f] = arch.errors
				push_warning("[Generics] Skipping archetype %s: %s" % [f, "; ".join(arch.errors)])
				continue
			if archetypes.has(arch.id):
				archetype_errors[f] = ["duplicate archetype id '%s'" % arch.id]
				continue
			archetypes[arch.id] = arch
	name_pools = _parse_names(_read_json(names_path))
	population = _parse_population(_read_json(population_path))

func _parse_names(data) -> Dictionary:
	var pools = {}
	if not data is Dictionary:
		return pools
	var regions: Dictionary = data.get("regions", data) if data.get("regions") is Dictionary else data
	for region in regions:
		var entry = regions[region]
		var given: Array = []
		var family: Array = []
		if entry is Array:
			given = entry.map(func(n): return str(n))
		elif entry is Dictionary:
			for key in ["given", "first", "names", "male", "female", "forenames"]:
				if entry.get(key) is Array:
					given.append_array(entry[key].map(func(n): return str(n)))
			for key in ["family", "last", "surnames", "bynames", "epithets"]:
				if entry.get(key) is Array:
					family.append_array(entry[key].map(func(n): return str(n)))
		if not given.is_empty():
			pools[str(region)] = {"given": given, "family": family}
	return pools

## population.json: {location: [{archetype, count}]}, {"locations": {...}}, or [{location, archetype, count}]
func _parse_population(data) -> Array:
	var out: Array = []
	if data is Dictionary and data.get("locations") is Dictionary:
		data = data.locations
	elif data is Dictionary and data.get("population") != null:
		data = data.population
	if data is Dictionary:
		var locs = data.keys()
		for loc in locs:
			if str(loc).begins_with("_") or not data[loc] is Array:
				continue
			for entry in data[loc]:
				if entry is Dictionary:
					out.append(_population_entry(str(loc), entry))
	elif data is Array:
		for entry in data:
			if entry is Dictionary and entry.has("location"):
				out.append(_population_entry(str(entry.location), entry))
	return out

func _population_entry(location: String, entry: Dictionary) -> Dictionary:
	return {"location": location, "archetype": str(entry.get("archetype", "")), "count": maxi(int(entry.get("count", 1)), 0),
		"hours": entry.get("hours").map(func(h): return int(h)) if entry.get("hours") is Array else []}

# =============================================================================
# INSTANCES
# =============================================================================

## Create every instance population.json asks for that does not exist yet (deterministic)
func populate() -> Array:
	var created: Array = []
	var counters: Dictionary = {}
	var unknown: Dictionary = {}
	for entry in population:
		var arch = archetypes.get(entry.archetype)
		if arch == null:
			unknown[entry.archetype] = true
			continue
		for i in entry.count:
			var n = int(counters.get(arch.id, 0)) + 1
			counters[arch.id] = n
			var id = "gen_%s_%d" % [arch.id, n]
			if instances.has(id):
				continue
			created.append(create_instance(arch, entry.location, n, entry.get("hours", [])).id)
	if not unknown.is_empty():
		push_warning("[Generics] population names unloaded archetype(s): %s" % ", ".join(unknown.keys()))
	return created

## Roll one instance. The seed (world seed + id) fixes its name, want weights, traits and voice variant
func create_instance(arch, location: String, n: int, hours: Array = []):
	var inst = GenericInstance.new()
	inst.id = "gen_%s_%d" % [arch.id, n]
	inst.archetype_id = arch.id
	inst.seed_value = seed_for(inst.id)
	inst.home = location
	inst.region = _region_of(location)
	inst.hours = hours.duplicate()
	var rng = RandomNumberGenerator.new()
	rng.seed = inst.seed_value
	inst.name = _roll_name(inst.region, rng)
	for want_id in arch.want_order:
		inst.rolled_wants[want_id] = rng.randi_range(int(arch.wants[want_id].lo), int(arch.wants[want_id].hi))
	for t in GenericInstance.TRAITS:
		inst.rolled_traits[t] = rng.randi_range(-40, 40)
	inst.voice_variant = rng.randi_range(0, maxi(arch.voice_variants.size() - 1, 0))
	inst.soul_text = SoulBuilder.build_rolled_soul(inst, arch, _ctx(inst))
	inst.note_history("created", now_minutes())
	instances[inst.id] = inst
	instance_order.append(inst.id)
	_record_location(inst)
	_register_name(inst)
	_register_soul(inst)
	instance_created.emit(inst.id)
	return inst

func seed_for(id: String) -> int:
	return hash("%d|%s" % [world_seed, id]) & 0x7fffffff

func _roll_name(region: String, rng: RandomNumberGenerator) -> String:
	var pool: Dictionary = name_pools.get(region, name_pools.get("*", name_pools.get("default", {})))
	if pool.is_empty() and not name_pools.is_empty():
		pool = name_pools[name_pools.keys()[0]]
	var given: Array = pool.get("given", FALLBACK_GIVEN)
	var family: Array = pool.get("family", [] if pool.has("given") else FALLBACK_FAMILY)
	var taken = _taken_names()
	var picked = ""
	for attempt in 24:
		picked = str(given[rng.randi_range(0, given.size() - 1)])
		if not family.is_empty() and (" " not in picked):
			picked += " " + str(family[rng.randi_range(0, family.size() - 1)])
		if not taken.has(picked.to_lower()):
			return picked
	return "%s %d" % [picked, instances.size() + 1]

func _taken_names() -> Dictionary:
	var taken = {}
	for id in instances:
		taken[instances[id].name.to_lower()] = true
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry:
		for key in registry.get_npc_keys():
			taken[registry.get_npc_name(key).to_lower()] = true
	return taken

## WorldState npc_states holds every generic's location too, so travel (move_npc, start_npc_travel),
## away status and the Director's personal turns treat generics like anyone else. A location
## already recorded (a save, a journey) is kept
func _record_location(inst) -> void:
	var world_state = get_node_or_null("/root/WorldState")
	if world_state == null or inst.home == "":
		return
	if str(world_state.npc_states.get(inst.id, {}).get("location", "")) == "":
		world_state.set_npc_location(inst.id, inst.get_location())

func get_instance(id: String):
	return instances.get(id)

func is_generic(npc_id: String) -> bool:
	return instances.has(npc_id)

func get_archetype(id: String):
	return archetypes.get(id)

func get_ids() -> Array:
	return instance_order.duplicate()

func get_promoted_ids() -> Array:
	return instance_order.filter(func(id): return instances[id].tier == "promoted")

## Main (authored, world.json) NPCs are anchored: they decay but never demote
func is_anchored(npc_id: String) -> bool:
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry != null and registry.get_npc_key(npc_id) != "" and not instances.has(npc_id)

## Where an instance is: WorldState's record (travel, move_npc), else its own location/home
func get_location(id: String) -> String:
	var inst = instances.get(id)
	if inst == null:
		return ""
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and world_state.npc_states.has(id) and str(world_state.npc_states[id].get("location", "")) != "":
		return str(world_state.npc_states[id].location)
	return inst.get_location()

## Present at a location now: not travelling, not dead, inside its hours
func is_present(id: String, location_id: String) -> bool:
	var inst = instances.get(id)
	if inst == null or get_location(id) != location_id:
		return false
	var world_state = get_node_or_null("/root/WorldState")
	if world_state:
		if world_state.is_npc_travelling(id) or not world_state.is_npc_alive(id):
			return false
	return _within_hours(inst)

func _within_hours(inst) -> bool:
	if inst.hours.size() < 2:
		return true
	var hour = floori((now_minutes() % 1440) / 60.0)
	var start = int(inst.hours[0])
	var end = int(inst.hours[1])
	return (hour >= start and hour < end) if start <= end else (hour >= start or hour < end)

## Instances present at a location (spawner)
func get_present_ids(location_id: String) -> Array:
	return instance_order.filter(func(id): return is_present(id, location_id))

func get_ids_at(location_id: String) -> Array:
	return instance_order.filter(func(id): return location_id == "" or get_location(id) == location_id)

func sprite_for(id: String) -> String:
	var inst = instances.get(id)
	var arch = archetypes.get(inst.archetype_id) if inst else null
	if arch and arch.sprite != "":
		return arch.sprite
	var probe = ((arch.id + " " + arch.title) if arch else (inst.archetype_id if inst else "")).to_lower()
	for row in SPRITE_KEYWORDS:
		for word in row[0]:
			if word in probe:
				return row[1]
	return DEFAULT_SPRITE

func tint_for(id: String) -> Color:
	var inst = instances.get(id)
	return PALETTE[posmod(inst.seed_value if inst else 0, PALETTE.size())]

# =============================================================================
# NAMES ARE CANON (WorldEvents memory validation)
# =============================================================================

func _register_name(inst) -> void:
	var world_events = get_node_or_null("/root/WorldEvents")
	if world_events and world_events.has_method("register_npc_name"):
		world_events.register_npc_name(inst.name, inst.id)
	_registered_names[inst.id] = inst.name

func _unregister_names() -> void:
	var world_events = get_node_or_null("/root/WorldEvents")
	if world_events and world_events.has_method("unregister_npc_names_from"):
		for id in _registered_names:
			world_events.unregister_npc_names_from(id)
	_registered_names.clear()

# =============================================================================
# DIRECTOR (arcs-engine API: register_soul / unregister_soul / set_soul_tier)
# =============================================================================

func _director() -> Node:
	if director_override != null:
		return director_override
	return get_node_or_null("/root/StorylineDirector") if is_inside_tree() else null

func _register_soul(inst) -> bool:
	var director = _director()
	if director == null or not director.has_method("register_soul"):
		return false
	var ok = director.register_soul(inst.id, inst.soul_text, {"tier": inst.tier, "npc_id": inst.id, "home": inst.home})
	if not ok:
		_log("register_soul refused %s (tier %s)" % [inst.id, inst.tier])
	return bool(ok)

func _set_tier(inst) -> void:
	var director = _director()
	if director == null:
		return
	# The soul text changes with the tier (generated Life on promotion, residue on demotion)
	if director.has_method("register_soul"):
		if not _register_soul(inst) and director.has_method("set_soul_tier"):
			director.set_soul_tier(inst.id, inst.tier)
	elif director.has_method("set_soul_tier"):
		director.set_soul_tier(inst.id, inst.tier)

## (Re)register every instance soul, e.g. after the Director reloaded its content
func register_all_souls() -> int:
	var count = 0
	for id in instance_order:
		if _register_soul(instances[id]):
			count += 1
	return count

func _director_knows(id: String) -> bool:
	var director = _director()
	return director != null and director.has_method("get_soul") and director.get_soul(id) != null

# =============================================================================
# LAYERS (every interaction a generic has layers on top of its generic base)
# =============================================================================

## An analysed interaction with the player (called by GenericNPC after BaseNPC records it)
## context: description, player_message, topics, importance ... (BaseNPC.record_interaction's)
func record_interaction(npc_id: String, interaction_type: String, context: Dictionary = {}) -> void:
	var inst = instances.get(npc_id)
	if inst == null:
		return
	var now = now_minutes()
	var arch = archetypes.get(inst.archetype_id)
	inst.interactions += 1
	ledger.note_contact(npc_id, now)
	var talked = inst.add_layer("acquaintance", "You and the stranger have talked %s." % _times(inst.interactions),
		mini(2 + floori(inst.interactions / 3.0), 5), now, {"tag": "acquaintance"})
	talked.text = "You and the stranger have talked %s." % _times(inst.interactions)
	var moment = MOMENTS.get(interaction_type)
	if moment:
		var text = str(moment[0])
		var gist = _gist(str(context.get("player_message", "")))
		if gist != "":
			text += " (\"%s\")" % gist
		inst.add_layer("moment", text + ".", int(moment[1]), now, {"tag": "moment:" + interaction_type})
		for t in moment[2]:
			inst.nudge_trait(t, int(moment[2][t]))
		_nudge_want_for(inst, arch, moment[3])
	elif interaction_type == "storyline_effect":
		pass
	_after_change(inst)

## What the generic learned about the player (analysis.learned_about_player)
func record_learned(npc_id: String, info: Dictionary) -> void:
	var inst = instances.get(npc_id)
	if inst == null or info == null or info.is_empty():
		return
	var now = now_minutes()
	var player_name = info.get("name")
	if player_name is String and player_name.strip_edges() != "":
		inst.add_layer("learned", "The stranger's name is %s." % player_name.strip_edges(), 10, now, {"pinned": true, "tag": "learned:name"})
	var occupation = info.get("occupation")
	if occupation is String and occupation.strip_edges() != "":
		inst.add_layer("learned", "The stranger is a %s." % occupation.strip_edges(), 8, now, {"tag": "learned:occupation"})
	var origin = info.get("origin")
	if origin is String and origin.strip_edges() != "":
		inst.add_layer("learned", "The stranger comes from %s." % origin.strip_edges(), 7, now, {"tag": "learned:origin"})
	var facts = info.get("notable_facts", [])
	if facts is Array:
		for fact in facts:
			if fact is String and fact.strip_edges() != "":
				inst.add_layer("learned", "About the stranger: %s" % fact.strip_edges(), 6, now)
	_after_change(inst)

func _nudge_want_for(inst, arch, rule) -> void:
	if arch == null:
		return
	var order = inst.wants_by_weight(arch.want_order)
	if order.is_empty():
		return
	if rule is String and rule == "safety":
		for want_id in arch.want_order:
			var text = (want_id + " " + str(arch.wants[want_id].text)).to_lower()
			for word in SAFETY_WORDS:
				if word in text:
					inst.nudge_want(want_id, 1)
					return
		inst.nudge_want(order[0], -1)  # fear shrinks hope
	elif (rule is int or rule is float) and int(rule) != 0:
		inst.nudge_want(order[0], int(rule))

func _gist(message: String) -> String:
	var g = message.strip_edges().replace("\"", "'").replace("\n", " ")
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry and registry.has_method("sanitize_forbidden"):
		g = registry.sanitize_forbidden(g)
	return g if g.length() <= 40 else g.substr(0, 37) + "..."

func _times(n: int) -> String:
	return "once" if n == 1 else ("twice" if n == 2 else "%d times" % n)

## News reached NPCs (EventPropagator.news_spread): generics in reach hear it too and can repeat it
## how: "witnessed" (keys empty, location = where it happened) or "gossip" (keys, region)
func on_news_spread(flag_name: String, text: String, how: String, keys: Array, region: String, location: String) -> Array:
	var reached: Array = []
	var now = now_minutes()
	for id in instance_order:
		var inst = instances[id]
		var hears = false
		if how == "witnessed":
			hears = location != "" and is_present(id, location)
		elif "*" in keys:
			hears = inst.region == (region if region != "" else GOSSIP_REGION)
		else:
			hears = id in keys or _shares_location_with(id, keys)
		if not hears or inst.has_layer_tag("news:" + flag_name):
			continue
		if how == "witnessed":
			inst.witnessed += 1
			inst.add_layer("witnessed", "You saw it yourself: %s" % text, 7, now, {"tag": "news:" + flag_name, "flag": flag_name})
		else:
			inst.gossip_heard += 1
			inst.add_layer("gossip", "Word going round (you may pass it on): %s" % text, 5, now, {"tag": "news:" + flag_name, "flag": flag_name})
		reached.append(id)
		_after_change(inst, false)
	return reached

func _shares_location_with(id: String, keys: Array) -> bool:
	var here = get_location(id)
	var registry = get_node_or_null("/root/WorldRegistry")
	var world_state = get_node_or_null("/root/WorldState")
	for key in keys:
		var npc_id = registry.get_npc_id(str(key)) if registry else ""
		var where = ""
		if npc_id != "" and world_state:
			where = world_state.get_npc_location(npc_id)
		elif instances.has(str(key)):
			where = get_location(str(key))
		if where != "" and where == here:
			return true
	return false

func _after_change(inst, refresh_node: bool = true) -> void:
	inst.significance = compute_significance(inst)
	layers_changed.emit(inst.id)
	if refresh_node:
		for node in _loaded_nodes(inst.id):
			if node.has_method("refresh_from_instance"):
				node.refresh_from_instance()

# =============================================================================
# PROMPT (archetype base + seed + the most important and recent layers; compact by design)
# =============================================================================

## Block for ContextBuilder. include_soul = false when the Director already injects the soul
## (essence, wants, voice); the seed line and layers are always added
func get_prompt_block(npc_id: String, include_soul: bool = true) -> String:
	var inst = instances.get(npc_id)
	if inst == null:
		return ""
	var arch = archetypes.get(inst.archetype_id)
	var now = now_minutes()
	var block = ""
	if include_soul and arch:
		var slots = SoulBuilder.slots_for(inst, _ctx(inst))
		block += "## WHO YOU ARE\n%s\n" % _flat(Archetype.fill_slots(arch.essence, slots), 280)
		var wants = inst.wants_by_weight(arch.want_order).slice(0, 3)
		if not wants.is_empty():
			block += "What you want most: %s\n" % "; ".join(wants.map(func(w): return "%s (%d/10)" % [_flat(Archetype.fill_slots(str(arch.wants[w].text), slots), 60), inst.get_want_weight(w)]))
		var voice = SoulBuilder.voice_for(inst, arch)
		if voice != "":
			block += "Your voice: %s\n" % _flat(voice, 160)
	var ctx = _ctx(inst)
	block += "You are %s, %s of %s%s. Ordinary folk: you know your own life and what you have heard, nothing more.\n" % [
		inst.name, _article(arch.title.to_lower() if arch else inst.archetype_id), ctx.home_name,
		"" if inst.tier == "generic" else " (the stranger matters to you now)"]
	var mood = _trait_mood(inst)
	if mood != "":
		block += "Lately: %s\n" % mood
	var top = inst.top_layers(GenericInstance.PROMPT_LAYERS, now)
	if not top.is_empty():
		block += "## WHAT HAS HAPPENED TO YOU (most important first)\n"
		for layer in top:
			block += "- %s\n" % layer.text
	return block + "\n"

## Approximate tokens (4 characters per token, the ContextBuilder convention)
static func estimate_tokens(text: String) -> int:
	return ceili(text.length() / 4.0)

func _trait_mood(inst) -> String:
	var parts: Array = []
	if int(inst.trait_nudges.get("neuroticism", 0)) >= 3:
		parts.append("on edge")
	if int(inst.trait_nudges.get("agreeableness", 0)) >= 3:
		parts.append("warmer than usual")
	elif int(inst.trait_nudges.get("agreeableness", 0)) <= -3:
		parts.append("guarded and short")
	if int(inst.trait_nudges.get("openness", 0)) >= 2:
		parts.append("more willing to confide")
	return ", ".join(parts)

func _article(word: String) -> String:
	return ("an " if word.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + word

func _flat(text: String, max_chars: int) -> String:
	var flat = text.replace("\n\n", " ").replace("\n", " ").strip_edges()
	return flat if flat.length() <= max_chars else flat.substr(0, max_chars - 3) + "..."

## Runtime NPCPersonality so BaseNPC's conversation flow works for a generic
func build_personality(npc_id: String) -> Resource:
	var inst = instances.get(npc_id)
	var p = NPCPersonality.new()
	if inst == null:
		return p
	var arch = archetypes.get(inst.archetype_id)
	var ctx = _ctx(inst)
	p.npc_id = inst.id
	p.display_name = inst.name
	p.core_identity = "%s, %s of %s in %s." % [inst.name, _article(arch.title.to_lower() if arch else "local"), ctx.home_name, ctx.region_name]
	var anchors: Array[String] = ["Your name is %s." % inst.name, "You live at %s." % ctx.home_name]
	p.identity_anchors = anchors
	p.trait_openness = inst.get_trait("openness")
	p.trait_conscientiousness = inst.get_trait("conscientiousness")
	p.trait_extraversion = inst.get_trait("extraversion")
	p.trait_agreeableness = inst.get_trait("agreeableness")
	p.trait_neuroticism = inst.get_trait("neuroticism")
	p.is_fearful = inst.get_trait("neuroticism") > 30
	p.is_trusting = inst.get_trait("agreeableness") > 30
	p.is_humorous = inst.get_trait("extraversion") > 30
	if arch:
		var fears: Array[String] = []
		for f in arch.fears.slice(0, 3):
			fears.append(str(f))
		p.fears = fears
	p.vocabulary_level = "simple"
	var styles = ["casual", "warm", "nervous", "cold", "confident"]
	p.speaking_style = styles[posmod(inst.seed_value + inst.voice_variant, styles.size())]
	p.default_player_address = "stranger"
	return p

# =============================================================================
# RELATIONSHIPS FOR EVERY NPC (ledger + decay)
# =============================================================================

## BaseNPC.initialize: the ledger's feelings become the node's (or the node seeds the ledger)
func apply_to_npc(npc: Node) -> void:
	var npc_id = str(npc.get("npc_id"))
	if npc_id == "":
		return
	if ledger.has_entry(npc_id):
		_push_dims(npc, ledger.get_dims(npc_id))
	else:
		ledger.set_dims(npc_id, _node_dims(npc), now_minutes())

## The player spoke with this NPC (BaseNPC.start_conversation)
func note_contact(npc_id: String) -> void:
	if npc_id == "":
		return
	ledger.note_contact(npc_id, now_minutes())
	var inst = instances.get(npc_id)
	if inst:
		inst.significance = compute_significance(inst)

## BaseNPC.end_conversation: copy the node's feelings into the ledger
func sync_from_npc(npc: Node) -> void:
	var npc_id = str(npc.get("npc_id"))
	if npc_id != "":
		ledger.set_dims(npc_id, _node_dims(npc), now_minutes())
		if instances.has(npc_id):
			instances[npc_id].significance = compute_significance(instances[npc_id])

func _on_relationship_changed(event: Dictionary) -> void:
	var npc_id = str(event.get("npc_id", ""))
	if npc_id == "" or str(event.get("interaction_type", "")) == "decay":
		return
	var dims = event.get("new_dimensions", {})
	if dims is Dictionary and not dims.is_empty():
		ledger.set_dims(npc_id, dims, now_minutes())
	if instances.has(npc_id):
		instances[npc_id].significance = compute_significance(instances[npc_id])

func _node_dims(npc: Node) -> Dictionary:
	var dims = {}
	for dim in RelationshipLedger.DIMENSIONS:
		var v = npc.get("relationship_" + dim)
		dims[dim] = float(v) if v != null else 0.0
	return dims

func _push_dims(npc: Node, dims: Dictionary) -> void:
	for dim in dims:
		if ("relationship_" + dim) in npc:
			npc.set("relationship_" + dim, float(dims[dim]))
	if npc.has_method("_update_legacy_relationship_status"):
		npc._update_legacy_relationship_status()

## Decay every NPC for the whole days apart not yet applied; loaded NPCs not in conversation follow
func process_time() -> Dictionary:
	var now = now_minutes()
	var changed = ledger.decay(now)
	for npc_id in changed:
		for node in _loaded_nodes(npc_id):
			if not node.get("is_in_conversation"):
				_push_dims(node, ledger.get_dims(npc_id))
	for id in instance_order:
		instances[id].significance = compute_significance(instances[id])
	_check_demotions()
	_refresh_presence()
	return changed

## Debug/tests: n more game days apart for everyone (the clock itself does not move)
func simulate_days_apart(days: int) -> Dictionary:
	for npc_id in ledger.entries:
		ledger.entries[npc_id].last_contact = int(ledger.entries[npc_id].last_contact) - days * RelationshipLedger.MINUTES_PER_DAY
	for id in instance_order:
		for layer in instances[id].layers:
			layer.minute = int(layer.minute) - days * RelationshipLedger.MINUTES_PER_DAY
	return process_time()

func _on_time_advanced(_minutes: int, _total: int, _reason: String) -> void:
	if test_now >= 0:
		return  # tests drive the clock themselves
	process_time()

func _refresh_presence() -> void:
	var changed = false
	for id in instance_order:
		if instances[id].hours.size() < 2:
			continue
		var present = _within_hours(instances[id])
		if _presence_cache.get(id) != present:
			changed = changed or _presence_cache.has(id)
			_presence_cache[id] = present
	if changed:
		var scene_manager = get_node_or_null("/root/SceneManager")
		if scene_manager and scene_manager.has_method("refresh_npcs"):
			scene_manager.refresh_npcs()

# =============================================================================
# SIGNIFICANCE (0-100)
# =============================================================================

## relationship (0-40) + layers (0-30) + story involvement (0-15) + recency (0-15)
func compute_significance(inst) -> float:
	return get_significance_parts(inst).total

func get_significance_parts(inst) -> Dictionary:
	var now = now_minutes()
	var relationship = 40.0 * min(ledger.strength(inst.id) / 50.0, 1.0)
	var layer_part = 30.0 * min(inst.layer_weight(now) / 40.0, 1.0)
	var story = min(3.0 * inst.witnessed + 2.0 * inst.gossip_heard, 15.0)
	var recency = 15.0 * exp(-ledger.days_apart(inst.id, now) / 4.0) if ledger.is_met(inst.id) else 0.0
	var total = clamp(relationship + layer_part + story + recency, 0.0, 100.0)
	return {"relationship": relationship, "layers": layer_part, "story": story, "recency": recency, "total": total}

## The bar a generic must hold to be promoted: promote_at, minus repromote_bonus per previous
## promotion, never below repromote_floor
func promote_threshold(inst) -> float:
	var base = float(tiers.promote_at)
	if inst.promotions > 0:
		base = max(base - float(tiers.repromote_bonus) * inst.promotions, float(tiers.repromote_floor))
	return base

# =============================================================================
# PROMOTION AND DEMOTION (hysteresis: sustained rounds up, threshold + days apart down)
# =============================================================================

func _on_round_completed(_round: int, _reason: String, _entries: Array) -> void:
	evaluate_round()

## One story round: significance, sustained-threshold counting, promotions, demotions
## Also re-registers souls the Director lost (it clears souls when it reloads content)
func evaluate_round() -> Dictionary:
	var result = {"promoted": [], "demoted": []}
	for id in instance_order:
		var inst = instances[id]
		if _director() != null and _director().has_method("register_soul") and not _director_knows(id):
			_register_soul(inst)
		inst.significance = compute_significance(inst)
		if inst.tier == "generic":
			if inst.significance >= promote_threshold(inst):
				inst.rounds_at_threshold += 1
				if inst.rounds_at_threshold >= int(tiers.promote_rounds):
					if promote(id).ok:
						result.promoted.append(id)
			else:
				inst.rounds_at_threshold = 0
	result.demoted = _check_demotions()
	return result

func _check_demotions() -> Array:
	var demoted: Array = []
	for id in get_promoted_ids():
		var inst = instances[id]
		if inst.significance <= float(tiers.demote_at) and ledger.days_apart(id, now_minutes()) >= float(tiers.demote_days_apart):
			if demote(id).ok:
				demoted.append(id)
	return demoted

## Generic -> promoted: a full SOUL.md from archetype + layers (Life arc from the strongest want),
## saved under user://souls/<id>/SOUL.md, tier `promoted`, its own memory collection
func promote(id: String, force: bool = false) -> Dictionary:
	if is_anchored(id):
		return {"ok": false, "reason": "%s is an authored NPC (anchored)" % id}
	var inst = instances.get(id)
	if inst == null:
		return {"ok": false, "reason": "no generic '%s'" % id}
	if inst.tier == "promoted":
		return {"ok": false, "reason": "%s is already promoted" % id}
	var arch = archetypes.get(inst.archetype_id)
	if arch == null:
		return {"ok": false, "reason": "archetype '%s' is not loaded" % inst.archetype_id}
	var now = now_minutes()
	var text = SoulBuilder.build_promoted_soul(inst, arch, _ctx(inst), now)
	var check = SoulBuilder.validate_soul_text(text, id, true)
	var director = _director()
	if check.ok and director and director.has_method("validate_soul_text"):
		var verdict = director.validate_soul_text(id, text)
		if verdict is Dictionary and not verdict.get("ok", true):
			check.ok = false
			check.errors.append_array(verdict.get("errors", []))
	if not check.ok:
		_log("promotion of %s refused: generated soul invalid: %s" % [id, "; ".join(check.errors)])
		return {"ok": false, "reason": "generated soul invalid", "errors": check.errors}
	inst.tier = "promoted"
	inst.promotions += 1
	inst.rounds_at_threshold = 0
	inst.soul_text = text
	inst.soul_path = _save_soul_file(id, text)
	inst.memory_mode = "chroma"
	inst.memory_collection = "npc_%s_memories" % id.to_lower()
	ledger.ensure(id, now)
	inst.note_history("promoted", now, {"forced": force, "threshold": promote_threshold(inst)})
	_set_tier(inst)
	_log("%s (%s) promoted at significance %.1f, day %d" % [inst.name, id, inst.significance, floori(now / 1440.0) + 1])
	for node in _loaded_nodes(id):
		if node.has_method("on_tier_changed"):
			node.on_tier_changed()
	generic_promoted.emit(id)
	if write_souls_in_character and (soul_writer.is_valid() or _claude_mode()):
		rewrite_soul_in_character(id)  # async; keeps the deterministic soul unless the rewrite validates
	return {"ok": true, "soul_path": inst.soul_path, "arcs": check.arcs}

## Claude mode: the promoted soul rewritten in character. Accepted only if it parses, its machine
## lines are unchanged and its Life still passes the strict §8 check; else the deterministic soul stays
func rewrite_soul_in_character(id: String) -> bool:
	var inst = instances.get(id)
	if inst == null or inst.tier != "promoted":
		return false
	var original = inst.soul_text
	var written = ""
	if soul_writer.is_valid():
		written = str(await soul_writer.call(original, inst))
	else:
		written = await _claude_rewrite(original, inst)
	if written.strip_edges() == "" or instances.get(id) == null or inst.soul_text != original:
		return false
	var check = SoulBuilder.validate_soul_text(written, id, true)
	if not check.ok or SoulBuilder.machine_signature(written) != SoulBuilder.machine_signature(original):
		_log("in-character soul for %s rejected (%s); keeping the generated soul" % [id, "; ".join(check.errors) if not check.ok else "machine lines changed"])
		return false
	inst.soul_text = written
	inst.soul_path = _save_soul_file(id, written)
	_set_tier(inst)
	_log("in-character soul for %s accepted" % id)
	return true

func _claude_mode() -> bool:
	var config = get_node_or_null("/root/Config")
	return config != null and "npc_agency_mode" in config and str(config.npc_agency_mode) == "claude" and config.has_method("get_claude_api_key") and config.get_claude_api_key() != ""

func _claude_rewrite(original: String, inst) -> String:
	var client_script = load("res://scripts/dialogue/claude_client.gd")
	if client_script == null:
		return ""
	var client = client_script.new()
	add_child(client)
	var system = "You rewrite SOUL.md files for a late-medieval low-fantasy game. Rewrite ONLY the prose (Essence, Voice, Secrets and the one prose paragraph under each ### Arc) in the voice of the person described. Copy every other line exactly, character for character: the header lines, every line starting with '- ', every '### Arc' line and every '## ' heading. No modern concepts. Reply with the file only."
	var response = await client.send_message([{"role": "user", "content": original}], system)
	client.queue_free()
	return str(response.get("text", "")) if response is Dictionary else ""

## Promoted -> generic ("friends become acquaintances"): name, residue (3 strongest memories as
## one-line layers, nudges halved) and history stay; arc, chroma retrieval and personal turns go
func demote(id: String, force: bool = false) -> Dictionary:
	if is_anchored(id):
		return {"ok": false, "reason": "%s is an authored NPC: anchored, never demoted" % id}
	var inst = instances.get(id)
	if inst == null:
		return {"ok": false, "reason": "no generic '%s'" % id}
	if inst.tier != "promoted":
		return {"ok": false, "reason": "%s is not promoted" % id}
	var arch = archetypes.get(inst.archetype_id)
	var now = now_minutes()
	var strongest = inst.layers.filter(func(l): return l.kind != "acquaintance")
	strongest.sort_custom(func(a, b): return a.importance > b.importance if a.importance != b.importance else int(a.minute) > int(b.minute))
	var residue: Array = []
	for layer in strongest.slice(0, 3):
		var line = str(layer.text).split(" (\"")[0].trim_suffix(".")
		residue.append({"kind": "residue", "text": "Long ago: %s." % _flat(line, 90), "importance": maxi(int(layer.importance) - 1, 1),
			"minute": int(layer.minute), "count": 1, "pinned": false, "tag": "residue:" + str(layer.get("tag", "")), "flag": str(layer.get("flag", ""))})
	inst.layers = residue
	inst.add_layer("acquaintance", "You knew the stranger well once; it has been a long while. An old acquaintance now.", 3, now, {"tag": "acquaintance"})
	inst.halve_nudges()
	inst.tier = "generic"
	inst.rounds_at_threshold = 0
	inst.memory_mode = "layers"
	_retire_soul_file(id)
	inst.soul_path = ""
	inst.soul_text = SoulBuilder.build_rolled_soul(inst, arch, _ctx(inst)) if arch else inst.soul_text
	inst.significance = compute_significance(inst)
	inst.note_history("demoted", now, {"forced": force, "days_apart": snappedf(ledger.days_apart(id, now), 0.1)})
	_set_tier(inst)
	_log("%s (%s) demoted to generic at significance %.1f, day %d" % [inst.name, id, inst.significance, floori(now / 1440.0) + 1])
	for node in _loaded_nodes(id):
		if node.has_method("on_tier_changed"):
			node.on_tier_changed()
	generic_demoted.emit(id)
	return {"ok": true, "residue": residue.map(func(l): return l.text)}

## Whether this NPC's memory uses its own ChromaDB collection (promoted) or only in-memory layers
func wants_chroma(npc_id: String) -> bool:
	var inst = instances.get(npc_id)
	return inst == null or (inst.memory_mode == "chroma" and use_chromadb)

func _save_soul_file(id: String, text: String) -> String:
	var dir_path = "%s/%s" % [souls_dir, id]
	DirAccess.make_dir_recursive_absolute(dir_path)
	var path = dir_path + "/SOUL.md"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[Generics] Could not write %s" % path)
		return ""
	file.store_string(text)
	file.close()
	return path

func _retire_soul_file(id: String) -> void:
	var path = "%s/%s/SOUL.md" % [souls_dir, id]
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, "%s/%s/SOUL.demoted.md" % [souls_dir, id])

# =============================================================================
# SAVE / LOAD (inside WorldState's save file)
# =============================================================================

func save() -> Dictionary:
	var list: Array = []
	for id in instance_order:
		list.append(instances[id].to_dict())
	return {"version": 1, "world_seed": world_seed, "instances": list, "relationships": ledger.save()}

## Restore instances (layers, tiers, history, soul texts) and the ledger, then re-register every
## name and soul. Population entries added since the save are created
func load_from_dict(data: Dictionary) -> void:
	_unregister_names()
	instances.clear()
	instance_order.clear()
	world_seed = int(data.get("world_seed", world_seed))
	ledger.load_from_dict(data.get("relationships", {}))
	for d in data.get("instances", []):
		if not d is Dictionary:
			continue
		var inst = GenericInstance.from_dict(d)
		if inst.id == "":
			continue
		var arch = archetypes.get(inst.archetype_id)
		if inst.soul_text == "" and arch:
			inst.soul_text = SoulBuilder.build_rolled_soul(inst, arch, _ctx(inst))
		instances[inst.id] = inst
		instance_order.append(inst.id)
		_record_location(inst)
		_register_name(inst)
		_register_soul(inst)
	populate()

func reset() -> void:
	_unregister_names()
	instances.clear()
	instance_order.clear()
	ledger.entries.clear()
	log_lines.clear()

# =============================================================================
# DEBUG
# =============================================================================

func describe_list(location_id: String = "") -> Array:
	var out: Array = []
	for id in get_ids_at(location_id):
		var inst = instances[id]
		out.append("%s  %s (%s) @ %s  sig %.0f%s%s" % [id, inst.name, inst.archetype_id, get_location(id), inst.significance,
			"  PROMOTED" if inst.tier == "promoted" else "", "" if is_present(id, get_location(id)) else "  (away)"])
	return out

func describe(id: String) -> Array:
	var inst = instances.get(id)
	if inst == null:
		return ["No generic '%s'" % id]
	var parts = get_significance_parts(inst)
	var dims = ledger.get_dims(id)
	var out: Array = [
		"%s (%s), %s of %s, tier %s, promotions %d" % [inst.name, id, inst.archetype_id, inst.home, inst.tier, inst.promotions],
		"seed %d  voice variant %d  memory %s" % [inst.seed_value, inst.voice_variant, inst.memory_mode],
		"significance %.1f = rel %.1f + layers %.1f + story %.1f + recency %.1f  (promote at %.0f, %d/%d rounds; demote at %d)" % [
			parts.total, parts.relationship, parts.layers, parts.story, parts.recency, promote_threshold(inst),
			inst.rounds_at_threshold, int(tiers.promote_rounds), int(tiers.demote_at)],
		"feelings T%.1f R%.1f A%.1f F%.1f Fam%.1f  days apart %.1f" % [dims.trust, dims.respect, dims.affection, dims.fear, dims.familiarity, ledger.days_apart(id, now_minutes())],
		"wants %s" % ", ".join(inst.rolled_wants.keys().map(func(w): return "%s %d" % [w, inst.get_want_weight(w)])),
		"nudges %s" % JSON.stringify(inst.trait_nudges),
		"layers (%d):" % inst.layers.size(),
	]
	for layer in inst.ranked_layers(now_minutes()):
		out.append("  [%s %d] %s" % [layer.kind, layer.importance, layer.text])
	if not inst.history.is_empty():
		out.append("history: %s" % ", ".join(inst.history.map(func(h): return "%s d%d" % [h.event, int(h.day)])))
	return out

func _log(line: String) -> void:
	print("[Generics] " + line)
	log_lines.append(line)
	if log_lines.size() > 50:
		log_lines.pop_front()

# =============================================================================
# HELPERS
# =============================================================================

func now_minutes() -> int:
	if test_now >= 0:
		return test_now
	var world_state = get_node_or_null("/root/WorldState")
	return int(world_state.game_minutes) if world_state else 0

func _ctx(inst) -> Dictionary:
	var registry = get_node_or_null("/root/WorldRegistry")
	var home_name = inst.home.replace("_", " ").capitalize()
	var region_name = inst.region.replace("_", " ").capitalize()
	if registry:
		if registry.has_location(inst.home):
			home_name = registry.get_location_name(inst.home)
		if inst.region != "":
			region_name = registry.get_region_name(inst.region)
	return {"home_name": home_name, "region_name": region_name}

func _region_of(location: String) -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry.get_region(location) if registry else ""

func _loaded_nodes(npc_id: String) -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in node and str(node.npc_id) == npc_id and not node.is_queued_for_deletion():
			out.append(node)
	return out

func _read_json(path: String):
	if path == "" or not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data
