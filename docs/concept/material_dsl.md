# Material DSL: composition, crush, nutrients

Requested directly: describe a material like an apple as percentages of real
substances (60% water, 20% sugar, 2% vitamins, ...); eating applies a real
crushing force to the object; the composition converts into nutrients that
satisfy thirst/hunger/nutrition, the *same* mechanism working implicitly for
the player and every animal species.

## Why this is new, not a duplicate

[materials.md](materials.md) already gives this game "one damage model for
the whole world" (momentum through a contact geometry, resolved against a
material's property vector) and [survival.md](survival.md) already gives it
hunger/thirst meters — but nothing today connects them. `SurvivalMeters.eat()`
is a flat scalar; `Player.eat_food()` passes one hardcoded constant
(`EAT_HUNGER_RELIEF`) identical for an apple, a mushroom, and a cooked fish;
`ItemCatalog`'s food rows carry no composition field at all; thirst is
relieved *only* by standing in water, never by food, no matter how juicy.
`docs/playtests/2026-08-25-full-session.md` named this directly as its top
finding: *"no nutrition, no damage derived from anything... the deepest
system in the project is invisible."* This doc is that connection.

It also fills in a real, previously-declared gap: materials.md's "Two
material tracks" section names an **organic** track (DNA-driven, variable)
as a deliberate sibling to the **mineral** track `MaterialProperties`
implements — but nothing has ever populated it (`dna.md`/`evolution.md`
carry no material-property content today). This is the organic track's
first real content: a material whose relevant scalars are food composition,
not ore hardness.

## Design pillars

- **One shared, species-blind core.** Cross-species eating already funnels
  through one thin primitive — `Drives.satisfy(drive)`, wrapped by the
  player's `CreatureNeeds` facade, land mammals, and birds via
  `BirdDigestion` — that resets a `[0,1]` meter by a fixed per-body-plan
  "meal" size, **blind to what was actually eaten**. The new
  `NutrientRelease.consume(food_id)` function is the missing piece: it reads
  *what* was eaten and derives real nutrient amounts, then hands them to
  whichever meters that particular eater already has. It does not know or
  care who is eating — "implicitly the same for all species" falls out of
  that function being pure and content-driven rather than hardcoded per
  caller.
- **Reuse the existing damage model, don't parallel it.** A bite is a real
  impact event — momentum, delivered through a contact geometry (a blunt
  bite face), resolved against a material's response — the exact shape
  `ImpactResolver.resolve_impact` already implements for combat. Eating gets
  its own calibration point (bite-scale momentum), the same way
  `CrushMechanic` already added a footstep-scale one alongside
  `ImpactResolver`'s own combat-scale `T_CRUSH` — a third point on the same
  formula, not a fourth mechanic.
- **Composition is data, not code.** A material's nutrient makeup is a plain
  keyed dictionary of fractions (water/sugar/vitamins), mirroring
  `ethogram.gd`'s own "receptor sensitivity is authored as a flat data
  table, not a program" convention — there is no control flow to a
  composition record, so it gets no parser.
- **Only a modeled material gets the real behaviour.** Exactly
  [item_durability.md](item_durability.md)'s rule for wear ("a stat nobody
  has measured stays unmodeled... an item with no known material simply
  never accrues wear"): a food with no composition entry yields zero
  nutrients and falls back to today's exact flat-relief behaviour. Nothing
  currently-working regresses; the new system only ever adds behaviour where
  real data exists.
- **Name what's deferred.** Shelled nuts, birds, ants, and caterpillars are
  explicitly out of this pass (see Status) — not silently unequal, named.

## Real-world grounding

Water and sugar fractions are real (USDA-ballpark) figures for the raw
fruit: apple ≈ 86% water, ≈ 10% sugar by mass; sweet cherry ≈ 82% water,
≈ 13% sugar. **"Vitamins" is a deliberately coarse gameplay abstraction**,
not literal vitamin-C mass (real vitamin C content is under 0.01% by mass —
far too small a number to be a legible gameplay lever) — it stands in for
the combined micronutrient/mineral/fiber value of a whole fruit, scaled to
be a meaningful fraction. This project consistently names its own
simplifications rather than presenting a fake-precise number as measured
fact; this is one of them.

Biting into ripe fruit is real, blunt-face crushing — the same "momentum
through a contact geometry, resolved against material response" mechanism
combat uses, just at a much smaller, chewing-scale momentum, and against a
much softer material than any of the eighteen entries `MaterialProperties`
carries today. A firm bite reads as "crush" (not "shatter" — soft flesh
mushes, it doesn't fracture into shards) because its toughness is placed
above `ImpactResolver.T_BRITTLE_TOUGHNESS`, the same brittleness cutoff
combat already uses.

## Mechanism

### `src/gameplay/organic_material_properties.gd` (new)

A sibling to `MaterialProperties`, identical shape (`DEFAULT_PROPERTIES`,
a `MATERIALS` dict, `property_value(material, property_name)`), never
merged into `MaterialProperties.MATERIALS` itself — that file's own doc
comment scopes it to the mineral track. One entry today, `"fruit_flesh"`:
soft (hardness at the bottom of the scale, on par with muscle tissue's own
negligible 0.001 — there is no meaningfully different real hardness datum
for fruit pulp at this resolution), and toughness placed just above
`T_BRITTLE_TOUGHNESS` so a firm bite reads as crush, not shatter, while
still well below fibrous/structural tissue like muscle or wood — a
legibility ordering, exactly how `materials.md` already treats every
non-measured column on this vector.

### `src/gameplay/impact_resolver.gd` (extended, behaviour-preserving)

`ImpactResolver._materials` becomes constructor-injectable
(`_init(materials_source: RefCounted = MaterialProperties.new())`). Every
existing call site (combat, throwables) passes no argument and gets exactly
today's mineral table — zero behaviour change. Only the new eating path
constructs `ImpactResolver.new(OrganicMaterialProperties.new())`.

### `src/gameplay/food_composition.gd` (new) — the composition table

```gdscript
const COMPOSITION := {
    "apple":  {"water": 0.86, "sugar": 0.10, "vitamins": 0.02},
    "cherry": {"water": 0.82, "sugar": 0.13, "vitamins": 0.025},
}
func composition_for(food_id: String) -> Dictionary:
    return COMPOSITION.get(food_id, {})
```

An unmodeled food (every non-fruit food today, and shelled nuts — see
Status) returns an empty dict, the unmodeled-material fallback shape.
Fractions per entry are real-grounded and sum to comfortably under 1.0 (the
remainder is fiber/protein/fat/structure this pass doesn't model) — a real,
test-pinned invariant, not an eyeballed one.

### `src/gameplay/nutrient_release.gd` (new) — the generic core

`const BITE_MOMENTUM_KG_M_S` — a new named, test-pinned bite-scale
constant, the third calibration point alongside `CrushMechanic`'s footstep
scale and `ImpactResolver.T_CRUSH`'s combat scale (each its own physical
situation; none reused verbatim across the others).

`static func consume(food_id: String) -> Dictionary` returns `{"crushed":
bool, "water": float, "sugar": float, "vitamins": float}`:
1. Look up `FoodComposition.composition_for(food_id)`. Empty → `{"crushed":
   false, "water": 0.0, "sugar": 0.0, "vitamins": 0.0}` (nothing to release).
2. Otherwise resolve `ImpactResolver.new(OrganicMaterialProperties.new())
   .resolve_impact(BITE_MOMENTUM_KG_M_S, "blunt", "fruit_flesh")`. Anything
   but `"crush"` (there is no real path to anything else at this momentum
   against this material today, but the check is real, not assumed) →
   `crushed = false`, zero nutrients.
3. On `"crush"`: each composition fraction × `NUTRIENT_UNIT_SCALE` (a named
   constant converting "fraction of one whole fruit" into "meter-ready
   units", calibrated so a whole apple's sugar content relieves a
   comparable amount of hunger to today's flat `EAT_HUNGER_RELIEF`, keeping
   the new, real number in the same ballpark as the old guess it replaces).

### Per-eater adapters — thin, additive, existing meters extended not replaced

- `SurvivalMeters` (extended): a new `nutrition` meter, built exactly
  parallel to `hunger`/`thirst` (`NUTRITION_RATE_PER_SECOND` depletion,
  advanced in `advance()`), and `nourish(amount)` mirroring `eat`/`drink`.
  This gives [survival.md](survival.md)'s named-but-unbuilt "dietary variety
  affects disease resistance" follow-on a real meter to eventually read —
  wiring resistance itself stays out of this pass.
- `Player.eat_food()` (extended): calls `NutrientRelease.consume(item_id)`;
  on `crushed`, routes `water → survival.drink`, `sugar → survival.eat`,
  `vitamins → survival.nourish`; on an unmodeled food, falls back to exactly
  today's `survival.eat(EAT_HUNGER_RELIEF)`.
- `Drives.satisfy_amount(drive, amount)` (new, additive): the same
  `after_meal` arithmetic `satisfy()` already uses, parameterized by a real
  amount instead of the body-plan's fixed "meal" size. `satisfy()` itself,
  and every existing caller, is untouched.
- `CreatureNeeds.feed_amount(amount)`/hydrate equivalent (new, additive):
  thin wrappers over `Drives.satisfy_amount`, alongside the existing
  `feed()`.
- `CreatureMarker._take_forage_bite()`'s `GrazerForaging.FOOD_FRUIT` branch
  (extended): calls `NutrientRelease.consume` on the species id
  `take_fruit_at` already returns, routing amounts via the new
  `CreatureNeeds` methods. Every other forage kind (grass/seed/worm/
  underfoot) keeps calling `_needs.feed()` exactly as today — none of them
  have composition data yet.

## Status

- ✅ `OrganicMaterialProperties` + `ImpactResolver` injection (organic
  track's first real content; zero behaviour change for every existing
  combat/throwable caller).
- ✅ `FoodComposition` for apple and cherry (soft, shell-less fruit).
- ✅ `NutrientRelease.consume` — the generic, species-blind core.
- ✅ Player: hunger, thirst, *and* the new nutrition meter, all relieved by
  eating real fruit; every other food unchanged.
- ✅ Land mammals (deer/boar/horse/sheep, via the shared `GrazerForaging` →
  `CreatureNeeds` → `Drives` path): fruit relieves hunger by a real,
  composition-derived amount instead of the flat body-plan "meal" size;
  grass/seed/worm/underfoot unchanged.
- ⬜ Shelled nuts (walnut/acorn/hazelnut) — these already have a separate
  "crack it open" mechanic (`EarthChunkManager.crush_walnut_near`). Whether
  a cracked kernel then feeds through this same pipeline is a real,
  separate design question, not decided here.
- ⬜ Birds (`BirdDigestion`), `AntColony`'s own flat food-unit ledger, and
  caterpillars (no meter at all today) — `NutrientRelease.consume` already
  works for them unchanged; each just needs its own thin per-eater adapter,
  the same shape `CreatureNeeds`'s got here.
- ⬜ Wiring the new `nutrition` meter into [survival.md](survival.md)'s
  dietary-variety-affects-disease-resistance design (itself still ⬜ there)
  — this pass only gives that future work real data to read.
- ⬜ Composition for any food beyond apple/cherry — cooked dishes, meat,
  fish, mushrooms, root vegetables all keep today's flat behaviour until
  someone measures them in.
