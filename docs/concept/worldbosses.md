## World bosses: emergent apex predators

[evolution.md](evolution.md)'s fitness/rarity system already implies this —
formalizing it: the population/fitness simulation itself, not a scripted
spawner, occasionally produces a genuinely exceptional individual that
becomes a real world-boss-tier threat. See
[flora.md](flora.md#ancient-trees-emergent-legendary-flora) for the same
emergent-threshold pattern applied to flora instead of fauna — an ancient
tree is the non-combat, non-fauna equivalent of a world boss.

- **Emergent, not placed.** No hand-designed "boss room." An individual
  animal that has, through the ordinary sexual-selection/fitness sim
  ([evolution.md](evolution.md)), accumulated an extreme combination of
  fitness traits (age, size, combat stats, survived-many-generations
  lineage) crosses a threshold and becomes a named, unique, world-boss-tier
  creature — an ancient boar, an apex wolf that's outlived and outfought
  its whole pack. Monster Hunter apex / ARK Alpha energy, but the result of
  the same simulation that makes ordinary boars boars, not a separate
  system bolted on top.
- **Unique per world.** Because it's emergent from that world's actual
  population history, no two servers/save-files produce the same world
  boss at the same time or place — a genuinely unique, discoverable event
  rather than a fixed encounter every player eventually sees.
- **Real stakes both ways.** A world boss is both a major threat (very
  dangerous fight, real use for [combat.md](combat.md)'s tactical layers)
  and a major opportunity: best-in-slot [crafting.md](crafting.md)
  materials, and — per [pets.md](pets.md)'s DNA-sets-quality model — a
  tempting, high-risk taming target for a Beastmaster with the skill to
  attempt it, since a world boss's DNA is by definition exceptional.
  Killing it removes an extreme outlier from the breeding population
  ([evolution.md](evolution.md)'s phenotype-target drift applies here too:
  taking out the most-fit individual measurably affects the species going
  forward), taming it keeps that same genetic outlier in play as a
  companion instead.

### Encounter design: emergent stats + physics spectacle + prebaked authored phases

Resolves the open "special AI/behavior" question below with a specific
mechanism, decided in a 2026-07-16 brainstorm crossing this design against
WoW's raid-boss encounter language:

- **The fight is genuinely emergent, not scripted, at the base layer.** A
  world boss runs the exact same creature-AI and physics systems
  ([materials.md](materials.md)) as every other creature — its outlier stats
  (mass, speed, damage) just push those systems to extremes it alone reaches
  (shockwaves on impact, terrain cratering under its weight, momentum most
  creatures never generate). Nothing here is boss-specific code.
- **On top of that, one prebaked LLM authoring pass gives it real "encounter"
  texture.** The instant the fitness sim promotes an individual to
  world-boss status, an LLM is called **exactly once, offline** — never live
  during the fight, matching this project's NPC-planner architecture
  ([npc.md](npc.md): the LLM plans, an FSM executes with zero further calls)
  — with a natural-language description of that specific individual's
  emergent traits (species, size, age, lineage, temperament, notable
  mutations). It returns a small set of **telegraphed phase
  abilities/thresholds**, baked into that boss's data at promotion time. The
  result reads as a designed encounter (a real "phase 2 at 50% HP" moment)
  without a human ever hand-authoring it and without any inference cost
  during play.
- Net effect: three layers compose into one fight — real emergent stats,
  real emergent physics spectacle from those stats, and a thin authored-feeling
  telegraph layer generated once per unique boss. See
  [synthesis.md](synthesis.md) for how this mirrors the project's general
  "compose primitives, let simulation (or a one-shot LLM authoring pass)
  resolve the result" pattern.

### Era-gated bosses

A signature world boss can also gate an [era](eras.md) transition rather than
(or in addition to) a zone: defeating the right emergent apex individual is
one of the triggers that lets a reincarnating character (or, per
[eras.md](eras.md)'s open per-player/per-server question, the whole world)
advance to the next technological age. This keeps era transitions from being
a pure timer/milestone checklist — the last age's defining threat has to
actually fall first.

### Village endangerment: an attractor, not a spawner

Resolves the "server-wide visibility/tracking" open question below
(2026-08-13 design pass): a settlement's own net worth and population raise
the local odds this promotion threshold gets crossed nearby in the first
place — feeding as additional "opportunity biomass" into the same local
carrying-capacity term `predator_population_model.gd` already derives from
prey density, not a bespoke boss-seeks-village targeting system. Defender combat strength deliberately does not feed that
likelihood, only the outcome once a threat exists — a well-guarded
settlement isn't statistically punished for being well-guarded. Discovery
itself is both signaled (a real-time rumor from an endangered NPC's
need-threshold crossing, per [npc.md](npc.md)'s replan-interrupt
architecture, while the settlement's chunk is loaded) and sometimes purely
incidental (an unloaded settlement's whole threat-to-outcome arc can resolve
via catch-up simulation with zero warning). Full mechanism, including how
the quest itself is offered and what a settlement's success/failure
actually changes, in [quests.md](quests.md#village-endangerment-the-attractor-mechanism).

### Open questions

- Exact fitness-threshold/rarity math for when the sim promotes an
  individual to world-boss status — needs numeric design once the base
  fitness/rarity system ([evolution.md](evolution.md)) has real numbers.
  The wealth→opportunity-biomass conversion above needs the same numeric
  pass, as a further input to the same open question.
- Exact cost/latency budget for the one-time promotion-triggered LLM call,
  and what the fallback behavior is if that call fails (a boss should never
  fail to spawn just because an API call did).
