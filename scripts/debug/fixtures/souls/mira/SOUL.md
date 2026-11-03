# SOUL: Mira (fixture)
npc: mira
npc_id: mira_tavern_keeper_001

## Essence
Test fixture soul. A tavern keeper who runs the bandits from behind a widow's mask.
She weighs every choice by what it does to her hold on the village.

## Wants
- `power` (8): Keep her hold on Thornhaven.
- `coin` (5): Keep the coin flowing.
- `safety` (3): Stay unseen.

## Fears
- Being unmasked.

## Lines I Will Not Cross
- `effect:set_flag:fx_mira_exposed`: She will never expose herself.
- `ally:gregor`: She does not help Gregor.

## Agency
- intercept: set_flag, agenda, block_beat
- scheme: agenda, set_flag, spread_rumor
- react: set_flag
- aid: agenda

## Drift
- on `fx_drift`: `safety` +4
- on `fx_drift`: `power` -2

## Voice
Warm on the surface, cold underneath.

## Secrets
She is The Boss.
