# Mushrooms: fruiting bodies, identification risk, and real toxicity

Reported: "brainstorm and implement mushrooms next, 5x5 illustrated variant
sheets per species."

This doc specifies a new **wild mushroom** layer: fungal fruiting bodies that
appear on the forest floor after a real weather trigger, stand there as a
genuine forageable/pickable ground object, and always show their real
species' own illustrated look and name (see "Revised again: the
identification gate is gone" below for why). Eating one for real has a real
consequence: an edible species relieves hunger like any raw food, a toxic
one genuinely poisons the player.

## Design pillars

1. **A fruiting body is an event, not a growing plant.** [wild_crops.md](wild_crops.md)'s
   carrot/potato grow visibly through three stages because a real root crop
   does. A real mushroom's underground mycelium is already there, invisibly,
   for the whole time the game can see a chunk; what's stochastic is the
   FRUITING — a real fruiting body expands to full size within hours to a
   few days, far faster than this game's own tick granularity could usefully
   show as a multi-stage growth animation. So a mushroom simply appears, at
   full size, when a flush condition is met — closer to a fruit dropping than
   to a crop growing.
2. **Real illustrated art doubles as the field guide.** Originally this pillar
   was "you cannot always tell what you're looking at" — a real, well-
   documented fact about amateur foraging, modeled with an in-game
   identification-by-experience gate reusing `ProceduralEggSprite`'s shared
   pre-hatch look. **Revised once real art arrived**: since every species'
   illustrated sheet is drawn to directly resemble its real-world
   counterpart, hiding that art behind a grind gate fought the art itself
   rather than showcasing it. The game now always shows a mushroom's real
   species — recognizing danger is a real-time visual-pattern skill, the
   same way an actual forager cross-checks against a physical field guide
   rather than starting from zero. That guide lives on the companion
   website, external to the game world, not as an in-game unlock (see
   "Revised again: the identification gate is gone" below).
3. **Eating one is real, not flavor text.** [carrion.md](carrion.md)/the
   venomous-snake pass already prove this project is willing to let a real
   hazard hurt the player (`VenomModel`/`DebuffStack`). A toxic mushroom is
   the plant-kingdom equivalent: eating a Fly Agaric should be able to
   genuinely hurt, at a real, differentiated severity from a Psilocybe —
   the same way this project already differentiates predator danger by
   species rather than by one flat number.
4. **Reuse before invention.** Every piece of this has a direct precedent
   already proven at production scale in this codebase: the patch-sim shape
   ([wild_crops.md](wild_crops.md)'s `WildCropPatch`), forage-for-free
   ([leaf_litter.md](leaf_litter.md)'s `DroppedItem.FORAGEABLE_GROUP_NAME`),
   player pickup (`LiftableStone`/`PickableSeed`'s duck-typed `pick_up`),
   deterministic per-cell art variants (`IllustratedAntMoundSprite`'s
   9-variant sheet, [soil_fauna.md](soil_fauna.md)), a real weather-driven
   flush trigger (`EarthwormPatch.surface_drive`), and a real toxin debuff
   (`VenomModel`). Nothing here is a new shape; it's existing shapes
   recombined for fungi specifically.

## Real-world grounding

- **Fruiting is triggered by rain following cooling temperatures, and is
  heavily autumn-concentrated** in temperate climates — the classic "mushroom
  season." A few real species flush at other times (spring morels are the
  textbook exception), but the roster below is entirely autumn-fruiting
  species, so this pass models one flush window honestly rather than
  building a per-species calendar it doesn't yet need.
- **Two real nutritional strategies, and they place differently.**
  Ectomycorrhizal fungi live in a real symbiosis with a living tree's roots
  and cannot fruit without one nearby — Fly Agaric partners with pine,
  Black Trumpet and Chanterelle with oak; all three are forest/rainforest
  only. Saprotrophic fungi instead decompose dead organic matter directly
  and need no living host, but real saprotrophs don't all share one
  habitat either: Champignon (*Agaricus campestris*, the real "field
  mushroom") is specifically a pasture/grassland species, genuinely
  uncommon in deep forest, while Psilocybe and Parasol are real
  mixed-habitat species found in both grassland and forest (see
  `MushroomSpecies.allows_biome`).
- **Toxicity is real, specific, and asymmetric.** Fly Agaric
  (*Amanita muscaria*) is toxic — ibotenic acid/muscimol poisoning, real GI
  distress and neurological effects — but rarely fatal in a modern medical
  context. Psilocybe (psilocybin) poisoning is primarily perceptual/
  psychoactive and rarely physically dangerous on its own, a real, genuinely
  smaller physical danger than Fly Agaric, not a second copy of the same
  number. Neither is anywhere near the originally-considered Death Cap
  (*Amanita phalloides*, real amatoxin poisoning, often fatal) — this
  roster deliberately has no "certainly lethal" tier (see "Revised once
  real art arrived" below).
- **Black Trumpet, Champignon, Chanterelle, and Parasol are real, prized,
  commonly foraged edibles** — the payoff side of the same real activity
  the toxic species make risky.

## Species roster (`MushroomSpecies`)

**Revised once real art arrived.** The roster below was originally designed
as Fly Agaric/Death Cap/Chanterelle/Porcini/Puffball. The user then
hand-generated six real illustrated sprite sheets directly
(`assets/sprites/mushrooms/*.png`) covering a different, real six-species
lineup instead. Rather than keep code/tests referencing species with no art
and discard art generated for species the code never named, the roster was
redesigned to match what actually exists — the same "reality over the
original plan" principle this doc's own skill_web pivot below already
follows, applied to art instead of a skill slot. Every replacement species
below is real, grounded, and re-verified against real mycology rather than
just renamed in place.

Six species, mirroring `TreeSpecies`'s exact shape (`IDS` + a `SPECIES`
profile dict + small per-trait lookups):

| id | display name | toxic | host tree | why |
|---|---|---|---|---|
| `fly_agaric` | Fly Agaric | ✅ | `pine` | iconic red-cap toadstool; real, rarely-fatal toxin |
| `psylo` | Psilocybe | ✅ | *(none — saprotroph)* | real psychoactive genus; toxic but meaningfully milder than Fly Agaric |
| `black_trumpet` | Black Trumpet | — | `acorn` (oak) | real prized edible, dark trumpet-shaped cap |
| `champignon` | Champignon | — | *(none — saprotroph)* | the common cultivated table mushroom; real edible |
| `chanterelle` | Chanterelle | — | `acorn` (oak) | real prized edible, golden |
| `parasol` | Parasol | — | *(none — saprotroph)* | real edible, large flat cap on a tall stem |

`host_tree` reuses `TreeSpecies.IDS` values directly (`"pine"`/`"acorn"`) —
not a new tree taxonomy — since these are the same real species this
project's orchard/forest trees already model.

## Mechanism spec

### Where and when a flush happens (`WildMushroomPatch`, `MushroomFlush`)

One `WildMushroomPatch` per chunk, same per-chunk-instance contract as
`TallGrass`/`WildCropPatch`/`EarthwormPatch`/`AntColony`
(`PixelNoise`-seeded, never Godot's `hash`, hard per-chunk cap). Unlike a
crop's continuous `0..1` growth, a cell here is binary: **fruiting** or not,
because pillar 1 above means there is no visible growth stage to track.

Mycorrhizal species (`fly_agaric`, `black_trumpet`, `chanterelle`) seed
only on forest/rainforest soil — the same biome their real host tree
already grows in, per `TreeSpecies`. The saprotrophs don't share one
blanket rule: `champignon` (a real pasture species) seeds ONLY on
grassland, while `psylo` and `parasol` (real mixed-habitat species) seed
on forest/rainforest as well as grassland — see
`MushroomSpecies.allows_biome`, the single real source of truth for this
`WildMushroomPatch` itself only delegates to. (Literally
checking proximity to a specific live tree instance is real and grounded,
but is a genuine new cross-system query this pass does not build — see
Deliberately not modeled.)

`MushroomFlush.flush_drive(moisture: float, season: String) -> float`
is a pure, tested function, same shape as `EarthwormPatch.surface_drive`:
a moisture term (real rain trigger, identical curve to the earthworm case)
multiplied by a real season term keyed off `SeasonCycle.season_at`'s own
string — full in autumn, a small named trickle in spring/summer, exactly
zero in winter (the inverse emphasis of `EarthwormPatch`'s own cold-gate,
which suppresses winter specifically rather than favoring one season; the
discrete season-string gate itself matches [leaf_litter.md](leaf_litter.md)'s
autumn leaf-fall trigger). `WildMushroomPatch.advance(delta,
flush_drive)` rolls each non-fruiting cell against it; a successful roll
starts fruiting immediately (no growth animation to run first). A fruiting
cell reverts to available-to-reroll after a real, tested "spent" duration
(a fruiting body doesn't last forever either), mirroring
`EarthwormPatch`'s post-predation `recovery` countdown in shape, not value.

### What the player (and everyone else) sees (`MushroomMarker`)

A `Node2D` per fruiting cell, deterministic `mushroom_seed := hash(global_cell)`
exactly like `AntMoundMarker.mound_seed`, so the same world position always
re-picks the same look across a reload.

**Always the real species' own art and name** (see "Revised again" below) —
`_rebuild_sprite` draws the real illustrated sheet if one exists for
`species_id` (has-art-or-doesn't fallback chain every optional
illustrated-art seam in this codebase uses), the procedural
species-coloured silhouette otherwise. The hover name (`get_display_name`)
is always the real species name plus a "(Toxic)"/"(Edible)" hint.

Joins `DroppedItem.GROUP_NAME` (ordinary E/click pickup) and
`DroppedItem.FORAGEABLE_GROUP_NAME` (a decomposer ant/bug can find and eat
one too — real fungivory, insects and gastropods genuinely do eat fruiting
bodies, distinct from and in addition to the invisible mycelium's own
decomposition of dead wood/litter, which this system does not otherwise
model).

**Picking one up resolves to the same real species item id it was already
showing.** This sidesteps [item_identity.md](item_identity.md)'s
id-only-stacking rule entirely: two `fly_agaric` items always correctly
stack.

### Revised again: the identification gate is gone

**Originally an in-game learned-by-experience mechanic, now removed
entirely** — every mushroom always shows its real species (see pillar 2
above). The first revision here replaced a planned `skill_web.gd` unlock
(no free ring slot existed in the herbalist wedge — every ring in every
wedge sat exactly at its `RING_SLOT_COUNT` capacity) with
`Player.mushrooms_eaten`/`knows_mushrooms()`, a real-encounters counter
gating the sprite/name. Once real illustrated art existed for every
species, gating it behind a grind fought the art rather than showing it
off — the player then supplies their own reference (a mushroom guide on
the companion website, external to the game world) the same way a real
forager carries a physical field guide, rather than the game itself
withholding species identity until a threshold is crossed.

`Player.knows_mushrooms()` and `MushroomSpecies.
MUSHROOMS_TO_LEARN_IDENTIFICATION` are removed — nothing reads them any
more. `Player.mushrooms_eaten: int` stays, persisted, as a simple lifetime
counter (every real mushroom eaten, edible or toxic) — harmless flavor
telemetry, no longer gating anything.

One named simplification: `_mushroom_toxin_step`'s damage-over-time reads
a single `_mushroom_toxin_species` field, so eating a second toxic
species while still poisoned from a first overwrites which severity the
WHOLE active stack ticks at, rather than tracking each bite's species
independently. The same simplification `DebuffStack` already accepts for
venom (one flat model, no per-bite distinction) — acceptable here since
back-to-back toxic mushrooms from two different species in one dose
window is an edge case, not the common path.

### Eating one (`MushroomToxin`)

Reuses `Player._use_food`'s existing raw-eat branch (`eat_food`) — an
edible species relieves hunger exactly like any other raw food item, no new
mechanism needed. A toxic species additionally applies a new debuff through
the identical `VenomModel`/`DebuffStack` pipeline a venomous snake bite
already uses:

```
MushroomToxin.DEBUFF_ID := "mushroom_toxin"
MushroomToxin.damage_per_second(stacks: int, species_id: String) -> float
```

Severity is **per real species, not one flat number** —
`MushroomToxin.severity_for(species_id)` is pinned by test to put
`fly_agaric` genuinely above `psylo` (real: ibotenic-acid/muscimol
poisoning carries genuinely more physical risk than psilocybin poisoning,
which is primarily perceptual and rarely physically dangerous), an
ordering test in the same style as `AntColony.WINDFALL_CONSUMED_CHANCE`
being pinned above/below its siblings rather than an eyeballed absolute
value. `Player.
apply_mushroom_toxin(species_id)` / `_mushroom_toxin_step(delta)` mirror
`apply_venom`/`_venom_step` line for line, against their own
`active_mushroom_toxin_debuffs` array.

### World wiring

`EarthChunkManager.step_wild_mushrooms(delta)`, chunk load creates a
`WildMushroomPatch`, chunk unload drops it — not persisted, not catch-up
integrated, the identical explicit scope cut `EarthwormPatch`/`AntColony`/
`Carcass` already make (ephemeral, self-renewing, chunk-local; see each of
those docs' own Scope-choices sections). **Must be wired into
`scenes/world.gd`'s live per-frame ecology batch at build time, proven by a
real integration test** (`test_world_ecology_batch_wild_mushrooms.gd`,
mirroring `test_world_ecology_batch_wild_crops.gd`) — `WildCropPatch`
shipped fully built and tested but was never actually called from the live
game loop for a time, purely decorative until that gap was caught; this
system is built to prove the same thing from the start rather than risk
repeating it.

### Crushed underfoot

Reported live: "A mushroom is a physical entity... when you walk over
one it should be crushed because of the player weight."
`WildMushroomPatch.crush(cell, momentum_kg_m_s)` mirrors
`EarthwormPatch.crush` exactly (same shared `CrushMechanic.is_crushed_by`
threshold, same "recover on the same clock as being picked" shape) —
see [soil_fauna.md's "Generalized past animals: mushrooms and
walnuts"](soil_fauna.md#generalized-past-animals-mushrooms-and-walnuts-2026-09-06)
for the full mechanism this reuses, including why no Karma penalty
applies (a mushroom is a fungus, not an animal).

## Deliberately not modeled

- **No visible growth stages.** A fruiting body appears fully formed — see
  pillar 1. A future pass wanting a "just emerged, still small" beat would
  need new art and a short-lived growth timer this pass does not build.
- **No literal host-tree proximity check.** Mycorrhizal species are
  biome-gated (the same biome their host tree grows in), not gated on an
  actual nearby living tree instance. A real proximity query
  (`WildMushroomPatch` reading `EarthChunkManager`'s live tree positions)
  is a genuine, well-grounded enhancement, deliberately deferred rather than
  adding a new cross-system dependency this pass does not need to prove the
  mechanic.
- **No persistence/catch-up across a chunk unload**, for the same reason
  `EarthwormPatch`'s burrows and `AntColony`'s mounds aren't — short-
  timescale, self-renewing, chunk-local.
- **No visual lookalike confusion between species.** All six real species
  above are visually distinct from each other — there is no in-game
  ambiguity to create in the first place any more (see "Revised again"
  above); recognizing danger is entirely a real-time, real-world visual
  skill now.
- **No cooking-recipe integration.** `CookingRecipeBook`'s multi-ingredient
  recipe table has zero live callers anywhere in this project today —
  wiring it in at all is a separate, larger, pre-existing gap, not something
  a single new ingredient should be the one to close.

## Status

- ✅ `MushroomSpecies` (`src/world/mushroom_species.gd`) — IDS, display
  names, cap colours, `is_toxic`, `host_tree_for`/`is_saprotroph`.
- ✅ `MushroomFlush` (`src/world/mushroom_flush.gd`) — `flush_drive(moisture,
  season)`, autumn-weighted, zero in winter.
- ✅ `MushroomToxin` (`src/gameplay/mushroom_toxin.gd`) — per-species
  `severity_for`, `damage_per_second(stacks, species_id)`, wired all the
  way to a real eat action (see below).
- ✅ `ProceduralMushroomSprite` (`src/rendering/procedural_mushroom_sprite.gd`)
  — `generate_image(species_id, identified)` still supports the plain
  shared look as a generator capability, but `MushroomMarker` no longer
  ever calls it with `false` (see "Revised again" above).
- ✅ `IllustratedMushroomSprite` (`src/rendering/illustrated_mushroom_sprite.gd`)
  — real 5×5 (25-variant) sheets for all 6 species
  (`assets/sprites/mushrooms/*.png`), chroma-key despilled where needed
  (5 of 6 sheets; `fly_agaric`'s own background is already transparent),
  each with its own measured `marker_scale(species_id)`. See
  [ai_sprite_prompts.md section 12](../art/ai_sprite_prompts.md#12-wild-mushrooms-one-5x5-sheet-per-species-2026-09-05).
- ✅ `WildMushroomPatch` (`src/world/wild_mushroom_patch.gd`) — fixed
  per-chunk sites (real per-species biome eligibility via
  `MushroomSpecies.allows_biome`), PixelNoise-seeded, flush/recovery/
  pick/crush.
- ✅ Item catalog entries for all 6 species (`item_catalog.gd`) — a
  hard prerequisite for the marker below, since `ItemCatalog.make()`
  fails loudly on an unregistered id.
- ✅ `MushroomMarker` (`src/rendering/mushroom_marker.gd`) — the visible,
  pickable ground object: always its real species' own sprite/name, joins
  `DroppedItem.GROUP_NAME`/`FORAGEABLE_GROUP_NAME`/
  `HoverTargetFinder.GROUP_NAME` (the last one reported live as missing —
  "they need hover tooltips" — and fixed), `pick_up(picker)` resolves to
  the real species item, and scales an illustrated sprite by its own
  measured `marker_scale`, not the procedural generator's flat scale.
- ✅ `MushroomRenderer` (`src/rendering/mushroom_renderer.gd`) —
  spawn_markers/sync_markers keep markers in sync with which cells are
  fruiting (no per-tick identification push any more).
- ✅ `Player.mushrooms_eaten`/`apply_mushroom_toxin`/`_mushroom_toxin_step`,
  wired into `eat_food` and `_authority_step`, and `mushrooms_eaten`
  persisted through save/load as a simple lifetime counter. Eating a
  toxic species really does poison the player — through the ordinary
  `eat_food` path a player already uses for every other food item.
- ✅ `EarthChunkManager.step_wild_mushrooms` + chunk load/unload lifecycle
  — chunk load creates a real `WildMushroomPatch` and spawns its markers;
  unload frees them.
- ✅ Wired into `scenes/world.gd`'s live `_step_ecology_batch`, proven by
  `test_world_ecology_batch_wild_mushrooms.gd` — built with that
  regression test from the start (the exact gap that shipped silently for
  wild crops once before), not added after the fact.

**Every piece is now real, tested, and reachable from a running game,
including real illustrated art for every species**: chunk load grows real
mushroom sites, the world's own per-frame loop advances fruiting, every
standing marker renders its own real illustrated sheet at its own measured
on-screen size, and eating one calls back into the real toxin wiring — all
green. What's left is entirely the "No literal host-tree proximity check"
/ other deliberate scope cuts named above, not missing wiring — see
progress.md for the session-by-session record of this landing.
