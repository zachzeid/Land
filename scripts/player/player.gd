extends CharacterBody2D
## Player controller with navigation constraint and directional animations
## Movement is constrained to NavigationPolygon walkable areas when present

const SPEED = 200.0
const LOOK_AHEAD_DISTANCE = 50.0

## Enable/disable navigation constraint (useful for testing)
@export var use_navigation_constraint: bool = true

## Reference to AnimatedSprite2D for directional animations
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## Current facing direction (for animation)
var current_direction: String = "down"

## Whether the player is currently moving
var is_moving: bool = false

func _ready():
	add_to_group("player")

	# Start with idle animation
	if animated_sprite and animated_sprite.sprite_frames:
		animated_sprite.play("idle_down")

func _physics_process(_delta):
	# Get input direction
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if input_direction != Vector2.ZERO:
		# Update facing direction based on dominant axis
		_update_facing_direction(input_direction)

		if use_navigation_constraint and _has_navigation_map():
			# Constrain movement to walkable areas
			var target = global_position + input_direction * LOOK_AHEAD_DISTANCE
			var nav_map = get_world_2d().navigation_map
			var closest = NavigationServer2D.map_get_closest_point(nav_map, target)
			velocity = global_position.direction_to(closest) * SPEED
		else:
			# Free movement (no navigation constraint)
			velocity = input_direction * SPEED

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
