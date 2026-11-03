extends "res://scripts/world/physics/flammable.gd"
## Rope - holds weights until it is cut or burnt (docs/PLAYER_SYSTEMS.md §5.1)
## A rope is flammable (it burns fast). Cutting or burning it lets every held weight fall: the
## Weight stops hanging and rests where it is, so a stone hung over a plate lands on it.
## sever(by) cuts it (a blade, a puzzle); signal `cut` when it parts

signal cut

## The weights it holds: Weight components or things with a Weight child
@export var holds: Array[NodePath] = []

var is_cut: bool = false

func _init() -> void:
	burn_seconds = 3.0
	reach = 40.0
	on_burnt = "keep"

func kind() -> String:
	return "rope"

func _ready() -> void:
	# Weights hang while the rope holds (in the scene's own state the rope is whole)
	for w in held_weights():
		w.hanging = not is_cut

## Cut the rope. Returns false when it was already cut
func sever(_by: String = "") -> bool:
	if is_cut:
		return false
	is_cut = true
	for w in held_weights():
		w.hanging = false
	cut.emit()
	return true

func held_weights() -> Array:
	var out: Array = []
	for p in holds:
		var n = get_node_or_null(p)
		if n == null:
			continue
		if n.has_method("kind") and n.kind() == "weight":
			out.append(n)
		else:
			for c in n.get_children():
				if c.has_method("kind") and c.kind() == "weight":
					out.append(c)
	return out

func _on_burnt() -> void:
	sever("fire")
	super._on_burnt()

func get_state() -> Dictionary:
	var s = super.get_state()
	s["is_cut"] = is_cut
	return s

func apply_state(state: Dictionary) -> void:
	super.apply_state(state)
	if bool(state.get("is_cut", false)) and not is_cut:
		is_cut = true
		for w in held_weights():
			w.hanging = false
