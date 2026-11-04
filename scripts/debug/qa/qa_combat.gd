extends SceneTree

# QA driver (windowed): fights and puzzle doors in the real game scenes, with screenshots and a trace.
# Not a headless suite. Run one scenario at a time:
#   CLAUDE_API_KEY= ELEVENLABS_API_KEY= godot --path . -s res://scripts/debug/qa/qa_combat.gd -- \
#     --save-path=user://qa_combat_save.json --no-autosave --scenario=<name> --out=<dir>
# Scenarios: bow_player | bow_npc | bow_walls | bow_child | melee | wolf_door | wolf_exit | puzzles |
#   child_harm
# Never saves the real game (--save-path points elsewhere, autosave off); stops if any API key is set.

const DAY = 24 * 60
const AI = preload("res://scripts/combat/combat_ai.gd")

var out_dir: String = "user://qa_combat"
var scenario: String = ""
var world_state: Node
var director: Node
var registry: Node
var combat: Node
var scenes: Node
var pe: Node
var stats: Node
var player: Node2D
var log_lines: Array = []
var shots_seen: Dictionary = {}   # projectile instance id -> {born_ms, from, outcome}
var _frame: int = 0
var cam: Camera2D = null

func _init() -> void:
	await process_frame
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.substr(11)
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var config = root.get_node_or_null("Config")
	if config and (str(config.get("claude_api_key")) != "" or str(config.get("elevenlabs_api_key")) != ""):
		_log("STOP: an API key is configured; refusing to run")
		_finish(2)
		return
	world_state = root.get_node("WorldState")
	if world_state.save_path == world_state.SAVE_PATH:
		_log("STOP: no --save-path override; refusing to touch the real save")
		_finish(2)
		return
	world_state.autosave_enabled = false
	world_state.set_idle_clock_rate(0.0)
	world_state.game_minutes = DAY + 12 * 60
	director = root.get_node("StorylineDirector")
	director.round_boundaries_enabled = false
	director.set_round_timer_paused(true)
	director.set_agency_mode("offline")
	registry = root.get_node("WorldRegistry")
	combat = root.get_node("Combat")
	scenes = root.get_node("SceneManager")
	pe = root.get_node("PlayerEvents")
	stats = root.get_node("PlayerStats")
	_log("scenario %s" % scenario)
	match scenario:
		"bow_player": await _bow_player()
		"bow_npc": await _bow_npc()
		"bow_walls": await _bow_walls()
		"bow_child": await _bow_child()
		"melee": await _melee()
		"wolf_door": await _wolf_door()
		"wolf_exit": await _wolf_exit()
		"puzzles": await _puzzles()
		"child_harm": await _child_harm()
		_: _log("unknown scenario")
	_finish(0)

# =============================================================================
# SCENARIOS
# =============================================================================

## Renna against the player in the forest: closes from far, shoots at range, gives ground, draws the
## sword when closed on, sheathes with room, runs out of arrows
func _bow_player() -> void:
	await _go("forest_path")
	await _clear_creatures()
	var renna = await _bring("renna")
	player.global_position = Vector2(280, 20)  # clear of the scene's exits, open wood to the west
	renna.global_position = player.global_position + Vector2(-480, 0)
	_force_fight(renna, player)
	_log("phase far: player 480 away (keep_range 150..360)")
	await _watch(renna, 3.0, "far")
	_log("phase hold: player stands still")
	await _watch(renna, 7.0, "range")
	_log("phase press: player walks at her")
	await _walk_player_toward(renna, 60.0, 4.0, "press")
	await _watch(renna, 2.0, "close")
	_log("phase closed_on: player steps in to 50")
	player.global_position = renna.global_position + (player.global_position - renna.global_position).normalized() * 50.0
	await _watch(renna, 3.0, "closed_on")
	_log("phase retreat: player backs off 300")
	await _move_player_to(renna.global_position + (player.global_position - renna.global_position).normalized() * 320.0, 1.5)
	await _watch(renna, 3.0, "retreat")
	_log("phase empty: three arrows left")
	renna.arrows = 3
	await _watch(renna, 9.0, "empty")
	await _report_shots()

## Renna against a hostile NPC (a Hollow grunt with a sword): her arrows reach him, his blade her
func _bow_npc() -> void:
	await _go("forest_path")
	await _clear_creatures()
	var renna = await _bring("renna")
	var grunt = await _bring("gen_hollow_grunt_1", true)
	if grunt == null:
		grunt = await _bring_any_generic("hollow_grunt")
	renna.global_position = player.global_position + Vector2(-200, -120)
	grunt.global_position = player.global_position + Vector2(220, -120)
	_force_fight(renna, grunt)
	_force_fight(grunt, renna)
	await _watch(renna, 12.0, "vs_grunt", grunt)
	await _report_shots()

## A generic ranger and the player on two sides of a building (walls on world_solid)
func _bow_walls() -> void:
	await _go("thornhaven_town_square")
	var ranger = await _bring("gen_ranger_1", true)
	var wall = _find_solid_near(player.global_position, 900.0)
	if wall.is_empty():
		_log("no world_solid body found")
		return
	var r: Rect2 = wall.rect
	_log("wall %s rect %s" % [wall.name, r])
	player.global_position = Vector2(r.get_center().x, r.end.y + 40)
	ranger.global_position = Vector2(r.get_center().x + 40, r.position.y - 60)
	_log("los at start: %s" % combat.has_line_of_sight(ranger, player))
	_force_fight(ranger, player)
	await _watch(ranger, 14.0, "walls")
	_log("phase loose_into_wall: an arrow loosed at the player with the house between them")
	ranger.end_fight("over", false)
	ranger.global_position = Vector2(r.get_center().x, r.position.y - 40)
	player.global_position = Vector2(r.get_center().x, r.end.y + 40)
	await _wait(0.3)
	_log("los now %s" % combat.has_line_of_sight(ranger, player))
	var p = combat.shoot(ranger, combat.weapon_of(ranger), player)
	_track_projectiles()
	await _wait(0.1)
	await _shot("bow_walls_arrow_at_wall")
	await _wait(1.0)
	await _report_shots()

## A ranger shooting at the player with Rook in the line, then out of it; and set on Rook
func _bow_child() -> void:
	await _go("forest_path")
	await _clear_creatures()
	var ranger = await _bring("gen_ranger_1", true)
	var rook = await _bring("rook")
	ranger.global_position = player.global_position + Vector2(-260, 0)
	rook.global_position = player.global_position + Vector2(-130, 4)
	rook.set_physics_process(false)
	_force_fight(ranger, player)
	_log("phase child_in_line")
	await _watch(ranger, 5.0, "child_in_line")
	rook.global_position = player.global_position + Vector2(-130, 160)
	_log("phase child_clear")
	await _watch(ranger, 4.0, "child_clear")
	_log("phase set_on_child")
	ranger.end_fight("over", false)
	_force_fight(ranger, rook)
	await _watch(ranger, 5.0, "on_child", rook)
	await _report_shots()

## Melee alongside: a garrison soldier and Bjorn's hammer against the player
func _melee() -> void:
	await _go("thornhaven_town_square")
	var bjorn = await _bring("bjorn")
	var soldier = await _bring_any_generic("garrison_soldier")
	bjorn.global_position = player.global_position + Vector2(-200, 0)
	soldier.global_position = player.global_position + Vector2(200, 30)
	_force_fight(bjorn, player)
	_force_fight(soldier, player)
	await _watch(bjorn, 6.0, "melee", soldier)

## A wolf chases the player to the Spoil Heap's door: waits outside, gives up, goes home
func _wolf_door() -> void:
	await _go("greystone_mines")
	var door = scenes.get_tree().current_scene.find_child("TheSpoilHeapDoor", true, false)
	var wolf = _spawn_wolf(door.global_position + Vector2(-260, 60))
	player.global_position = door.global_position + Vector2(-120, 60)
	await _watch_wolf(wolf, 1.5, "chase")
	player.global_position = door.global_position
	_log("player in the door zone")
	await _watch_wolf(wolf, 7.0, "door")
	player.global_position = door.global_position + Vector2(0, 400)
	_log("player out again, far off: the wolf has given up on them")
	await _watch_wolf(wolf, 4.0, "home")

## The same wolf at a scene exit that is not a building (the forest path's way to the village gate)
func _wolf_exit() -> void:
	await _go("forest_path")
	var exit_ = null
	for t in scenes.get_tree().current_scene.find_children("*", "Area2D", true, false):
		if str(t.get("target_location")) == "village_gate":
			exit_ = t
	var wolf = _spawn_wolf(exit_.global_position + Vector2(0, 200))
	player.global_position = exit_.global_position + Vector2(0, 90)
	await _watch_wolf(wolf, 1.5, "chase")
	player.global_position = exit_.global_position
	_log("player in the exit zone (not a building)")
	await _watch_wolf(wolf, 6.0, "exit")

## The puzzle rooms: the ways in, the shut Pit gate and its opening, the clue examinables
func _puzzles() -> void:
	await _go("greystone_mines")
	var stair = scenes.get_tree().current_scene.find_child("OldWorkingsStair", true, false)
	player.global_position = stair.global_position + Vector2(0, 60)
	await _wait(0.5)
	await _shot("puzzle_greystone_stair_approach")
	player.global_position = stair.global_position
	await _wait(0.5)
	await _shot("puzzle_greystone_stair_prompt")
	await _press_interact()
	await _await_location("old_workings")
	await _shot("puzzle_old_workings_in")
	var gate = _trigger_to("the_pit")
	_log("pit gate: %s requires %s open=%s" % [gate.name if gate else "none", gate.requires_flag if gate else "", gate.is_open() if gate else false])
	world_state.set_world_flag("old_workings_way_found", false)
	player.global_position = gate.global_position
	await _wait(0.5)
	await _press_interact()
	await _wait(1.0)
	await _shot("puzzle_pit_gate_closed")
	_log("still in %s" % scenes.get_current_location_id())
	# Play the room the way a player would: the tub onto the treadle, then the rope cut with a knife
	var room = scenes.get_tree().current_scene
	var tub = room.find_child("OreTub", true, false)
	player.global_position = tub.global_position + Vector2(0, -30)
	await _wait(0.4)
	_log("push the tub: %s" % [tub.find_child("Push", false, false).perform()])
	await _wait(1.0)
	var inv = root.get_node("Inventory")
	if not inv.has("knife"):
		inv.add("knife")
	var rope = room.find_child("CageRope", true, false)
	player.global_position = rope.global_position + Vector2(30, 0)
	await _wait(0.4)
	_log("cut the rope: %s" % [rope.find_child("Cut", false, false).perform()])
	await _wait(1.0)
	await _shot("puzzle_rope_cut")
	_log("way found=%s gate open=%s why=%s" % [world_state.get_world_flag("old_workings_way_found"), gate.is_open(), gate.why_closed()])
	player.global_position = gate.global_position + Vector2(0, 60)
	await _wait(0.4)
	player.global_position = gate.global_position
	await _wait(0.6)
	await _press_interact()
	await _await_location("the_pit")
	await _shot("puzzle_pit_reached")
	world_state.set_world_flag("old_workings_way_found", false)
	# The abbey's undercroft
	await _go("brackenmoor_abbey")
	var down = _trigger_to("abbey_undercroft")
	player.global_position = down.global_position
	await _wait(0.5)
	await _shot("puzzle_abbey_stair")
	await _press_interact()
	await _await_location("abbey_undercroft")
	await _shot("puzzle_undercroft_in")
	# The clues
	for pair in [["thornhaven_chapel", "UrnTiles"], ["thornhaven_blacksmith", "BjornsScale"], ["brackenmoor_abbey", "AnselmShelfIndex"]]:
		await _go(pair[0])
		var item = scenes.get_tree().current_scene.find_child(pair[1], true, false)
		if item == null:
			_log("%s: no %s" % [pair[0], pair[1]])
			continue
		player.global_position = item.global_position + Vector2(0, 40)
		await _wait(0.6)
		await _press_interact()
		await _wait(1.2)
		await _shot("clue_%s" % pair[1])
		_log("%s %s examined" % [pair[0], pair[1]])
		await _press_key(KEY_ESCAPE)
		await _wait(0.3)

## The player strikes a Warrens urchin: the deed is recorded with victim_minor; the child flees or cries;
## nobody turns on the child
func _child_harm() -> void:
	await _go("capitol_warrens")
	var urchin = await _bring_any_generic("warrens_urchin")
	urchin.global_position = player.global_position + Vector2(30, 0)
	player.call("_update_facing_direction", Vector2.RIGHT)
	var before = pe.get_events().size()
	await _wait(0.3)
	await _shot("child_before")
	var hit = combat.attack(player, urchin, "light")
	_log("strike: %s" % [hit])
	await _wait(0.5)
	var events = pe.get_events()
	for i in range(before, events.size()):
		var e = events[i]
		_log("deed %s about=%s victim_minor=%s" % [e.get("kind"), e.get("about"), e.get("victim_minor", e.get("opts", {}).get("victim_minor", "?"))])
	_log("urchin state=%s cry_decision=%s" % [urchin.combat_state, urchin.last_combat_decision])
	for i in 12:
		await _wait(0.5)
		var targeting: Array = []
		for n in get_nodes_in_group("npcs"):
			if n != urchin and n.get("combat_foe") == urchin:
				targeting.append(str(n.get("npc_id")))
		for c in get_nodes_in_group("creatures"):
			if c.get("target") == urchin:
				targeting.append(str(c.name))
		var others: Array = []
		for n in get_nodes_in_group("npcs"):
			if n != urchin and str(n.get("combat_state")) != "":
				others.append("%s:%s>%s" % [n.get("npc_id"), n.get("combat_state"), AI.key_of(n.get("combat_foe")) if is_instance_valid(n.get("combat_foe")) else "-"])
		_log("t+%.1f urchin %s at %s dist %.0f; targeting the child: %s; others in a fight: %s" % [i * 0.5, urchin.combat_state, urchin.global_position.round(), urchin.global_position.distance_to(player.global_position), targeting, others])
		if i == 3:
			await _shot("child_after")

# =============================================================================
# HELPERS
# =============================================================================

func _go(location: String) -> void:
	scenes.transition_to(location, "default", 0.0, false)
	await _await_location(location)
	player = get_first_node_in_group("player")
	await _wait(0.4)

func _await_location(location: String) -> void:
	for i in 300:
		await process_frame
		if scenes.get_current_location_id() == location and not scenes.get("is_transitioning"):
			break
	await _wait(0.3)
	player = get_first_node_in_group("player")
	_log("in %s (player %s)" % [scenes.get_current_location_id(), player.global_position.round() if player else "none"])

## Puts a roster NPC (key) or a generic (id) in the current scene and returns its body
func _bring(key_or_id: String, generic: bool = false) -> Node2D:
	var id = key_or_id if generic else registry.get_npc_id(key_or_id)
	world_state.set_npc_location(id, scenes.get_current_location_id())
	scenes.refresh_npcs()
	await _wait(0.3)
	for n in get_nodes_in_group("npcs"):
		if str(n.get("npc_id")) == id:
			n.set("is_alive", true)
			_log("brought %s (%s)" % [id, n.name])
			return n
	_log("could not bring %s" % id)
	return null

func _bring_any_generic(archetype: String) -> Node2D:
	var gm = root.get_node("DynamicNPCRegistry").generics
	for id in gm.get_ids():
		if gm.get_instance(id).archetype_id == archetype:
			return await _bring(id, true)
	return null

## Frames the fighters: a camera of our own at their midpoint (the player's own camera follows only them)
func _frame_on(a: Node2D, b: Node2D) -> void:
	if not is_instance_valid(cam) or not cam.is_inside_tree():
		cam = Camera2D.new()
		scenes.get_tree().current_scene.add_child(cam)
	cam.make_current()
	var pts = [a.global_position, b.global_position] if is_instance_valid(b) else [a.global_position, a.global_position]
	cam.global_position = (pts[0] + pts[1]) / 2.0
	var span = maxf(absf(pts[0].x - pts[1].x) / 1500.0, absf(pts[0].y - pts[1].y) / 800.0)
	var z = clampf(1.0 / maxf(span, 0.5), 0.8, 2.0)
	cam.zoom = Vector2(z, z)

## The forest's own wolves and boars would run into the line of the shots: clear them for a bow duel
func _clear_creatures() -> void:
	for c in get_nodes_in_group("creatures"):
		c.queue_free()
	for c in scenes.get_tree().current_scene.find_children("*", "CharacterBody2D", true, false):
		if c.get("creature_id") != null and str(c.get("creature_id")) != "":
			c.queue_free()
	await process_frame

func _force_fight(npc, foe) -> void:
	npc._fight = {"foe_key": AI.key_of(foe), "band": "steady", "harm_recorded": true, "help_recorded": true, "last_hit_ms": Time.get_ticks_msec()}
	npc._set_combat_state({"action": "fight", "side": "", "band": "steady"}, foe)
	_log("%s fights %s" % [npc.npc_id, AI.key_of(foe)])

func _spawn_wolf(at: Vector2) -> Node2D:
	var wolf = load("res://scenes/creatures/wolf.tscn").instantiate()
	var scene_root = scenes.get_tree().current_scene
	scene_root.add_child(wolf)
	wolf.global_position = at
	wolf.home = wolf.position
	wolf.zone_root = scene_root
	if wolf.has_method("setup") and wolf.def.is_empty():
		wolf.setup("wolf")
		wolf.home = wolf.position
	_log("wolf at %s (home %s)" % [wolf.global_position.round(), wolf.home.round()])
	return wolf

## Samples a fighter every 0.25 s: distance, velocity, weapon in hand, arrows, projectiles alive
func _watch(npc, seconds: float, tag: String, other = null) -> void:
	var steps = int(seconds / 0.25)
	for i in steps:
		_keep_alive(npc, other)
		await _wait(0.25)
		_track_projectiles()
		if not is_instance_valid(npc):
			return
		var foe = npc.combat_foe
		var d = npc.global_position.distance_to(foe.global_position) if is_instance_valid(foe) else -1.0
		var line = "[%s] %s state=%s d=%.0f v=%s hand=%s arrows=%d cd=%.2f los=%s arrows_in_air=%d" % [tag, npc.npc_id, npc.combat_state, d,
			npc.velocity.round(), npc.get_combat_profile().weapon, npc.arrows_left(), npc._attack_cooldown,
			combat.has_line_of_sight(npc, foe) if is_instance_valid(foe) else false, _live_projectiles().size()]
		line += " at %s player@%s" % [npc.global_position.round(), player.global_position.round()]
		if is_instance_valid(foe):
			var col = npc.move_and_collide((foe.global_position - npc.global_position).normalized() * 22.0, true)
			if col:
				line += " ahead:%s" % col.get_collider().name
		_frame_on(npc, foe if is_instance_valid(foe) else player)
		if other and is_instance_valid(other):
			line += " | %s state=%s hp=%.0f v=%s at %s hand=%s" % [other.npc_id, other.combat_state, other.health, other.velocity.round(), other.global_position.round(), other.get_combat_profile().weapon] + " phys=%s stag=%s foe=%s" % [other.is_physics_processing(), other.is_staggered(), AI.key_of(other.combat_foe) if is_instance_valid(other.combat_foe) else "none"]
		_log(line)
		if i % 4 == 0:
			await _shot("%s_%s_%02d" % [scenario, tag, i / 4])

func _watch_wolf(wolf, seconds: float, tag: String) -> void:
	var steps = int(seconds / 0.25)
	for i in steps:
		_keep_alive(null, null)
		await _wait(0.25)
		var zones = wolf.zone_at(wolf.global_position)
		_log("[%s] wolf state=%s at %s d_player=%.0f d_home=%.0f in_zone=%s" % [tag, wolf.state, wolf.global_position.round(),
			wolf.global_position.distance_to(player.global_position), wolf.global_position.distance_to(wolf._home_global()), zones.map(func(z): return z.name)])
		_frame_on(wolf, player)
		if i % 4 == 0:
			await _shot("%s_%s_%02d" % [scenario, tag, i / 4])

func _keep_alive(npc, other) -> void:
	if stats and stats.get_health() < stats.get_max_health():
		stats.heal(stats.get_max_health())
	for n in [npc, other]:
		if n and is_instance_valid(n) and "health" in n and n.health < 40.0:
			n.health = n.max_health

func _walk_player_toward(npc, stop_at: float, seconds: float, tag: String) -> void:
	var steps = int(seconds / 0.05)
	for i in steps:
		_keep_alive(npc, null)
		await _wait(0.05)
		var to = npc.global_position - player.global_position
		if to.length() > stop_at:
			player.global_position += to.normalized() * 110.0 * 0.05
		_frame_on(npc, player)
		if i % 5 == 0:
			_track_projectiles()
			_log("[%s] d=%.0f %s v=%s hand=%s" % [tag, to.length(), npc.combat_state, npc.velocity.round(), npc.get_combat_profile().weapon])
		if i % 20 == 0:
			await _shot("%s_%s_%02d" % [scenario, tag, i / 20])

func _move_player_to(at: Vector2, seconds: float) -> void:
	var from = player.global_position
	var steps = int(seconds / 0.05)
	for i in steps:
		await _wait(0.05)
		player.global_position = from.lerp(at, float(i + 1) / steps)

func _live_projectiles() -> Array:
	var out: Array = []
	var scene_root = scenes.get_tree().current_scene
	for c in scene_root.get_children():
		if c is Area2D and c.collision_layer == 64:
			out.append(c)
	return out

func _track_projectiles() -> void:
	for p in _live_projectiles():
		var id = p.get_instance_id()
		if not shots_seen.has(id):
			shots_seen[id] = {"born": Time.get_ticks_msec(), "from": str(p.shooter.get("npc_id")), "outcome": "", "pos": p.global_position.round()}
			p.landed.connect(func(o): _on_landed(id, o))
			if shots_seen.size() <= 6:
				_flight_shot(p, shots_seen.size())

## A frame of an arrow in flight (fired and forgotten: the watch loop goes on)
func _flight_shot(p: Node2D, n: int) -> void:
	await physics_frame
	if is_instance_valid(p) and is_instance_valid(cam):
		cam.global_position = p.global_position
		cam.zoom = Vector2(2.5, 2.5)
		await process_frame
		if is_instance_valid(p):
			_log("  arrow %d in flight at %s, on screen at %s, visible %s, z %d, cam %s zoom %s current %s" % [n, p.global_position.round(),
				p.get_global_transform_with_canvas().origin.round(), p.is_visible_in_tree(), p.z_index, cam.global_position.round(), cam.zoom, cam.is_current()])
		await _shot("%s_arrow_in_flight_%d" % [scenario, n])

func _on_landed(id: int, o: Dictionary) -> void:
	var s = shots_seen[id]
	var what = "wall" if o.has("wall") else ("spent" if o.has("spent") else "hit %s dmg %.1f" % [AI.key_of(o.get("fighter")), float(o.get("result", {}).get("damage", 0))])
	s.outcome = what
	s["life_ms"] = Time.get_ticks_msec() - int(s.born)
	_log("  arrow from %s: %s after %d ms" % [s.from, what, s.life_ms])

func _report_shots() -> void:
	await _wait(1.5)
	var unfinished = shots_seen.values().filter(func(s): return s.outcome == "")
	_log("SHOTS %d, still in flight or never landed %d, alive now %d" % [shots_seen.size(), unfinished.size(), _live_projectiles().size()])

func _find_solid_near(at: Vector2, radius: float) -> Dictionary:
	var best = {}
	for b in scenes.get_tree().current_scene.find_children("*", "StaticBody2D", true, false):
		if (b.collision_layer & 4) == 0:
			continue
		for cs in b.get_children():
			if cs is CollisionShape2D and cs.shape is RectangleShape2D:
				var size: Vector2 = cs.shape.size * cs.global_scale
				if size.x < 120 or size.y < 80 or size.x > 600:
					continue
				var rect = Rect2(cs.global_position - size / 2.0, size)
				var d = rect.get_center().distance_to(at)
				if d < radius and (best.is_empty() or d < best.d):
					best = {"name": str(b.name), "rect": rect, "d": d}
	return best

func _trigger_to(location: String) -> Node:
	for t in scenes.get_tree().current_scene.find_children("*", "Area2D", true, false):
		if str(t.get("target_location")) == location:
			return t
	return null

func _press_interact() -> void:
	var ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up = InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(0.2)

func _press_key(code: int) -> void:
	var ev = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout
	_unpause()

## A new game's difficulty card (or any panel left open) pauses the world: name it and close it
func _unpause() -> void:
	if not paused:
		return
	var who: Array = []
	for n in root.find_children("*", "", true, false):
		var open_ = n.get("is_open")
		if open_ is bool and open_:
			who.append(str(n.name))
			if n.has_method("choose"):
				n.choose("normal")
			elif n.has_method("close"):
				n.close()
	if paused:
		paused = false
	_log("unpaused (open: %s)" % [who])

func _shot(name: String) -> void:
	# The frame just drawn, not a stale texture: a window the OS reports covered draws nothing
	var drawn = [false]
	var mark = func(): drawn[0] = true
	RenderingServer.frame_post_draw.connect(mark, CONNECT_ONE_SHOT)
	for i in 30:
		await process_frame
		if drawn[0]:
			break
	if not drawn[0]:
		RenderingServer.frame_post_draw.disconnect(mark)
		_log("NO FRAME DRAWN for %s (window covered?)" % name)
		return
	var img = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])

func _log(line: String) -> void:
	print("[QA] " + line)
	log_lines.append(line)

func _finish(code: int) -> void:
	var f = FileAccess.open("%s/%s.log" % [out_dir, scenario if scenario != "" else "qa"], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()
	quit(code)
