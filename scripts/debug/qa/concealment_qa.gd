extends SceneTree

# QA driver (windowed): rangers' Concealment on the forest path by day and night, near trees and in the
# open, at several distances; saves screenshots and prints each body's alpha / seen.
# Run (not headless): CLAUDE_API_KEY= ELEVENLABS_API_KEY= godot --path . -s res://scripts/debug/qa/concealment_qa.gd -- <out_dir>
# Writes no save (autosave off) and records no deeds (PlayerEvents capture off)

const FOREST = "res://scenes/exterior/forest_path.tscn"
const LAMP = preload("res://scripts/world/physics/lamp.gd")
const TREES = Vector2(430, 385)   # between Tree14 and AshTree4: full cover
const OPEN = Vector2(-20, 20)     # the fork: open ground

var out_dir: String = "user://qa_concealment"
var world_state: Node
var scene: Node
var player: Node2D
var renna: Node2D
var ranger: Node2D
var saved_minutes: int

func _init():
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var config = root.get_node_or_null("Config")
	if config and config.has_method("get_claude_api_key") and str(config.get_claude_api_key()) != "":
		print("QA: an API key is present; stopping")
		quit(2)
		return
	world_state = root.get_node("WorldState")
	world_state.autosave_enabled = false
	world_state.set_idle_clock_rate(0.0)
	saved_minutes = world_state.game_minutes
	root.get_node("PlayerEvents").capture_enabled = false
	root.get_node("WorldPhysics").set_weather("clear", Vector2.ZERO, -1)
	change_scene_to_file(FOREST)
	for i in 20:
		await process_frame
	scene = current_scene
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	renna = load("res://scenes/npcs/renna.tscn").instantiate()
	scene.add_child(renna)
	renna.global_position = TREES
	var gm = root.get_node("DynamicNPCRegistry").generics
	ranger = load("res://scenes/npcs/generic_npc.tscn").instantiate()
	ranger.setup("gen_ranger_1", gm)
	scene.add_child(ranger)
	ranger.global_position = OPEN
	for body in [renna, ranger]:
		_stand_in(body)

	_hour(12)
	await _shot("day_trees_100", renna, TREES + Vector2(-100, 0))
	await _shot("day_trees_170", renna, TREES + Vector2(-170, 0))
	await _shot("day_trees_300", renna, TREES + Vector2(-300, 0))
	await _shot("day_open_250", ranger, OPEN + Vector2(250, 0))
	await _shot("day_open_380", ranger, OPEN + Vector2(380, 0))
	await _shot("day_open_520", ranger, OPEN + Vector2(520, 0))
	# Renna shoots (away from the player): the arrow shows where it came from
	await _shot("day_trees_300_before_shot", renna, TREES + Vector2(-300, 0))
	var mark = Node2D.new()
	scene.add_child(mark)
	mark.global_position = TREES + Vector2(0, -300)
	root.get_node("Combat").shoot(renna, root.get_node("Combat").get_weapon_def("hunting_bow"), mark)
	await _shot("day_trees_300_after_shot", renna, TREES + Vector2(-300, 0), 0.4)
	await _shot("day_trees_300_shot_plus_6s", renna, TREES + Vector2(-300, 0), 6.0)

	_hour(23)
	await _shot("night_trees_100", renna, TREES + Vector2(-100, 0))
	await _shot("night_trees_35", renna, TREES + Vector2(-35, 0))
	await _shot("night_open_150", ranger, OPEN + Vector2(150, 0))
	await _shot("night_open_80", ranger, OPEN + Vector2(80, 0))
	var lantern = Node2D.new()
	lantern.name = "QALantern"
	scene.add_child(lantern)
	lantern.global_position = TREES + Vector2(10, 10)
	var lamp = LAMP.new()
	lamp.exposure = "outdoors"
	lamp.lit = true
	lantern.add_child(lamp)
	await _shot("night_trees_100_lamp", renna, TREES + Vector2(-100, 0))
	lantern.queue_free()

	world_state.game_minutes = saved_minutes
	print("QA: done")
	quit(0)

func _hour(h: int) -> void:
	world_state.game_minutes = (saved_minutes / 1440) * 1440 + h * 60

## Put the player at `at`, let the fade and the camera settle, save a screenshot
func _shot(label: String, who: Node2D, at: Vector2, wait: float = 2.5) -> void:
	player.global_position = at
	var cam = player.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()
	await create_timer(wait).timeout
	var c = who.get_node_or_null("Concealment")
	var o = c.current_opts() if c else {}
	print("QA %s: %s alpha %.2f seen %s distance %.0f cover %.2f sight %.2f prompt %s" % [label, who.npc_name,
		c.alpha if c else 1.0, c.seen if c else true, float(o.get("distance", 0)), float(o.get("cover", 0)), float(o.get("sight", 1)),
		who.get_node("InteractionPrompt").visible])
	await RenderingServer.frame_post_draw
	var img = root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(label + ".png"))

## Without a cached sprite the body draws nothing but its label: give it a plain stand-in so the fade
## shows (a child of the body, so it takes the body's alpha as the sprite would)
func _stand_in(body: Node2D) -> void:
	var sprite = body.get_node_or_null("AnimatedSprite2D")
	if sprite and sprite.sprite_frames != null:
		return
	var r = ColorRect.new()
	r.color = Color(0.3, 0.5, 0.3) if body == renna else Color(0.45, 0.4, 0.3)
	r.size = Vector2(24, 44)
	r.position = Vector2(-12, -46)
	body.add_child(r)
	print("QA: %s has no sprite frames; drawing a stand-in" % body.npc_name)
