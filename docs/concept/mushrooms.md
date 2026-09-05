# Mushrooms: fruiting bodies, identification risk, and real toxicity

Reported: "brainstorm and implement mushrooms next, 5x5 illustrated variant
sheets per species."

This doc specifies a new **wild mushroom** layer: fungal fruiting bodies that
appear on the forest floor after a real weather trigger, stand there as a
genuine forageable/pickable ground object, and — because a real forager
cannot tell species apart at a glance — read as one shared, unidentified
shape until the player has actually learned to identify them. Eating one for
real has a real consequence: an edible species relieves hunger like any raw
food, a toxic one genuinely poisons the player.

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
2. **You cannot always tell what you're looking at, and that is the point.**
   An untrained forager genuinely cannot reliably identify a mushroom species
   at a glance across a forest floor — this is real and well-documented (it
   is the entire reason amateur mushroom poisoning is a recognized
   public-health category), not an arbitrary game restriction. This project
   already has the exact shape for "this is real but not yet identifiable" —
   `ProceduralEggSprite`/`AmbientFlyerMarker._is_pre_hatch` shows one shared
   generic look for every pollinator species pre-hatch because "a real
   butterfly/bee egg is not identifiable by species to the naked eye either"
   ([ecosystem_dynamics.md](ecosystem_dynamics.md)). Mushrooms reuse that
   identical shape, gated on a learned skill instead of a life stage.
3. **Eating one is real, not flavor text.** [carrion.md](carrion.md)/the
   venomous-snake pass already prove this project is willing to let a real
   hazard hurt the player (`VenomModel`/`DebuffStack`). A toxic mushroom is
   the plant-kingdom equivalent: eating a Death Cap should be able to
   genuinely hurt, at a real, differentiated severity from a Fly Agaric —
   the same way this project already differentiates predator danger by
   species rather than by one flat number.
4. **Reuse before invention.** Every piece of this has a direct precedent
   already proven at production scale in this codebase: the patch-sim shape
   ([wild_crops.md](wild_crops.md)'s `WildCropPatch`), forage-for-free
   ([leaf_litter.md](leaf_litter.md)'s `DroppedItem.FORAGEABLE_GROUP_NAME`),
   player pickup (`LiftableStone`/`PickableSeed`'s duck-typed `pick_up`),
   deterministic per-cell art variants (`IllustratedAntMoundSprite`'s
   9-variant sheet, [soil_fauna.md](soil_fauna.md)), a real weather-driven
   flush trigger (`EarthwormPatch.surface_drive`), a real toxin debuff
   (`VenomModel`), and a binary (non-scaling) skill unlock
   (`KeystonePassive`'s `land_sense`). Nothing here is a new shape; it's five
   existing shapes recombined for fungi specifically.

## Real-world grounding

- **Fruiting is triggered by rain following cooling temperatures, and is
  heavily autumn-concentrated** in temperate climates — the classic "mushroom
  season." A few real species flush at other times (spring morels are the
  textbook exception), but the roster below is entirely autumn-fruiting
  species, so this pass models one flush window honestly rather than
  building a per-species calendar it doesn't yet need.
- **Two real nutritional strategies, and they place differently.**
  Ectomycorrhizal fungi live in a real symbiosis with a living tree's roots
  and cannot fruit without one nearby — Fly Agaric partners with birch/pine,
  Porcini and Chanterelle with pine/oak. Saprotrophic fungi instead decompose
  dead organic matter directly and need no living host — Puffball is this
  roster's saprotroph, which is why it alone can also appear in grassland.
- **Toxicity is real, specific, and asymmetric.** Death Cap
  (*Amanita phalloides*) is the textbook deadliest mushroom in the world —
  amatoxin poisoning, delayed onset, real organ failure, and critically: no
  folk test reliably distinguishes it from a safe lookalike, which is why
  real foraging guides treat "learn it or don't eat anything you're not
  certain of" as the only real rule. Fly Agaric (*Amanita muscaria*) is also
  toxic (ibotenic acid/muscimol — GI distress and neurological effects) but
  is rarely fatal in a modern medical context — a real, meaningfully smaller
  danger than Death Cap, not just a second copy of the same number.
- **Chanterelle, Porcini, and Puffball are real, prized, commonly foraged
  edibles** — the payoff side of the same real activity the toxic species
  make risky.

## Species roster (`MushroomSpecies`)

Five species, mirroring `TreeSpecies`'s exact shape (`IDS` + a `SPECIES`
profile dict + small boolean lookups):

| id | display name | toxic | host tree | why |
|---|---|---|---|---|
| `fly_agaric` | Fly Agaric | ✅ | `pine` | iconic red-cap toadstool; real, rarely-fatal toxin |
| `death_cap` | Death Cap | ✅ | `acorn` (oak) | the real deadliest mushroom; understated pale-green cap |
| `chanterelle` | Chanterelle | — | `acorn` (oak) | real prized edible, golden |
| `porcini` | Porcini | — | `pine` | real prized edible, brown cap |
| `puffball` | Puffball | — | *(none — saprotroph)* | edible when young; the one species that also grows in grassland |

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

Mycorrhizal species (`fly_agaric`, `death_cap`, `chanterelle`, `porcini`)
seed only on forest/rainforest soil — the same biome their real host tree
already grows in, per `TreeSpecies`. `puffball` additionally seeds on
grassland, being the roster's one non-tree-tied saprotroph. (Literally
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

**Identification gate, checked before species art at all** — the exact
shape `AmbientFlyerMarker._animate_wings` already uses to swap in
`ProceduralEggSprite`'s shared egg look pre-hatch, with the gate condition
swapped from a life stage to a learned skill:

```
if not Player.knows_mushrooms():
    sprite.texture = unidentified_frame   # one shared look, built once from
                                           # mushroom_seed alone, no species
else:
    sprite.texture = <this cell's true species' frame>
```

`unidentified_frame` is built once per marker, from the seed only — a
plain, nondescript brown toadstool shape, the fungal equivalent of the
pollinator egg's "not identifiable to the naked eye" stand-in. The hover
name (`get_display_name`) mirrors the same gate: **"Unidentified Mushroom"**
unidentified, the real species name (plus a "(toxic)"/"(edible)" hint) once
`Player.knows_mushrooms()` is true.

Joins `DroppedItem.GROUP_NAME` (ordinary E/click pickup) and
`DroppedItem.FORAGEABLE_GROUP_NAME` (a decomposer ant/bug can find and eat
one too — real fungivory, insects and gastropods genuinely do eat fruiting
bodies, distinct from and in addition to the invisible mycelium's own
decomposition of dead wood/litter, which this system does not otherwise
model).

**Picking one up always resolves to its real species item id.** The
ambiguity is about what you see standing in the world at a distance, not
about what ends up in your hand — a specimen you are actually holding is
close enough to identify by inspection even if you don't yet know its name,
the same way a real forager can look closely at what they picked. This
sidesteps [item_identity.md](item_identity.md)'s id-only-stacking rule
entirely: two `fly_agaric` items always correctly stack, whether or not the
player has unlocked identification. See Deliberately not modeled for the
one consequence of this scope cut (inventory display is not re-gated).

### Identification (`mycology` skill node)

A new, permanent, non-scaling `SkillTree` node —
`stat_name = ""`, `bonus_amount = 0.0` — the exact sentinel shape
`KeystonePassive.land_sense` already establishes for "this node is a
boolean unlock, not a stat," pinned the same way
(`test_mycology_keystone_carries_no_stat_bonus`, mirroring
`test_land_sense_keystone_carries_no_stat_bonus`). Lives in the herbalist
wedge of `skill_web.gd`, alongside `naturalist_1`/`naturalist_2` — foraging
knowledge is exactly that wedge's theme. `Player.knows_mushrooms() -> bool`
reads `allocated_nodes`/`unlocked_keystones`, mirroring `_has_menagerie()`'s
existing shape exactly.

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
`death_cap` genuinely above `fly_agaric` (real: amatoxin poisoning is far
more dangerous than muscimol/ibotenic-acid poisoning), an ordering test in
the same style as `AntColony.WINDFALL_CONSUMED_CHANCE` being pinned above/
below its siblings rather than an eyeballed absolute value. `Player.
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
- **Inventory display is not re-gated by identification.** Once picked up,
  an item shows its real name regardless of whether `knows_mushrooms()` is
  true — only the world-standing marker (seen at a distance) is ambiguous.
  Re-gating the inventory/hover UI too is a real, separable follow-up, not
  required for the core "you can't tell from across the clearing" mechanic
  to be real.
- **No visual lookalike confusion between species.** All five real species
  above are visually distinct from each other; the shared "Unidentified
  Mushroom" look is what creates the challenge, not any one species
  disguising itself as another.
- **No illustrated art this pass.** The system ships on
  `ProceduralMushroomSprite` (a plain cap+stem silhouette, species-colored
  once identified) end to end. `IllustratedMushroomSprite` exists as a real,
  tested class with an empty variant table (`has_variants(species_id)` is
  false for every species today, pinned by test) — ready to receive a real
  5×5 (25-variant) sheet per species, the same "code first, real art
  drops in later with zero further code changes" path `AntMoundMarker`/
  `IllustratedAntMoundSprite` already proved. The `docs/art/ai_sprite_
  prompts.md` generation prompt for these sheets is intentionally not
  written this pass (asked, and explicitly deferred).
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
  `severity_for`, `damage_per_second(stacks, species_id)`. **Not yet
  wired** to `Player.apply_mushroom_toxin`/`_mushroom_toxin_step` or to the
  eat-food path — the pure model exists, nothing calls it in the live game
  yet.
- ✅ `ProceduralMushroomSprite` (`src/rendering/procedural_mushroom_sprite.gd`),
  incl. the shared unidentified look.
- ✅ `IllustratedMushroomSprite` (`src/rendering/illustrated_mushroom_sprite.gd`),
  empty variant table (pinned by test), ready for real art.
- ⬜ `WildMushroomPatch` (`src/world/wild_mushroom_patch.gd`)
- ⬜ `MushroomMarker` (`src/rendering/mushroom_marker.gd`)
- ⬜ `mycology` skill node (`skill_tree.gd`/`skill_web.gd`) +
  `Player.knows_mushrooms()`
- ⬜ Item catalog entries for all 5 species
- ⬜ `EarthChunkManager.step_wild_mushrooms` + chunk load/unload lifecycle
- ⬜ Wired into `scenes/world.gd`'s live ecology batch, proven by
  `test_world_ecology_batch_wild_mushrooms.gd`

The five pieces above are pure logic/headless-tested (39 tests, all green)
with no scene-tree or live-game wiring yet — nothing is visible or playable
in a running game from this alone. The remaining items are where this
connects to the actual world (patch-sim placement, the marker a player
sees and picks up, the skill node, the eat-food/toxin hookup, and the
world/chunk-manager wiring) — see progress.md for session-by-session
status as those land.
