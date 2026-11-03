extends CharacterBody2D
## Player controller with navigation constraint and directional animations
## Movement is constrained to NavigationPolygon walkable areas when present
## Combat input (docs/PLAYER_SYSTEMS.md §3): attack Z/LMB, heavy_attack X/RMB, block C (held),
## dodge V, sprint Shift (held); movement stays on the arrows. Every action goes through Combat,
## which prices it in stamina; Space/Enter stay with talking to NPCs

const SPEED = 200.0
const LOOK_AHEAD_DISTANCE = 50.0
const SPRINT_FACTOR = 1.6
const BLOCK_FACTOR = 0.5             # walking with the guard up
const DODGE_SPEED = 520.0
const DODGE_TIME = 0.25

## Enable/disable navigation constraint (useful for testing)
@export var use_navigation_constraint: bool = true

## Reference to AnimatedSprite2D for directional animations
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## Current facing direction (for animation)
var current_direction: String = "down"

## Whether the player is currently moving
var is_moving: bool = false

## Seconds left of a dodge roll, and its direction
var _dodge_left: float = 0.0
var _dodge_dir: Vector2 = Vector2.ZERO
var is_sprinting: bool = false

func _ready():
	add_to_group("player")
	var stats = get_node_or_null("/root/PlayerStats")
	if stats and stats.has_method("set_body"):
		stats.set_body(self)  # deaths, line-of-sight witnesses and respawns work from this body

	# Start with idle animation
	if animated_sprite and animated_sprite.sprite_frames:
		animated_sprite.play("idle_down")

## Strikes, guard and dodge are events: GUI (a focused text box, a menu) takes them first
func _unhandled_input(event: InputEvent) -> void:
	var combat = _combat()
	if combat == null or not _combat_free():
		return
	if event.is_action_pressed("attack"):
		combat.attack(self, null, "light")
	elif event.is_action_pressed("heavy_attack"):
		combat.attack(self, null, "heavy")
	elif event.is_action_pressed("block"):
		combat.begin_block(self)
	elif event.is_action_released("block"):
		combat.end_block(self)
	elif event.is_action_pressed("dodge"):
		var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if combat.dodge(self):
			_dodge_left = DODGE_TIME
			_dodge_dir = dir.normalized() if dir != Vector2.ZERO else get_facing_vector()
	else:
		return
	get_viewport().set_input_as_handled()

func _physics_process(delta):
	var combat = _combat()
	if combat and combat.is_blocking(self) and not Input.is_action_pressed("block"):
		combat.end_block(self)
	if combat and combat.is_staggered(self):
		velocity = Vector2.ZERO
		_dodge_left = 0.0
		move_and_slide()
		return
	if _dodge_left > 0.0:
		_dodge_left -= delta
		velocity = _dodge_dir * DODGE_SPEED
		move_and_slide()
		return

	# Get input direction
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed = SPEED
	is_sprinting = false
	if input_direction != Vector2.ZERO and combat and Input.is_action_pressed("sprint") and _combat_free() \
			and not combat.is_blocking(self) and combat.sprint_tick(self, delta):
		is_sprinting = true
		speed = SPEED * SPRINT_FACTOR
	elif combat and combat.is_blocking(self):
		speed = SPEED * BLOCK_FACTOR

	if input_direction != Vector2.ZERO:
		# Update facing direction based on dominant axis
		_update_facing_direction(input_direction)

		if use_navigation_constraint and _has_navigation_map():
			# Constrain movement to walkable areas
			var target = global_position + input_direction * LOOK_AHEAD_DISTANCE
			var nav_map = get_world_2d().navigation_map
			var closest = NavigationServer2D.map_get_closest_point(nav_map, target)
			velocity = global_position.direction_to(closest) * speed
		else:
			# Free movement (no navigation constraint)
			velocity = input_direction * speed

		# Play walk animation
		if not is_moving:
			is_moving = true
			_play_animation("walk")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)

		# Play idle animation when stopped
		if is_moving:
			is_moving = false
			_play_animation("idle")

	move_and_slide()

## Update facing direction based on input vector
func _update_facing_direction(direction: Vector2):
	# Determine dominant direction
	if abs(direction.x) > abs(direction.y):
		# Horizontal movement dominant
		current_direction = "right" if direction.x > 0 else "left"
	else:
		# Vertical movement dominant
		current_direction = "down" if direction.y > 0 else "up"

## Play animation with current facing direction
func _play_animation(anim_type: String):
	if not animated_sprite:
		return

	if not animated_sprite.sprite_frames:
		return

	var anim_name = "%s_%s" % [anim_type, current_direction]

	# Check if animation exists
	if animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name:
			animated_sprite.play(anim_name)
	elif animated_sprite.sprite_frames.has_animation(anim_type):
		# Fallback to non-directional animation
		if animated_sprite.animation != anim_type:
			animated_sprite.play(anim_type)

## Get current facing direction
func get_facing_direction() -> String:
	return current_direction

## Get facing direction as Vector2
func get_facing_vector() -> Vector2:
	match current_direction:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		_:
			return Vector2.DOWN

## Check if a navigation map exists and has regions
func _has_navigation_map() -> bool:
	var nav_map = get_world_2d().navigation_map
	if nav_map == RID():
		return false
	# Check if the map has any navigation regions
	return NavigationServer2D.map_get_regions(nav_map).size() > 0

func _combat() -> Node:
	return get_node_or_null("/root/Combat")

## No fighting mid-conversation, while typing, or in a paused menu
func _combat_free() -> bool:
	if get_tree().paused:
		return false
	var dialogue = get_node_or_null("/root/DialogueManager")
	if dialogue and "active_conversations" in dialogue and not dialogue.active_conversations.is_empty():
		return false
	var focus = get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)
