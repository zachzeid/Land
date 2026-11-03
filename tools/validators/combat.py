"""Combat content (docs/PLAYER_SYSTEMS.md §3): resources/combat/weapons.json and armour.json.

Weapons: damage by known types, positive stamina per action, reach/arc/speed, poise, wear, a skill that
exists (resources/player/skills.json when present, else the spec's twelve), ranged weapons with a
projectile speed, fists present. Armour: slot body|head|off_hand, resistances by known type within 0..0.8,
shields with a block share. No forbidden concepts in any id or text. Stdlib only.
"""
import json
import re

DAMAGE_TYPES = {"cut", "pierce", "blunt", "fire"}
SPEC_SKILLS = {"blades", "blunt", "bows", "defence", "athletics", "stealth", "smithing", "woodcraft",
               "herbcraft", "mining", "speech", "lore"}
COMBAT_SKILLS = {"blades", "blunt", "bows"}
WEAPON_KINDS = {"melee", "ranged"}
MELEE_ACTIONS = {"light", "heavy"}
ARMOUR_SLOTS = {"body", "head", "off_hand"}  # Inventory equipment slots
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
RESIST_CAP = 0.8


def _load(ctx, rel):
    path = ctx["root"] / rel
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        ctx["err"](rel, f"invalid JSON: {e}")
        return None


def _skills(ctx):
    path = ctx["root"] / "resources/player/skills.json"
    if not path.exists():
        return SPEC_SKILLS
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        return SPEC_SKILLS
    if isinstance(data, dict) and isinstance(data.get("skills"), (dict, list)):
        data = data["skills"]
    if isinstance(data, dict):
        return set(data)
    if isinstance(data, list):
        return {s.get("id") if isinstance(s, dict) else s for s in data}
    return SPEC_SKILLS


def _texts(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield str(k)
            yield from _texts(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _texts(v)


def _forbidden(ctx, where, obj):
    for text in _texts(obj):
        low = text.lower()
        for w in ctx["forbidden"]:
            if re.search(r"(?<![a-z])" + re.escape(w.lower()) + r"(?![a-z])", low):
                ctx["err"](where, f"forbidden concept '{w}' in '{text[:60]}'")


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _damage(ctx, where, dmg):
    if not isinstance(dmg, dict) or not dmg:
        ctx["err"](where, "damage must be a non-empty {type: amount}")
        return
    for t, v in dmg.items():
        if t not in DAMAGE_TYPES:
            ctx["err"](where, f"unknown damage type '{t}' (cut, pierce, blunt, fire)")
        if not _num(v) or v <= 0:
            ctx["err"](where, f"damage.{t} must be a positive number")


def validate_weapons(ctx, data, skills):
    rel = "resources/combat/weapons.json"
    weapons = data.get("weapons") if isinstance(data, dict) else None
    if not isinstance(weapons, dict) or not weapons:
        ctx["err"](rel, "needs a non-empty 'weapons' object")
        return
    if "fists" not in weapons:
        ctx["err"](rel, "needs 'fists' (what a broken weapon hits like)")
    for wid, w in weapons.items():
        where = f"{rel}:{wid}"
        if not ID_RE.match(wid):
            ctx["err"](where, "id must be snake_case")
        if not isinstance(w, dict):
            ctx["err"](where, "must be an object")
            continue
        kind = w.get("kind", "melee")
        if kind not in WEAPON_KINDS:
            ctx["err"](where, f"kind must be melee|ranged, not '{kind}'")
        if not isinstance(w.get("name"), str) or not w.get("name"):
            ctx["err"](where, "needs a name")
        _damage(ctx, where, w.get("damage"))
        stamina = w.get("stamina")
        needed = {"shoot"} if kind == "ranged" else MELEE_ACTIONS
        if not isinstance(stamina, dict) or not needed <= set(stamina):
            ctx["err"](where, f"stamina needs {sorted(needed)}")
        else:
            for a, v in stamina.items():
                if a not in MELEE_ACTIONS | {"shoot"}:
                    ctx["err"](where, f"unknown stamina action '{a}'")
                elif not _num(v) or v <= 0:
                    ctx["err"](where, f"stamina.{a} must be positive")
            if kind == "melee" and _num(stamina.get("light")) and _num(stamina.get("heavy")) and stamina["heavy"] <= stamina["light"]:
                ctx["warn"](where, "a heavy should cost more stamina than a light")
        for key in ("reach", "speed"):
            if not _num(w.get(key)) or w[key] <= 0:
                ctx["err"](where, f"{key} must be a positive number")
        if kind == "melee" and (not _num(w.get("arc")) or not 0 < w["arc"] <= 360):
            ctx["err"](where, "arc must be degrees in (0, 360]")
        if kind == "ranged" and (not _num(w.get("projectile_speed")) or w["projectile_speed"] <= 0):
            ctx["err"](where, "a ranged weapon needs a positive projectile_speed")
        for key in ("poise", "durability_per_hit"):
            if not _num(w.get(key)) or w[key] < 0:
                ctx["err"](where, f"{key} must be a number >= 0")
        if "block" in w and (not _num(w["block"]) or not 0 <= w["block"] <= 1):
            ctx["err"](where, "block must be a share in 0..1")
        skill = w.get("skill")
        if skill not in skills:
            ctx["err"](where, f"skill '{skill}' is not a skill (resources/player/skills.json)")
        elif skill not in COMBAT_SKILLS:
            ctx["warn"](where, f"skill '{skill}' is not a weapon skill (blades, blunt, bows)")
        _forbidden(ctx, where, w)
        _forbidden(ctx, where, wid)


def validate_armour(ctx, data):
    rel = "resources/combat/armour.json"
    armour = data.get("armour") if isinstance(data, dict) else None
    if not isinstance(armour, dict):
        ctx["err"](rel, "needs an 'armour' object")
        return
    for aid, a in armour.items():
        where = f"{rel}:{aid}"
        if not ID_RE.match(aid):
            ctx["err"](where, "id must be snake_case")
        if not isinstance(a, dict):
            ctx["err"](where, "must be an object")
            continue
        if not isinstance(a.get("name"), str) or not a.get("name"):
            ctx["err"](where, "needs a name")
        if a.get("slot") not in ARMOUR_SLOTS:
            ctx["err"](where, f"slot must be body|head|off_hand, not '{a.get('slot')}'")
        resist = a.get("resist", {})
        if not isinstance(resist, dict):
            ctx["err"](where, "resist must be {type: share}")
        else:
            for t, v in resist.items():
                if t not in DAMAGE_TYPES:
                    ctx["err"](where, f"unknown damage type '{t}'")
                elif not _num(v) or not 0 <= v <= RESIST_CAP:
                    ctx["err"](where, f"resist.{t} must be in 0..{RESIST_CAP}")
        if "poise" in a and (not _num(a["poise"]) or a["poise"] < 0):
            ctx["err"](where, "poise must be >= 0")
        if a.get("slot") == "off_hand" and (not _num(a.get("block")) or not 0 < a["block"] <= 1):
            ctx["err"](where, "a shield needs a block share in (0, 1]")
        _forbidden(ctx, where, a)
        _forbidden(ctx, where, aid)


def validate(ctx):
    skills = _skills(ctx)
    weapons = _load(ctx, "resources/combat/weapons.json")
    if weapons is None:
        ctx["err"]("resources/combat/weapons.json", "missing")
    else:
        validate_weapons(ctx, weapons, skills)
    armour = _load(ctx, "resources/combat/armour.json")
    if armour is None:
        ctx["err"]("resources/combat/armour.json", "missing")
    else:
        validate_armour(ctx, armour)
