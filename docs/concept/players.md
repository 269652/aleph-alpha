## Players: relationships, marriage, and children

A new unique player system: players can marry and have children. The child
becomes its own NPC, instructable by the parent through the
[NPC DSL](npc.md#ai-native-npcs) — a genuinely inheritable, ongoing
relationship rather than a one-off flavor event.

- **Solo-playable now, not gated on multiplayer.** Since MVP is
  single-player (see [overview.md](overview.md)), a player can marry an
  eligible NPC citizen and have a child with them today — this doesn't need
  to wait for [Phase 5+ multiplayer](../roadmap.md). Player-to-player
  marriage/reproduction is the same system, just unlocked once another
  player is a valid partner.
- **DNA inheritance**: a child's DNA is a genetic cross of both parents' DNA
  (see [dna.md](dna.md)) — stats, phenotype/looks, and class-resonance
  scores all derive from this cross, with a small mutation chance for a
  trait neither parent has. Two high-resonance-Mage parents are likely (not
  guaranteed) to produce a child who resonates with Mage too — this is
  where player-driven eugenics/breeding-for-traits becomes a real strategy,
  mirroring the wild-population selection pressure already described in
  [evolution.md](evolution.md), just applied to players' own lineage.

### Birth and the child life stage

Birth **fast-forwards straight to a usable age** — no simulated infancy/
toddler growth arc to build or maintain. The child spawns as a full
NPC-DSL character at a "Child" life stage: capable of basic activity and
dialogue, but not full adult stats, combat, or an unlocked skill tree yet.

### Sims-style needs minigame

While at the Child life stage, the child runs a deep Sims-inspired
simulation, not a shallow flavor stat:

- **Needs** (hunger, comfort, hygiene, fun, social) that decay over time and
  must be tended, same category of system as [survival.md](survival.md)'s
  player needs but framed as things the *parent* provides or teaches the
  child to provide for itself.
- **Wants/fears**, Sims "wish"-style: a rotating small set of desires (e.g.
  "wants a pet," "afraid of the dark," "wants to learn to fish") that, when
  fulfilled or ignored, shift the child's mood and personality traits over
  time — feeding into the same trait/personality model
  [npc.md](npc.md#ai-native-npcs) uses for its daily-planner NPCs.
- **Traits** solidify gradually from repeated want fulfillment/neglect
  patterns rather than being rolled once — a child who's consistently fed
  and played with trends toward positive traits; a chronically neglected
  one trends toward negative ones (clingy, resentful, fearful).
- **Consequences of neglect**: a sustained-unhappy child can run away
  (becomes a wandering NPC, relationship damaged but not necessarily
  unrecoverable) or, at the extreme, die. **Resolved**: a child's death does
  *not* cost the parent one of their own [nine lives](death.md) — the two
  systems stay decoupled — but it does apply a permanent debuff to the
  parent (grief), a lasting mechanical scar rather than a resource cost.
  Exact debuff shape TBD (stat penalty? capped max resource? something
  narrative-flavored like reduced NPC/hired-help trust?) — worth its own
  pass once the base needs/wants loop is built.

### Growing up

Once a child accumulates enough positive trait/relationship progress (exact
threshold TBD), it graduates to a full independent adult NPC — at that
point it's a normal instructable/hireable NPC per [npc.md](npc.md), just
one with a persistent relationship to its parent and inherited DNA.
