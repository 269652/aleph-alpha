# Item Durability: Wear and Fatigue Failure

[materials.md](materials.md)'s "Physical honesty over time" section names this
directly: *"Items wear, chip, and break... Maintenance/repair is a real loop,
and material choice is a durability-vs-performance decision."* Until this
pass, none of that was real — [emergent_crafting.md](emergent_crafting.md)
says so plainly: *"`weakest_link` is computed and the compiler ignores it.
Nothing degrades, nothing breaks."*

This doc is the other half of a story the game already told half of.

## Design pillars

- **Complements the existing shatter mechanic, never duplicates it.**
  `ImpactResolver` already gives a brittle material (toughness <
  `MaterialProperties.BRITTLE_TOUGHNESS`) a real, tested failure mode: it
  shatters in a single hit at high momentum. This doc is exclusively about
  the *other* case — a tough-enough material that never shatters but still
  shouldn't last forever. An item fails exactly one of these two ways, never
  both, gated on opposite sides of the same cutoff.
- **Only a modeled material can wear out.** `item_catalog.gd` already draws
  this line for weapon mass (`_WEAPON_MATERIAL_AND_VOLUME` — three items,
  "not guessed at" for the rest): a stat nobody has measured stays unmodeled
  rather than faked. Wear follows the identical rule. An item with no known
  material simply never accrues wear and can never break from it.
- **A discrete per-use count, not a continuous integral.** Every use event
  (a connecting attack, a block that absorbs a hit) costs one flat unit of
  wear — legible, "8-bit", and directly watchable, not an opaque running sum
  of momentum.
- **Broken means non-functional, not destroyed.** A broken item keeps
  existing, at zero effectiveness, so a future repair loop (materials.md's
  own named aspiration) has something left to repair. Not built here.
- **Every tuned number is named and test-pinned**, per this project's
  standing rule — see "Where the constant comes from" below for the one
  number here that is a deliberate design anchor rather than an external
  measurement, and why that is still an honest choice, not an eyeballed one.

## Real-world grounding

### Fatigue and brittle fracture are genuinely different failure modes

This isn't a game-design simplification standing in for one real phenomenon —
they're two different things in real materials science. Brittle fracture is a
single-event failure once stress exceeds what the material's toughness can
absorb *right now* (real fracture mechanics: `K_IC²/E`, the same energy term
[heat_treatment.md](heat_treatment.md)'s own hardness/toughness trade derives
from). Fatigue is cumulative: a tough, ductile material that would never
shatter from one blow can still fail after enough repeated stress cycles,
because each cycle leaves microscopic damage that never fully heals — real
engineering's S-N (stress vs. cycles-to-failure) curves are exactly this.
A sword blade snapping after a thousand parries and a wine glass shattering
on the first hard tap are not the same kind of failure, and this game's
material vector already has the right axis (toughness) to tell them apart —
it just wasn't being read for the second one.

### None of today's three weapons are brittle, and that's the right split

`material_properties.gd`'s real toughness column: **iron 7.0, wood 6.0, stone
5.0** — all comfortably above `BRITTLE_TOUGHNESS` (3.0). So `wooden_club`,
`iron_sword` and `crude_blade` — the only three items with a real material at
all today — never shatter under `impact_resolver.gd`'s existing rule, and
this doc doesn't change that. What they need instead is exactly the fatigue
story: gradual wear, eventual failure, no drama, no flying shards. (Stone
being *harder* than either of the other two, per `HARDNESS_HV`, but *less
tough* — the least durable of the three here — is the two-axis model working
as designed, not a coincidence: a knapped edge is famously sharp and famously
short-lived, which is precisely why the knapping chain leads toward iron.)

### Toughness is already "energy absorbed before failure" — reuse it, don't refit it

Every other consumer of `toughness` in this codebase already treats it as a
placed 0–10 *legibility* scale, not a hyper-precise physical unit (the
column's own header comment says so directly) — used only in comparisons and
thresholds (`BRITTLE_TOUGHNESS`, `ROPE_MIN_TOUGHNESS`), never run through a
further transform. Wear capacity follows the same convention: since toughness
is already this game's "how much energy before it fails" quantity, and every
qualifying use event delivers roughly comparable stress, the number of
survivable events before accumulated damage matches the material's own
absorbable-energy budget should scale **linearly** with toughness — the
simplest relationship consistent with what toughness already means here, and
the same level of rigor this exact scalar already gets everywhere else it's
used.

## Mechanism spec (`src/gameplay/item_wear.gd`)

Pure logic, mirroring `block.gd`'s tiny focused shape:

| Function | Does |
|---|---|
| `max_wear(material)` | `toughness(material) × USES_PER_TOUGHNESS_POINT`. `INF` for an unmodeled material — mirrors `MaterialProperties.NO_THERMAL_FAILURE`'s "nothing this game models will ever hurt it" convention. |
| `is_broken(wear, material)` | `wear >= max_wear(material)`. |
| `condition_for(wear, material)` | `"pristine"` / `"worn"` (at `WORN_THRESHOLD_FRACTION` = 0.6 of max_wear) / `"broken"` — the three states [item_illustrations.md](item_illustrations.md)'s composite sheet spec draws. Always `"pristine"` for an unmodeled material. |

### Where the constant comes from

`USES_PER_TOUGHNESS_POINT = 8.0` is a **named, deliberate game-balance
anchor**, not a second external measurement dressed up as one — there is no
single published "N real strikes before a hand weapon fails" figure the way
Vickers hardness or IACS conductivity exist for the other columns in this
table. What *is* principled: the linear relationship to toughness (see
above), and the resulting relative ordering across the three modeled weapons
(`iron_sword` 56 uses, `wooden_club` 48, `crude_blade` 40 — iron outlasts
wood outlasts knapped stone, matching the whole knapping→iron progression's
own story). The multiplier itself is an honest, named, test-pinned choice —
in the same tier as `impact_resolver.gd`'s own `T_CUT`/`T_PIERCE`/`T_CRUSH`
thresholds, which are also relatively-reasoned round numbers without an
individual external citation each, not in the tier of a Vickers-derived
column. A future pass with real playtest data is free to retune this one
constant; nothing else in the model depends on its specific value.

### Where wear lives, and the one documented exception to "Item is immutable"

`item.gd`'s own header frames `Item` as "identity/stats shared by every stack
of that item." `wear` is a deliberate, narrow exception: it has to survive
the transition from inventory (`ItemStack`) to equipped
(`Equipment._worn`, which stores a bare `Item`, not a stack) — the same
transition food's `age_seconds` never has to make, since food isn't
equippable. Putting `wear` on `ItemStack` the way `age_seconds` lives there
would simply lose it the moment something is equipped. Putting it on `Item`
itself costs nothing else: every `Item` is already its own fresh instance
from its own `ItemCatalog.make()` call, so mutating one's `wear` field can
never leak into another item of the same id.

### Scope: three items today, by the same rule weapon mass already uses

`_wear_equipped_item()` (`scenes/player.gd`) reads
`ItemCatalog.material_of(equipped_item.id)` and no-ops if it's `""` — the
exact gate `_WEAPON_MATERIAL_AND_VOLUME` already draws for real mass. Today
that's `wooden_club`, `iron_sword`, `crude_blade`. Every other weapon/tool
(axe, pickaxe, fishing rod, ...) has `max_wear` return `INF` and can never
break — not a bug, the same honest "not modeled yet" the mass field already
carries for them.

### Two triggers, both real combat events already in `Player`

- **A connecting attack** — once per creature actually struck inside
  `_perform_attack()`'s existing hit loop (a swing that hits three creatures
  wears the blade three times; a whiff wears it zero).
- **A block that absorbs a real hit** — inside `take_damage()`'s existing
  `is_blocking()` branch, gated on the *incoming* amount being `> 0.0` so a
  stray `take_damage(0.0)` call is never counted as a use.

### What "broken" does: falls back to bare hands, everywhere, for free

`_held_weapon()` returns `null` (instead of the broken `Item`) once
`is_broken()` is true; `_held_kind()` returns `"unarmed"` the same way. Every
existing caller of either — `MeleeAttack.attack_damage`'s `null` → unarmed
fallback, `Block.blocked_damage`'s kind lookup, knockback force — already
has a correct "nothing held" path, so a broken weapon needs no new damage or
efficiency branch anywhere: it simply stops being findable as a weapon at
all, the moment it breaks, and starts again the moment (if ever) it's
repaired.

## The composite sheet consequence

This is what unblocks
[item_illustrations.md](item_illustrations.md#placed-structures-a-second-surface-this-doc-never-named)'s
sibling ask: "attack / defense / worn / broken, one sheet." `condition_for`
above is exactly the "worn"/"broken" half; the "attack"/"defense" half is
real too now (a weapon already has distinct attack-swing and block-guard
game states, per `WeaponSwing`'s rotation and `Block`'s efficiency table) —
so a composite sheet can legitimately draw all four without inventing a
state the simulation can't actually produce.

## Status

### Built and tested (✅)

- ✅ `item_wear.gd` — `max_wear`/`is_broken`/`condition_for`, 18 tests
  (`test_item_wear.gd`).
- ✅ `Item.wear` field, defaulting to 0.0, mutable post-construction
  (`test_item.gd`).
- ✅ Wear accrues from a connecting attack and from a real absorbed block,
  scoped to the three items with modeled material, never for the rest
  (`test_player.gd`'s "item wear" section).
- ✅ A broken weapon reads as bare hands for both damage and block
  efficiency, with no separate fallback logic needed at either call site.

### Not built (⬜)

- ⬜ **Repair.** A broken item has no way back. Materials.md's own "a real
  loop" aspiration stays exactly that.
- ⬜ **Edge wear / sharpness dulling.** [heat_treatment.md](heat_treatment.md)'s
  own named gap — *"a softer draw should lose its edge faster than a harder
  one"* — is a **different** mechanic than this doc's binary broken/not: it's
  about `sharpness_capacity` degrading gradually and affecting per-swing cut
  damage, not about whether the whole item still functions at all. This pass
  answers "does it eventually stop working," not "does each individual swing
  get incrementally weaker first." Genuinely related, not yet the same thing.
- ⬜ **Gradual pre-break falloff.** Today wear is a step function: full
  performance until `is_broken()`, then zero. No degraded-but-still-working
  middle tier.
- ⬜ **Tool-use wear** (chopping, mining) — this pass is combat-only
  (attack/block), matching the states actually asked for. A felling axe
  swung at a tree accrues no wear today even once it has a real material.
- ⬜ **Wear beyond the three modeled weapons** — tools/armor never wear until
  they get real `_WEAPON_MATERIAL_AND_VOLUME`-equivalent entries of their
  own (already a named follow-up in `item_catalog.gd`).
- ⬜ **A tooltip line.** [items.md](items.md)'s "Reading an item" fixed line
  order has no condition/wear row yet.
- ⬜ **Rarity-driven wear resistance.** `rarity_tier.gd` has a real tier
  vocabulary; nothing here reads it.

## Open questions

- Should tools get real material + wear once they get real mass modeled
  (item_catalog.gd's own named follow-up), or does non-combat use need a
  different wear rule entirely (a felling axe's real failure mode is edge
  dulling, not fatigue fracture)?
- If repair is ever built: does it reset wear to 0, or only partially
  restore it (a repaired blade being permanently a little weaker than new is
  a real, common crafting-game convention)?
- Does worn armor wear from absorbing hits the way a blocking weapon does,
  or is armor exempt?
