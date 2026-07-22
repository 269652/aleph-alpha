## Farming: crops get the same DNA treatment as animals

A Stardew/Harvest Moon-style farming loop (plant, tend, harvest), but
crops run through the **same DNA/phenotype simulation** as wild animals
([evolution.md](evolution.md), [dna.md](dna.md)) instead of being a
separate, simpler system — "life" is simulated consistently across flora
and fauna, not just for the parts of the world that walk around. More
specifically, crops share **one DNA model** with [flora.md](flora.md)'s
wild-plant/seed-dispersal system, not a lookalike parallel one — see below.

- **Crops have genetics.** Yield, growth speed, disease resistance, and
  flavor/quality are all DNA-driven traits, common → rare → legendary tier
  like everything else in this vocabulary.
- **Selective breeding is real strategy**, not flavor: cross-pollinate/
  cross-breed two high-quality plants to bias offspring traits, same
  genetic-cross-plus-mutation-chance model as
  [players.md](players.md)'s child inheritance. A rare crop strain (a
  legendary-tier tomato line, say) becomes a genuine collecting/breeding
  hook, exactly like a rare-phenotype boar.
- **Feeds the shared production chain.** Harvested crops are
  [crafting.md](crafting.md) blueprint inputs and [cooking.md](cooking.md)
  ingredients (quality of ingredient affects quality of output, same
  DNA-quality→material-quality link [crafting.md](crafting.md) already
  establishes for animal-sourced materials).
- **Plugs into the world sim, doesn't fork it.** A farm plot is a
  player-managed override of [world.md](world.md)'s vegetation-density
  cellular-automaton model — tilling/watering/fertilizing a cell locally
  raises its carrying capacity above what the wild simulation would produce
  there, rather than farming being a wholly separate mechanic layered on
  top of unrelated terrain.

### Resolved: farmed and wild genetics are one shared model

See [flora.md](flora.md) — a discarded/escaped farm seed can establish as
a wild plant carrying cultivated traits, and a wild plant with an
unusually good trait roll is legitimate starting stock for domestication.
Farming and [flora.md](flora.md)'s wild seed-dispersal/coevolution system
are two access points into the same population, the same relationship
taming has to the wild animal population.

### Open questions

- Cross-breeding UI/mechanic — how does a player actually select and pair
  two plants, and how visible is the resulting trait math (fully
  Mendelian/transparent vs. some hidden-info discovery play, à la Stardew's
  opaque quality-upgrade system)?
- Seasonal crop viability — ties into [weather.md](weather.md)'s season
  system once that's built out.
