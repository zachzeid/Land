"""Taverns (docs/WORLD_SCHEMA.md "Taverns"): world.json locations with a `tavern` block.

Every tavern block is {keeper, rooms, rent_copper, brothel}: rooms >= 1, rent > 0, a keeper who exists
(an NPC key, a generic archetype, or a generic id of one), a scene holding at least `rooms` Bed nodes
(scripts/world/bed.gd) at that rent, each with its own Marker2D under SpawnPoints. Back rooms
(Bed back_room = true) and the companions who keep them (archetype house_companion) appear only where
brothel is true, never alongside a child (a minor archetype in its population, or a minor NPC who
lives there). The companion archetype is adult (an `age:` header starting at 20 or more, never
`minor:`) and its text carries nothing explicit.
"""
import json
import re

BED_SCRIPT = "res://scripts/world/bed.gd"
DOOR_SCRIPT = "res://scripts/world/room_door.gd"
COMPANION = "house_companion"
KEYS = {"keeper", "rooms", "rent_copper", "brothel"}
MIN_AGE = 20
# Words a companion's soul must never carry: it is fed to the conversation prompt
EXPLICIT = re.compile(r"\b(sex|sexual|naked|nude|nudity|aroused|arousal|lust|lustful|erotic|seduce|seduction|undress)\b", re.I)


def _scene(path):
    """Bed nodes [{name, spawn_point, rent, back_room}], SpawnPoints marker names, door count"""
    text = path.read_text()
    ext = dict((m.group(2), m.group(1)) for m in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text))
    beds, markers, doors = [], set(), 0
    for block in re.split(r"\n(?=\[node )", text):
        m = re.match(r'\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]*)")?', block)
        if not m:
            continue
        name, ntype, parent = m.group(1), m.group(2), m.group(3) or ""
        s = re.search(r'script = ExtResource\("([^"]+)"\)', block)
        script = ext.get(s.group(1), "") if s else ""
        if script == BED_SCRIPT:
            sp = re.search(r'spawn_point = "([^"]*)"', block)
            rent = re.search(r"^rent = (\d+)", block, re.M)
            beds.append({"name": name, "spawn_point": sp.group(1) if sp else "bed", "rent": int(rent.group(1)) if rent else 0,
                         "back_room": bool(re.search(r"^back_room = true", block, re.M))})
        elif script == DOOR_SCRIPT:
            doors += 1
        if ntype == "Marker2D" and parent == "SpawnPoints":
            markers.add(name)
    return beds, markers, doors


def _header(text, key):
    for line in text.splitlines():
        if line.startswith("## "):
            break
        if line.lower().startswith(key + ":"):
            return line.split(":", 1)[1].strip()
    return None


def validate(ctx):
    root, err, warn = ctx["root"], ctx["err"], ctx["warn"]
    world = ctx["world"]
    npc_keys = set(ctx["npc_keys"])
    arch_dir = root / "resources/generics/archetypes"
    archetypes = {p.stem: p.read_text() for p in arch_dir.glob("*.md")} if arch_dir.exists() else {}
    minors = {a for a, t in archetypes.items() if (_header(t, "minor") or "").lower() in ("true", "yes")}
    pop_path = root / "resources/generics/population.json"
    population = json.loads(pop_path.read_text()).get("locations", {}) if pop_path.exists() else {}
    npcs = world.get("npcs", [])
    taverns = {}
    for loc in world.get("locations", []):
        if "tavern" not in loc:
            continue
        where = f"world.json:{loc.get('id')}:tavern"
        t = loc["tavern"]
        if not isinstance(t, dict):
            err(where, "must be an object {keeper, rooms, rent_copper, brothel}")
            continue
        taverns[loc["id"]] = t
        for k in sorted(KEYS - set(t)):
            err(where, f"missing '{k}'")
        for k in sorted(set(t) - KEYS):
            err(where, f"unknown key '{k}'")
        rooms, rent, brothel = t.get("rooms"), t.get("rent_copper"), t.get("brothel")
        if not isinstance(rooms, int) or isinstance(rooms, bool) or rooms < 1:
            err(where, "rooms must be a whole number, 1 or more")
            rooms = 0
        if not isinstance(rent, int) or isinstance(rent, bool) or rent <= 0:
            err(where, "rent_copper must be a whole number of copper above 0")
        if not isinstance(brothel, bool):
            err(where, "brothel must be true or false")
        keeper = str(t.get("keeper", ""))
        gen = re.match(r"^gen_([a-z0-9_]+?)_\d+$", keeper)
        if not (keeper in npc_keys or keeper in archetypes or (gen and gen.group(1) in archetypes)):
            err(where, f"keeper '{keeper}' is no NPC key, archetype or generic id")
        if keeper in archetypes and keeper in minors:
            err(where, f"keeper '{keeper}' is a child's archetype")
        scene = str(loc.get("scene", ""))
        path = root / scene.replace("res://", "", 1)
        if not scene or not path.exists():
            err(where, f"scene '{scene}' does not exist")
            continue
        beds, markers, doors = _scene(path)
        lettable = [b for b in beds if not b["back_room"]]
        matching = [b for b in lettable if b["rent"] == rent]
        if len(matching) < rooms:
            err(where, f"scene has {len(matching)} Bed node(s) at {rent} copper for {rooms} room(s)")
        for b in lettable:
            if b["rent"] != rent:
                err(where, f"Bed '{b['name']}' rent {b['rent']} differs from rent_copper {rent}")
        spawns = [b["spawn_point"] for b in beds]
        for sp in sorted({s for s in spawns if spawns.count(s) > 1}):
            err(where, f"two rooms share the spawn point '{sp}': each room needs its own")
        for b in beds:
            if b["spawn_point"] not in markers:
                err(where, f"Bed '{b['name']}' spawn point '{b['spawn_point']}' is not a Marker2D under SpawnPoints")
        backs = [b for b in beds if b["back_room"]]
        if backs and brothel is not True:
            err(where, f"back rooms ({', '.join(b['name'] for b in backs)}) where brothel is not true")
        if brothel is True and not backs:
            warn(where, "brothel is true but the scene has no back room (Bed back_room = true)")
        if doors < rooms:
            warn(where, f"{doors} room door(s) (room_door.gd) for {rooms} room(s): rooms without one cannot be trespassed")
        if brothel is True:
            for e in population.get(loc["id"], []):
                if e.get("archetype") in minors:
                    err(where, f"a child's archetype '{e['archetype']}' lives in a house that keeps back rooms")
            for n in npcs:
                if n.get("home") == loc["id"] and n.get("minor"):
                    err(where, f"'{n.get('key')}', a child, lives in a house that keeps back rooms")
    # Companions only where a house keeps back rooms
    for loc_id, entries in population.items():
        for e in entries:
            if e.get("archetype") == COMPANION and taverns.get(loc_id, {}).get("brothel") is not True:
                err("resources/generics/population.json", f"{loc_id}: companions live only in a tavern with brothel: true")
    text = archetypes.get(COMPANION)
    if text is not None:
        where = f"resources/generics/archetypes/{COMPANION}.md"
        age = _header(text, "age") or ""
        m = re.match(r"^(\d+)\s*-\s*(\d+)$", age)
        if not m or int(m.group(1)) < MIN_AGE or int(m.group(1)) > int(m.group(2)):
            err(where, f"needs an `age:` header lo-hi with lo {MIN_AGE} or more")
        if COMPANION in minors:
            err(where, "a companion is never a child")
        for hit in sorted({h.group(0).lower() for h in EXPLICIT.finditer(text)}):
            err(where, f"explicit word '{hit}': the back rooms are never described")
