# Materials, Shape & Emergent Physics

> Design-direction capture from a brainstorm on 2026-07-15. This doc **evolves**
> [crafting.md](crafting.md): where that doc describes a blueprint =
> base-template + modifier-slots producing stats from a lookup, this pushes
> further — item stats and effects are **not authored per recipe**, they
> *emerge* from the physical properties of the materials and the geometry of
> the shape, resolved by a small deterministic "8-bit physics" model shared by
> crafting, combat, tools, and the world itself. Treat this as the target the
> crafting DSL is compiling toward.

## The core idea

We do **not** hardcode "iron sword = 12 damage, inflicts cut." Instead:

- Every **material** carries an intrinsic **property vector** (a handful of
  scalars: density, hardness, toughness, etc.).
- Every **shape/part** carries **geometric properties** (an edge, a point, a
  mass distribution, a lever arm).
- **Assembling** parts composes their properties by simple physical rules
  (a handle gives a blade *leverage* — Hebelwirkung — multiplying delivered
  force; a heavy head raises momentum but lowers swing speed).
- An item's stats and **effect tags** (cut / pierce / crush / cleave / …)
  then *fall out* of the resulting composite properties crossing **thresholds**
  — not from a hand-written stat block.

The payoff: **novel, unique items whose properties nobody wrote down.** A
player who lashes an obsidian flake to a long shaft has built something the
designers never enumerated, and the model knows exactly how it behaves —
keen, brittle, reach-y, prone to shattering on a hard parry.

## The material property vector

Rich but bounded — roughly 8–10 scalars, enough for real emergence, few
enough to stay "8-bit" legible, deterministic, and unit-testable (per this
project's TDD constraint — every threshold and formula below is a pure
function with a red-first test):

- **Density** — with volume → **mass**. Drives momentum, throw/fall damage,
  and carry/lift gating.
- **Hardness** — resistance to being scratched/deformed; sets edge-holding and
  penetration.
- **Toughness ↔ Brittleness** — resistance to fracture. Low toughness →
  **shatters** under stress (obsidian, glass, ceramic, ancient bone).
- **Elasticity/Springiness** — stores and returns energy (bows, hafts that
  flex without breaking).
- **Sharpness capacity** — how keen an edge the material can *take and hold*
  (a function of hardness + grain).
- **Flammability** — ignites and sustains fire; couples to the surface/
  reaction system below.
- **Thermal/electrical conductivity** — conducts heat and shock (metal blade
  in a fire; shock through a wet or metal object). See
  [electromagnetism.md](electromagnetism.md) for the real mechanism this
  scalar drives — wire resistance, circuit current, overload burnout — once
  a material carries current instead of just a torch's heat.
- **Melting/damage thresholds** — the stress/temperature at which it deforms
  or fails.
- **Decay/weathering rate** — how fast it degrades untended (organics rot;
  metals corrode; stone endures).

### Two material tracks (deliberate asymmetry)

- **Organic materials** (hide, bone, sinew, wood, chitin, fiber): the vector is
  **DNA-driven and variable**. This is the genetic loot loop — hunt/breed/
  mutate for better scalars. See [dna.md](dna.md), [evolution.md](evolution.md),
  [flora.md](flora.md).
- **Mineral materials** (metal, stone, ore): the vector is **fixed and
  reliable**, a property of the material type and its geology, *not* genetics.
  Mined, predictable, the dependable backbone.

Materials stay **pure** — no alloying/compositing into new materials (design
decision). All emergent depth therefore lives in **shape + assembly +
physical interaction**, which leans the whole game toward physics rather than
chemistry. A crafter's art is blending a *variable biological* input with a
*stable mineral* one and choosing the geometry that turns their properties
into the effect they want.

## Shape and assembly

An item is a small graph of **parts**, each a (material × geometry) pair:

- **Geometry primitives**: edge (length, angle → keenness potential), point
  (→ pierce), flat/face (→ crush/block), haft/lever (length → torque
  multiplier), bulk/head (mass concentration).
- **Assembly rules** compose them with real (simplified) mechanics:
  - *Hebelwirkung / leverage*: `delivered_force ∝ head_mass × lever_length ×
    swing_speed`. A blade with a handle multiplies its cutting force; too long
    a lever trades control/speed for force.
  - *Edge + backing*: a keen edge needs a tough spine or it chips — geometry
    can compensate for a brittle material, or fail to.
  - *Balance / mass distribution*: shifts swing speed vs. impact, and how much
    momentum transfers vs. rebounds.

Deterministic throughout: the same parts + geometry always yield the same
composite. Variance lives entirely in the *inputs you sourced*, never in the
craft action (consistent with [crafting.md](crafting.md)'s no-random-roll
principle).

## Effects from thresholds, not authorship

Following the "tags define what's *possible*, thresholds decide what *fires*"
rule: a composite exposes candidate effect tags, and each is gated on a
derived property clearing a threshold.

- `sharpness ≥ T_cut` → **inflicts Cut** (bleed), scaled by keenness.
- `point_pressure ≥ T_pierce` → **Pierce** (armor bypass), from point geometry
  × force / contact area.
- `momentum ≥ T_crush` with a blunt face → **Crush** (stun, bone-break).
- `toughness < T_brittle` under impact stress → **the item itself Shatters**.

Balance stays tractable because designers tune the **threshold curves and tag
vocabulary**, not thousands of individual items — while players still get a
combinatorially open space of buildable things.

## One damage model for the whole world

Because [world.md](world.md)-scale terrain, objects, creatures, armor, tools,
and weapons **all carry the same property vector**, there is exactly one
resolution formula, applied everywhere:

> **impact** = momentum (`mass × velocity`) delivered through a contact
> geometry, resolved against the target's material response (hardness /
> toughness / thresholds) → an outcome: **cut, dent, crush, pierce, shatter,
> or bounce.**

This single equation covers, with no per-case scripting:

- **Melee**: swung weapon momentum vs. hide/armor vector.
- **Thrown objects**: pick up *anything* under your strength limit (rock,
  barrel, corpse, enemy) and hurl it — same momentum formula.
- **Shove / knockback**: displace a target; if it hits a wall or hazard, the
  *collision* resolves through the same formula (generalizes the existing
  `Knockback` system).
- **Topple / collapse**: push over a heavy or brittle structure onto something.
- **Gravity / falls**: fall damage is momentum with **height as velocity** —
  literally the same equation. Drop a hazard on an enemy, or leap for a
  slam.
- **Mining / siege / destruction**: a pick's edge vs. stone's hardness is the
  same edge-vs-hardness check as a blade vs. bone. Breaking terrain **drops
  its constituent materials**, closing the loop straight back into crafting
  supply.
- **Armor & defense**: not a separate "resist" stat — armor is just the
  target-side material vector the attack resolves against.

### Physical interaction verbs

All available as general systems, not scripted per object:

- **Shove**, **Throw**, **Topple**, **Drop/gravity** (all four).
- **Strength-gated capacity**: innate strength (DNA/breeding payoff) sets a
  base lift/throw limit; effort scales it (heavier = slower/shorter); tools,
  levers, ropes, mounts, and later tech blow the ceiling off (the Artisan
  loop). A strong bloodline hurls boulders a weak one cannot lift.

### Reactive surfaces

The **floor holds property-state** and reactions play out on it (the elemental
reaction matrix from [magic.md](magic.md)/[combat.md](combat.md), on the
ground): oil is flammable and spreads, water conducts shock, ice is
low-friction, mud slows. Surfaces created by shattering containers or spilling
material interact by the same rules. (Whether burn-scars/floods *persist* and
reshape terrain is deferred to the world-sim/[weather.md](weather.md) layer;
here we only need them reactive within an encounter.)

### Verticality (2.5D tactical layer)

Layered-tile elevation makes up/down a resource: height grants range/impact
advantage, gates line-of-sight and concealment (reusing vegetation density),
and enables shove-off-ledge and fall-slam plays — all resolving through the
one momentum formula.

## Physical honesty over time

Items **wear, chip, and break**: accumulated stress vs. toughness dulls edges
and, past a threshold, **fractures** them. That obsidian blade genuinely can
**shatter mid-fight** — treated as a *tactical event* (flying shards, a sudden
disarm), not just a punishment. Maintenance/repair is a real loop, and
material choice is a durability-vs-performance decision (keen brittle glass vs.
dependable dull iron).

## Learning an emergent system

Legibility is the real risk of any emergent model. Approach: **learn by
doing** — properties and effects are revealed through *use and
experimentation*, mirroring how breeding hides genotypes behind observed
phenotypes. You discover that obsidian takes a wicked edge but shatters on a
shield the way you discover a recessive coat colour: by trying it. (A deeper
inspect surfacing raw numbers for min-maxers is a possible later affordance,
serving the "all playstyles" goal, but the default is descriptors + discovery,
not a spreadsheet.)

## The crafting act: character × player skill

Deterministic *inputs* still leave room for the *act*: **character skill sets
the ceiling** (a master smith realizes more of an item's theoretical potential
from the same parts), while **player execution reaches for it** (a forging
interaction where doing it well pushes quality). Mastery is thus in sourcing,
design, *and* the making.

## Worked example — "throw the oil-barrel into the torch-lit room"

Nothing below is scripted for "oil barrel"; it's all general systems composing:

1. The barrel is an object with `mass = density × volume`; under your
   strength limit → **throwable**.
2. Hurled (momentum), it strikes a wall. Its container material has low
   toughness → **shatters** (physical-honesty rule).
3. Contents spill as a **flammable surface** (reactive-surface rule).
4. The surface meets an open flame → **ignites** and **spreads** along
   connected oil (reaction matrix).
5. A panicked **shove** pushes a burning enemy off a ledge → **fall damage**
   (momentum, height-as-velocity).

Object mass, container brittleness, surface flammability, reaction rules, and
shove-momentum are each independent general systems. The "combo" is emergent.

## Open questions

- Exact scalar list and units for the property vector; keeping it "8-bit"
  (small integers / fixed-point) for determinism and cheap testing.
- Threshold-curve tuning: per this project's rule, tuned thresholds must be a
  *tested function*, not an eyeballed constant — see the no-manual-tuning
  memory. Each `T_cut`/`T_pierce`/… needs a calibration test.
- Destructible-world **bounds**: which terrain is breakable vs. permanent
  (performance and, later, multiplayer griefing limits) — 61C committed to
  "destruction yields materials," but not yet to how far it extends.
- Performance of a per-contact physics resolution at many-agent scale; likely
  wants the same throttling/caching approach already used for creature sensing.
- How the blueprint DSL in [crafting.md](crafting.md) *surfaces* this: does the
  player manipulate parts/geometry directly, or author intent that compiles to
  a part-graph? (Cross-refs the natural-language-to-structured-policy pattern
  used for NPC instruction.)
