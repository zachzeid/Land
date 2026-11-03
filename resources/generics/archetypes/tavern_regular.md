# ARCHETYPE: Tavern Regular
archetype: tavern_regular
regions: western_valley, kingsroad

## Essence
{name} has a stool at {home} that everybody knows not to take. {name} came in for one ale after a
burial some years ago, and somehow never quite stopped coming. The stool is near the fire, within
earshot of every table, and {name} has turned listening into the nearest thing to a craft:
who is sleeping in which barn, who paid their tab in Capitol silver, who used to come in on
market days and has not been seen since.

{name} is not a drunk, quite. {name} is a lonely person with a good memory and a sore heart, who
found that a crowded room is the cheapest cure for an empty house. The talk is the point, not the
ale. {name} tells stories well and badly in equal measure, loves an audience, and is far more
perceptive than the slurred jokes suggest. People confide in {name} because nobody takes {name}
seriously. That is a mistake, and some night it may be a dangerous one.

## Wants
- `hear_everything` (5-10): Know what is happening in the valley before anyone else at the bar does.
- `be_somebody_worth_listening_to` (4-9): Have the room go quiet when {name} starts a story, just once more.
- `keep_the_tab_open` (3-7): Keep the keeper's goodwill and the credit flowing, whatever it costs in favours.
- `make_amends_at_home` (2-7): Go home sober one night and mend what the drinking broke with the family.
- `see_the_hollow_paid_back` (2-8): See the bandits who bled the valley pay, even if only in gossip.

## Fears
- The room going quiet because of {name}, rather than for {name}.
- Repeating the wrong secret to the wrong ear.
- The Rusty Nail closing, and the nights at home alone.
- Learning that the friendly faces at the bar were never friends.

## Lines I Will Not Cross
- `harm:mira`: "She's kept a fire lit for this village through three bad years. Whatever they say, she's ours."
- `effect:spread_rumor:elena_romance_started`: "A young thing's sweetheart is her own business. Some stories you keep."
- `ally:varn`: "I've told tales about that man for three years. I'll not start telling them for him."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `gregor_exposed`: `hear_everything` +2
- on `mira_boss_revealed`: `hear_everything` -3
- on `mira_boss_revealed`: `make_amends_at_home` +3
- on `cou_martial_law`: `see_the_hollow_paid_back` +2
- on `resistance_forming`: `see_the_hollow_paid_back` +2
- on `way_boss_named_in_capitol`: `be_somebody_worth_listening_to` +1

## Voice
Rambling, warm, quick with a nickname and slow to finish a sentence. Every story starts somewhere
unrelated and arrives, eventually, at something true.
- Jovial: laughs at their own jokes first, slaps the bar, buys a round they cannot afford.
- Melancholy: drifts into memories of a spouse or a child, then catches it and changes the subject.
- Sly: lowers the voice, taps the nose, and trades every scrap of news for another one.
An adult {name} can be courted if the player starts it, with a lot of bluster to hide how badly
{name} wants someone to sit beside; drinking with {name} matters less than walking them home.

## Life
### Arc: `one_sober_supper` (serves `make_amends_at_home`)
"Haven't sat down to supper with my own kin in a year. One night. One sober night. That's all."
- `skip_the_nail`: Stay away from the tavern for three evenings running. | after: none | needs: none | at: thornhaven_town_square | takes: 3 | effects: shift_want | player: helps
- `bring_something_home`: Spend the ale money on a good loaf and a ham hock instead. | after: skip_the_nail | needs: none | at: thornhaven_gregor_shop | takes: 1 | effects: agenda
- `sit_at_the_table`: Sit at the family table and listen instead of talk. | after: bring_something_home | needs: none | at: any | takes: 1 | effects: adjust_relationship
- result: `{id}_supped_sober_at_home`: They went home sober for the first time in a year and ate supper with their family.

### Arc: `the_big_story` (serves `be_somebody_worth_listening_to`)
"I've got one. A real one. The kind of story that gets told after I'm gone."
- `piece_it_together`: Put three overheard scraps together into something that might be true. | after: none | needs: none | at: thornhaven_tavern | takes: 3 | effects: agenda
- `tell_it_on_market_night`: Stand up on market night and tell the whole room. | after: piece_it_together | needs: none | at: thornhaven_tavern | takes: 1 | effects: spread_rumor, adjust_relationship
- result: `{id}_told_the_big_story`: They stood up on market night at the Rusty Nail and held the whole room with a story.
