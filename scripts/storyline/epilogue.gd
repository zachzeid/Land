class_name Epilogue
extends RefCounted
# Epilogue - Epilogues, not endings (docs/WORLD_SCHEMA.md §15)
# Epilogue.generate() reads the world state and assembles, deterministically, from templates:
#   people        one passage per main or promoted NPC the player touched: their state, what they feel
#                 and know of the player, their Life arcs, how they ended
#   places        one per settlement (location area) and per region: storyline state, reputation,
#                 fixed points that moved
#   fixed_points  every calendar point that moved, and why
#   highlights    the authored storyline endings reached, as named highlights
#   intentions    the player's intentions (InnerVoice) set against their deeds (PlayerEvents, choices)
# Epilogue.rewrite() (Claude mode) asks for the same text in the world's voice and keeps it only when
# validate_rewrite() finds no fact outside the state (names, numbers, forbidden concepts); else the
# offline text stands. StorylineDirector.end_game() runs both and emits epilogue_ready
#
# Returns {"title", "trigger", "day", "time", "mode", "people", "places", "fixed_points",
#          "highlights", "intentions", "sections": [{id, heading, text}], "text"}

const NpcAgent = preload("res://scripts/storyline/npc_agent.gd")
const REPUTATION_PATH = "res://scripts/world_state/reputation.gd"
const TOUCH_DIMENSION = 1.0       # any feeling at least this far from 0 means the player touched them
const FEELING_AT = 15.0           # a feeling worth naming
const MAX_INTENTIONS = 10
const POSITIVE_KINDS = ["help", "gift", "spared", "confession"]
const NEGATIVE_KINDS = ["harm", "kill", "theft", "threat", "insult", "lie", "accusation"]
const COMMON_CAPITALS = ["You", "Your", "The", "A", "An", "In", "At", "On", "Of", "And", "But", "When", "Day",
	"It", "He", "She", "They", "His", "Her", "Their", "What", "Who", "Across", "Among", "Nothing", "No", "I"]

## Build the epilogue from the world as it stands. opts: {"trigger": "player"|"season_end"|"debug",
## "director", "world_state", "player_events", "inner_voice", "registry"} (overrides, for tests)
static func generate(opts: Dictionary = {}) -> Dictionary:
	var ctx = _context(opts)
	var director = ctx.director
	var now = int(ctx.world_state.get_game_minutes()) if ctx.world_state else 0
	var epilogue = {
		"title": "What the valley remembers",
		"trigger": str(opts.get("trigger", "player")),
		"day": floori(now / 1440.0) + 1,
		"time": _time_text(now),
		"mode": "offline",
		"people": [], "places": [], "fixed_points": [], "highlights": [], "intentions": [],
	}
	if director == null:
		epilogue["sections"] = []
		epilogue["text"] = ""
		return epilogue
	epilogue.people = _people(ctx)
	epilogue.fixed_points = _fixed_points(ctx)
	epilogue.highlights = _highlights(ctx)
	epilogue.places = _places(ctx, epilogue.fixed_points)
	epilogue.intentions = _intentions(ctx, now)
	var sections: Array = []
	sections.append({"id": "opening", "heading": epilogue.title,
		"text": "It is %s. This is the world you leave behind, as the people in it would tell it." % epilogue.time})
	if not epilogue.highlights.is_empty():
		sections.append({"id": "highlights", "heading": "What came to an end", "text": "\n".join(epilogue.highlights.map(func(h): return h.text))})
	if not epilogue.people.is_empty():
		sections.append({"id": "people", "heading": "The people you touched", "text": "\n\n".join(epilogue.people.map(func(p): return p.text))})
	if not epilogue.places.is_empty():
		sections.append({"id": "places", "heading": "The places", "text": "\n\n".join(epilogue.places.map(func(p): return p.text))})
	if not epilogue.fixed_points.is_empty():
		sections.append({"id": "fixed_points", "heading": "The hours that moved", "text": "\n".join(epilogue.fixed_points.map(func(f): return f.text))})
	var intent_text = "\n".join(epilogue.intentions.map(func(i): return i.text)) if not epilogue.intentions.is_empty() \
		else "You kept your own counsel. Whatever you meant, only your deeds were seen."
	sections.append({"id": "intentions", "heading": "What you meant, and what you did", "text": intent_text})
	epilogue["subtitle"] = sections[0].text
	epilogue["sections"] = sections
	epilogue["text"] = "\n\n".join(sections.map(func(s): return "## %s\n%s" % [s.heading, s.text]))
	return epilogue

# =============================================================================
# CONTEXT
# =============================================================================

static func _context(opts: Dictionary) -> Dictionary:
	var tree = Engine.get_main_loop() as SceneTree
	var root = tree.root if tree else null
	var director = opts.get("director", root.get_node_or_null("StorylineDirector") if root else null)
	var pe = opts.get("player_events", director.get_player_events() if director and director.has_method("get_player_events") else null)
	var voice = opts.get("inner_voice", director.get_inner_voice() if director and director.has_method("get_inner_voice") else null)
	return {
		"director": director,
		"world_state": opts.get("world_state", root.get_node_or_null("WorldState") if root else null),
		"player_events": pe,
		"inner_voice": voice,
		"registry": opts.get("registry", root.get_node_or_null("WorldRegistry") if root else null),
		"events": pe.get_events() if pe and pe.has_method("get_events") else [],
	}

# =============================================================================
# PEOPLE
# =============================================================================

static func _people(ctx: Dictionary) -> Array:
	var director = ctx.director
	var registry = ctx.registry
	var keys: Array = []
	for key in (registry.get_npc_keys() if registry else []):
		if director.has_soul(key):
			keys.append(key)
	var extra: Array = director.get_registered_souls().keys()
	extra.sort()
	for key in extra:
		if key not in keys:
			keys.append(key)
	var out: Array = []
	for key in keys:
		if director.get_soul_tier(key) not in ["main", "promoted"] or not touched(ctx, key):
			continue
		out.append(_person(ctx, key))
	return out

## Did the player touch this NPC? Feelings moved, a player event about or witnessed by them, a
## conversation in which they acted, an emergent beat they were bound into, help promised with their Life
static func touched(ctx: Dictionary, key: String) -> bool:
	var director = ctx.director
	var dims: Dictionary = director.get_relationship_dims(key)
	for dim in dims:
		if absf(float(dims[dim])) >= TOUCH_DIMENSION:
			return true
	var npc_id = director._npc_id(key)
	for ev in ctx.events:
		if key in ev.get("about", []) or npc_id in ev.get("witnesses", []) or ev.get("heard_by", {}).has(key):
			return true
	for entry in director.get_chronicle(0):
		var mode = str(entry.get("mode", ""))
		if mode == "conversation" and str(entry.get("npc", "")) == key:
			return true
		if mode == "emergent" and key in entry.get("roles", {}).values():
			return true
	var soul = director.get_soul(key)
	if soul:
		var arcs: Dictionary = soul.get_life_state().get("arcs", {})
		for arc_id in arcs:
			if not arcs[arc_id].get("helped", []).is_empty():
				return true
	return false

static func _person(ctx: Dictionary, key: String) -> Dictionary:
	var director = ctx.director
	var registry = ctx.registry
	var name = director.get_display_name(key)
	var tier = director.get_soul_tier(key)
	var parts: Array = []
	var alive = director._is_npc_alive(key)
	var here = director.get_npc_location(key)
	var place = registry.get_location_name(here) if registry and registry.has_location(here) else here
	if not alive:
		parts.append("%s did not live to see the end." % name)
	elif place != "":
		parts.append("At the last, %s was at %s." % [name, place])
	else:
		parts.append("%s was still about the valley." % name)
	var dims: Dictionary = director.get_relationship_dims(key)
	parts.append(_feeling_sentence(name, dims))
	var known: Array = []
	if ctx.player_events and ctx.player_events.has_method("known_by"):
		known = ctx.player_events.known_by(key)
	if not known.is_empty():
		var line = "%s had heard of %d thing%s you did" % [_pronoun_name(name), known.size(), "" if known.size() == 1 else "s"]
		var first_text = str(known[0].get("text", "")).strip_edges()
		parts.append(line + (": %s." % first_text.trim_suffix(".") if first_text != "" else "."))
	var rep_line = _reputation_line(ctx, "npc", key, name)
	if rep_line != "":
		parts.append(rep_line)
	var soul = director.get_soul(key)
	var life_lines: Array = []
	if soul:
		for arc in soul.life_arcs:
			var status = soul.get_arc_status(arc.id)
			var arc_name = str(arc.id).replace("_", " ")
			if status == "completed":
				life_lines.append(str(arc.result.text).strip_edges().trim_suffix(".") + ".")
			elif status == "failed":
				life_lines.append("%s gave up on %s." % [name, arc_name])
			else:
				var done = arc.steps.filter(func(s): return soul.is_step_done(arc.id, s.id)).size()
				if done > 0:
					life_lines.append("%s was still working toward %s (%d of %d steps)." % [name, arc_name, done, arc.steps.size()])
	parts.append_array(life_lines)
	var acted = director.get_chronicle(0).filter(func(e): return str(e.get("npc", "")) == key and str(e.get("mode", "")) in ["offline", "claude", "claude_fallback", "emergent"] and str(e.get("choice", "")) not in ["pass", "instantiated", "resolved", "expired"]).size()
	if acted > 0:
		parts.append("%s acted on their own %d time%s while you were in the valley." % [name, acted, "" if acted == 1 else "s"])
	return {"npc": key, "name": name, "tier": tier, "alive": alive, "location": here, "feelings": dims.duplicate(),
		"known": known.size(), "text": " ".join(parts)}

static func _feeling_sentence(name: String, dims: Dictionary) -> String:
	var phrases: Array = []
	var t = float(dims.get("trust", 0.0))
	var a = float(dims.get("affection", 0.0))
	var r = float(dims.get("respect", 0.0))
	var f = float(dims.get("fear", 0.0))
	if t >= FEELING_AT:
		phrases.append("trusted you")
	elif t <= -FEELING_AT:
		phrases.append("did not trust you")
	if a >= FEELING_AT:
		phrases.append("was fond of you")
	elif a <= -FEELING_AT:
		phrases.append("disliked you")
	if r >= FEELING_AT:
		phrases.append("respected you")
	elif r <= -FEELING_AT:
		phrases.append("thought little of you")
	if f >= FEELING_AT:
		phrases.append("feared you")
	if phrases.is_empty():
		return "%s had no settled feeling about you." % name
	if phrases.size() == 1:
		return "%s %s." % [name, phrases[0]]
	return "%s %s and %s." % [name, ", ".join(phrases.slice(0, phrases.size() - 1)), phrases[-1]]

static func _pronoun_name(name: String) -> String:
	return name

static func _reputation_line(ctx: Dictionary, scope: String, id: String, who: String) -> String:
	var score = ctx.director.get_reputation(scope, id)
	if absf(score) < 5.0:
		return ""
	var rep = load(REPUTATION_PATH) if ResourceLoader.exists(REPUTATION_PATH) else null
	var label = str(rep.label(score)) if rep else ("well thought of" if score > 0 else "distrusted")
	return "To %s you were %s." % [who, label]

# =============================================================================
# FIXED POINTS, HIGHLIGHTS, PLACES
# =============================================================================

static func _fixed_points(ctx: Dictionary) -> Array:
	var out: Array = []
	if ctx.world_state == null or not ctx.world_state.has_method("get_calendar"):
		return out
	for entry in ctx.world_state.get_calendar():
		if entry.get("shifts", []).is_empty():
			continue
		var what = str(entry.description).strip_edges().trim_suffix(".")
		var how = ""
		if entry.cancelled:
			how = "it never came"
		elif int(entry.shift_days) > 0:
			how = "it came %d day%s late" % [int(entry.shift_days), "" if int(entry.shift_days) == 1 else "s"]
		elif int(entry.shift_days) < 0:
			how = "it came %d day%s early" % [-int(entry.shift_days), "" if int(entry.shift_days) == -1 else "s"]
		else:
			how = "it was moved, and moved back"
		var reasons: Array = []
		var by_you = false
		for item in entry.shifts:
			if str(item.get("reason", "")) != "" and str(item.reason) not in reasons:
				reasons.append(str(item.reason).strip_edges().trim_suffix("."))
		for row in ctx.director.get_chronicle(0):
			if str(row.get("mode", "")) == "fixed_point" and str(row.get("hook", "")) == entry.flag and str(row.get("npc", "")) == "player":
				by_you = true
		var text = "%s: %s%s." % [what, how, " because of you" if by_you else ""]
		if not reasons.is_empty():
			text += " " + ". ".join(reasons) + "."
		out.append({"point": entry.flag, "shift_days": int(entry.shift_days), "cancelled": entry.cancelled, "fired": entry.fired,
			"by_player": by_you, "reasons": reasons, "text": text})
	return out

static func _highlights(ctx: Dictionary) -> Array:
	var director = ctx.director
	var out: Array = []
	for sid in director.get_storyline_ids():
		var ending_id = director.get_ending(sid)
		if ending_id == "":
			continue
		var storyline: Dictionary = director.get_storyline(sid)
		var ending: Dictionary = {}
		for e in storyline.get("endings", []):
			if e is Dictionary and str(e.get("id", "")) == ending_id:
				ending = e
		var title = str(ending.get("title", ending_id))
		var summary = str(ending.get("summary", "")).strip_edges()
		out.append({"storyline": sid, "storyline_title": str(storyline.get("title", sid)), "ending": ending_id, "title": title,
			"summary": summary, "text": "%s: %s.%s" % [str(storyline.get("title", sid)), title.trim_suffix("."), (" " + summary) if summary != "" else ""]})
	return out

## Where a storyline happens: the area and region most of its beats are set in
static func _storyline_home(ctx: Dictionary, sid: String) -> Dictionary:
	var registry = ctx.registry
	var areas: Dictionary = {}
	var regions: Dictionary = {}
	for beat in ctx.director.get_storyline(sid).get("beats", []):
		var location = str(beat.get("location", "")) if beat is Dictionary else ""
		if registry and registry.has_location(location):
			var area = str(registry.get_area(location))
			var region = str(registry.get_region(location))
			areas[area] = int(areas.get(area, 0)) + 1
			regions[region] = int(regions.get(region, 0)) + 1
	return {"area": _top(areas), "region": _top(regions)}

static func _top(counts: Dictionary) -> String:
	var keys = counts.keys()
	keys.sort()
	var best = ""
	for k in keys:
		if best == "" or int(counts[k]) > int(counts[best]):
			best = k
	return best

static func _places(ctx: Dictionary, fixed_points: Array) -> Array:
	var director = ctx.director
	var registry = ctx.registry
	if registry == null:
		return []
	var by_area: Dictionary = {}   # area -> [storyline lines]
	var area_region: Dictionary = {}
	var by_region: Dictionary = {}  # region -> {"ended": n, "moving": n}
	for sid in director.get_storyline_ids():
		var home = _storyline_home(ctx, sid)
		if home.area == "":
			continue
		var beats: Array = director.get_beats(sid)
		var resolved = beats.filter(func(b): return b.status == "resolved").size()
		var opened = beats.filter(func(b): return b.status != "locked").size()
		var ending = director.get_ending(sid)
		if opened == 0 and ending == "":
			continue
		var title = str(director.get_storyline(sid).get("title", sid))
		var line = ""
		if ending != "":
			line = "%s came to an end" % title
		elif resolved > 0:
			line = "%s was left half-told (%d of %d moments came to pass)" % [title, resolved, beats.size()]
		else:
			line = "%s had only begun" % title
		if not by_area.has(home.area):
			by_area[home.area] = []
		by_area[home.area].append(line)
		area_region[home.area] = home.region
		var r: Dictionary = by_region.get(home.region, {"ended": 0, "open": 0})
		r[("ended" if ending != "" else "open")] += 1
		by_region[home.region] = r
	var points_by_area: Dictionary = {}
	for fp in fixed_points:
		var sid = _storyline_for_point(director, str(fp.point))
		if sid == "":
			continue
		var area = _storyline_home(ctx, sid).area
		if not points_by_area.has(area):
			points_by_area[area] = []
		points_by_area[area].append(fp)
	var out: Array = []
	for region in registry.get_region_ids():
		var areas: Array = by_area.keys().filter(func(a): return area_region[a] == region)
		areas.sort()
		for area in areas:
			var text = "In %s, %s." % [area, "; ".join(by_area[area])]
			for fp in points_by_area.get(area, []):
				text += " " + str(fp.text)
			out.append({"scope": "settlement", "id": area, "region": region, "name": area, "text": text})
		var rep_score = director.get_reputation("region", region)
		var faction_lines: Array = []
		for faction in (registry.data.get("factions", []) if "data" in registry and registry.data is Dictionary else []):
			if faction is Dictionary and str(faction.get("region", "")) == region:
				var line = _reputation_line(ctx, "faction", str(faction.id), str(faction.get("name", faction.id)))
				if line != "":
					faction_lines.append(line)
		if areas.is_empty() and absf(rep_score) < 5.0 and faction_lines.is_empty():
			continue
		var region_name = registry.get_region_name(region)
		var counts: Dictionary = by_region.get(region, {"ended": 0, "open": 0})
		var text = "Across %s, %d stor%s ended and %d %s still unfolding." % [region_name, int(counts.ended), "y" if int(counts.ended) == 1 else "ies",
			int(counts.open), "was" if int(counts.open) == 1 else "were"]
		var region_line = _reputation_line(ctx, "region", region, "the people of " + region_name)
		if region_line != "":
			text += " " + region_line
		if not faction_lines.is_empty():
			text += " " + " ".join(faction_lines)
		out.append({"scope": "region", "id": region, "name": region_name, "reputation": rep_score, "text": text})
	return out

## The storyline a calendar point belongs to: the one whose prefix the point's flag carries
static func _storyline_for_point(director, point: String) -> String:
	for sid in director.get_storyline_ids():
		var prefix = str(director.get_storyline(sid).get("prefix", ""))
		if prefix != "" and point.begins_with(prefix):
			return sid
	return ""

# =============================================================================
# INTENTIONS VERSUS DEEDS
# =============================================================================

## Each intention (newest MAX_INTENTIONS, one per goal) with a verdict: kept | betrayed | abandoned |
## unresolved, from the player's deeds after it: events about its NPCs (help/gift/spared/kept promise
## for, harm/kill/theft/threat/insult/lie/broken promise against), its flags' end state, its storylines' endings
static func _intentions(ctx: Dictionary, now: int) -> Array:
	var voice = ctx.inner_voice
	if voice == null or not voice.has_method("get_history"):
		return []
	var history: Array = voice.get_history()
	var seen: Dictionary = {}
	var chosen: Array = []
	for i in range(history.size() - 1, -1, -1):
		var goal = str(history[i].get("goal", "")).to_lower()
		if seen.has(goal):
			continue
		seen[goal] = true
		chosen.push_front(history[i])
		if chosen.size() >= MAX_INTENTIONS:
			break
	var out: Array = []
	for intention in chosen:
		out.append(_judge(ctx, intention, now))
	return out

static func _judge(ctx: Dictionary, intention: Dictionary, now: int) -> Dictionary:
	var director = ctx.director
	var stance = str(intention.get("stance", "neutral"))
	var sign = -1 if stance == "oppose" else 1
	var since = int(intention.get("minute", 0))
	var score = 0
	var evidence: Array = []
	for item in intention.get("about", []):
		var about = str(item)
		if about.begins_with("npc:"):
			var key = about.substr(4)
			for ev in ctx.events:
				if int(ev.get("minute", 0)) < since or key not in ev.get("about", []):
					continue
				var s = _deed_sign(ev)
				if s == 0:
					continue
				score += s * sign
				if evidence.size() < 2:
					evidence.append(str(ev.get("summary", "")))
		elif about.begins_with("flag:"):
			# The wish is about the fact: it came true (or stayed false, for a "stop it" thought)
			var on = director._flag(about.substr(5))
			var wanted = intention.get("flags_wanted", true) != false
			if on and wanted:
				score += 2
				evidence.append(StoryFlags.get_flag_description(about.substr(5)))
			elif on and not wanted:
				score -= 2
				evidence.append(StoryFlags.get_flag_description(about.substr(5)))
		elif about.begins_with("storyline:"):
			var ending = director.get_ending(about.substr(10))
			if ending != "" and stance == "support":
				score += 1
	var verdict = "unresolved"
	if score > 0:
		verdict = "kept"
	elif score < 0:
		verdict = "betrayed"
	elif now - since >= 2 * 1440:
		verdict = "abandoned"
	var goal = str(intention.get("goal", "")).strip_edges().trim_suffix(".")
	var phrase = {"kept": "You did as you meant to", "betrayed": "Your deeds went the other way",
		"abandoned": "Nothing you did came of it", "unresolved": "It was still before you when it ended"}[verdict]
	var proof = ""
	evidence = evidence.filter(func(e): return str(e).strip_edges() != "")
	if not evidence.is_empty():
		proof = ": " + "; ".join(evidence.map(func(e): return str(e).strip_edges().trim_suffix(".")))
	var text = "On day %d you meant to %s. %s%s." % [int(intention.get("day", 1)), _lower_first(goal), phrase, proof]
	return {"id": str(intention.get("id", "")), "goal": goal, "stance": stance, "day": int(intention.get("day", 1)),
		"verdict": verdict, "score": score, "evidence": evidence, "text": text}

static func _deed_sign(ev: Dictionary) -> int:
	var kind = str(ev.get("kind", ""))
	if kind == "promise":
		return 1 if str(ev.get("status", "")) == "kept" else (-1 if str(ev.get("status", "")) == "broken" else 0)
	if kind in POSITIVE_KINDS:
		return 1
	if kind in NEGATIVE_KINDS:
		return -1
	return 0

# =============================================================================
# CLAUDE REWRITE (optional; validated)
# =============================================================================

## Ask Claude for the epilogue in the world's voice. Kept only when validate_rewrite() passes; otherwise
## the offline text stands and mode says why ("claude_rejected" / "claude_fallback")
static func rewrite(epilogue: Dictionary, client: Object, tree: SceneTree = null) -> Dictionary:
	var out: Dictionary = epilogue.duplicate(true)
	if client == null:
		out["mode"] = "claude_fallback"
		out["rewrite_reason"] = "no Claude client"
		return out
	var agent = NpcAgent.new()
	agent.client = client
	agent.tree = tree
	if not agent._has_api_key():
		out["mode"] = "claude_fallback"
		out["rewrite_reason"] = "no API key"
		return out
	var system = "You are the voice of the world of a role-playing game, telling the player how their story ended. " \
		+ "Rewrite the epilogue below as warm, plain prose in the same sections and order, keeping every '## ' heading. " \
		+ "Use ONLY the facts given: add no names, places, numbers or events that are not in it. Respond with the epilogue text only."
	var response = await agent._send_with_timeout([{"role": "user", "content": str(epilogue.text)}], system)
	if response.has("error"):
		out["mode"] = "claude_fallback"
		out["rewrite_reason"] = "Claude error: %s" % response.error
		return out
	var text = str(response.get("text", "")).strip_edges()
	var checked = validate_rewrite(text, epilogue)
	if not checked.ok:
		out["mode"] = "claude_rejected"
		out["rewrite_reason"] = checked.reason
		return out
	out["offline_text"] = epilogue.text
	out["text"] = text
	out["mode"] = "claude"
	return out

## Does a rewrite stay within the facts? Every capitalised word (not starting a sentence) and every
## number must appear in the offline epilogue; no forbidden concept; every heading kept; sane length
static func validate_rewrite(text: String, epilogue: Dictionary) -> Dictionary:
	var source = str(epilogue.get("text", ""))
	if text.strip_edges() == "":
		return {"ok": false, "reason": "empty rewrite"}
	if text.length() < int(source.length() * 0.3) or text.length() > int(source.length() * 2.5) + 200:
		return {"ok": false, "reason": "length out of bounds"}
	for section in epilogue.get("sections", []):
		if not ("## " + str(section.heading)) in text:
			return {"ok": false, "reason": "heading '%s' missing" % section.heading}
	var lower_source = source.to_lower()
	var number_re = RegEx.create_from_string("\\d+")
	for m in number_re.search_all(text):
		if not m.get_string() in source:
			return {"ok": false, "reason": "number %s is not in the state" % m.get_string()}
	var sentence_start_re = RegEx.create_from_string("(^|[.!?:\\n#\"]\\s*)$")
	for m in RegEx.create_from_string("\\b[A-Z][a-zA-Z']+").search_all(text):
		var word = m.get_string()
		var before = text.substr(maxi(0, m.get_start() - 3), mini(3, m.get_start()))
		if sentence_start_re.search(before) != null or m.get_start() == 0:
			continue
		if word in COMMON_CAPITALS:
			continue
		if not word.to_lower().trim_suffix("'s") in lower_source:
			return {"ok": false, "reason": "'%s' is not in the state" % word}
	var tree = Engine.get_main_loop() as SceneTree
	var registry = tree.root.get_node_or_null("WorldRegistry") if tree and tree.root else null
	if registry and registry.has_method("contains_forbidden_concept") and registry.contains_forbidden_concept(text):
		return {"ok": false, "reason": "a forbidden concept"}
	return {"ok": true, "reason": ""}

# =============================================================================

static func _time_text(minute: int) -> String:
	return "day %d, %02d:%02d" % [floori(minute / 1440.0) + 1, floori((minute % 1440) / 60.0), minute % 60]

static func _lower_first(text: String) -> String:
	if text.length() < 2:
		return text.to_lower()
	return text.substr(0, 1).to_lower() + text.substr(1) if text.substr(1, 1) == text.substr(1, 1).to_lower() else text
