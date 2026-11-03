"""Creatures and the minors rule (docs/PLAYER_SYSTEMS.md §3, §1.4).

resources/combat/creatures.json: every creature has an id, a name, positive health, non-negative
damage, a known damage type and behaviour, resistances within -1..1, where-entries naming real
locations with a count range and a chance, and drops naming item ids (checked against
resources/items/*.json when that folder exists). No forbidden concept in any name or text.
Archetypes: a `minor:` header, when present, says true or false.
"""
import json
import re

DAMAGE_TYPES = {"cut", "pierce", "blunt", "fire"}
BEHAVIOURS = {"stalk", "charge", "flee_when_hurt"}
NUMBERS = ("health", "damage", "poise", "speed", "charge_speed", "sense", "reach", "attack_seconds")


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

    # Generic archetypes: `minor: true` makes every instance a child (never a combat target)
    for arch in sorted((root / "resources/generics/archetypes").glob("*.md")):
        m = re.search(r"^minor:\s*(\S+)\s*$", arch.read_text(), re.M)
        if m and m.group(1).lower() not in ("true", "false", "yes", "no"):
            ctx["err"](str(arch.relative_to(root)), f"'minor:' must be true or false, not '{m.group(1)}'")
