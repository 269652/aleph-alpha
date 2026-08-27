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
- 🚧 **Alloy blending** — `src/gameplay/alloy_blend.gd` (tested): two mineral
  property vectors blend into a third by real metallurgy — solid-solution
  strengthening, the strength/ductility tradeoff, and cryoscopic melting
  depression. Bronze really does come out harder than copper *and* harder than
  tin. `copper`/`tin`/`carbon` rows now exist in `material_properties.gd`,
  closing the gap named below. **Nothing calls it yet**: there is no tin ore, no
  alloy ingot item, and no smelt path that produces a blended vector — the
  computation is real and the content wiring is absent. See "What actually got
  built" below.
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

### What actually got built (2026-08-27)

`src/gameplay/alloy_blend.gd` implements the blend itself —
`blend(material_a, material_b, fraction_b) -> Dictionary`, returning an ordinary
eight-scalar vector of exactly the shape a `MATERIALS` row already has, so
nothing downstream (`impact_resolver`, `descriptors_for`, `mass_kg_for`) learns a
new type. `material_properties.gd` gained the three rows it needs — `copper`,
`tin`, `carbon` — with real measured densities and the 0–10 scalars placed
against the rows that already existed.

The blend is not linear, and every non-linearity in it is a named real effect
rather than a curve shaped until it looked right:

- **Solid-solution strengthening** rises as the **square root** of solute
  concentration (Fleischer's law), not as a parabola. This matters: a parabola
  centred at 50/50 says the first 1% of tin does almost nothing, when in reality
  the first 1% does more than the tenth. The sqrt puts the steep part at the
  dilute end, which is why every historical recipe lives down there.
- **The peak is derived, not authored.** It sits at the **solubility limit**
  (15.8 wt% Sn in Cu, off the published phase diagram) — past that the lattice
  cannot dissolve more tin and the excess forms a second phase, whose properties
  follow the lever rule and so go linear. The 10–12% tin history actually settled
  on then *falls out* of Fleischer's sqrt rather than being asserted: by 12% you
  already hold ~87% of the available hardening, and the rest costs scarce tin and
  real toughness for almost nothing.
- **The tradeoff is real.** Toughness is divided by exactly the factor hardness is
  multiplied by — the one-parameter form of the "banana curve" every alloy system
  lies on. It introduces no second tuned number and guarantees the tradeoff can
  never silently vanish.
- **Melting depression** is the van 't Hoff cryoscopic relation,
  `dT = (R·T_melt²/ΔH_fusion)·x_solute`, with **no alloy-specific constant
  anywhere** — only each metal's own published melting point and enthalpy of
  fusion. The eutectic is where the two branches cross, solved rather than
  authored. Cu-12Sn lands at ~1006 °C against a real liquidus of ~1000 °C, and
  Fe-4.3C at ~1197 °C against the real 1147 °C, from published constants with
  nothing fitted.
- **One model covers both archetypes.** Substitutional (Cu-Sn) and interstitial
  (Fe-C) differ only in how lattice misfit is measured: a substitutional solute
  replaces an atom, an interstitial one is jammed into an octahedral hole of
  radius `(√2 − 1)·r_host` — pure packing geometry. That single distinction gives
  carbon ~5× tin's misfit, which is why 0.8% carbon transforms iron while it takes
  12% tin to transform copper. No second curve, no "if steel" branch.

The one sourced anchor in the whole model is cast 88Cu-12Sn measuring roughly
twice annealed copper's hardness (~100 HB vs ~50 HB). Misfit and the solubility
limit were already fixed by real data, so the strengthening coefficient is that
anchor **solved for**, and a test re-derives it from the anchors so it cannot
drift away from the measurement it encodes.

**Where this deliberately diverges from the 2026-08-24 brainstorm above** — the
brainstorm was written before the metallurgy was researched, and four of its
claims did not survive contact with it:

1. It says the alloy is "harder *and* tougher than either input". That is a free
   lunch and it is not how alloys work: the same lattice distortion that pins
   dislocations is what destroys ductility. Toughness **falls**. This is the
   change that makes the blend space contain decisions instead of a dominant
   strategy.
2. It specifies "a bell-shaped bonus curve centered on the real historical peak
   fraction (~12% tin)". Authoring the peak at the historical answer would make
   the model a restatement of the history rather than an explanation of it. The
   peak is now the solubility limit, and the historical ratio is an *output*.
3. It calls for a new `melting_threshold` **scalar on the vector**. Melting is
   instead a separate function (`melting_point_c`), because an alloy vector has to
   stay shape-identical to a `MATERIALS` row and half that table has no melting
   point at all — wood chars, flesh cooks, graphite sublimes. A ninth key would
   force every one of those to lie. The eutectic also does **not** sit "near the
   same peak region": for Cu-Sn it is far out on the tin-rich side, nowhere near
   the hardness peak. Those are two independent curves over one axis, which is
   more interesting than one dip aligned with one bulge.
4. Its "brittle collapse past a ceiling" is attributed to cementite formation.
   No cementite is modeled. The plateau past the eutectoid is the 0–10 scale
   clamping, and the *reason* extra carbon is a bad trade is that toughness keeps
   falling while hardness has nowhere left to go. Right answer about cast iron,
   arrived at partly for the wrong reason — recorded here rather than glossed.

Also: density mixes **harmonically**, not linearly as the brainstorm's item 1
assumed. Mass fractions do not add to a density, volume fractions do, and the
exact relation for a mass split is `1/ρ = w_a/ρ_a + w_b/ρ_b`. Worth the extra line
because it is checkable — 88Cu-12Sn comes out at 8.72 g/cm³ against a measured
~8.78 for real cast tin bronze.

### Open questions (2026-08-27)

The 2026-08-24 list below still stands except where the section above resolved
it (the curve constants are now derived and test-pinned; binary blends are the
implemented scope). What implementing it newly exposed:

- **The 0–10 hardness scale has no headroom left, and steel saturates it.** The
  real range from annealed copper (~50 HV) to quenched tool steel (~800 HV) is a
  factor of 16, and the existing table already spends its budget putting copper at
  4 and iron at 8. So *any* carbon steel pins at 10 and the scale cannot tell mild
  steel from tool steel. The model is not wrong; the scale has nowhere to put the
  answer. This is the single biggest known limitation of the slice, and it is
  pinned by a test rather than hidden. Fixing it means rescaling the whole table —
  a change that touches every existing calibration — or giving hardness a
  non-linear reading curve.
- **Conductivity mixes linearly, and real alloys do not.** Nordheim's rule says a
  solid solution scatters electrons far worse than either pure metal, so alloy
  conductivity drops **below both** constituents — the same qualitative shape as
  the hardness bulge, inverted. Modeled as linear for now, which is the one place
  the file knowingly states something false rather than merely incomplete.
- **The eutectic's position is only qualitatively right.** The ideal-dilute
  linearization over-extrapolates far from either pure end: a Cu-Sn eutectic does
  emerge on the correct tin-rich side, but at ~88 wt% Sn / 169 °C against the real
  99.3 wt% / 227 °C. Real activity coefficients close that gap and are not
  modeled. The solvent-rich regime — where every alloy anyone actually makes lives
  — is the part to trust.
- **Heat treatment is absent, and it is a big absence.** What `blend()` returns is
  an as-cast vector. Quenched high-carbon steel really is hard and really does
  shatter, and the model says so; tempering — which trades hardness back for
  toughness — is an *operation on a finished part*, not a property of a
  composition, and belongs to whatever models the forge. Until it exists, there is
  no way to make a steel blade that is not brittle, which is a real gameplay hole.
- **Nothing calls any of this yet.** There is no tin ore (`ORE_TYPES` is still
  `["iron", "copper", "coal"]`), no alloy ingot item, no smelt path that yields a
  blended vector, and no UI for choosing a ratio. The blend is a computation with
  no content around it. The brainstorm's "feed the smelt a coal *ratio* to walk
  iron along the carbon spectrum" remains the cheapest route to making it real,
  since it needs no new ore at all.
- **The skill→ratio-drift formula is still untouched**, exactly as the 2026-08-24
  list says — implementing the blend did not answer it.

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
