## Crafting: blueprint DSL-lite

The base loop is Minecraft/Terraria-familiar: gather resources at/near
crafting stations, craft them into items, tools, and structures, with
stations and recipes gated behind [skill](skills.md) progression.

The twist: recipes aren't a fixed picklist. Crafting uses a small
**blueprint DSL** — much simpler than [magic.md](magic.md)'s spell DSL, but
the same underlying idea of small composable pieces instead of a static
menu. A blueprint is a base item template plus material inputs plus
modifier slots (grip, socket, coating, ...); the combination
**deterministically** produces the resulting item's stats — no random roll
on craft. Feed it an Iron base + a Leather grip modifier + a Ruby socket
modifier, get exactly the stats that combination implies, every time.

This makes crafted-item quality directly legible and optimizable, and gives
[dna.md](dna.md)'s creature-quality-rarity idea a second payoff beyond
taming: a hide harvested from a rare, high-fitness boar is a *better
material input* to the blueprint DSL than common boar hide, so hunting/
taming rare individuals feeds crafting power, not just pet collection.

See [items.md](items.md) for how this deterministic crafted-item track
relates to randomly-rolled found/looted gear — they're two complementary
sources feeding the same rarity/affix vocabulary, not competing systems.

### Open questions

- **How parts get surfaced** — half-answered by
  [emergent_crafting.md](emergent_crafting.md): the *part graph* a blueprint
  would compile to is now a real, tested model (parts as `(material, geometry,
  role)` nodes, typed joints as edges), so the target of the compilation exists
  even though the DSL that targets it does not. Whether the player manipulates
  that graph directly or authors intent that compiles to it is still open.
  **A text form that compiles to that graph now exists** —
  [standard_model.md](standard_model.md)'s `device` grammar's `part` and
  `joint` clauses — built for machines rather than for item blueprints;
  whether item blueprints reuse the same clauses is the remaining half of
  this question.
- Exact blueprint slot taxonomy (how many modifier slots per item category,
  what governs which modifiers are compatible with which base templates).
- ~~How station tiers gate blueprint complexity~~ — answered by
  [labor_skills.md](labor_skills.md#tiers): the station gates what's
  *possible* (which blueprint slots exist at all), the crafter's own labor
  skill tier gates how *well* whatever the station allows gets realized.
  Exact station-tier-to-slot-count numbers still need working out.
