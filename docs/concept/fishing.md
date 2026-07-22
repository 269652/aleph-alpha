## Fishing & aquatic ecosystem

[world.md](world.md)'s hydraulic-erosion pass carves real rivers and lakes,
but nothing lives in them yet. Fishing gives water a gameplay reason to
exist, and does it by **reusing the land ecosystem/evolution simulation**
rather than building an unrelated bolt-on minigame.

- **Aquatic creatures run the same sim as land animals.** Fish and other
  aquatic life follow [world.md](world.md)'s population model (reproduction/
  migration/death driven by local conditions — here, water
  quality/temperature/food density instead of vegetation/water access) and
  [evolution.md](evolution.md)'s full DNA/phenotype/sexual-selection
  machinery. A rare-phenotype fish is exactly as desirable to catch as a
  rare-phenotype boar is to tame.
- **Catching is an active minigame** (BOTW/Stardew-style skill check —
  timing, tension, bait choice) layered on top of the underlying sim, not a
  replacement for it: what fish are even available to catch at a given spot
  is determined by the aquatic population sim, not a fixed loot table.
- **Feeds the same production chain** as farming/hunting — caught fish are
  [cooking.md](cooking.md) ingredients and [crafting.md](crafting.md)
  material inputs, with the same DNA-quality → material-quality link.
- **Beastmaster/Herbalist crossover**: can a sufficiently rare/high-fitness
  fish be *tamed* rather than caught (a companion fish in a pond, or an
  aquatic mount)? Open question, but consistent with
  [pets.md](pets.md)'s species-sets-category/DNA-sets-quality model if so.

### Open questions

- Does the aquatic sim run at the same fidelity as land (full regional
  aggregate + promotion-to-individual-agents near the player), or a lighter
  weight model given water covers a smaller fraction of active play space?
- Bait/lure system depth — does bait choice meaningfully bias which species/
  quality you can hook, giving skilled fishing real strategy?
- Saltwater/ocean vs. freshwater ecosystems as distinct populations, or one
  unified aquatic model to start?
