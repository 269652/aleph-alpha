## Wild root crops: carrot and potato grow in the meadow, not on a farm

A real, visible wild population of root/tuber crops — not a random drop
tacked onto another mechanic. Carrot previously only existed as an
occasional freebie from harvesting tall grass (`EarthChunkManager.
has_wild_carrot`, see [taming.md](taming.md)); this supersedes that with an
actual plant: it sprouts, grows through visible stages, spreads to
neighboring ground on its own, and is harvested with a real, animated pull
that yanks the root up out of the earth.

This is the wild/flora side of the crop population — see
[farming.md](farming.md)'s "resolved" note: a farmed crop and a wild one are
two access points into the same kind of population, not two unrelated
systems. Player-tilled farming (DNA, cross-breeding, plots) is still
entirely unbuilt; this is the wild half working on its own, the same
relationship [flora.md](flora.md)'s wild seed-dispersal has to a future
orchard.

### Design pillars

- **A patch-spread simulation, not a spawn table.** Mirrors
  [long_grass.md](long_grass.md)'s `TallGrass` contract exactly: per-chunk,
  deterministic (`PixelNoise`/hash-seeded, never Godot's RNG), growth is a
  continuous 0..1 accumulated over time, and mature patches spread into
  adjacent grassland on a throttled tick. A meadow you leave alone for a
  while has visibly more carrots in it when you come back, the same way a
  grazed grass field regrows and spreads.
- **Growth is seen, not just tracked.** Three real, visually distinct
  stages (seedling → vegetative → mature) drawn from the composite art kit
  below — a player can look at a patch and tell whether it's worth pulling
  yet, the same legibility `ChoppableTree`'s branch-by-branch growth or
  `TallGrass`'s own maturity gate already give other wild plants.
- **The harvest is a real physical action, animated, not a menu
  transaction.** Pulling a ripe root is a swing-driven interaction (same
  input as chopping a tree or harvesting grass — see below) that visibly
  disturbs the soil and lifts the plant clear of the ground before it
  yields anything, not an instant free item.
- **Composite art, not one drawing per state.** Exactly
  [ai_sprite_prompts.md](../art/ai_sprite_prompts.md)'s "genuinely composite"
  kit: a leaves sheet (3 growth stages), one shared soil-mound sprite
  (undisturbed/disturbed, reused across every crop), and a root/tuber sheet
  (the actual harvested object, several color variants). The pull motion
  itself is a runtime tween over these static parts — no baked animation
  frames (see `CropPull`).

### Real-world grounding, and one honest simplification

Wild carrot (*Daucus carota*) is a genuinely common temperate meadow/
roadside plant — the existing "grows among the grasses" framing in
[taming.md](taming.md) is accurate, and this system keeps that same biome
association (`grassland`). **Potato is a deliberate stylization**: its wild
ancestors are Andean highland plants, not a temperate-meadow species — there
is no real-world "wild potato growing in a European meadow" to point to.
It's placed in the same `grassland` population as carrot anyway, for the
same reason `StoneSize.rock_yield` compresses real cube-law volume into a
playable linear scale: modeling potato's real habitat would need a highland/
mountain wild-crop population this game doesn't have a use for yet, and
splitting the two crops across different biome-gating machinery for one
species is not worth it for a first pass. Noted here rather than left
silent, so a future pass that wants potato somewhere geographically honest
(mountain/tundra) knows this was a deliberate choice, not an oversight.

### Growth and spreading (`WildCropPatch`)

One `WildCropPatch` instance per chunk **per crop** (a chunk holds one
carrot patch-sim and one separate potato patch-sim, not one sim juggling
both) — the same "one instance per chunk" shape `TallGrass`/`FlowerPatch`/
`DesertScrub`/`TundraLichen` already use, just two parallel instances
instead of one.

- Seeds onto a small fraction of a chunk's `grassland` cells at chunk
  generation, well below `TallGrass.SEED_CHANCE` — a meadow is mostly
  grass with the occasional carrot in it, not the other way around
  (`WildCropPatch.SEED_CHANCE`, pinned below `TallGrass.SEED_CHANCE` by
  test, per CLAUDE.md's no-eyeballed-constants rule).
- Grows linearly at `GROWTH_RATE` per second, the same 0..1 accumulator
  `TallGrass.advance` uses. Slower than grass regrowth — a carrot patch
  takes noticeably longer to mature than a grazed grass tuft takes to grow
  back, echoing the real gap between a root crop's growing season and a
  grass's own regrowth time; the exact ratio is pinned by test, not an
  eyeballed comment.
- Mature (`growth >= 1.0`) patches spread into an adjacent, currently-empty
  `grassland` cell on a throttled interval (`SPREAD_INTERVAL`,
  `SPREAD_PER_TICK`), identical mechanism to `TallGrass._step_spread` —
  hash-derived pick of parent + direction, no animal-carried seed step (no
  scatter-hoarding equivalent for root crops; out of scope for this pass).
- `graze(cell)` removes a patch the same way `TallGrass.graze` does —
  called once a pull actually completes, not when it starts.
- **Disjoint territory between crops.** Two independently-seeded sims
  sharing a chunk (carrot, potato) could otherwise claim the exact same
  cell — reported live as "carrots render potatoes as crop" (two markers
  stacked on one tile, one per crop). `_in_this_crops_territory` partitions
  every cell into exactly one crop's share up front (a stable hash mod the
  number of crops), so seeding and spread both skip any cell outside their
  own crop's territory — collision is impossible by construction, not just
  unlikely.

### Growth stages -> art (`IllustratedCropSprite`)

The three real AI-illustrated growth-stage frames per crop
(`assets/sprites/plants/{carrot,potato}_leaves.png`, sliced the same
chroma-key + divider-line convention as `sheep.png` — see
`ai_sprite_prompts.md`) map onto the sim's continuous 0..1 growth:

- `[0, 1/3)` — **seedling**: a tiny sprout, just planted.
- `[1/3, 1)` — **vegetative**: half-grown, visibly a real plant, not yet
  worth pulling.
- `[1, ∞)` — **mature**: full leaf volume, ready to pull.

Only the mature stage is harvestable — pulling a seedling or a half-grown
plant does nothing, same "young shoots tear uselessly" rule
`harvest_grass_near` already applies to immature grass.

### The pull (`CropPull`, `WildCropMarker`)

Bound to the **same swing input as chopping a tree / harvesting grass /
smashing a boulder** (`attack`, default Space) — a mature crop patch is
another thing a swing can work, not a separate pickup gesture, and the hover
tooltip (see `HoverTargetFinder`) shows "Pull (Space)" over a ready patch the
same way it shows "Chop"/"Harvest" over its neighbors.

The leaves+root are assembled as ONE entity from the moment a patch spawns,
not built lazily at pull time — `WildCropMarker._ready()` loads the root's
real illustrated art immediately, but clips it away entirely
(`Sprite2D.region_rect` height 0) so nothing of it shows while planted, only
the leaves above it. Reported live: an earlier version toggled the root's
whole `visible` flag at the instant a swing landed, so it either showed
completely or not at all, with the soil's own small footprint unable to
plausibly hide a much taller buried root the rest of the time.

On a swing connecting with a mature patch (`WildCropMarker.begin_pull`,
found via `Player._pull_step`'s melee-range sweep, identical shape to
`_chop_step`/`_smash_step`):

1. The shared soil sprite swaps from its undisturbed to its disturbed
   texture (see `ai_sprite_prompts.md` 2b) — the ground itself shows
   something was just pulled out of it.
2. The leaves+root group rises clear of the mound over
   `CropPull.DURATION_SECONDS`, eased out (`CropPull.progress_at`) — a real
   yank, not a linear slide, and a pure function of elapsed time so the
   curve itself is headlessly testable, the same "runtime tween over static
   parts" idiom `Knockback.step` already established for hit displacement.
   The SAME progress also grows the root's `region_rect` from nothing up to
   its full art, top-down (crown-first, tip-last — the root's own canvas
   convention puts the crown, closest to the leaves, near the top and the
   tip, deepest underground, near the bottom) — the root visibly emerges as
   it rises, rather than popping fully visible the instant the swing lands.
   The revealed strip's BOTTOM edge stays pinned to the marker's own ground
   line throughout (`WildCropMarker._root.centered = false`, an explicit
   offset recomputed every reveal) rather than the strip being centered on
   it — a centered growing rect straddles the ground line (half revealed
   above it, half below) the instant any of it shows, which read as "the
   vegetable is already sitting above the soil, not buried" — obvious on a
   wide, round potato tuber, easy to miss on a carrot's thin taper, but a
   real defect for both (reported live, fixed 2026-08-24; see
   `progress.md`). No baked "mid-pull" animation frames —
   `ai_sprite_prompts.md`'s own note on why that draft was dropped.
3. Once the rise completes, the sim's patch cell is actually removed
   (`WildCropPatch.graze`) and the harvested root drops into the world as a
   real `DroppedItem` — carrying the SAME illustrated root texture the
   player just watched rise out of the ground, not a different fallback
   sprite. It is a real physical object from here on, not an instant
   straight-to-inventory grant: it can be picked up the ordinary way (E or
   a click), exactly like a felled tree's wood or a mined boulder's ore,
   and it can also be **kicked** — a harvested root carries a real average
   whole-vegetable mass (`ItemCatalog._PRODUCE_MASS_KG`, a real reference
   weight rather than a material-density estimate), trivially light enough
   for `Kick.is_kickable`, so `Player`'s existing kick action
   (`docs/concept/stone.md`) now reaches any dropped item with a real,
   modeled mass, not just `LiftableStone`. It does NOT (yet) share
   `LiftableStone`'s full hand-hold-and-throw shape — picking one into the
   HAND to charge and release is a real refactor of `Player`'s stone-typed
   hand state, deliberately deferred rather than rushed (see `progress.md`
   for the explicit follow-up).

### Status

- ✅ Real AI-illustrated art exists and is ingested:
  `assets/sprites/plants/{carrot,potato}{,_leaves}.png` (3 growth-stage
  frames + 7 root/tuber color variants each), sliced by
  `IllustratedCropSprite` (chroma-key + `SpriteSheetSlicer`, mirroring
  `sheep.png`'s recipe).
- ✅ Soil mound: procedural (`ProceduralSoilSprite`) — no AI art exists yet
  for `ai_sprite_prompts.md`'s 2b soil-pile prompt; a hand-drawn fallback in
  the same "offline procedural art" style as every other not-yet-AI-
  illustrated object in this codebase (`ProceduralBobberSprite` and
  friends). Swappable for real art later with no sim/marker changes needed.
- ✅ Growth + spread simulation (`WildCropPatch`), one instance per chunk
  per crop, wired into `EarthChunkManager.step_wild_crops` on the same
  refresh cadence as `step_tall_grass`.
- ✅ Visible per-patch markers (`WildCropMarker`/`WildCropRenderer`),
  spawned/despawned per chunk load same as trees/stones.
- ✅ Animated pull harvest (`CropPull`), bound to the swing input, dropping
  a real ground item, its reveal correctly ground-anchored for any crop's
  art (see "The pull" step 2 above).
- ✅ Superseded: `EarthChunkManager.has_wild_carrot`/grass-harvest-yields-a-
  carrot freebie is removed — a real wild carrot patch supplies carrots now,
  so the old shortcut would just be a second, disconnected way to get the
  same item. `taming.md` updated to point at this system instead.
- ✅ Real produce mass + kickable: carrot/potato carry a real average
  whole-vegetable mass (`ItemCatalog._PRODUCE_MASS_KG`), and any dropped
  item with a real, modeled, kickable mass now offers Kick
  (`DroppedItem.get_hover_actions`, `Player._kick_step`) — a pulled root is
  a real physical object, not just an inventory grant.
- ⬜ Held-item pickup + charge/release throw for a dropped item generally
  (`LiftableStone`'s full hand-hold shape) — `Player`'s hand state is
  currently typed around "a stone, described by a diameter"; generalizing
  it to hold an arbitrary item is a real refactor deliberately deferred to
  its own pass, not attempted here.
- ⬜ No animal-carried seed dispersal for root crops (no scatter-hoarding
  equivalent to `TallGrass`'s mouse-cached grass seed) — spreading is
  purely the adjacent-cell throttled tick.
- ⬜ No DNA/quality variation on the wild population (the 7 root/tuber art
  variants are purely cosmetic, not linked to any trait) — the shared
  farmed/wild DNA model `farming.md` calls for is still entirely unbuilt.
- ⬜ No player-tilled farming, no domestication access point from this wild
  population yet (see `farming.md`'s own open questions).
