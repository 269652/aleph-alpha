# Smelting & Metalworking

The bridge from raw mined **ore** to worked **metal gear**. This is the concrete
first rung of [materials.md](materials.md)'s mineral track ("metal, stone, ore")
and slots into [crafting.md](crafting.md) as a heat-gated recipe category: the
tech step that lifts the player out of the stone-and-bone tier into iron tools,
weapons, and armor.

## Design pillars

1. **Ore is not usable raw — it must be smelted.** Real metallurgy: ore + a
   reducing **fuel** (charcoal/coal) + sustained **heat** yields metal. Mining
   gives you `iron_ore`/`copper_ore`; you can't wear or wield those — you smelt
   them into `iron_ingot`/`copper_ingot` first. This makes fuel and a heat
   source genuinely valuable, and gives coal a purpose beyond a black rock.
2. **Heat-gated, like cooking.** Smelting requires a heat source present (a
   campfire, or the sturdier crafted **furnace**), exactly as
   [cooking](cooking.md) requires a fire — one consistent "you need warmth to
   transform this" rule across the crafting surface (`CampfireCooking` and
   `Smelting` share the gate shape).
3. **Deterministic recipes now, emergent material physics later.** Smelting is a
   fixed ore→ingot lookup and ingots→gear recipes today (test-pinned, no RNG).
   This is the compiling-toward-`materials.md` note made concrete: eventually an
   ingot carries the mineral property vector and the gear's stats *emerge* from
   shape+assembly; for now iron simply beats stone/leather by fixed numbers.

## The chain

1. **Mine** ore-bearing boulders with a pickaxe → `iron_ore` / `copper_ore` /
   `coal` (already implemented, see the Mining rows in progress.md).
2. **Build a furnace** (crafted from `stone`) — the dedicated, better heat
   source; a carried campfire also works as a low-tier smelter.
3. **Smelt**: `iron_ore` + `coal` (fuel) at a heat source → `iron_ingot`;
   `copper_ore` + `coal` → `copper_ingot`. Consumes the ore and the fuel.
4. **Forge**: ingots are the inputs for the metal tier — `iron_helm`/
   `iron_chest`/`iron_legs`/`iron_boots` (armor that clearly out-protects
   leather) and better weapons/tools. These are ordinary heat-gated crafting
   recipes.

## Status / mechanisms

- ✅ Smelting transform (ore + coal + heat → ingot) — `src/gameplay/smelting.gd`
  (tested); `Player.craft` heat-gates smelting recipes on a carried campfire or
  furnace. Ingot recipes live in `crafting_recipe_book.gd`, shown in the crafting UI.
- ✅ `iron_ingot` / `copper_ingot` items + the crafted **furnace** heat source +
  a full **iron armor set** (helm/chest/legs/boots), all with their own pixel art.
- ✅ Iron armor out-protects leather (2× armor values, feeds `Equipment.total_armor`).
- ⬜ Charcoal from wood (a renewable fuel besides mined coal).
- ⬜ Material-property-vector emergence (the `materials.md` target: stats fall out
  of composite material + shape rather than fixed per-recipe numbers).
- ⬜ Smithing skill quality multiplier (a master realizes more of an item's
  ceiling — designed in [labor_skills.md](labor_skills.md#skill-driven-crafting-quality-closes-smeltingmds-open-todo),
  not yet implemented).

---

## Brainstorm extensions (2026-08-24)

Answers the open request "an emergent smithing/metalworking/alloys system,
based on physical properties." Resolves this doc's own long-standing pillar
3 ("deterministic recipes now, emergent material physics later") and the
`⬜ Material-property-vector emergence` item above. Revises one clause of
[materials.md](materials.md) — see that doc's own 2026-08-24 note — scoped
strictly to the mineral track.

### Alloying: emergent metallurgy, not a recipe menu

The core move: an alloy **is not a new item type with hand-authored stats**.
It's a property vector *computed* from a weighted blend of two existing
mineral vectors (`src/gameplay/material_properties.gd`'s already-real,
already-tested `MATERIALS` table — iron is already there with a genuinely
accurate real density, 7.8 g/cm³), using blend rules grounded in actual
metallurgy rather than invented ones. The result flows through
[materials.md](materials.md)'s existing shape+assembly+threshold pipeline
completely unchanged — an alloy ingot is just one more way to arrive at a
property vector, not a new downstream system.

**Four blend terms, each a real, well-documented metallurgical effect —
not a made-up curve:**

1. **Linear rule-of-mixtures baseline.** Most scalars (density,
   conductivity, flammability, decay_rate) blend close to linearly by mass
   fraction in real alloys — `blended = Σ(fraction_i × vector_i[prop])`.
   Real physics, not an approximation invented for this game.
2. **Solid-solution strengthening bonus (hardness, toughness).** Real
   alloys are famously *not* a linear average for hardness: a second
   element's atoms distort the base metal's crystal lattice and impede
   deformation, so hardness/toughness **peak above either pure
   constituent** at a specific ratio (bronze is harder than a linear
   copper/tin blend would predict). Modeled as a bell-shaped bonus curve
   centered on the real historical peak fraction (~12% tin for bronze),
   the same "tuned curve, pinned by a property test" shape
   `spell_cost.gd`'s `MAG_EXP`/`SPAM_PENALTY` already use elsewhere in
   this codebase.
3. **Eutectic melting-point dip.** Real alloys often melt *below* either
   pure constituent's melting point (bronze melts below pure copper) — a
   genuinely surprising, well-documented fact, not folklore. Modeled as a
   dip in a new `melting_threshold` scalar near the same peak region.
   (`material_properties.gd`'s vector doesn't have this scalar yet —
   `materials.md`'s own property list already names "melting/damage
   thresholds," so this closes an existing doc/code gap, not just an
   alloy-specific addition.)
4. **Brittle collapse past a ceiling.** Push the second element too far
   (high carbon in iron → cast iron; excess tin in bronze) and toughness
   collapses sharply — real intermetallic/cementite formation, not a
   penalty invented for balance. Feeds `materials.md`'s **existing**
   `toughness < T_brittle → shatters` rule with zero new downstream logic:
   cast iron is correctly hard, cheap, *and* liable to shatter on a parry.

Together: near-0% second metal reads as the base metal, softer/tougher
(wrought iron: ductile, weldable, poor edge). A real historical sweet-spot
ratio gives a genuine, physically-motivated power spike (steel; bronze) —
harder *and* tougher than either input, at a *lower* melting point. Overshoot
the ratio and toughness collapses (cast iron: hard but brittle) — a
continuous, emergent composition space, not a discrete recipe list. Alloy
*names* (Bronze/Steel/Cast Iron/Wrought Iron/Brass) are a purely
descriptive lookup over regions of that space — matching
`materials.md`'s existing "you discover a recessive coat colour, not a
spreadsheet" philosophy — the sim computes real numbers; the label is
flavor text, discovered by trying it.

### Reuses two existing seams for free; needs two small pieces of new content

- **Steel needs zero new ore types.** It reuses the fuel slot every smelt
  already requires (`FUEL_ITEM := "coal"`, `smelting.gd`). Today a smelt's
  fuel *count* doesn't affect the output at all — feeding it a *ratio*
  (how much coal relative to ore) instead of a fixed 1:1 is the only
  change needed to walk iron along the real wrought-iron → steel → cast-iron
  carbon spectrum from inputs the game already has.
- **Bronze/brass need new ore types** — tin and zinc don't exist yet
  (`ore_placement.gd`'s `ORE_TYPES` is `["iron", "copper", "coal"]` today).
  Real new content: new ore types, new `item_catalog.gd` items, and new
  `material_properties.gd` rows with real-world-*directional* values (tin:
  soft, low melting point, decent corrosion resistance) on the same 0–10
  "8-bit" scale the existing table already uses — not literal external
  units, to stay consistent with how iron/stone/wood are already scaled
  against each other.
- **Copper itself has no property vector yet.** `copper_ore`/`copper_ingot`
  already exist as items, but `material_properties.gd`'s `MATERIALS` table
  only has wood/flesh/stone/iron/obsidian/fiber — copper is a real,
  pre-existing small gap this design needs filled as a first concrete step
  (bronze can't be computed without it).

### Alloy ratio precision — a second, DIFFERENT skill effect, not a
### duplicate of `ceiling_realization`

[labor_skills.md](labor_skills.md#skill-driven-crafting-quality-closes-smeltingmds-open-todo)'s
`ceiling_realization(crafter_skill_level)` already answers "how much of a
crafted item's theoretical stats does this crafter's skill let them
realize" — general, applies to every craft, not alloy-specific. What it
does NOT answer: which property vector an alloy smelt even PRODUCES in the
first place. That's a step *before* `ceiling_realization` ever applies,
and it's what this section adds — a smith's **intended** input ratio and
their **delivered** ratio aren't the same thing. A low-skill smith's
delivered ratio drifts, deterministically (seeded from the craft, not true
RNG — this project's standing convention), away from what they asked for;
a master hits their intended ratio exactly. Reaching the real historical
sweet spot — where the hardness/toughness bonus peaks and the melting
point dips — becomes a skill-gated craft in itself, independent of and
composing with `ceiling_realization`: a novice smith who fumbles the ratio
gets a worse property vector to begin with, THEN also realizes less of
whatever that (already worse) vector's ceiling is. Two independent skill
gates on two different parts of the pipeline, not one mechanic described
twice.

### Open questions (2026-08-24)

- Exact blend-curve constants (peak fraction, bonus magnitude, brittleness
  cutoff) per alloy pair — a first-pass numeric design at implementation
  time, pinned by property tests like every other tuned curve in this
  project, not eyeballed.
- Exact skill→ratio-drift formula (how forgiving is a mid-skill smith?) —
  unlike `ceiling_realization`, this one is still genuinely open; nothing
  in `labor_skills.md` answers it.
- Does a smelt accept more than two inputs (a three-metal alloy), or is the
  first pass strictly binary blends? Binary is likely the right scope for
  a first implementation — real historical alloys are overwhelmingly
  binary-dominant (bronze, brass, steel) even when trace elements exist.
- Should alloy discovery feed [items.md](items.md)'s `rarity_tier.gd`
  complexity-to-rarity mapping (a masterwork-ratio ingot as a rare crafting
  material), the same way a spell gem's rarity derives from its complexity?
- Where does an alloy's blend ratio get chosen in the UI — a slider on the
  existing crafting card, or literally "feed it however much of each input
  you want" the way recipe input counts already work?
