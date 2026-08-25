extends RefCounted

## Deterministic entity id for the local player as a real emergence-substrate
## party -- docs/concept/player_citizenship.md's "no player concept exists
## today" gap. Single local player only for this pass (no multiplayer
## per-connection identity yet -- see player_citizenship.md's own open
## questions).

const PLAYER_ENTITY_ID := "player:local"
