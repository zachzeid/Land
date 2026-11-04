extends SceneTree
## QA driver (windowed): the six taverns in the real game window (docs/WORLD_SCHEMA.md §16)
## For each tavern: an evening and the next morning with the clock run through SceneManager's
## scene, lodgers checked at their room markers (not stacked, not in a wall, gone by morning, never a
## child), every RoomDoor walked through by the real Player body (physics), screenshots of each
## Run (never the real save):
##   CLAUDE_API_KEY= ELEVENLABS_API_KEY= godot --path . -s res://scripts/debug/qa/qa_taverns.gd \
##     -- --save-path=<scratch>/qa_save.json --no-autosave --qa-out=<dir>
## Prints QA lines "  ✅ / ❌" and a final count; quits itself

const TAVERNS = ["thornhaven_tavern", "kingsroad_waystation", "ferrisford_tavern", "greystone_tavern",
	"capitol_docks_tavern", "capitol_market_inn"]
const DAY = 1440
const Rep = preload("res://scripts/world_state/reputation.gd")

var out_dir = "user://qa_taverns/"
var ws: Node
var sm: Node
var taverns: Node
var pe: Node
var inv: Node
var stats: Node
var director: Node
var registry: Node
var failures = 0
var day = 3

func _init():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-out="):
			out_dir = arg.substr("--qa-out=".length())
	await process_frame
	await process_frame
	await process_frame
	var config = root.get_node("Config")
	if str(config.claude_api_key) != "" or str(config.elevenlabs_api_key) != "" or str(config.pixellab_api_key) != "":
		print("QA STOP: an API key is configured; refusing to run")
		quit(2)
		return
	ws = root.get_node("WorldState")
	sm = root.get_node("SceneManager")
	taverns = root.get_node("Taverns")
	pe = root.get_node("PlayerEvents")
	inv = root.get_node("Inventory")
	stats = root.get_node("PlayerStats")
	director = root.get_node("StorylineDirector")
	registry = root.get_node("WorldRegistry")
	if not str(ws.save_path).begins_with("/private/tmp") or ws.autosave_enabled:
		print("QA STOP: save path is not the scratch override (%s)" % ws.save_path)
		quit(2)
		return
	ws.set_idle_clock_rate(0.0)
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	stats.move_on_respawn = false
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr("--only=".length())
	for loc in TAVERNS:
		if only != "" and loc != only:
			continue
		await _visit(loc)
		day += 2
	print("\nQA: %s" % ("ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	quit(0 if failures == 0 else 1)

# =============================================================================

func _visit(loc: String) -> void:
	print("\n=== %s (%s) ===" % [loc, taverns._place(loc)])
	_clock(day * DAY + 19 * 60)
	sm.transition_to(loc, "default", 0.05, false)
	await sm.scene_transition_completed
	await _frames(10)
	var scene = current_scene
	_report_people(loc, "19:00")
	await _shot("%s_1_evening" % loc)
	_clock(day * DAY + 21 * 60 + 30)
	await _frames(10)
	var lodgers: Dictionary = taverns.lodgers(loc)
	print("  lodgers at 21:30: %s" % str(lodgers))
	_report_people(loc, "21:30")
	_check_rooms(loc, scene, lodgers, true)
	await _shot("%s_2_night" % loc)
	_clock((day + 1) * DAY + 7 * 60)
	await _frames(10)
	_report_people(loc, "07:00")
	_check_rooms(loc, scene, lodgers, false)
	await _shot("%s_3_morning" % loc)
	# The doors: by day with a room of the player's own (yours / free), then by night (a lodger's)
	_clock((day + 1) * DAY + 12 * 60)
	await _frames(6)
	inv.coin = 200
	print("  rented at noon: %s" % str(taverns.rent(loc)))
	await _doors(loc, scene, "day")
	taverns.reset()
	_clock((day + 1) * DAY + 22 * 60)
	await _frames(10)
	print("  lodgers at 22:00: %s" % str(taverns.lodgers(loc)))
	await _doors(loc, scene, "night")
	await _renting(loc, scene)
	if taverns.is_brothel(loc):
		await _back_rooms(loc)

func _clock(target: int) -> void:
	if target > ws.game_minutes:
		ws.advance_time(target - ws.game_minutes, "qa")
	else:
		ws.game_minutes = target - 1
		ws.advance_time(1, "qa")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

## Every body in the scene, with where it stands
func _bodies(scene: Node) -> Array:
	return get_nodes_in_group("npcs").filter(func(n): return n is Node2D and is_instance_valid(n) and scene.is_ancestor_of(n) and n.visible)

func _report_people(loc: String, label: String) -> void:
	var names = []
	for b in _bodies(current_scene):
		names.append("%s@%s" % [taverns._body_who(b), Vector2i(b.global_position)])
	print("  %s present=%s bodies=%s" % [label, str(taverns._present(loc)), ", ".join(names)])

## Lodgers at their markers, not stacked, not in walls; by morning gone from the rooms; no child in a room
func _check_rooms(loc: String, scene: Node, lodgers: Dictionary, night: bool) -> void:
	var spawns = scene.find_child("SpawnPoints", true, false)
	var bodies = _bodies(scene)
	var markers: Dictionary = {}
	for room in taverns.lettable(loc) + taverns.back_rooms(loc):
		var m = spawns.get_node_or_null(str(room))
		if m:
			markers[room] = m.global_position
	for room in lodgers:
		var who = str(lodgers[room])
		var body = bodies.filter(func(b): return taverns._body_who(b) == who)
		var at = body[0].global_position if not body.is_empty() else Vector2.INF
		if night:
			_check("%s: %s in %s (%s, marker %s)" % [loc, who, room, at, markers.get(room)], not body.is_empty() and at.distance_to(markers[room]) < 8.0)
		else:
			_check("%s: by morning %s has left %s (%s)" % [loc, who, room, at], body.is_empty() or markers.values().all(func(p): return at.distance_to(p) > 40.0))
	# Nobody stacked, nobody in a wall
	for i in bodies.size():
		var b: Node2D = bodies[i]
		for j in range(i + 1, bodies.size()):
			if b.global_position.distance_to(bodies[j].global_position) < 24.0:
				_check("%s: %s and %s are not stacked" % [loc, taverns._body_who(b), taverns._body_who(bodies[j])], false)
		var hits = _overlaps(b)
		if not hits.is_empty():
			_check("%s: %s at %s is not inside %s" % [loc, taverns._body_who(b), Vector2i(b.global_position), hits], false)
	# Children: never in a room marker's reach
	for b in bodies:
		if taverns._is_minor(taverns._body_who(b)):
			for room in markers:
				_check("%s: the child %s is not in %s" % [loc, taverns._body_who(b), room], b.global_position.distance_to(markers[room]) > 100.0)
	_check("%s (%s): no child is given a room" % [loc, "night" if night else "morning"], not lodgers.values().any(func(w): return taverns._is_minor(str(w))))

## The solid bodies (walls, props) this body's own collision shape overlaps where it stands
func _overlaps(body: Node2D) -> Array:
	var shape_node: CollisionShape2D = null
	for c in body.get_children():
		if c is CollisionShape2D and not c.disabled:
			shape_node = c
	if shape_node == null or shape_node.shape == null:
		return []
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape_node.shape
	q.transform = shape_node.global_transform
	q.collision_mask = 4 | 8
	q.exclude = [body.get_rid()]
	var out = []
	for hit in body.get_world_2d().direct_space_state.intersect_shape(q, 8):
		var c = hit.collider
		if c and c != body:
			out.append(str(c.get_parent().name) + "/" + str(c.name))
	return out

# =============================================================================
# DOORS
# =============================================================================

func _doors(loc: String, scene: Node, when: String) -> void:
	var player: CharacterBody2D = sm.player_instance
	var doors = scene.find_children("*", "Area2D", true, false).filter(func(d): return d.get_script() and d.get_script().resource_path.ends_with("room_door.gd"))
	var beds = {}
	for b in scene.find_children("*", "Area2D", true, false):
		if b is Bed:
			beds[b.spawn_point] = b
	if when == "day":
		print("  doors: %s" % ", ".join(doors.map(func(d): return "%s@%s" % [d.room, Vector2i(d.global_position)])))
	for d in doors:
		var status = str(taverns.room_status(loc, d.room))
		var shape: RectangleShape2D = d.get_node("CollisionShape2D").shape
		var bed: Node2D = beds.get(d.room)
		if bed == null:
			_check("%s: door %s has a bed behind it" % [loc, d.room], false)
			continue
		var c: Vector2 = d.global_position
		var normal: Vector2
		if shape.size.x >= shape.size.y:
			normal = Vector2(0, signf(bed.global_position.y - c.y))
		else:
			normal = Vector2(signf(bed.global_position.x - c.x), 0)
		var along = Vector2(absf(normal.y), absf(normal.x))
		var half = (shape.size.x if along.x > 0 else shape.size.y) / 2.0
		if when == "day":
			# The gap: walls on both sides of the door's centre, the area centred in it and as wide
			# Find the wall line: step out from the area's centre until walls stand close on both sides
			var depth = (shape.size.y if along.x > 0 else shape.size.x) / 2.0
			var k = -1.0
			var a = -1.0
			var b = -1.0
			for i in range(0, 80, 2):
				a = _wall_distance(c - normal * i, along)
				b = _wall_distance(c - normal * i, -along)
				if a >= 0 and b >= 0 and a + b <= 200:
					k = float(i)
					break
			_check("%s: door %s sits across its doorway (gap %.0f, area %.0f, off-centre %.0f, %.0f from the wall line, area depth %.0f)" % [loc, d.room, a + b, half * 2, absf(a - b) / 2.0, k, depth],
				k >= 0 and k <= depth + 14 and absf(a - b) <= 12.0 and half * 2 >= (a + b) * 0.6 and half * 2 <= a + b + 8)
		# Hug the wall outside, beside the door, and walk past it: no deed
		var before = pe.order.size()
		d._last_night = -1
		player.global_position = c - normal * 110 - along * (half + 50)
		await _frames(2)
		await _walk(player, normal * 110, 40)   # up against the wall
		await _walk(player, along * (2 * half + 100), 60)
		var past = pe.order.slice(before).filter(func(id): return pe.events[id].kind == "trespass")
		_check("%s %s: hugging the wall past door %s (%s) is no deed" % [loc, when, d.room, status], past.is_empty())
		# Walk in through the gap
		before = pe.order.size()
		d._last_night = -1
		player.global_position = c - normal * 80 + Vector2(0, 24) * along.y
		await _frames(3)
		var reached = await _walk(player, normal * 150, 70)
		var got = pe.order.slice(before).map(func(id): return pe.events[id]).filter(func(e): return e.kind == "trespass")
		await _shot("%s_4_door_%s_%s" % [loc, d.room, status], player.global_position + normal * -40, 1.5)
		_check("%s %s: the player walks in through door %s (moved %.0f of 150)" % [loc, when, d.room, reached], reached > 130.0)
		match status:
			"taken", "back_room":
				_check("%s %s: into %s (%s) is one trespass deed (%s)" % [loc, when, d.room, status, got.map(func(e): return e.summary)], got.size() == 1)
			_:
				_check("%s %s: into %s (%s) is no deed" % [loc, when, d.room, status], got.is_empty())
		player.global_position = c - normal * 80
		await _frames(3)

func _d_reset(d) -> void:
	d._last_night = -1

## How far from p along dir the first wall is (-1 = none within 300)
func _wall_distance(p: Vector2, dir: Vector2) -> float:
	for i in range(0, 300, 2):
		if not _point_free(p + dir * i):
			return float(i)
	return -1.0

func _point_free(p: Vector2) -> bool:
	var q = PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 4
	return current_scene.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()

## Move the body by `by` in `frames` physics steps (stopping at walls). Returns the distance covered
func _walk(body: CharacterBody2D, by: Vector2, frames: int) -> float:
	var start = body.global_position
	for i in frames:
		body.move_and_collide(by / frames)
		await physics_frame
	await process_frame
	return body.global_position.distance_to(start) if by.length() > 0 else 0.0

# =============================================================================
# RENTING
# =============================================================================

const EXPLICIT = ["naked", "nude", "undress", "sex", "breast", "thigh", "moan", "lust", "aroused", "kiss", "caress", "strip"]

func _world_rent(loc: String) -> int:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://resources/world/world.json"))
	for l in data.locations:
		if str(l.get("id", "")) == loc:
			return int(l.tavern.rent_copper)
	return -1

func _renting(loc: String, scene: Node) -> void:
	taverns.reset()
	pe.reset()
	inv.reset()
	day += 1
	var keeper = str(taverns.tavern(loc).keeper)
	var rent = _world_rent(loc)
	var beds = scene.find_children("*", "Area2D", true, false).filter(func(b): return b is Bed and not b.back_room)
	_check("%s: the house rent is world.json's %d copper, and every room's bed asks it" % [loc, rent], taverns.rent_of(loc) == rent and beds.all(func(b): return b.rent == rent))
	_clock(day * DAY + 20 * 60)
	await _frames(4)
	inv.coin = 100
	var res: Dictionary = director.apply_conversation_actions(keeper, [{"type": "rent_room", "price": rent}])
	var mine: Dictionary = taverns.my_room(loc)
	_check("%s: %s lets a room in conversation for %d (%s)" % [loc, keeper, rent, str(res.applied if not res.applied.is_empty() else res.dropped)], res.applied.size() == 1 and inv.get_coin() == 100 - rent and not mine.is_empty())
	if mine.is_empty():
		return
	_check("%s: ...the room is the player's until 10:00 next morning" % loc, int(mine.until) == (day + 1) * DAY + 10 * 60)
	var bed = beds.filter(func(b): return b.spawn_point == str(mine.room))[0]
	var r: Dictionary = bed.sleep()
	_check("%s: ...a sleep in it that night is free and sets where the player wakes" % loc, r.ok and r.paid == 0 and inv.get_coin() == 100 - rent and stats.get_respawn().spawn_point == bed.spawn_point)
	_clock(day * DAY + 23 * 60)
	r = bed.sleep()
	_check("%s: ...and again later that night" % loc, r.ok and r.paid == 0)
	# Save and load through WorldState, to the scratch save
	_check("%s: ...saved (to %s)" % [loc, ws.save_path], ws.save_game())
	taverns.reset()
	ws.load_game()
	ws._apply_player_systems_state()  # what startup's _apply_late_save_state does once autoloads are ready
	await _frames(2)
	_check("%s: ...and loaded, the room is still the player's (%s)" % [loc, str(taverns.my_room(loc))], str(taverns.my_room(loc).get("room", "")) == str(mine.room))
	_clock((day + 1) * DAY + 9 * 60 + 59)
	_check("%s: ...still theirs at 09:59" % loc, not taverns.my_room(loc).is_empty())
	_clock((day + 1) * DAY + 10 * 60)
	_check("%s: ...not at 10:00" % loc, taverns.my_room(loc).is_empty())
	r = bed.sleep()
	_check("%s: a new night costs the rent again (%d)" % [loc, int(r.get("paid", -1))], r.ok and r.paid == rent)
	# A keeper who thinks badly of the player
	taverns.reset()
	for i in 6:
		if Rep.of("npc", keeper) < taverns.REFUSE_BELOW:
			break
		pe.record("harm", "beat a drinker senseless in the taproom", [keeper], {"witnesses": [keeper], "location": loc, "spread": false})
	var opinion = Rep.of("npc", keeper)
	r = bed.sleep()
	res = director.apply_conversation_actions(keeper, [{"type": "rent_room", "price": rent}])
	_check("%s: %s at %.0f will not let a room, at the bed (%s) or in conversation" % [loc, keeper, opinion, r.reason],
		opinion < -30 and not r.ok and str(r.reason).contains("will not let") and res.applied.is_empty())
	pe.reset()
	taverns.reset()

func _back_rooms(loc: String) -> void:
	day += 1
	for h in [[14, false], [15, true], [23, true], [24, false]]:
		_clock(day * DAY + int(h[0]) * 60 + 30)
		await _frames(4)
		var here = taverns.companions(loc)
		_check("%s: at %02d:30 the companions are %s (%s)" % [loc, int(h[0]) % 24, "in" if h[1] else "away", str(here)], (not here.is_empty()) == h[1])
	_clock((day + 1) * DAY + 20 * 60)
	await _frames(6)
	var companion = str(taverns.companions(loc)[0])
	var block: String = director.get_conversation_agency_block(companion)
	var arch_text = FileAccess.get_file_as_string("res://resources/generics/archetypes/house_companion.md").to_lower()
	var said = block.to_lower() + "\n" + arch_text
	var words = EXPLICIT.filter(func(w): return said.contains(" " + w))
	_check("%s: nothing in the companion's prompt or archetype invites explicit content (%s)" % [loc, words], words.is_empty() and block.contains("never describe it"))
	# Closed while a child is in the house
	var child = ""
	for id in gm().get_ids():
		if gm().is_minor(id):
			child = id
			break
	taverns.present_override[loc] = taverns._present(loc).duplicate() + [child]
	_check("%s: with a child (%s) in the house the back rooms are shut and company is not offered" % [loc, child],
		not taverns.brothel_open(loc) and not director.get_conversation_agency_block(companion).contains("\"company\""))
	var res = director.apply_conversation_actions(companion, [{"type": "company", "price": 15}])
	_check("%s: ...nor taken" % loc, res.applied.is_empty())
	taverns.present_override = {}
	inv.coin = 40
	var before = ws.game_minutes
	res = director.apply_conversation_actions(companion, [{"type": "company", "price": taverns.COMPANY_COPPER}])
	await create_timer(0.7).timeout
	await _shot("%s_5_back_room_fade" % loc, sm.player_instance.global_position, 1.0)
	var dark = float(sm.fade_overlay.modulate.a)
	_check("%s: company costs %d copper and an hour (coin %d, minutes %d)" % [loc, taverns.COMPANY_COPPER, inv.get_coin(), ws.game_minutes - before], res.applied.size() == 1 and inv.get_coin() == 40 - 15 and ws.game_minutes - before == 60)
	_check("%s: ...the screen fades to black (overlay %.2f)" % [loc, dark], dark > 0.95)
	await create_timer(2.0).timeout
	await _shot("%s_6_back_room_after" % loc)
	_check("%s: ...and comes back (overlay %.2f)" % [loc, float(sm.fade_overlay.modulate.a)], float(sm.fade_overlay.modulate.a) < 0.05)
	var seen = pe.order.map(func(id): return pe.events[id]).filter(func(e): return e.kind == "seen_at" and str(e.summary).contains("back rooms"))
	_check("%s: ...the deed says only where they went (%s)" % [loc, seen.map(func(e): return e.summary)], seen.size() == 1 and not EXPLICIT.any(func(w): return str(seen[0].summary).contains(w)))

func gm():
	return root.get_node("DynamicNPCRegistry").generics

## Screenshot: the whole interior, or a close view at `at`
func _shot(name: String, at: Vector2 = Vector2.INF, zoom: float = 0.0) -> void:
	var cam = Camera2D.new()
	current_scene.add_child(cam)
	if at == Vector2.INF:
		var floor_node = current_scene.get_node_or_null("Floor")
		var rect = Rect2(floor_node.global_position, floor_node.size) if floor_node is Control else Rect2(-1000, -600, 2000, 1200)
		cam.global_position = rect.get_center()
		var z = minf(1920.0 / rect.size.x, 1080.0 / rect.size.y) * 0.95
		cam.zoom = Vector2(z, z)
	else:
		cam.global_position = at
		cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	await _frames(4)
	var img = root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	cam.queue_free()
	await process_frame
	print("  [shot] %s" % name)

func _check(label: String, ok: bool) -> void:
	print(("  ✅ " if ok else "  ❌ ") + label)
	if not ok:
		failures += 1
