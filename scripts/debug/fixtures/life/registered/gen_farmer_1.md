# SOUL: Tam the Farmer
archetype: farmer
npc_id: gen_farmer_1

## Essence
A farmer from {home}, already rolled: Tam saves every copper for a cow.

## Wants
- `buy_a_cow` (7): Save enough for a milk cow.
- `stay_out_of_trouble` (4): Keep his head down.

## Agency
- converse: agenda, set_flag

## Life
### Arc: `cow` (serves `buy_a_cow`)
- `save_coin`: Put coins aside after market. | after: none | needs: none | at: any | takes: 1 | effects: shift_want
- `the_cow`: Buy the cow at the gate market. | after: save_coin | needs: none | at: any | takes: 2 | effects: agenda
- result: `gen_farmer_1_cow_bought`: Tam bought a milk cow.
