extends "res://scripts/world/physics/physics_component.gd"
## Metal - iron, steel, bronze, a lodestone (docs/PLAYER_SYSTEMS.md §5.1)
## Sinks in water (Basin.drop_in). Conducts heat: in a fire's reach it heats, out of it it cools,
## and while hot it lights flammables it touches (a hot blade lights tinder). Iron and steel rust
## while they stay wet on the game clock. A lodestone pulls loose iron and steel toward it

signal rusted(amount: float)

## iron | steel | bronze | copper | lead | gold | lodestone
@export var metal: String = "iron"
## A lodestone can move it (a key, a blade on the floor; not an iron gate)
@export var loose: bool = true
## Lodestone: how far it pulls (pixels) and how fast (pixels per second)
@export var pull_range: float = 160.0
@export var pull_speed: float = 60.0

var heat: float = 0.0       # 0 cold .. 1 white-hot; lights tinder from WorldPhysics.HOT
var heated_by: String = ""  # who put the heat in it (a fire it lights is theirs)
var rust: float = 0.0       # 0 bright .. 1 eaten through
var sunk: bool = false

func kind() -> String:
	return "metal"

func is_lodestone() -> bool:
	return metal == "lodestone"

func is_iron() -> bool:
	return metal in ["iron", "steel"]

func rusts() -> bool:
	return is_iron()

func get_state() -> Dictionary:
	var s = {"wetness": wetness, "heat": heat, "heated_by": heated_by, "rust": rust, "sunk": sunk}
	if loose:
		var t = thing()
		if t and t.is_inside_tree():
			s["pos"] = [t.global_position.x, t.global_position.y]
	return s

func apply_state(state: Dictionary) -> void:
	super.apply_state(state)
	heat = float(state.get("heat", heat))
	heated_by = str(state.get("heated_by", heated_by))
	rust = float(state.get("rust", rust))
	sunk = bool(state.get("sunk", sunk))
	var pos = state.get("pos", null)
	var t = thing()
	if pos is Array and pos.size() == 2 and t and t.is_inside_tree():
		t.global_position = Vector2(float(pos[0]), float(pos[1]))
