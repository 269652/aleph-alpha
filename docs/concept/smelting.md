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
  property vectors blend into a third by real metallurgy — a **two-regime model
  split by each pair's published second-phase onset**, Labusch solid-solution
  strengthening below it, a lever-rule brittle-phase collapse above it, and
  cryoscopic melting depression. Bronze really does come out harder than copper
  *and* harder than tin, and the *optimum* composition of three unrelated alloy
  systems falls out of three published phase boundaries. `copper`/`tin`/`carbon`
  rows now exist in `material_properties.gd`, closing the gap named below.
  **Nothing calls it yet**: there is no tin ore, no alloy ingot item, and no
  smelt path that produces a blended vector — the computation is real and the
  content wiring is absent. See "The two-regime rewrite" below.
- 🚧 **Heat as a real tech gate** — `material_properties.gd`'s
  `thermal_failure_c`/`thermal_failure_mode`/`can_melt`/`materials_meltable_at`
  plus `STATION_TEMPERATURE_C` (tested): real Celsius melting/ignition/charring/
  fracture temperatures, compared against what real campfires, bloomeries and
  crucible furnaces reach. The whole progression ladder now falls out of
  arithmetic with **no authored gating anywhere**. **Nothing calls it yet** —
  `smelting.gd` still gates on "is a heat source present", not on its
  temperature.
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

### The two-regime rewrite, and the material-vector correction pass (2026-08-28)

Three corrections to `material_properties.gd` and one to `alloy_blend.gd`. The
alloy one supersedes part of the section above; where it does, that is called
out rather than quietly overwritten.

#### The blend model now has two regimes, split by a published number

The 2026-08-27 model had one law: Fleischer `sqrt(c)` strengthening peaking at
the solubility limit, with toughness divided by exactly the factor hardness was
multiplied by. It was decent, and it authored its own answer in two places. The
replacement has **two regimes separated by each pair's published second-phase
onset** — the composition where a brittle intermetallic starts coming out of
solution:

- **Below the onset** the alloy is a single solid solution. Hardness rises by
  **Labusch's** `c^(2/3)`, not Fleischer's `c^(1/2)`. This is a correction, not
  a preference: Fleischer is documented as the *dilute* result, valid below
  about 1 at% solute, and every alloy here is far outside that (12 wt% tin is
  6.8 at%; 39 wt% zinc is 38 at%). Toughness in this regime simply follows the
  rule of mixtures, because one ductile phase is still one ductile phase.
- **Above it** a real named compound precipitates — δ-Cu₃₁Sn₈, β′-CuZn, γ-Cu₃As,
  cementite Fe₃C — its volume fraction grows by the **lever rule**, hardness
  keeps climbing toward it, and **toughness collapses**, because a continuous
  brittle network on the grain boundaries is a crack highway.

**The four onsets, each off a real phase diagram:** Cu-Sn **13.5 wt%** (the
practical as-cast limit; the equilibrium α boundary is 15.8% at 586 °C, but
bronze is a cast material and coring is what a caster meets), Cu-Zn **39 wt%**
(the α/(α+β) boundary at ~454–470 °C), Cu-As **7.96 wt%** (max solubility at
685 °C), Fe-C **0.76 wt%**. That last one is deliberately *not* a solubility
limit — ferrite dissolves 0.02% C — it is the **eutectoid**, above which
proeutectoid cementite films the prior-austenite grain boundaries. It is named
`SECOND_PHASE_ONSET` rather than a solubility precisely so that this stays
honest.

**The payoff, and the test that earns the rewrite.** The optimum is defined as
the richest composition with no brittle network yet, and it is *scanned* from
the model rather than returned from the constant. Three unrelated systems, three
published boundaries, three real historical answers:

| system | model optimum | reality |
| --- | --- | --- |
| Cu-Sn | 13.5% tin | weapons bronze is 10–14% Sn |
| Cu-Zn | 39% zinc | Muntz metal is 40% Zn |
| Fe-C | 0.76% carbon | eutectoid steel, the classic edged-tool carbon |

Nothing in the formula knows any of that. And the **anti-wiki property** is
explicit and test-pinned: the onsets differ so wildly per pair that a player who
learns "about one part in seven" from bronze is wrong about brass by ~3× and
wrong about steel by ~18×. One authored ratio could never produce that; it is
the whole design argument for a blend *space* over a recipe list.

**Where this supersedes the 2026-08-27 write-up.** Divergence 4 above recorded
that the past-the-eutectoid plateau was "the right answer about cast iron,
arrived at partly for the wrong reason (the plateau is the ceiling clamping, not
modeled cementite)". Cementite is now modeled, by name and by the lever rule,
so it is the right answer for the right reason. Two tests were rewritten to the
better invariant rather than deleted: eutectoid steel now reads **hard, keen and
not brittle** (normalized 0.76% pearlitic steel genuinely is the tough edged-tool
material, and if it came out brittle the historical optimum would be nonsense),
while **cast iron at 4.3% C reads brittle**. The old model called 0.8% carbon
steel brittle, which was simply false. Likewise
`test_toughness_falls_where_hardness_peaks` became
`test_toughness_holds_up_through_the_whole_single_phase_field`: the old "every
alloy is less tough than its parents" shape is contradicted by the
most-produced copper alloy there is — cartridge brass at 30% zinc is both
stronger than pure copper *and* more ductile than it.

**The second phase's composition is derived, not looked up.** Only the formula
is stored; the solute mass fraction is arithmetic over the molar masses already
present. That the arithmetic reproduces the textbook figures (Cu₃₁Sn₈ → 32.5%
against a published 32.6; Fe₃C → 6.69% against the textbook 6.67) is the check
that the derivation is right, and it means a fifth alloy system needs one
published boundary and one chemical formula rather than a measured composition.

#### Conductivity is now a real IACS scale

The column was wrong in the direction that matters: **iron shipped at 9.0
against copper's 10.0**, an 11% gap, when real iron is 15.6% IACS against
copper's 100% — a factor of six and a half, and near the *bottom* of the metals
rather than the top. Flesh shipped at 3.0 when wet tissue is seven orders of
magnitude below any metal.

It is now derived: one anchor (`IACS_SILVER_PERCENT = 105.0`, chosen because
silver is the true maximum of the periodic table and so never has to move
again), one pure function `conductivity_from_iacs()`, and a published %IACS
figure per row. Nothing in the column is assigned. This was free exactly once —
a repo-wide grep confirms **nothing in `src/` or `scenes/` reads `conductivity`
at all** — and it matters because [electromagnetism.md](electromagnetism.md) is
written against this scalar and three of its sentences ("copper makes a
genuinely better wire than iron"; "wood or stone simply doesn't conduct and
can't complete a circuit at all") were unsupported by the old numbers and are
supported now.

The honest cost, test-pinned rather than hidden: on a *linear* silver-anchored
scale every non-metal collapses to effectively zero, because real conductivity
spans ~24 orders of magnitude. That is the right answer for what the scalar is
for, and it means the scale cannot rank insulators against each other. The
stored %IACS figures still can.

#### Heat is a real temperature, and it gates the tech tree for free

`materials.md`'s property list has always named "melting/damage thresholds" and
the table never had one. There is now a real Celsius figure and a **failure
mode** per material — the mode matters because half the table does not melt, and
reporting a bare melting point for a hearth stone or a hide would be a number
standing in place of the truth:

- **melt** — the metals (the *same* published constants `alloy_blend.gd`'s
  cryoscopic model runs on, pinned equal so a tooltip cannot say 1085 while the
  physics says 1084.62) and the two glasses (their glass-transition
  temperatures, since a glass has no melting point).
- **fracture** — stone, at **573 °C**, the α→β quartz inversion. This is why
  fire-cracked rock is a diagnostic artifact class in real archaeology.
- **ignite** — the cellulose fuels (wood ~300 °C, charcoal ~349 °C).
- **char** — the protein tissues. A fourth mode beyond the three originally
  specified, because keratin and collagen genuinely neither melt nor sustain a
  flame; they char and self-extinguish, the same chemistry that makes wool a
  flame-retardant fibre. (Cooking is a *different*, far lower threshold — protein
  denatures around 65 °C — and belongs to `cooking.gd`; this column is about
  structural failure.)

Set against `STATION_TEMPERATURE_C` — campfire ~800 °C, bloomery ~1200 °C,
crucible furnace ~1600 °C, all real figures — **the Iron Age reproduces itself
with zero authored gating**. A campfire melts tin and zinc and works glass but
comes nowhere near copper at 1085 (the Chalcolithic problem exactly). A bloomery
pours copper, bronze (which melts *below* copper, ~1000 °C) and cast iron
(~1200 °C at the eutectic) but cannot melt wrought iron at 1538 — which is
precisely why a bloomery makes a solid-state *bloom* to be hammered rather than a
pour. Only a crucible furnace melts iron, which is historically when crucible
steel appears. No recipe needs a `requires: crucible` flag; iron requires a
crucible because 1537.85 > 1200.

#### Eight missing materials

`MATERIALS` had no **hide, leather, bone, sinew, glass, silver, gold or zinc**,
so every organic part in the design resolved through `DEFAULT_PROPERTIES`' all-
1.0 vector and every one of them realized *identically* — a boar hide and a pane
of glass were the same material, and [crafting.md](crafting.md)'s headline
promise ("a hide from a rare, high-fitness boar is a better material input") was
unreachable in code. All eight now exist with sourced values. Two carry real
mechanisms rather than just numbers: **tanning** is the hide → leather decay drop
(the same shape the table already used for wood → timber seasoning), and **sinew**
is the springiest and strongest cordage in the game because tendon really is the
biological spring.

One knock-on, recorded because it crossed a file boundary: gold at 19.30 g/cm³
is now the densest modelled material, which tripped `assembly_id.gd`'s
volume-quantum guard — a test whose own doc comment says that adding a denser
material *must* force the quantum to be re-derived. It was, from 0.1 cm³ to
0.05 cm³, which is the coarsest quantum under which one quantum of gold still
weighs less than a gram.

### Open questions (2026-08-27)

The 2026-08-24 list below still stands except where the section above resolved
it (the curve constants are now derived and test-pinned; binary blends are the
implemented scope). What implementing it newly exposed:

- ~~**The 0–10 hardness scale has no headroom left, and steel saturates it.**~~
  **RESOLVED 2026-08-28.** This was the slice's single biggest limitation: the
  table spent its whole 0–10 budget putting copper at 4 and iron at 8, so *any*
  carbon steel pinned at 10 and the scale could not tell mild steel from tool
  steel. The fix was the one this bullet named as expensive — rescale the whole
  table — done the same way conductivity was: `hardness` is now every material's
  published **Vickers** figure through `MaterialProperties.hardness_from_hv`,
  linear, anchored on **martensite at 1000 HV** rather than on wherever iron
  happened to sit. Iron is 1.0 and there are nine points of headroom above it.
  Carbon content now moves hardness across the whole range (0.2 % C → 3.79,
  0.76 % → 7.76, 3.5 % → 8.79 as-cast), and a cast steel no longer pins the
  ceiling, because the ceiling is a *heat treatment* and not a composition.
  `test_carbon_content_moves_hardness_now_that_the_scale_has_headroom` replaces
  the test that used to pin the limitation. `SOLUTION_STRENGTHENING_COEFFICIENT`
  moved with its inputs (13.40902 → 14.33195) — it is solved from copper's and
  tin's own hardnesses, so a rescale of those *should* move it, and the anchor
  it encodes is unchanged: 88Cu-12Sn is still twice annealed copper, which is
  now literally 100 HB against 50 HV rather than a ratio on an abstract scale.
  - The one thing the rescale exposes rather than fixes: the single shared `K`
    reproduces the bronze anchor exactly and over-states Fe-C by roughly 3×
    (the model's as-cast eutectoid is ~776 HV against a real annealed ~180 HV).
    Labusch with one coefficient cannot satisfy both anchors at once. It is
    survivable because the quench clamp lands the result on martensite anyway,
    but it is now the biggest *remaining* hardness question in this file.
- **Conductivity mixes linearly, and real alloys do not.** Nordheim's rule says a
  solid solution scatters electrons far worse than either pure metal, so alloy
  conductivity drops **below both** constituents — the same qualitative shape as
  the hardness bulge, inverted. Modeled as linear for now, which is the one place
  the file knowingly states something false rather than merely incomplete.
  *(Still open as of 2026-08-28. Note that the 2026-08-28 pass fixed the*
  *conductivity **column** — it is now derived from published %IACS — but not the*
  *blend **rule**, which is a separate and still-unmodeled non-linearity. Doing it*
  *would be cheap now that the onsets exist, since Nordheim's `x(1-x)` scattering*
  *term applies exactly in the single-phase field and nowhere else.)*
- **The eutectic's position is only qualitatively right.** The ideal-dilute
  linearization over-extrapolates far from either pure end: a Cu-Sn eutectic does
  emerge on the correct tin-rich side, but at ~88 wt% Sn / 169 °C against the real
  99.3 wt% / 227 °C. Real activity coefficients close that gap and are not
  modeled. The solvent-rich regime — where every alloy anyone actually makes lives
  — is the part to trust.
- **Heat treatment is absent, and it is a big absence.** What `blend()` returns is
  an as-cast vector; tempering and quenching trade hardness against toughness on
  an *operation on a finished part*, not by composition, and belong to whatever
  models the forge. *Rewritten 2026-08-28: this bullet used to say "quenched
  high-carbon steel really is hard and really does shatter, and the model says
  so", and that is no longer what the model says — nor should it be, since
  composition alone cannot distinguish quenched martensite from normalized
  pearlite. The two-regime model now correctly calls eutectoid steel tough. The
  absence has flipped direction: there is no way to make a steel blade that IS
  brittle-because-quenched, and no way to temper cast iron's brittleness back
  out. Same hole, honestly relabelled.*
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
