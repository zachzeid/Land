"""Judgement (docs/WORLD_SCHEMA.md §16): resources/characters/judgement.json, how each person weighs a
deed people judge by their own nature (PlayerEvents opts.morals; Taverns.judge reads it).

Checks: every morals block has range [lo, hi] (integers, lo < 0 <= hi), default reason/feels,
courting (styles named from NPCPersonality's relationship_style, weights in range and never above 0;
never: orientations; affection_share and budding_scale within 0..1; flags with at most a {key}
slot) and rules. A rule has an id, a group, a weight in range (0 for a `tone` rule), a reason and a
first-person feels line, only known condition keys, at least one condition; archetypes exist;
traits are Big Five names with [lo, hi] spans; flags are NPCPersonality booleans; scope is main or
generic. Word lists that match no soul or archetype voice are warned about (a typo judges nobody).
Nothing explicit and no forbidden concept in any text.
"""
import json
import re

PATH = "resources/characters/judgement.json"
PERSONALITY = "scripts/resources/npc_personality.gd"
BIG_FIVE = {"openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"}
CONDITIONS = {"values", "dislikes", "interests", "roles", "archetypes", "voices", "flags", "traits", "scope", "keeps_back_rooms"}
RULE_KEYS = CONDITIONS | {"id", "group", "weight", "reason", "feels", "tone"}
SOUL_FIELDS = {"values": "core_values", "dislikes": "dislikes", "interests": "interests"}
# Never in a line fed to a prompt (as tools/validators/taverns.py keeps the companion's soul)
EXPLICIT = re.compile(r"\b(sex|sexual|naked|nude|nudity|aroused|arousal|lust|lustful|erotic|seduce|seduction|undress)\b", re.I)


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _text(ctx, where, text):
    if not isinstance(text, str) or not text.strip():
        ctx["err"](where, "must be a non-empty string")
        return
    if EXPLICIT.search(text):
        ctx["err"](where, "explicit wording: nothing behind the door is ever described")
    for w in ctx["forbidden"]:
        if re.search(r"\b" + re.escape(w.lower()) + r"s?\b", text.lower()):
            ctx["err"](where, f"forbidden concept '{w}'")


def _soul_lists(root):
    """{field: [lower-cased entries across every soul]}, plus orientations used by souls"""
    out = {f: [] for f in SOUL_FIELDS}
    orientations = set()
    for p in sorted((root / "resources/npc_personalities").glob("*.tres")):
        t = p.read_text()
        for f, prop in SOUL_FIELDS.items():
            m = re.search(r"^" + prop + r" = Array\[String\]\((\[.*?\])\)", t, re.M | re.S)
            if m:
                try:
                    out[f] += [str(x).lower() for x in json.loads(m.group(1))]
                except ValueError:
                    pass
        m = re.search(r'^orientation = "([^"]+)"', t, re.M)
        if m:
            orientations.add(m.group(1))
    return out, orientations


def _voices(root):
    """{archetype id: [Voice bullet lines, lower case]}"""
    out = {}
    for p in (root / "resources/generics/archetypes").glob("*.md"):
        voice, lines = False, []
        for line in p.read_text().splitlines():
            if line.startswith("## "):
                voice = line.strip() == "## Voice"
            elif voice and line.startswith("- "):
                lines.append(line[2:].lower())
        out[p.stem] = lines
    return out


def _personality(root):
    """NPCPersonality bool flags and enums (relationship_style, orientation)"""
    t = (root / PERSONALITY).read_text()
    flags = set(re.findall(r"@export var (is_\w+): bool", t))
    enums = {}
    for m in re.finditer(r'@export_enum\(([^)]*)\) var (\w+)', t):
        enums[m.group(2)] = set(re.findall(r'"([^"]+)"', m.group(1)))
    return flags, enums


def _in_range(ctx, where, w, lo, hi):
    if not _num(w):
        ctx["err"](where, "weight must be a number")
    elif not lo <= w <= hi:
        ctx["err"](where, f"weight {w} outside range [{lo}, {hi}]")


def validate(ctx):
    root, err, warn = ctx["root"], ctx["err"], ctx["warn"]
    path = root / PATH
    if not path.exists():
        err(PATH, "missing: Taverns.judge has no rules to read")
        return
    try:
        data = json.loads(path.read_text())
    except ValueError as e:
        err(PATH, f"not valid JSON: {e}")
        return
    morals = data.get("morals")
    if not isinstance(morals, dict) or not morals:
        err(PATH, "needs a non-empty 'morals' object")
        return
    if "company" not in morals:
        err(PATH, "no 'company' block: Taverns.company records morals 'company'")
    souls, orientations = _soul_lists(root)
    voices = _voices(root)
    flags_known, enums = _personality(root)
    styles = enums.get("relationship_style", set())
    orientations |= enums.get("orientation", set())
    for name, block in morals.items():
        where = f"{PATH}:{name}"
        if not isinstance(block, dict):
            err(where, "must be an object")
            continue
        span = block.get("range")
        if not (isinstance(span, list) and len(span) == 2 and all(isinstance(v, int) and not isinstance(v, bool) for v in span) and span[0] < 0 <= span[1]):
            err(where + ":range", "must be [lo, hi], integers with lo < 0 <= hi")
            span = [-12, 3]
        lo, hi = span
        dflt = block.get("default", {})
        for k in ("reason", "feels"):
            _text(ctx, f"{where}:default:{k}", dflt.get(k) if isinstance(dflt, dict) else None)
        c = block.get("courting")
        if c is not None:
            cw = where + ":courting"
            if not isinstance(c, dict):
                err(cw, "must be an object")
            else:
                for k in ("reason", "feels"):
                    _text(ctx, f"{cw}:{k}", c.get(k))
                for s, w in (c.get("styles") or {}).items():
                    if s not in styles:
                        err(cw, f"style '{s}' is no relationship_style ({sorted(styles)})")
                    _in_range(ctx, f"{cw}:styles:{s}", w, lo, 0)
                for o in c.get("never", []):
                    if o not in orientations:
                        err(cw, f"orientation '{o}' is neither an NPCPersonality orientation nor used by a soul")
                for k in ("affection_share", "budding_scale"):
                    v = c.get(k)
                    if v is not None and not (_num(v) and 0 <= v <= 1):
                        err(cw, f"{k} must be within 0..1")
                for f in c.get("flags", []):
                    if not isinstance(f, str) or re.search(r"\{(?!key\})", f):
                        err(cw, f"flag '{f}' may only carry a {{key}} slot")
        rules = block.get("rules", [])
        if not isinstance(rules, list) or not rules:
            err(where, "needs a non-empty 'rules' list")
            continue
        for i, r in enumerate(rules):
            rw = f"{where}:rules[{i}]"
            if not isinstance(r, dict):
                err(rw, "must be an object")
                continue
            rw = f"{where}:{r.get('id', i)}"
            for k in sorted(set(r) - RULE_KEYS):
                err(rw, f"unknown key '{k}'")
            for k in ("id", "group"):
                if not isinstance(r.get(k), str) or not r.get(k):
                    err(rw, f"needs a '{k}'")
            if not set(r) & CONDITIONS:
                err(rw, "has no condition: it would judge everyone")
            _in_range(ctx, rw, r.get("weight"), lo, hi)
            if r.get("tone") and r.get("weight") != 0:
                err(rw, "a tone rule only words the view: weight must be 0")
            _text(ctx, rw + ":reason", r.get("reason"))
            _text(ctx, rw + ":feels", r.get("feels"))
            for field in ("values", "dislikes", "interests", "roles", "voices"):
                if field not in r:
                    continue
                words = r[field]
                if not isinstance(words, list) or not words or not all(isinstance(w, str) and w for w in words):
                    err(rw, f"'{field}' must be a non-empty list of words")
                    continue
                if field in SOUL_FIELDS:
                    pool = souls[field]
                elif field == "voices":
                    pool = [v for vs in voices.values() for v in vs]
                else:
                    pool = [str(n.get("role", "")).lower() for n in ctx["world"].get("npcs", [])]
                if not any(w.lower() in e for w in words for e in pool):
                    warn(rw, f"no word in '{field}' matches anyone today")
            for a in r.get("archetypes", []):
                if a not in voices:
                    err(rw, f"unknown archetype '{a}'")
            for f, v in (r.get("flags") or {}).items():
                if f not in flags_known:
                    err(rw, f"'{f}' is no NPCPersonality flag ({sorted(flags_known)})")
                if not isinstance(v, bool):
                    err(rw, f"flag '{f}' must be true or false")
            for t, s in (r.get("traits") or {}).items():
                if t not in BIG_FIVE:
                    err(rw, f"'{t}' is no Big Five trait")
                if not (isinstance(s, list) and len(s) == 2 and all(_num(x) for x in s) and s[0] <= s[1]):
                    err(rw, f"trait '{t}' needs [lo, hi]")
            if "scope" in r and r["scope"] not in ("main", "generic"):
                err(rw, "scope must be main or generic")
            if "keeps_back_rooms" in r and r["keeps_back_rooms"] is not True:
                err(rw, "keeps_back_rooms is only ever true")
