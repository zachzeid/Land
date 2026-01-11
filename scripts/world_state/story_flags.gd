class_name StoryFlags
extends RefCounted
## Story flag constants for tracking narrative progression
## Use these with WorldState.set_world_flag() and WorldState.get_world_flag()

# =============================================================================
# FLAG DESCRIPTIONS (for NPC context - what does this flag MEAN to NPCs)
# =============================================================================

## Get a description of what a flag means for NPC context
## Returns empty string if flag not recognized
static func get_flag_description(flag_name: String) -> String:
	return FLAG_DESCRIPTIONS.get(flag_name, "")

## Get description for the NPC who is IMPLICATED by this flag
## (e.g., Gregor should react differently than Elena to ledger_found)
static func get_implicated_npc_description(flag_name: String, npc_id: String) -> String:
	var implicated = IMPLICATED_NPCS.get(flag_name, "")
	if implicated != "" and npc_id.to_lower().contains(implicated.to_lower()):
		return IMPLICATED_DESCRIPTIONS.get(flag_name, "")
	return ""

const FLAG_DESCRIPTIONS = {
	"ledger_found": "The player discovered a hidden ledger with suspicious records of payments to bandits",
	"weapons_traced_to_bjorn": "The player has connected bandit weapons to Bjorn's smithy",
	"gregor_bandit_meeting_known": "The player knows Gregor secretly meets with bandits",
	"marcus_death_learned": "The player learned about Marcus's execution",
	"varn_killed_marcus_known": "The player knows Varn was the one who killed Marcus",
	"gregor_confession_heard": "Gregor confessed his deal with the bandits to the player",
	"gregor_gold_secret_revealed": "Gregor revealed the gold was meant to save Elena from illness",
	"mira_testimony_given": "Mira shared what she witnessed about the conspiracy",
	"bjorn_truth_revealed": "Bjorn learned his weapons have been going to bandits",
	"elena_knows_about_father": "Elena was told about her father's crimes",
	"elena_shown_proof": "Elena was shown proof of Gregor's involvement with bandits",
	"aldric_has_evidence": "Captain Aldric has been given evidence against Gregor",
	"mathias_informed": "Elder Mathias knows about the conspiracy",
	"bjorn_knows_about_weapons": "Bjorn knows where his weapons have been going",
	"elena_romance_started": "A romantic relationship has begun with Elena",
	"aldric_ally": "Aldric considers the player a trusted ally",
	"mira_trusts_player": "Mira has come to trust the player",
	"bjorn_allied": "Bjorn has pledged to help against the conspiracy",
	"gregor_confronted": "The player has directly confronted Gregor about his crimes",
	"varn_confronted": "The player has confronted Varn",
	"iron_hollow_visited": "The player has been to Iron Hollow",
	"gregor_exposed": "Gregor's crimes have been made public",
	"gregor_redemption_path": "Gregor is attempting to make amends",
	"mira_boss_revealed": "The player discovered Mira is 'The Boss'",
	"resistance_forming": "A resistance movement is organizing"
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
	"ledger_found": "⚠️ THE PLAYER FOUND YOUR SECRET LEDGER. They have evidence of your payments to bandits. You are in serious danger of exposure. React with fear, denial, or desperate bargaining depending on trust level.",
	"gregor_bandit_meeting_known": "⚠️ THE PLAYER KNOWS you meet with bandits. Your secret is partially exposed.",
	"gregor_confession_heard": "You have confessed to the player. They know everything about your deal with the bandits.",
	"gregor_gold_secret_revealed": "The player knows the gold was to save Elena. They understand your desperate motivation.",
	"weapons_traced_to_bjorn": "⚠️ THE PLAYER connected YOUR weapons to the bandits. You may not have known, but you're implicated.",
	"bjorn_truth_revealed": "You now know your weapons have been arming bandits. This revelation shattered you.",
	"elena_knows_about_father": "You have learned the terrible truth about your father's crimes.",
	"elena_shown_proof": "You were shown undeniable proof of your father's guilt.",
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
