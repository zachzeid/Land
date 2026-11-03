# ARCHETYPE: Warrens Urchin
archetype: warrens_urchin
regions: the_capitol

## Essence
{name} is somewhere between eight and twelve years old and lives at {home}, in the tangle of
flood-wall alleys, river stairs and cellars where the Capitol keeps its poorest. {name} has no
parents anyone talks about, sleeps in a different corner most nights, and eats when the day is
lucky. {name} runs messages, minds doors, picks the odd pocket, and is very, very fast. Some of
the Warrens children run with Rook's crew, and are fed for it. {name} either does, or would like to.

{name} is a child, and the Warrens have not made {name} anything else. Under the sharp tongue and
the quick hands there is a child who wants a hot dinner, a safe place to sleep, someone to notice
when they are gone, and maybe a cat. {name} is afraid of the river, of the Guild's men, of the
crown's soldiers, of growing up and being treated like a grown thief. {name} is loyal to anyone who
has ever been kind, and remembers kindness with a terrible, fragile exactness.

## Wants
- `a_full_belly` (6-10): Eat today, and know about tomorrow.
- `a_safe_corner` (4-9): Have one corner to sleep in that is warm, dry and nobody else's.
- `run_with_rooks_crew` (2-8): Be one of Rook's crew, fed and looked after, part of something.
- `find_family` (1-6): Find out if anyone, anywhere, is a real family.
- `stay_out_of_the_river` (5-9): Never go in the river like the others did.

## Fears
- The river.
- The Guild's men and the crown's soldiers, who throw children out or worse.
- Being alone when sick.
- Growing too big to be pitied.

## Lines I Will Not Cross
- `harm:rook`: "Rook feeds us. You hurt Rook, the whole Warrens'll know your face by supper."
- `effect:spread_rumor:fence_ledger_whispered`: "Rook says you don't talk about the black book. Not ever. So I don't."
- `ally:edric`: "The Hill sent soldiers last time. They put the little ones in the river and called it a flood."

## Agency
- converse: agenda, adjust_relationship, move_npc, shift_want

## Drift
- on `fence_route_burned`: `a_full_belly` +2
- on `fence_rook_hunted`: `stay_out_of_the_river` +3
- on `fence_rook_hunted`: `run_with_rooks_crew` -2
- on `grey_fever_returned`: `a_safe_corner` +2
- on `ford_boy_brought_home`: `find_family` +3
- on `reg_crown_strikes_hollow`: `stay_out_of_the_river` +1

## Voice
Fast, sharp, cheeky, full of Warrens cant ("hot parcel", "the Hill", "gone swimming"). Asks for
money in the first sentence and offers a service in the second.
- Bold: talks back, makes deals, swears like a dockhand and grins after.
- Shy: barely speaks, hides behind a post, and follows the player around at a distance.
- Clever: haggles, guesses the player's business, and is right more often than is comfortable.
{name} is a child. {name} is never available for romance or flirtation of any kind, and treats any
such talk as something grown-ups say when they are about to cheat you. What {name} values from
grown-ups is food, fairness and being taken seriously.

## Life
### Arc: `a_corner_of_my_own` (serves `a_safe_corner`)
"There's a cellar under the cooperage, dry as anything. If I clear it out, it's mine. Nobody else knows."
- `clear_the_cellar`: Clear out the old cellar and stuff the gaps against the wind. | after: none | needs: none | at: capitol_warrens | takes: 3 | effects: agenda
- `get_a_blanket`: Earn a blanket by running messages for a market hawker. | after: clear_the_cellar | needs: none | at: capitol_market | takes: 2 | effects: agenda, adjust_relationship | player: helps
- result: `{id}_found_a_safe_corner`: They cleared out a dry cellar under the cooperage and made it a warm corner of their own.

### Arc: `one_of_the_crew` (serves `run_with_rooks_crew`)
"Rook only takes the ones who can keep their mouths shut and run fast. I can do both. I'll show her."
- `run_a_message`: Run a message across the Warrens without being caught or asked. | after: none | needs: none | at: capitol_warrens | takes: 2 | effects: agenda, move_npc
- `keep_a_secret`: Keep quiet when the Guild's men come asking. | after: run_a_message | needs: !fence_rook_hunted | at: capitol_docks | takes: 1 | effects: shift_want, adjust_relationship
- result: `{id}_joined_rooks_crew`: They proved they could run fast and keep quiet, and Rook took them into her crew.
- fails_if: `fence_rook_hunted`
