"""Puzzles (docs/PLAYER_SYSTEMS.md §5.2, §5.3): resources/puzzles/*.json.

Every puzzle's flag is a declared flag (world.json discovery_flags, or a storyline's flags, so solving
it moves a real story); every `requires` flag is known; every clue exists: a StoryItem node of that
name in its scene (with the flag it claims), or a declared examinable object with text and a real
location. Answers are well formed for their shape, names in a `name` answer are NPC keys, rooms point
at real scenes built from the WorldPhysics components, and no forbidden concept appears anywhere.
"""
import json
import re

SHAPES = {"choose", "arrange", "name", "decode"}
TYPES = {"lore", "room"}
COMPONENTS = {"flammable", "pressure_plate", "rope", "lamp", "basin", "metal"}
STORY_ITEM_SCRIPT = "res://scripts/world/story_item.gd"


def _scene_nodes(path):
    """{node name: {"story_item": bool, "flag": str}} for a .tscn, and the set of script paths it uses"""
    text = path.read_text()
    ext = dict((m.group(2), m.group(1)) for m in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text))
    nodes = {}
    for block in re.split(r"\n(?=\[node )", text):
        m = re.match(r'\[node name="([^"]+)"', block)
        if not m:
            continue
        s = re.search(r'script = ExtResource\("([^"]+)"\)', block)
        f = re.search(r'flag_to_set = "([^"]*)"', block)
        nodes[m.group(1)] = {"script": ext.get(s.group(1), "") if s else "", "flag": f.group(1) if f else ""}
    return nodes, set(ext.values())


def _res(root, res_path):
    return root / res_path.replace("res://", "", 1)


def validate(ctx):
    root, err, warn = ctx["root"], ctx["err"], ctx["warn"]
    pdir = root / "resources/puzzles"
    if not pdir.exists():
        return
    world = ctx["world"]
    discovery = set(world.get("discovery_flags", {}))
    story_flags = set()
    for p in (root / "resources/storylines").glob("*.json"):
        try:
            story_flags |= set(json.loads(p.read_text()).get("flags", {}))
        except json.JSONDecodeError:
            pass
    known = set(ctx["flags_known"]) | discovery | story_flags
    npc_keys = set(ctx["npc_keys"])
    locations = ctx["locations"]
    scene_cache = {}
    seen_ids = set()
    for path in sorted(pdir.glob("*.json")):
        where = str(path.relative_to(root))
        try:
            p = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            err(where, f"bad JSON: {e}")
            continue
        pid = p.get("id", "")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", str(pid)):
            err(where, f"id '{pid}' is not snake_case")
        if pid in seen_ids:
            err(where, f"duplicate puzzle id '{pid}'")
        seen_ids.add(pid)
        kind = p.get("type", "lore")
        if kind not in TYPES:
            err(where, f"type '{kind}' not one of {sorted(TYPES)}")
        for key in ("title", "summary", "solved_summary"):
            if not str(p.get(key, "")).strip():
                err(where, f"missing {key}")
        if len(str(p.get("solved_summary", ""))) > 140:
            err(where, "solved_summary over 140 characters (PlayerEvents trims deed summaries there)")
        flag = p.get("flag", "")
        if flag not in discovery and flag not in story_flags:
            err(where, f"flag '{flag}' is neither a world.json discovery flag nor a storyline flag")
        if p.get("location") not in locations:
            err(where, f"location '{p.get('location')}' unknown")
        for f in p.get("requires", []):
            if f.lstrip("!") not in known:
                err(where, f"requires flag '{f}' unknown")
        for a in p.get("about", []):
            if a not in npc_keys:
                err(where, f"about '{a}' is not an NPC key")
        if kind == "lore":
            _validate_lore(p, where, root, err, warn, npc_keys, locations, scene_cache, known)
        else:
            _validate_room(p, where, root, err, scene_cache)
        text = json.dumps(p).lower()
        for w in ctx["forbidden"]:
            if re.search(r"\b" + re.escape(w) + r"s?\b", text):
                err(where, f"forbidden concept '{w}'")


def _validate_lore(p, where, root, err, warn, npc_keys, locations, scene_cache, known):
    if not str(p.get("question", "")).strip():
        err(where, "missing question")
    if not p.get("requires"):
        warn(where, "requires nothing: the answer can be guessed before any clue is found")
    clues = p.get("clues", [])
    if not clues:
        err(where, "no clues")
    for c in clues:
        cw = f"{where} clue {c.get('id')}"
        ck = c.get("kind")
        if ck == "story_item":
            scene = c.get("scene", "")
            sp = _res(root, scene)
            if not sp.exists():
                err(cw, f"scene {scene} missing")
                continue
            if scene not in scene_cache:
                scene_cache[scene] = _scene_nodes(sp)
            node = scene_cache[scene][0].get(c.get("id"))
            if node is None:
                err(cw, f"no node '{c.get('id')}' in {scene}")
            elif node["script"] != STORY_ITEM_SCRIPT:
                err(cw, f"'{c.get('id')}' in {scene} is not a StoryItem")
            elif c.get("flag") and node["flag"] != c["flag"]:
                err(cw, f"claims flag '{c['flag']}' but the StoryItem sets '{node['flag']}'")
            if c.get("flag") and c["flag"] not in known:
                err(cw, f"flag '{c['flag']}' unknown")
            if not str(c.get("note", "")).strip():
                err(cw, "a StoryItem clue needs a note (what it shows toward the answer)")
        elif ck == "object":
            if c.get("location") not in locations:
                err(cw, f"location '{c.get('location')}' unknown")
            if not str(c.get("text", c.get("note", ""))).strip():
                err(cw, "a declared object needs text")
        else:
            err(cw, f"kind '{ck}' not story_item or object")
    ans = p.get("answer", {})
    shape = ans.get("shape")
    if shape not in SHAPES:
        err(where, f"answer shape '{shape}' not one of {sorted(SHAPES)}")
        return
    if shape == "choose":
        ids = [o.get("id") for o in ans.get("options", [])]
        if len(ids) < 2 or len(set(ids)) != len(ids):
            err(where, "choose needs two or more distinct options")
        if ans.get("correct") not in ids:
            err(where, f"correct '{ans.get('correct')}' is not an option")
        for k in ans.get("wrong", {}):
            if k not in ids or k == ans.get("correct"):
                err(where, f"wrong '{k}' is not a wrong option")
    elif shape == "arrange":
        items = [i if isinstance(i, str) else i.get("id") for i in ans.get("items", [])]
        if sorted(items) != sorted(ans.get("correct", [])) or len(items) < 2:
            err(where, "arrange's correct order must use every item exactly once")
    elif shape == "name":
        names = ans.get("names", {})
        if ans.get("correct") not in names:
            err(where, f"correct '{ans.get('correct')}' has no names entry")
        for k, v in names.items():
            if k not in npc_keys:
                err(where, f"name '{k}' is not an NPC key")
            if k != ans.get("correct") and not v.get("near_miss") and v.get("truth", "false") not in ("true", "false"):
                err(where, f"name '{k}' truth must be true or false")
        aliases = [a.lower() for v in names.values() for a in v.get("aliases", [])]
        if len(aliases) != len(set(aliases)):
            err(where, "an alias belongs to two names")
    elif shape == "decode":
        lines = ans.get("lines", [])
        if not lines or len({l.get("id") for l in lines}) != len(lines):
            err(where, "decode needs lines with distinct ids")
        for l in lines:
            if not l.get("cipher") or not l.get("correct"):
                err(where, f"decode line '{l.get('id')}' needs cipher and correct")


def _validate_room(p, where, root, err, scene_cache):
    scene = p.get("scene", "")
    sp = _res(root, scene)
    if not scene.startswith("res://scenes/puzzles/") or not sp.exists():
        err(where, f"room scene {scene} missing (rooms live in scenes/puzzles/)")
        return
    nodes, scripts = _scene_nodes(sp)
    for node, comp in p.get("components", {}).items():
        if comp not in COMPONENTS:
            err(where, f"component '{comp}' is not a WorldPhysics component")
            continue
        want = f"res://scripts/world/physics/{comp}.gd"
        if want not in scripts:
            err(where, f"scene does not use {want}")
        camel = "".join(w.capitalize() for w in node.split("_"))
        if camel not in nodes:
            err(where, f"scene has no node '{camel}' for component '{node}'")
        elif nodes[camel]["script"] != want:
            err(where, f"node '{camel}' does not carry {want}")
    if not p.get("ways"):
        err(where, "a room needs at least one way to its reward")
    if not str(p.get("reward", "")).strip():
        err(where, "a room needs a reward that matters in the world")
