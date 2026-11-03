extends "res://scripts/puzzles/room_base.gd"
## The old workings above Greystone's seventh level (resources/puzzles/room_old_workings.json).
## An old winze drops past Dagna's boards to the old fall: a way to the Pit the Hollow does not watch.
## Two ways down, and one way to spoil the first:
## - weigh the winch brake down (BrakePlate) and cut the CageRope: the cage rides down on the brake;
##   cut it with the brake off and the cage falls and jams the winze for good;
## - burn out the rotten Barricade across the old adit (a fire in Greystone's timber; WorldPhysics
##   records it as a deed, the room only sees that it burned).
## State keys: brake_on, cage ("up" | "down" | "jammed"), adit ("barred" | "open"), way ("" | "winze" | "adit")

func _init():
	room_id = "old_workings"

func _wire() -> void:
	listen("BrakePlate", "pressed", _on_brake)
	listen("CageRope", "cut", _on_cage_rope_cut)

func _restore() -> void:
	var cage = str(state("cage", "up"))
	set_part_enabled("CageJammed", cage == "jammed")
	set_part_enabled("CageDown", cage == "down")
	set_part_enabled("WayDown", str(state("way", "")) != "")
	if str(state("adit", "barred")) == "open":
		remove_part("AditBlock")

func _on_brake(on: bool) -> void:
	put_state("brake_on", on)

func _on_cage_rope_cut() -> void:
	if str(state("cage", "up")) != "up":
		return
	if state("brake_on", false):
		put_state("cage", "down")
		_open_way("winze", _at("Winze"))
	else:
		# Nothing holds the drum: the cage drops the length of the winze and wedges in the timbering
		put_state("cage", "jammed")
	_restore()

func _on_burned(node: Node, _owner_key: String) -> void:
	if not is_part(node, "Barricade") or str(state("adit", "barred")) == "open":
		return
	put_state("adit", "open")
	_open_way("adit", _at("Adit"))
	_restore()

func _open_way(route: String, at: Vector2) -> void:
	if str(state("way", "")) == "":
		put_state("way", route)
	complete(at)

func _at(node_name: String) -> Vector2:
	var n = part(node_name)
	return n.position if n is Node2D else Vector2.ZERO
