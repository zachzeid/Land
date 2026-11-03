extends Area2D
## A loosed arrow or sling stone (docs/PLAYER_SYSTEMS.md §3). It sits on the projectile layer (7) so
## the world can see it, and finds what it hits with a ray along each step (no tunnelling at speed):
## the first fighter body or hurtbox (layers player 1, npc 2) takes the hit through
## Combat.resolve_hit; a wall (world_solid 3) stops it. It passes through its shooter and through
## anyone Combat may not target for this shooter (a minor, unless the player loosed it)

const PROJECTILE_LAYER = 64          # 2d_physics layer 7, projectile
const HIT_MASK = 1 | 2 | 4           # player, npc, world_solid
const MAX_PASSES = 8                 # bodies passed through in one step

var shooter: Node = null
var weapon: Dictionary = {}
var direction: Vector2 = Vector2.DOWN
var speed: float = 500.0
var max_distance: float = 400.0
var travelled: float = 0.0

## Emitted once with the outcome, just before the projectile frees itself
signal landed(outcome: Dictionary)
## What it ended on: {} while in flight, then {fighter, result} or {wall: true} or {spent: true}
var outcome: Dictionary = {}

func _ready() -> void:
	collision_layer = PROJECTILE_LAYER
	collision_mask = 0
	monitoring = false
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 3.0
	shape.shape = circle
	add_child(shape)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if not outcome.is_empty():
		return
	var step = direction * speed * delta
	if travelled + step.length() > max_distance:
		step = direction * maxf(max_distance - travelled, 0.0)
	var from = global_position
	var hit = _cast(from, from + step)
	if not hit.is_empty():
		global_position = hit.position
		_land(hit)
		return
	global_position = from + step
	travelled += step.length()
	if travelled >= max_distance - 0.01:
		_end({"spent": true})

func _cast(from: Vector2, to: Vector2) -> Dictionary:
	var combat = get_node_or_null("/root/Combat")
	var space = get_world_2d().direct_space_state
	var exclude: Array = [get_rid()]
	if shooter is CollisionObject2D:
		exclude.append(shooter.get_rid())
	for i in MAX_PASSES:
		var query = PhysicsRayQueryParameters2D.create(from, to, HIT_MASK, exclude)
		query.collide_with_areas = true
		var res = space.intersect_ray(query)
		if res.is_empty():
			return {}
		var collider = res.collider
		var fighter = combat.fighter_of(collider) if combat else null
		if fighter == null:
			if collider is CollisionObject2D and (collider.collision_layer & 4) != 0:
				return {"wall": true, "position": res.position}
		elif fighter != shooter and combat.can_target_node(fighter, shooter):
			return {"fighter": fighter, "position": res.position}
		exclude.append(res.rid)
	return {}

func _land(hit: Dictionary) -> void:
	if hit.has("fighter"):
		var combat = get_node_or_null("/root/Combat")
		var result = combat.resolve_hit(shooter, hit.fighter, weapon, "shoot") if combat else {}
		_end({"fighter": hit.fighter, "result": result})
	else:
		_end({"wall": true})

func _end(what: Dictionary) -> void:
	outcome = what
	landed.emit(what)
	queue_free()
