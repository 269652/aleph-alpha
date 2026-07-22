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

### Open questions

- Rate of phenotype-target drift — fast enough to feel responsive to player
  hunting/taming pressure within one play session's timescale, without
  making species identity feel unstable.
- How many phenotype dimensions (color, size, pattern, ...) are worth
  simulating per species vs. flattening into a simpler score.
