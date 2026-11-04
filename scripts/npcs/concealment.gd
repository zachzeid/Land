extends Node
## Concealment - whether the player can make out a woodwise watcher in the wilds (docs/WORLD_SCHEMA.md §9.1)
## A child of an NPC body whose kind can hide (CharacterTypes.can_hide: the woodwise trait and some
## stealth skill; rangers today). Outdoors and outside any settlement the body is drawn faded, then not
## at all, beyond the distance the player makes them out at: it shrinks with their stealth and the
## cover around them (props on world_obstacle: trees, brush), at night (WorldPhysics.sight_factor at
## their spot, so a lamp or fire near them gives them away) and when the player stands in light and
## looks into the dark (glare_factor); it grows with the player's own stealth (it takes one to know
## where one would hide). Moving, loosing an arrow (for SHOT_SECONDS), being struck, or speaking to the
## player shows them. While unseen the name label and interaction prompt are hidden and the player
## cannot talk to them (BaseNPC.is_seen_by_player). This is only the player's eye: Witnesses still
## counts them as seeing what they see

const CharacterTypes = preload("res://scripts/npcs/character_types.gd")
const Witnesses = preload("res://scripts/world/witnesses.gd")
const SELF_PATH = "res://scripts/npcs/concealment.gd"
const NODE_NAME = "Concealment"

const SPOT_RANGE = 520.0       # Witnesses.DAY_RANGE: anyone's eye by day
const HIDE_SHRINK = 0.9        # fully hidden, they are made out at a tenth of that
const OPEN_COVER = 0.5         # open ground: stealth counts half
const FULL_COVER = 1.8         # among trees: stealth counts nearly twice
const PERCEPTION_BONUS = 0.5   # the player's stealth 100 spots them half as far again
const FADE_INNER = 0.7         # fully drawn inside this share of the range, gone at its edge
const FADE_PER_SECOND = 2.0    # alpha change per second: no popping
const SEEN_ALPHA = 0.5         # drawn at least this much: the player sees them (label, prompt, talk)
const COVER_RADIUS = 72.0      # props this near count as cover
const COVER_MASK = 8           # 2d_physics layer 4, world_obstacle
const COVER_FULL_AT = 2        # this many props around them is full cover
const MOVE_SPEED = 12.0        # pixels a second: faster than this is moving
const SHOT_SECONDS = 4.0
const STRUCK_SECONDS = 8.0
const SPEECH_SECONDS = 10.0
const RECHECK_SECONDS = 0.5    # cover, place and kind are re-read this often

## Drawn share 0..1 (1 as anyone), and whether the player sees them
var alpha: float = 1.0
var seen: bool = true

var _conceal: float = 0.0
var _cover: float = 0.0
var _wild: bool = false
var _moving: bool = false
var _recheck: float = 0.0
var _last_pos = null
var _reveal_until_ms: int = 0
var _scene: Node = null
var _player: Node2D = null

## Attach to an NPC body whose kind can hide (once). Returns the component, null for anyone else
static func attach(npc: Node) -> Node:
	if npc == null or not npc.has_method("character_kind"):
		return null
	var have = npc.get_node_or_null(NODE_NAME)
	if have:
		return have
	if not CharacterTypes.can_hide(npc.character_kind()):
		return null
	var c = load(SELF_PATH).new()
	c.name = NODE_NAME
	npc.add_child(c)
	return c

## How much they hide, 0..1. o: concealment (0-100), cover (0..1), wild, moving, revealed
static func hide_amount(o: Dictionary) -> float:
	if not bool(o.get("wild", true)) or bool(o.get("moving", false)) or bool(o.get("revealed", false)):
		return 0.0
	var c = clampf(float(o.get("concealment", 0.0)), 0.0, 100.0) / 100.0
	return clampf(c * lerpf(OPEN_COVER, FULL_COVER, clampf(float(o.get("cover", 0.0)), 0.0, 1.0)), 0.0, 1.0)

## How far (pixels) the player makes them out. o as hide_amount, plus sight (darkness at their spot,
## 1 .. 0.3), glare (on the player's eyes, 1 .. ), perception (the player's stealth, 0-100)
static func spot_range(o: Dictionary) -> float:
	var reach = SPOT_RANGE * float(o.get("sight", 1.0)) * float(o.get("glare", 1.0))
	reach *= 1.0 - HIDE_SHRINK * hide_amount(o)
	return reach * (1.0 + PERCEPTION_BONUS * clampf(float(o.get("perception", 0.0)), 0.0, 100.0) / 100.0)

## How much of them is drawn at o.distance, 0..1: 1 for anyone not hiding (they are drawn as anyone,
## whatever the dark), else full inside FADE_INNER of spot_range, fading to nothing at its edge
static func visibility(o: Dictionary) -> float:
	if hide_amount(o) <= 0.0:
		return 1.0
	var reach = spot_range(o)
	return 1.0 - smoothstep(reach * FADE_INNER, reach, float(o.get("distance", 0.0)))

## The wilds: outdoors (no Floor) at a world.json exterior with no settlement. Towns, villages, the
## city, interiors and scenes the registry does not know are not
static func is_wild(scene_root: Node) -> bool:
	if scene_root == null or scene_root.get_node_or_null("Floor") != null or scene_root.scene_file_path == "":
		return false
	var tree = Engine.get_main_loop() as SceneTree
	var registry = tree.root.get_node_or_null("WorldRegistry") if tree else null
	if registry == null or not registry.has_method("get_location_for_scene"):
		return false
	var id = str(registry.get_location_for_scene(scene_root.scene_file_path))
	if id == "":
		return false
	var loc: Dictionary = registry.get_location(id)
	return str(loc.get("kind", "exterior")) != "interior" and str(loc.get("settlement", "")) == ""

## Show them for `seconds` whatever the cover (an arrow loosed, a blow taken, a word spoken)
func reveal(seconds: float) -> void:
	_reveal_until_ms = maxi(_reveal_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))

func is_revealed() -> bool:
	var npc = get_parent()
	return Time.get_ticks_msec() < _reveal_until_ms or (npc != null and npc.get("is_in_conversation") == true)

func _ready() -> void:
	var npc = get_parent()
	if npc.has_signal("dialogue_response_ready"):
		npc.dialogue_response_ready.connect(func(_id, _text): reveal(SPEECH_SECONDS))
	var combat = get_node_or_null("/root/Combat")
	if combat and combat.has_signal("hit_landed"):
		combat.hit_landed.connect(_on_hit_landed)
	_refresh()

func _on_hit_landed(info: Dictionary) -> void:
	if info.get("target") == get_parent():
		reveal(STRUCK_SECONDS)

## A projectile entering the scene from this body: the arrow shows where it came from
func _on_scene_child(node: Node) -> void:
	if node.get("shooter") == get_parent():
		reveal(SHOT_SECONDS)

func _bind_scene() -> void:
	var npc = get_parent()
	var root: Node = npc._scene_root() if npc.has_method("_scene_root") else null
	if root == _scene:
		return
	if _scene and is_instance_valid(_scene) and _scene.child_entered_tree.is_connected(_on_scene_child):
		_scene.child_entered_tree.disconnect(_on_scene_child)
	_scene = root
	if _scene:
		_scene.child_entered_tree.connect(_on_scene_child)

## Re-read the place, their kind and the cover around them
func _refresh() -> void:
	var npc = get_parent() as Node2D
	if npc == null or not npc.is_inside_tree():
		return
	_bind_scene()
	_wild = is_wild(_scene)
	_conceal = CharacterTypes.wild_concealment(npc.character_kind(), _wild) if npc.has_method("character_kind") else 0.0
	_cover = _cover_at(npc.global_position) if _conceal > 0.0 else 0.0

func _cover_at(at: Vector2) -> float:
	var npc = get_parent() as Node2D
	var space = npc.get_world_2d().direct_space_state if npc.get_world_2d() else null
	if space == null:
		return 0.0
	var shape = CircleShape2D.new()
	shape.radius = COVER_RADIUS
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = COVER_MASK
	q.collide_with_areas = false
	return clampf(float(space.intersect_shape(q, COVER_FULL_AT).size()) / COVER_FULL_AT, 0.0, 1.0)

func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

## Everything visibility() needs, as it stands now (tests read it too)
func current_opts() -> Dictionary:
	var npc = get_parent() as Node2D
	var player = _find_player()
	var o = {"concealment": _conceal, "cover": _cover, "wild": _wild, "moving": _moving, "revealed": is_revealed(),
		"sight": 1.0, "glare": 1.0, "perception": 0.0, "distance": 0.0}
	if npc.get("is_alive") == false:
		o.wild = false  # the dead hide nothing
	if player == null:
		return o
	o.distance = npc.global_position.distance_to(player.global_position)
	var stats = get_node_or_null("/root/PlayerStats")
	if stats and stats.has_method("get_skill"):
		o.perception = float(stats.get_skill("stealth"))
	var physics = get_node_or_null("/root/WorldPhysics")
	var light_opts = {"scene_root": _scene, "outdoors": true}
	if physics and physics.has_method("sight_factor"):
		o.sight = float(physics.sight_factor(npc.global_position, light_opts))
		o.glare = float(physics.glare_factor(player.global_position, npc.global_position, light_opts))
	else:
		o.sight = Witnesses.sight_range({"range": 1.0}, npc.global_position, _scene)
	return o

func _physics_process(delta: float) -> void:
	var npc = get_parent() as Node2D
	if npc == null or not npc.is_inside_tree():
		return
	var pos = npc.global_position
	var speed = 0.0 if _last_pos == null else (pos - _last_pos).length() / maxf(delta, 0.001)
	if npc is CharacterBody2D:
		speed = maxf(speed, npc.velocity.length())
	_moving = speed > MOVE_SPEED
	_last_pos = pos
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = RECHECK_SECONDS
		_refresh()
	var target = visibility(current_opts()) if _conceal > 0.0 else 1.0
	alpha = move_toward(alpha, target, FADE_PER_SECOND * delta)
	_apply()

## Draw them at alpha; the name label goes before the body does, and the prompt with it
func _apply() -> void:
	var npc = get_parent() as CanvasItem
	npc.modulate.a = alpha
	var label = npc.get_node_or_null("NameLabel") as CanvasItem
	if label:
		label.modulate.a = clampf((alpha - SEEN_ALPHA) / (1.0 - SEEN_ALPHA), 0.0, 1.0)
	var now_seen = alpha >= SEEN_ALPHA
	if now_seen != seen:
		seen = now_seen
		if npc.has_method("_show_interaction_prompt"):
			npc._show_interaction_prompt(bool(npc.get("player_nearby")))

## Tests: settle at once (no fade) for the opts as they stand
func settle() -> void:
	_refresh()
	alpha = visibility(current_opts()) if _conceal > 0.0 else 1.0
	_apply()
