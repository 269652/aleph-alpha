## Evolution

An evolutionary system based on DNA, reproduction, and selection criteria —
NPC animal populations evolve and reproduce like real ones. Reproduction is
constrained by local resources: food, water, natural predators, and climate
(see [world.md](world.md)'s ecosystem sim, which this plugs directly into).

### Phenotypes and sexual selection

Animals exhibit a phenotypical "look" deterministically generated from
genetics ([dna.md](dna.md)). Mate choice is driven by a real scoring
mechanic, not flat rarity:

- **Each species has an evolving "attractive phenotype target"** — an ideal
  point in phenotype-space (color saturation, size, symmetry, etc.) that
  itself drifts slowly over generations, driven by which individuals
  actually bred successfully. An individual's mate-attractiveness score is
  its distance from that current target, not a fixed rarity-tier lookup.
- This is what makes the core "tame the rare boar → it gets rarer in the
  wild" pillar a literal simulation outcome rather than narrative flavor:
  removing high-scoring individuals from the breeding population measurably
  shifts which phenotypes propagate, and the target itself can drift in
  response over time.
- **Player-facing payoff**: the same phenotype distinctiveness that drives
  in-sim mate selection is what makes a rare-colored/rare-shaped individual
  visually stand out and desirable to players — one underlying system
  serves both the ecosystem simulation and the "ooh, a shiny boar" instinct,
  deliberately mirroring Pokémon's shiny-hunting appeal but with the rarity
  being emergent from population dynamics instead of a fixed spawn roll.

### DNA, fitness, and attributes

DNA also determines non-visual attributes and overall fitness — some
individuals are simply stronger, faster, or hardier than the population
average, independent of how attractive their phenotype is. See
[pets.md](pets.md) for how this fitness dimension carries over into a
tamed animal's functional performance, not just its looks, and
[worldbosses.md](worldbosses.md) for what happens when this fitness
dimension hits an extreme outlier. [fishing.md](fishing.md) and
[farming.md](farming.md) apply this same DNA/fitness/selection model to
aquatic life and crops, respectively.

#### Bloodlines: a real genome, not a re-rolled spawn (mechanism spec)

Compiled from a design-brainstorm session. Today this section's own claims
are aspirational, not real: an animal birth (`animal_reproduction.gd`) is
gated purely on energy/health/cooldown and produces an offspring with **no
genome at all** — nothing is crossed, nothing mutates, nothing to select
for. This closes that gap by reusing infrastructure this project already
built and proved for a different population entirely:
[npc.md](npc.md)'s own NPCs already cross two parents' continuous genes
plus a small mutation chance (`npc_genome.gd`, `dna_crossover.gd`) — real
quantitative-genetics blending inheritance, not an invented mechanic. An
`AnimalGenome` mirrors that exact shape (continuous 0..1 genes: speed,
size, coat_saturation, fertility, disease_resistance) and every
individual-scale birth — a wild pairing near the player, or a deliberate
[pets.md](pets.md) breeding-pen pairing — calls the SAME, already-built
`dna_crossover.gd.crossover()` on the two parents' genomes. Zero new
crossover mechanism, only a new struct and one more real call site.
Real-world grounding: this is literally how real selective breeding
works — an estimated breeding value from measurable parent traits, not a
black-box "breeding chance" roll — the actual reason two fast, hardy tames
produce a foal that measurably outperforms either parent, and why a bad
pairing can just as really produce a worse one.

### Herd social structure and behavioral realism (mechanism spec)

Compiled from the same design-brainstorm session as Bloodlines above —
real ethology beyond the existing per-individual flee/hunt/graze decision
loop (`CreatureBehavior`), which today treats every animal as
independently reactive with no notion of a group at all.

- **Flushing the herd.** One individual noticing a threat and breaking
  into flight should be enough to spook same-species neighbors who never
  independently perceived anything — a same-species individual entering
  flee state broadcasts a short-lived alarm, readable by neighbors within a
  call radius LARGER than their own sense radius, who flee the alarmed
  animal's own heading without running their own threat check. Reuses
  [ecosystem_dynamics.md](ecosystem_dynamics.md)'s existing ramped
  acquire/decay pattern (already used for flee acquisition/release) for the
  alarm itself, rather than a new hard flag. Real grounding: the "many-eyes
  hypothesis" (Pulliam 1973) and real flight-contagion behavior in flocking/
  herding prey — vigilance is pooled across a real group, not scanned
  independently by each member, which is why a stalking predator (or
  player) that spooks one animal loses the whole herd, not just that one
  individual.
- **Night shift.** A per-species real activity-window table (beside
  `creature_info.gd`'s existing diet/temperament tables) scales each
  species' hunt/wander/bed-down drive by real time-of-day — deer bedding
  down at night, wolves shifting toward nocturnal activity, small prey
  emerging after dark — reading `solar_position.gd`'s already-real
  time-of-day data (`SolarPosition.elevation_degrees` / `local_hour`, the
  same real-astronomy source the lighting and the HUD clock already share),
  which today drives lighting but no creature behavior at all. Ramped against time-of-day, never switched, the
  same "thresholds are ramps or hysteresis, never hard switches" rule
  governing every other behavior gate in `ecosystem_dynamics.md`. Real
  grounding: real crepuscular/nocturnal/diurnal activity partitioning —
  species stagger their active hours specifically to minimize overlap with
  their own predators' or competitors' activity windows, not a flat
  day/night multiplier on the same behavior.
- **The herd has a boss.** This doc's own "mate choice is a real scoring
  mechanic, not flat rarity" pillar above is missing its actual selection
  PRESSURE: today mate pairing is same-species/nearby/coin-flip, with zero
  fitness weighting. A composite dominance score (body condition/energy +
  health fraction + the Bloodlines fitness gene above — no new stat) ranks
  individuals within a local cluster; the top-ranked gets first pick at
  `GrazerForaging`'s best bite (subordinates displaced to lesser forage)
  and priority access during a mating window, so it's the dominant
  individual's own genome that actually propagates and pulls the
  phenotype-target's drift, not a coin flip. Real grounding: real linear
  dominance hierarchies in herd/pack social structure (fallow-deer stag
  contests, horse-herd "boss mare" ranking) where rank tracks body
  condition and produces real reproductive skew — dominant individuals
  really do sire disproportionately more offspring.

### Status

- ⬜ Everything above (Bloodlines and herd social structure alike) — design
  spec only, not yet implemented. `dna_crossover.gd`, `ecosystem_dynamics.md`'s
  ramped-threshold pattern, and `solar_position.gd`'s real time-of-day data
  are all real and already proven elsewhere; nothing here needed a new
  mechanism invented, only new callers of what already exists. (This bullet
  previously cited `world_clock.gd`/`sunlight_model.gd` as "proven
  elsewhere"; that was false — `world_clock.gd` was referenced only by its
  own test and has been deleted as dead code, and `sunlight_model.gd` is
  unreferenced outside its own test too.)

### Open questions

- Rate of phenotype-target drift — fast enough to feel responsive to player
  hunting/taming pressure within one play session's timescale, without
  making species identity feel unstable.
- How many phenotype dimensions (color, size, pattern, ...) are worth
  simulating per species vs. flattening into a simpler score.
- Whether a settled dominance hierarchy persists as real per-individual
  state across a chunk unload/reload, or re-derives itself fresh from
  current condition each time a cluster re-forms — the latter is simpler
  and matches this project's existing precedent for ephemeral per-chunk
  sim state, but the former would let a long-reigning "boss" feel like a
  real, trackable individual across sessions.
