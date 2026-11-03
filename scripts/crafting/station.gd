extends Node2D
## A crafting station placed in a scene (docs/PLAYER_SYSTEMS.md §4): a campfire, workbench, forge and
## anvil, herb table or loom from resources/crafting/stations.json. It registers with Crafting so the
## deeds done at it are witnessed from here (Witnesses.in_sight); the player's interact opens it
## (Crafting.station_opened, which the crafting panel listens for)

@export var station_id: String = ""

func _ready():
	add_to_group("crafting_stations")
	var crafting = _crafting()
	if crafting and station_id != "":
		crafting.register_station(station_id, self)

func _exit_tree():
	var crafting = _crafting()
	if crafting and station_id != "":
		crafting.unregister_station(station_id, self)

## The player uses the station: recipes they hold the inputs for are discovered, and the crafting
## panel opens (PlayerUI.open_crafting). Returns recipes_at
func interact(_by: Node = null) -> Array:
	var crafting = _crafting()
	var listed = crafting.open_station(station_id) if crafting else []
	var ui = get_tree().get_first_node_in_group("player_ui") if is_inside_tree() else null
	if ui and ui.has_method("open_crafting"):
		ui.open_crafting(station_id)
	return listed

func get_definition() -> Dictionary:
	var crafting = _crafting()
	return crafting.get_station(station_id) if crafting else {}

## Ask the owner's leave (async: the owner's soul decides). Returns Crafting.ask_leave
func ask_leave(purpose: Dictionary = {}) -> Dictionary:
	var crafting = _crafting()
	if crafting == null:
		return {"granted": false, "choice": "", "reason": "no crafting", "decision": {}}
	return await crafting.ask_leave(station_id, purpose)

func craft(recipe_id: String) -> Dictionary:
	var crafting = _crafting()
	return crafting.craft(recipe_id, station_id) if crafting else {"ok": false, "item": {}, "reason": "no crafting"}

func _crafting() -> Node:
	return get_node_or_null("/root/Crafting") if is_inside_tree() else null
