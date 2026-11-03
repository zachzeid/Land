# SOUL: Bjorn (emergence fixture)
npc: bjorn
npc_id: bjorn_blacksmith_001

## Essence
Emergence fixture soul. A smith.

## Wants
- `honest_steel` (9): Every blade bearing his mark must be forged true.

## Agency
- react: agenda

## Voice
Few words.

## Life
### Arc: `true_blade` (serves `honest_steel`)
One blade he is proud of.
- `fold_iron`: Fold the iron by lamplight, alone. | after: none | needs: none | at: any | takes: 3 | effects: shift_want
- result: `bjorn_true_blade_forged`: Bjorn forged a blade he was proud to put his mark on.
