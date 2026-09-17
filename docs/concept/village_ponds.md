# Village ponds

*Asked for directly: "The Fisher should build a similar 3x2 enclosure but
filled with water and a pond with river water physics and fish swimming in
it which reproduce".*

A fisher who lives in a village should not have to be born beside a river.
The farmer's answer to "where do you work" is a fenced 3×2 bed outside their
own door ([village_farms.md](village_farms.md)); this is the same answer for
the fisher, dug rather than sown.

## Design pillars

- **The same shape as a field, because it is the same idea.** A 3×2 or 2×3
  rectangle to the sides and downwards of the house, nearest first, with a
  fence frame round it. Everything about siting, fencing and reloading is
  `VillageFarm`'s, reused rather than restated — a pond that sited itself by
  its own rule would drift away from the field it is modelled on.
- **A pond is real water, not a picture of water.** It is the SAME water
  every other system already understands: creatures refuse it, the surface
  paints it, its flow moves what floats in it. The alternative — a decorative
  pond with special cases in every consumer — is how a world stops being one
  world.
- **Fish live there, and go on living there.** A pond stocked once and
  fished flat is a bucket. A pond whose fish breed toward what the water can
  feed is a fishery.

## Real-world grounding

A village fishpond is not an ornament: carp ponds are the standard medieval
answer to "fish on a Friday, nowhere near the sea", dug beside a settlement
and stocked deliberately. They are small — a few tens of metres — fed by a
diverted channel rather than still, and their stock is managed: netted down
in autumn, left to breed back. Three tiles by two, moving water, a
population with a ceiling, is a fair miniature of that.

## Mechanism

### The pond is a field of water

`VillagePond.pond_rect` is `VillageFarm.field_rect` with the fisher's own
building, and its frame is `VillageFarm.fence_cells`/`fence_facing`
unchanged. Identical geometry, identical rails, identical gate rule.

### Built water

A pond cell is an ordinary chunk modification, `pond_water`, exactly like a
rail — which is what makes it survive a reload with nothing else stored. Two
world queries widen to include it and everything else follows for free:

- `is_water_at_global` — so creatures refuse to walk in
  (`CreatureMarker`), the water surface paints it, and anything that asks
  "is this water" gets the right answer.
- `is_river_at_global` — so it carries the river **flow** the ask names:
  the flow overlay draws on it and `FishMarker` reads a current there.

It is `OVERLAY_ONLY_TILE_IDS`-adjacent in spirit but not in fact: unlike a
rail it *replaces* the ground, because that is the point.

### Fish that reproduce

A pond holds its own small population, grown on the world's own ecology tick
toward a carrying capacity derived from the water it has. Stocking is not
spontaneous: a pond starts empty and the fisher stocks it, which is what a
village actually does.

## Status

- ✅ **`VillagePond.pond_rect` and its frame.** Delegated to
  `VillageFarm.field_rect`/`fence_cells` rather than restated, and the tests
  pin the sameness as hard as the pond: a pond that sited or fenced itself by
  its own rule would drift away from the field it is modelled on.
- ✅ **`pond_water` as built water.** `is_water_at_global` and
  `is_river_at_global` both answer for it, so creatures refuse it, the
  surface paints it and its flow moves what floats in it, with no case of its
  own anywhere else. `is_buildable_ground_at` refuses it too — the fisher's
  own water is not somewhere to put a house. Filling one in gives the dry
  ground back.
- ✅ **A fisher's house digs one.** Sited against the house that carries the
  `fisher` occupation, since a fisher lives in an ordinary house and there is
  no separate building to hang it on. Fenced on the field's own rule, through
  the field's own skips.

  Idempotence needed its own answer, and a reload proved it: "a pond cell is
  occupied, so no pond fits there again" is not enough, because another
  rectangle in the same reach still fits and the fisher got a second pond on
  every chunk load. `_has_pond_already` asks whether the house has water at
  all.
- ✅ **Fish that live there and breed.** A pond holds its own stock, keyed
  by the ANCHOR cell of that body of water (its top-left, found by flooding
  it) — one pond is one stock however many cells it has, rather than six
  buckets. `VillagePond.carrying_capacity`/`step` are the world's OWN
  `AquaticPopulationModel`, not a second curve: a pond is a small body of
  water, and fish in it breed for the same reasons and at the same rate as
  fish anywhere else. `EarthChunkManager.step_ponds` runs it on the world's
  ecology tick, wired into `_step_ecology_batch` and pinned there by a
  source-contract test — a step nothing calls breeds nothing, which is a bug
  this repo has already shipped once with wild crops.

  **Stocking is a real act.** Growth is logistic, so nothing grows from
  nothing: water nobody stocked stays empty however long it ticks. The
  village stocks the pond as it digs it, and stocking an already-stocked
  pond changes nothing — a fisher stocks a pond, they do not keep stocking
  it.
- 🚧 **Fish you can SEE in it.** The population is real and breeding; what is
  not wired is `FishRenderer` spawning markers on pond cells to match it. A
  fish placed in a pond already swims and drifts correctly (the water answers
  `is_water_at_global` and `is_river_at_global`), so this is a spawn/despawn
  sync, not new physics.
- ⬜ **The fisher works it.** Catching from their own pond into their own
  house's stock and on to the village, reusing the chain
  [village_farms.md](village_farms.md)'s "Grown, stored, carried" describes.
