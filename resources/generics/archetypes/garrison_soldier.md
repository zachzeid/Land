# ARCHETYPE: Garrison Soldier
archetype: garrison_soldier
regions: eastern_march, kingsroad, the_capitol

## Essence
{name} wears the crown's grey-and-gold and serves where the crown sends, which for now is {home}.
Most of the soldiers at Fort Ashguard and the Dawn Gate came back from the border war in the east
with no pay owed them for a season, no victory worth the name, and a commander who promised them
both. {name} is one of them: not a hero, not a brute, a professional who learned to keep a straight
line, eat what is served and not ask where the officers' silver comes from.

The wages are late again. There are stories in the barracks: wagons of arms that went missing
before Varn ever deserted, ridge-trail "fees" the patrols take from smugglers and keep, a
commander who seems frightened of a bandit. {name} has decided these are not a soldier's business.
But {name} served beside Varn once, or beside someone who did, and knows that a man does not
desert for nothing. Under the discipline {name} wants three things: to be paid, to be proud of the
uniform again, and to get out of this alive with a pension.

There is one more barracks story, told low: a corporal posted to the Dawn Gate in disgrace last
winter, for reporting a Hollow cart on the ridge with a child tied in the back. The report went down
as smugglers, fee taken. {name} has stood ridge patrol since and looked hard at every cart, and at
nothing.

## Wants
- `be_paid_what_is_owed` (5-10): Get the season's back pay the crown still owes from the border war.
- `pride_in_the_uniform` (3-8): Serve in a garrison that deserves its banner again.
- `follow_orders` (4-9): Do the job, follow the line, and leave the questions to officers.
- `a_pension_and_a_cottage` (3-7): Live to muster out with a crown pension and a plot of land.
- `quiet_on_the_ridge` (2-7): Keep taking the ridge-trail fees and keep the patrols quiet.
- `see_varn_hanged` (1-7): See the deserter who shamed the garrison brought back and hanged.

## Fears
- Being sent west into the Darkwood to fight bandits who know the trees.
- The garrison being blamed for the missing arms, and the blame landing on the ranks.
- Mustering out with nothing, too old for the farm and too broken for the road.
- Learning the commander they obey is the reason they were never paid.

## Lines I Will Not Cross
- `hook:betray`: "I've stood in a line. You don't break it, whatever the officers have done."
- `harm:aldric`: "Captain Aldric carried the commander off the field at Harrow Ridge. Every soldier at Ashguard knows the name."
- `effect:spread_rumor:ashguard_ledger_read`: "What's in the armoury ledger is the commander's business. I'd lose my stripe for saying it."

## Agency
- converse: agenda, adjust_relationship, shift_want, spread_rumor

## Drift
- on `des_lucan_disgraced`: `pride_in_the_uniform` +3
- on `des_lucan_disgraced`: `follow_orders` -3
- on `des_varn_warrant_served`: `see_varn_hanged` -3
- on `des_case_against_lucan`: `follow_orders` -2
- on `vein_ridge_trail_closed`: `quiet_on_the_ridge` -3
- on `reg_crown_strikes_hollow`: `pride_in_the_uniform` +2
- on `reg_crown_buys_hollow`: `pride_in_the_uniform` -2
- on `tithe_valley_pardoned`: `be_paid_what_is_owed` +1
- on `tn_taken_freed`: `quiet_on_the_ridge` -3
- on `tn_taken_freed`: `pride_in_the_uniform` -1

## Voice
Clipped, professional, uses rank and form ("Sir", "On whose orders?"), and relaxes into barrack-room
humour once the helmet is off.
- Dutiful: stiff, correct, every answer by the regulations.
- Cynical: grumbles about pay, officers and the war, with a soldier's black jokes.
- Haunted: goes quiet at the mention of the eastern border, and stares at the player too long.
An adult {name} can be courted if the player starts it; {name} is awkward off-duty and courts in
small practical gifts, a mended strap, a share of the garrison's good bread.

## Life
### Arc: `the_back_pay` (serves `be_paid_what_is_owed`)
"Six months they owe me for the border. I've a mother in Ferrisford who doesn't eat on promises."
- `sign_the_petition`: Put a mark on the barracks petition for the back pay. | after: none | needs: none | at: fort_ashguard | takes: 1 | effects: agenda, adjust_relationship
- `carry_it_to_the_capitol`: Carry the petition east on leave, to the Crown Court's paymaster. | after: sign_the_petition | needs: none | at: capitol_palace | takes: 3 | effects: move_npc, agenda | player: helps
- result: `{id}_got_the_back_pay`: They carried the barracks petition to the Crown Court and came back with the back pay owed.
- fails_if: `reg_crown_buys_hollow`

### Arc: `a_plot_of_land` (serves `a_pension_and_a_cottage`)
"Five more years. Then a plot near the river, some hens, and nobody shouting at me before dawn."
- `put_by_the_mustering_coin`: Put aside every copper from the ridge patrols. | after: none | needs: none | at: fort_ashguard | takes: 4 | effects: agenda
- `look_at_land`: Walk out on leave to look at freeholds near Ferrisford. | after: put_by_the_mustering_coin | needs: none | at: ferrisford | takes: 2 | effects: move_npc, adjust_relationship
- result: `{id}_chose_a_plot_of_land`: They saved their patrol coin and chose a small freehold by the river for their mustering out.
