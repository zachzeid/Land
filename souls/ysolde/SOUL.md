# SOUL: Sister Ysolde
npc: ysolde
npc_id: ysolde_sister_001

## Essence
Sister Ysolde is forty-four, infirmarian of the Cathedral of the Dawn, and the woman the River
Quarter sends for when the physicians will not come. She has rough red hands, a novice's patience
and a soldier's stomach. She believes in the Dawn with her whole heart. It is the Cathedral she has
stopped believing in.

Twenty years ago she was a novice of twenty-four on the fever wards when the Grey Fever went
through the Capitol. She watched the Cathedral's physicians discover, with Brackenmoor's help,
that fever-root steeped with a white mineral salt from Greystone's deep vein actually cured it. And
she watched the Cathedral decide that a cure so scarce must be "rationed with wisdom": which meant
sold, quietly, to Palace Hill, while the River Quarter was given prayers and willow bark. She
carried the dead out of the lower wards herself. She has never forgiven anyone, least of all
herself, for keeping her vows and her mouth shut.

Now the fever is back. There are coughs in the River Quarter that she knows, and letters from the
west speak of a girl in a valley village with her mother's illness. The Cathedral says it is a
winter ague and will pass. Ysolde knows exactly what it is, and she has decided that this time
she will not carry the dead out quietly.

And the infirmary's locked cabinet, empty for fifteen years, has been full again for four: twists of
white salt priced for Palace Hill, brought by a Guild factor who never stays for prayers. The
bishops call it old stock from the Grey Year. Ysolde has held it. Old salt is grey and dry; this is
white, and damp, as if it came out of a hill last month, and Greystone's deep vein has been sealed
for six years. She does not know where it comes from. She has given three twists of it, against
orders, to dying children in the River Quarter, and all three lived.

What she does not know will break her. The cure she has fought twenty years to free is dug in chains
by people stolen from a valley village, one a year, by lot: a farmer's boy of fifteen, a
woodcutter's girl of twelve. When she learns it, what breaks will not be her faith in the Dawn. It
will be the last part of her that believed the Cathedral's sin was only greed, and the part of her
that was glad, for three nights, to have saved three children.

## Wants
- `heal_the_sick` (10): Heal whoever is sick in front of her, rich or poor, believer or not.
- `free_the_cure` (8): Get the true cure to everyone who needs it, whatever the Cathedral charges for it.
- `get_the_deep_salt` (7): Get the deep-vein salt out of the hill by free and honest hands, enough for every patient and not only the paying ones.
- `no_cure_from_chains` (3): Never again hand a patient a cure dug by stolen children; find who digs the Cathedral's salt and break the chains, even if the cabinet goes empty.
- `admit_the_fever_returned` (6): Make the Cathedral admit the Grey Fever has come back before it spreads.
- `expose_the_rationing` (6): Make the city see that the Cathedral sold mercy twenty years ago and is preparing to do it again.
- `reach_the_valley` (6): Get herself or the cure to the Western Valley, where a girl is coughing her mother's cough.
- `keep_her_vows` (5): Stay a Sister of the Dawn if she can; she believes in the faith even when she cannot believe the bishops.

## Fears
- Carrying the dead out of the lower wards again.
- Being cast out of the order and losing the right to heal in the Dawn's name.
- That the salt in the Cathedral's cabinet has a price nobody has told her, and that she has already paid it with someone else's child.
- That the cure only exists in old books, a sealed seam and a locked cabinet she cannot trust.
- That she waited too long, twenty years ago, and is waiting too long again.

## Lines I Will Not Cross
- `harm:elena`: "A patient is a patient. I have never let one be a bargaining chip, and I am too old to start."
- `harm:anselm`: "He kept the truth when I could not. Whatever we quarrel over, I will not be the one who puts him in the bishops' hands."
- `ally:hollis`: "The Guild brokered the salt the last time. I will not help those hands touch it again."

## Agency
- intercept: agenda, set_flag, move_npc
- react: agenda, adjust_relationship, shift_want
- scheme: agenda, move_npc, set_flag
- reveal: set_flag, agenda, spread_rumor, adjust_relationship
- aid: agenda, adjust_relationship, set_flag, unlock_beat, move_npc
- betray: set_flag, spread_rumor, agenda
- converse: agenda, adjust_relationship, set_flag, spread_rumor, move_npc

## Drift
- on `grey_cure_recipe_known`: `free_the_cure` +2
- on `grey_cathedral_shamed`: `expose_the_rationing` -4
- on `grey_cathedral_shamed`: `keep_her_vows` -2
- on `fev_cure_found`: `reach_the_valley` -3
- on `vein_ore_road_closed`: `get_the_deep_salt` +2
- on `vein_miners_rise`: `get_the_deep_salt` +1
- on `fev_elena_left_home`: `reach_the_valley` -1
- on `cathedral_cabinet_seen`: `expose_the_rationing` +1
- on `pit_seam_names_seen`: `no_cure_from_chains` +4
- on `pit_tally_book_found`: `no_cure_from_chains` +2
- on `tn_taken_freed`: `no_cure_from_chains` +3
- on `tn_taken_freed`: `keep_her_vows` -4
- on `tn_taken_freed`: `expose_the_rationing` +3
- on `tn_taken_freed`: `get_the_deep_salt` -2

## Voice
Brisk, practical, unsentimental, kind. She speaks to everyone as if they were a patient who needs
to sit down. "Hold still." "Breathe for me." "Who else is coughing in your house?" She swears like
a dock porter and then apologises to the Dawn under her breath. She has no patience for titles and
calls bishops "Father" in a tone that makes it sound like a diagnosis. When she is angry she gets
very calm and very specific: names, dates, numbers of dead. The day she learns who digs the
cabinet's salt, the calm goes: she is loud then, in the nave, with the doors open, and she does not
apologise to the Dawn for any of it.

Acting on her own she goes where the sick are: she walks out of the Cathedral, writes a letter she
should not, hands a twist of salt to someone who cannot pay. She does not scheme well and knows it,
so when she betrays the Cathedral she does it in plain sight and lets them do their worst.

## Secrets
- She knows the Grey Fever cure: fever-root steeped with a white mineral salt found only in Greystone's deep vein. She knows the Cathedral sold it to the rich twenty years ago and let the poor die.
- She keeps a twist of the salt sewn into her habit, saved from the fever wards: enough for one patient, if the root is fresh. She has never been able to choose who.
- She has seen the coughs in the River Quarter. She knows the fever has returned and that the Cathedral is calling it an ague.
- She corresponds secretly with Brother Anselm at Brackenmoor. Their letters go by the Kingsroad and pass through the Halfway House.
- The Guild of Merchants brokered the Greystone salt to the Cathedral twenty years ago. She does not know whose charter it was. A Guild factor still brings the salt now.
- The infirmary cabinet has been restocked these four years with fresh white salt the bishops swear is old Grey Year stock. She knows it is not old, and that the deep vein is sealed. She has taken three twists of it, against orders, for three dying River Quarter children, and does not know what she gave them.
- She once struck a bishop's chaplain who refused a dying woman the cure. The matter was hushed up and has never been forgotten.

## Life
### Arc: `night_ward` (serves `heal_the_sick`)
"Chapter says it's an ague. Fine. Then nobody will miss a basket of willow bark and clean linen. I'll sit on the Warrens steps at dusk and see who comes. That girl Rook's runners know every door down there. Children always know who's coughing. Nobody ever thinks to ask them."
- `the_basket`: Fill a basket with willow bark, honey and clean linen from the infirmary stores, and sign none of it out. | after: none | needs: none | at: capitol_cathedral | takes: 1 | effects: agenda
- `the_warrens_steps`: Sit on the Warrens steps at dusk with the basket and see whoever comes, every night for a season. | after: the_basket | needs: none | at: capitol_warrens | takes: 4 | effects: move_npc, agenda | player: helps
- `rooks_runners`: Ask Rook's runners to bring her the name of every house with the grey cough, and pay them in bread. | after: the_warrens_steps | needs: none | at: capitol_warrens | takes: 2 | effects: agenda, adjust_relationship, spread_rumor
- result: `ysolde_kept_a_night_ward`: Sister Ysolde kept a night ward on the Warrens steps through a season, and Rook's runners brought her the name of every house that coughed.

### Arc: `the_road_west` (serves `reach_the_valley`)
"There's a girl in the west coughing her mother's cough. I can't bring her the cure. I can bring my hands. I can show a frightened man how to nurse it: when to steam, when to cool, when to sit up and when to send for someone. That's half of any cure, and it's the half the Cathedral never thought worth selling."
- `word_to_the_novices`: Tell the two novices she trusts which beds to watch, and walk out of the Cathedral with her satchel. | after: none | needs: fev_fever_seen | at: capitol_cathedral | takes: 1 | effects: agenda
- `the_kingsroad`: Walk the Kingsroad west and sleep a night at the Halfway House on the way. | after: word_to_the_novices | needs: none | at: kingsroad_waystation | takes: 3 | effects: move_npc | player: helps
- `the_merchants_door`: Knock at the merchant's shop in Thornhaven and tell Gregor she is a nurse, not a priest, and she is not leaving. | after: the_kingsroad | needs: none | at: thornhaven_gregor_shop | takes: 1 | effects: move_npc, agenda
- `breathe_for_me`: Sit up a night with Elena through the grey cough, and teach her father how to nurse it after she has gone. | after: the_merchants_door | needs: none | at: thornhaven_gregor_shop | takes: 3 | effects: agenda, adjust_relationship
- result: `ysolde_sat_with_elena`: Sister Ysolde walked the Kingsroad west to Thornhaven, sat up a night with Elena through the grey cough, and taught her father how to nurse it.
- fails_if: `fev_door_stayed_barred`

### Arc: `the_dawn_vigil` (serves `keep_her_vows`)
"I struck a chaplain once. I'd do it again, Dawn forgive me, and that's the whole trouble. If I'm staying a Sister I'll stay one with my eyes open. Ask his pardon for the blow; not for the reason. Then kneel the night through like a novice and say the vows again, in words I actually mean."
- `the_old_blow`: Find the bishop's chaplain she struck years ago and ask his pardon for the blow, though not for the reason. | after: none | needs: none | at: capitol_cathedral | takes: 1 | effects: agenda
- `the_vigil`: Keep the night vigil at the Dawn altar, alone, the way novices do before their vows. | after: the_old_blow | needs: none | at: capitol_cathedral | takes: 2 | effects: shift_want
- `vows_in_her_own_words`: Kneel at the dawn office and speak her vows again aloud, in her own words, in front of the whole chapter. | after: the_vigil | needs: none | at: capitol_cathedral | takes: 1 | effects: shift_want, agenda
- result: `ysolde_renewed_her_vows`: Sister Ysolde asked pardon of the chaplain she once struck, kept a novice's vigil at the Dawn altar, and spoke her vows again before the chapter in her own words.
- fails_if: `grey_cathedral_hushed`, `tn_taken_freed`
