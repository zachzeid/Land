extends Node
## Puzzles - lore and evidence puzzles, authored rooms' state (docs/PLAYER_SYSTEMS.md §5.2, §5.3)
## Content is resources/puzzles/*.json: "lore" puzzles (clues, an answer shape, a flag) and "room"
## puzzles (authored scenes built from WorldPhysics components; scripts/puzzles/room_*.gd).
## A solved puzzle sets its flag through WorldState, so the storylines react as if the evidence were
## found, records a `solved` deed and uses the lore skill. Deeds go through PlayerEvents.record, never
## NPC state. Naming a person aloud is an `accusation`, true or false by the puzzle's own answer

const Witnesses = preload("res://scripts/world/witnesses.gd")

const PUZZLE_DIR = "res://resources/puzzles"
const SHAPES = ["choose", "arrange", "name", "decode"]
const LORE_BASE = 1.0   # use_skill difficulty when a puzzle gives none

signal solved(puzzle_id: String)
signal room_completed(room_id: String)
signal room_changed(room_id: String, key: String, value)

var puzzles: Dictionary = {}     # id -> data (lore and room)
var attempts: Dictionary = {}    # id -> answers given while unsolved
var solved_at: Dictionary = {}   # id -> game minute it was solved
var rooms: Dictionary = {}       # room id -> {key: value} (plates, ropes, cage, letters ...)

func _ready():
	load_content()

## Read every puzzle file. Returns how many loaded
func load_content(dir_path: String = PUZZLE_DIR) -> int:
	puzzles.clear()
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return 0
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join(file)))
		if data is Dictionary and str(data.get("id", "")) != "":
			puzzles[data.id] = data
	return puzzles.size()

## Puzzle ids, sorted; kind "lore" or "room" narrows them
func get_puzzle_ids(kind: String = "") -> Array:
	var ids = puzzles.keys().filter(func(id): return kind == "" or str(puzzles[id].get("type", "lore")) == kind)
	ids.sort()
	return ids

## What the player may see of a puzzle (never the answer): {id, type, title, summary, question, shape,
## options | lines | items, clues [{id, kind, text, found}], hints (by lore skill), available, solved,
## attempts, flag}. {} when unknown
func get_puzzle(puzzle_id: String) -> Dictionary:
	if not puzzles.has(puzzle_id):
		return {}
	var p: Dictionary = puzzles[puzzle_id]
	var ans: Dictionary = p.get("answer", {})
	var view = {
		"id": puzzle_id, "type": str(p.get("type", "lore")), "title": str(p.get("title", "")),
		"summary": str(p.get("summary", "")), "question": str(p.get("question", "")),
		"location": str(p.get("location", "")), "shape": str(ans.get("shape", "")),
		"available": is_available(puzzle_id), "solved": is_solved(puzzle_id),
		"attempts": int(attempts.get(puzzle_id, 0)), "flag": str(p.get("flag", "")),
	}
	if ans.has("options"):
		view["options"] = ans.options.map(func(o): return {"id": str(o.id), "label": str(o.get("label", o.id))})
	if ans.has("lines"):
		view["lines"] = ans.lines.map(func(l): return {"id": str(l.id), "cipher": str(l.get("cipher", ""))})
		view["cipher"] = "\n".join(view.lines.map(func(l): return l.cipher))
	# The puzzle card (scripts/ui/puzzle_card.gd) reads these names
	view["answer_kind"] = view.shape
	view["prompt"] = view.question
	if ans.has("items"):
		view["items"] = ans.items.duplicate(true)
	var clues = []
	for c in p.get("clues", []):
		var flag = str(c.get("flag", ""))
		clues.append({"id": str(c.id), "kind": str(c.get("kind", "")), "found": flag == "" or _flag(flag),
			"text": str(c.get("text", c.get("note", "")))})
	view["clues"] = clues
	var lore = _skill("lore")
	view["hints"] = p.get("hints", []).filter(func(h): return lore >= float(h.get("min_lore", 0))).map(func(h): return str(h.text))
	if view.type == "room":
		view["reward"] = str(p.get("reward", ""))
		view["state"] = get_room_state(puzzle_id)
	return view

func is_solved(puzzle_id: String) -> bool:
	return solved_at.has(puzzle_id)

## Every flag in `requires` is set (the player has found what the reasoning needs)
func is_available(puzzle_id: String) -> bool:
	if not puzzles.has(puzzle_id):
		return false
	for f in puzzles[puzzle_id].get("requires", []):
		if not _flag(str(f)):
			return false
	return true

## Give an answer. Returns {ok, flag, reason}, plus `wrong` (decode line ids / arrange places),
## `event_id` (the solved deed) and `accusation_id`. Shapes: choose (option id), arrange (Array of
## ids), name (an NPC key or alias), decode (Dictionary line id -> value, or an Array in line order).
## opts: aloud (a name said to whoever is present: an accusation), witnesses (Array),
## scene_root + at (Witnesses.in_sight for a deed done in a scene), source (the NPC it was said to)
func answer(puzzle_id: String, given, opts: Dictionary = {}) -> Dictionary:
	if not puzzles.has(puzzle_id):
		return {"ok": false, "flag": "", "reason": "unknown_puzzle"}
	var p: Dictionary = puzzles[puzzle_id]
	var flag = str(p.get("flag", ""))
	if str(p.get("type", "lore")) == "room":
		return {"ok": is_solved(puzzle_id), "flag": flag if is_solved(puzzle_id) else "", "reason": "a room is solved in the room"}
	if is_solved(puzzle_id):
		return {"ok": true, "flag": flag, "reason": "already_solved"}
	if not is_available(puzzle_id):
		return {"ok": false, "flag": "", "reason": "missing_clues"}
	attempts[puzzle_id] = int(attempts.get(puzzle_id, 0)) + 1
	var check = _check(p.get("answer", {}), given)
	var out = {"ok": check.ok, "flag": flag if check.ok else "", "reason": str(check.get("reason", ""))}
	if check.has("wrong"):
		out["wrong"] = check.wrong
	if str(check.get("named", "")) != "" and opts.get("aloud", false):
		out["accusation_id"] = _accuse(p, str(check.named), check.ok or str(check.get("truth", "false")) == "true", opts)
	if check.ok:
		out["event_id"] = _solve(puzzle_id, opts)
		out["reason"] = "solved"
	return out

# =============================================================================
# ROOMS (scripts/puzzles/room_*.gd keep their state here so it saves)
# =============================================================================

func get_room_state(room_id: String) -> Dictionary:
	return rooms.get(room_id, {}).duplicate(true)

func set_room_state(room_id: String, key: String, value) -> void:
	if not rooms.has(room_id):
		rooms[room_id] = {}
	if rooms[room_id].has(key) and rooms[room_id][key] == value:
		return
	rooms[room_id][key] = value
	room_changed.emit(room_id, key, value)

## A room's reward reached: set its flag, record the deed (seen by line of sight in the room).
## opts: scene_root, at (Vector2), witnesses. Returns {ok, flag, reason}
func complete_room(room_id: String, opts: Dictionary = {}) -> Dictionary:
	if not puzzles.has(room_id) or str(puzzles[room_id].get("type", "")) != "room":
		return {"ok": false, "flag": "", "reason": "unknown_room"}
	var flag = str(puzzles[room_id].get("flag", ""))
	if is_solved(room_id):
		return {"ok": true, "flag": flag, "reason": "already_solved"}
	set_room_state(room_id, "complete", true)
	var id = _solve(room_id, opts)
	room_completed.emit(room_id)
	return {"ok": true, "flag": flag, "reason": "solved", "event_id": id}

# =============================================================================
# CHECKING ANSWERS
# =============================================================================

func _check(ans: Dictionary, given) -> Dictionary:
	match str(ans.get("shape", "")):
		"choose":
			var pick = _norm(given)
			if pick == _norm(ans.get("correct", "")):
				return {"ok": true}
			var ids = ans.get("options", []).map(func(o): return _norm(o.id))
			if not pick in ids:
				return {"ok": false, "reason": "not_an_option"}
			return {"ok": false, "reason": str(ans.get("wrong", {}).get(pick.replace(" ", "_"), "That is not it."))}
		"arrange":
			var want: Array = ans.get("correct", []).map(func(x): return _norm(x))
			var got: Array = (given if given is Array else []).map(func(x): return _norm(x))
			if got == want:
				return {"ok": true}
			var wrong = []
			for i in want.size():
				if i >= got.size() or got[i] != want[i]:
					wrong.append(i)
			return {"ok": false, "reason": "%d of %d in their place" % [want.size() - wrong.size(), want.size()], "wrong": wrong}
		"name":
			var key = _name_key(ans.get("names", {}), given)
			if key == "":
				return {"ok": false, "reason": "nobody_by_that_name"}
			if key == str(ans.get("correct", "")):
				return {"ok": true, "named": key}
			var entry: Dictionary = ans.names[key]
			if entry.get("near_miss", false):
				# Close enough that saying it aloud is no lie, so it is no accusation either
				return {"ok": false, "reason": str(entry.get("reason", ""))}
			return {"ok": false, "named": key, "truth": str(entry.get("truth", "false")), "reason": str(entry.get("reason", "That is not who."))}
		"decode":
			var lines: Array = ans.get("lines", [])
			if given is String:
				given = Array(given.replace(";", ",").replace("\n", ",").split(",")).map(func(s): return s.strip_edges())
			var wrong = []
			for i in lines.size():
				var line: Dictionary = lines[i]
				var v = ""
				if given is Dictionary:
					v = given.get(line.id, "")
				elif given is Array and i < given.size():
					v = given[i]
				var accepted = [_norm(line.correct)] + line.get("aliases", []).map(func(a): return _norm(a))
				if not _norm(v) in accepted:
					wrong.append(str(line.id))
			if wrong.is_empty():
				return {"ok": true}
			return {"ok": false, "reason": "%d of %d lines read true" % [lines.size() - wrong.size(), lines.size()], "wrong": wrong}
	return {"ok": false, "reason": "unknown_shape"}

func _name_key(names: Dictionary, given) -> String:
	var g = _norm(given)
	if g == "":
		return ""
	for key in names:
		if g == _norm(key) or g in names[key].get("aliases", []).map(func(a): return _norm(a)):
			return str(key)
	return ""

## Lowercase, underscores as spaces, one space between words
func _norm(v) -> String:
	var s = str(v).to_lower().replace("_", " ").strip_edges()
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s

# =============================================================================
# DEEDS
# =============================================================================

func _solve(puzzle_id: String, opts: Dictionary) -> String:
	var p: Dictionary = puzzles[puzzle_id]
	solved_at[puzzle_id] = _now()
	var flag = str(p.get("flag", ""))
	var ws = get_node_or_null("/root/WorldState")
	if flag != "" and ws:
		ws.set_world_flag(flag, true)
	# Reasoning alone is seen by nobody; a deed in a scene by whoever has line of sight
	var witnesses = _witnesses(opts, [])
	var id = ""
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe:
		var rec = {"witnesses": witnesses, "spread": false}
		if flag != "":
			rec["flag"] = flag
		id = pe.record("solved", str(p.get("solved_summary", "worked out " + str(p.get("title", puzzle_id)))), p.get("about", []), rec)
	if str(p.get("type", "lore")) == "lore":
		var stats = get_node_or_null("/root/PlayerStats")
		if stats:
			stats.use_skill("lore", float(p.get("difficulty", LORE_BASE)), {"puzzle": puzzle_id, "witnessed_by": witnesses})
	solved.emit(puzzle_id)
	return id

## Naming someone aloud: an accusation, true when the puzzle's answer bears it out
func _accuse(p: Dictionary, key: String, truth: bool, opts: Dictionary) -> String:
	var pe = get_node_or_null("/root/PlayerEvents")
	if pe == null:
		return ""
	var rec = {"truth": "true" if truth else "false"}
	var w = _witnesses(opts, null)
	if w != null:
		rec["witnesses"] = w
	if opts.has("source"):
		rec["source"] = opts.source
	return pe.record("accusation", "said aloud that %s was behind %s" % [_display_name(key), str(p.get("accuses", "it"))], [key], rec)

## Explicit witnesses, else line of sight in a scene, else `fallback` (null: PlayerEvents uses presence)
func _witnesses(opts: Dictionary, fallback):
	if opts.has("witnesses"):
		return opts.witnesses.duplicate()
	if opts.get("scene_root") is Node and opts.get("at") is Vector2:
		return Witnesses.in_sight(opts.scene_root, opts.at, {"stealth": _skill("stealth")})
	return fallback

func _display_name(key: String) -> String:
	var reg = get_node_or_null("/root/WorldRegistry")
	var n = str(reg.get_npc_name(key)) if reg and reg.has_method("get_npc_name") else ""
	return n if n != "" else key.capitalize()

func _flag(name: String) -> bool:
	var ws = get_node_or_null("/root/WorldState")
	return ws != null and ws.get_world_flag(name)

func _skill(name: String) -> float:
	var stats = get_node_or_null("/root/PlayerStats")
	return float(stats.get_skill(name)) if stats else 0.0

func _now() -> int:
	var ws = get_node_or_null("/root/WorldState")
	return ws.get_game_minutes() if ws else 0

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {"attempts": attempts.duplicate(true), "solved": solved_at.duplicate(true), "rooms": rooms.duplicate(true)}

func load_from_dict(data: Dictionary) -> void:
	attempts = {}
	solved_at = {}
	rooms = {}
	for k in data.get("attempts", {}):
		attempts[str(k)] = int(data.attempts[k])
	for k in data.get("solved", {}):
		solved_at[str(k)] = int(data.solved[k])
	for k in data.get("rooms", {}):
		if data.rooms[k] is Dictionary:
			rooms[str(k)] = data.rooms[k].duplicate(true)
