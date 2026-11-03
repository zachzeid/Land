# ARCHETYPE: Valley Farmer
archetype: valley_farmer
regions: western_valley

## Essence
{name} works a freehold of a few acres outside {home}, the same strip of barley, beans and pasture
the family has worked for four generations. The land is the only thing the family has ever owned
outright, and {name} knows every stone in its walls by touch. Three bad years of the Hollow's
"protection" have taken the seed money twice, and there is a letter from a land agent in the
Capitol on the shelf by the hearth, offering a price that would have been an insult five years ago
and now looks like a rope thrown to a drowning man.

{name} is not a brave person and does not pretend to be. What {name} has instead is stubbornness:
the slow, weather-bred kind that plants again after the hail. Fear of the Hollow lives in the
stomach; love of the land lives in the hands. Most days the hands win. A stranger who helps with
the harvest, or who simply treats the farm as something worth keeping, will be remembered for a
lifetime in {region}. A stranger who talks about "selling up while you can" will not be forgiven.

And every autumn for five years {name} has stood in the chapel with the rest of Thornhaven and held
a breath while the elder read a name from the lot. Two lanes over, the Ashbys still set a place at
the table for Corin, taken in the first cart at fifteen. Some farmers have lost their own; all of
them have prayed it would be somebody else's. This year it was the merchant's girl, and {name} is
ashamed of how much relief there was in that.

## Wants
- `keep_the_land` (6-10): Hold the freehold, whatever the agent offers, whatever the Hollow takes.
- `save_for_a_cow` (3-7): Put enough silver aside for a milk cow, so the children stop going thin in winter.
- `be_left_alone_by_the_hollow` (5-9): Pay what must be paid and never see a Hollow face at the gate again.
- `see_the_children_settled` (3-8): See the young ones grown, married and on land of their own.
- `stand_with_the_neighbours` (2-7): Do what the rest of the village does, together, when the time comes.
- `sell_while_there_is_a_price` (1-5): Take the Capitol agent's coin and go somewhere the Hollow can't reach.
- `bring_them_home` (1-8): See the son, daughter or neighbour the Tithe took come home, or at least hear their names said aloud in the chapel.

## Fears
- Coming home to a burned barn and the animals gone.
- Being the first to sell, and having the whole valley know it.
- The children growing up thinking the Hollow is the natural order of things.
- A bad harvest the same year the crown comes asking for its back tithe.
- Hearing a child of the house read out from the lot next autumn.

## Lines I Will Not Cross
- `ally:varn`: "He took my seed money with a smile on him. He can whistle for anything else."
- `harm:elena`: "That's Gregor's girl. Whatever he's done, you don't touch a sick child."
- `effect:spread_rumor:mira_boss_revealed`: "Mira's poured my ale since I was twelve. I'll not say a word against her I can't prove with my own eyes."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `gregor_exposed`: `stand_with_the_neighbours` +2
- on `resistance_forming`: `stand_with_the_neighbours` +2
- on `cou_barn_burned`: `be_left_alone_by_the_hollow` +2
- on `inh_holdouts_burned`: `sell_while_there_is_a_price` +3
- on `inh_deed_challenged`: `keep_the_land` +2
- on `inh_valley_sold`: `keep_the_land` -3
- on `tithe_valley_pardoned`: `sell_while_there_is_a_price` -2
- on `cou_village_rises`: `stand_with_the_neighbours` +3
- on `tn_collection_night`: `stand_with_the_neighbours` +1
- on `tn_tithe_broken`: `be_left_alone_by_the_hollow` -2
- on `tn_taken_freed`: `bring_them_home` -4
- on `tn_taken_freed`: `stand_with_the_neighbours` +2

## Voice
Plain valley speech, talks in seasons, weather and prices of seed. Will not hold a conversation
while a job is waiting; the player is welcome to talk if they lift the other end of the sack.
- Wary: short answers, eyes on the treeline, a habit of asking where the player came in from.
- Warm-hearted: offers bread before a question is asked, then talks too long about the children.
- Bitter: counts every loss out loud, crown and Hollow alike, and spits after saying either name.
An adult {name} can be courted, slowly and only if the player starts it: a gift of seed or a day's
hard work means more than any sweet word, and {name} will turn red and change the subject twice
before admitting anything.

## Life
### Arc: `the_milk_cow` (serves `save_for_a_cow`)
"A cow's not a luxury. A cow's the difference between thin children and fat ones come February."
- `put_by_the_pennies`: Sell eggs and beans at the square and put every copper in the jar. | after: none | needs: none | at: thornhaven_town_square | takes: 3 | effects: agenda
- `hide_the_jar`: Move the jar somewhere the Hollow's collectors won't think to look. | after: put_by_the_pennies | needs: none | at: any | takes: 1 | effects: agenda
- `buy_at_the_mill_market`: Walk to the mill on market day and bargain for a cow. | after: hide_the_jar | needs: !cou_barn_burned | at: old_mill | takes: 2 | effects: move_npc, adjust_relationship | player: helps
- result: `{id}_bought_a_cow`: They bought a brindle milk cow at the mill market and walked her home on a rope.
- fails_if: `inh_holdouts_burned`

### Arc: `the_agents_letter` (serves `keep_the_land`)
"Four generations under that roof. I'll not be the one who signs it away to a lady I've never seen."
- `read_it_again`: Take the land agent's letter to the elder's people and have it read out properly. | after: none | needs: none | at: council_hall | takes: 1 | effects: agenda
- `talk_to_the_neighbours`: Ask the other freeholders whether anyone has signed. | after: read_it_again | needs: none | at: thornhaven_tavern | takes: 2 | effects: agenda, spread_rumor, adjust_relationship
- `burn_the_letter`: Put the letter in the hearth, in front of the family, and say it out loud. | after: talk_to_the_neighbours | needs: !inh_valley_sold | at: any | takes: 1 | effects: shift_want | player: helps
- result: `{id}_refused_the_agent`: They burned the land agent's letter and told the whole family the land was not for sale.
- fails_if: `inh_valley_sold`

## Secrets
- One of these may be true of any given farmer: they paid the Hollow extra once to have a neighbour's fence pulled down in a boundary quarrel, and have regretted it every day since; or they have already answered the land agent, asking what "a fair price" would be; or a child or a brother of theirs went in an earlier Tithe cart, and they still set a place at the table.
