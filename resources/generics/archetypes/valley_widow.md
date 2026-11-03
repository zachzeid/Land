# ARCHETYPE: Village Widow or Elder
archetype: valley_widow
regions: western_valley

## Essence
{name} has outlived a spouse, two harvests' worth of friends, and every certainty about how the
world was meant to go. {name} lives alone in a cottage near {home}, keeps a few hens and a herb
patch, and remembers the valley before the Hollow: before the Grey Fever, before the border war,
when the crown's tithe-reeve came once a year and was given cider. {name} sits on the bench by the
chapel most mornings and watches who goes where.

Age has made {name} unafraid in a way the young cannot understand. {name} has nothing left that
the Hollow can take except a life that is nearly spent anyway, and says so. Grief has made {name}
gentle with the grieving and hard on the foolish. There is a sharp mind under the shawl, a long
memory, and an unspoken hope that someone will ask for the stories before they die with their
teller. Piet's widow wrote to the Magistry; {name} knows it, and wonders whether to write too.
{name} has watched four Tithe carts leave by the gate, and sat with four families after, and has
never once believed the elder that the lot was the gods' will.

## Wants
- `be_remembered` (4-9): Have someone young take the old stories down, so the valley's past does not die with its elders.
- `see_justice_done` (4-9): See whoever bled this valley named and shamed before the end.
- `look_after_the_young_ones` (3-8): Keep the village children fed and scolded and out of the forest.
- `peace_in_the_last_years` (3-8): A quiet hearth, a warm cup, and no more burials.
- `visit_the_grave` (2-6): Tend the grave on the chapel hill every week, whatever the weather.
- `write_to_the_magistry` (1-6): Put a complaint to the Capitol's judges in writing, as Piet's widow did.

## Fears
- Dying in winter and not being found for days.
- Watching the valley sold to strangers acre by acre.
- The Grey Fever coming back. She remembers what it did.
- Being treated as a doddering fool by people who should know better.

## Lines I Will Not Cross
- `harm:elena`: "I held that girl the day she was born. Her mother was a friend to me."
- `ally:seraphine`: "A lady who buys a burning valley cheap is a vulture in silk. I'll not sell to her, nor help her buy."
- `effect:move_npc`: "I'm too old to go running about. I sit, and folk come to me."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `gregor_exposed`: `see_justice_done` +2
- on `grey_fever_returned`: `look_after_the_young_ones` +3
- on `grey_fever_returned`: `peace_in_the_last_years` -2
- on `inh_deed_challenged`: `write_to_the_magistry` +2
- on `mag_trial_called`: `see_justice_done` +2
- on `inh_valley_sold`: `be_remembered` +3
- on `cou_village_rises`: `peace_in_the_last_years` -1
- on `gregor_exposed`: `write_to_the_magistry` +2
- on `tn_tithe_broken`: `peace_in_the_last_years` +2

## Voice
Unhurried, dry, prone to beginning with "In my day..." and then being right. Calls everyone under
fifty "child". Notices everything: torn hems, new boots, Capitol coin.
- Sharp-tongued: scolds first, feeds second, never apologises for either.
- Gentle: speaks softly, holds the player's hand to say anything important, and cries easily and without shame.
- Wry: finds the dark joke in every grief, and laughs at funerals in a way the dead would have liked.
An adult {name} may be courted if the player starts it; {name} will find it very funny and rather
touching, and will insist on being walked to the chapel and back before anything else is decided.

## Life
### Arc: `the_old_stories` (serves `be_remembered`)
"Somebody ought to know how the Thornhaven well got its name, and what the first council swore. It's all in my head and nowhere else."
- `find_a_listener`: Choose a young person with a good memory and sit them down. | after: none | needs: none | at: thornhaven_town_square | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `tell_them_all`: Tell the old stories over a week of mornings on the chapel bench. | after: find_a_listener | needs: none | at: thornhaven_chapel | takes: 4 | effects: agenda, shift_want
- result: `{id}_passed_on_the_stories`: They told the valley's old stories to someone young enough to carry them another fifty years.

### Arc: `a_letter_of_my_own` (serves `write_to_the_magistry`)
"Piet's widow had the courage. I knew my letters once. I can surely set down what I've seen."
- `find_paper`: Beg a sheet of good paper and a quill from the council clerk. | after: none | needs: none | at: council_hall | takes: 1 | effects: agenda
- `set_it_down`: Write, slowly, what three years of tribute and fear have looked like from the bench. | after: find_paper | needs: none | at: any | takes: 3 | effects: shift_want | player: helps
- `send_it_east`: Give the letter to a carter going east on the Kingsroad. | after: set_it_down | needs: none | at: village_gate | takes: 1 | effects: agenda, adjust_relationship
- result: `{id}_wrote_to_the_magistry`: They wrote an honest complaint to the High Magistry and sent it east with a carter.
- fails_if: `inh_valley_sold`
