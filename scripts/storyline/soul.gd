extends RefCounted
# Soul - One NPC's SOUL.md, parsed into what the storyline runtime needs
# Wants carry runtime weights that drift as flags turn true (the file is never rewritten)
# permits() is the single gate every NPC-caused effect must pass (docs/WORLD_SCHEMA.md §3)

const HOOK_TYPES = ["intercept", "react", "scheme", "reveal", "aid", "betray"]
## Conversation is not a hook type: a `converse:` Agency line grants what the soul may do while
## talking; without one it falls back to the union of these grants (docs/WORLD_SCHEMA.md §6)
const CONVERSE = "converse"
const CONVERSE_FALLBACK = ["react", "reveal", "aid"]
## Personal arcs (docs/WORLD_SCHEMA.md §8, `## Life`): steps may only use these effect types,
## never set_flag, block_beat or unlock_beat. A `hook:personal` line forbids personal acts outright
const PERSONAL = "personal"
const PERSONAL_EFFECTS = ["agenda", "move_npc", "adjust_relationship", "shift_want", "spread_rumor"]
const STEP_FIELDS = ["after", "needs", "at", "takes", "effects", "when", "player"]
const TimeWindow = preload("res://scripts/storyline/time_window.gd")
const STEP_REQUIRED = ["after", "needs", "at", "takes", "effects"]
const MAX_TAKES = 6

var npc_key: String = ""
var npc_id: String = ""
var display_name: String = ""
var essence: String = ""
var voice: String = ""
var secrets: String = ""
var fears: Array = []          # prose bullets
var wants: Dictionary = {}     # want_id -> {"weight": int (authored), "text": String}
var want_order: Array = []     # want ids in file order (stable tie-breaks)
var lines: Array = []          # [{"rule": "effect:spread_rumor:x", "reason": String}]
var agency: Dictionary = {}    # hook_type -> Array of effect types
var drift: Array = []          # [{"flag": String, "want": String, "delta": int}]
var source_path: String = ""
## `## Life`: valid arcs in file order. Each arc: {"id", "serves", "prose", "result": {"flag", "text"},
## "fails_if": [flags], "steps": [{"id", "text", "after", "needs": [flags, "!" allowed], "at",
## "takes", "effects": [types], "player": ""|"helps"|"needed", "flag": "<key>_<arc>_<step>"}]}
var life_arcs: Array = []
## Why arcs (or stray Life lines) were rejected. A malformed arc is skipped whole, never half-run
var life_errors: Array = []

var _weights: Dictionary = {}  # want_id -> current runtime weight (1-10)
# Life runtime state (the Director drives it; saved through StorylineDirector.save()):
# arc_id -> {"status": "active"|"completed"|"failed", "done": [step ids], "progress": {step: turns},
#            "helped": [step ids], "waiting_since": int}
var _life: Dictionary = {}
var _life_focus: Dictionary = {}  # {"arc", "step"}: what this soul is working on now ({} = nothing)
var _last_personal_turn: int = -1  # personal round of its last turn (-1 = never)

## Load and parse a SOUL.md file. Returns null if missing or unparseable
static func load_from_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var soul = load("res://scripts/storyline/soul.gd").new()
	soul.source_path = path
	soul.parse(file.get_as_text())
	file.close()
	return soul if soul.npc_key != "" else null

## Parse soul text that never lived in a file (runtime-registered souls: generics, promotions)
## key, when given, overrides the text's `npc:` header (it also prefixes the Life flags)
## Returns null when no key is known
static func from_text(text: String, key: String = "", path: String = ""):
	var soul = load("res://scripts/storyline/soul.gd").new()
	soul.source_path = path
	soul.parse(text, key)
	return soul if soul.npc_key != "" else null

## Parse SOUL.md text. Prose is kept; machine lines use the exact schema shapes
## forced_key replaces the `npc:` header (runtime-registered souls are keyed by their registrar)
func parse(text: String, forced_key: String = "") -> void:
	var want_re = RegEx.create_from_string("^[-*]\\s*`([A-Za-z0-9_]+)`\\s*\\((\\d+)\\)\\s*:?\\s*(.*)$")
	var line_re = RegEx.create_from_string("^[-*]\\s*`([^`]+)`\\s*:?\\s*(.*)$")
	var agency_re = RegEx.create_from_string("^[-*]\\s*`?([A-Za-z_]+)`?\\s*:\\s*(.+)$")
	var drift_re = RegEx.create_from_string("^[-*]\\s*on\\s*`([^`]+)`\\s*:\\s*`([A-Za-z0-9_]+)`\\s*([+-]\\s*\\d+)")

	var section = ""
	var prose: Dictionary = {}  # section -> Array of lines
	var raw_arcs: Array = []     # Life arcs as written, validated once the whole soul is read
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.begins_with("# ") and not line.begins_with("## "):
			var title = line.substr(2).strip_edges()
			if title.to_lower().begins_with("soul:"):
				title = title.substr(5).strip_edges()
			display_name = title
			continue
		if line.begins_with("## "):
			section = line.substr(3).strip_edges().to_lower()
			continue
		if section == "":
			if line.begins_with("npc:"):
				npc_key = line.substr(4).strip_edges().to_lower()
			elif line.begins_with("npc_id:"):
				npc_id = line.substr(7).strip_edges()
			continue

		var m: RegExMatch = null
		match section:
			"wants":
				m = want_re.search(line)
				if m:
					var want_id = m.get_string(1)
					wants[want_id] = {"weight": clampi(int(m.get_string(2)), 1, 10), "text": m.get_string(3).strip_edges()}
					if want_id not in want_order:
						want_order.append(want_id)
			"lines i will not cross":
				m = line_re.search(line)
				if m:
					lines.append({"rule": m.get_string(1).strip_edges().to_lower(), "reason": m.get_string(2).strip_edges()})
			"agency":
				m = agency_re.search(line)
				if m:
					var hook_type = m.get_string(1).to_lower()
					var effects: Array = []
					for part in m.get_string(2).split(","):
						var effect_type = part.strip_edges().trim_prefix("`").trim_suffix("`").to_lower()
						if effect_type != "":
							effects.append(effect_type)
					agency[hook_type] = effects
			"drift":
				m = drift_re.search(line)
				if m:
					drift.append({"flag": m.get_string(1), "want": m.get_string(2), "delta": int(m.get_string(3).replace(" ", ""))})
			"fears":
				if line.begins_with("- ") or line.begins_with("* "):
					fears.append(line.substr(2).strip_edges())
			"life":
				_parse_life_line(line, raw_arcs)
			_:
				if not prose.has(section):
					prose[section] = []
				prose[section].append(raw.rstrip(" \t"))

	essence = _join_prose(prose.get("essence", []))
	voice = _join_prose(prose.get("voice", []))
	secrets = _join_prose(prose.get("secrets", []))
	if forced_key != "":
		npc_key = forced_key.strip_edges().to_lower()
	_finalize_life(raw_arcs)
	reset_weights()
	reset_life()

# =============================================================================
# WANTS (runtime weights)
# =============================================================================

func reset_weights() -> void:
	_weights.clear()
	for want_id in wants:
		_weights[want_id] = wants[want_id].weight

func get_weight(want_id: String) -> int:
	return int(_weights.get(want_id, 0))

func has_want(want_id: String) -> bool:
	return wants.has(want_id)

## Change a want's runtime weight, clamped 1-10. Returns false for unknown wants
func shift_want(want_id: String, delta: int) -> bool:
	if not wants.has(want_id):
		return false
	_weights[want_id] = clampi(get_weight(want_id) + delta, 1, 10)
	return true

## Drift rules that fire when this flag turns true
func get_drift_for_flag(flag_name: String) -> Array:
	var result = []
	for rule in drift:
		if rule.flag == flag_name:
			result.append(rule)
	return result

## Want ids sorted by current weight (highest first, file order breaks ties)
func get_top_wants(count: int = 3) -> Array:
	var ids = want_order.duplicate()
	ids.sort_custom(func(a, b):
		var wa = get_weight(a)
		var wb = get_weight(b)
		if wa != wb:
			return wa > wb
		return want_order.find(a) < want_order.find(b))
	return ids.slice(0, count)

## Sum of current weights for the wants an option serves (unknown wants count 0)
func score_wants(serves: Array) -> int:
	var total = 0
	for want_id in serves:
		total += get_weight(str(want_id))
	return total

func get_weights() -> Dictionary:
	return _weights.duplicate()

func set_weights(saved: Dictionary) -> void:
	for want_id in saved:
		if wants.has(want_id):
			_weights[want_id] = clampi(int(saved[want_id]), 1, 10)

# =============================================================================
# LIFE (personal arcs, docs/WORLD_SCHEMA.md §8)
# =============================================================================

func _parse_life_line(line: String, raw_arcs: Array) -> void:
	if line == "":
		return
	var arc_re = RegEx.create_from_string("^###\\s*Arc:\\s*`([A-Za-z0-9_]+)`\\s*\\(\\s*serves\\s*`([A-Za-z0-9_]+)`\\s*\\)\\s*$")
	if line.begins_with("#"):
		var m = arc_re.search(line)
		if m == null:
			life_errors.append("Life: unrecognised heading '%s' (expected ### Arc: `id` (serves `want`))" % _truncate(line, 80))
			raw_arcs.append({"id": "", "serves": "", "prose": [], "steps": [], "result": {}, "fails_if": [], "errors": ["bad heading"]})  # swallows its lines until the next arc
			return
		raw_arcs.append({"id": m.get_string(1), "serves": m.get_string(2), "prose": [], "steps": [], "result": {}, "fails_if": [], "errors": []})
		return
	var is_bullet = line.begins_with("- ") or line.begins_with("* ")
	if raw_arcs.is_empty():
		if is_bullet:
			life_errors.append("Life: line before any ### Arc heading: '%s'" % _truncate(line, 80))
		return
	var arc: Dictionary = raw_arcs[raw_arcs.size() - 1]
	if not is_bullet:
		if arc.has("prose"):
			arc.prose.append(line)
		return
	var body = line.substr(2).strip_edges()
	var result_re = RegEx.create_from_string("^result\\s*:\\s*`([A-Za-z0-9_]+)`\\s*:?\\s*(.*)$")
	var fails_re = RegEx.create_from_string("^fails_if\\s*:\\s*(.+)$")
	var step_re = RegEx.create_from_string("^`([A-Za-z0-9_]+)`\\s*:\\s*(.*)$")
	var m: RegExMatch = result_re.search(body)
	if m:
		if not arc.get("result", {}).is_empty():
			arc.errors.append("more than one result line")
		arc["result"] = {"flag": m.get_string(1), "text": m.get_string(2).strip_edges()}
		return
	m = fails_re.search(body)
	if m:
		for part in m.get_string(1).split(","):
			var flag = part.strip_edges().trim_prefix("`").trim_suffix("`").strip_edges()
			if flag == "" or not _is_flag_name(flag):
				arc.errors.append("bad fails_if flag '%s'" % flag)
			else:
				arc.fails_if.append(flag)
		return
	m = step_re.search(body)
	if m == null:
		arc.errors.append("unrecognised line '%s'" % _truncate(body, 80))
		return
	var parsed = _parse_step(m.get_string(1), m.get_string(2))
	if parsed.error != "":
		arc.errors.append("step `%s`: %s" % [m.get_string(1), parsed.error])
	else:
		arc.steps.append(parsed.step)

## "<text> | after: x | needs: a, !b | at: loc | takes: 2 | effects: agenda, move_npc [| when: night] [| player: helps]"
func _parse_step(step_id: String, rest: String) -> Dictionary:
	var parts = rest.split("|")
	var step = {"id": step_id, "text": parts[0].strip_edges(), "after": "", "needs": [], "at": "any", "takes": 1, "effects": [], "when": "", "player": ""}
	if step.text == "":
		return {"step": {}, "error": "no text"}
	var seen: Dictionary = {}
	for i in range(1, parts.size()):
		var field = parts[i].strip_edges()
		var colon = field.find(":")
		if colon <= 0:
			return {"step": {}, "error": "field '%s' is not 'name: value'" % field}
		var name = field.substr(0, colon).strip_edges().to_lower()
		var value = field.substr(colon + 1).strip_edges().trim_prefix("`").trim_suffix("`").strip_edges()
		if name not in STEP_FIELDS:
			return {"step": {}, "error": "unknown field '%s'" % name}
		if seen.has(name):
			return {"step": {}, "error": "field '%s' given twice" % name}
		seen[name] = true
		match name:
			"after":
				step.after = "" if value.to_lower() == "none" else value
				if step.after != "" and not _is_flag_name(step.after):
					return {"step": {}, "error": "bad after '%s'" % value}
			"needs":
				if value.to_lower() != "none" and value != "":
					for raw_flag in value.split(","):
						var flag = raw_flag.strip_edges().trim_prefix("`").trim_suffix("`").strip_edges()
						if not _is_flag_name(flag.trim_prefix("!")):
							return {"step": {}, "error": "bad needs flag '%s'" % flag}
						step.needs.append(flag)
			"at":
				step.at = value.to_lower() if value != "" else "any"
				if step.at != "any" and not _is_flag_name(step.at):
					return {"step": {}, "error": "bad at '%s'" % value}
			"takes":
				if not value.is_valid_int() or int(value) < 1 or int(value) > MAX_TAKES:
					return {"step": {}, "error": "takes must be a whole number of rounds 1-%d (got '%s')" % [MAX_TAKES, value]}
				step.takes = int(value)
			"effects":
				if value.to_lower() != "none" and value != "":
					for raw_type in value.split(","):
						var effect_type = raw_type.strip_edges().trim_prefix("`").trim_suffix("`").to_lower()
						if effect_type not in PERSONAL_EFFECTS:
							return {"step": {}, "error": "'%s' is not a personal-scope effect (allowed: %s)" % [effect_type, ", ".join(PERSONAL_EFFECTS)]}
						if effect_type not in step.effects:
							step.effects.append(effect_type)
			"when":
				if not TimeWindow.is_valid(value.to_lower()):
					return {"step": {}, "error": "when must be one of %s or HH-HH (got '%s')" % [", ".join(TimeWindow.WINDOWS.keys()), value]}
				step.when = value.to_lower()
			"player":
				if value.to_lower() not in ["helps", "needed"]:
					return {"step": {}, "error": "player must be helps or needed (got '%s')" % value}
				step.player = value.to_lower()
	for name in STEP_REQUIRED:
		if not seen.has(name):
			return {"step": {}, "error": "missing field '%s'" % name}
	return {"step": step, "error": ""}

## Validate whole arcs now that wants and the key are known; keep only sound ones
func _finalize_life(raw_arcs: Array) -> void:
	life_arcs.clear()
	var arc_ids: Dictionary = {}
	for arc in raw_arcs:
		var errors: Array = arc.get("errors", []).duplicate()
		var arc_id = str(arc.get("id", ""))
		if arc_id == "":
			continue  # its heading was already reported
		if arc_ids.has(arc_id):
			errors.append("duplicate arc id")
		if not wants.has(str(arc.get("serves", ""))):
			errors.append("serves `%s`, which is not one of this soul's Wants" % arc.get("serves", ""))
		if arc.get("steps", []).is_empty():
			errors.append("no steps")
		var step_ids: Dictionary = {}
		for step in arc.get("steps", []):
			if step_ids.has(step.id):
				errors.append("duplicate step `%s`" % step.id)
			if step.after != "" and not step_ids.has(step.after):
				errors.append("step `%s` comes after `%s`, which is not an earlier step of this arc" % [step.id, step.after])
			step_ids[step.id] = true
		var result: Dictionary = arc.get("result", {})
		if result.is_empty():
			errors.append("no result line")
		elif npc_key == "" or not str(result.flag).begins_with(npc_key + "_"):
			errors.append("result `%s` must start with this soul's key ('%s_')" % [result.flag, npc_key])
		elif str(result.get("text", "")) == "":
			errors.append("result `%s` has no description" % result.flag)
		if not errors.is_empty():
			life_errors.append("arc `%s`: %s" % [arc_id, "; ".join(errors)])
			continue
		arc_ids[arc_id] = true
		var steps: Array = []
		for step in arc.steps:
			steps.append(step.merged({"flag": step_flag(arc_id, step.id)}))
		for step in steps:
			if step.flag == result.flag:
				errors.append("result flag equals step `%s`'s flag" % step.id)
		if not errors.is_empty():
			life_errors.append("arc `%s`: %s" % [arc_id, "; ".join(errors)])
			continue
		life_arcs.append({"id": arc_id, "serves": str(arc.serves), "prose": " ".join(arc.prose).strip_edges(),
			"result": {"flag": str(result.flag), "text": str(result.text)}, "fails_if": arc.fails_if.duplicate(), "steps": steps})

func _is_flag_name(text: String) -> bool:
	return text != "" and RegEx.create_from_string("^[A-Za-z0-9_]+$").search(text) != null

func has_life() -> bool:
	return not life_arcs.is_empty()

## The derived personal flag a completed step sets
func step_flag(arc_id: String, step_id: String) -> String:
	return "%s_%s_%s" % [npc_key, arc_id, step_id]

func get_arc(arc_id: String) -> Dictionary:
	for arc in life_arcs:
		if arc.id == arc_id:
			return arc
	return {}

func get_step(arc_id: String, step_id: String) -> Dictionary:
	for step in get_arc(arc_id).get("steps", []):
		if step.id == step_id:
			return step
	return {}

## {"arc": arc, "step": step} for a step flag (also accepts "help:<flag>"), {} when not this soul's
func find_step_by_flag(flag: String) -> Dictionary:
	flag = flag.strip_edges().trim_prefix("help:")
	for arc in life_arcs:
		for step in arc.steps:
			if step.flag == flag:
				return {"arc": arc, "step": step}
	return {}

## Every personal flag this soul's Life can set, with canonical text: step flags and result flags
func get_life_flags() -> Dictionary:
	var name = display_name if display_name != "" else npc_key.capitalize()
	var flags: Dictionary = {}
	for arc in life_arcs:
		for step in arc.steps:
			flags[step.flag] = "%s, for themselves: %s" % [name, str(step.text).trim_suffix(".")]
		flags[arc.result.flag] = arc.result.text
	return flags

## Rounds a step needs: takes, halved (rounded up) once the player committed to a `helps` step
func get_effective_takes(arc_id: String, step_id: String) -> int:
	var step = get_step(arc_id, step_id)
	if step.is_empty():
		return 0
	if step.player == "helps" and is_step_helped(arc_id, step_id):
		return maxi(ceili(step.takes / 2.0), 1)
	return int(step.takes)

# --- runtime state -----------------------------------------------------------

func reset_life() -> void:
	_life.clear()
	for arc in life_arcs:
		_life[arc.id] = {"status": "active", "done": [], "progress": {}, "helped": []}
	_life_focus = {}
	_last_personal_turn = -1

func _arc_state(arc_id: String) -> Dictionary:
	if not _life.has(arc_id):
		_life[arc_id] = {"status": "active", "done": [], "progress": {}, "helped": []}
	return _life[arc_id]

## "active" | "completed" | "failed" ("" for an unknown arc)
func get_arc_status(arc_id: String) -> String:
	return str(_arc_state(arc_id).status) if not get_arc(arc_id).is_empty() else ""

func set_arc_status(arc_id: String, status: String) -> void:
	if not get_arc(arc_id).is_empty():
		_arc_state(arc_id)["status"] = status

func is_step_done(arc_id: String, step_id: String) -> bool:
	return step_id in _arc_state(arc_id).done

func mark_step_done(arc_id: String, step_id: String) -> void:
	var state = _arc_state(arc_id)
	if step_id not in state.done:
		state.done.append(step_id)

func get_step_progress(arc_id: String, step_id: String) -> int:
	return int(_arc_state(arc_id).progress.get(step_id, 0))

func add_step_progress(arc_id: String, step_id: String, turns: int = 1) -> int:
	var state = _arc_state(arc_id)
	state.progress[step_id] = get_step_progress(arc_id, step_id) + turns
	return int(state.progress[step_id])

func is_step_helped(arc_id: String, step_id: String) -> bool:
	return step_id in _arc_state(arc_id).helped

func mark_step_helped(arc_id: String, step_id: String) -> void:
	var state = _arc_state(arc_id)
	if step_id not in state.helped:
		state.helped.append(step_id)

## A step's `after` is met (none, or that step is done)
func is_step_unlocked(arc_id: String, step: Dictionary) -> bool:
	return step.after == "" or is_step_done(arc_id, step.after)

## Every step of the arc is done
func is_arc_finished(arc_id: String) -> bool:
	for step in get_arc(arc_id).get("steps", []):
		if not is_step_done(arc_id, step.id):
			return false
	return not get_arc(arc_id).is_empty()

func get_life_focus() -> Dictionary:
	return _life_focus.duplicate()

func set_life_focus(arc_id: String, step_id: String) -> void:
	_life_focus = {} if arc_id == "" else {"arc": arc_id, "step": step_id}

func get_last_personal_turn() -> int:
	return _last_personal_turn

func set_last_personal_turn(personal_round: int) -> void:
	_last_personal_turn = personal_round

func get_life_state() -> Dictionary:
	return {"arcs": _life.duplicate(true), "focus": _life_focus.duplicate(), "last_turn": _last_personal_turn}

## Restore saved progress. Arcs or steps no longer in the soul text are ignored
func set_life_state(saved: Dictionary) -> void:
	var arcs: Dictionary = saved.get("arcs", {}) if saved.get("arcs") is Dictionary else {}
	for arc_id in arcs:
		var arc = get_arc(str(arc_id))
		if arc.is_empty() or not arcs[arc_id] is Dictionary:
			continue
		var step_ids = arc.steps.map(func(s): return s.id)
		var src: Dictionary = arcs[arc_id]
		var state = _arc_state(str(arc_id))
		state["status"] = str(src.get("status", "active")) if str(src.get("status", "active")) in ["active", "completed", "failed"] else "active"
		state["done"] = Array(src.get("done", [])).map(func(s): return str(s)).filter(func(s): return s in step_ids)
		state["helped"] = Array(src.get("helped", [])).map(func(s): return str(s)).filter(func(s): return s in step_ids)
		var progress: Dictionary = {}
		var src_progress = src.get("progress", {})
		for step_id in (src_progress if src_progress is Dictionary else {}):
			if str(step_id) in step_ids:
				progress[str(step_id)] = int(src_progress[step_id])
		state["progress"] = progress
	var focus = saved.get("focus", {})
	if focus is Dictionary and not get_step(str(focus.get("arc", "")), str(focus.get("step", ""))).is_empty():
		_life_focus = {"arc": str(focus.arc), "step": str(focus.step)}
	_last_personal_turn = int(saved.get("last_turn", -1))

## The arc and step this soul is about, for prompts: the Director's focus, else the first
## active arc's first unlocked step (file order). {} when its Life is done or empty
func get_current_life_step() -> Dictionary:
	if not _life_focus.is_empty():
		var arc = get_arc(str(_life_focus.arc))
		var step = get_step(str(_life_focus.arc), str(_life_focus.step))
		if not step.is_empty() and get_arc_status(arc.id) == "active" and not is_step_done(arc.id, step.id):
			return {"arc": arc, "step": step}
	for arc in life_arcs:
		if get_arc_status(arc.id) != "active":
			continue
		for step in arc.steps:
			if not is_step_done(arc.id, step.id) and is_step_unlocked(arc.id, step):
				return {"arc": arc, "step": step}
	return {}

## Compact Life block for the conversation prompt: the active arc and its current step only
func get_life_prompt_block() -> String:
	var current = get_current_life_step()
	if current.is_empty():
		return ""
	var arc: Dictionary = current.arc
	var step: Dictionary = current.step
	var block = "## YOUR OWN LIFE (what you pursue for yourself, when no one asks anything of you)\n"
	var want_text = str(wants.get(arc.serves, {}).get("text", arc.serves))
	block += "For %s: %s\n" % [_truncate(want_text, 90).trim_suffix("."), _truncate(arc.prose, 200)] if arc.prose != "" else "For %s.\n" % _truncate(want_text, 90).trim_suffix(".")
	var where = "" if step.at == "any" else ", at %s" % step.at
	block += "Now: %s (%d of %d turns%s)\n" % [_truncate(step.text, 140), get_step_progress(arc.id, step.id), get_effective_takes(arc.id, step.id), where]
	if step.player != "" and not is_step_helped(arc.id, step.id):
		block += ("You cannot finish this without the player's help. " if step.player == "needed" else "The player's help would make this quicker. ")
		block += "If they GENUINELY promise to help, put \"help:%s\" in \"commitments\".\n" % step.flag
	elif step.player != "":
		block += "The player has promised to help with this.\n"
	return block + "\n"

func life_to_debug() -> Array:
	var rows: Array = []
	for arc in life_arcs:
		var steps: Array = []
		for step in arc.steps:
			steps.append({"id": step.id, "flag": step.flag, "text": step.text, "after": step.after, "needs": step.needs, "at": step.at,
				"takes": step.takes, "effective_takes": get_effective_takes(arc.id, step.id), "effects": step.effects, "player": step.player,
				"done": is_step_done(arc.id, step.id), "progress": get_step_progress(arc.id, step.id), "helped": is_step_helped(arc.id, step.id)})
		rows.append({"arc": arc.id, "serves": arc.serves, "weight": get_weight(arc.serves), "status": get_arc_status(arc.id),
			"result": arc.result.flag, "fails_if": arc.fails_if, "steps": steps})
	return rows

# =============================================================================
# PERMISSIONS (schema checks b and c; check a is the caller's: effect must come from the option)
# =============================================================================

## Whether this soul engages with a hook type at all (has Agency and no hook: line)
func engages(hook_type: String) -> bool:
	return agency.has(hook_type) and _forbidding_rule("hook:" + hook_type) == ""

## Whether this soul may cause this effect at this hook type
func permits(hook_type: String, effect: Dictionary) -> bool:
	return get_denial_reason(hook_type, effect) == ""

## Why permits() would refuse, or "" when it allows the effect
func get_denial_reason(hook_type: String, effect: Dictionary) -> String:
	var effect_type = str(effect.get("type", ""))
	if not agency.has(hook_type):
		return "no Agency for hook type '%s'" % hook_type
	var rule = _forbidding_rule("hook:" + hook_type)
	if rule != "":
		return "line 'hook:%s': %s" % [hook_type, rule]
	if effect_type not in agency[hook_type]:
		return "Agency for '%s' does not grant %s" % [hook_type, effect_type]
	return _effect_line_denial(effect)

## Effect types this soul may use in conversation: its converse: line, else react + reveal + aid
func get_converse_grants() -> Array:
	if agency.has(CONVERSE):
		return agency[CONVERSE].duplicate()
	var grants: Array = []
	for hook_type in CONVERSE_FALLBACK:
		for effect_type in agency.get(hook_type, []):
			if effect_type not in grants:
				grants.append(effect_type)
	return grants

## Where the converse grants come from: "converse" or "react+reveal+aid"
func get_converse_grant_source() -> String:
	return CONVERSE if agency.has(CONVERSE) else "+".join(CONVERSE_FALLBACK)

## Why this soul may not cause this effect while talking ("" when it may)
func get_converse_denial_reason(effect: Dictionary) -> String:
	var effect_type = str(effect.get("type", ""))
	var rule = _forbidding_rule("hook:" + CONVERSE)
	if rule != "":
		return "line 'hook:converse': %s" % rule
	if effect_type not in get_converse_grants():
		return "Agency for converse (%s) does not grant %s" % [get_converse_grant_source(), effect_type]
	return _effect_line_denial(effect)

## Why this soul may not make a trade action (StorylineDirector.TRADE_ACTIONS: return_pack, teach)
## in conversation ("" when it may). Every soul may answer the player's ask; Lines still refuse it
func get_trade_denial_reason(effect: Dictionary) -> String:
	var rule = _forbidding_rule("hook:" + CONVERSE)
	if rule != "":
		return "line 'hook:converse': %s" % rule
	return _effect_line_denial(effect)

## Why this soul may not cause this effect while working a personal step ("" when it may):
## personal-scope types only, only those the step lists, and no Lines-I-Will-Not-Cross violation
func get_personal_denial_reason(effect: Dictionary, step: Dictionary) -> String:
	var effect_type = str(effect.get("type", ""))
	if effect_type not in PERSONAL_EFFECTS:
		return "personal scope: %s is never a personal effect" % effect_type
	if effect_type not in step.get("effects", []):
		return "step `%s` does not use %s" % [step.get("id", ""), effect_type]
	var rule = _forbidding_rule("hook:" + PERSONAL)
	if rule != "":
		return "line 'hook:personal': %s" % rule
	return _effect_line_denial(effect)

## Lines I Will Not Cross that forbid an effect outright or for its flag
func _effect_line_denial(effect: Dictionary) -> String:
	var effect_type = str(effect.get("type", ""))
	var rule = _forbidding_rule("effect:" + effect_type)
	if rule != "":
		return "line 'effect:%s': %s" % [effect_type, rule]
	var flag = str(effect.get("flag", ""))
	if flag != "":
		rule = _forbidding_rule("effect:%s:%s" % [effect_type, flag])
		if rule != "":
			return "line 'effect:%s:%s': %s" % [effect_type, flag, rule]
	return ""

## Option-level checks: ally:<key> refuses options tagged aids: <key>,
## harm:<key> refuses options whose harms list names <key> (harm: does nothing else),
## crowd refuses options tagged "crowd": true (leading or joining a mob)
func get_option_denial_reason(option: Dictionary) -> String:
	if option.get("crowd", false) == true:
		var crowd_rule = _forbidding_rule("crowd")
		if crowd_rule != "":
			return "line 'crowd': %s" % crowd_rule
	var aids = str(option.get("aids", "")).to_lower()
	if aids != "":
		var rule = _forbidding_rule("ally:" + aids)
		if rule != "":
			return "line 'ally:%s': %s" % [aids, rule]
	var harms = option.get("harms", [])
	if harms is String:
		harms = [harms]
	for victim in harms if harms is Array else []:
		var key = str(victim).to_lower()
		var rule = _forbidding_rule("harm:" + key)
		if rule != "":
			return "line 'harm:%s': %s" % [key, rule]
	return ""

func _forbidding_rule(rule: String) -> String:
	for entry in lines:
		if entry.rule == rule:
			return entry.reason if entry.reason != "" else "forbidden"
	return ""

# =============================================================================
# PROMPT BLOCKS
# =============================================================================

## Compact block for conversation prompts (essence + top current wants)
## full = true adds lines, voice and secrets, for the soul's own decisions
func get_prompt_block(full: bool = false) -> String:
	var block = "## YOUR SOUL (who you are beneath the dialogue)\n"
	if essence != "":
		block += _truncate(essence, 700 if full else 450) + "\n"
	var top = get_top_wants(5 if full else 3)
	if not top.is_empty():
		block += "What you want most right now:\n"
		for want_id in top:
			block += "- %s (%d/10)\n" % [wants[want_id].text if wants[want_id].text != "" else want_id, get_weight(want_id)]
	if full:
		if not lines.is_empty():
			block += "Lines you will not cross:\n"
			for entry in lines:
				block += "- %s\n" % (entry.reason if entry.reason != "" else entry.rule)
		if voice != "":
			block += "Your voice: %s\n" % _truncate(voice, 300)
		if secrets != "":
			block += "What only you know: %s\n" % _truncate(secrets, 400)
	return block + "\n"

## Conversation block (docs/WORLD_SCHEMA.md §6): essence, top wants, lines and voice; never secrets
func get_conversation_prompt_block() -> String:
	var block = get_prompt_block(false).trim_suffix("\n")
	if not lines.is_empty():
		block += "Lines you will not cross: %s\n" % "; ".join(lines.map(func(l): return l.reason if l.reason != "" else l.rule))
	if voice != "":
		block += "Your voice: %s\n" % _truncate(voice, 220)
	return block + "\n" + get_life_prompt_block()

func to_debug_dict() -> Dictionary:
	return {
		"npc": npc_key,
		"npc_id": npc_id,
		"name": display_name,
		"wants": want_order.map(func(w): return "%s %d (base %d)" % [w, get_weight(w), wants[w].weight]),
		"lines": lines.map(func(l): return l.rule),
		"agency": agency.duplicate(true),
		"drift": drift.map(func(d): return "on %s: %s %+d" % [d.flag, d.want, d.delta]),
		"life": life_arcs.map(func(a): return "%s (serves %s, %s)" % [a.id, a.serves, get_arc_status(a.id)]),
		"life_errors": life_errors.duplicate(),
	}

func _join_prose(raw_lines: Array) -> String:
	return "\n".join(raw_lines).strip_edges()

func _truncate(text: String, max_chars: int) -> String:
	var flat = text.replace("\n\n", " ").replace("\n", " ").strip_edges()
	return flat if flat.length() <= max_chars else flat.substr(0, max_chars - 3) + "..."
