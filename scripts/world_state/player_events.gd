extends Node
# PlayerEvents - The world's memory of what the player did and said (docs/WORLD_SCHEMA.md §10)
#
# - record(kind, summary, about, opts): one player event, fixed kinds, witnesses = who was present
# - promises (due by day and/or flag) run open -> kept | broken; claims that name a flag turn into
#   lies when the world contradicts them. Each change is player_event_changed and can spread
# - spread(event_id, to_keys, via): word travels the routes graph from the nearest person who knows
#   it, arriving after the route's minutes, losing fidelity per retelling, and drifting toward the
#   teller's attitude (offline templates). Below ANON_BELOW it is a rumour of a stranger
# - hearers store what they HEARD: mains through EventPropagator (RAG memory, source_flag dedup,
#   queued while unloaded), generics as layers through GenericManager.on_news_spread (tag dedup)
# - capture: conversation utterances (BaseNPC), Director commitments (player_choice), StoryItem
#   discoveries, arrivals (seen_at) and time spent near someone (kept_company, hourly)
# Reputation (scripts/world_state/reputation.gd) is computed only from what each party knows here

signal player_event_recorded(ev: Dictionary)
signal player_event_changed(ev: Dictionary)          # status (kept/broken) or truth (lie exposed)
signal player_event_heard(event_id: String, who: String, fidelity: float)

const KINDS = ["claim", "promise", "threat", "lie", "insult", "gift", "help", "harm", "theft", "kill",
	"spared", "confession", "accusation", "refusal", "seen_at", "kept_company",
	# Player systems (docs/PLAYER_SYSTEMS.md §7): physical deeds, witnessed by line of sight
	"feat", "crafted", "fled", "fire", "trespass", "solved", "fell"]
## What an NPC may report from a conversation (deeds of place and time are captured, not reported)
const UTTERANCE_KINDS = ["claim", "promise", "threat", "lie", "insult", "gift", "help", "harm", "theft",
	"kill", "spared", "confession", "accusation", "refusal"]
## Loud deeds: witnesses talk, so word goes round the region on its own
const AUTO_SPREAD_KINDS = ["threat", "harm", "theft", "kill", "spared", "help", "gift", "confession", "accusation",
	"feat", "fire", "fell", "fled"]
const AUTO_SPREAD_VIA = "talk going round"

const FIDELITY_HOP = 0.15        # lost per retelling
const RELAY_MINUTES = 240        # a longer road passes through one more mouth per this many minutes
const ANON_BELOW = 0.3           # below this the stranger is nobody in particular
const HALF_HEARD_BELOW = 0.6
const MIN_FIDELITY = 0.1
const MAX_EVENTS = 400
const MAX_UTTERANCES = 3
const SUMMARY_MAX = 140
const ARRIVAL_THROTTLE_MINUTES = 60
const COMPANY_MINUTES = 60
const MINUTES_PER_DAY = 1440
const SOURCE_PREFIX = "pe:"
const PROMPT_MAX_EVENTS = 4
const PROMPT_LINE_MAX = 150

const IMPORTANCE = {"kill": 9, "harm": 8, "spared": 8, "theft": 7, "threat": 7, "lie": 7, "confession": 7,
	"promise": 6, "gift": 6, "help": 6, "accusation": 6, "insult": 5, "refusal": 5, "claim": 4,
	"seen_at": 3, "kept_company": 3,
	"fire": 8, "fell": 6, "feat": 5, "fled": 5, "trespass": 5, "solved": 4, "crafted": 3}

## Anonymous rumours: what is left of the deed when nobody remembers who did it
const VAGUE = {"claim": "told some tale", "promise": "made someone a promise", "threat": "threatened someone",
	"lie": "told lies", "insult": "insulted someone", "gift": "gave something away", "help": "helped someone",
	"harm": "hurt someone", "theft": "stole something", "kill": "killed a man", "spared": "spared someone's life",
	"confession": "confessed to something", "accusation": "accused someone", "refusal": "refused someone",
	"seen_at": "was seen about", "kept_company": "kept company with someone",
	"feat": "did something few could", "crafted": "made something", "fled": "ran from a fight",
	"fire": "set a fire", "trespass": "went where they had no right to", "solved": "worked out a puzzle",
	"fell": "fell, and lay still"}

## Retelling drift, keyed by the teller's attitude and whether the deed reads well or ill
const TONE_TEMPLATES = {
	"dark_bad": ["%s. There's malice in that one.", "%s, and worse besides, I'd wager."],
	"dark_good": ["%s. Ask yourself what they want for it.", "%s. I don't trust a kindness like that."],
	"soft_bad": ["%s. I'd wager they had their reasons.", "%s, though hard times make hard choices."],
	"soft_good": ["%s. A kind soul, that one.", "%s. We could use more like them."],
	"plain_bad": ["%s.", "Word is %s."],
	"plain_good": ["%s.", "Word is %s."],
}

const Rep = preload("res://scripts/world_state/reputation.gd")

var events: Dictionary = {}      # id -> event (WORLD_SCHEMA §10 shape plus status/due/changed fields)
var order: Array = []            # ids, oldest first
var counter: int = 0
var in_flight: Array = []        # [{event, to, at, fidelity, from, via, tone}] word on the road
var _company: Dictionary = {}    # who -> minutes near the player toward the next kept_company tick
var _last_arrival: Dictionary = {}  # location -> minute of the last seen_at there

## Tests and tools
var player_location_override: String = ""
var now_override: int = -1
var capture_enabled: bool = true     # false: signals from the world record nothing (tests)

func _ready():
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.time_advanced.connect(_on_time_advanced)
		bus.world_flag_changed.connect(_on_world_flag_changed)
		bus.world_event.connect(_on_world_event)
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_signal("scene_transition_completed"):
		scene_manager.scene_transition_completed.connect(_on_arrived)
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and "player_events_state" in world_state and not world_state.player_events_state.is_empty():
		load_from_dict(world_state.player_events_state)
	call_deferred("_connect_director")
	print("PlayerEvents initialized (%d events)" % order.size())

func _connect_director() -> void:
	var director = get_node_or_null("/root/StorylineDirector")
	if director == null:
		return
	if director.has_signal("decision_recorded") and not director.decision_recorded.is_connected(_on_director_decision):
		director.decision_recorded.connect(_on_director_decision)
	if director.has_signal("conversation_acted") and not director.conversation_acted.is_connected(_on_conversation_acted):
		director.conversation_acted.connect(_on_conversation_acted)

# =============================================================================
# RECORDING
# =============================================================================

## Record one player event. Returns its id ("" when refused: unknown kind or empty summary)
## summary: what the player did, without a subject ("promised Gregor to get Elena out")
## about: npc keys / ids / generic ids it concerns
## opts:
##   location, minute          where and when (default: the player's location, now)
##   witnesses: Array          who saw it (npc ids, keys or generic ids). Default: everyone present
##   with_present: bool        add everyone present to the explicit witnesses
##   source: String            the NPC who reported it (a conversation partner already remembers it)
##   flag, value (default true) the world fact a claim asserts or a promise is about
##   due: {"day": n, "flag": f, "value": bool, "fails": [flags]}  promise deadline / fulfilment
##   believed: bool            whether the reporting NPC believed it (default true)
##   truth, status             override (rarely needed)
##   spread: bool              force/forbid the automatic regional gossip (default: loud kinds spread)
##   commitment: String        the player flag a Director commitment set
##   remember: bool            witnesses store a memory (default true; false for kept_company and plain
##                             arrivals, which are knowledge for reputation and prompts, not RAG entries)
func record(kind: String, summary: String, about: Array = [], opts: Dictionary = {}) -> String:
	kind = kind.strip_edges().to_lower()
	if kind not in KINDS:
		push_warning("[PlayerEvents] Unknown event kind '%s'" % kind)
		return ""
	summary = _clean_summary(summary)
	if summary == "":
		return ""
	var location = str(opts.get("location", _player_location()))
	var minute = int(opts.get("minute", _now()))
	var witnesses: Array = []   # who-keys while building; stored as npc ids (schema shape)
	var from_presence = not opts.has("witnesses")
	if opts.has("witnesses"):
		for w in opts.witnesses:
			_append_unique(witnesses, _who(str(w)))
	if from_presence or opts.get("with_present", false):
		for w in get_present(location):
			_append_unique(witnesses, w)
	witnesses = witnesses.filter(func(w): return w != "")
	var flag = opts.get("flag", null)
	if flag != null and str(flag) == "":
		flag = null
	var source = str(opts.get("source", ""))
	var ev = {
		"id": _next_id(), "kind": kind, "summary": summary, "about": _normalize_about(about),
		"flag": flag, "value": opts.get("value", true) != false,
		"truth": str(opts.get("truth", "true" if kind not in ["claim", "promise"] else "unknown")),
		"status": str(opts.get("status", "open" if kind == "promise" else "none")),
		"location": location, "minute": minute,
		"witnesses": witnesses.map(func(w): return _npc_id_of(w)),
		"heard_by": {}, "fidelity": 1.0,
		"source": _who(source) if source != "" else "",
		"believed": opts.get("believed", true) != false,
		"due": _parse_due(opts.get("due", null)),
		"changed_minute": minute,
	}
	if opts.has("commitment"):
		ev["commitment"] = str(opts.commitment)
	# A claim the world already contradicts is a lie from the start
	if kind == "claim" and flag != null:
		var current = _flag_value(str(flag))
		if current and ev.value:
			ev["truth"] = "true"
		elif current and not ev.value:
			ev["was"] = "claim"
			ev["kind"] = "lie"
			ev["truth"] = "false"
			ev["status"] = "exposed"
	events[ev.id] = ev
	order.append(ev.id)
	_prune()
	print("[PlayerEvents] %s %s: %s (%d witness(es))" % [ev.id, ev.kind, summary, witnesses.size()])
	player_event_recorded.emit(ev.duplicate(true))
	if opts.get("remember", ev.kind != "kept_company") != false:
		_tell_witnesses(ev, witnesses, from_presence)
	var loud = ev.kind in AUTO_SPREAD_KINDS
	if bool(opts.get("spread", loud)) and not witnesses.is_empty():
		spread(ev.id, ["*"], AUTO_SPREAD_VIA)
	return ev.id

## One event by id (a copy; {} when unknown)
func get_event(id: String) -> Dictionary:
	return events[id].duplicate(true) if events.has(id) else {}

## Every event, oldest first (copies)
func get_events() -> Array:
	return order.map(func(id): return events[id].duplicate(true))

## What one NPC knows of the player, newest first:
## [{id, kind, status, truth, about, minute, learned, fidelity, how ("witnessed"|"heard"), from, text, anonymous}]
func known_by(npc_key: String) -> Array:
	var who = _who(npc_key)
	var result: Array = []
	for id in order:
		var k = _knowledge(events[id], who)
		if not k.is_empty():
			result.append(k)
	result.reverse()
	return result

## Whether this NPC knows the event, at what fidelity (0 = it does not)
func fidelity_for(event_id: String, npc_key: String) -> float:
	if not events.has(event_id):
		return 0.0
	var k = _knowledge(events[event_id], _who(npc_key))
	return float(k.fidelity) if not k.is_empty() else 0.0

## Events matching every given field (copies, oldest first). query keys:
## kind (String|Array; an exposed lie also matches its original kind), status, truth, about (one key),
## witness (one key), known_by (one key), flag, location, since (minute), source
func events_matching(query: Dictionary = {}) -> Array:
	var result: Array = []
	for id in order:
		var ev: Dictionary = events[id]
		if query.has("kind"):
			var kinds = query.kind if query.kind is Array else [query.kind]
			if ev.kind not in kinds and str(ev.get("was", "")) not in kinds:
				continue
		if query.has("status") and ev.status != str(query.status):
			continue
		if query.has("truth") and ev.truth != str(query.truth):
			continue
		if query.has("about") and _who(str(query.about)) not in ev.about:
			continue
		if query.has("witness") and _npc_id_of(_who(str(query.witness))) not in ev.witnesses:
			continue
		if query.has("known_by") and _knowledge(ev, _who(str(query.known_by))).is_empty():
			continue
		if query.has("flag") and str(ev.flag) != str(query.flag):
			continue
		if query.has("location") and ev.location != str(query.location):
			continue
		if query.has("since") and int(ev.minute) < int(query.since):
			continue
		if query.has("source") and ev.source != _who(str(query.source)):
			continue
		result.append(ev.duplicate(true))
	return result

# =============================================================================
# PROMISES AND TRUTH
# =============================================================================

## Settle a promise by hand (Director, debug). outcome "kept" | "broken". Returns false when not open
func resolve_promise(event_id: String, outcome: String, reason: String = "") -> bool:
	if not events.has(event_id) or outcome not in ["kept", "broken"]:
		return false
	var ev: Dictionary = events[event_id]
	if ev.kind != "promise" or ev.status != "open":
		return false
	_set_promise(ev, outcome, reason if reason != "" else "settled")
	return true

## Set or replace a promise's due ({"day", "flag", "value", "fails"})
func set_due(event_id: String, due: Dictionary) -> bool:
	if not events.has(event_id) or events[event_id].kind != "promise":
		return false
	events[event_id]["due"] = _parse_due(due)
	return true

func _set_promise(ev: Dictionary, outcome: String, reason: String) -> void:
	ev["status"] = outcome
	ev["truth"] = "true" if outcome == "kept" else "false"
	ev["changed_minute"] = _now()
	ev["change_reason"] = reason
	print("[PlayerEvents] %s promise %s (%s): %s" % [ev.id, outcome, reason, ev.summary])
	player_event_changed.emit(ev.duplicate(true))
	if outcome == "broken" and not _knowers(ev).is_empty():
		spread(ev.id, ["*"], "word of a broken promise")

func _expose_lie(ev: Dictionary, reason: String) -> void:
	ev["was"] = ev.kind
	ev["kind"] = "lie"
	ev["truth"] = "false"
	ev["status"] = "exposed"
	ev["changed_minute"] = _now()
	ev["change_reason"] = reason
	print("[PlayerEvents] %s exposed as a lie (%s): %s" % [ev.id, reason, ev.summary])
	player_event_changed.emit(ev.duplicate(true))
	if not _knowers(ev).is_empty():
		spread(ev.id, ["*"], "word that the stranger lied")

## Promises past their day, promises whose flag came true (kept) or whose fail flag did (broken)
func check_promises() -> void:
	var day = floori(_now() / float(MINUTES_PER_DAY)) + 1
	for id in order.duplicate():
		if not events.has(id):
			continue
		var ev: Dictionary = events[id]
		if ev.kind != "promise" or ev.status != "open" or ev.due.is_empty():
			continue
		var due: Dictionary = ev.due
		if due.has("flag") and _flag_value(str(due.flag)) == bool(due.get("value", true)):
			_set_promise(ev, "kept", "%s came true" % due.flag)
			continue
		var failed = ""
		for f in due.get("fails", []):
			if _flag_value(str(f)):
				failed = str(f)
				break
		if failed != "":
			_set_promise(ev, "broken", "%s made it impossible" % failed)
		elif due.has("day") and day > int(due.day):
			_set_promise(ev, "broken", "day %d passed" % int(due.day))

func _on_world_flag_changed(flag_name: String, _old_value, new_value) -> void:
	var value = new_value == true
	for id in order.duplicate():
		if not events.has(id):
			continue
		var ev: Dictionary = events[id]
		if ev.flag == null or str(ev.flag) != flag_name:
			continue
		if ev.kind == "claim":
			if value == bool(ev.value):
				if ev.truth != "true":
					ev["truth"] = "true"
					ev["changed_minute"] = _now()
					player_event_changed.emit(ev.duplicate(true))
			else:
				_expose_lie(ev, "%s became %s" % [flag_name, str(value).to_lower()])
		elif ev.kind == "promise" and ev.status == "open" and ev.due.is_empty() and value != bool(ev.value):
			_set_promise(ev, "broken", "%s became %s" % [flag_name, str(value).to_lower()])
	check_promises()

# =============================================================================
# SPREAD
# =============================================================================

## Send word of an event to people (the Director's spread_event effect calls this)
## to_keys: npc keys / ids / generic ids, or "*" = everyone living in the event's region
## Each target hears it from the nearest living person who knows it, after the route's minutes, at
## that teller's fidelity minus FIDELITY_HOP per retelling (one, plus one per RELAY_MINUTES of road).
## Nobody unreachable on the routes graph hears anything
## Returns {"ok": bool, "scheduled": [{to, from, at, fidelity}], "refused": [{to, reason}]}
func spread(event_id: String, to_keys: Array, via: String = "") -> Dictionary:
	var result = {"ok": false, "scheduled": [], "refused": []}
	if not events.has(event_id):
		result.refused.append({"to": "", "reason": "no such event '%s'" % event_id})
		return result
	var ev: Dictionary = events[event_id]
	var now = _now()
	for target in _expand_targets(ev, to_keys):
		var known = _knowledge(ev, target)
		if not known.is_empty() and known.how == "witnessed":
			continue
		if _in_flight_to(event_id, target):
			continue
		if _location_of(target) == "":
			result.refused.append({"to": target, "reason": "nobody called '%s' is anywhere" % target})
			continue
		if not _is_alive(target):
			result.refused.append({"to": target, "reason": "%s is dead" % target})
			continue
		var best = _best_teller(ev, target)
		if best.is_empty():
			result.refused.append({"to": target, "reason": "unreachable: nobody who knows it can get word to %s" % target})
			continue
		if not known.is_empty() and float(known.fidelity) >= float(best.fidelity):
			continue  # already heard it at least this well
		var item = {"event": event_id, "to": target, "at": now + int(best.minutes), "fidelity": float(best.fidelity),
			"from": best.teller, "via": via, "tone": _tone_of(best.teller)}
		result.scheduled.append({"to": target, "from": best.teller, "at": item.at, "fidelity": item.fidelity})
		if int(best.minutes) <= 0:
			_deliver_heard(item)
		else:
			in_flight.append(item)
	result.ok = not result.scheduled.is_empty()
	return result

## Deliver word whose time has come (the clock moving calls this). Returns how many arrived
func process_in_flight() -> int:
	var now = _now()
	var arrived: Array = in_flight.filter(func(i): return int(i.at) <= now)
	if arrived.is_empty():
		return 0
	in_flight = in_flight.filter(func(i): return int(i.at) > now)
	arrived.sort_custom(func(a, b): return int(a.at) < int(b.at))
	for item in arrived:
		_deliver_heard(item)
	return arrived.size()

func _deliver_heard(item: Dictionary) -> void:
	if not events.has(str(item.event)):
		return
	var ev: Dictionary = events[str(item.event)]
	var target = str(item.to)
	var known = _knowledge(ev, target)
	if not known.is_empty() and float(known.fidelity) >= float(item.fidelity):
		return
	var f = float(item.fidelity)
	var tone = str(item.get("tone", "plain"))
	var text = compose(ev, tone, f, abs(hash(str(ev.id) + target)))
	ev.heard_by[target] = {"fidelity": f, "minute": int(item.at), "from": str(item.from), "via": str(item.get("via", "")),
		"tone": tone}
	var how = "I heard"
	if f >= ANON_BELOW:
		how += " from " + _display_name(str(item.from))
	if str(item.get("via", "")) != "":
		how += " (%s)" % str(item.via)
	_store_memory(target, ev, "%s: %s" % [how, text], "heard")
	player_event_heard.emit(str(ev.id), target, f)

## Witnesses remember the deed (and its known status) as they saw it. A conversation partner (source)
## already remembers the conversation itself
func _tell_witnesses(ev: Dictionary, witnesses: Array, from_presence: bool) -> void:
	var gm = _generics()
	var text = compose(ev, "plain", 1.0, 0)
	var generic_witnesses: Array = []
	for w in witnesses:
		if gm and gm.is_generic(w):
			generic_witnesses.append(w)
		elif w != ev.source:
			_store_memory(w, ev, "I saw it myself: " + text, "witnessed")
	if gm and not generic_witnesses.is_empty() and gm.has_method("on_news_spread"):
		if from_presence:
			gm.on_news_spread(_source_flag(ev), text, "witnessed", [], _region_of(ev.location), ev.location)
		else:
			for w in generic_witnesses:
				if w != ev.source:
					_store_memory(w, ev, text, "witnessed")

## Memory of a player event: mains through EventPropagator (RAG, deduped by source_flag, queued while
## unloaded), generics as a layer through on_news_spread (deduped by tag)
func _store_memory(who: String, ev: Dictionary, text: String, how: String) -> void:
	var gm = _generics()
	if gm and gm.is_generic(who):
		if gm.has_method("on_news_spread"):
			var where = _location_of(who)
			gm.on_news_spread(_source_flag(ev), text, "gossip", [who], _region_of(where), where)
		return
	var propagator = get_node_or_null("/root/EventPropagator")
	if propagator == null or not propagator.has_method("deliver_memory"):
		return
	var importance = int(IMPORTANCE.get(str(ev.get("was", ev.kind)), 5))
	if ev.status in ["broken", "exposed"]:
		importance = maxi(importance, 8)
	if how == "heard":
		importance = maxi(importance - 1, 3)
	propagator.deliver_memory(who, {
		"flag": _source_flag(ev),
		"how": how,
		"text": text,
		"event_type": "player_event_" + how,
		"importance": importance,
		"emotion": "afraid" if Rep.kind_weight(ev) <= -12 else ("curious" if how == "heard" else "surprised"),
	})

## Who knows an event: who -> fidelity (witnesses 1.0, then what was heard)
func _knowers(ev: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for npc_id in ev.witnesses:
		result[_who(str(npc_id))] = 1.0
	for who in ev.heard_by:
		if not result.has(who):
			result[who] = float(ev.heard_by[who].fidelity)
	return result

func _best_teller(ev: Dictionary, target: String) -> Dictionary:
	var registry = _registry()
	var to_loc = _location_of(target)
	var best: Dictionary = {}
	var knowers = _knowers(ev)
	for teller in knowers:
		if teller == target or not _is_alive(teller):
			continue
		var from_loc = _location_of(teller)
		if from_loc == "" or to_loc == "":
			continue
		var minutes = 0 if from_loc == to_loc else (registry.travel_minutes(from_loc, to_loc) if registry else -1)
		if minutes < 0:
			continue
		var hops = 1 + floori(minutes / float(RELAY_MINUTES))
		var f = maxf(float(knowers[teller]) - FIDELITY_HOP * hops, MIN_FIDELITY)
		if best.is_empty() or minutes < int(best.minutes) or (minutes == int(best.minutes) and f > float(best.fidelity)):
			best = {"teller": teller, "minutes": minutes, "fidelity": snappedf(f, 0.01)}
	return best

func _expand_targets(ev: Dictionary, to_keys: Array) -> Array:
	var targets: Array = []
	for raw in to_keys:
		var key = str(raw).strip_edges()
		if key == "*":
			var region = _region_of(ev.location)
			if region == "":
				for teller in _knowers(ev):
					region = _region_of(_location_of(teller))
					if region != "":
						break
			for who in get_people_in_region(region):
				_append_unique(targets, who)
		elif key != "":
			_append_unique(targets, _who(key))
	return targets

func _in_flight_to(event_id: String, who: String) -> bool:
	for item in in_flight:
		if str(item.event) == event_id and str(item.to) == who:
			return true
	return false

# =============================================================================
# WORDING (deterministic; fidelity- and attitude-aware)
# =============================================================================

## The event as someone would tell it: tone "dark" | "soft" | "plain", at this fidelity
func compose(ev: Dictionary, tone: String, fidelity: float, seed: int = 0) -> String:
	var kind = str(ev.get("was", ev.kind))
	if fidelity < ANON_BELOW:
		var vague = str(VAGUE.get(kind, "did something"))
		if ev.status == "broken":
			vague = "broke a promise"
		elif ev.status == "exposed":
			vague = "was caught in a lie"
		return "There's a rumour of a stranger who %s." % vague
	var core = "the stranger " + str(ev.summary) + _status_suffix(ev)
	var valence = "bad" if Rep.kind_weight(ev) < 0 else "good"
	var templates: Array = TONE_TEMPLATES.get("%s_%s" % [tone, valence], TONE_TEMPLATES.plain_good)
	var text = _capitalize(str(templates[seed % templates.size()]) % core)
	if fidelity < HALF_HEARD_BELOW:
		text = "I only half heard it, but " + _decapitalize(text)
	return text

func _status_suffix(ev: Dictionary) -> String:
	match str(ev.status):
		"broken":
			return ", and broke their word"
		"kept":
			return ", and kept their word"
		"exposed":
			return ", and it was a lie"
	if str(ev.kind) == "claim" and ev.truth == "true":
		return ", and it proved true"
	return ""

## The teller's attitude toward the player: fear or dislike darkens a tale, fondness softens it
func _tone_of(who: String) -> String:
	var dims = get_dims(who)
	var fear = float(dims.get("fear", 0))
	var affection = float(dims.get("affection", 0))
	var trust = float(dims.get("trust", 0))
	if fear >= 30 or affection <= -30 or trust <= -40:
		return "dark"
	if affection >= 30:
		return "soft"
	return "plain"

## Relationship dimensions toward the player: a loaded body's, else the relationship ledger's
func get_dims(who: String) -> Dictionary:
	var npc_id = _npc_id_of(who)
	for node in _loaded_nodes(npc_id):
		var dims = {}
		for dim in ["trust", "respect", "affection", "fear", "familiarity"]:
			var v = node.get("relationship_" + dim)
			dims[dim] = float(v) if v != null else 0.0
		return dims
	var gm = _generics()
	if gm and "ledger" in gm and gm.ledger.has_entry(npc_id):
		return gm.ledger.get_dims(npc_id)
	return {}

# =============================================================================
# KNOWLEDGE (what one NPC knows of an event)
# =============================================================================

func _knowledge(ev: Dictionary, who: String) -> Dictionary:
	if who == "":
		return {}
	if _npc_id_of(who) in ev.witnesses:
		return {"id": ev.id, "kind": ev.kind, "status": ev.status, "truth": ev.truth, "about": ev.about.duplicate(),
			"minute": int(ev.minute), "learned": int(ev.minute), "fidelity": 1.0, "how": "witnessed", "from": "",
			"text": compose(ev, "plain", 1.0, 0), "anonymous": false}
	if ev.heard_by.has(who):
		var h: Dictionary = ev.heard_by[who]
		var f = float(h.fidelity)
		return {"id": ev.id, "kind": ev.kind, "status": ev.status, "truth": ev.truth, "about": ev.about.duplicate(),
			"minute": int(ev.minute), "learned": int(h.minute), "fidelity": f, "how": "heard", "from": str(h.from),
			"text": compose(ev, str(h.get("tone", "plain")), f, abs(hash(str(ev.id) + who))), "anonymous": f < ANON_BELOW}
	return {}

## Union of what a set of people know: event id -> {"event": ev, "fidelity": best, "learned": minute}
func knowledge_of(parties: Array) -> Dictionary:
	var result: Dictionary = {}
	var by_id: Dictionary = {}
	for p in parties:
		var who = _who(str(p))
		by_id[_npc_id_of(who)] = who
	for id in order:
		var ev: Dictionary = events[id]
		var best = 0.0
		var learned = int(ev.minute)
		for npc_id in ev.witnesses:
			if by_id.has(str(npc_id)):
				best = 1.0
		if best < 1.0:
			for npc_id in by_id:
				var who = by_id[npc_id]
				if ev.heard_by.has(who) and float(ev.heard_by[who].fidelity) > best:
					best = float(ev.heard_by[who].fidelity)
					learned = int(ev.heard_by[who].minute)
		if best > 0.0:
			result[id] = {"event": ev, "fidelity": best, "learned": learned}
	return result

# =============================================================================
# PROMPT BLOCK ("What you have heard of the stranger")
# =============================================================================

## Compact prompt block: this NPC's most telling known events, fidelity-aware, plus its faction's view
## "" when it knows nothing of the player
func get_heard_block(npc_id: String, max_events: int = PROMPT_MAX_EVENTS) -> String:
	var who = _who(npc_id)
	var known = known_by(who)
	if known.is_empty():
		return ""
	var now = _now()
	known.sort_custom(func(a, b): return _salience(a, now, who) > _salience(b, now, who))
	var block = "## What you have heard of the stranger\n"
	for k in known.slice(0, max_events):
		var tag = "saw it"
		if k.how != "witnessed":
			tag = "rumour" if k.anonymous else ("heard" if float(k.fidelity) >= HALF_HEARD_BELOW else "half-heard")
		var line = "- (%s) %s" % [tag, str(k.text)]
		if line.length() > PROMPT_LINE_MAX:
			line = line.substr(0, PROMPT_LINE_MAX - 3) + "..."
		block += line + "\n"
	var standing = Rep.standing_line(who)
	if standing != "":
		block += standing + "\n"
	return block + "\n"

## What an NPC would bring up first: heavy deeds, open promises (owed), things done to it; fresh and clear
func _salience(k: Dictionary, now: int, who: String = "") -> float:
	var ev: Dictionary = events.get(str(k.id), {})
	var w = absf(Rep.kind_weight(ev)) + 1.0
	if str(ev.get("kind", "")) == "promise" and str(ev.get("status", "")) == "open":
		w = maxf(w, 10.0)
	if who != "" and who in ev.get("about", []):
		w *= 1.5
	var age_days = maxf(now - int(k.learned), 0) / float(MINUTES_PER_DAY)
	return w * (0.2 if k.anonymous else float(k.fidelity)) * maxf(0.25, pow(0.5, age_days / 7.0))

# =============================================================================
# CAPTURE: conversation, commitments, discoveries, arrivals, company
# =============================================================================

## Validate an NPC reply's utterances (analysis.utterances). Returns clean dicts
## {kind, about, summary, believed, flag?, value?, due_day?}; at most MAX_UTTERANCES
func parse_utterances(raw) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for u in raw:
		if result.size() >= MAX_UTTERANCES:
			break
		if not u is Dictionary:
			continue
		var kind = str(u.get("kind", "")).strip_edges().to_lower()
		var summary = _clean_summary(str(u.get("summary", "")))
		if kind not in UTTERANCE_KINDS or summary == "":
			continue
		var about = u.get("about", [])
		if about is String:
			about = [about]
		var clean = {"kind": kind, "summary": summary, "about": about if about is Array else [],
			"believed": u.get("believed", true) != false}
		if u.get("flag") is String and str(u.flag) != "" and StoryFlags.get_flag_description(str(u.flag)) != "":
			clean["flag"] = str(u.flag)
			clean["value"] = u.get("value", true) != false
		if _is_number(u.get("due_day")):
			clean["due_day"] = int(u.due_day)
		result.append(clean)
	return result

## Record what the player said to an NPC, as that NPC heard it. Witnesses: the NPC and everyone
## present where it stands. Returns the new event ids
func record_utterances(npc_id: String, raw, location: String = "") -> Array:
	var ids: Array = []
	var who = _who(npc_id)
	if location == "":
		location = _location_of(who)
	for u in parse_utterances(raw):
		var about: Array = []
		for a in u.about:
			var s = str(a).strip_edges().to_lower()
			about.append(who if s in ["me", "self", "myself", "you", "i"] else str(a))
		var opts = {"location": location, "witnesses": [who], "with_present": true, "source": who, "believed": u.believed}
		if u.has("flag"):
			opts["flag"] = u.flag
			opts["value"] = u.value
		if u.kind == "promise":
			var due = {}
			if u.has("due_day"):
				due["day"] = u.due_day
			if u.has("flag"):
				due["flag"] = u.flag
				due["value"] = u.value
			if not due.is_empty():
				opts["due"] = due
		var id = record(u.kind, u.summary, about, opts)
		if id != "":
			ids.append(id)
	return ids

## Director: the player's choice of a storyline flag (debug "choose", StoryItems, conversation commitments)
func _on_director_decision(entry: Dictionary) -> void:
	if not capture_enabled or str(entry.get("mode", "")) != "player" or str(entry.get("choice", "")) != "player_choice":
		return
	for effect in entry.get("applied", []):
		if effect is Dictionary and str(effect.get("type", "")) == "set_flag":
			_record_commitment(str(effect.get("flag", "")), "")

## Director: a conversation's applied commitments and promises of help, with the NPC who heard them
func _on_conversation_acted(entry: Dictionary) -> void:
	if not capture_enabled:
		return
	var key = str(entry.get("npc", ""))
	for item in entry.get("applied", []):
		if not item is Dictionary:
			continue
		match str(item.get("type", "")):
			"commitment":
				_record_commitment(str(item.get("flag", "")), key)
			"personal_help":
				_record_help_promise(str(item.get("flag", "")), key)

func _record_commitment(flag: String, npc_key: String) -> void:
	if flag == "":
		return
	var existing = events_matching({"kind": "promise", "flag": flag})
	if not existing.is_empty():
		# The same commitment, first seen through player_choice: the NPC who heard it is its witness
		if npc_key != "":
			var ev: Dictionary = events[existing.back().id]
			var npc_id = _npc_id_of(_who(npc_key))
			if npc_id not in ev.witnesses:
				ev.witnesses.append(npc_id)
			ev["source"] = _who(npc_key)
		return
	var opts = {"flag": flag, "value": true, "commitment": flag, "spread": false}
	if npc_key != "":
		opts["witnesses"] = [npc_key]
		opts["with_present"] = true
		opts["source"] = npc_key
		opts["location"] = _location_of(_who(npc_key))
	record("promise", _summary_from_flag(flag), _about_from_flag(flag), opts)

## help:<key>_<arc>_<step>: kept when the step's flag is set, broken if three days pass first
func _record_help_promise(step_flag: String, npc_key: String) -> void:
	if step_flag == "" or not events_matching({"kind": "promise", "flag": step_flag}).is_empty():
		return
	var day = floori(_now() / float(MINUTES_PER_DAY)) + 1
	var who = _who(npc_key)
	record("promise", "promised %s help" % _display_name(who), [who], {"flag": step_flag, "value": true,
		"witnesses": [who], "with_present": true, "source": who, "location": _location_of(who), "spread": false,
		"due": {"flag": step_flag, "value": true, "day": day + 3}})

## StoryItem discoveries (EventBus.world_event item_discovered): seen by whoever is present
func _on_world_event(data: Dictionary) -> void:
	if not capture_enabled or str(data.get("type", "")) != "item_discovered":
		return
	note_discovery(str(data.get("flag", "")), str(data.get("item_id", "")), _player_location())

## Record a discovery as a seen_at deed at this location. Returns its id ("" when no place is known)
func note_discovery(flag: String, item_id: String, location: String) -> String:
	if location == "":
		return ""
	var desc = StoryFlags.get_flag_description(flag) if flag != "" else ""
	var summary = "was seen searching %s; %s" % [_place_name(location), _summary_from_text(desc)] if desc != "" \
		else "was seen examining %s at %s" % [item_id.to_lower() if item_id != "" else "something", _place_name(location)]
	return record("seen_at", summary, _about_from_flag(flag) if flag != "" else [], {"location": location, "spread": false})

## Arrival: everyone present sees the stranger come in
func _on_arrived(location_id: String) -> void:
	if capture_enabled and location_id != "":
		note_arrival(location_id)

## A seen_at for an arrival here, unless one was recorded here within the throttle. Returns its id
func note_arrival(location_id: String) -> String:
	var now = _now()
	if _last_arrival.has(location_id) and now - int(_last_arrival[location_id]) < ARRIVAL_THROTTLE_MINUTES:
		return ""
	if get_present(location_id).is_empty():
		return ""
	_last_arrival[location_id] = now
	return record("seen_at", "was seen at %s" % _place_name(location_id), [], {"location": location_id, "spread": false, "remember": false})

func _on_time_advanced(minutes: int, _total: int, reason: String) -> void:
	process_in_flight()
	check_promises()
	if capture_enabled and not reason.begins_with("travel") and not reason.begins_with("walk"):
		accrue_company(minutes)

## Time near people: one kept_company tick per COMPANY_MINUTES per NPC present. Ticks on the same day
## extend that day's event ("hours") instead of adding another. Returns the event ids that ticked
func accrue_company(minutes: int, location: String = "") -> Array:
	if location == "":
		location = _player_location()
	var ticked: Array = []
	if location == "" or minutes <= 0:
		return ticked
	var present = get_present(location)
	for who in _company.keys():
		if who not in present:
			_company.erase(who)
	var day = floori(_now() / float(MINUTES_PER_DAY)) + 1
	for who in present:
		var total = int(_company.get(who, 0)) + minutes
		var hours = floori(total / float(COMPANY_MINUTES))
		_company[who] = total - hours * COMPANY_MINUTES
		if hours <= 0:
			continue
		var npc_id = _npc_id_of(who)
		var existing = ""
		for id in order:
			var ev: Dictionary = events[id]
			if ev.kind == "kept_company" and ev.witnesses == [npc_id] and int(ev.get("day", 0)) == day:
				existing = id
		if existing != "":
			events[existing]["hours"] = int(events[existing].get("hours", 1)) + hours
			events[existing]["changed_minute"] = _now()
			ticked.append(existing)
			continue
		var id = record("kept_company", "kept company with %s" % _display_name(who), [who],
			{"location": location, "witnesses": [who], "spread": false})
		if id != "":
			events[id]["hours"] = hours
			events[id]["day"] = day
			ticked.append(id)
	return ticked

# =============================================================================
# PEOPLE, PLACES, PRESENCE
# =============================================================================

## Everyone at a location now (who-keys: roster key or generic id): roster NPCs by WorldState,
## generics by the generic manager, and any loaded body standing there. Travellers and the dead are absent
func get_present(location_id: String) -> Array:
	var result: Array = []
	if location_id == "":
		return result
	var registry = _registry()
	var world_state = get_node_or_null("/root/WorldState")
	if registry and world_state:
		for key in registry.get_npc_keys():
			var npc_id = registry.get_npc_id(key)
			if world_state.get_npc_location(npc_id) == location_id and not world_state.is_npc_travelling(npc_id) and world_state.is_npc_alive(npc_id):
				result.append(key)
	var gm = _generics()
	if gm:
		for id in gm.get_present_ids(location_id):
			_append_unique(result, id)
	var propagator = get_node_or_null("/root/EventPropagator")
	if propagator and propagator.has_method("get_npcs_present"):
		for npc in propagator.get_npcs_present(location_id):
			_append_unique(result, _who(str(npc.npc_id)))
	return result

## Everyone who lives (or now is) in a region: roster NPCs by home or location, generics by region
func get_people_in_region(region: String) -> Array:
	var result: Array = []
	if region == "":
		return result
	var registry = _registry()
	if registry:
		for key in registry.get_npc_keys():
			if registry.get_region(registry.get_npc_home(key)) == region or _region_of(_location_of(key)) == region:
				result.append(key)
	var gm = _generics()
	if gm:
		for id in gm.get_ids():
			if str(gm.get_instance(id).region) == region:
				result.append(id)
	return result

## Normal form for a person: roster key ("gregor") for mains, the id itself for generics and others
func _who(x: String) -> String:
	var s = x.strip_edges()
	if s == "":
		return ""
	var registry = _registry()
	var key = registry.get_npc_key(s) if registry else ""
	return key if key != "" else s

func _npc_id_of(who: String) -> String:
	var registry = _registry()
	if registry and registry.has_npc(who):
		return registry.get_npc_id(who)
	return who

func _location_of(who: String) -> String:
	var gm = _generics()
	if gm and gm.is_generic(who):
		return gm.get_location(who)
	var registry = _registry()
	var world_state = get_node_or_null("/root/WorldState")
	if registry and registry.has_npc(who) and world_state:
		return world_state.get_npc_location(registry.get_npc_id(who))
	for node in _loaded_nodes(who):
		if node.has_method("get_current_location"):
			return node.get_current_location()
	return ""

func _is_alive(who: String) -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state == null or world_state.is_npc_alive(_npc_id_of(who))

func _display_name(who: String) -> String:
	var registry = _registry()
	if registry and registry.has_npc(who):
		return str(registry.get_npc_name(who)).split(" ")[0]
	var gm = _generics()
	if gm and gm.is_generic(who):
		var inst = gm.get_instance(who)
		if inst and "name" in inst and str(inst.name) != "":
			return str(inst.name).split(" ")[0]
	return who

func _place_name(location_id: String) -> String:
	var registry = _registry()
	var name = registry.get_location_name(location_id) if registry and location_id != "" else location_id
	return name if name != "" else "somewhere"

func _region_of(location_id: String) -> String:
	var registry = _registry()
	return registry.get_region(location_id) if registry and location_id != "" else ""

func _normalize_about(about: Array) -> Array:
	var result: Array = []
	var gm = _generics()
	var registry = _registry()
	for a in about:
		var who = _who(str(a))
		if who == "" or who.to_lower() in ["player", "stranger"]:
			continue
		if (registry and registry.has_npc(who)) or (gm and gm.is_generic(who)):
			_append_unique(result, who)
	return result

func _about_from_flag(flag: String) -> Array:
	var result: Array = []
	var registry = _registry()
	if registry == null or flag == "":
		return result
	var implicated = str(StoryFlags.IMPLICATED_NPCS.get(flag, ""))
	if implicated != "" and registry.has_npc(implicated):
		result.append(implicated)
	var text = " " + StoryFlags.get_flag_description(flag).to_lower()
	for key in registry.get_npc_keys():
		var first = str(registry.get_npc_name(key)).split(" ")[0].to_lower()
		if first.length() >= 3 and (" " + first) in text and key not in result:
			result.append(key)
	return result.slice(0, 4)

func _summary_from_flag(flag: String) -> String:
	var desc = StoryFlags.get_flag_description(flag)
	return _summary_from_text(desc) if desc != "" else "committed to %s" % flag.replace("_", " ")

## "The player gave Varn their word..." -> "gave Varn their word..."
func _summary_from_text(desc: String) -> String:
	var s = desc.strip_edges().trim_suffix(".")
	for prefix in ["The player ", "the player ", "The stranger ", "the stranger "]:
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return s.substr(0, 1).to_lower() + s.substr(1)

func _clean_summary(text: String) -> String:
	var s = text.strip_edges().replace("\n", " ").trim_suffix(".")
	for prefix in ["the stranger ", "the player ", "player ", "stranger ", "they "]:
		if s.to_lower().begins_with(prefix):
			s = s.substr(prefix.length())
			break
	var registry = _registry()
	if registry and registry.has_method("sanitize_forbidden"):
		s = registry.sanitize_forbidden(s)
	if s.length() > SUMMARY_MAX:
		s = s.substr(0, SUMMARY_MAX - 3).strip_edges() + "..."
	return s.strip_edges()

func _parse_due(due) -> Dictionary:
	if not due is Dictionary:
		return {}
	var result: Dictionary = {}
	if _is_number(due.get("day")):
		result["day"] = int(due.day)
	if due.get("flag") is String and str(due.flag) != "":
		result["flag"] = str(due.flag)
		result["value"] = due.get("value", true) != false
	if due.get("fails") is Array and not due.fails.is_empty():
		result["fails"] = due.fails.map(func(f): return str(f))
	return result

## An int, a float (JSON numbers) or a numeric string
func _is_number(v) -> bool:
	return v is int or v is float or (v is String and v.is_valid_float())

func _player_location() -> String:
	if player_location_override != "":
		return player_location_override
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("get_current_location_id"):
		return scene_manager.get_current_location_id()
	return ""

func _now() -> int:
	if now_override >= 0:
		return now_override
	var world_state = get_node_or_null("/root/WorldState")
	return world_state.get_game_minutes() if world_state else 0

func _flag_value(flag: String) -> bool:
	var world_state = get_node_or_null("/root/WorldState")
	return world_state.get_world_flag(flag) if world_state else false

func _next_id() -> String:
	counter += 1
	var id = "pe_%06d" % counter
	while events.has(id):
		counter += 1
		id = "pe_%06d" % counter
	return id

## RAG / layer dedup key: the id plus a digest of what happened, so a lost save (fresh counter) never
## collides with an older game's memories still in ./chroma
func _source_flag(ev: Dictionary) -> String:
	return SOURCE_PREFIX + str(ev.id) + ":" + (str(ev.summary) + "|" + str(ev.minute)).md5_text().substr(0, 8)

## Keep the log bounded: the oldest seen_at / kept_company go first, then the oldest of anything
func _prune() -> void:
	while order.size() > MAX_EVENTS:
		var victim = ""
		for id in order:
			if events[id].kind in ["seen_at", "kept_company"]:
				victim = id
				break
		if victim == "":
			victim = order[0]
		order.erase(victim)
		events.erase(victim)
		in_flight = in_flight.filter(func(i): return str(i.event) != victim)

func _registry() -> Node:
	return get_node_or_null("/root/WorldRegistry")

func _generics() -> Node:
	var registry = get_node_or_null("/root/DynamicNPCRegistry")
	return registry.generics if registry and "generics" in registry and registry.generics else null

func _loaded_nodes(npc_id: String) -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group("npcs").filter(func(n): return "npc_id" in n and (str(n.npc_id) == npc_id or _who(str(n.npc_id)) == npc_id))

func _append_unique(list: Array, value) -> void:
	if value not in list:
		list.append(value)

func _capitalize(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

func _decapitalize(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if s != "" else s

# =============================================================================
# SAVE / LOAD (inside WorldState's save file, key "player_events")
# =============================================================================

func save() -> Dictionary:
	return {"version": 1, "counter": counter, "order": order.duplicate(), "events": events.duplicate(true),
		"in_flight": in_flight.duplicate(true), "company": _company.duplicate()}

func load_from_dict(data: Dictionary) -> void:
	reset()
	counter = int(data.get("counter", 0))
	var saved: Dictionary = data.get("events", {}) if data.get("events") is Dictionary else {}
	for raw_id in data.get("order", []):
		var id = str(raw_id)
		if not saved.has(id) or not saved[id] is Dictionary:
			continue
		var ev: Dictionary = saved[id].duplicate(true)
		ev["minute"] = int(ev.get("minute", 0))
		ev["changed_minute"] = int(ev.get("changed_minute", ev.minute))
		ev["witnesses"] = ev.get("witnesses", []) if ev.get("witnesses") is Array else []
		ev["heard_by"] = ev.get("heard_by", {}) if ev.get("heard_by") is Dictionary else {}
		ev["about"] = ev.get("about", []) if ev.get("about") is Array else []
		ev["due"] = _parse_due(ev.get("due", {}))
		for field in ["hours", "day"]:
			if ev.has(field):
				ev[field] = int(ev[field])
		for who in ev.heard_by:
			ev.heard_by[who]["minute"] = int(ev.heard_by[who].get("minute", 0))
		events[id] = ev
		order.append(id)
	for item in data.get("in_flight", []):
		if item is Dictionary and events.has(str(item.get("event", ""))):
			var copy: Dictionary = item.duplicate(true)
			copy["at"] = int(copy.get("at", 0))
			in_flight.append(copy)
	var company = data.get("company", {})
	if company is Dictionary:
		for who in company:
			_company[str(who)] = int(company[who])

## Forget everything (new game, tests)
func reset() -> void:
	events.clear()
	order.clear()
	counter = 0
	in_flight.clear()
	_company.clear()
	_last_arrival.clear()
