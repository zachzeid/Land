extends SceneTree
## Windowed walking QA (not a headless suite): loads each scene through SceneManager, drives the real
## Player with the movement actions along a grid path to every door, item, bed and NPC, pushes into
## every building to see it hold, walks through each new tavern door and back out, and advances the
## clock hour by hour checking every NPC body against the solid layers. Screenshots and a report go
## to the directory given by --qa-out=<dir>.
## Run: godot --path . -s res://scripts/debug/qa/walk_qa.gd -- --no-opening --no-autosave \
##      --save-path=<scratch>/qa_save.json --qa-out=<scratch>/qa
## Nothing here saves: --save-path keeps WorldState off the real save even if something asked

const PLAYER_BODY = Vector2(32, 48)
const SOLID_MASK = 12          # world_solid + world_obstacle
const WALK_MASK = 14           # what the player bumps into: those and NPCs
const CELL = 8.0
const STUCK_SECONDS = 1.5
const TIME_SCALE = 1.0         # faster steps overshoot the 8px grid path

const SCENES = ["ferrisford", "fort_ashguard", "greystone_mines", "iron_hollow_camp", "thornhaven_town_square",
	"brackenmoor_abbey", "kingsroad_waystation", "ferrisford_tavern", "greystone_tavern",
	"capitol_docks_tavern", "capitol_market_inn"]
const TAVERNS = {
	"ferrisford_tavern": "ferrisford",
	"greystone_tavern": "greystone_mines",
	"capitol_docks_tavern": "capitol_docks",
	"capitol_market_inn": "capitol_market",
}

var out_dir: String = ""
var only: String = ""          # --qa-only=<location>: that scene alone, no door round trips
var skip: Array = []           # --qa-skip=<a,b>: scenes already walked
var report: Array = []
var problems: Array = []
var scene_manager: Node

func _init():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			out_dir = arg.substr("--qa-out=".length())
		elif arg.begins_with("--qa-skip="):
			skip = arg.substr("--qa-skip=".length()).split(",")
		elif arg.begins_with("--qa-only="):
			only = arg.substr("--qa-only=".length())
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame
	var config = root.get_node_or_null("Config")
	if config and (str(config.claude_api_key) != "" or str(config.elevenlabs_api_key) != "" or str(config.pixellab_api_key) != ""):
		_log("STOP: an API key is configured; refusing to run")
		_finish()
		return
	scene_manager = root.get_node("SceneManager")
	root.get_node("WorldState").set_idle_clock_rate(0.0)
	Engine.time_scale = TIME_SCALE

	for loc in SCENES:
		if (only == "" or only == loc) and not loc in skip:
			await _visit(loc)
	for id in TAVERNS:
		if only == "":
			await _door_round_trip(id, TAVERNS[id])
	_finish()

func _finish() -> void:
	Engine.time_scale = 1.0
	_log("PROBLEMS: %d" % problems.size())
	for p in problems:
		_log("  - " + p)
	var f = FileAccess.open(out_dir.path_join("report.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report) + "\n")
		f.close()
	quit(0)

## ===== ONE SCENE =====

func _visit(loc: String) -> void:
	_log("\n== %s" % loc)
	if not await _go(loc, "default"):
		return
	var scene = current_scene
	var player = _player()
	if scene == null or player == null:
		_problem("%s: no scene or player after loading" % loc)
		return
	await _shot("%s_arrive" % loc)
	var start = player.global_position

	# every door, item, bed and NPC: walk to it with the movement keys
	var targets = _targets(scene)
	var reached = 0
	for t in targets:
		if not is_instance_valid(t):
			continue
		await _teleport(start)
		var ok = await _walk_to_rect(_rect_of(t), "%s → %s" % [loc, _label(t)])
		if ok:
			reached += 1
	_log("%s: reached %d/%d targets" % [loc, reached, targets.size()])

	# buildings hold: from outside, push at the middle of every wall-layer body for a second
	var held = 0
	var bodies = _all(scene).filter(func(n): return n is StaticBody2D and n.collision_layer == 4 and _rect_of(n).size.x < 600 and _rect_of(n).size.y < 600)
	for b in bodies:
		var r = _rect_of(b)
		var outside = _outside_spot(r)
		if outside == Vector2.INF:
			continue
		await _teleport(outside)
		await _hold_toward(r.get_center(), 1.0)
		if _player_rect(player.global_position).grow(-3).intersects(r):
			_problem("%s: walked into %s" % [loc, b.name])
			await _shot("%s_into_%s" % [loc, b.name])
		else:
			held += 1
	_log("%s: %d/%d buildings held" % [loc, held, bodies.size()])
	if not bodies.is_empty():
		await _shot("%s_push" % loc)

	# a day: hour by hour, refresh the NPCs and check every body
	await _teleport(start)
	var world_state = root.get_node("WorldState")
	for hour in 24:
		world_state.advance_time(60, "qa_walk")
		scene_manager.refresh_npcs()
		await physics_frame
		await physics_frame
		for npc in get_nodes_in_group("npcs"):
			if npc is CharacterBody2D and npc.visible and current_scene.is_ancestor_of(npc):
				if not _clear(npc.global_position, _body_size(npc), SOLID_MASK):
					_problem("%s: %s inside a body at %s (%s)" % [loc, npc.name, npc.global_position, world_state.get_time_string()])
		if hour == 12:
			await _shot("%s_noon" % loc)
	await _shot("%s_day_end" % loc)

## ===== TAVERN DOORS =====

func _door_round_trip(id: String, exterior: String) -> void:
	_log("\n== door %s ↔ %s" % [exterior, id])
	if not await _go(exterior, "default"):
		return
	var door = _triggers(current_scene).filter(func(t): return str(t.target_location) == id)
	if door.size() != 1:
		_problem("%s: no single door to %s" % [exterior, id])
		return
	var arrive_name = str(door[0].target_spawn_point)
	if not await _walk_to_rect(_rect_of(door[0]), "%s → door of %s" % [exterior, id]):
		return
	await _shot("%s_at_door" % id)
	if not await _interact_until(id):
		_problem("%s: pressing interact at the door did not go in" % id)
		return
	var marker = _marker(current_scene, arrive_name)
	var player = _player()
	_check_near(player, marker, "%s: arrived on %s" % [id, arrive_name])
	await _shot("%s_inside" % id)
	var exit = _triggers(current_scene).filter(func(t): return str(t.target_location) == exterior)
	if exit.size() != 1:
		_problem("%s: no single way out" % id)
		return
	var back_name = str(exit[0].target_spawn_point)
	if not await _walk_to_rect(_rect_of(exit[0]), "%s → way out" % id):
		return
	if not await _interact_until(exterior):
		_problem("%s: pressing interact at the way out did not leave" % id)
		return
	_check_near(_player(), _marker(current_scene, back_name), "%s: back out on %s" % [id, back_name])
	await _shot("%s_back_out" % id)

## Press E (the door hears it once the overlap has registered, a physics frame after touching it)
func _interact_until(location_id: String) -> bool:
	for attempt in 3:
		for j in 4:
			await physics_frame
		for pressed in [true, false]:
			var ev = InputEventAction.new()
			ev.action = "interact"
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await process_frame
		for i in 120:
			await process_frame
			if scene_manager.get_current_location_id() == location_id and _player() != null:
				for j in 10:
					await physics_frame
				return true
	return false

func _check_near(player: Node2D, marker: Node2D, what: String) -> void:
	if player == null or marker == null:
		_problem(what + ": missing player or marker")
	elif player.global_position.distance_to(marker.global_position) > 4.0:
		_problem("%s: player at %s, marker at %s" % [what, player.global_position, marker.global_position])
	else:
		_log(what + " ✓")

## ===== DRIVING =====

var _arrived: bool = false

## Through SceneManager, as a door would. False when the transition never finishes (logged)
func _go(loc: String, spawn: String) -> bool:
	_arrived = false
	_transition(loc, spawn)
	for i in 1200:
		if _arrived:
			break
		await process_frame
	if not _arrived:
		_problem("%s: the transition never finished (SceneManager still waiting)" % loc)
		await _shot("%s_hung" % loc)
		return false
	for i in 20:
		await process_frame
	return true

func _transition(loc: String, spawn: String) -> void:
	await scene_manager.transition_to(loc, spawn, 0.0, false)
	_arrived = true

func _teleport(pos: Vector2) -> void:
	_release()
	var p = _player()
	p.global_position = pos
	p.velocity = Vector2.ZERO
	await physics_frame
	await physics_frame

## Plan a grid path (around walls, props and NPCs) to where the body overlaps rect, then walk it
## with the movement actions. False (and logged) when there is no path or the walk sticks
func _walk_to_rect(rect: Rect2, what: String) -> bool:
	var player = _player()
	var path = _plan(player.global_position, rect, WALK_MASK)
	if path.is_empty():
		var through_npcs = _plan(player.global_position, rect, SOLID_MASK)
		_problem("%s: no path%s" % [what, " (NPCs in the way: %s)" % _blockers(through_npcs) if not through_npcs.is_empty() else ""])
		await _shot(_slug(what) + "_nopath")
		return false
	var i = 0
	var last_pos = player.global_position
	var still = 0.0
	var elapsed = 0.0
	while not _player_rect(player.global_position).intersects(rect):
		while i < path.size() - 1 and player.global_position.distance_to(path[i]) < 4.0:
			i += 1
		# along the grid path one axis at a time, as a player steers round a corner
		var d: Vector2 = path[i] - player.global_position
		_press(Vector2(signf(d.x), 0) if absf(d.x) > absf(d.y) else Vector2(0, signf(d.y)))
		await physics_frame
		var dt = 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
		elapsed += dt
		if player.global_position.distance_to(last_pos) < 0.5:
			still += dt
		else:
			still = 0.0
		last_pos = player.global_position
		if still > STUCK_SECONDS or elapsed > 60.0:
			_release()
			var hit = player.get_last_slide_collision()
			_problem("%s: stuck at %s against %s, heading for %s" % [what, player.global_position,
				hit.get_collider().name if hit and hit.get_collider() else "nothing", path[i]])
			await _shot(_slug(what) + "_stuck")
			return false
	_release()
	_log(what + " ✓")
	return true

## Visible NPCs standing on or beside a path (corners only: test the legs between them)
func _blockers(path: Array) -> String:
	var out: Array = []
	var pts: Array = [_player().global_position] + path
	for npc in get_nodes_in_group("npcs"):
		if not (npc is CharacterBody2D and npc.visible and current_scene.is_ancestor_of(npc)):
			continue
		var body = _player_rect(npc.global_position).grow(PLAYER_BODY.x / 2.0 + 4.0)
		for k in range(1, pts.size()):
			var leg = Rect2(pts[k - 1], Vector2.ZERO).expand(pts[k])
			leg = Rect2(leg.position + Vector2(0, -PLAYER_BODY.y / 2.0), leg.size)
			if leg.intersects(body, true):
				out.append("%s@%s" % [npc.name, npc.global_position])
				break
	return ", ".join(out)

func _hold_toward(target: Vector2, seconds: float) -> void:
	var player = _player()
	var t = 0.0
	while t < seconds:
		_press(target - player.global_position)
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
	_release()

func _press(dir: Vector2) -> void:
	var d = dir.normalized()
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(a)
	if d.x < -0.2:
		Input.action_press("ui_left", -d.x)
	elif d.x > 0.2:
		Input.action_press("ui_right", d.x)
	if d.y < -0.2:
		Input.action_press("ui_up", -d.y)
	elif d.y > 0.2:
		Input.action_press("ui_down", d.y)

func _release() -> void:
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_release(a)

## BFS over CELL steps to the first cell whose body overlaps rect; the path as cell positions
func _plan(from: Vector2, rect: Rect2, mask: int) -> Array:
	var start = Vector2i(roundi(from.x / CELL), roundi(from.y / CELL))
	var came: Dictionary = {start: start}
	var todo: Array = [start]
	var head = 0
	while head < todo.size() and head < 60000:
		var c: Vector2i = todo[head]
		head += 1
		if _player_rect(Vector2(c) * CELL).intersects(rect):
			var cells: Array = []
			while c != start:
				cells.push_front(c)
				c = came[c]
			cells.push_front(start)
			# keep the corners only: the walker goes straight along each leg
			var path: Array = []
			for k in range(1, cells.size()):
				if k == cells.size() - 1 or (cells[k] - cells[k - 1]) != (cells[k + 1] - cells[k]):
					path.append(Vector2(cells[k]) * CELL)
			path.append(rect.get_center())
			return path
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not came.has(n) and _clear(Vector2(n) * CELL, PLAYER_BODY + Vector2(4, 4), mask):
				came[n] = c
				todo.append(n)
	return []

## A spot just outside rect (below it, else above, left, right) where the body fits
func _outside_spot(r: Rect2) -> Vector2:
	for p in [Vector2(r.get_center().x, r.end.y + 6), Vector2(r.get_center().x, r.position.y - 6),
			Vector2(r.position.x - 22, r.end.y - 4), Vector2(r.end.x + 22, r.end.y - 4)]:
		if _clear(p, PLAYER_BODY + Vector2(4, 4), WALK_MASK):
			return p
	return Vector2.INF

## ===== GEOMETRY =====

func _clear(pos: Vector2, size: Vector2, mask: int) -> bool:
	var shape = RectangleShape2D.new()
	shape.size = size - Vector2(2, 2)
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	# centred on the body (feet at pos), so a grown size leaves slack below as well as above
	q.transform = Transform2D(0.0, pos + Vector2(0, -PLAYER_BODY.y / 2.0 if size.y >= PLAYER_BODY.y else -size.y / 2.0))
	q.collision_mask = mask
	var p = _player()
	if p:
		q.exclude = [p.get_rid()]
	return current_scene.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()

func _player_rect(pos: Vector2) -> Rect2:
	return Rect2(pos + Vector2(-PLAYER_BODY.x / 2.0, -PLAYER_BODY.y), PLAYER_BODY)

func _rect_of(node: Node) -> Rect2:
	for c in node.get_children():
		if c is CollisionShape2D and c.shape:
			var r: Rect2 = c.shape.get_rect()
			return Rect2(c.global_position + r.position * c.global_scale, r.size * c.global_scale)
	return Rect2(node.global_position, Vector2.ONE)

func _body_size(npc: Node) -> Vector2:
	var c = npc.get_node_or_null("CollisionShape2D")
	return c.shape.size if c and c.shape is RectangleShape2D else PLAYER_BODY

## ===== SCENE QUERIES =====

func _player() -> Node2D:
	return current_scene.find_child("Player", true, false) if current_scene else null

func _marker(scene: Node, marker_name: String) -> Node2D:
	var points = scene.find_child("SpawnPoints", true, false)
	var m = points.find_child(marker_name, false, false) if points else null
	return m if m is Marker2D else null

func _triggers(scene: Node) -> Array:
	return _all(scene).filter(func(n): return n is SceneTrigger)

func _targets(scene: Node) -> Array:
	var out: Array = []
	for n in _all(scene):
		if n is Area2D and (n is Interactable or n is SceneTrigger) and not _under_npc(n):
			out.append(n)
	for npc in get_nodes_in_group("npcs"):
		if npc is CharacterBody2D and npc.visible and scene.is_ancestor_of(npc) and npc.get_node_or_null("InteractionArea"):
			out.append(npc.get_node("InteractionArea"))
	return out

func _under_npc(n: Node) -> bool:
	var p = n.get_parent()
	while p:
		if p is CharacterBody2D:
			return true
		p = p.get_parent()
	return false

func _label(n: Node) -> String:
	return str(n.get_parent().name) + "/" + str(n.name) if n.name == "InteractionArea" else str(n.name)

func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out

## ===== OUTPUT =====

var _drawn: int = 0

## A frame drawn after the call (an occluded window draws nothing: give up after a while, logged)
func _shot(shot_name: String) -> void:
	var want = _drawn + 3
	if not RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.connect(_on_drawn)
	for i in 240:
		if _drawn >= want:
			break
		await process_frame
	if _drawn < want:
		_log("(no frame drawn for %s: window hidden?)" % shot_name)
	var img = root.get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_png(out_dir.path_join(_slug(shot_name) + ".png"))

func _on_drawn() -> void:
	_drawn += 1

func _slug(s: String) -> String:
	var out = ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out

func _log(s: String) -> void:
	print("[QA] " + s)
	report.append(s)

func _problem(s: String) -> void:
	problems.append(s)
	_log("PROBLEM " + s)
