extends Interactable
class_name Bed
## Bed - where the player sleeps, and so where they wake after a death (docs/PLAYER_SYSTEMS.md §2, §6)
## Sleeping here sets PlayerStats' respawn to this scene's location and spawn_point (a Marker2D in
## SpawnPoints). An inn room costs rent for the night (Inventory.spend_coin; refused when the purse is
## short); a bed of the player's own costs nothing. Outdoors, a bedroll and a campfire do the same
## (camp.gd)

## The location this bed is in ("" = the current scene's)
@export var location_id: String = ""
## The spawn marker the player wakes at
@export var spawn_point: String = "bed"
## Coin for the night (an inn room); 0 = the player's own bed
@export var rent: int = 0
## Whose room it is (an npc key), for the prompt
@export var keeper: String = ""

signal slept(info: Dictionary)

func _ready():
	super._ready()
	add_to_group("beds")
	if interaction_name == "Interact":
		interaction_name = "Sleep here" if rent <= 0 else "Take a room for the night"
	if rent > 0:
		interaction_name += " (%s)" % _coin_text(rent)

func _on_interact():
	var r = sleep()
	if r.ok:
		interacted.emit(self)

## Sleep here: pay the rent, and wake here after a death. Returns {ok, reason, location, spawn_point, paid}
func sleep() -> Dictionary:
	var out = {"ok": false, "reason": "", "location": _location(), "spawn_point": spawn_point, "paid": 0}
	var stats = get_node_or_null("/root/PlayerStats")
	if stats == null or not stats.has_method("set_respawn"):
		out.reason = "no one to sleep"
		return out
	if out.location == "":
		out.reason = "nowhere known"
		return out
	if rent > 0:
		var inv = get_node_or_null("/root/Inventory")
		if inv == null or not inv.spend_coin(rent):
			out.reason = "you cannot pay for the room"
			return out
		out.paid = rent
	stats.set_respawn(out.location, spawn_point)
	out.ok = true
	print("[Bed] The player will wake at %s (%s)" % [out.location, spawn_point])
	slept.emit(out)
	return out

func _location() -> String:
	if location_id != "":
		return location_id
	var scenes = get_node_or_null("/root/SceneManager")
	var id = str(scenes.get_current_location_id()) if scenes and scenes.has_method("get_current_location_id") else ""
	return "" if id == "none" else id

func _coin_text(amount: int) -> String:
	var inv = get_node_or_null("/root/Inventory")
	return str(inv.format_coin(amount)) if inv and inv.has_method("format_coin") else str(amount)
