"""Creatures and the minors rule (docs/PLAYER_SYSTEMS.md §3, §1.4).

resources/combat/creatures.json: every creature has an id, a name, positive health, non-negative
damage, a known damage type and behaviour, resistances within -1..1, where-entries naming real
locations with a count range and a chance, and drops naming item ids (checked against
resources/items/*.json when that folder exists). No forbidden concept in any name or text.
Every creature has `regrow_days` > 0 (how long a kill thins its place).
Buildings (docs/WORLD_SCHEMA.md "Buildings"): a world.json location's `building`, when present, is
true or false (else interiors are buildings, exteriors are not). No `where` names a building, no
building location's scene has CreatureSpawns markers, and no marker stands inside a world_solid
StaticBody2D (a building's footprint) or within DOOR_MARGIN of a doorway (a SceneTrigger or a
"building_zones" Area2D). Scenes are read as text: positions and scales, rectangle shapes only.
Archetypes: a `minor:` header, when present, says true or false.
resources/combat/loadouts.json: npcs keyed by world.json npc keys and archetypes by archetype ids,
each weapon a weapons.json id and each armour an armour.json id (one per slot), and no loadout gives
a minor (world.json `minor`, archetype `minor: true`) a weapon or armour.
"""
import json
import re

DAMAGE_TYPES = {"cut", "pierce", "blunt", "fire"}
BEHAVIOURS = {"stalk", "charge", "flee_when_hurt"}
NUMBERS = ("health", "damage", "poise", "speed", "charge_speed", "sense", "reach", "attack_seconds")


DOOR_MARGIN = 30.0   # scripts/combat/creature.gd DOOR_MARGIN
SOLID_LAYER = 4      # world_solid


def is_building(loc):
    """scripts/combat/creature.gd location_is_building: `building`, else kind == interior"""
    if isinstance(loc.get("building"), bool):
        return loc["building"]
    return loc.get("kind") == "interior"


def _vec(text):
    m = re.match(r"Vector2\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)", text or "")
    return (float(m.group(1)), float(m.group(2))) if m else None


def read_tscn(path):
    """Nodes of a .tscn as {path: {type, props, parent}} plus sub_resource rect sizes and ext scripts"""
    nodes, subs, exts, cur = {}, {}, {}, None
    for line in path.read_text().splitlines():
        head = re.match(r"\[(\w+)(.*)\]$", line.strip())
        if head:
            kind, attrs = head.group(1), dict(re.findall(r'(\w+)="([^"]*)"', head.group(2)))
            cur = None
            if kind == "ext_resource":
                exts[attrs.get("id")] = attrs.get("path", "")
            elif kind == "sub_resource":
                cur = subs.setdefault(attrs.get("id"), {"type": attrs.get("type")})
            elif kind == "node":
                parent = attrs.get("parent")
                name = attrs.get("name", "")
                key = name if parent is None else (name if parent == "." else f"{parent}/{name}")
                cur = nodes.setdefault(key, {"type": attrs.get("type", ""), "parent": parent, "name": name})
                groups = re.search(r"groups=\[([^\]]*)\]", head.group(2))
                cur["groups"] = groups.group(1) if groups else ""
                if parent is None:
                    cur["root"] = True
            continue
        if cur is not None and " = " in line:
            k, v = line.split(" = ", 1)
            cur[k.strip()] = v.strip()
    return nodes, subs, exts


def _xform(nodes, key):
    """(scale, offset) of a node relative to the scene root (position and scale; None if rotated)"""
    chain = []
    while key in nodes and not nodes[key].get("root"):
        chain.append(nodes[key])
        parent = nodes[key]["parent"]
        key = parent if parent != "." else None
        if key is None:
            break
    sx, sy, ox, oy = 1.0, 1.0, 0.0, 0.0
    for n in reversed(chain):
        if "rotation" in n:
            return None
        px, py = _vec(n.get("position")) or (0.0, 0.0)
        ox, oy = ox + sx * px, oy + sy * py
        nsx, nsy = _vec(n.get("scale")) or (1.0, 1.0)
        sx, sy = sx * nsx, sy * nsy
    return sx, sy, ox, oy


def _rects(nodes, subs, owner):
    """Root-space rects (x0, y0, x1, y1) of the rectangle CollisionShape2Ds under `owner`"""
    out = []
    for key, n in nodes.items():
        if n["type"] != "CollisionShape2D" or n["parent"] != owner or n.get("disabled") == "true":
            continue
        m = re.match(r'SubResource\("([^"]+)"\)', n.get("shape", ""))
        sub = subs.get(m.group(1)) if m else None
        size = _vec(sub.get("size")) if sub and sub.get("type") == "RectangleShape2D" else None
        t = _xform(nodes, key)
        if size is None or t is None:
            continue
        sx, sy, ox, oy = t
        hw, hh = abs(sx) * size[0] / 2, abs(sy) * size[1] / 2
        out.append((ox - hw, oy - hh, ox + hw, oy + hh))
    return out


def scene_blockers(path):
    """(solids, doors, markers) of a scene: world_solid body rects, doorway rects grown by DOOR_MARGIN
    as (rect, target), and CreatureSpawns markers as (name, x, y)"""
    nodes, subs, exts = read_tscn(path)
    solids, doors, markers = [], [], []
    for key, n in nodes.items():
        script = re.match(r'ExtResource\("([^"]+)"\)', n.get("script", ""))
        script = exts.get(script.group(1), "") if script else ""
        owner = "." if n.get("root") else key
        # world_solid.gd puts its body on world_solid at runtime, whatever the scene says
        if n["type"] == "StaticBody2D" and (script.endswith("world_solid.gd") or int(n.get("collision_layer", "1")) & SOLID_LAYER):
            solids += _rects(nodes, subs, owner)
        elif n["type"] == "Area2D" and (script.endswith("scene_trigger.gd") or "building_zones" in n.get("groups", "")):
            target = (n.get("target_location") or '""').strip('"')
            doors += [((r[0] - DOOR_MARGIN, r[1] - DOOR_MARGIN, r[2] + DOOR_MARGIN, r[3] + DOOR_MARGIN), target) for r in _rects(nodes, subs, owner)]
        elif n["type"] == "Marker2D" and (n["parent"] or "").split("/")[-1] == "CreatureSpawns":
            t = _xform(nodes, key)
            if t:
                markers.append((n["name"], t[2], t[3]))
    return solids, doors, markers


def _inside(r, x, y):
    return r[0] <= x <= r[2] and r[1] <= y <= r[3]


def _validate_buildings(ctx, root, creatures):
    world = "resources/world/world.json"
    locs = {str(l.get("id")): l for l in ctx["world"].get("locations", []) if isinstance(l, dict)}
    for lid, loc in locs.items():
        if "building" in loc and not isinstance(loc["building"], bool):
            ctx["err"](f"{world}:{lid}", "'building' must be true or false")
    for c in creatures:
        for entry in c.get("where", []) if isinstance(c, dict) else []:
            lid = entry.get("location") if isinstance(entry, dict) else None
            if lid in locs and is_building(locs[lid]):
                ctx["err"](f"resources/combat/creatures.json:{c.get('id')}", f"where: '{lid}' is a building (creatures never go indoors)")
    for lid, loc in sorted(locs.items()):
        scene = str(loc.get("scene", ""))
        path = root / scene.replace("res://", "") if scene.startswith("res://") else None
        if path is None or not path.exists():
            continue
        solids, doors, markers = scene_blockers(path)
        where = scene.replace("res://", "")
        if markers and is_building(loc):
            ctx["err"](where, f"CreatureSpawns in '{lid}', a building (creatures never go indoors)")
        for name, x, y in markers:
            if any(_inside(r, x, y) for r in solids):
                ctx["err"](where, f"CreatureSpawns/{name} stands inside a building or wall (world_solid body)")
            for r, target in doors:
                if _inside(r, x, y):
                    ctx["err"](where, f"CreatureSpawns/{name} stands in the doorway to '{target or '?'}'")


def _range(value):
    return isinstance(value, list) and len(value) == 2 and all(isinstance(v, int) for v in value) and 0 <= value[0] <= value[1]


def _item_ids(root):
    folder = root / "resources/items"
    if not folder.is_dir():
        return None
    ids = set()
    for path in folder.glob("*.json"):
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        rows = data.get("items", data) if isinstance(data, dict) else data
        for row in rows if isinstance(rows, list) else []:
            if isinstance(row, dict) and row.get("id"):
                ids.add(str(row["id"]))
    return ids


def _forbidden(ctx, where, text):
    for word in ctx["forbidden"]:
        if re.search(r"\b%s\b" % re.escape(word.lower()), text.lower()):
            ctx["err"](where, f"forbidden concept '{word}'")


def validate(ctx):
    root = ctx["root"]
    path = root / "resources/combat/creatures.json"
    where = "resources/combat/creatures.json"
    if not path.exists():
        ctx["err"](where, "missing")
        return
    try:
        data = json.loads(path.read_text())
    except ValueError as e:
        ctx["err"](where, f"bad JSON: {e}")
        return
    creatures = data.get("creatures") if isinstance(data, dict) else None
    if not isinstance(creatures, list) or not creatures:
        ctx["err"](where, "needs a non-empty 'creatures' list")
        return
    items = _item_ids(root)
    seen = set()
    for c in creatures:
        cid = str(c.get("id", "")) if isinstance(c, dict) else ""
        w = f"{where}:{cid or '?'}"
        if not re.fullmatch(r"[a-z][a-z0-9_]*", cid):
            ctx["err"](w, "id must be lowercase letters, digits and _")
            continue
        if cid in seen:
            ctx["err"](w, "duplicate id")
        seen.add(cid)
        if not str(c.get("name", "")).strip():
            ctx["err"](w, "missing name")
        for key in NUMBERS:
            v = c.get(key)
            if not isinstance(v, (int, float)) or v < 0 or (key == "health" and v <= 0):
                ctx["err"](w, f"'{key}' must be a {'positive' if key == 'health' else 'non-negative'} number")
        if c.get("damage_type") not in DAMAGE_TYPES:
            ctx["err"](w, f"damage_type must be one of {sorted(DAMAGE_TYPES)}")
        behaviour = c.get("behaviour", [])
        if not isinstance(behaviour, list) or not behaviour or any(b not in BEHAVIOURS for b in behaviour):
            ctx["err"](w, f"behaviour must list some of {sorted(BEHAVIOURS)}")
        elif not ({"stalk", "charge"} & set(behaviour)):
            ctx["err"](w, "behaviour needs stalk or charge (how it closes in)")
        flee = c.get("flee_below", 0)
        if not isinstance(flee, (int, float)) or not 0 <= flee < 1:
            ctx["err"](w, "flee_below must be 0..1")
        elif "flee_when_hurt" in (behaviour or []) and flee <= 0:
            ctx["err"](w, "flee_when_hurt needs flee_below > 0")
        for dtype, v in (c.get("resist") or {}).items():
            if dtype not in DAMAGE_TYPES or not isinstance(v, (int, float)) or not -1 <= v <= 1:
                ctx["err"](w, f"resist {dtype}: type must be known and value -1..1")
        regrow = c.get("regrow_days")
        if not isinstance(regrow, (int, float)) or isinstance(regrow, bool) or regrow <= 0:
            ctx["err"](w, "regrow_days must be a positive number of game days")
        lives = c.get("where", [])
        if not isinstance(lives, list) or not lives:
            ctx["err"](w, "needs 'where' (the locations it lives in)")
        for entry in lives if isinstance(lives, list) else []:
            loc = entry.get("location") if isinstance(entry, dict) else None
            if loc not in ctx["locations"]:
                ctx["err"](w, f"where: unknown location '{loc}'")
                continue
            if not _range(entry.get("count")) or entry["count"][1] < 1:
                ctx["err"](w, f"where {loc}: count must be [lo, hi] with hi >= 1")
            chance = entry.get("chance", 1.0)
            if not isinstance(chance, (int, float)) or not 0 < chance <= 1:
                ctx["err"](w, f"where {loc}: chance must be in (0, 1]")
        for drop in c.get("drops", []):
            item = drop.get("item") if isinstance(drop, dict) else None
            if not item or not re.fullmatch(r"[a-z][a-z0-9_]*", str(item)):
                ctx["err"](w, f"drop item id '{item}' must be lowercase letters, digits and _")
                continue
            if not _range(drop.get("qty")) or drop["qty"][1] < 1:
                ctx["err"](w, f"drop {item}: qty must be [lo, hi] with hi >= 1")
            chance = drop.get("chance", 1.0)
            if not isinstance(chance, (int, float)) or not 0 < chance <= 1:
                ctx["err"](w, f"drop {item}: chance must be in (0, 1]")
            if items is not None and item not in items:
                ctx["warn"](w, f"drop '{item}' is not in resources/items (yet)")
        _forbidden(ctx, w, " ".join(str(c.get(k, "")) for k in ("id", "name", "description")))

    # Generic archetypes: `minor: true` makes every instance a child (never an NPC's or creature's target)
    for arch in sorted((root / "resources/generics/archetypes").glob("*.md")):
        m = re.search(r"^minor:\s*(\S+)\s*$", arch.read_text(), re.M)
        if m and m.group(1).lower() not in ("true", "false", "yes", "no"):
            ctx["err"](str(arch.relative_to(root)), f"'minor:' must be true or false, not '{m.group(1)}'")

    _validate_buildings(ctx, root, creatures)
    _validate_loadouts(ctx, root)


def _json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def _validate_loadouts(ctx, root):
    where = "resources/combat/loadouts.json"
    path = root / where
    if not path.exists():
        return
    data = _json(path)
    if not isinstance(data, dict):
        ctx["err"](where, "bad JSON")
        return
    weapons = (_json(root / "resources/combat/weapons.json") or {}).get("weapons", {})
    armour = (_json(root / "resources/combat/armour.json") or {}).get("armour", {})
    npcs = {str(n.get("key")): n for n in ctx["world"].get("npcs", []) if isinstance(n, dict)}
    arch_dir = root / "resources/generics/archetypes"
    archetypes = {}
    for arch in sorted(arch_dir.glob("*.md")):
        text = arch.read_text()
        m = re.search(r"^archetype:\s*(\S+)\s*$", text, re.M)
        minor = re.search(r"^minor:\s*(true|yes)\s*$", text, re.M | re.I)
        archetypes[m.group(1) if m else arch.stem] = bool(minor)
    for group, known in (("npcs", {k: bool(v.get("minor")) for k, v in npcs.items()}), ("archetypes", archetypes)):
        rows = data.get(group, {})
        if not isinstance(rows, dict):
            ctx["err"](where, f"'{group}' must be an object")
            continue
        for key, row in rows.items():
            w = f"{where}:{group}.{key}"
            if key not in known:
                ctx["err"](w, f"unknown {'npc key' if group == 'npcs' else 'archetype'}")
                continue
            if not isinstance(row, dict):
                ctx["err"](w, "must be an object")
                continue
            weapon = row.get("weapon")
            kit = row.get("armour", [])
            if weapon is not None and weapon not in weapons:
                ctx["err"](w, f"weapon '{weapon}' is not in weapons.json")
            if not isinstance(kit, list):
                ctx["err"](w, "armour must be a list")
                kit = []
            slots = set()
            for a in kit:
                if a not in armour:
                    ctx["err"](w, f"armour '{a}' is not in armour.json")
                    continue
                slot = armour[a].get("slot")
                if slot in slots:
                    ctx["err"](w, f"two pieces for the {slot} slot")
                slots.add(slot)
            if known[key] and (weapon not in (None, "", "fists") or kit):
                ctx["err"](w, "a minor carries nothing")
            _forbidden(ctx, w, str(row.get("why", "")))
