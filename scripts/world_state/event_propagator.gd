extends Node
# EventPropagator - Lets NPCs learn about story events they plausibly know about
# Witnesses: NPCs present when a witnessable flag is set learn it immediately
# Gossip: public news spreads to listed NPCs after a delay, even across scenes
# NPCs not loaded when news reaches them get it on their next initialize()
# Memory text comes from StoryFlags.FLAG_DESCRIPTIONS, so nothing is invented

signal memory_propagated(npc_id: String, flag_name: String, how: String)
## News reached people: "witnessed" (location = where it happened, keys empty) or "gossip"
## (keys = the rule's listeners, "*" = everyone in region). Generic NPCs listen here (they are not
## on the roster, so they get it as a layer, never through the pending queue)
signal news_spread(flag_name: String, text: String, how: String, keys: Array, region: String, location: String)

## NPC keys come from WorldRegistry (world.json). "*" means every roster NPC who lives in the
## region the news starts in: news moves at the speed of a rider, so it stays local
## The base gossip rules below are Thornhaven's, so their "*" is the valley's
const GOSSIP_REGION = "western_valley"

## Flags an NPC in the same room would notice happening
const WITNESSABLE_FLAGS = [
	"ledger_found",
	"bulk_orders_found",
	"weapons_traced_to_bjorn",
	"gregor_confronted",
	"gregor_confession_heard",
	"varn_confronted",
	"elena_shown_proof",
	"iron_hollow_visited",
]

## News that travels by word of mouth: flag -> who hears it, how, and after how many seconds
## "to" holds roster keys ("*" = every NPC whose home is in GOSSIP_REGION)
## Secrets (ledger_found, mira_boss_revealed, ...) are absent on purpose: only witnesses learn them
const GOSSIP_RULES = {
	"gregor_exposed": {"to": ["*"], "via": "talk in the village square", "delay": 30.0, "importance": 9},
	"resistance_forming": {"to": ["*"], "via": "hushed talk among the villagers", "delay": 60.0, "importance": 8},
	"aldric_has_evidence": {"to": ["mathias"], "via": "Captain Aldric's report to the council", "delay": 30.0, "importance": 8},
	"bjorn_truth_revealed": {"to": ["gregor"], "via": "Bjorn storming into the shop", "delay": 45.0, "importance": 9},
	"gregor_confronted": {"to": ["elena"], "via": "raised voices from her father's shop", "delay": 20.0, "importance": 7},
	# Varn answers to The Boss, so Mira hears what happens at the camp
	"varn_confronted": {"to": ["mira"], "via": "a bandit runner carrying Varn's report", "delay": 60.0, "importance": 8},
	"iron_hollow_visited": {"to": ["mira"], "via": "a bandit runner from Iron Hollow", "delay": 90.0, "importance": 7},
}

var _delivered: Dictionary = {}   # "npc_id|flag" -> true
var _pending: Dictionary = {}     # npc key -> Array of memory dicts awaiting that NPC
var _scheduled: Dictionary = {}   # flag -> true while its gossip timer is running

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.world_flag_changed.connect(_on_world_flag_changed)
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and not world_state.event_propagation_state.is_empty():
		load_from_dict(world_state.event_propagation_state)
	print("EventPropagator initialized")

func _on_world_flag_changed(flag_name: String, _old_value, new_value):
	if new_value == true:
		# Flags the StorylineDirector set (NPC or on_resolve effects) were not the player's doing,
		# so nobody witnesses the player do them; gossip rules still apply
		var director = get_node_or_null("/root/StorylineDirector")
		var player_caused = director == null or not director.has_method("is_director_change") or not director.is_director_change()
		# Calendar fixed points are the world's doing (the clock), never the player's: no witnesses
		var world_state = get_node_or_null("/root/WorldState")
		if world_state and world_state.has_method("is_world_change") and world_state.is_world_change():
			player_caused = false
		propagate_flag(flag_name, "", player_caused)

## Spread a story flag to witnesses now and schedule any gossip
## with_witnesses = false skips the witness step (the change was not the player's)
func propagate_flag(flag_name: String, location_id: String = "", with_witnesses: bool = true) -> void:
	var description = StoryFlags.get_flag_description(flag_name)
	if description == "":
		return
	if location_id == "":
		location_id = _current_location_id()

	var witnesses: Array = []
	if with_witnesses and is_witnessable(flag_name):
		for npc in get_npcs_present(location_id):
			witnesses.append(npc.npc_id)
			_deliver(npc, _witness_memory(flag_name, description, npc.npc_id))
	_register_canonical(description, witnesses, location_id)
	if with_witnesses and is_witnessable(flag_name):
		news_spread.emit(flag_name, description, "witnessed", [], _region_of(location_id), location_id)

	if GOSSIP_RULES.has(flag_name) and not _scheduled.has(flag_name):
		_schedule_gossip(flag_name, GOSSIP_RULES[flag_name].get("delay", 0.0))

## Flags an NPC in the same room would notice: WITNESSABLE_FLAGS plus world.json discovery flags
func is_witnessable(flag_name: String) -> bool:
	return flag_name in WITNESSABLE_FLAGS or StoryFlags.is_discovery_flag(flag_name)

## Deliver a gossip rule's news to its listeners (called when the delay elapses)
func spread_gossip(flag_name: String) -> void:
	_scheduled.erase(flag_name)
	var rule = GOSSIP_RULES.get(flag_name, {})
	if not rule.is_empty():
		_spread(flag_name, rule.merged({"region": GOSSIP_REGION}))

## Spread a flag's canonical text to chosen NPCs now (StorylineDirector's spread_rumor effect)
## to: npc keys or ["*"]; via: how it travelled; region: where "*" listeners live
## ("" = the current scene's region, else GOSSIP_REGION). Unloaded NPCs get it on their next initialize()
func spread_flag(flag_name: String, to: Array, via: String = "", importance: int = 7, region: String = "") -> bool:
	if StoryFlags.get_flag_description(flag_name) == "" or to.is_empty():
		return false
	_spread(flag_name, {"to": to, "via": via if via != "" else "village talk", "importance": importance, "region": region})
	return true

## Roster keys a "*" reaches: everyone who lives in that region
func get_star_keys(region: String = "") -> Array:
	var registry = get_node_or_null("/root/WorldRegistry")
	if registry == null:
		return []
	if region == "":
		region = registry.get_region(_current_location_id())
	if region == "":
		region = GOSSIP_REGION
	return registry.get_npcs_in_region(region)

func _spread(flag_name: String, rule: Dictionary) -> void:
	var description = StoryFlags.get_flag_description(flag_name)
	if description == "":
		return

	var keys: Array = get_star_keys(str(rule.get("region", ""))) if "*" in rule.to else rule.to
	var region = str(rule.get("region", ""))
	if region == "":
		region = _region_of(_current_location_id())
	news_spread.emit(flag_name, description, "gossip", rule.to.duplicate(), region if region != "" else GOSSIP_REGION, _current_location_id())
	var loaded = get_loaded_npcs()
	for key in keys:
		var memory = _gossip_memory(flag_name, description, rule, key)
		var reached = false
		for npc in loaded:
			if _npc_key(npc.npc_id) == key:
				reached = true
				_deliver(npc, memory)
		if not reached:
			_queue(key, memory)

## Hand an NPC everything that reached it while it wasn't loaded
## Called by BaseNPC at the end of initialize()
func deliver_pending(npc: Node) -> void:
	var key = _npc_key(npc.npc_id)
	if not _pending.has(key):
		return
	var queued: Array = _pending[key]
	_pending.erase(key)
	for memory in queued:
		_deliver(npc, memory)

## NPCs alive and visible at a location ("" = any location)
func get_npcs_present(location_id: String) -> Array:
	var result = []
	for npc in get_loaded_npcs():
		if not npc.is_visible_in_tree():
			continue
		if location_id != "" and npc.has_method("get_current_location") and npc.get_current_location() != location_id:
			continue
		result.append(npc)
	return result

## NPCs currently in the scene tree and alive
func get_loaded_npcs() -> Array:
	var result = []
	if not is_inside_tree():
		return result
	for npc in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in npc and npc.npc_id != "" and npc.get("is_alive") != false:
			result.append(npc)
	return result

func get_pending_count(npc_key: String = "") -> int:
	if npc_key != "":
		return _pending.get(npc_key, []).size()
	var total = 0
	for key in _pending:
		total += _pending[key].size()
	return total

func has_delivered(npc_id: String, flag_name: String) -> bool:
	return _delivered.has("%s|%s" % [npc_id, flag_name])

# =============================================================================
# SAVE / LOAD (stored inside WorldState's save file)
# =============================================================================

func save() -> Dictionary:
	return {
		"delivered": _delivered.keys(),
		"pending": _pending.duplicate(true),
		"scheduled": _scheduled.keys()
	}

func load_from_dict(data: Dictionary) -> void:
	_delivered.clear()
	for key in data.get("delivered", []):
		_delivered[key] = true
	_pending = data.get("pending", {}).duplicate(true)
	_scheduled.clear()
	# Gossip that was in flight at save time restarts its full delay
	for flag_name in data.get("scheduled", []):
		if GOSSIP_RULES.has(flag_name):
			_schedule_gossip(flag_name, GOSSIP_RULES[flag_name].get("delay", 0.0))

# =============================================================================
# INTERNALS
# =============================================================================

func _schedule_gossip(flag_name: String, delay: float) -> void:
	_scheduled[flag_name] = true
	if delay > 0.0 and is_inside_tree():
		# process_always = false: gossip waits while the game is paused
		get_tree().create_timer(delay, false).timeout.connect(spread_gossip.bind(flag_name))
	else:
		spread_gossip(flag_name)

func _deliver(npc: Node, memory: Dictionary) -> void:
	var key = "%s|%s" % [npc.npc_id, memory.flag]
	if _delivered.has(key):
		return
	if not npc.get("_is_initialized") or npc.get("rag_memory") == null:
		_queue(_npc_key(npc.npc_id), memory)
		return
	_delivered[key] = true
	# _delivered only lives in the save file, but ChromaDB persists across sessions:
	# skip memories this NPC's collection already holds for the same flag and event type
	if npc.rag_memory.has_method("has_memory_with"):
		var exists = await npc.rag_memory.has_memory_with({"source_flag": memory.flag, "event_type": memory.event_type})
		if exists:
			print("[EventPropagator] %s already remembers '%s' (%s), skipping" % [npc.npc_id, memory.flag, memory.how])
			return
	# Canonical text from StoryFlags - skip hallucination validation (it would reject names like Marcus)
	npc.rag_memory.store({
		"text": memory.text,
		"event_type": memory.event_type,
		"importance": memory.importance,
		"emotion": memory.emotion,
		"participants": ["player"],
		"source_flag": memory.flag,
		"how": memory.how
	}, "", true)
	print("[EventPropagator] %s learned '%s' (%s)" % [npc.npc_id, memory.flag, memory.how])
	memory_propagated.emit(npc.npc_id, memory.flag, memory.how)

func _queue(npc_key: String, memory: Dictionary) -> void:
	var queue: Array = _pending.get(npc_key, [])
	for existing in queue:
		if existing.flag == memory.flag:
			return
	queue.append(memory)
	_pending[npc_key] = queue

func _witness_memory(flag_name: String, description: String, npc_id: String) -> Dictionary:
	var implicated = _is_implicated(flag_name, npc_id)
	return {
		"flag": flag_name,
		"how": "witnessed",
		"text": "I witnessed: " + description,
		"event_type": "witnessed_event",
		"importance": 9 if implicated else 7,
		"emotion": "afraid" if implicated else "surprised"
	}

func _gossip_memory(flag_name: String, description: String, rule: Dictionary, npc_key: String) -> Dictionary:
	var implicated = _is_implicated(flag_name, npc_key)
	return {
		"flag": flag_name,
		"how": "gossip",
		"text": "I heard through %s: %s" % [rule.get("via", "village talk"), description],
		"event_type": "heard_news",
		"importance": rule.get("importance", 7),
		"emotion": "afraid" if implicated else "curious"
	}

## Whether this flag is about this NPC (StoryFlags.IMPLICATED_NPCS)
func _is_implicated(flag_name: String, npc_id: String) -> bool:
	var implicated = StoryFlags.IMPLICATED_NPCS.get(flag_name, "")
	return implicated != "" and implicated in npc_id.to_lower()

func _register_canonical(description: String, witnesses: Array, location_id: String) -> void:
	var world_events = get_node_or_null("/root/WorldEvents")
	if world_events:
		world_events.register_event(world_events.EventCategory.QUEST_PROGRESS, description, ["player"] + witnesses, location_id)

func _region_of(location_id: String) -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry.get_region(location_id) if registry and location_id != "" else ""

func _current_location_id() -> String:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("get_current_location_id"):
		return scene_manager.get_current_location_id()
	return ""

func _npc_key(npc_id: String) -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	var key = registry.get_npc_key(npc_id) if registry else ""
	return key if key != "" else npc_id.to_lower()
