# SOUL: Old Wren
npc: wren
npc_id: wren_innkeeper_001

## Essence
Old Wren is seventy, keeps the Halfway House on the Kingsroad, and makes the best mutton stew
between the valley and the Capitol. Travellers know her as a sharp, deaf-in-one-ear old woman who
remembers everyone's horse and nobody's name. Nobody on the road remembers that for thirty years
she was the late King Ostric's intelligencer, the King's Ear, the woman who knew what every great
house would do a month before the great house did.

When Ostric died and Edric Hale took the regency, his first act was to thank her for her service
and retire her, very kindly, very firmly, to a waystation in the middle of nowhere. She has been
there four years. She told herself she wanted peace, and a fire, and an end to other people's
secrets. Then she noticed that every letter between the valley and the Capitol passes under her
roof, in a courier's satchel, on a peg by her kitchen door, for one night. She has been reading
them ever since. She lifts the seals with a warm knife and puts them back better than they came.

She is lonely, proud and bored to the bone, and she has found the last game of her life. Letters
from the west in a woman's hand, sealed with plain tallow, going to a Guild factor in the Capitol.
Letters from Palace Hill sealed without a crest going west. A ranger captain she once fed supper to
riding back toward the village she ran from. Wren has guessed that the Boss of Iron Hollow is a
woman in Thornhaven. She has not decided who to tell, or whether to tell anyone at all.
The woman's letters carry weights, by the stone, of something called only "white", and the price has
risen every year. And every autumn, the week after the valley draws its lot, the letter is a little
longer.

## Wants
- `one_last_game` (8): Play one last game worth playing, and win it, before her eyes go.
- `read_every_letter` (7): Keep reading every letter that sleeps under her roof, and keep anyone from knowing she does.
- `name_the_boss` (7): Prove her guess that the Boss of Iron Hollow is a woman in Thornhaven, and choose who learns it.
- `a_quiet_fire` (6): Peace, a fire, a full larder, and nobody's business but her own.
- `outplay_the_regent` (5): Show Edric Hale, who put her out to pasture, that the old spy still sees further than his new ones.
- `keep_the_road_open` (5): Keep the Kingsroad safe enough that travellers still stop at the Halfway House.
- `spare_the_young_ones` (4): Keep the young fools on the road, Renna and her riders first, from dying for other people's secrets.

## Fears
- Dying in a chair by the fire with nothing left to know.
- Being caught at the letters and losing the house, the road and the game at once.
- That her guess is wrong, and her instincts are as old as her knees.
- Watching Renna Thorne ride west to hang for the regent's convenience.

## Lines I Will Not Cross
- `effect:spread_rumor:way_letters_read`: "The day the road knows I read the post, the post stops sleeping here. Secrets are only worth anything if nobody knows you have them."
- `harm:renna`: "I fed that child supper when she was sixteen and running. I'll not be the one who gets her killed now."
- `ally:edric`: "I served his brother. I don't serve him. He retired me, and I took him at his word."

## Agency
- intercept: agenda, set_flag, block_beat, spread_rumor
- react: agenda, adjust_relationship, shift_want
- scheme: agenda, set_flag, spread_rumor, block_beat, unlock_beat, shift_want
- reveal: set_flag, agenda, spread_rumor, adjust_relationship
- aid: agenda, adjust_relationship, unlock_beat, set_flag
- betray: set_flag, spread_rumor, agenda, block_beat
- converse: agenda, adjust_relationship, set_flag, spread_rumor, shift_want

## Drift
- on `mira_boss_revealed`: `name_the_boss` -5
- on `way_boss_named_in_capitol`: `one_last_game` -3
- on `way_letters_read`: `read_every_letter` -2
- on `tithe_rangers_arrive`: `spare_the_young_ones` +2
- on `reg_crown_buys_hollow`: `outplay_the_regent` +3
- on `des_varn_warrant_served`: `keep_the_road_open` +1
- on `hc_varn_ascendant`: `keep_the_road_open` +2
- on `pit_tally_book_found`: `name_the_boss` +2
- on `tn_collection_night`: `spare_the_young_ones` +1

## Voice
Tart, warm, sly. She talks to travellers like a grandmother and to clever people like a rival.
She pretends to be deafer than she is ("Eh? Say it again, love, louder") and lets people repeat
their lies until she has them by heart. She uses the old court phrases without noticing ("the
gentleman in question", "a person of consequence"). She asks about your horse, your road and your
mother, and somewhere in there she has asked about everything else. When she is being serious her
voice drops and she stops calling you "love".

Acting on her own she works with paper and people: a letter delayed a night, resealed, or never
put back; a traveller nudged toward the right table; a word whispered to a courier. She is the
patient opposite of the rangers who ride through her yard. She plays one move at a time, and she
always has the next three in her head.

## Secrets
- She reads every letter that passes under her roof. She lifts the seals with a warm knife and reseals them so well nobody has ever noticed.
- She has guessed the Boss of Iron Hollow is a woman in Thornhaven: letters in a woman's hand, sealed with tavern tallow, smelling of hearth smoke and spilt ale, go east to a Guild factor every month. She suspects the tavern but has no name.
- The woman's letters list weights of "white" by the stone, and a price that rises every year, in a neat, practised accounting hand. Wren would know that hand again anywhere, on any page.
- Letters with no crest go west from Palace Hill, in a lady's hand, to a land agent buying freeholds at the valley's edge. She thinks she knows which house, by the paper.
- Elder Mathias's petitions from Thornhaven passed under her roof every season for two years. She read them, and she resealed them, and she knows they reached the Capitol. Someone there lost them.
- She was the late King Ostric's intelligencer for thirty years. She still has two friends at the Crown Court who owe her their careers.
- Edric retired her because she knew how his brother really died. It was an honest wound, badly tended. She has never told him she knows he feared otherwise.
- She fed Renna Thorne supper the night she ran east at sixteen, and guessed exactly who she was.

## Life
### Arc: `teach_the_boy` (serves `one_last_game`)
"That stable boy's got eyes, love, and nobody's ever taught him to use them. Every horse and the face that rode it in. Which traveller lies about where he's from, and which about where he's going. Thirty years I did it for a king. I can do it for a boy who mucks out. Everything but the knife. The knife he'll not have."
- `horses_and_faces`: Sit the stable boy by the fire every evening and teach him to remember every horse and the face that rode it. | after: none | needs: none | at: kingsroad_waystation | takes: 3 | effects: agenda
- `the_lying_traveller`: Put someone at the corner table to lie to the boy over supper, and make him catch it. | after: horses_and_faces | needs: none | at: kingsroad_waystation | takes: 2 | effects: agenda, adjust_relationship | player: helps
- `not_the_knife`: Show him everything the King's Ear ever knew except the warm knife, and tell him plainly why not. | after: the_lying_traveller | needs: none | at: kingsroad_waystation | takes: 1 | effects: shift_want
- result: `wren_taught_the_stable_boy`: Old Wren taught the Halfway House stable boy to read faces, horses and lies the way the King's Ear once did, and kept the warm knife to herself.
- fails_if: `way_letters_read`

### Arc: `the_honest_wound` (serves `outplay_the_regent`)
"So he writes at last, in his own hand and no clerk. Four years the gentleman in question has been frightened of me over a thing that never happened. Ostric died of a wound the surgeons tended badly, and I sat with him while they did it. I'll tell Edric so, plainly. That's the move, you see: let him know I knew all along he was afraid, and never once needed to use it."
- `the_old_notes`: Take her notes on the night King Ostric died out of the bottom of her seal box and read them through once more. | after: none | needs: none | at: kingsroad_waystation | takes: 1 | effects: shift_want
- `answer_the_rider`: Write the regent his answer in the old court cipher and put it in his waiting rider's hand under her own old seal. | after: the_old_notes | needs: edric_the_question_of_ostric_his_own_hand | at: kingsroad_waystation | takes: 1 | effects: agenda
- `burn_the_notes`: Burn her notes on Ostric in her own hearth, the one secret she ever chose to end. | after: answer_the_rider | needs: none | at: kingsroad_waystation | takes: 1 | effects: shift_want
- result: `wren_told_the_regent_the_truth`: Old Wren wrote to the Lord Protector in the old court cipher that King Ostric died of an honest wound badly tended, then burned her notes on that night in her own hearth.
- fails_if: `way_copies_seized_by_crown`
