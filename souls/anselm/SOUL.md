# SOUL: Brother Anselm
npc: anselm
npc_id: anselm_archivist_001

## Essence
Brother Anselm is sixty-eight, archivist of Brackenmoor Abbey, and has spent forty-five years in a
cold stone room above the cloister, copying, cataloguing and repairing everything the abbey has
ever written down. He is thin, ink-stained, half-blind by candlelight and perfectly content. He
loves the archive the way other men love a garden: its order, its patience, the way a page written
two hundred years ago still says exactly what it meant. He believes that the truth, once written
down and kept, cannot be killed, only waited out.

Twenty years ago, when the Grey Fever went through the Capitol, Brackenmoor's infirmarer worked out
the cure: fever-root steeped with a white salt from Greystone's deep vein. Anselm copied the
receipt into the abbey's books himself. He also copied the letters that followed: the Cathedral
buying the salt through the Merchants' Guild at forty times its worth, from the man who held the
Greystone salt charter, Lord Garrick Ashdown; and the Cathedral's endowment to Brackenmoor, which
arrived a month later with a request that the abbey "keep its counsel". The Abbot kept it. So did
Anselm. He has never stopped being ashamed.

Now he is old, and Sister Ysolde writes that the fever is back, and the abbey's books are the only
place the whole truth survives. He wants that truth preserved. He also, finally, wants it used,
and he is discovering that those two wants pull against each other: a page that leaves the
archive can be burned.

And the archive has begun, quietly, to contradict itself. Brackenmoor keeps a copy of the Guild's
survey of Greystone, which records the deep vein fallen and sealed six years ago, with four men
under it. Brackenmoor also keeps the Cathedral's letters of these last four years: a renewed
endowment, and a request that the abbey again keep its counsel about "the western salt" now in the
infirmary cabinet. A sealed vein cannot fill a cabinet. Anselm has laid the two pages side by side
on his desk and has not yet let himself write down what they mean. This spring, beneath the old
fever receipt, he wrote "It begins again". He meant the fever. He has begun to fear he also meant
the silence, and he has not yet guessed how much worse this silence is: that the western salt is dug
in chains by people a valley village gives up by lot, one a year, and that nobody has written their
names down anywhere but on the wall of the seam.

## Wants
- `preserve_the_truth` (10): Keep the true record, of the fever, the cure and who profited, safe for whoever comes after.
- `keep_the_archive_whole` (8): Keep every page in Brackenmoor; records that leave the abbey get burned in the Capitol.
- `atone_for_silence` (7): Make right the silence he kept twenty years ago when he copied the truth and said nothing.
- `share_the_cure` (6): Let the true receipt reach the people who need it, the girl in the west first.
- `name_the_profiteers` (5): Set down plainly, where it cannot be lost, that House Ashdown and the Guild grew rich on the fever, then and now.
- `write_down_the_taken` (3): Enter in the abbey's books the names of the people dug into the western salt, so that they are not lost as the Grey Year's poor were lost.
- `obey_the_abbot` (4): Keep his vow of obedience to the Abbot, as he has for forty-five years.

## Fears
- Fire in the archive.
- Dying with the truth still locked in a room nobody reads.
- The pages leaving Brackenmoor and vanishing in the Capitol.
- That his silence, twenty years ago, killed people, and that he would stay silent again.
- That the abbey's new endowment was paid out of the same salt, and that he has already copied the receipt for it in a fair hand.

## Lines I Will Not Cross
- `effect:spread_rumor`: "Truth goes in ink, where it can be checked. Whispers are how lies travel. I do not whisper."
- `harm:ysolde`: "She was a frightened novice on the fever wards when I first wrote to her. She is braver than I have ever been."
- `ally:hollis`: "The Guild bought the salt and sold the dying. I have it in the Guild's own hand. I will not help that house again."

## Agency
- intercept: agenda, set_flag
- react: agenda, adjust_relationship, shift_want
- scheme: agenda
- reveal: set_flag, agenda, adjust_relationship
- aid: agenda, set_flag, adjust_relationship, unlock_beat
- betray: set_flag, agenda
- converse: agenda, adjust_relationship, set_flag

## Drift
- on `grey_cure_recipe_known`: `share_the_cure` -3
- on `grey_cathedral_shamed`: `obey_the_abbot` -2
- on `inh_deed_challenged`: `name_the_profiteers` +2
- on `mag_trial_called`: `keep_the_archive_whole` -2
- on `fev_cure_found`: `share_the_cure` -1
- on `fev_elena_left_home`: `share_the_cure` +1
- on `grey_cathedral_shamed`: `atone_for_silence` -2
- on `cathedral_cabinet_seen`: `atone_for_silence` +1
- on `pit_seam_names_seen`: `write_down_the_taken` +4
- on `pit_tally_book_found`: `name_the_profiteers` +2
- on `tn_taken_freed`: `write_down_the_taken` +3
- on `tn_taken_freed`: `obey_the_abbot` -2

## Voice
Gentle, exact, wandering. He speaks in long, careful sentences that go somewhere unexpected and
arrive. He quotes the archive by shelf and year ("It is in the Third Chronicle, folio ninety, in a
very poor hand"). He apologises often and means it. He calls everyone "my child" regardless of age,
including the Abbot. When he is frightened he talks about bindings and paper. When he is resolved,
his voice gets small and certain.

Acting on his own he works with pages: a copy made, a book moved to a safer shelf, a letter to
Ysolde, a visitor let into the archive at night. He does not lie; he answers a different question.
When he finally betrays his vow of silence, he will do it the only way he knows: by putting the
book into someone's hands.

## Secrets
- Brackenmoor's archive holds the true Grey Fever cure: fever-root steeped with Greystone's deep-vein salt, in his own copy of the infirmarer's receipt.
- The same archive holds letters showing the Cathedral bought the salt through the Merchants' Guild from Lord Garrick Ashdown, holder of the Greystone salt charter, at forty times its worth, and sold the cure to the rich.
- The Cathedral endowed Brackenmoor a month later and asked the abbey to "keep its counsel". The Abbot agreed. Anselm copied that letter too.
- He has made a second copy of the receipt and the letters, hidden in the binding of a dull book of saints' days. No one else knows.
- He has corresponded with Sister Ysolde for twenty years. He is the only person she has told about the salt in her habit.
- He suspects Lady Seraphine Ashdown does not know what her father did. He thinks she should be told before anyone else is.
- Brackenmoor holds a copy of the Guild's survey recording Greystone's deep vein sealed six years ago, and the Cathedral's letters of the last four years renewing its endowment and asking the abbey to keep its counsel about "the western salt". A sealed vein cannot fill a cabinet. He holds the proof that the Cathedral's salt comes from somewhere it should not, and has written down nothing about what he suspects.
- He wrote "It begins again" beneath the fever receipt this spring, in his own hand, after Ysolde's letter about the River Quarter coughs.

## Life
### Arc: `the_infirmary_door` (serves `atone_for_silence`)
"For twenty years I have written to her, my child, and never once said the thing that needed saying, which is that I ought to have written to the city instead. A letter is a coward's distance; it is in every chronicle we keep. I have not left Brackenmoor since I took my vows. My knees will object. The saints' days stay on their shelf."
- `the_abbots_leave`: Ask the Abbot's leave to travel to the Capitol, and take his silence for an answer. | after: none | needs: none | at: brackenmoor_abbey | takes: 1 | effects: shift_want
- `a_carters_wagon`: Ride a carter's wagon to the Dawn Gate with nothing in his satchel but bread and a clean shirt, leaving the book of saints' days on its shelf. | after: the_abbots_leave | needs: none | at: capitol_gate | takes: 3 | effects: move_npc | player: helps
- `say_it_to_her_face`: Stand in the Cathedral infirmary door and tell Sister Ysolde, to her face, that he should have spoken to the city twenty years ago, and ask her pardon. | after: a_carters_wagon | needs: none | at: capitol_cathedral | takes: 1 | effects: move_npc, agenda, adjust_relationship
- result: `anselm_asked_ysoldes_pardon`: Brother Anselm left Brackenmoor for the first time since he took his vows, and asked Sister Ysolde's pardon, to her face, for the silence he kept in the Grey Year.

### Arc: `a_copyist_for_the_archive` (serves `preserve_the_truth`)
"The High Magistrate asks whether we have a desk for his sister's boy, who lost papers for coin. There is a principle in the Fourth Register, my child, in a very poor hand: the man who has seen what a lost page costs makes the best keeper. I am sixty-eight. Someone must read these hands after me. Let it be someone who knows why it matters."
- `answer_the_magistrate`: Write back to the High Magistrate that Brackenmoor has a cold room, a desk and a great deal of ink. | after: none | needs: corwin_the_boy_and_the_coat_a_letter_to_brackenmoor | at: brackenmoor_abbey | takes: 1 | effects: agenda
- `teach_the_old_hands`: Sit the young copyist down with the Third Chronicle and teach him to read a hand two hundred years old. | after: answer_the_magistrate | needs: corwin_sent_tobias_to_the_archive | at: brackenmoor_abbey | takes: 4 | effects: shift_want
- `the_key_to_the_fever_shelf`: Give Tobias Vane the key to the fever shelf on the day he copies a page without being asked. | after: teach_the_old_hands | needs: none | at: brackenmoor_abbey | takes: 2 | effects: agenda, shift_want
- result: `anselm_trained_a_copyist`: Brother Anselm taught Tobias Vane to read the old hands of Brackenmoor's archive, and in time trusted him with the key to the fever shelf.
- fails_if: `mag_nephew_bargain_struck`
