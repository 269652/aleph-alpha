# Ecosystem Dynamics

This doc specifies the living-ecosystem simulation: how plants fruit, how that
fruit feeds animals, how animal populations grow and prey on one another, and
how all of this is computed at two fidelities — **individual agents** on-screen
near the player, and a cheaper **aggregate catch-up** for chunks the player
isn't looking at. Every rule below is deliberately grounded in a real-world
ecological mechanism so the world behaves plausibly rather than arbitrarily.

## Design pillars

1. **Real mechanisms, not scripted spawns.** Fruit appears because trees are in
   their fruiting phase, not because a timer drops loot. Boars are where boars
   thrive. Populations rise and fall from births, deaths, predation, and food —
   the same feedback loops that govern real ecosystems.
2. **Two fidelities, one truth.** What the player can see runs at individual-agent
   fidelity (each ripe fruit is a pixel, each animal a node making its own
   decisions). What the player can't see runs as an aggregate per-chunk integration
   that is *catch-up integrated* the moment the player returns, so a region the
   player left evolves believably instead of freezing or resetting.
3. **Determinism.** Both fidelities are seeded/deterministic so a region looks
   the same on revisit given the same elapsed time — no divergence between the
   two representations beyond intended stochastic variation.

## Plant phenology (fruiting)

Real fruit trees move through phenological stages: flowering → fruit set →
green (immature) fruit → **ripening** → **abscission** (ripe fruit detaches and
falls) → decomposition. We model a simplified version per tree, driven by the
tree's own DNA (`TreeGenome.fruit_yield` sets its potential crop; `species_bias`
sets fruit-vs-nut lean) and its local climate (warmer/wetter → faster ripening,
matching growing-degree-day phenology).

Per-tree state over elapsed time yields three counts:

- **Growing** — immature fruits still developing on the tree (not yet edible).
- **Ripe** — mature fruits still hanging (edible; **rendered as individual
  pixel dots on the canopy**). Capped by the tree's `fruit_yield` crop potential.
- **Fallen** — ripe fruits that have abscised and dropped to the ground this
  step (become ground-item `fruit`/`nut` drops that animals and the player can eat).

Ripening rate and the fall (abscission) threshold are tuned constants pinned by
tests, not eyeballed. A tree that has just dropped its crop re-enters the growing
phase (a new fruiting cycle), so trees fruit repeatedly over time — like a real
seasonal bearing cycle compressed to the game's timescale.

## Frugivory and seed dispersal

Fallen fruit is food. Herbivores (and omnivores like boars) that pass within
eating range of a fallen fruit consume it, gaining body condition (energy). This
is the frugivory half of a real seed-dispersal mutualism: the plant trades food
energy for having its seeds carried and its offspring fed. (Seed dispersal by
animals — a moved-and-deposited seed germinating elsewhere — is a documented
future extension; today fruit simply feeds animals and drives their condition.)

## Animal bioenergetics and reproduction

Real animals only reproduce when their body condition supports it — starving
animals don't breed. Each creature carries an **energy/condition** value that:

- **rises** when it eats (fallen fruit, grazing, or — for predators — prey),
- **decays** slowly over time (basal metabolism),
- and **gates reproduction**: a creature reproduces only when it is both
  **healthy** (high health fraction) and **well-fed** (energy above a threshold),
  and then only after a **refractory cooldown** (real inter-birth interval).

When those conditions are met near the player, the individual creature spawns an
offspring beside it (individual-scale birth), paying an energy cost. Away from
the player the same effect is captured by the aggregate logistic growth term.

## Population dynamics (aggregate)

At the aggregate (per-chunk) level we use the classic ecological equations:

- **Logistic growth** for herbivores toward a vegetation/water-derived carrying
  capacity `K`: `dN/dt = r·N·(1 − N/K)`. Growth is fastest at intermediate
  density and stalls as the region fills up — real density dependence.
- **Lotka–Volterra-style predator–prey coupling**: predator carrying capacity is
  derived from prey abundance (a trophic-pyramid ratio), so predators lag and
  track their prey; over-predation depresses prey, which then depresses predators,
  which lets prey recover — the canonical oscillation.
- **Fruit stock** accumulates on the region's trees over elapsed time (aggregate
  of the per-tree phenology) and is drawn down by herbivore consumption, coupling
  the plant and animal layers.

These already exist for *loaded* chunks (`ecosystem_simulation.gd`,
`herbivore_population_model.gd`, `predator_population_model.gd`). This doc adds
the *unloaded* case.

## Variable-fidelity simulation (LOD)

The world is far too large to simulate every chunk every frame. So:

- **Loaded chunks (near the player)** run at **individual fidelity**: real tree
  nodes with per-tree fruiting and visible pixel-dot fruit, real creature nodes
  making per-agent decisions (flee/hunt/graze/eat/drink/reproduce). This is the
  "happens right on the scene" layer.
- **Unloaded chunks (away from the player)** are *not* ticked continuously.
  Instead each chunk records the world-time at which it was unloaded, and on
  reload a **catch-up integration** advances its aggregate state (vegetation
  regrowth, accumulated fruit stock, herbivore logistic growth, predator–prey
  coupling) by the elapsed unloaded duration in one step. The region the player
  returns to therefore reflects everything that "would have happened" while they
  were away — trees have fruited, herds have grown or been thinned by predators —
  without paying per-frame cost for unwatched chunks.

This catch-up is the honest, bounded version of a full always-on planetary
simulation: correct in aggregate, deterministic, and O(chunks-revisited) rather
than O(all-chunks-per-frame).

## Status / mechanisms

- ✅ Logistic herbivore growth, predator–prey capacity coupling, per-loaded-chunk
  ecosystem step (pre-existing).
- 🚧 Per-tree fruit phenology (growing/ripe/fallen) — `fruiting_model.gd`.
- 🚧 Ripe fruit rendered as canopy pixel dots on near trees.
- 🚧 Condition-gated individual reproduction — `animal_reproduction.gd`.
- 🚧 Unloaded-chunk catch-up integration — `chunk_ecology_catchup.gd`.
- ⬜ Animal-mediated seed dispersal (moved seeds germinating elsewhere).
- ✅ Seasonal forcing of phenology by a real calendar/season variable —
  `season_cycle.gd` scales fruiting warmth (see [seasons.md](seasons.md)).
