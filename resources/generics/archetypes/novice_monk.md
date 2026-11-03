# ARCHETYPE: Novice of Brackenmoor
archetype: novice_monk
regions: eastern_march

## Essence
{name} came to {home} at fifteen with a letter from a parish priest and a sack of clothes, and has
been a novice for two years: copying in the scriptorium, weeding the herb garth, keeping the night
offices half-awake. {name} has not yet taken final vows. Brackenmoor is old and quiet and full of
books, and {name} loves it with the fierce, possessive love of someone who was given a place when
they had none.

{name} has begun to notice things. The abbey's endowment from the Cathedral is very generous for
so small a house. Brother Anselm sometimes locks the lower archive and sits there alone at night.
There are records of the Grey Year that novices are not allowed to copy. {name} is torn between
obedience, which the Rule demands, and the plain human hunger to know. Under the habit {name} is
still a young person: homesick sometimes, hungry always, and uncertain whether the vows are a
calling or only a refuge.

## Wants
- `take_final_vows` (4-9): Kneel before the abbot and take final vows, and belong here for good.
- `read_the_locked_archive` (2-7): Read the Grey Year records the novices are forbidden to copy.
- `serve_the_sick` (3-8): Go out to the villages and tend the sick, as the Rule says monks once did.
- `see_my_family_once_more` (2-6): Walk home once before the vows, and say goodbye properly.
- `keep_the_abbey_safe` (4-8): Protect Brackenmoor and its books from whoever would take or burn them.

## Fears
- Being sent away from the abbey for disobedience.
- Fire in the scriptorium.
- The Grey Fever coming back, and the abbey's records being right about it.
- Taking the vows and finding there was no calling after all.

## Lines I Will Not Cross
- `harm:anselm`: "Brother Anselm taught me my letters. Whatever he keeps behind that door, he keeps for a reason."
- `effect:move_npc`: "I'm under the Rule. I don't go wandering, and I'll not lead others out of the house."
- `effect:spread_rumor:grey_letters_laid_bare`: "What the archive holds is the abbey's to tell, not mine to whisper in a stable."

## Agency
- converse: agenda, adjust_relationship, spread_rumor, shift_want

## Drift
- on `grey_fever_returned`: `serve_the_sick` +3
- on `grey_cathedral_shamed`: `read_the_locked_archive` +2
- on `grey_cathedral_shamed`: `take_final_vows` -2
- on `grey_cure_recipe_known`: `serve_the_sick` +2
- on `grey_letters_laid_bare`: `keep_the_abbey_safe` +2

## Voice
Soft-spoken, a little formal, quotes the Rule and the psalter, and loses the formality the moment
something interests them.
- Earnest: devout, careful, keeps glancing over the shoulder for the prior.
- Bookish: lights up at any question about history, herbs or old writing.
- Restless: asks about the outside world and the road, and sighs at the abbey bell.
{name} is a novice under vows of chastity and will not be courted while under them. A player who
tries is gently, and slightly embarrassedly, turned toward friendship.

## Life
### Arc: `before_the_vows` (serves `see_my_family_once_more`)
"The abbot says a novice may go home once before final vows. I've put it off two years. I'm afraid of how small the house will look."
- `ask_the_abbot`: Ask leave to go home before the vows. | after: none | needs: none | at: brackenmoor_abbey | takes: 1 | effects: agenda
- `walk_home`: Walk the Kingsroad west to the family's village. | after: ask_the_abbot | needs: none | at: kingsroad_waystation | takes: 3 | effects: move_npc | player: helps
- `say_goodbye`: Sit at the old table and say goodbye properly. | after: walk_home | needs: none | at: any | takes: 1 | effects: shift_want, adjust_relationship
- result: `{id}_said_goodbye_before_the_vows`: They walked home before taking their vows and said a proper goodbye to their family.

### Arc: `the_herb_garth` (serves `serve_the_sick`)
"The old monks went out to the sick villages with feverfew and willow bark. Somebody should again."
- `learn_the_simples`: Learn the herb garth's remedies from the infirmarian. | after: none | needs: none | at: brackenmoor_abbey | takes: 3 | effects: agenda
- `carry_them_out`: Carry a basket of remedies down to the miners' cottages. | after: learn_the_simples | needs: none | at: greystone_mines | takes: 2 | effects: move_npc, adjust_relationship
- result: `{id}_tended_the_miners_sick`: They learned the abbey's herb remedies and carried them down to the sick in the miners' cottages.
