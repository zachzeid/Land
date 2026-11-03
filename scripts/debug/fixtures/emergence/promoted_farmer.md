# SOUL: Tam the Farmer
archetype: valley_farmer
npc_id: gen_farmer_9

## Essence
A farmer who once shared bread with the stranger.

## Wants
- `buy_a_cow` (7): Save enough for a milk cow.

## Agency
- converse: agenda

## Life
### Arc: `cow` (serves `buy_a_cow`)
Tam has wanted a milk cow since he was a boy.
- `save_coin`: Put coins aside after market. | after: none | needs: none | at: any | takes: 1 | effects: shift_want
- result: `gen_farmer_9_cow_bought`: Tam bought a milk cow.
