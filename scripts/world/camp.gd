extends RefCounted
## Camp - a bedroll and a campfire anywhere outdoors (docs/PLAYER_SYSTEMS.md §6 "Camp"): where the
## player wakes after a death, and a cooking station. The bedroll is laid out and rolled up again in
## the morning (it stays in the pack); the fire is the player's own campfire there, built from wood
## (Crafting.build_station) when there is none yet. Indoors (world.json kind "interior") there is no
## camp: a bed does that (bed.gd)

const CAMP_SPAWN = "camp"

## Make camp at a place outdoors. location "" = where the player is. Returns {ok, reason, location,
## position, station_id, built_fire}
static func make_camp(location: String = "", position: Vector2 = Vector2.ZERO) -> Dictionary:
	var out = {"ok": false, "reason": "", "location": location, "position": position, "station_id": "", "built_fire": false}
	var inv = _node("Inventory")
	var crafting = _node("Crafting")
	var stats = _node("PlayerStats")
	if inv == null or stats == null:
		out.reason = "no one to camp"
		return out
	if out.location == "":
		out.location = _here()
	var registry = _node("WorldRegistry")
	if out.location == "" or (registry and not registry.has_location(out.location)):
		out.reason = "nowhere known"
		return out
	if registry and str(registry.get_location(out.location).get("kind", "")) == "interior":
		out.reason = "you cannot make camp indoors; find a bed"
		return out
	if not inv.has("bedroll", 1):
		out.reason = "you need a bedroll"
		return out
	var fire = _own_campfire(crafting, out.location)
	if fire == "":
		if crafting == null or not crafting.has_method("build_station"):
			out.reason = "you need a fire"
			return out
		var built: Dictionary = crafting.build_station("campfire", out.location, position)
		if not built.ok:
			out.reason = "you need a fire: %s" % built.reason
			return out
		fire = str(built.station_id)
		out.built_fire = true
	out.station_id = fire
	stats.set_respawn(out.location, CAMP_SPAWN, position)
	out.ok = true
	print("[Camp] Camp at %s %s (fire %s)" % [out.location, position, fire])
	return out

## The player's own campfire at this place, or ""
static func _own_campfire(crafting: Node, location: String) -> String:
	if crafting == null or not "built" in crafting:
		return ""
	for id in crafting.built:
		var s: Dictionary = crafting.built[id]
		if str(s.get("kind", "")) == "campfire" and str(s.get("location", "")) == location:
			return str(id)
	return ""

static func _here() -> String:
	var scenes = _node("SceneManager")
	var id = str(scenes.get_current_location_id()) if scenes and scenes.has_method("get_current_location_id") else ""
	if id == "" or id == "none":
		var ws = _node("WorldState")
		id = str(ws.player_location) if ws and "player_location" in ws else ""
	return id

static func _node(node_name: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null
