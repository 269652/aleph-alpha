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

### Current implementation status (divergence note)

What exists today (see `docs/progress.md`'s Fishing section for the full
breakdown) is a first **visual/gameplay layer**, not yet the aquatic
ecosystem sim this doc specs: ocean tiles spawn deterministic, capped,
idle-swimming `FishMarker` entities in one of 4 hand-authored species
(`ProceduralFishSprite`), catchable via the existing active minigame
(`fishing_session.gd`/`fishing_minigame.gd`). Species is a per-tile
deterministic pick, not DNA/phenotype-driven, and there's no aquatic
population sim (reproduction/migration/death) behind it yet — closer to
`CreatureRenderer`'s decorative promotion layer than to
`EcosystemSimulation`. A rare/legendary catch now becomes its own item
(`rare_fish`/`legendary_fish`, not just the generic `fish`) and grants a real
timed buff on eating (extra stamina regen / melee damage, see
`FoodConsumption.FISH_BUFFS`) — the rarity roll finally survives past the
catch instead of only affecting reward quantity, though it's still a
per-tile deterministic pick, not DNA/phenotype-driven. Catching a real
nearby fish also removes it visually and names its species in the message.
Everything else this doc specs (full DNA/evolution reuse, sexual selection,
rare-phenotype desirability, bait-driven targeting, taming/companion fish)
is still open, unstarted work.

### Open questions

- Does the aquatic sim run at the same fidelity as land (full regional
  aggregate + promotion-to-individual-agents near the player), or a lighter
  weight model given water covers a smaller fraction of active play space?
- Bait/lure system depth — does bait choice meaningfully bias which species/
  quality you can hook, giving skilled fishing real strategy?
- Saltwater/ocean vs. freshwater ecosystems as distinct populations, or one
  unified aquatic model to start?
