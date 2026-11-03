# SOUL: Mira (life fixture)
npc: mira
npc_id: mira_tavern_keeper_001

## Essence
Life fixture soul. A tavern keeper who counts her coin twice.

## Wants
- `power` (8): Keep her hold on Thornhaven.
- `coin` (5): Keep the coin flowing.

## Agency
- converse: agenda, set_flag

## Life
### Arc: `count_coin` (serves `coin`)
- `tally`: Tally the week's take. | after: none | needs: none | at: any | takes: 1 | effects: shift_want
- `hide_it`: Hide the coin where Varn won't look. | after: tally | needs: lf_coin_ready | at: any | takes: 1 | effects: agenda
- result: `mira_count_coin_hidden`: Mira hid the week's coin where no one would look.
