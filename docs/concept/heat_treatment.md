# Heat Treatment: One Steel, a Family of Tools

A file and a spring are the same steel in the same shape.

That sentence is the whole reason this system exists. Nothing else in the
emergent-crafting stack can express the difference. [`emergent_crafting.md`](emergent_crafting.md)'s
part graph knows geometry and material and nothing else, so a 70 cm wedge of
0.6 % carbon steel is *one item* to it however long the smith stood at the
quench tub. [`alloy_blend.gd`](../../src/gameplay/alloy_blend.gd) can vary the
composition, but composition is a property of the *stock*, not of the piece —
and every historical smith bought one bar of steel and made a razor, a chisel
and a saw out of it by choosing three different fires.

Heat treatment is that axis. Three operations turn one row of
`material_properties.gd` into a continuum, and it is the cheapest large win in
the whole design: no new item types, no new data, no new vector shape.

It also closes a hole the alloy model left open and documented. `alloy_blend.gd`
notes plainly that what it emits is an **as-cast / as-quenched** vector, and its
write-up in [`progress.md`](../progress.md) lists, among its known gaps, that
as-cast carbon steel comes out brittle **with no way to fix it**. Tempering is
the fix.

## Design pillars

1. **One vector in, one vector out.** Everything here takes the ordinary
   eight-scalar property vector and returns a new one, exactly as
   `alloy_blend.blend` does. Nothing downstream — `impact_resolver`,
   `descriptors_for_vector`, `mass_kg_for` — learns a new type, and no caller's
   dictionary is ever mutated.
2. **The trade can never be a free lunch.** Tempering *moves* the
   hardness/toughness tradeoff. If any draw could raise both, "temper to max
   everything" would be the only move anybody ever made and the mechanic would
   be dead on arrival. This is enforced structurally, not by convention (see
   *The single trade*, below).
3. **The colour ladder is the interface.** A smith reads the draw off the oxide
   film on a polished blade. That is real, it is beautiful, and it is a
   ready-made legibility surface: pale straw, dark straw, bronze, purple, blue,
   pale blue, grey. No numbers on screen required.
4. **Every tuned number is a quotient of published measurements**, re-derived
   by a calibration test so it cannot drift away from the thing it encodes.
5. **Limits are pinned in code, not buried in prose.** Where the model is
   knowingly wrong, a test says so by name.

## Real-world grounding

### The oxide colour ladder

Heat clean, polished steel in air and an iron-oxide film grows on it. The film
thickness tracks temperature, and thin-film interference turns thickness into
colour. This is the temper ladder every workshop manual prints, in the standard
workshop temperatures (usually tabulated in Fahrenheit, given here in Celsius):

| Colour | Draw | Historically makes |
|---|---|---|
| pale straw | 205 °C (400 °F) | razors, scrapers, lathe tools |
| dark straw | 230 °C (440 °F) | drills, punches, knives, files |
| bronze | 255 °C (490 °F) | wood chisels, shears, hammers |
| purple | 280 °C (540 °F) | cold chisels, axes, press tools |
| blue | 300 °C (570 °F) | springs, screwdrivers, needles |
| pale blue | 320 °C (610 °F) | hand saws, spring steel |
| grey | 340 °C (640 °F) | too soft to hold an edge |

The colour depends **only on how hot the steel got** — not on its carbon
content, because it is optics, not metallurgy. That is why the ladder is a
separate table from the hardness data below, and why a low-carbon steel drawn
to blue is still blue.

### Quench: martensite

Cool a carbon steel fast enough and the carbon has no time to diffuse out of
solution; the lattice shears into martensite, a distorted, carbon-stuffed
structure whose dislocations can barely move. Hardness goes up sharply and
toughness collapses. A fully martensitic ~0.8 % C steel measures **832 HV**
(65 HRC); the same steel fully annealed is about **180 HV**. Their ratio, 4.62,
is where quenching's hardness drive comes from — not a multiplier somebody
picked, the quotient of two measurements, and it is the familiar "quenching
roughly quadruples hardness".

An as-quenched blade is famously, genuinely brittle. It is not "a bit fragile":
it will crack sitting on the bench overnight. Tempering was invented because of
this, and in the model it has to be *true*, not gestured at — the as-quenched
vector has to fall below the toughness cutoff the impact model already fractures
things at.

### Temper: the hardness ladder

Reheat the quenched piece and some of the trapped carbon precipitates out as
fine carbides. Hardness comes back down, fracture resistance comes back up. For
a water-quenched 0.8 % C steel the published figures are, in Rockwell C: **65**
as-quenched, then **62 / 58 / 55 / 51 / 48** at 200 / 250 / 300 / 350 / 400 °C.

They are stored converted to Vickers (832 / 746 / 653 / 595 / 530 / 484) through
the standard ASTM E140 table, because **HRC is a depth scale and ratios of HRC
numbers mean nothing**. Reading 55/65 as "keeps 85 % of its hardness" is a real
and easy bug; the true retention at 300 °C is 0.72. In a window only two
hardness points wide (see below), a 13-point error would wreck every draw on the
ladder. `test_hardness_retention_is_read_in_vickers_not_as_a_ratio_of_rockwell_numbers`
exists precisely to keep that bug out.

### Sharpen: the whetstone ladder

An edge is honed toward, and never past, what the material can hold. That
ceiling *is* `sharpness_capacity`: obsidian parts along a conchoidal fracture a
few molecules wide, and iron's grain will not go finer than its carbides. It is
why obsidian beats iron on edge and loses on everything else.

Sharpening is quantized to **eight rungs**, read from
`AssemblyId.TREATMENT_LEVELS` rather than restated. That constant is grounded in
a real waterstone progression (#220 / #400 / #1000 / #3000 / #6000 / #8000, plus
blunt below and stropped above), and it is load-bearing for a second reason:
`assembly_id.gd` content-addresses an item by quantizing its process levels on
exactly this ladder, so an unquantized keenness would mint an unbounded id
space — a new item every stroke of the stone. The two ladders must be one
number.

## The conservation law

This is the part that decides whether the mechanic is alive or dead, so it gets
its own section.

### Why not a plain sum

`hardness + toughness = const` is the obvious candidate. It is wrong three ways:

1. **It is not a real exchange rate.** A sum asserts one point of hardness is
   worth exactly one point of toughness *everywhere on the curve*. Every
   published temper table says otherwise: coming off the as-quenched end a few
   points of hardness buy a large toughness return, and down at the soft end you
   give up a great deal of hardness for very little. Toughness gained per unit
   hardness lost is emphatically not constant across the draw range.
2. **It is not dimensionally coherent.** Hardness is an indentation pressure and
   toughness is an energy. The 0–10 legibility scale puts them on one axis for
   *reading*, not for adding. A power law only multiplies and divides, so it
   survives a rescaling of that axis that a sum would silently change the
   answers under.
3. **It has no derivation.** The exponent below falls out of three real
   relations. A sum falls out of nothing.

### Where the exponent comes from

Three published relations, composed; nothing fitted:

- **Tabor's relation**: HV ≈ 3·σ_y, so yield strength is proportional to
  hardness.
- **The strength–toughness tradeoff along a temper line**: drawing AISI 4340 —
  the textbook case, because both ends are so well measured — from a low temper
  (~200 °C) to a high one (~550 °C) takes σ_y from ~1700 to ~1000 MPa while
  K_IC goes from ~50 to ~110 MPa·m^½. That is K_IC ∝ σ_y^−1.486.
- **Work of fracture**: the energy an impact spends is the fracture energy
  K_IC²/E spread over the plastic zone it opens, whose depth goes as
  (K_IC/σ_y)². Young's modulus **E is structure-insensitive** — martensite,
  pearlite and ferrite are all about 205 GPa, one of the most robust facts in
  the field — so heat treatment does not move it and it drops straight out of
  the ratio. What survives is absorbed energy ∝ K_IC²/σ_y.

Composing: toughness ∝ σ_y^(−2·1.486)/σ_y = σ_y^−3.97, and σ_y ∝ hardness, so

> **hardness^3.97 × toughness is conserved.**

`test_the_toughness_exponent_is_the_published_fracture_anchor_solved_for_n`
re-derives 3.97178 from the stored anchor, so the constant cannot drift away
from the measurement it encodes.

## Mechanism spec (`src/gameplay/treatment.gd`)

### The single trade

Both thermal operations are the *same* private helper, `_slide_to_hardness`.
That is not code reuse, it is pillar 2 made structural: there is no code path in
this file that can raise hardness and toughness at once, because there is only
one path and it trades them.

Along that slide:

- **hardness** goes where it is told, capped at the top of the 0–10 scale
  (`AlloyBlend.SCALE_MAX`, read rather than restated);
- **toughness** pays or is repaid by the power law above;
- **sharpness_capacity** rides hardness exactly — edge retention is downstream
  of hardness, the same rule and the same reason `alloy_blend.blend` gives (a
  soft metal's edge rolls over on first contact, which is why a copper knife
  lost to a flint one);
- **elasticity** rides toughness exactly. That column is **not** Young's
  modulus, and the table's own obsidian row is the proof: obsidian scores 0.0
  while being *more* compliant by modulus than iron at 2.0. It is usable
  bend-and-return, and what limits that is whether the piece survives the bend.
  A blue-drawn saw is springy; an as-quenched one is a pane of glass.

Neither rider introduces a second tuned number, which is the point:
`alloy_blend.gd` made the same choice for the same reason, and a tradeoff with
no free parameters cannot be quietly turned into a free lunch later.

The remaining four scalars — density, flammability, conductivity, decay_rate —
are **deliberately untouched**, and that is a claim rather than an oversight
(`test_heat_treatment_leaves_the_scalars_it_has_no_business_touching_alone`).
Density moves under a percent between martensite and pearlite, and a fire
changes nothing at all about how flammable, how conductive or how rot-prone a
piece of steel is.

### Public surface

| Function | Does |
|---|---|
| `quench(vector)` | Drive to the hard end: hardness × 4.62 (or the scale ceiling), toughness paying the envelope price. |
| `temper(as_quenched, draw_c)` | Slide back down to the hardness that draw leaves. |
| `hardness_retention(draw_c)` | Fraction of as-quenched hardness kept at that draw. |
| `temper_colour(draw_c)` | The oxide colour showing at that temperature. |
| `draw_c_for_colour(colour)` | The inverse; −1.0 for a colour not on the ladder. |
| `sharpen(vector, keen_step)` | New vector whose `sharpness_capacity` carries the edge actually ground on. |
| `keenness(vector, keen_step)` | The same as a scalar, ceilinged at the material's own capacity. |

Two documented preconditions, both pinned by tests:

- **`temper` takes an as-quenched vector.** Retention is defined relative to the
  untempered state, so tempering an already-tempered vector draws it a second
  time from a lower start. A smith re-hardens before re-drawing, and so should a
  caller — `quench()` returns a tempered blade *exactly* to the as-quenched
  state (`test_re_hardening_a_tempered_blade_returns_it_to_the_as_quenched_state`),
  which is both real and a free consequence of both operations being one slide
  along one curve.
- **`sharpen` takes the material's vector**, not one it already returned: it
  overwrites the capacity slot with the achieved edge, so feeding its own output
  back grinds against a ceiling that has already been lowered.

`sharpen` writing the *achieved* edge into `sharpness_capacity` also fixes a
small pre-existing honesty problem: before it, an unworked iron bar read as
`keen` in the tooltip, because the table's 8.0 is the edge it *could* hold. A
blank is not a blade until somebody grinds it.

### What the ladder actually produces

For 0.6 wt % carbon steel (1060/5160 — leaf springs, machetes, blades) straight
out of `AlloyBlend.blend("iron", "carbon", 0.006)`, quenched and drawn:

| Draw | H | T | S | E | Tooltip reads |
|---|---|---|---|---|---|
| as-cast / as-quenched | 10.00 | 1.51 | 10.00 | 1.99 | hard, keen, brittle |
| pale straw 205 °C | 8.86 | 2.45 | 8.86 | 3.22 | hard, keen, brittle |
| dark straw 230 °C | 8.30 | 3.17 | 8.30 | 4.18 | hard, keen |
| bronze 255 °C | 7.78 | 4.09 | 7.78 | 5.39 | hard |
| purple 280 °C | 7.43 | 4.91 | 7.43 | 6.47 | hard |
| blue 300 °C | 7.15 | 5.71 | 7.15 | 7.53 | hard |
| pale blue 320 °C | 6.84 | 6.82 | 6.84 | 8.99 | — |
| grey 340 °C | 6.53 | 8.22 | 6.53 | 10.00 | — |

Read down that table and the historical `use` column falls out of it rather than
being asserted: the razor draw still holds a keen edge *and is still brittle*
(straight razors really do chip), the knife/file draw is the first one that is
both keen and not brittle, and by pale blue the edge is gone and what is left is
a spring. `test_the_colour_ladder_names_the_tools_it_really_makes` holds the
model to exactly that.

## Status

### Built and tested (✅) — `src/gameplay/treatment.gd`, 32 tests

- ✅ **Quench** — martensite drive from the published 832/180 HV quotient;
  as-quenched iron falls below `MaterialProperties.BRITTLE_TOUGHNESS`, which is
  the same number as `ImpactResolver.T_BRITTLE_TOUGHNESS`, and reads `brittle`
  in words.
- ✅ **Temper** — the real HRC→HV ladder, interpolated; monotone in both
  directions across the whole measured range; no draw Pareto-dominates another;
  the power-law envelope is conserved to 0.1 %.
- ✅ **The anti-degeneracy law** — enforced structurally (one slide, one
  helper), and asserted both as "no draw mints both" and as "the *sum* is
  visibly not what is conserved".
- ✅ **The colour ladder** — ordered, round-tripping between colour and
  temperature, and checked against the tools each draw historically makes.
- ✅ **Sharpen** — ceilinged at the material's own capacity at every rung, on
  the same eight-rung ladder `assembly_id.gd` content-addresses with; an
  unsharpened blank no longer reads `keen`.
- ✅ **The acceptance case** — `AlloyBlend.blend("iron","carbon",0.006)`,
  quenched and drawn to dark straw, is harder than plain iron, out of the
  brittle band, and still keen. This is the hole the alloy write-up named,
  closed.
- ✅ **Purity and determinism** — the caller's vector comes back untouched, a
  new dictionary every time, no RNG.

### Known limitations, each pinned by a test rather than hidden (🚧)

- 🚧 **The vector cannot express hardenability.** An eight-scalar property
  vector carries no composition, so nothing here can tell a hardenable steel
  from wrought iron. Real wrought iron does not quench-harden *at all*, and real
  bronze *softens* when quenched; the model hardens both.
  `test_the_vector_cannot_express_hardenability_so_quench_overstates_pure_metals`
  records it as KNOWN WRONG. Fixing it needs a composition-aware caller — the
  forge would have to hand over what it is quenching, not just its vector.
- ✅ ~~**The usable window is 15 °C wide, because the 0–10 scale saturates.**~~
  **RESOLVED 2026-08-28** by rescaling `material_properties.gd`'s hardness
  column to published Vickers anchored on martensite (see
  [materials.md](materials.md)). Plain iron is 1.0 (100 HV) against a ceiling
  of 10.0 (1000 HV), so the window is **175 °C wide** — every colour on the
  ladder from dark straw upward makes a usable tool, and only the pale-straw
  razor draw falls outside it, which is exactly the ladder's own claim.
  Pinned by `test_the_useful_draw_window_is_wide_now_that_the_scale_has_headroom`.
- ✅ ~~**Quenching a modelled carbon steel is a no-op.**~~ **RESOLVED
  2026-08-28** by the same rescale. As-cast 0.6 % C steel arrives at 6.78 with
  room above it; the quench takes it to 10.0 and charges the toughness price
  (6.96 → 1.49, well under the brittle cutoff), and the ceiling it lands on is
  the *right* ceiling because the top of the scale **is** martensite. Pinned by
  `test_quenching_a_modelled_carbon_steel_really_hardens_it`.
- 🚧 **As-quenched hardness is the same for every carbon content.** The fix
  above makes the quench real but not composition-sensitive: 0.2 %, 0.76 % and
  3.5 % carbon all clamp to 10.0 as-quenched, because
  `MARTENSITE_HARDNESS_RATIO` is a single published figure for 0.8 % C and the
  vector carries no composition (same root cause as the hardenability gap
  above). Real quenched 0.2 % C reaches only ~450 HV. What *does* survive is
  the toughness column — as-quenched toughness runs 0.15 / 2.54 / 2.25 across
  those three — so a mild steel still cannot be tempered into a knife and a
  eutectoid one can. The right answer emerges; the hardness number does not
  yet show it.
- 🚧 **Quenching is envelope-conserving, which understates it.** Real quenching
  does better than a pure trade: tempered martensite is a genuinely better
  structure than annealed pearlite, worth roughly a factor of two in
  hardness²×toughness. *How much* better is set by carbon content, which the
  vector does not carry, so the model stays conservative rather than inventing
  a number.
- 🚧 **The exponent rests on a two-point log-log fit** of representative AISI
  4340 strength/K_IC values. The composition of the derivation (Tabor +
  fracture energy + structure-insensitive E) is solid; the slope would tighten
  with a fuller published dataset.
- 🚧 **The draw table is calibrated over 200–400 °C only.** Below 200 °C it
  interpolates in a straight line to the as-quenched point, which overstates
  softening at very low draws (real steel barely tempers under ~150 °C). Past
  400 °C it goes **flat** rather than extrapolating — real steel keeps
  softening, but this file has no figures for it and will not invent a curve
  (`test_a_draw_past_the_measured_table_stops_moving`). Same rule
  `AlloyBlend.SOLID_SOLUBILITY` follows.
- 🚧 **Tempered martensite embrittlement is not modelled.** Real steels have a
  toughness *trough* around 260–370 °C ("500 °F embrittlement"). Modelling it
  would break the monotonicity the design deliberately wants, so the model uses
  the idealised envelope. A named omission, not an oversight.

### Not built (⬜)

- ⬜ **Nothing calls this module.** `treatment.gd` has no caller outside its own
  test — the dominant defect class in this codebase, so it is stated first and
  plainly. There is no forge, no quench tub, no whetstone item and no crafting
  UI that produces a draw temperature, so no item in a running game has ever
  been quenched, tempered or sharpened.
- ⬜ **`impact_resolver.gd` cannot consume a treated vector.** `resolve_impact()`
  takes a material *name* and looks it up, so a computed vector — treated or
  alloyed — cannot reach the fracture model at all. Widening it to accept a bare
  vector (the way `descriptors_for_vector` was widened for alloys) is the single
  smallest change that would make heat treatment matter in play.
- ⬜ **Nothing carries a piece's treatment state.** An item has no "drawn to
  blue" field; the treated vector has to be recomputed or stored by whatever
  owns the item. `assembly_id.gd` already reserves a `treatment` field on a part
  and quantizes it, so the id side is ready and the item side is not.
- ⬜ **Edge wear.** Sharpening exists; blunting does not. A softer draw should
  lose its edge faster than a harder one, which is the other half of why the
  ladder matters — and it needs the durability/wear state
  [`materials.md`](materials.md) lists as unstarted.
- ⬜ **Case hardening / carburising**, differential hardening (a clay-backed
  blade hard at the edge and tough at the spine), and normalising/annealing as
  distinct operations. All real, all natural extensions of one slide along one
  envelope, none built.
