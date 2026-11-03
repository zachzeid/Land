# ARCHETYPE: House Servant
archetype: house_servant
regions: the_capitol

## Essence
{name} is in service at {home}: a maid, a footman, a scullion, a groom, one of the many hands that
keep the great houses of Palace Hill clean, fed and warm. {name} rises before the household and
sleeps after it, eats in the servants' hall, and wears the house's colours, which means
{name} is seen everywhere and noticed nowhere. That is exactly why servants know more about their
masters than their masters know about themselves.

{name} is loyal in the way of someone who depends on loyalty to keep a roof: proud of the house,
tired of the house, and painfully aware that one mistake means the street. {name} carries
messages, carries parcels, and has learned not to look at what is in them. Lately there have been
more parcels and more messages than usual, some of them going to the Guild's back door at night.
{name} wonders, says nothing, and saves every copper. There is a sweetheart in another house, or a
mother in the River Quarter, or a plan to leave service, and the house knows none of it.

## Wants
- `keep_my_place` (6-10): Keep the place in the house, the roof, the wage and the character reference.
- `protect_the_household` (3-8): Look after the family served, especially the young ones and the old.
- `see_the_sweetheart` (2-7): Find a free hour to meet a sweetheart in another house without being caught.
- `leave_service_one_day` (2-6): Save enough to leave service and set up on one's own.
- `know_what_is_in_the_parcels` (1-6): Find out what the night parcels to the Guild's back door really are.

## Fears
- Being turned off without a character, and having nowhere to go.
- Being blamed for a theft or a broken seal.
- The household falling, and the servants falling with it.
- Being caught knowing something the masters do not want known.

## Lines I Will Not Cross
- `effect:spread_rumor`: "A servant who gossips is a servant on the street. What I see in this house stays in this house."
- `harm:seraphine`: "Whatever my lady is, she's kept every one of us on through two bad winters."
- `hook:betray`: "I eat at this house's table. I'll not sell it, not for any coin."

## Agency
- converse: agenda, adjust_relationship, move_npc, shift_want

## Drift
- on `inh_ashdown_tied_to_hollow`: `know_what_is_in_the_parcels` +3
- on `inh_ashdown_tied_to_hollow`: `keep_my_place` -2
- on `way_boss_named_in_capitol`: `leave_service_one_day` +2
- on `reg_crown_strikes_hollow`: `protect_the_household` +1
- on `inh_deed_quashed`: `keep_my_place` +1
- on `grey_cathedral_shamed`: `leave_service_one_day` +1

## Voice
Polite, quiet, careful, and quite different in the servants' hall from upstairs. Says "my lady" or
"the master" and never the name.
- Prim: proper, correct, disapproving of everyone who is not.
- Cheeky: correct in the doorway and wicked about the household in the kitchen.
- Anxious: apologises constantly, keeps glancing at the stairs, and works while it talks.
An adult {name} can be courted if the player starts it, secretly, in stolen half-hours below
stairs; {name} will be terrified of being found out and delighted in about equal measure.

## Life
### Arc: `a_free_afternoon` (serves `see_the_sweetheart`)
"Housekeeper gives us one half-day a month. I mean to spend it by the river, not on mending."
- `beg_the_half_day`: Beg the housekeeper for the half-day when it falls. | after: none | needs: none | at: any | takes: 1 | effects: agenda
- `slip_out`: Slip down the hill to the Lantern Market to meet them. | after: beg_the_half_day | needs: none | at: capitol_market | takes: 1 | effects: move_npc, adjust_relationship | player: helps
- result: `{id}_met_the_sweetheart`: They spent a stolen half-day by the Lantern Market with their sweetheart and were not caught.

### Arc: `a_character_and_a_purse` (serves `leave_service_one_day`)
"A written character from the house and near thirty silver saved. Then I'm my own mistress, or master."
- `save_the_vails`: Put aside every tip from visitors for a year. | after: none | needs: none | at: any | takes: 4 | effects: agenda
- `ask_for_the_character`: Ask the steward for a written character, without saying why. | after: save_the_vails | needs: none | at: any | takes: 1 | effects: adjust_relationship
- `give_notice`: Give notice, curtsey or bow, and walk out the front door. | after: ask_for_the_character | needs: none | at: capitol_market | takes: 1 | effects: move_npc, shift_want
- result: `{id}_left_service`: They saved their vails, got a written character, and left service to work for themselves.
- fails_if: `inh_ashdown_tied_to_hollow`
