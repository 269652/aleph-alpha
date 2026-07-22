## Cooking

[farming.md](farming.md), [fishing.md](fishing.md), and hunting all produce
ingredients, and [survival.md](survival.md) covers eating — cooking is the
system that turns raw production into a real payoff, BOTW-style.

- **Dishes grant real temporary buffs** on top of restoring hunger —
  stamina regen, cold/heat resistance, damage boost, faster health
  regen — not just a bigger hunger number than the raw ingredient.
- **Ingredient quality carries through.** The same DNA-quality → output-
  quality link [crafting.md](crafting.md) establishes for materials applies
  here: a dish made from high-fitness/rare-phenotype ingredients (a
  legendary-tier farmed crop, a rare-DNA fish) produces a stronger or
  longer-lasting buff than the same recipe made from common ingredients.
- **Recipe discovery/composition** likely reuses [crafting.md](crafting.md)'s
  blueprint-DSL approach (base dish + ingredient inputs + seasoning
  modifiers → deterministic buff profile) rather than being a wholly
  separate recipe system — consistent with keeping "combine inputs
  deterministically" as one shared pattern across crafting, farming, and
  cooking.
- Gives [classes.md](classes.md)'s Herbalist and Artisan archetypes a
  natural specialization to lean into, and [housing.md](housing.md)'s
  festival/visitor moments (see [festivals.md](festivals.md)) a reason to
  involve food specifically.

### Buff slots: fixed, and typed by category

Resolves the buff-stacking open question below, decided in a 2026-07-16
brainstorm against Valheim's fixed-food-slot model: a player has a **small
fixed number of active food-buff slots** (Valheim-style), but each slot is a
**category** — e.g. *sustenance*, *resistance*, *combat* — rather than an
arbitrary stack of same-type buffs. Eating a second combat-category dish
replaces the first combat buff instead of stacking with it; eating a
resistance-category dish alongside it is fine, since it occupies a different
slot. Keeps the Zelda-style variety of individual dish effects while avoiding
both "just eat one food forever" (Zelda's actual problem) and "stack twenty
buffs at once" (freeform-stacking degeneracy).

### Open questions

- Exact category list and slot count — first-pass numeric design needed once
  the recipe/buff-type space (see below) has real entries.
- Do food buffs compete with potion/medicine buffs from
  [survival.md](survival.md)'s remedy system, or are those separate slots
  entirely?
- How large should the recipe/buff-type space be for a solo/part-time
  project to keep balanced and interesting without becoming unmanageable?
