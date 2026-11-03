extends Node
# InnerVoice - The player's private thoughts (docs/WORLD_SCHEMA.md §13)
# think(text) parses a thought into an intention {goal, about[], stance, strength}. Offline: keyword
# matching against NPC names, flags, storyline titles, beat and hook text, Life arcs and emergent
# templates. Claude mode may refine the parse afterwards; the result is validated against known ids.
#
# NPCs NEVER see a thought: nothing here writes to a prompt, memory, gossip, agenda, WorldEvents,
# PlayerEvents or the chronicle. Thoughts only steer the StorylineDirector by numbers:
#   score_target(target)  how much the active intentions concern a hook / Life step / template (boost)
#   pressure_for(npc)     how much this NPC's wants oppose the active intentions (they act sooner)
# and are kept (history) for the epilogue, which sets them against the player's deeds.
#
# about[] entries are typed ids: npc:<key>, storyline:<id>, beat:<sid>/<beat>, hook:<sid>/<hook>,
# flag:<flag>, arc:<npc>/<arc>, template:<emergence template id>
# stance: support | oppose | curious | neutral; strength 0.1..1.0

signal intention_formed(intention: Dictionary)
signal intention_refined(intention: Dictionary)   # Claude mode replaced the offline parse

const STANCES = ["support", "oppose", "curious", "neutral"]
const MAX_HISTORY = 200
const ACTIVE_WINDOW = 6           # the most recent intentions that steer
const NEWER_DECAY = 0.6           # each newer thought weakens an older one by this factor
const STALE_DAYS = 3.0            # older than this (game days): weight halves
const MIN_WEIGHT = 0.05
const MAX_ABOUT = 8
const MAX_GOAL_CHARS = 120
const MAX_TEXT_CHARS = 500
const STRUCTURED_MATCH = 0.5      # per typed about-id the target carries
const KEYWORD_MATCH = 0.25        # per shared content word
const KEYWORD_CAP = 0.5

const SUPPORT_WORDS = ["save", "help", "protect", "free", "rescue", "defend", "support", "aid", "heal", "cure",
	"warn", "spare", "trust", "befriend", "guard", "shelter", "keep", "marry", "love", "side", "join", "ally",
	"comfort", "feed", "hide", "find", "bring", "return", "give", "forgive", "pay", "follow"]
const OPPOSE_WORDS = ["stop", "kill", "expose", "betray", "ruin", "destroy", "fight", "prevent", "punish",
	"unmask", "accuse", "rob", "steal", "hurt", "harm", "avenge", "revenge", "sabotage", "defeat", "confront",
	"oppose", "murder", "frame", "blackmail", "threaten", "break", "burn", "end", "trick", "deceive", "fool", "cheat", "refuse"]
const CURIOUS_WORDS = ["learn", "discover", "understand", "know", "ask", "wonder", "watch", "see", "investigate",
	"why", "who", "what", "suspect", "figure", "search", "look"]
## Verbs that mean "make it not happen": a flag such a thought matches is one the player wants to stay false
const PREVENT_WORDS = ["stop", "prevent", "oppose", "sabotage", "refuse", "defeat", "break", "end"]
const NEGATIONS = ["not", "never", "no", "dont", "don't", "won't", "wont", "cannot", "can't", "cant"]
const INTENSIFIERS = ["must", "will", "swear", "need", "vow", "promise", "whatever", "absolutely", "definitely", "now", "tonight"]
const HEDGES = ["maybe", "might", "perhaps", "could", "possibly", "unsure", "if", "should"]
const STOPWORDS = ["the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "from", "by",
	"is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "i", "me", "my",
	"we", "us", "our", "you", "your", "he", "him", "his", "she", "her", "they", "them", "their", "will", "would",
	"can", "could", "should", "must", "have", "has", "had", "do", "does", "did", "not", "no", "so", "then",
	"than", "there", "here", "what", "who", "why", "how", "when", "where", "which", "all", "any", "some",
	"one", "into", "out", "up", "down", "about", "over", "before", "after", "again", "just", "only", "very",
	"want", "going", "get", "make", "need", "think", "know", "let", "if", "maybe", "might", "player", "stranger",
	"came", "come", "went", "being", "still", "even", "like", "more", "most", "much", "other", "own"]

var mode: String = ""             # "" follows StorylineDirector.agency_mode; "offline" | "claude"
var director_override: Node = null
var client_override: Object = null
var claude_timeout: float = 15.0

var _history: Array = []          # intentions, oldest first (each carries id, text, minute, day, mode)
var _seq: int = 0
var _opposition_cache: Dictionary = {}   # "intention id|round" -> {npc key: score}

func _ready():
	var world_state = get_node_or_null("/root/WorldState")
	if world_state and "inner_voice_state" in world_state and world_state.inner_voice_state is Dictionary and not world_state.inner_voice_state.is_empty():
		load_from_dict(world_state.inner_voice_state)
	print("InnerVoice initialized (%d intentions)" % _history.size())

# =============================================================================
# THINKING
# =============================================================================

## Parse a thought into an intention and remember it. Returns
## {"id", "text", "goal", "about": [typed ids], "stance", "strength", "keywords", "minute", "day", "mode"}
## ({} for an empty thought). In Claude mode an async refinement may replace it later (intention_refined)
func think(text: String) -> Dictionary:
	var intention = _remember(parse_offline(text))
	if intention.is_empty():
		return {}
	if _mode() == "claude":
		_refine.call_deferred(intention.id)
	return intention.duplicate(true)

## Like think(), but waits for the Claude refinement in Claude mode (offline parse when it fails)
func think_async(text: String) -> Dictionary:
	var intention = _remember(parse_offline(text))
	if intention.is_empty():
		return {}
	if _mode() == "claude":
		await _refine(intention.id)
	return get_intention(intention.id)

func _remember(intention: Dictionary) -> Dictionary:
	if intention.is_empty():
		return {}
	_seq += 1
	intention["id"] = "th_%d" % _seq
	var now = _now()
	intention["minute"] = now
	intention["day"] = floori(now / 1440.0) + 1
	intention["mode"] = "offline"
	_history.append(intention)
	if _history.size() > MAX_HISTORY:
		_history = _history.slice(_history.size() - MAX_HISTORY)
	_opposition_cache.clear()
	print("[InnerVoice] %s: %s (%s, %.2f) about %s" % [intention.id, intention.goal, intention.stance, intention.strength, intention.about])
	intention_formed.emit(intention.duplicate(true))
	return intention

## The deterministic parse (no memory, no side effects)
func parse_offline(text: String) -> Dictionary:
	var raw = text.strip_edges().substr(0, MAX_TEXT_CHARS)
	if raw == "":
		return {}
	var words: Array = _words(raw)
	var lower = " " + " ".join(words) + " "
	var about: Array = []
	var npc_names: Dictionary = {}  # key -> display name found
	for entry in _npc_names():
		for name in entry.names:
			if (" %s " % name) in lower:
				_add(about, "npc:" + entry.key)
				npc_names[entry.key] = entry.display
				break
	var content: Array = _content_words(words)
	var director = _director()
	if director:
		_match_storylines(director, lower, content, about)
		_match_flags(director, lower, content, about)
		_match_arcs(director, content, about)
		_match_templates(director, content, about)
	var stance_info = _stance(words)
	var strength = 0.5
	for w in words:
		if w in INTENSIFIERS:
			strength += 0.15
		elif w in HEDGES:
			strength -= 0.15
	if "!" in raw:
		strength += 0.1
	strength = clampf(strength, 0.1, 1.0)
	var goal = _clip(raw, MAX_GOAL_CHARS)
	if stance_info.verb != "":
		var target = ""
		for item in about:
			if item.begins_with("npc:"):
				target = npc_names.get(item.substr(4), item.substr(4))
				break
		if target != "":
			goal = ("%s%s %s" % ["not " if stance_info.negated else "", stance_info.verb, target]).strip_edges()
	# The flags it names: does the player want them to come true? (no, after a negation or a "stop" verb)
	var wants_flags = not ((stance_info.verb in PREVENT_WORDS) != stance_info.negated)
	return {"text": raw, "goal": _clip(goal, MAX_GOAL_CHARS), "about": about.slice(0, MAX_ABOUT),
		"stance": stance_info.stance, "strength": snappedf(strength, 0.01), "keywords": content.slice(0, 12),
		"flags_wanted": wants_flags}

func _stance(words: Array) -> Dictionary:
	for i in words.size():
		var w: String = words[i]
		var stance = ""
		if w in SUPPORT_WORDS:
			stance = "support"
		elif w in OPPOSE_WORDS:
			stance = "oppose"
		if stance == "":
			continue
		var negated = false
		for j in range(maxi(0, i - 2), i):
			if words[j] in NEGATIONS:
				negated = true
		if negated:
			stance = "oppose" if stance == "support" else "support"
		return {"stance": stance, "verb": w, "negated": negated}
	for w in words:
		if w in CURIOUS_WORDS:
			return {"stance": "curious", "verb": "", "negated": false}
	return {"stance": "neutral", "verb": "", "negated": false}

func _match_storylines(director: Node, lower: String, content: Array, about: Array) -> void:
	for sid in director.get_storyline_ids():
		var storyline: Dictionary = director.get_storyline(sid)
		var title_words = _content_words(_words(str(storyline.get("title", ""))))
		if (" %s " % str(sid).replace("_", " ")) in lower or (not title_words.is_empty() and title_words.all(func(w): return w in content)):
			_add(about, "storyline:" + sid)
		for beat in storyline.get("beats", []):
			if not beat is Dictionary:
				continue
			var beat_words = _content_words(_words(str(beat.get("title", ""))))
			if (beat_words.size() >= 2 and beat_words.all(func(w): return w in content)) or _overlap(content, _content_words(_words(str(beat.get("summary", ""))))) >= 3:
				_add(about, "beat:%s/%s" % [sid, beat.get("id", "")])
			for hook in beat.get("hooks", []):
				if hook is Dictionary and _overlap(content, _content_words(_words(str(hook.get("situation", ""))))) >= 3:
					_add(about, "hook:%s/%s" % [sid, hook.get("id", "")])

func _match_flags(director: Node, lower: String, content: Array, about: Array) -> void:
	var scored: Array = []
	var flags: Array = director._declared_flags.keys() if "_declared_flags" in director else []
	for flag in StoryFlags.get_calendar_flags():
		if flag not in flags:
			flags.append(flag)
	for flag in StoryFlags.get_discovery_flags():
		if flag not in flags:
			flags.append(flag)
	for flag in director.get_personal_flags():
		if flag not in flags:
			flags.append(flag)
	for flag in flags:
		var f = str(flag)
		if (" %s " % f) in lower:
			scored.append([100, f])
			continue
		var id_words = _content_words(_words(" ".join(f.split("_").slice(1))))  # the id without its prefix
		var id_hit = id_words.size() >= 2 and id_words.all(func(w): return w in content)
		var overlap = _overlap(content, _content_words(_words(StoryFlags.get_flag_description(f))))
		if id_hit or overlap >= 3:
			scored.append([overlap + (10 if id_hit else 0), f])
	scored.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for pair in scored.slice(0, 3):
		_add(about, "flag:" + pair[1])

func _match_arcs(director: Node, content: Array, about: Array) -> void:
	var keys = director.get_soul_keys()
	keys.sort()
	for key in keys:
		var soul = director.get_soul(key)
		if soul == null:
			continue
		for arc in soul.life_arcs:
			var text = "%s %s" % [str(arc.id).replace("_", " "), str(arc.get("prose", ""))]
			for step in arc.steps:
				text += " " + str(step.text)
			if _overlap(content, _content_words(_words(text))) >= 2:
				_add(about, "arc:%s/%s" % [key, arc.id])

func _match_templates(director: Node, content: Array, about: Array) -> void:
	if not director.has_method("get_emergence"):
		return
	var emergence = director.get_emergence()
	for tid in emergence.template_order:
		var t: Dictionary = emergence.templates[tid]
		var title_words = _content_words(_words(str(t.get("title", ""))))
		if (not title_words.is_empty() and title_words.all(func(w): return w in content)) or _overlap(content, _content_words(_words(str(t.get("summary", ""))))) >= 3:
			_add(about, "template:" + tid)

# =============================================================================
# CLAUDE REFINEMENT (validated; the offline parse stands on any problem)
# =============================================================================

func _refine(intention_id: String) -> void:
	var client = _client()
	var index = _index_of(intention_id)
	if client == null or index < 0:
		return
	var intention: Dictionary = _history[index]
	var system = "You read a player's private thought in a role-playing game and state the intention in it. " \
		+ "Respond with ONLY JSON: {\"goal\": \"<= 12 words\", \"about\": [ids from the list], \"stance\": \"support|oppose|curious|neutral\", \"strength\": 0.1-1.0}"
	var user = "Thought: %s\nKnown ids (use only these): %s" % [intention.text, ", ".join(known_ids().slice(0, 160))]
	var response = await _send(client, [{"role": "user", "content": user}], system)
	var checked = validate_refinement(str(response.get("text", "")) if response is Dictionary else "")
	index = _index_of(intention_id)
	if index < 0:
		return
	if not checked.ok:
		_history[index]["mode"] = "claude_fallback"
		_history[index]["fallback_reason"] = str(checked.get("reason", "no response"))
		return
	var refined: Dictionary = _history[index].merged(checked.intention, true)
	refined["mode"] = "claude"
	_history[index] = refined
	_opposition_cache.clear()
	intention_refined.emit(refined.duplicate(true))

## Validate a Claude parse: JSON with a goal (<= 120 chars), about ids that exist, a known stance,
## strength 0..1 (clamped). Unknown about ids are dropped. Returns {"ok", "intention", "reason"}
func validate_refinement(text: String) -> Dictionary:
	var start = text.find("{")
	var finish = text.rfind("}")
	if start == -1 or finish <= start:
		return {"ok": false, "reason": "not JSON"}
	var data = JSON.parse_string(text.substr(start, finish - start + 1))
	if not data is Dictionary or not data.get("goal") is String or str(data.goal).strip_edges() == "":
		return {"ok": false, "reason": "no goal"}
	if str(data.get("stance", "")) not in STANCES:
		return {"ok": false, "reason": "unknown stance '%s'" % data.get("stance", "")}
	if not (data.get("strength") is float or data.get("strength") is int):
		return {"ok": false, "reason": "strength is not a number"}
	var known: Array = known_ids()
	var about: Array = []
	for item in data.get("about", []) if data.get("about") is Array else []:
		if str(item) in known and str(item) not in about:
			about.append(str(item))
	return {"ok": true, "reason": "", "intention": {"goal": _clip(str(data.goal), MAX_GOAL_CHARS), "about": about.slice(0, MAX_ABOUT),
		"stance": str(data.stance), "strength": snappedf(clampf(float(data.strength), 0.1, 1.0), 0.01)}}

## Every typed id an intention may be about
func known_ids() -> Array:
	var ids: Array = []
	for entry in _npc_names():
		ids.append("npc:" + entry.key)
	var director = _director()
	if director == null:
		return ids
	for sid in director.get_storyline_ids():
		ids.append("storyline:" + sid)
		for beat in director.get_storyline(sid).get("beats", []):
			if beat is Dictionary:
				ids.append("beat:%s/%s" % [sid, beat.get("id", "")])
				for hook in beat.get("hooks", []):
					if hook is Dictionary:
						ids.append("hook:%s/%s" % [sid, hook.get("id", "")])
		for flag in director.get_storyline(sid).get("flags", {}):
			ids.append("flag:" + str(flag))
	for flag in StoryFlags.get_calendar_flags():
		ids.append("flag:" + str(flag))
	for key in director.get_soul_keys():
		var soul = director.get_soul(key)
		for arc in soul.life_arcs if soul else []:
			ids.append("arc:%s/%s" % [key, arc.id])
	if director.has_method("get_emergence"):
		for tid in director.get_emergence().template_order:
			ids.append("template:" + tid)
	return ids

func _send(client: Object, messages: Array, system_prompt: String) -> Dictionary:
	var done = {"value": null}
	var runner = func():
		done.value = await client.send_message(messages, system_prompt)
	runner.call()
	var waited = 0.0
	while done.value == null and waited < claude_timeout and is_inside_tree():
		await get_tree().process_frame
		waited += 0.016
	return done.value if done.value is Dictionary else {"error": "timeout"}

# =============================================================================
# STEERING (read by StorylineDirector; numbers only)
# =============================================================================

func has_active_intentions() -> bool:
	return not get_active_intentions().is_empty()

## The intentions that steer now, newest first, each with "weight":
## strength × 0.6^(newer thoughts) × (0.5 when older than 3 game days); below 0.05 they stop steering
func get_active_intentions() -> Array:
	var out: Array = []
	var now = _now()
	var newer = 0
	for i in range(_history.size() - 1, -1, -1):
		if newer >= ACTIVE_WINDOW:
			break
		var intention: Dictionary = _history[i]
		var w = float(intention.strength) * pow(NEWER_DECAY, newer)
		if now - int(intention.get("minute", now)) > int(STALE_DAYS * 1440):
			w *= 0.5
		newer += 1
		if w < MIN_WEIGHT or (intention.get("about", []).is_empty() and intention.get("keywords", []).is_empty()):
			continue
		out.append(intention.merged({"weight": w}))
	return out

## Boost for a target: Σ over active intentions of weight × relevance, relevance =
## min(1, 0.5 per typed id it shares + min(0.5, 0.25 per shared content word)).
## target: {"npcs": [keys], "storyline", "beat", "hook", "flags": [], "arc": "npc/arc", "template", "text"}
func score_target(target: Dictionary) -> float:
	var total = 0.0
	var ids = _target_ids(target)
	var words = _content_words(_words(str(target.get("text", ""))))
	for intention in get_active_intentions():
		var rel = 0.0
		for item in intention.get("about", []):
			if str(item) in ids:
				rel += STRUCTURED_MATCH
		rel += minf(KEYWORD_CAP, KEYWORD_MATCH * _overlap(intention.get("keywords", []), words))
		total += float(intention.weight) * minf(1.0, rel)
	return snappedf(total, 0.001)

func _target_ids(target: Dictionary) -> Array:
	var ids: Array = []
	for key in target.get("npcs", []):
		ids.append("npc:" + str(key))
	var sid = str(target.get("storyline", ""))
	if sid != "":
		ids.append("storyline:" + sid)
		if str(target.get("beat", "")) != "":
			ids.append("beat:%s/%s" % [sid, target.beat])
		if str(target.get("hook", "")) != "":
			ids.append("hook:%s/%s" % [sid, target.hook])
	for flag in target.get("flags", []):
		if str(flag) != "":
			ids.append("flag:" + str(flag))
	if str(target.get("arc", "")) != "":
		ids.append("arc:" + str(target.arc))
	if str(target.get("template", "")) != "":
		ids.append("template:" + str(target.template))
	return ids

## Pressure on one NPC: Σ over active intentions of weight × min(1, opposition / 10)
func pressure_for(npc: String) -> float:
	var director = _director()
	var key = director._npc_key(npc) if director else npc
	var total = 0.0
	for intention in get_active_intentions():
		var opp: Dictionary = get_opposition(intention)
		total += float(intention.weight) * minf(1.0, float(opp.get(key, 0.0)) / 10.0)
	return snappedf(total, 0.001)

## Who opposes an intention, and how much: npc key -> score. An NPC opposes when an option it is
## eligible for (in a beat not resolved) works against the intention: it sets an about-flag the other
## way, blocks a beat of an about-storyline/beat or one resolving on an about-flag, harms someone the
## player means to support, or aids someone the player means to oppose. Score = Σ want weight the option
## serves (at least 1). The target of an "oppose" intention always opposes it (10)
func get_opposition(intention: Dictionary) -> Dictionary:
	var director = _director()
	if director == null:
		return {}
	var cache_key = "%s|%d" % [intention.get("id", ""), director.get_round()]
	if _opposition_cache.has(cache_key):
		return _opposition_cache[cache_key]
	var dir = 1 if intention.get("stance", "") == "support" else (-1 if intention.get("stance", "") == "oppose" else 0)
	var about: Array = intention.get("about", [])
	var opp: Dictionary = {}
	if dir != 0:
		for sid in director.get_storyline_ids():
			for beat in director.get_storyline(sid).get("beats", []):
				if not beat is Dictionary or director.get_beat_status(sid, str(beat.get("id", ""))) == "resolved":
					continue
				for hook in beat.get("hooks", []):
					if not hook is Dictionary:
						continue
					for option in hook.get("options", []):
						if not option is Dictionary:
							continue
						var a = _alignment(director, option, about, dir, intention.get("flags_wanted", true) != false)
						if a >= 0:
							continue
						for key in hook.get("eligible", []):
							var soul = director.get_soul(str(key))
							var weight = maxf(1.0, float(soul.score_wants(option.get("serves", []))) if soul else 1.0)
							opp[str(key)] = float(opp.get(str(key), 0.0)) + weight * float(-a)
		if dir == -1:
			for item in about:
				if str(item).begins_with("npc:"):
					opp[str(item).substr(4)] = float(opp.get(str(item).substr(4), 0.0)) + 10.0
	_opposition_cache[cache_key] = opp
	return opp

func _alignment(director: Node, option: Dictionary, about: Array, dir: int, flags_wanted: bool = true) -> int:
	var a = 0
	var flag_dir = 1 if flags_wanted else -1  # flags: the wish is about the fact, whatever the verb's stance
	for effect in option.get("effects", []):
		if not effect is Dictionary:
			continue
		match str(effect.get("type", "")):
			"set_flag":
				if ("flag:" + str(effect.get("flag", ""))) in about:
					a += flag_dir if effect.get("value", true) == true else -flag_dir
			"block_beat", "unlock_beat":
				var sign = -1 if effect.type == "block_beat" else 1
				var beat: Dictionary = director._find_beat(str(effect.get("storyline", "")), str(effect.get("beat", "")))
				var touches = ("storyline:" + str(effect.get("storyline", ""))) in about or ("beat:%s/%s" % [effect.get("storyline", ""), effect.get("beat", "")]) in about
				var flag_touch = false
				for f in beat.get("resolves_on", []):
					if ("flag:" + str(f)) in about:
						flag_touch = true
				if flag_touch:
					a += sign * flag_dir
				elif touches:
					a += sign * dir
	var harms = option.get("harms", [])
	for victim in (harms if harms is Array else [harms]):
		if ("npc:" + str(victim).to_lower()) in about:
			a -= dir
	if str(option.get("aids", "")) != "" and ("npc:" + str(option.aids).to_lower()) in about:
		a += dir
	return a

# =============================================================================
# HISTORY, SAVE
# =============================================================================

## Every intention, oldest first (copies). The epilogue reads this; NPCs never do
func get_history() -> Array:
	return _history.duplicate(true)

func get_intention(intention_id: String) -> Dictionary:
	var i = _index_of(intention_id)
	return _history[i].duplicate(true) if i >= 0 else {}

func clear() -> void:
	_history.clear()
	_seq = 0
	_opposition_cache.clear()

func save() -> Dictionary:
	return {"history": _history.duplicate(true), "seq": _seq}

func load_from_dict(data: Dictionary) -> void:
	clear()
	if not data is Dictionary:
		return
	for item in data.get("history", []):
		if item is Dictionary and item.has("goal"):
			var copy: Dictionary = item.duplicate(true)
			copy["strength"] = float(copy.get("strength", 0.5))
			copy["minute"] = int(copy.get("minute", 0))
			copy["day"] = int(copy.get("day", 1))
			_history.append(copy)
	_seq = int(data.get("seq", _history.size()))

# =============================================================================
# INTERNALS
# =============================================================================

func _mode() -> String:
	if mode != "":
		return mode
	var director = _director()
	return str(director.agency_mode) if director and "agency_mode" in director else "offline"

func _client() -> Object:
	if client_override != null:
		return client_override
	var director = _director()
	return director.get_claude_client_for_agents() if director and director.has_method("get_claude_client_for_agents") else null

func _director() -> Node:
	if director_override != null:
		return director_override
	return get_node_or_null("/root/StorylineDirector") if is_inside_tree() else null

func _now() -> int:
	var world_state = get_node_or_null("/root/WorldState") if is_inside_tree() else null
	return int(world_state.get_game_minutes()) if world_state else 0

func _index_of(intention_id: String) -> int:
	for i in _history.size():
		if str(_history[i].get("id", "")) == intention_id:
			return i
	return -1

## [{key, display, names: [lowercase whole-word forms]}] for roster NPCs and registered souls
func _npc_names() -> Array:
	var out: Array = []
	var registry = get_node_or_null("/root/WorldRegistry") if is_inside_tree() else null
	var keys: Array = registry.get_npc_keys() if registry else []
	var director = _director()
	if director:
		for key in director.get_registered_souls():
			if key not in keys:
				keys.append(key)
	for key in keys:
		var display = registry.get_npc_name(key) if registry and registry.has_npc(key) else (director.get_display_name(key) if director else str(key))
		var names: Array = []
		var parts = display.to_lower().split(" ", false)
		if not parts.is_empty() and parts[0].length() >= 3 and parts[0] not in ["the", "old", "elder", "brother", "sister", "lord", "lady", "captain", "master", "mother", "father"]:
			names.append(_clean(parts[0]))
		for part in parts.slice(1):
			if part.length() >= 4:
				names.append(_clean(part))
		if not "_" in str(key):
			names.append(str(key))
		out.append({"key": str(key), "display": display, "names": names})
	return out

func _words(text: String) -> Array:
	var out: Array = []
	for raw in text.to_lower().replace("'s", "").replace("-", " ").split(" ", false):
		var w = _clean(raw)
		if w != "":
			out.append(w)
	return out

func _clean(word: String) -> String:
	var re = RegEx.create_from_string("[^a-z0-9_']")
	return re.sub(word, "", true).trim_prefix("'").trim_suffix("'")

## Content words, crudely stemmed: no stopwords, at least 3 letters
func _content_words(words: Array) -> Array:
	var out: Array = []
	for w in words:
		if w.length() < 3 or w in STOPWORDS:
			continue
		var stem = _stem(w)
		if stem not in out:
			out.append(stem)
	return out

func _stem(w: String) -> String:
	for suffix in ["ing", "ed", "es", "s"]:
		if w.length() > 5 and w.ends_with(suffix):
			return w.substr(0, w.length() - suffix.length())
	return w

func _overlap(a: Array, b: Array) -> int:
	var n = 0
	for w in a:
		if w in b:
			n += 1
	return n

func _add(list: Array, item: String) -> void:
	if item not in list:
		list.append(item)

func _clip(text: String, max_chars: int) -> String:
	var flat = text.replace("\n", " ").strip_edges()
	return flat if flat.length() <= max_chars else flat.substr(0, max_chars - 3) + "..."
