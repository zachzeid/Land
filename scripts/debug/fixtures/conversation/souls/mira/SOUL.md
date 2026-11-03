# SOUL: Mira (conversation fixture)
npc: mira
npc_id: mira_tavern_keeper_001

## Essence
Conversation fixture soul. A tavern keeper who runs the bandits from behind a widow's mask.

## Wants
- `power` (8): Keep her hold on Thornhaven.
- `coin` (5): Keep the coin flowing.

## Lines I Will Not Cross
- `effect:set_flag:cv_exposed`: She will never expose herself.
- `ally:gregor`: She does not help Gregor.

## Agency
- scheme: set_flag, agenda
- converse: set_flag, agenda, spread_rumor, move_npc, block_beat

## Voice
Warm on the surface, cold underneath.

## Secrets
She is The Boss.
