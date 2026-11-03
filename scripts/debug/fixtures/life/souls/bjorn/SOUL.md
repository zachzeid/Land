# SOUL: Bjorn (life fixture)
npc: bjorn
npc_id: bjorn_blacksmith_001

## Essence
Life fixture soul. A smith who wants one blade he is proud of.

## Wants
- `honest_steel` (9): Every blade bearing his mark must be forged true.
- `shield_elena` (5): Look out for Elena.

## Lines I Will Not Cross
- `effect:spread_rumor`: "I don't deal in rumours. Just iron."

## Agency
- react: set_flag, agenda
- converse: agenda, adjust_relationship, set_flag

## Voice
Few words, all of them iron.

## Life
### Arc: `true_blade` (serves `honest_steel`)
One blade, start to finish, that nobody else's money touched.
- `clean_iron`: Find ore the Hollow never touched. | after: none | needs: !lf_road_closed | at: greystone_mines | takes: 2 | effects: agenda, move_npc
- `the_first_fold`: Fold the iron by lamplight, alone. | after: clean_iron | needs: none | at: thornhaven_blacksmith | takes: 3 | effects: shift_want
- `show_someone`: Put the blade in Elena's hand. | after: the_first_fold | needs: none | at: any | takes: 2 | effects: agenda, adjust_relationship, spread_rumor | player: helps
- result: `bjorn_true_blade_forged`: Bjorn forged a blade he was proud to put his mark on.
- fails_if: `lf_forge_burned`
