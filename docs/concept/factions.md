## Factions & settlement reputation

[npc.md](npc.md) gives individual NPCs real relationships and memory, but
nothing above that per-NPC level. Rather than bolting on a separate,
classic MMO faction-rep bar, settlement-level reputation is **emergent**:
a settlement's overall attitude toward a player is an aggregate of its
individual NPCs' actual relationship/memory state, not a hidden number of
its own.

- **Consistent with the whole NPC system's philosophy**: nothing here is
  hand-scripted. If you've helped enough individual villagers, the village
  as a whole treats you better — hiring is easier
  ([npc.md](npc.md#hiring--instruction)), quest offers skew friendlier,
  prices may soften (see [economy.md](economy.md)) — because that's the
  honest sum of real, legible relationship state, not a separate meter
  going up.
- **A settlement can still be legible as a unit** (a name, a rough
  "how do they feel about me" summary a player can check) — it's a
  *presentation* layer/aggregation function over NPC state, not a claim
  that no faction-level concept exists at all.
- **Foundation for player factions later.** Once [multiplayer](../roadmap.md)
  lands, player-formed groups (guilds/settlements) can plug into the same
  aggregation model — a player faction's standing with an NPC settlement is
  just the aggregate of its members' individual relationships, keeping one
  consistent reputation model instead of a second, parallel one for
  player-vs-player-group politics.

### Open questions

- Aggregation function — simple average of relationship scores, weighted by
  the NPC's social influence/role in the settlement (the blacksmith's
  opinion matters more than a random farmer's?), or something else?
- Does reputation ever propagate *between* settlements (word travels), or
  is every settlement's opinion of you independently earned?
