extends "res://scripts/puzzles/room_base.gd"
## Brackenmoor's undercroft (resources/puzzles/room_abbey_undercroft.json). The aumbry behind an iron
## grate lifts on its counterweight only while both kneeling stones are weighed at once (KneelerNorth,
## KneelerSouth: the player and the reliquary chest, or two people); a pawl then holds it. Inside, the
## book of saints' days (SaintsDaysBook) carries Anselm's second set of the salt letters in its binding.
## Cut the LampRope while the HangingLamp burns and it falls into the DullShelves; WorldPhysics spreads
## the fire, and if the shelves burn before the letters are taken, the letters burn with them.
## State keys: north, south (weighed), grate ("shut" | "open"), letters ("hidden" | "taken" | "burned")

@export var lamp_lit_default: bool = true   # the undercroft lamp hangs lit unless the lamp says otherwise

func _init():
	room_id = "abbey_undercroft"

func _wire() -> void:
	listen("KneelerNorth", "pressed", _on_kneeler.bind("north"))
	listen("KneelerSouth", "pressed", _on_kneeler.bind("south"))
	listen("LampRope", "cut", _on_lamp_rope_cut)
	listen("SaintsDaysBook", "interacted", _on_book)

func _restore() -> void:
	var open = str(state("grate", "shut")) == "open"
	if open:
		remove_part("GrateShut")
	set_part_enabled("SaintsDaysBook", open and str(state("letters", "hidden")) == "hidden")
	set_part_enabled("Ashes", str(state("letters", "hidden")) == "burned")

func _on_kneeler(on: bool, which: String) -> void:
	put_state(which, on)
	if state("north", false) and state("south", false) and str(state("grate", "shut")) == "shut":
		put_state("grate", "open")
		_restore()

func _on_lamp_rope_cut() -> void:
	if state("lamp_fallen", false):
		return
	put_state("lamp_fallen", true)
	var lamp = part("HangingLamp")
	var lit = lamp.get("lit") if lamp and "lit" in lamp else lamp_lit_default
	var physics = get_node_or_null("/root/WorldPhysics")
	if lit and physics and part("DullShelves"):
		physics.ignite(part("DullShelves"), "player")

func _on_burned(node: Node, _owner_key: String) -> void:
	if is_part(node, "DullShelves") and str(state("letters", "hidden")) == "hidden":
		put_state("letters", "burned")
		_restore()

## The book is opened and its binding cut: the reward
func _on_book(_item = null) -> void:
	take_letters()

func take_letters() -> Dictionary:
	if str(state("grate", "shut")) != "open" or str(state("letters", "hidden")) != "hidden":
		return {"ok": false, "flag": "", "reason": "out_of_reach" if str(state("letters", "hidden")) == "hidden" else str(state("letters"))}
	put_state("letters", "taken")
	var book = part("SaintsDaysBook")
	var out = complete(book.position if book is Node2D else Vector2.ZERO)
	_restore()
	return out
