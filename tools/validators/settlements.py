"""Settlements and their taverns (docs/WORLD_SCHEMA.md §17).

A world.json location may carry `"settlement": "village" | "town" | "city"`: it is part of a
settlement of that size. A settlement is a group of such locations with the same size joined by
world.json routes of at most JOIN_MINUTES (a village's square, shop and gate; a city's districts),
so two villages in one region stay two settlements.
A tavern is a location with a `tavern` block. It counts for a settlement when it is a member, or
when a route of at most JOIN_MINUTES joins it to a member (a tavern entry without its own
`settlement` field still belongs to the square it opens onto). A tavern that joins no settlement is
a roadside inn (the Halfway House) and is fine.
Rule: every village and town has at least one tavern, every city at least two.
A tavern keeper that is a generic id (`gen_<archetype>_<n>`) must be an instance population.json
creates: ids number each archetype's instances 1, 2, ... in population.json order.
"""
import json

SIZES = {"village": 1, "town": 1, "city": 2}
JOIN_MINUTES = 60


def _generic_ids(root):
    path = root / "resources/generics/population.json"
    if not path.exists():
        return set()
    data = json.loads(path.read_text())
    rows = data.get("locations", data) if isinstance(data, dict) else data
    counters, ids = {}, set()
    pairs = rows.items() if isinstance(rows, dict) else [(r.get("location"), [r]) for r in rows]
    for _loc, entries in pairs:
        for e in entries:
            arch = str(e.get("archetype", ""))
            for _ in range(max(int(e.get("count", 1)), 0)):
                counters[arch] = counters.get(arch, 0) + 1
                ids.add("gen_%s_%d" % (arch, counters[arch]))
    return ids


def settlements(world):
    """[{size, members: [ids], taverns: [ids]}], members in world.json order"""
    locs = {l["id"]: l for l in world.get("locations", [])}
    near = {lid: set() for lid in locs}
    for r in world.get("routes", []):
        a, b = r.get("a"), r.get("b")
        if a in near and b in near and int(r.get("minutes", 0)) <= JOIN_MINUTES:
            near[a].add(b)
            near[b].add(a)
    seen, out = set(), []
    for lid, loc in locs.items():
        size = loc.get("settlement")
        if size not in SIZES or lid in seen:
            continue
        group, todo = [], [lid]
        seen.add(lid)
        while todo:
            cur = todo.pop()
            group.append(cur)
            for nxt in near[cur]:
                if nxt not in seen and locs[nxt].get("settlement") == size:
                    seen.add(nxt)
                    todo.append(nxt)
        members = [m for m in locs if m in group]
        joined = set(members)
        for m in members:
            joined |= near[m]
        taverns = [t for t in locs if t in joined and isinstance(locs[t].get("tavern"), dict)]
        areas = [locs[m].get("area", m) for m in members]
        out.append({"size": size, "members": members, "taverns": taverns,
                    "name": max(areas, key=areas.count)})  # the commonest area names it
    return out


def validate(ctx):
    world, err, warn = ctx["world"], ctx["err"], ctx["warn"]
    where = "world.json settlements"
    for loc in world.get("locations", []):
        if "settlement" in loc and loc["settlement"] not in SIZES:
            err(where, "%s: settlement '%s' is not village, town or city" % (loc.get("id"), loc["settlement"]))
    for s in settlements(world):
        need = SIZES[s["size"]]
        have = len(s["taverns"])
        if have < need:
            err(where, "%s (%s): %d tavern(s), needs at least %d (members: %s)" % (s["name"], s["size"], have, need, ", ".join(s["members"])))
    generics = _generic_ids(ctx["root"])
    for loc in world.get("locations", []):
        keeper = str((loc.get("tavern") or {}).get("keeper", "")) if isinstance(loc.get("tavern"), dict) else ""
        if keeper.startswith("gen_") and keeper not in generics:
            err(where, "%s: tavern keeper '%s' is not a generic population.json creates" % (loc.get("id"), keeper))
