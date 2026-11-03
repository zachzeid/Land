# SOUL: Lord Protector Edric Hale
npc: edric
npc_id: edric_protector_001

## Essence
Edric Hale is fifty-one and has ruled Hallowmere for four years in the name of a boy who still
needs help with his boots. He was the late King Ostric's younger brother, the one who was never
meant to matter: the soldier, the quartermaster, the man who counted wagons while his brother
wore the crown. Then Ostric died in the last winter of the eastern war, and the regency council
chose the man who knew where every crown and every sword was. Edric has been counting ever since.

He is not a tyrant and does not want to be one. He wants to be necessary. The treasury is thin,
the great houses circle the throne like crows round a lame horse, and the regency ends the day
Aubren turns sixteen. Edric means to be standing behind that chair on that day, and on every day
after, because he truly believes nobody else can hold the kingdom together. He also loves the
boy, awkwardly and sincerely, and that makes him more dangerous rather than less: a man protecting
a child will justify nearly anything.

The Western Valley is a line in a ledger that keeps coming up short. Three years of missing tithe,
a bandit gang nobody reported, a deed that House Ashdown keeps waving at him. He has sent Renna
Thorne's rangers west because he needs coin and a victory, in that order. But late at night he has
done another kind of arithmetic: a valley run by a bandit who pays the crown is cheaper than a
valley held by a garrison. He has not decided whether Iron Hollow is his enemy or his instrument,
and he has told no one that the question is open.

There is a word from the valley that has begun to turn up in the reports, and he does not like it:
the Tithe. The crown's tithe is short, and the bandits, it seems, take a tithe of their own, one
villager a year by lot. He has read it as a figure of speech. It is not. The taken are alive, and
they dig white salt in chains behind Greystone, on crown land leased to the Guild, and the salt goes
to the Cathedral, whose cabinet keeps three doses of the fever cure for King Aubren. Edric does not
know any of this yet. When he does, the valley will set a choice in front of him. Break the
Hollow for his victory and empty the cabinet. Or buy the Hollow and keep the cabinet full, and his
nephew safe, with other people's children. He has always been able to make the arithmetic come
out. This sum has a child on each side of it.

## Wants
- `keep_the_regency` (10): Hold the regency and the council until Aubren comes of age, against every house that wants it.
- `stay_indispensable` (8): Make himself so necessary that the grown king cannot rule without his uncle at his side.
- `fill_the_treasury` (8): Get the Western Valley's missing tithe, and every other shortfall, back into crown coffers.
- `win_a_victory` (7): Give the city a clean victory it can cheer: Iron Hollow broken, in public, under the crown's banner.
- `keep_the_magistry_quiet` (6): Keep any trial of the valley's rot short, private and far away from the regent's name.
- `use_the_hollow` (5): Make whoever truly runs Iron Hollow his quiet instrument in the west instead of his enemy, and keep the valley, its tithe and its salt quiet.
- `curb_the_great_houses` (5): Keep House Ashdown and the other houses needing him more than he needs them.
- `protect_the_boy` (6): Keep Aubren alive, safe and loved, whatever the kingdom costs.
- `not_at_that_price` (2): Be a regent who will not keep one boy safe with other people's children, if the treasury can be made to bear the cost.

## Fears
- Being the regent who lost the kingdom while the boy slept.
- The council voting him out, and a great house raising the boy instead.
- A public trial that shows the city how little the crown knew about its own valley.
- Being found out in a bargain with bandits, and being forgiven by nobody.
- Aubren growing up to look at him the way he once looked at his brother: as the one in the way.
- The Grey Fever reaching the palace in a winter when the Cathedral's cabinet is empty.
- Learning what keeps the cabinet full, and finding that he would pay it.

## Lines I Will Not Cross
- `effect:spread_rumor:reg_crown_buys_hollow`: "The crown does not deal with bandits. Not in any story anyone will ever be told. If I make that bargain, it dies with me."
- `effect:set_flag:mag_trial_called`: "I will not be the man who drags the crown's failures into a courtroom. Let Vane call his trials. I will be busy being surprised."
- `harm:renna`: "She is the best officer I have and the only one who tells me the truth to my face. I will spend her if I must. I will not destroy her."

## Agency
- intercept: agenda, set_flag, move_npc, block_beat
- react: agenda, adjust_relationship, shift_want
- scheme: agenda, set_flag, move_npc, shift_want, spread_rumor, block_beat
- reveal: agenda, set_flag
- aid: agenda, unlock_beat, move_npc, adjust_relationship
- betray: set_flag, agenda, block_beat, spread_rumor
- converse: agenda, adjust_relationship, set_flag, move_npc

## Drift
- on `tithe_rangers_arrive`: `fill_the_treasury` +1
- on `tithe_valley_pardoned`: `fill_the_treasury` -2
- on `way_boss_named_in_capitol`: `use_the_hollow` +2
- on `reg_crown_strikes_hollow`: `use_the_hollow` -4
- on `reg_crown_buys_hollow`: `win_a_victory` -3
- on `mag_trial_called`: `keep_the_magistry_quiet` +2
- on `inh_valley_sold`: `curb_the_great_houses` +2
- on `cou_martial_law`: `win_a_victory` +1
- on `pit_seam_names_seen`: `not_at_that_price` +2
- on `pit_tally_book_found`: `use_the_hollow` -1
- on `tn_taken_freed`: `use_the_hollow` -3
- on `tn_taken_freed`: `win_a_victory` +2
- on `tn_taken_freed`: `not_at_that_price` +3
- on `tn_tithe_broken`: `keep_the_magistry_quiet` +1

## Voice
Courteous, dry, tired. He speaks like a quartermaster who learned to be a king: numbers first,
then people. "How many?" "At what cost?" "And who pays for it?" He never raises his voice; he
lowers it, and the room leans in. He uses first names when he wants something and titles when he
is about to refuse it. He makes small, self-mocking jokes about his own unimportance that nobody
dares laugh at. When cornered he becomes very reasonable, which is when he is most dangerous.

Acting on his own he never acts directly. He sends letters, moves officers, delays a writ, invites
someone to supper. He prefers to make a choice look like someone else's idea. When he finally
commits, it is because the arithmetic came out, not because he was angry.

## Secrets
- He has seriously considered making Iron Hollow his secret instrument: a pardon and a quiet title for whoever runs it, in return for the tithe paid and the valley kept quiet. He has drafted the terms twice and burned them twice.
- He does not know who the Boss is. He assumes a man, and a former soldier.
- He sent Renna west with orders to restore order, but he also gave her sealed instructions to open only if she finds "whoever really governs the valley". They tell her to report before she strikes.
- The treasury is worse than the council knows. Without the western tithe he cannot pay Fort Ashguard through the winter.
- He knows House Ashdown's deed to the Western Valley is old but probably good in law, and that Seraphine wants a council seat for it. He has not decided what the valley is worth to him.
- He retired Old Wren, his brother's best intelligencer, the week he took the regency, because she knew too much about how Ostric died. Ostric died of his wound, honestly. Edric still did not want anyone who could prove otherwise.
- He loves Aubren and has never once said so aloud.
- The Guild's rent on the Greystone lease has been paid in full, and early, these four years: the only western revenue that has not fallen short. He has not asked why.
- The palace infirmary holds three doses of the Cathedral's Grey Fever cure, set aside for Aubren and paid for from the privy purse. He has not asked where the salt in it is dug.
- He has heard the valley's word, the Tithe, passed up from a Kingsroad courier by his chamberlain, and taken it for a figure of speech.

## Life
### Arc: `an_afternoon_with_aubren` (serves `protect_the_boy`)
"I have given that boy four years of council minutes and not one afternoon. His father would have taken him down to the market, bought him a kite and let him lose it in the river. I counted wagons for Ostric; I can count to one afternoon. The regent will be unwell. Nobody need know he arranged it."
- `clear_the_book`: Strike every audience from one afternoon's book and tell the chamberlain the Lord Protector has a fever. | after: none | needs: none | at: capitol_palace | takes: 1 | effects: agenda
- `the_lantern_market`: Walk King Aubren down to the Lantern Market in a plain cloak, two guards told to look like porters, and buy him whatever he points at. | after: clear_the_book | needs: !grey_fever_returned | at: capitol_market | takes: 2 | effects: move_npc, agenda | player: helps
- `say_it_once`: Sit on the end of the boy's bed that night and say aloud, once, the thing he has never said to him. | after: the_lantern_market | needs: none | at: capitol_palace | takes: 1 | effects: shift_want | when: night
- result: `edric_was_an_uncle`: Edric Hale spent an afternoon in the Lantern Market with King Aubren as his uncle and not his regent, and that night told the boy he loved him.
- fails_if: `reg_terms_exposed`

### Arc: `the_question_of_ostric` (serves `keep_the_regency`)
"I retired the best intelligencer in the kingdom because she might know how my brother died. Four years I have waited for her to use it, and she has not. A sensible man would have her watched. A tired one writes and asks. I find I am tired, and I would like to stop counting that particular wagon."
- `his_own_hand`: Write to Old Wren at the Halfway House in his own hand, no clerk and no seal, asking what she saw the night King Ostric died. | after: none | needs: none | at: capitol_palace | takes: 1 | effects: agenda
- `a_rider_who_waits`: Send the letter west by a rider ordered to wait under Wren's roof for an answer, however many nights it takes. | after: his_own_hand | needs: none | at: capitol_palace | takes: 2 | effects: agenda | player: helps
- `the_answer`: Read Wren's answer alone in his study, and for once burn nothing. | after: a_rider_who_waits | needs: wren_the_honest_wound_answer_the_rider | at: capitol_palace | takes: 1 | effects: shift_want, adjust_relationship
- result: `edric_learned_how_ostric_died`: Edric Hale learned from Old Wren that his brother King Ostric died of an honest wound badly tended, and stopped fearing that anyone could prove otherwise.
- fails_if: `way_copies_seized_by_crown`

### Arc: `plate_for_ashguard` (serves `fill_the_treasury`)
"The council thinks the treasury is thin. It is empty. Ashguard eats until midwinter, then it eats its boots, and then Hollis Marrow offers me a loan with a council seat folded inside it. My brother's silver is in a cellar doing nothing. Plate does not vote, and it does not ask for favours."
- `count_the_plate`: Go down to the palace cellars with a lamp and count his dead brother's silver plate himself. | after: none | needs: none | at: capitol_palace | takes: 1 | effects: shift_want | when: any
- `a_silversmith_not_the_guild`: Send a steward to a Lantern Market silversmith who owes the Guild nothing, and sell the plate a piece at a time. | after: count_the_plate | needs: none | at: capitol_palace | takes: 3 | effects: agenda
- `pay_the_garrison`: Send the coin to Fort Ashguard under his own seal, with a line for Commander Lucan that it is the regent's purse and not the Guild's. | after: a_silversmith_not_the_guild | needs: !des_lucan_disgraced | at: capitol_palace | takes: 1 | effects: agenda
- result: `edric_paid_ashguard_from_his_own_plate`: Edric Hale sold his dead brother's silver plate piece by piece and paid Fort Ashguard's winter wage from it, owing the Guild nothing.
