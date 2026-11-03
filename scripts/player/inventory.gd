extends Node
## Inventory - items, equipment, coin (pennies), weight, provenance, the pack dropped on death
## docs/PLAYER_SYSTEMS.md §2 (the pack), §6 (the player's tools in the world)
## - item definitions: resources/items/*.json ({"items": [{id, name, kind, weight, stack, value, tags, ...}]})
## - records: {uid, id, qty, quality 0-100, durability, max_durability, maker, provenance {from, stolen,
##   owner}, broken, recognised}; stackable items stack per (id, quality, maker, provenance)
## - MAX_SLOTS slots, a carry-weight limit (PlayerStats.get_max_carry when it has one, else 60), five
##   equipment slots; a two-handed weapon frees the off hand
## - coin is held as pennies: 12 pennies a mark, 20 marks a crown (240 pennies). A labourer's season
##   (about 80 working days) is about 3 crowns = 720 pennies, roughly 9 pennies a day
## - stolen items the owner (or anyone who knows the item) sees equipped are recognised: a `theft` deed
##   about the owner, witnessed by line of sight, once per item (check_recognition)
## - every death drops everything as a pack (drop_all_at). Packs persist in the save by location and
##   position, respawn when their scene loads, and NPCs who come upon one decide by soul what to do
##   (resources/emergence/a_pack_by_the_road.json, triggered by the `fell` deed)
## Deeds go through PlayerEvents.record, never NPC state

signal changed()

const Witnesses = preload("res://scripts/world/witnesses.gd")

const ITEMS_DIR = "res://resources/items"
const WORLD_PATH = "res://resources/world/world.json"
const PACK_SCENE = "res://scenes/world/dropped_pack.tscn"
const PACK_TEMPLATE = "a_pack_by_the_road"
const KINDS = ["weapon", "armour", "tool", "material", "food", "remedy", "misc"]
const SLOTS = ["main_hand", "off_hand", "body", "head", "tool"]
const MAX_SLOTS = 24
const DEFAULT_CARRY = 60.0
const DEFAULT_QUALITY = 50
const PENNIES_PER_MARK = 12
const MARKS_PER_CROWN = 20
const PENNIES_PER_CROWN = PENNIES_PER_MARK * MARKS_PER_CROWN
const FELL_LINK_MINUTES = 60      # a fall and a pack at the same place this close together are one death

var defs: Dictionary = {}         # item id -> definition
var items: Array = []             # records, in slot order
var equipped: Dictionary = {}     # slot -> record uid
var coin: int = 0
var packs: Dictionary = {}        # pack id -> {id, location, position [x, y], items, coin, minute, state, holder, event_id}
var _uid: int = 0
var _pack_seq: int = 0
var _pending_fell: Dictionary = {}   # location -> {id, minute}: a fall recorded before its pack was dropped
var _factions: Dictionary = {}       # faction id -> member keys (world.json)

## Tests and tools
var location_override: String = ""
var carry_override: float = -1.0
var auto_recognise: bool = true      # equip() and scene loads look for owners in sight

func _ready():
	load_definitions()
	var world = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH)) if FileAccess.file_exists(WORLD_PATH) else null
	for f in world.get("factions", []) if world is Dictionary else []:
		_factions[str(f.get("id", ""))] = f.get("members", []).duplicate()
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_signal("scene_transition_completed"):
		scene_manager.scene_transition_completed.connect(_on_scene_loaded)
	var player_events = get_node_or_null("/root/PlayerEvents")
	if player_events and player_events.has_signal("player_event_recorded"):
		player_events.player_event_recorded.connect(_on_player_event)
	call_deferred("_connect_director")
	print("Inventory initialized (%d item definitions)" % defs.size())

func _connect_director() -> void:
	var director = get_node_or_null("/root/StorylineDirector")
	if director == null:
		return
	if director.has_signal("emergent_acted") and not director.emergent_acted.is_connected(_on_emergent_acted):
		director.emergent_acted.connect(_on_emergent_acted)
	if director.has_signal("emergent_closed") and not director.emergent_closed.is_connected(_on_emergent_closed):
		director.emergent_closed.connect(_on_emergent_closed)

# =============================================================================
# DEFINITIONS
# =============================================================================

## Load every resources/items/*.json. Returns the number of definitions
func load_definitions(dir_path: String = ITEMS_DIR) -> int:
	defs.clear()
	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_warning("[Inventory] No item directory %s" % dir_path)
		return 0
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join(file)))
		if not data is Dictionary or not data.get("items") is Array:
			push_warning("[Inventory] %s has no items array" % file)
			continue
		for d in data.items:
			if d is Dictionary and str(d.get("id", "")) != "":
				defs[str(d.id)] = d
	return defs.size()

## One item's definition (a copy; {} when unknown)
func get_definition(item_id: String) -> Dictionary:
	return defs.get(item_id, {}).duplicate(true)

## The UI's name for get_definition
func get_item_def(item_id: String) -> Dictionary:
	return get_definition(item_id)

func get_item_name(item_id: String) -> String:
	return str(defs.get(item_id, {}).get("name", item_id.capitalize()))

# =============================================================================
# ITEMS
# =============================================================================

## Add qty of an item. props: quality (0-100), durability, maker, provenance {from, stolen, owner,
## known_by?}, broken, force (ignore slots and weight: a pack taken back). false when unknown, full or
## too heavy; a refused add changes nothing
func add(item_id: String, qty: int = 1, props: Dictionary = {}) -> bool:
	if not defs.has(item_id):
		push_warning("[Inventory] Unknown item '%s'" % item_id)
		return false
	if qty <= 0:
		return false
	var d: Dictionary = defs[item_id]
	var force = props.get("force", false) == true
	if not force and get_weight() + float(d.get("weight", 0.0)) * qty > get_max_carry() + 0.0001:
		return false
	var proto = _new_record(item_id, props)
	var stack = maxi(int(d.get("stack", 1)), 1)
	var left = qty
	var fills: Array = []
	if stack > 1 and not proto.broken:
		for rec in items:
			if left <= 0:
				break
			if _stacks_with(rec, proto) and int(rec.qty) < stack:
				var n = mini(stack - int(rec.qty), left)
				fills.append([rec, n])
				left -= n
	var new_records = ceili(float(left) / float(stack)) if left > 0 else 0
	if not force and items.size() + new_records > MAX_SLOTS:
		return false
	for f in fills:
		f[0].qty = int(f[0].qty) + f[1]
	while left > 0:
		var rec = proto.duplicate(true)
		rec["uid"] = _next_uid()
		rec["qty"] = mini(stack, left)
		left -= int(rec.qty)
		items.append(rec)
	changed.emit()
	return true

## Remove qty of an item, unequipped records first. false (and nothing removed) when there is not enough
func remove(item_id: String, qty: int = 1) -> bool:
	if qty <= 0 or not has(item_id, qty):
		return false
	var left = qty
	var order: Array = items.filter(func(r): return r.id == item_id and not _is_equipped(r.uid))
	order.append_array(items.filter(func(r): return r.id == item_id and _is_equipped(r.uid)))
	for rec in order:
		if left <= 0:
			break
		var n = mini(int(rec.qty), left)
		rec.qty = int(rec.qty) - n
		left -= n
		if int(rec.qty) <= 0:
			_unequip_uid(rec.uid)
			items.erase(rec)
	changed.emit()
	return true

## Is there at least qty of this item (broken ones count: a broken blade is still in the pack)
func has(item_id: String, qty: int = 1) -> bool:
	return count(item_id) >= qty

func count(item_id: String) -> int:
	var total = 0
	for rec in items:
		if rec.id == item_id:
			total += int(rec.qty)
	return total

## Every record (copies), each with "slot" ("" when not equipped)
func get_items() -> Array:
	return items.map(func(r): return _out(r))

func get_weight() -> float:
	var total = 0.0
	for rec in items:
		total += float(defs.get(rec.id, {}).get("weight", 0.0)) * int(rec.qty)
	return total

## The carry limit: PlayerStats.get_max_carry() when it offers one, else DEFAULT_CARRY
func get_max_carry() -> float:
	if carry_override >= 0.0:
		return carry_override
	var stats = get_node_or_null("/root/PlayerStats")
	if stats and stats.has_method("get_max_carry"):
		return float(stats.get_max_carry())
	return DEFAULT_CARRY

func get_free_slots() -> int:
	return MAX_SLOTS - items.size()

# =============================================================================
# EQUIPMENT
# =============================================================================

## Equip an item (one not broken) into a slot its definition allows. A two-handed weapon in the main hand
## frees the off hand, and nothing goes in the off hand while one is held. Equipping a stolen item where
## its owner can see it is how a theft is found out (check_recognition, deferred, on the current scene)
func equip(item_id: String, slot: String) -> bool:
	if slot not in SLOTS or not defs.has(item_id):
		return false
	if slot not in defs[item_id].get("slots", []):
		return false
	var current = _record(equipped.get(slot, -1))
	if not current.is_empty() and current.id == item_id:
		return true
	if slot == "off_hand" and _two_handed(_record(equipped.get("main_hand", -1))):
		return false
	var rec: Dictionary = {}
	for r in items:
		if r.id == item_id and not r.get("broken", false) and not _is_equipped(r.uid):
			rec = r
			break
	if rec.is_empty():
		return false
	equipped[slot] = rec.uid
	if slot == "main_hand" and _two_handed(rec):
		equipped.erase("off_hand")
	changed.emit()
	if auto_recognise and is_inside_tree() and get_tree().current_scene:
		call_deferred("check_recognition", get_tree().current_scene)
	return true

## Take off whatever is in a slot. false when it was empty
func unequip(slot: String) -> bool:
	if not equipped.has(slot):
		return false
	equipped.erase(slot)
	changed.emit()
	return true

## The record in a slot (a copy; {} when empty)
func get_equipped(slot: String) -> Dictionary:
	var rec = _record(equipped.get(slot, -1))
	return {} if rec.is_empty() else _out(rec)

## Wear an equipped item (durability). At 0 it breaks: it leaves the slot and stays in the pack, broken,
## until mended (repair). Returns {broke, durability, item}
func wear(slot: String, amount: float = 1.0) -> Dictionary:
	var rec = _record(equipped.get(slot, -1))
	if rec.is_empty() or float(rec.max_durability) <= 0.0:
		return {"broke": false, "durability": 0.0, "item": str(rec.get("id", ""))}
	rec.durability = maxf(float(rec.durability) - maxf(amount, 0.0), 0.0)
	var broke = rec.durability <= 0.0
	if broke:
		rec["broken"] = true
		equipped.erase(slot)
		print("[Inventory] %s broke" % get_item_name(rec.id))
	changed.emit()
	return {"broke": broke, "durability": rec.durability, "item": rec.id}

## Mend an item (Crafting, at a station): the most worn record of item_id, broken ones first, by amount
## (-1: fully). A mended broken item is whole again. false when there is nothing of it to mend
func repair(item_id: String, amount: float = -1.0) -> bool:
	var target: Dictionary = {}
	for rec in items:
		if rec.id != item_id or float(rec.max_durability) <= 0.0 or float(rec.durability) >= float(rec.max_durability):
			continue
		if target.is_empty() or float(rec.durability) < float(target.durability):
			target = rec
	if target.is_empty():
		return false
	var mended = float(target.max_durability) if amount < 0.0 else float(target.durability) + amount
	target.durability = minf(mended, float(target.max_durability))
	if target.durability > 0.0:
		target["broken"] = false
	changed.emit()
	return true

# =============================================================================
# COIN (pennies)
# =============================================================================

func get_coin() -> int:
	return coin

## Add pennies (negative takes, never below nothing)
func add_coin(pennies: int) -> void:
	coin = maxi(coin + pennies, 0)
	changed.emit()

## Pay pennies. false (and nothing paid) when the purse is short
func spend_coin(pennies: int) -> bool:
	if pennies < 0 or pennies > coin:
		return false
	coin -= pennies
	changed.emit()
	return true

static func to_pennies(crowns: int = 0, marks: int = 0, pennies: int = 0) -> int:
	return crowns * PENNIES_PER_CROWN + marks * PENNIES_PER_MARK + pennies

## "2 crowns, 3 marks, 4 pennies" ("nothing" for 0)
static func format_coin(pennies: int) -> String:
	if pennies <= 0:
		return "nothing"
	var parts: Array = []
	var crowns = pennies / PENNIES_PER_CROWN
	var marks = (pennies % PENNIES_PER_CROWN) / PENNIES_PER_MARK
	var rest = pennies % PENNIES_PER_MARK
	if crowns > 0:
		parts.append("%d crown%s" % [crowns, "" if crowns == 1 else "s"])
	if marks > 0:
		parts.append("%d mark%s" % [marks, "" if marks == 1 else "s"])
	if rest > 0:
		parts.append("%d %s" % [rest, "penny" if rest == 1 else "pennies"])
	return ", ".join(parts)

# =============================================================================
# PROVENANCE AND RECOGNITION (§6)
# =============================================================================

## Stolen items worn or held where their owner, or anyone who knows the item, can see the player: a
## `theft` deed about the owner, witnessed by those who recognised it, once per item. Call on scene load
## and on equip (both done here when auto_recognise). at: where the player stands (default: the
## "player" group node under scene_root). Returns the deed ids
func check_recognition(scene_root: Node, at = null) -> Array:
	var ids: Array = []
	if scene_root == null or not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return ids
	var watched: Array = []
	for slot in SLOTS:
		var rec = _record(equipped.get(slot, -1))
		if not rec.is_empty() and rec.provenance.get("stolen", false) == true and not rec.get("recognised", false):
			watched.append(rec)
	if watched.is_empty():
		return ids
	var pos = at if at is Vector2 else _player_position(scene_root)
	if not pos is Vector2:
		return ids
	var stats = get_node_or_null("/root/PlayerStats")
	var stealth = float(stats.get_skill("stealth")) if stats and stats.has_method("get_skill") else 0.0
	var seen: Array = Witnesses.in_sight(scene_root, pos, {"stealth": stealth})
	var player_events = get_node_or_null("/root/PlayerEvents")
	if seen.is_empty() or player_events == null:
		return ids
	for rec in watched:
		var knowers = recognisers(rec)
		var who: Array = seen.filter(func(id): return id in knowers or _key(id) in knowers)
		if who.is_empty():
			continue
		var owner = _key(str(rec.provenance.get("owner", "")))
		var item_name = get_item_name(rec.id).to_lower()
		var summary = "was seen with the %s that went missing from %s" % [item_name, _name(owner)] if owner != "" \
			else "was seen with a stolen %s" % item_name
		var id = player_events.record("theft", summary, [owner] if owner != "" else [], {"witnesses": who, "location": _location()})
		rec["recognised"] = true
		if id != "":
			ids.append(id)
			print("[Inventory] %s recognised by %s" % [get_item_name(rec.id), ", ".join(who)])
	if not ids.is_empty():
		changed.emit()
	return ids

## Who would know this record on sight: its owner, provenance.known_by, the definition's known_by and
## the members of its known_by_faction (npc keys; generic ids as they are)
func recognisers(rec: Dictionary) -> Array:
	var prov: Dictionary = rec.get("provenance", {})
	var d: Dictionary = defs.get(str(rec.get("id", "")), {})
	var raw: Array = [str(prov.get("owner", ""))]
	raw.append_array(prov.get("known_by", []))
	raw.append_array(d.get("known_by", []))
	for faction_id in d.get("known_by_faction", []):
		raw.append_array(_factions.get(str(faction_id), []))
	var out: Array = []
	for who in raw:
		var k = _key(str(who))
		if k != "" and k not in out:
			out.append(k)
	return out

# =============================================================================
# THE PACK (§2: every death drops the whole inventory)
# =============================================================================

## Drop everything (equipment and coin too) where the player fell, as a pack node under scene_root.
## The pack is kept in the save by location and position until taken back. Returns the node (null when
## there was nothing to drop or no scene to put it in; the pack itself is still kept)
func drop_all_at(scene_root: Node, position: Vector2) -> Node:
	if items.is_empty() and coin <= 0:
		return null
	_pack_seq += 1
	var location = _location()
	var pack = {"id": "pack_%d" % _pack_seq, "location": location, "position": [position.x, position.y],
		"items": items.map(func(r): return _bare(r)), "coin": coin, "minute": _now(), "state": "lying",
		"holder": "", "event_id": ""}
	var fell: Dictionary = _pending_fell.get(location, {})
	if not fell.is_empty() and absi(int(pack.minute) - int(fell.minute)) <= FELL_LINK_MINUTES:
		pack.event_id = str(fell.id)
		_pending_fell.erase(location)
	packs[pack.id] = pack
	items.clear()
	equipped.clear()
	coin = 0
	print("[Inventory] Dropped %s at %s %s" % [pack.id, location, position])
	changed.emit()
	if scene_root == null or not is_instance_valid(scene_root):
		return null
	return _spawn_pack(scene_root, pack)

## Take a lying pack back: everything in it returns (over the weight limit if need be), unequipped.
## false when it is not lying there any more
func take_pack(pack_id: String) -> bool:
	var pack: Dictionary = packs.get(pack_id, {})
	if pack.is_empty() or pack.state != "lying":
		return false
	_return_contents(pack)
	packs.erase(pack_id)
	_free_pack_nodes(pack_id)
	print("[Inventory] Took back %s" % pack_id)
	return true

## A pack an NPC kept for the player (or the watch was given) comes back when the player talks to the
## holder. Returns how many packs came back
func reclaim_from(npc_key: String) -> int:
	var key = _key(npc_key)
	var back = 0
	for pack_id in packs.keys():
		var pack: Dictionary = packs[pack_id]
		if pack.state == "held" and _key(str(pack.holder)) == key:
			_return_contents(pack)
			packs.erase(pack_id)
			back += 1
			print("[Inventory] %s handed back %s" % [key, pack_id])
	return back

## Pack records (copies). location: only those there ("" = all)
func get_packs(location: String = "") -> Array:
	var out: Array = []
	for pack in packs.values():
		if location == "" or pack.location == location:
			out.append(pack.duplicate(true))
	return out

func get_pack(pack_id: String) -> Dictionary:
	return packs.get(pack_id, {}).duplicate(true)

## Put a pack node into the scene for every pack lying at this location that has none there yet
func spawn_packs(scene_root: Node, location: String) -> Array:
	var nodes: Array = []
	if scene_root == null or not is_instance_valid(scene_root):
		return nodes
	var present: Array = []
	for n in scene_root.find_children("*", "", true, false):
		if n.is_in_group("dropped_packs"):
			present.append(str(n.get("pack_id")))
	for pack in packs.values():
		if pack.state == "lying" and pack.location == location and not pack.id in present:
			var node = _spawn_pack(scene_root, pack)
			if node:
				nodes.append(node)
	return nodes

func _spawn_pack(scene_root: Node, pack: Dictionary) -> Node:
	var scene = load(PACK_SCENE)
	if scene == null:
		push_warning("[Inventory] No pack scene at %s" % PACK_SCENE)
		return null
	var node = scene.instantiate()
	node.pack_id = pack.id
	node.position = Vector2(float(pack.position[0]), float(pack.position[1]))
	scene_root.add_child(node)
	return node

func _free_pack_nodes(pack_id: String) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("dropped_packs"):
		if str(n.get("pack_id")) == pack_id:
			n.queue_free()

func _return_contents(pack: Dictionary) -> void:
	for rec in pack.get("items", []):
		var copy: Dictionary = rec.duplicate(true)
		copy["uid"] = _next_uid()
		items.append(copy)
	coin += int(pack.get("coin", 0))
	changed.emit()

# --- the pack and the world: a_pack_by_the_road ------------------------------------

## A fall: link it to the pack dropped there (before or after, within FELL_LINK_MINUTES)
func _on_player_event(ev: Dictionary) -> void:
	if str(ev.get("kind", "")) != "fell":
		return
	var location = str(ev.get("location", ""))
	for pack in packs.values():
		if pack.state == "lying" and pack.event_id == "" and pack.location == location \
				and absi(int(pack.minute) - int(ev.get("minute", 0))) <= FELL_LINK_MINUTES:
			pack.event_id = str(ev.id)
			return
	_pending_fell[location] = {"id": str(ev.get("id", "")), "minute": int(ev.get("minute", 0))}

## An NPC chose, by soul, what to do with the pack: take it, keep it safe, hand it to the watch, or leave it
func _on_emergent_acted(entry: Dictionary) -> void:
	if str(entry.get("template", "")) != PACK_TEMPLATE:
		return
	var pack = _pack_for(str(entry.get("event_id", "")), str(entry.get("location", "")))
	if pack.is_empty() or pack.state != "lying":
		return
	var npc = _key(str(entry.get("npc", "")))
	var watch = str(entry.get("roles", {}).get("watch", ""))
	match str(entry.get("choice", "")):
		"take_it":
			pack.state = "taken"
			pack.holder = npc
		"keep_it_safe":
			pack.state = "held"
			pack.holder = npc
		"hand_to_watch":
			pack.state = "held"
			pack.holder = _key(watch) if watch != "" else npc
		_:
			return
	print("[Inventory] %s: %s chose %s" % [pack.id, npc, entry.choice])
	_free_pack_nodes(pack.id)
	changed.emit()

## The beat resolved when the player talked to someone: a pack that person holds comes back
func _on_emergent_closed(inst: Dictionary) -> void:
	if str(inst.get("template", "")) != PACK_TEMPLATE:
		return
	var outcome = str(inst.get("outcome", ""))
	if outcome.begins_with("talked_to:"):
		reclaim_from(outcome.substr(10))

func _pack_for(event_id: String, location: String) -> Dictionary:
	if event_id != "":
		for pack in packs.values():
			if pack.event_id == event_id:
				return pack
	var newest: Dictionary = {}
	for pack in packs.values():
		if pack.state == "lying" and pack.location == location and (newest.is_empty() or int(pack.minute) > int(newest.minute)):
			newest = pack
	return newest

func _on_scene_loaded(location: String) -> void:
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var scene = get_tree().current_scene
	spawn_packs(scene, location)
	if auto_recognise:
		call_deferred("check_recognition", scene)

# =============================================================================
# HELPERS
# =============================================================================

func _new_record(item_id: String, props: Dictionary) -> Dictionary:
	var d: Dictionary = defs.get(item_id, {})
	var quality = clampi(int(props.get("quality", DEFAULT_QUALITY)), 0, 100)
	var base = float(d.get("max_durability", 0.0))
	# Quality sets how many uses (§4): quality 50 is the definition's own durability, 0 half, 100 one and a half
	var max_dur = roundf(base * (0.5 + quality / 100.0)) if base > 0.0 else 0.0
	var prov_in: Dictionary = props.get("provenance", {}) if props.get("provenance") is Dictionary else {}
	var prov = {"from": str(prov_in.get("from", "")), "stolen": prov_in.get("stolen", false) == true, "owner": str(prov_in.get("owner", ""))}
	if prov_in.get("known_by") is Array and not prov_in.known_by.is_empty():
		prov["known_by"] = prov_in.known_by.duplicate()
	var dur = clampf(float(props.get("durability", max_dur)), 0.0, max_dur)
	var broken = max_dur > 0.0 and (props.get("broken", false) == true or dur <= 0.0)
	return {"uid": 0, "id": item_id, "qty": 0, "quality": quality, "durability": dur, "max_durability": max_dur,
		"maker": str(props.get("maker", "")), "provenance": prov, "broken": broken, "recognised": false}

func _stacks_with(rec: Dictionary, proto: Dictionary) -> bool:
	return rec.id == proto.id and not rec.get("broken", false) and int(rec.quality) == int(proto.quality) \
		and str(rec.maker) == str(proto.maker) and rec.provenance == proto.provenance

func _record(uid) -> Dictionary:
	for rec in items:
		if rec.uid == uid:
			return rec
	return {}

func _is_equipped(uid) -> bool:
	return uid in equipped.values()

func _unequip_uid(uid) -> void:
	for slot in equipped.keys():
		if equipped[slot] == uid:
			equipped.erase(slot)

func _two_handed(rec: Dictionary) -> bool:
	return not rec.is_empty() and "two_handed" in defs.get(rec.id, {}).get("tags", [])

func _out(rec: Dictionary) -> Dictionary:
	var copy = rec.duplicate(true)
	copy["slot"] = ""
	for slot in equipped:
		if equipped[slot] == rec.uid:
			copy["slot"] = slot
	return copy

func _bare(rec: Dictionary) -> Dictionary:
	var copy = rec.duplicate(true)
	copy.erase("uid")
	return copy

func _next_uid() -> int:
	_uid += 1
	return _uid

func _key(who: String) -> String:
	if who == "":
		return ""
	var registry = get_node_or_null("/root/WorldRegistry")
	var key = registry.get_npc_key(who) if registry else ""
	return key if key != "" else who

func _name(key: String) -> String:
	var registry = get_node_or_null("/root/WorldRegistry")
	return registry.get_npc_name(key) if registry and registry.has_npc(key) else key

func _player_position(scene_root: Node):
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D and scene_root.is_ancestor_of(n):
			return n.global_position
	var player = scene_root.find_child("Player", true, false)
	return player.global_position if player is Node2D else null

func _location() -> String:
	if location_override != "":
		return location_override
	var scene_manager = get_node_or_null("/root/SceneManager")
	var id = str(scene_manager.get_current_location_id()) if scene_manager and scene_manager.has_method("get_current_location_id") else ""
	if id == "":
		var world_state = get_node_or_null("/root/WorldState")
		id = str(world_state.player_location) if world_state and "player_location" in world_state else ""
	return id

func _now() -> int:
	var world_state = get_node_or_null("/root/WorldState")
	return int(world_state.game_minutes) if world_state and "game_minutes" in world_state else 0

## Forget everything (tests, a new game)
func reset() -> void:
	items.clear()
	equipped.clear()
	coin = 0
	packs.clear()
	_pending_fell.clear()
	_uid = 0
	_pack_seq = 0
	changed.emit()

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

## Records and packs as plain JSON; equipment by index into items, so uids need not survive
func save() -> Dictionary:
	var eq: Dictionary = {}
	for slot in equipped:
		var i = items.find(_record(equipped[slot]))
		if i >= 0:
			eq[slot] = i
	return {"version": 1, "items": items.map(func(r): return _bare(r)), "equipped": eq, "coin": coin,
		"packs": packs.duplicate(true), "pack_seq": _pack_seq, "pending_fell": _pending_fell.duplicate(true)}

func load_from_dict(data: Dictionary) -> void:
	items.clear()
	equipped.clear()
	_uid = 0
	for raw in data.get("items", []):
		if not raw is Dictionary or not defs.has(str(raw.get("id", ""))):
			continue
		items.append(_loaded_record(raw))
	var eq = data.get("equipped", {})
	for slot in eq if eq is Dictionary else {}:
		var i = int(eq[slot])
		if slot in SLOTS and i >= 0 and i < items.size():
			equipped[slot] = items[i].uid
	coin = maxi(int(data.get("coin", 0)), 0)
	packs = {}
	for pack_id in data.get("packs", {}) if data.get("packs") is Dictionary else {}:
		var pack: Dictionary = data.packs[pack_id].duplicate(true)
		pack["coin"] = int(pack.get("coin", 0))
		pack["minute"] = int(pack.get("minute", 0))
		pack["items"] = pack.get("items", []).map(func(r): return _bare(_loaded_record(r)))
		packs[str(pack_id)] = pack
	_pack_seq = int(data.get("pack_seq", packs.size()))
	_pending_fell = data.get("pending_fell", {}).duplicate(true) if data.get("pending_fell") is Dictionary else {}
	changed.emit()
	if is_inside_tree() and get_tree().current_scene and _location() != "":
		call_deferred("spawn_packs", get_tree().current_scene, _location())

## JSON brings numbers back as floats: give a record its types again
func _loaded_record(raw: Dictionary) -> Dictionary:
	var rec: Dictionary = raw.duplicate(true)
	rec["uid"] = _next_uid()
	rec["qty"] = int(rec.get("qty", 1))
	rec["quality"] = int(rec.get("quality", DEFAULT_QUALITY))
	rec["durability"] = float(rec.get("durability", 0.0))
	rec["max_durability"] = float(rec.get("max_durability", 0.0))
	rec["maker"] = str(rec.get("maker", ""))
	rec["broken"] = rec.get("broken", false) == true
	rec["recognised"] = rec.get("recognised", false) == true
	var prov: Dictionary = rec.get("provenance", {}) if rec.get("provenance") is Dictionary else {}
	rec["provenance"] = {"from": str(prov.get("from", "")), "stolen": prov.get("stolen", false) == true, "owner": str(prov.get("owner", ""))}
	if prov.get("known_by") is Array and not prov.known_by.is_empty():
		rec.provenance["known_by"] = prov.known_by.duplicate()
	return rec
