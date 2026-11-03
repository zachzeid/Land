"""Character types (docs/WORLD_SCHEMA.md §9.1): resources/characters/character_types.json.

Checks: every type's traits are ones the engine reads (scripts/npcs/character_types.gd TRAITS, kept in
step here); skills are resources/player/skills.json ids at 0-100; temperament offsets are Big Five
names within -40..40; tactics keep_range is [lo, hi] with close_range below lo; indoor_hours a pair
of hours; npcs are world.json keys, never minors, naming a real type; archetype `type:` headers name
a real type and never sit on a `minor: true` archetype. Ranged loadouts (resources/combat/loadouts.json)
carry arrows and a melee sidearm. Population postings (posted_after/until_then) name known flags and
locations. No forbidden concept in any text.
"""
import json
import re

TRAITS = {"trail_reader", "woodwise", "keeps_distance", "beast_and_herb_lore", "weather_eye", "wilds_over_towns"}
BIG_FIVE = {"openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"}
PATH = "resources/characters/character_types.json"


def _json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def _forbidden(ctx, where, text):
    for w in ctx["forbidden"]:
        if re.search(r"\b" + re.escape(w.lower()) + r"s?\b", str(text).lower()):
            ctx["err"](where, f"forbidden concept '{w}'")


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _check_block(ctx, where, row, skill_ids):
    err = ctx["err"]
    for t in row.get("traits", []):
        if t not in TRAITS:
            err(where, f"unknown trait '{t}' (the engine reads {sorted(TRAITS)})")
    skills = row.get("skills", {})
    if not isinstance(skills, dict):
        err(where, "skills must be an object")
        skills = {}
    for sk, v in skills.items():
        if skill_ids and sk not in skill_ids:
            err(where, f"unknown skill '{sk}'")
        if not _num(v) or not 0 <= v <= 100:
            err(where, f"skill '{sk}' must be 0-100")
    for t, v in row.get("temperament", {}).items():
        if t not in BIG_FIVE:
            err(where, f"temperament '{t}' is not a Big Five trait")
        elif not isinstance(v, int) or not -40 <= v <= 40:
            err(where, f"temperament '{t}' must be an integer -40..40")
    if "morale" in row and (not _num(row["morale"]) or not -20 <= row["morale"] <= 20):
        err(where, "morale must be a number -20..20")
    tactics = row.get("tactics", {})
    keep = tactics.get("keep_range")
    if keep is not None:
        if not (isinstance(keep, list) and len(keep) == 2 and all(_num(x) for x in keep) and 0 < keep[0] < keep[1]):
            err(where, "tactics.keep_range must be [lo, hi] with 0 < lo < hi")
        elif _num(tactics.get("close_range")) and tactics["close_range"] >= keep[0]:
            err(where, "tactics.close_range must be below keep_range[0]")
    for k in ("close_range", "shoot_seconds", "switch_seconds"):
        if k in tactics and (not _num(tactics[k]) or tactics[k] <= 0):
            err(where, f"tactics.{k} must be a positive number")
    hours = row.get("indoor_hours")
    if hours is not None and not (isinstance(hours, list) and len(hours) == 2 and all(isinstance(h, int) and 0 <= h <= 24 for h in hours)):
        err(where, "indoor_hours must be [start, end] game hours")
    if "wilds_over_towns" in row.get("traits", []) and hours is None:
        err(where, "wilds_over_towns needs indoor_hours")
    sight = row.get("senses", {}).get("outdoor_sight")
    if sight is not None and (not _num(sight) or not 1.0 <= sight <= 2.0):
        err(where, "senses.outdoor_sight must be 1.0-2.0")
    for field in ("prompt", "why", "name"):
        _forbidden(ctx, where, row.get(field, ""))


def validate(ctx):
    err = ctx["err"]
    root = ctx["root"]
    path = root / PATH
    if not path.exists():
        return
    data = _json(path)
    if not isinstance(data, dict):
        err(PATH, "invalid JSON")
        return
    skills_doc = _json(root / "resources/player/skills.json") or {}
    skill_ids = {s.get("id") for s in skills_doc.get("skills", [])}
    types = data.get("types", {})
    for tid, row in types.items():
        where = f"{PATH}:types.{tid}"
        if not re.match(r"^[a-z][a-z0-9_]*$", tid):
            err(where, "bad type id")
        if not isinstance(row, dict):
            err(where, "must be an object")
            continue
        _check_block(ctx, where, row, skill_ids)
    world_npcs = {n.get("key"): n for n in ctx["world"].get("npcs", []) if isinstance(n, dict)}
    for key, row in data.get("npcs", {}).items():
        where = f"{PATH}:npcs.{key}"
        if key not in world_npcs:
            err(where, "unknown npc key")
            continue
        if world_npcs[key].get("minor"):
            err(where, "a minor has no character type (children are never fighters)")
        if not isinstance(row, dict) or row.get("type") not in types:
            err(where, f"type '{row.get('type') if isinstance(row, dict) else row}' is not a known type")
            continue
        _check_block(ctx, where, row, skill_ids)

    # Archetype `type:` headers
    typed = {}
    for arch in sorted((root / "resources/generics/archetypes").glob("*.md")):
        text = arch.read_text()
        head = text.split("\n## ", 1)[0]
        m = re.search(r"^type:\s*(\S+)\s*$", head, re.M)
        if not m:
            continue
        rel = str(arch.relative_to(root))
        if m.group(1) not in types:
            err(rel, f"type '{m.group(1)}' is not in {PATH}")
        if re.search(r"^minor:\s*(true|yes)\s*$", head, re.M | re.I):
            err(rel, "a minor archetype has no character type")
        typed[arch.stem] = m.group(1)

    # Ranged loadouts: arrows to shoot and a blade for when closed on
    loadouts = _json(root / "resources/combat/loadouts.json") or {}
    weapons = (_json(root / "resources/combat/weapons.json") or {}).get("weapons", {})
    for group in ("npcs", "archetypes"):
        for key, row in loadouts.get(group, {}).items():
            if not isinstance(row, dict):
                continue
            where = f"resources/combat/loadouts.json:{group}.{key}"
            w = weapons.get(row.get("weapon", ""), {})
            side = row.get("sidearm")
            if side is not None and weapons.get(side, {}).get("kind", "melee") != "melee":
                err(where, f"sidearm '{side}' must be a melee weapon in weapons.json")
            if side is not None and side not in weapons:
                err(where, f"sidearm '{side}' is not in weapons.json")
            arrows = row.get("arrows")
            if arrows is not None and (not isinstance(arrows, int) or not 0 <= arrows <= 60):
                err(where, "arrows must be an integer 0-60")
            if w.get("kind") == "ranged" and w.get("ammo") and not arrows:
                err(where, f"{row.get('weapon')} needs arrows to shoot")
            if w.get("kind") == "ranged" and side is None:
                ctx["warn"](where, "a bow with no sidearm fights with fists when closed on")
    for arch, tid in typed.items():
        if "keeps_distance" in types.get(tid, {}).get("traits", []):
            row = loadouts.get("archetypes", {}).get(arch)
            if not row or weapons.get(row.get("weapon", ""), {}).get("kind") != "ranged":
                ctx["warn"](f"resources/combat/loadouts.json:archetypes.{arch}", f"a {tid} keeps distance but carries no bow")

    # Population postings
    pop = _json(root / "resources/generics/population.json") or {}
    for loc, entries in pop.get("locations", {}).items():
        for e in entries if isinstance(entries, list) else []:
            if not isinstance(e, dict) or not ("posted_after" in e or "until_then" in e):
                continue
            where = f"resources/generics/population.json:{loc}.{e.get('archetype')}"
            if not e.get("posted_after") or not e.get("until_then"):
                err(where, "posted_after and until_then go together")
                continue
            if e["posted_after"] not in ctx["flags_known"]:
                err(where, f"posted_after '{e['posted_after']}' is not a known flag")
            if e["until_then"] not in ctx["locations"]:
                err(where, f"until_then '{e['until_then']}' is not a location")
            if e["until_then"] == loc:
                err(where, "until_then is the post itself")
