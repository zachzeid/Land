extends Area2D
## RoomDoor - the doorway of one tavern room (docs/WORLD_SCHEMA.md "Taverns"). Walking into a room
## that is not the player's while someone has it tonight (a lodger), or into a back room uninvited,
## is a `trespass` deed about whoever is in there, seen by those in sight (Witnesses). An empty,
## unlet room is nobody's: no deed. Once per room per night

const Witnesses = preload("res://scripts/world/witnesses.gd")

## The location ("" = the current scene's) and the room (its bed's spawn_point)
@export var location_id: String = ""
@export var room: String = ""

var _last_night: int = -1

func _ready():
	collision_layer = 0
	collision_mask = 1   # the player
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		enter(body.global_position)

## The player came through this door. Returns the trespass deed id ("" when none)
func enter(at: Vector2 = Vector2.ZERO) -> String:
	var taverns = get_node_or_null("/root/Taverns")
	var loc = _location()
	if taverns == null or loc == "" or room == "":
		return ""
	var status = str(taverns.room_status(loc, room))
	var about: Array = []
	var what = ""
	match status:
		"taken":
			about = [str(taverns.lodgers(loc).get(room, ""))]
			what = "walked into a room someone had taken for the night at %s" % taverns._place(loc)
		"back_room":
			about = taverns.companions(loc)
			what = "went into the back rooms at %s uninvited" % taverns._place(loc)
		_:
			return ""
	var night = int(taverns.checkout_after(taverns._now()))
	if night == _last_night:
		return ""
	_last_night = night
	var events = get_node_or_null("/root/PlayerEvents")
	if events == null:
		return ""
	var stats = get_node_or_null("/root/PlayerStats")
	var stealth = float(stats.get_skill("stealth")) if stats and stats.has_method("get_skill") else 0.0
	var scene = get_tree().current_scene if is_inside_tree() else null
	var witnesses: Array = Witnesses.in_sight(scene, at, {"stealth": stealth}) if scene else []
	for w in about:
		if str(w) != "" and not str(w) in witnesses:
			witnesses.append(str(w))  # whoever is in the room sees the door open
	return events.record("trespass", what, about.filter(func(w): return str(w) != ""), {"location": loc, "witnesses": witnesses})

func _location() -> String:
	if location_id != "":
		return location_id
	var scenes = get_node_or_null("/root/SceneManager")
	var id = str(scenes.get_current_location_id()) if scenes and scenes.has_method("get_current_location_id") else ""
	return "" if id == "none" else id
