extends RefCounted
## Loadouts - what each person fights with (resources/combat/loadouts.json; docs/PLAYER_SYSTEMS.md §3)
## By world.json npc key for the main cast, by archetype id for generics. {weapon, armour, sidearm,
## arrows}: a weapons.json id ("fists" when none), armour.json ids, the melee weapon drawn when a bow
## is no use ("" = none: fists) and the arrows carried for a bow. Minors always come back
## empty-handed, whatever the data says. BaseNPC.get_combat_profile reads it

const DATA_PATH = "res://resources/combat/loadouts.json"
const NONE = {"weapon": "fists", "armour": [], "sidearm": "", "arrows": 0}

static var _data: Dictionary = {}

static func _load() -> Dictionary:
	if _data.is_empty():
		var file = FileAccess.open(DATA_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			_data = {"npcs": {}, "archetypes": {}}
	return _data

static func _shape(row) -> Dictionary:
	if not row is Dictionary:
		return NONE.duplicate(true)
	var w = str(row.get("weapon", ""))
	var armour: Array = []
	for a in row.get("armour", []):
		armour.append(str(a))
	return {"weapon": w if w != "" else "fists", "armour": armour, "sidearm": str(row.get("sidearm", "")),
		"arrows": maxi(int(row.get("arrows", 0)), 0)}

## A main NPC's loadout by world.json key ("bjorn")
static func for_npc(key: String, minor: bool = false) -> Dictionary:
	return NONE.duplicate(true) if minor else _shape(_load().get("npcs", {}).get(key))

## A generic's loadout by its archetype id
static func for_archetype(archetype_id: String, minor: bool = false) -> Dictionary:
	return NONE.duplicate(true) if minor else _shape(_load().get("archetypes", {}).get(archetype_id))
