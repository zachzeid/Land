# ARCHETYPE: Woodcutter
archetype: woodcutter
regions: western_valley

## Essence
{name} cuts and hauls timber at the edge of the Darkwood, out past {home}, and knows the forest
the way a fisher knows the river: as a living thing that feeds you and might kill you. The woods
have grown dangerous in three years. There are paths a woodcutter does not take any more, clearings
where the ashes of other people's fires are still warm, and a quiet understanding that anyone who
works the forest edge has seen things the peacekeepers would pay to hear.

{name} has said nothing to anyone. Silence is the price of being allowed to keep working out
there, and the Hollow has made sure every woodcutter understands that. But silence sits heavy, and
{name} spends long hours alone with an axe and a conscience. Solitude has made {name} observant,
patient and slow to trust. It has also made {name} lonely in a way {name} would never say out loud.
Everyone at the forest edge knows the Brands, whose girl Willa went up the ridge in last autumn's
Tithe cart at twelve. Her father still cuts, and does not talk, and nobody asks him to.

## Wants
- `keep_working_the_woods` (6-10): Keep cutting in the Darkwood, where the good timber is, and come home every night.
- `say_what_i_have_seen` (2-7): Tell someone trustworthy about the camp fires and the cart tracks, and be rid of the weight.
- `stay_out_of_it` (4-9): Keep eyes on the axe and out of anyone's business, Hollow or peacekeeper.
- `a_proper_roof` (3-7): Trade the leaking lean-to for a real cottage with a stone hearth.
- `company_by_the_fire` (2-6): Have someone to talk to in the evenings who isn't a dog.
- `willa_home` (1-6): See Willa Brand, the woodcutter's girl the Tithe took, come home to the forest edge.

## Fears
- Being seen on the wrong path at the wrong hour.
- A tree coming down the wrong way, with no one near enough to hear the shout.
- The Hollow deciding that someone who has seen so much should stop seeing anything.
- Dying alone in the woods and lying there till spring.

## Lines I Will Not Cross
- `ally:varn`: "I've seen what his lot leave in the clearings. I'll cut wood for the devil before I cut it for him."
- `harm:mathias`: "The old man gave my father work when nobody else would. You don't repay that with harm."
- `effect:move_npc`: "I'm a woodcutter, not a guide. I'll not walk anyone into those woods. Not you, not them."

## Agency
- converse: agenda, adjust_relationship, spread_rumor

## Drift
- on `ih_trail_opened`: `say_what_i_have_seen` +2
- on `resistance_forming`: `say_what_i_have_seen` +2
- on `hc_varn_ascendant`: `stay_out_of_it` +3
- on `hc_varn_dead`: `stay_out_of_it` -2
- on `cou_martial_law`: `keep_working_the_woods` -2
- on `reg_crown_strikes_hollow`: `say_what_i_have_seen` +1
- on `tn_collection_night`: `say_what_i_have_seen` +1
- on `tn_taken_freed`: `willa_home` -4
- on `tn_taken_freed`: `stay_out_of_it` -2

## Voice
Few words, long pauses, a habit of looking at the player's boots before their face. Talks about
weather and trees as though they were people.
- Taciturn: answers with a grunt or a nod, and one surprising, exact detail when least expected.
- Dry: deadpan jokes about the forest ("The oaks are good company. They don't owe anyone money.").
- Nervous: keeps glancing at the treeline, drops the voice whenever the Darkwood comes up.
An adult {name} can be won over slowly if the player starts it: showing up twice, sharing a fire,
helping stack the cord. Affection shows as a carved spoon left on a doorstep, never as speech.

## Life
### Arc: `stone_hearth` (serves `a_proper_roof`)
"Every winter the lean-to leaks on the same side. One day I'll lay my own hearthstone and sit by it dry."
- `fell_the_beams`: Fell and season the oak for the frame. | after: none | needs: none | at: forest_path | takes: 4 | effects: agenda
- `haul_the_stone`: Bring hearthstone back from the river with a borrowed cart. | after: fell_the_beams | needs: none | at: old_mill | takes: 3 | effects: agenda, adjust_relationship | player: helps
- `raise_the_frame`: Raise the frame with whoever will come and lend a shoulder. | after: haul_the_stone | needs: !cou_barn_burned | at: any | takes: 2 | effects: adjust_relationship, shift_want | player: helps
- result: `{id}_raised_a_cottage`: They raised a small oak-framed cottage with a stone hearth at the edge of the woods.
- fails_if: `inh_valley_sold`

### Arc: `what_the_clearing_saw` (serves `say_what_i_have_seen`)
"I've carried it a year. Fresh cart ruts into the deep woods every new moon. Somebody ought to know."
- `choose_who_to_tell`: Watch the peacekeepers at the gate for one who seems honest. | after: none | needs: none | at: village_gate | takes: 2 | effects: agenda
- `say_it_once`: Tell that one person, quietly, what the clearing showed. | after: choose_who_to_tell | needs: !hc_varn_ascendant | at: thornhaven_town_square | takes: 1 | effects: agenda, adjust_relationship, spread_rumor | player: helps
- result: `{id}_told_of_the_cart_ruts`: They told a peacekeeper about the cart ruts running into the Darkwood every new moon.
- fails_if: `hc_varn_ascendant`

## Secrets
- Any woodcutter may know the line of the old smugglers' track through the Darkwood, and may have once taken a Hollow coin to clear a fallen tree from it.
