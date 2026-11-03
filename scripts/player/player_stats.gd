extends Node
## PlayerStats - health, stamina, poise, skills (use-based), level (derived), perks, difficulty, death
## docs/PLAYER_SYSTEMS.md. Phase 0 stub: the contract (signatures other systems call) and save hooks;
## the owning build agent fills in the rest. Deeds go through PlayerEvents.record, never NPC state

signal skill_raised(skill: String, level: float, milestone: int)
signal died(info: Dictionary)

var difficulty: String = "normal"   # "normal" | "hard", chosen at a new game (docs/PLAYER_SYSTEMS.md §2)

## Use a skill: gain = base_xp x difficulty x (1 - level/110). context: {witnessed_by, target, ...}
## Returns {gained, level, milestone}
func use_skill(skill: String, difficulty_factor: float = 1.0, context: Dictionary = {}) -> Dictionary:
	return {"gained": 0.0, "level": 0.0, "milestone": 0}

func get_skill(skill: String) -> float:
	return 0.0

func get_level() -> int:
	return 0

func get_health() -> float:
	return 100.0

func get_max_health() -> float:
	return 100.0

func get_stamina() -> float:
	return 100.0

func get_max_stamina() -> float:
	return 100.0

func heal(amount: float) -> void:
	pass

func has_perk(perk_id: String) -> bool:
	return false

func spend_stamina(amount: float) -> bool:
	return true

## Returns {health, staggered, dead}
func damage(amount: float, damage_type: String = "blunt", source: String = "") -> Dictionary:
	return {"health": 100.0, "staggered": false, "dead": false}

# =============================================================================
# SAVE / LOAD (WorldState "player_systems" block)
# =============================================================================

func save() -> Dictionary:
	return {}

func load_from_dict(_data: Dictionary) -> void:
	pass
