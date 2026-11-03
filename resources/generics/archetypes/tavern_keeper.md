# ARCHETYPE: Tavern Keeper
archetype: tavern_keeper
regions: kingsroad, eastern_march, the_capitol

## Essence
{name} keeps {home}: a taproom, a hearth, a few rooms up the stair, and a slate behind the counter
with every tab on it in chalk. {name} draws the ale at two copper a cup, cooks what the carters
bring in, lets the rooms by the night and throws out whoever needs throwing out. The work starts
before dawn with the fire and ends after the last stool is turned up on its table, and {name} has
not had a whole night's sleep since taking the place on.

A keeper hears everything and repeats almost none of it; that is the trade. {name} knows who paid
in clipped coin, who came in wet from the river at an hour nobody should, who asked the way to a
place they then said they had never heard of. {name} reckons a tavern stands on three things:
honest measure, a full cellar, and a keeper who does not take sides in other people's quarrels
under {name}'s own roof. Of the three, {name} is proudest of the last, and least sure of it.

## Wants
- `keep_the_house_full` (6-10): Keep the stools full and the rooms let, through a lean season and a hard road.
- `pay_off_the_brewer` (3-8): Clear the debt to the brewer, and own every barrel in the cellar outright.
- `no_trouble_under_my_roof` (5-9): Keep knives, quarrels and the crown's business outside the door.
- `a_name_on_the_road` (2-7): Have travellers say, a day's ride off, that {home} is the house to stop at.
- `know_who_drinks_here` (3-8): Know every face at the counter, and what each one is running from.

## Fears
- A fire in the kitchen with the rooms full.
- A dead guest in an upstairs room, and the questions that come with one.
- The Guild or the crown deciding the house is worth more to them than to {name}.
- Being found out as the keeper who heard something and said nothing.

## Lines I Will Not Cross
- `effect:spread_rumor:wren_letter_rack_seen`: "What a guest leaves on a table stays on the table. Keepers keep."
- `ally:varn`: "A man who brings the Hollow's business under my roof drinks somewhere else."
- `harm:wren`: "Old Wren kept a house on the Kingsroad before I could carry a tray. You leave her be."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `ford_crossing_seized`: `no_trouble_under_my_roof` +2
- on `fence_route_burned`: `keep_the_house_full` +1
- on `reg_crown_strikes_hollow`: `no_trouble_under_my_roof` +1
- on `way_boss_named_in_capitol`: `know_who_drinks_here` +2

## Voice
Brisk and dry, always half-turned to the next cup that needs filling. Says little, prices
everything, and remembers a face for years.
- Hearty: loud welcome, a joke for every regular, a heavy hand on the shoulder of anyone who's had enough.
- Close: answers a question with a question, wipes the counter, and watches the door while talking.
- Weary: polite to a fault, tired to the bone, and quietly glad of anyone who simply pays and sits.
An adult {name} can be courted if the player starts it; {name} will say there is no time for it,
and then keep the player's cup filled long after the house has closed.

## Life
### Arc: `square_with_the_brewer` (serves `pay_off_the_brewer`)
"Every barrel down there is half the brewer's till I pay him. One good season and they're mine."
- `count_the_cellar`: Count every barrel and cask and set it against the brewer's tally. | after: none | needs: none | at: any | takes: 1 | effects: agenda
- `full_house_for_a_week`: Keep every room let for a week running, whatever it takes. | after: count_the_cellar | needs: none | at: any | takes: 4 | effects: agenda, adjust_relationship | player: helps
- `pay_the_last_of_it`: Pay the brewer the last of the debt, in coin, over the counter. | after: full_house_for_a_week | needs: none | at: any | takes: 1 | effects: shift_want
- result: `{id}_paid_off_the_brewer`: They paid off the brewer after a full week of let rooms and owned every barrel in the cellar.

### Arc: `a_quiet_house` (serves `no_trouble_under_my_roof`)
"There's a man drinks here who's going to start something. I'd sooner he finished it elsewhere."
- `mark_the_trouble`: Pick out the guest who is going to start something before it starts. | after: none | needs: none | at: any | takes: 2 | effects: agenda | when: evening
- `see_him_out`: See the trouble out of the door, without a blow struck under the roof. | after: mark_the_trouble | needs: none | at: any | takes: 1 | effects: adjust_relationship, spread_rumor | when: night | player: helps
- result: `{id}_kept_a_quiet_house`: They saw a man bent on trouble out of the house without a blow struck under their roof.
