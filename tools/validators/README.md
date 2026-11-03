# Validator plugins

One module per player system (docs/PLAYER_SYSTEMS.md §8): `tools/validators/<system>.py` with
`validate(ctx)`. `tools/validate_world.py` runs every module here after the world's own checks.

ctx keys: `root` (Path), `world` (world.json dict), `souls`, `flags_known` (set), `npc_keys`,
`locations` (set), `event_kinds` (set), `forbidden` (concepts), `err(where, msg)`, `warn(where, msg)`.
Files starting with `_` are skipped. Stdlib only.
