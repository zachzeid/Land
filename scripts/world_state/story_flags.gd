class_name StoryFlags
extends RefCounted
## Story flag constants for tracking narrative progression
## Use these with WorldState.set_world_flag() and WorldState.get_world_flag()

# =============================================================================
# FLAG DESCRIPTIONS (for NPC context - what does this flag MEAN to NPCs)
# =============================================================================

## Get a description of what a flag means for NPC context
## Falls back to flags declared by storylines (StorylineDirector registers them)
## Returns empty string if flag not recognized
static func get_flag_description(flag_name: String) -> String:
	if FLAG_DESCRIPTIONS.has(flag_name):
		return FLAG_DESCRIPTIONS[flag_name]
	if _calendar_descriptions.has(flag_name):
		return _calendar_descriptions[flag_name]
	return _discovery_descriptions.get(flag_name, _registered_descriptions.get(flag_name, ""))

## Calendar fixed points (world.json "calendar.flags": flag -> description). The world sets them when
## the game clock reaches them (WorldState). Base flags: storylines may require them; no effect sets them
static var _calendar_descriptions: Dictionary = {}

static func register_calendar_flags(descriptions: Dictionary) -> void:
	_calendar_descriptions.clear()
	for flag_name in descriptions:
		_calendar_descriptions[str(flag_name)] = str(descriptions[flag_name])

static func is_calendar_flag(flag_name: String) -> bool:
	return _calendar_descriptions.has(flag_name)

static func get_calendar_flags() -> Array:
	return _calendar_descriptions.keys()

## Discovery flags (world.json "discovery_flags": flag -> canonical text). StoryItems set them; they
## are base flags at runtime: any effect may name them and witnesses see them. WorldRegistry registers them
static var _discovery_descriptions: Dictionary = {}

static func register_discovery_flags(descriptions: Dictionary) -> void:
	_discovery_descriptions.clear()
	for flag_name in descriptions:
		_discovery_descriptions[str(flag_name)] = str(descriptions[flag_name])

static func is_discovery_flag(flag_name: String) -> bool:
	return _discovery_descriptions.has(flag_name)

## Base flags: the built-in FLAG_DESCRIPTIONS plus world.json discovery and calendar flags
## (storyline flags are not base)
static func is_base_flag(flag_name: String) -> bool:
	return FLAG_DESCRIPTIONS.has(flag_name) or _discovery_descriptions.has(flag_name) or _calendar_descriptions.has(flag_name)

static func get_discovery_flags() -> Array:
	return _discovery_descriptions.keys()

## Storyline-declared flag -> canonical description (resources/storylines/*.json "flags")
static var _registered_descriptions: Dictionary = {}

static func register_flag_descriptions(descriptions: Dictionary) -> void:
	for flag_name in descriptions:
		_registered_descriptions[flag_name] = str(descriptions[flag_name])

static func clear_registered_flag_descriptions() -> void:
	_registered_descriptions.clear()

## Get description for the NPC who is IMPLICATED by this flag
## (e.g., Gregor should react differently than Elena to ledger_found)
static func get_implicated_npc_description(flag_name: String, npc_id: String) -> String:
	var implicated = IMPLICATED_NPCS.get(flag_name, "")
	if implicated != "" and npc_id.to_lower().contains(implicated.to_lower()):
		return IMPLICATED_DESCRIPTIONS.get(flag_name, "")
	return ""

const FLAG_DESCRIPTIONS = {
	"ledger_found": "The player found Gregor's hidden ledger: five years of rigged Tithe draws, each year's palmed tile and the neighbour's name it fell to, beside his deliveries to the Hollow",
	"weapons_traced_to_bjorn": "The player has connected bandit weapons to Bjorn's smithy",
	"bulk_orders_found": "The player read Bjorn's order book and saw Gregor buys far more weapons than his shop could sell",
	"gregor_bandit_meeting_known": "The player knows Gregor meets the Hollow's runner in secret at the old mill",
	"marcus_death_learned": "The player learned that Marcus did not die at random: he followed a Tithe cart and was killed for it",
	"varn_killed_marcus_known": "The player knows Varn was the one who killed Marcus",
	"gregor_confession_heard": "Gregor confessed that he rigged the Tithe lot for five years so that Elena's name never came up",
	"gregor_gold_secret_revealed": "Gregor revealed he made the deal for the Hollow's white salt, the only thing that keeps Elena's Grey Fever down",
	"mira_testimony_given": "Mira told the player what she claims to have seen of the Hollow's runners and the Tithe carts",
	"bjorn_truth_revealed": "Bjorn learned that his steel arms the Hollow and that the lot tiles he cast were rigged against his neighbours",
	"elena_knows_about_father": "Elena admitted she has known for months that her father rigged the Tithe lot",
	"elena_shown_proof": "Elena was shown the ledger of her father's rigged draws",
	"aldric_has_evidence": "Captain Aldric has been given proof of how the Tithe really works",
	"mathias_informed": "Elder Mathias was told that the lot he blesses every year has been rigged",
	"bjorn_knows_about_weapons": "Bjorn knows where his weapons have been going",
	"elena_romance_started": "A romantic relationship has begun with Elena",
	"aldric_ally": "Aldric considers the player a trusted ally",
	"mira_trusts_player": "Mira has come to trust the player",
	"bjorn_allied": "Bjorn has pledged his forge and his hands for Collection Night",
	"gregor_confronted": "The player confronted Gregor about the rigged lot",
	"varn_confronted": "The player has confronted Varn",
	"iron_hollow_visited": "The player has been to Iron Hollow",
	"gregor_exposed": "Thornhaven learned that Gregor rigged the Tithe lot and sent his neighbours' children to the Hollow",
	"gregor_redemption_path": "Gregor is trying to undo what the rigged lot cost his neighbours",
	"mira_boss_revealed": "The player discovered Mira is 'The Boss'",
	"resistance_forming": "Villagers are gathering in secret to refuse the Tithe"
}

## Which NPC is implicated/affected most by each flag
const IMPLICATED_NPCS = {
	"ledger_found": "gregor",
	"gregor_bandit_meeting_known": "gregor",
	"gregor_confession_heard": "gregor",
	"gregor_gold_secret_revealed": "gregor",
	"gregor_confronted": "gregor",
	"gregor_exposed": "gregor",
	"gregor_redemption_path": "gregor",
	"weapons_traced_to_bjorn": "bjorn",
	"bulk_orders_found": "gregor",
	"bjorn_truth_revealed": "bjorn",
	"bjorn_knows_about_weapons": "bjorn",
	"bjorn_allied": "bjorn",
	"elena_knows_about_father": "elena",
	"elena_shown_proof": "elena",
	"elena_romance_started": "elena",
	"varn_killed_marcus_known": "varn",
	"varn_confronted": "varn",
	"mira_testimony_given": "mira",
	"mira_trusts_player": "mira",
	"mira_boss_revealed": "mira",
	"aldric_has_evidence": "aldric",
	"aldric_ally": "aldric",
	"mathias_informed": "mathias"
}

## Special descriptions for the NPC who is directly implicated
const IMPLICATED_DESCRIPTIONS = {
	"ledger_found": "⚠️ THE PLAYER FOUND YOUR LEDGER OF RIGGED DRAWS. Five years of names. You are one word from the whole village knowing. React with terror, denial, or desperate bargaining depending on trust.",
	"gregor_bandit_meeting_known": "⚠️ THE PLAYER KNOWS you meet with bandits. Your secret is partially exposed.",
	"gregor_confession_heard": "You have confessed the rigged lot to the player. They know whose children went in Elena's place.",
	"gregor_gold_secret_revealed": "The player knows you did it for the white salt that keeps Elena alive.",
	"bulk_orders_found": "⚠️ THE PLAYER has seen Bjorn's order book. Your bulk weapon orders are on record. Deflect with a plausible excuse, or grow nervous if pressed.",
	"weapons_traced_to_bjorn": "⚠️ THE PLAYER connected YOUR weapons to the bandits. You may not have known, but you're implicated.",
	"bjorn_truth_revealed": "You now know your steel arms the Hollow and your own lot tiles were rigged. Davin went because of it.",
	"elena_knows_about_father": "You have admitted knowing your father rigged the lot. Now someone else carries it too.",
	"elena_shown_proof": "You were shown the ledger in your father's hand: every name that went instead of you.",
	"varn_killed_marcus_known": "⚠️ THE PLAYER KNOWS you killed Marcus. Your darkest secret is exposed.",
	"mira_boss_revealed": "⚠️ THE PLAYER discovered you are 'The Boss'. Your secret identity is known."
}

# =============================================================================
# DISCOVERY FLAGS - Information the player has learned
# =============================================================================

## Player found Gregor's secret ledger
const LEDGER_FOUND = "ledger_found"

## Player discovered weapons come from Bjorn's smithy
const WEAPONS_TRACED_TO_BJORN = "weapons_traced_to_bjorn"

## Player read Bjorn's order book showing Gregor's bulk weapon orders
const BULK_ORDERS_FOUND = "bulk_orders_found"

## Player discovered Gregor meets with bandits
const GREGOR_BANDIT_MEETING_KNOWN = "gregor_bandit_meeting_known"

## Player learned about Marcus's execution
const MARCUS_DEATH_LEARNED = "marcus_death_learned"

## Player discovered Varn is the enforcer who killed Marcus
const VARN_KILLED_MARCUS_KNOWN = "varn_killed_marcus_known"

# =============================================================================
# CONFESSION FLAGS - NPCs have confessed to the player
# =============================================================================

## Gregor confessed his deal with bandits
const GREGOR_CONFESSION_HEARD = "gregor_confession_heard"

## Gregor confessed about the gold for Elena
const GREGOR_GOLD_SECRET_REVEALED = "gregor_gold_secret_revealed"

## Mira confessed what she witnessed
const MIRA_TESTIMONY_GIVEN = "mira_testimony_given"

## Bjorn learned he's been arming bandits
const BJORN_TRUTH_REVEALED = "bjorn_truth_revealed"

# =============================================================================
# REVELATION FLAGS - Key information shared with NPCs
# =============================================================================

## Elena was told about her father's crimes
const ELENA_KNOWS_ABOUT_FATHER = "elena_knows_about_father"

## Elena was shown proof of Gregor's involvement
const ELENA_SHOWN_PROOF = "elena_shown_proof"

## Aldric was given evidence against Gregor
const ALDRIC_HAS_EVIDENCE = "aldric_has_evidence"

## Mathias was informed of the conspiracy
const MATHIAS_INFORMED = "mathias_informed"

## Bjorn was told about the weapons destination
const BJORN_KNOWS_ABOUT_WEAPONS = "bjorn_knows_about_weapons"

# =============================================================================
# RELATIONSHIP FLAGS - Character relationship milestones
# =============================================================================

## Romance started with Elena
const ELENA_ROMANCE_STARTED = "elena_romance_started"

## Aldric considers player a trusted ally
const ALDRIC_ALLY = "aldric_ally"

## Player has gained Mira's trust
const MIRA_TRUSTS_PLAYER = "mira_trusts_player"

## Bjorn pledged to help the resistance
const BJORN_ALLIED = "bjorn_allied"

# =============================================================================
# CONFRONTATION FLAGS - Major story confrontations
# =============================================================================

## Player confronted Gregor about his crimes
const GREGOR_CONFRONTED = "gregor_confronted"

## Player confronted Varn
const VARN_CONFRONTED = "varn_confronted"

## Player visited Iron Hollow
const IRON_HOLLOW_VISITED = "iron_hollow_visited"

# =============================================================================
# OUTCOME FLAGS - Story resolution states
# =============================================================================

## Gregor was exposed publicly
const GREGOR_EXPOSED = "gregor_exposed"

## Gregor was given a chance to make amends
const GREGOR_REDEMPTION_PATH = "gregor_redemption_path"

## The Boss's identity (Mira) was discovered
const MIRA_BOSS_REVEALED = "mira_boss_revealed"

## Resistance is organizing
const RESISTANCE_FORMING = "resistance_forming"

# =============================================================================
# HELPER: Get all defined flags (for debugging)
# =============================================================================

static func get_all_flags() -> Array[String]:
	return [
		LEDGER_FOUND,
		WEAPONS_TRACED_TO_BJORN,
		BULK_ORDERS_FOUND,
		GREGOR_BANDIT_MEETING_KNOWN,
		MARCUS_DEATH_LEARNED,
		VARN_KILLED_MARCUS_KNOWN,
		GREGOR_CONFESSION_HEARD,
		GREGOR_GOLD_SECRET_REVEALED,
		MIRA_TESTIMONY_GIVEN,
		BJORN_TRUTH_REVEALED,
		ELENA_KNOWS_ABOUT_FATHER,
		ELENA_SHOWN_PROOF,
		ALDRIC_HAS_EVIDENCE,
		MATHIAS_INFORMED,
		BJORN_KNOWS_ABOUT_WEAPONS,
		ELENA_ROMANCE_STARTED,
		ALDRIC_ALLY,
		MIRA_TRUSTS_PLAYER,
		BJORN_ALLIED,
		GREGOR_CONFRONTED,
		VARN_CONFRONTED,
		IRON_HOLLOW_VISITED,
		GREGOR_EXPOSED,
		GREGOR_REDEMPTION_PATH,
		MIRA_BOSS_REVEALED,
		RESISTANCE_FORMING
	]
