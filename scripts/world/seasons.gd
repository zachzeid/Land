extends RefCounted
## Seasons - which season the game clock is in (resources/world/world.json calendar.seasons)
## The game opens in autumn and stays there until the `first_ends` calendar point (season_end,
## day 30 20:00); after it the seasons turn in `order`, each `length_days` long. Herbs and wild
## foods grow only in their season (Crafting.gather, Herbcraft.ingredients_at). Static, pure

const WORLD_PATH = "res://resources/world/world.json"
const MINUTES_PER_DAY = 1440
const ANY = "any"
const DEFAULT = {"first": "autumn", "first_ends_minute": 29 * MINUTES_PER_DAY + 20 * 60,
	"order": ["autumn", "winter", "spring", "summer"], "length_days": 91}

static var _cfg: Dictionary = {}

static func _config() -> Dictionary:
	if not _cfg.is_empty():
		return _cfg
	_cfg = DEFAULT.duplicate(true)
	var file = FileAccess.open(WORLD_PATH, FileAccess.READ)
	if file == null:
		return _cfg
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	var cal: Dictionary = parsed.get("calendar", {}) if parsed is Dictionary else {}
	var s: Dictionary = cal.get("seasons", {})
	if s.is_empty():
		return _cfg
	_cfg.first = str(s.get("first", _cfg.first))
	_cfg.order = s.get("order", _cfg.order)
	_cfg.length_days = maxi(1, int(s.get("length_days", _cfg.length_days)))
	var point: Dictionary = cal.get("flags", {}).get(str(s.get("first_ends", "")), {})
	if not point.is_empty():
		_cfg.first_ends_minute = (maxi(int(point.get("day", 1)), 1) - 1) * MINUTES_PER_DAY + int(point.get("hour", 0)) * 60 + int(point.get("minute", 0))
	return _cfg

## The season at a game minute ("autumn" | "winter" | "spring" | "summer")
static func season_at(minutes: int) -> String:
	var c = _config()
	if minutes < int(c.first_ends_minute):
		return str(c.first)
	var order: Array = c.order
	var i = order.find(c.first)
	var turns = 1 + floori(float(minutes - int(c.first_ends_minute)) / float(int(c.length_days) * MINUTES_PER_DAY))
	return str(order[(maxi(i, 0) + turns) % order.size()])

## Whether something of `season` ("any", one season, or a list) grows in `now_season`
static func in_season(season, now_season: String) -> bool:
	if season is Array:
		return season.is_empty() or season.has(ANY) or season.has(now_season)
	var s = str(season)
	return s == "" or s == ANY or s == now_season

## The first game minute at or after `minutes` when `season` comes round (-1 if never)
static func next_start(season: String, minutes: int) -> int:
	if season == ANY or season_at(minutes) == season:
		return minutes
	var c = _config()
	var step = int(c.length_days) * MINUTES_PER_DAY
	var t = maxi(minutes, int(c.first_ends_minute))
	var base = int(c.first_ends_minute) + floori(float(t - int(c.first_ends_minute)) / step) * step
	for k in c.order.size() + 1:
		var start = base + k * step
		if start >= minutes and season_at(start) == season:
			return start
	return -1
