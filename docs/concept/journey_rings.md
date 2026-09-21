# Journey rings — naming the ground the player is standing on

The world already knows how dangerous a place is. `RegionDifficulty`
(`src/world/region_difficulty.gd`) turns a chunk's Chebyshev distance from
spawn into EASY / MEDIUM / HARD, and that tier already decides whether a
bear, a lion or a venomous snake may exist there at all
(`CreatureRenderer.MIN_DIFFICULTY_TIER_BY_SPECIES`, and see
[ecosystem_dynamics.md](ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness)).

The player has never been told. Three unnamed bands, no boundary the game
ever mentions, no sentence anywhere that says *what changed*. A player who
walks 16 chunks out has crossed from ground where bears cannot spawn to
ground where they can, and the only evidence is a bear.

This doc specifies the player-facing half of that same gradient: named
**rings**, each with a bound, a line about what is new and lethal there,
and the list of things the ring expects a traveller to be carrying. It adds
a *voice* to `RegionDifficulty`. It does not add a second opinion.

## Design pillars

1. **It derives; it never contradicts.** A ring's tier is
   `RegionDifficulty.tier_at`'s tier for that same distance, at every
   distance, without exception — pinned by a sweep over 0..400 chunks in
   `tests/unit/test_journey_ring.gd`. The rings *subdivide* the three
   bands; they never redraw them. Two modules that could disagree about
   where the danger starts is how a world stops being one world
   ([village_ponds.md](village_ponds.md)'s rule, kept).
2. **Every boundary is somebody's constant.** The boundaries that coincide
   with `RegionDifficulty`'s own are *read from it*, not retyped. The two
   extra boundaries this doc introduces are named constants whose value is
   a stated relationship to those radii — the hearth is the inner third of
   the easy band; the marches end at the geometric mean of the easy and
   medium radii — and each relationship is asserted by a test, per this
   repo's rule that a tuned number is a test-pinned constant and never an
   eyeballed comment.
3. **There is no wall, and there can never be one.** This module exposes
   no function that can refuse entry: no `can_enter`, no `is_blocked`, no
   `may_pass`, no `is_allowed`. A reflection test reads the script's own
   method list and fails if any of those names ever appears, so a later
   session cannot quietly turn a pressure into a fence. The friend's third
   requirement — *you should not be able to stroll to the final boss* — is
   answered by what lives out there and what the cold does to you, not by
   an invisible barrier that says no. A player who walks to the far
   country at hour one is allowed to. They are unlikely to walk back.
4. **Demands accumulate, because distance does.** A further ring wants
   everything a nearer ring wants, and one thing more. This is asserted
   pairwise across the whole table, so the ring list reads as a packing
   list that grows — not five unrelated moods.
5. **Crossing is an event, not a state.** `crossing_between` answers "did
   this step change ring?" so a caller can raise the card exactly once, on
   the step that crossed, and never again while the player wanders inside
   the ring. A banner that re-fires every frame teaches the player to stop
   reading banners.

## Real-world grounding

The names are the medieval settlement gradient, which is the same shape as
the mechanic and was arrived at for the same reason: how far you can get
back from before dark.

- The **hearth** is the ground a household actually occupies.
- The **commons** is worked ground held in common — grazed, coppiced,
  walked daily, but not watched.
- The **marches** are the real historical word for the frontier: the last
  ground that has a name and a claim on it. Marcher lords held it armed.
- The **wilds** are past the last claim. Nobody maintains a fire out
  there.
- The **far country** is the abroad of a traveller's tale, described by
  people who came back rather than people who live there.

That ladder is not decoration: it exists in the real record because the
cost of distance is cumulative — provisions first, then a weapon, then
warmth, then light — which is exactly the shape of the demands list below.

The distances are the world's own. A chunk is `CHUNK_SIZE` = 32 tiles and
a tile is ~1 km at world scale (`Lithology.KM_PER_TILE`, itself pinned to
`EarthChunkGenerator.TILES_PER_DEGREE`), so a chunk is ~32 km — the figure
`region_difficulty.gd`'s own doc comment already quotes. The hearth is
therefore ~160 km across, and the far country begins ~1900 km out. Real
Earth at 1 km per tile is a continental map, and these rings are
continental; the card speaks in kilometres because that is the unit the
map is actually in.

## Mechanism

### `JourneyRing` — pure, and only a description

`src/gameplay/journey_ring.gd`, a `RefCounted` of static functions in the
spirit of `spell_cost.gd` and `venom_model.gd`: no scene tree, no world
access, no file access, no singleton. It preloads `RegionDifficulty` —
that is the whole point — and nothing else.

### The table

Five rings, inner and outer bound inclusive in chunks, outer `UNBOUNDED`
(-1) for the last:

| ring | chunks | tier | new and lethal | demands |
|---|---|---|---|---|
| The Hearth | 0–5 | EASY | nothing kills you that you did not walk up to first | — |
| The Commons | 6–15 | EASY | worked ground nobody is watching | provisions |
| The Marches | 16–30 | MEDIUM | predators hunt here rather than pass through | + a weapon that kills |
| The Wilds | 31–60 | MEDIUM | no fire but the one you light | + warmth |
| The Far Country | 61+ | HARD | bear, lion and venomous snake live only out here | + a light, an answer to venom |

Each demand names a system that already exists and can already kill:
`provisions` is `SurvivalMeters`' hunger and thirst, `warmth` is its
`is_cold`/`is_freezing`, `an_answer_to_venom` is `VenomModel`'s stacking
damage-over-time, which only `venomous_snake` applies — and
`venomous_snake` is one of the exactly three species
`MIN_DIFFICULTY_TIER_BY_SPECIES` restricts to HARD. The far country's line
is a statement of fact about the spawn tables, not a threat.

### The boundaries, and where each one comes from

- `RegionDifficulty.EASY_RADIUS_CHUNKS` (15) ends The Commons.
- `RegionDifficulty.MEDIUM_RADIUS_CHUNKS` (60) ends The Wilds.
  Both are read from that module; neither is retyped here.
- `HEARTH_RADIUS_CHUNKS` = the easy radius divided by
  `HEARTH_DIVISOR_OF_EASY` (3) = 5, exactly. A third, because the hearth should be the band a player can
  leave and return from without packing, and it must divide the easy band
  into a "home" and a "near away" without either being a sliver.
- `MARCH_RADIUS_CHUNKS` = 30, the **geometric mean** of the easy and
  medium radii (30² = 15 × 60). The medium band is where distance starts
  doubling rather than adding, so the honest place to cut it is the point
  that is the same *factor* from each end — two steps of ×2 rather than
  one step of +15 and one of +30. `test_march_radius_is_the_geometric_mean_of_the_two_region_radii`
  is what holds that, not this paragraph.

### Functions

- `rings()` — the whole table, outward.
- `ring_at(distance_chunks)` / `ring_index_at(distance_chunks)` — the ring
  containing that distance, and its index in the table.
- `tier_at_distance(distance_chunks)` — that ring's `RegionDifficulty.Tier`.
- `demands_at(distance_chunks)` — the packing list at that distance.
- `distance_chunks(a, b)` — Chebyshev, the same convention
  `RegionDifficulty.tier_at` computes inline and `EarthChunkManager`'s
  `LOAD_RADIUS` math already uses.
- `crossing_between(from_distance, to_distance)` — the ring newly entered,
  or `{}` when both distances sit in the same ring. Inward crossings
  report too: coming home is also news, and a caller that only wants
  outward crossings can compare indices itself.
- `metres_from_spawn(distance_chunks)` — `METRES_PER_CHUNK` (32 000 m)
  times the distance, so the card can say "≈ 480 km from the hearth" in a
  unit a person owns.

`CHUNK_SIZE_TILES` and `KM_PER_TILE` are restated here rather than
preloaded — the same reason `Lithology` gives for restating `KM_PER_TILE`
and `BuilderMarker` gives for restating `CHUNK_SIZE`: a small pure module
should not pull in `EarthChunkManager`. The agreement is pinned by
`test_chunk_size_agrees_with_the_chunk_manager` and
`test_km_per_tile_agrees_with_the_world_scale` instead of asserted by
construction.

### What this module is deliberately not

- Not a spawn gate. `RegionDifficulty` already is one, and duplicating it
  would create the disagreement pillar 1 exists to forbid.
- Not a quest or a marker. It answers "where am I and what does here
  want", and stops.
- Not a fence. See pillar 3; the reflection test is the enforcement.

## Two scales, both true

This project carries a deliberate scale fiction, named in
`src/world/cave_network.gd`'s own header: the **same** chunk is 32 km of
real Earth on the map and about 45 m of ground underfoot at play scale.
Both are real. A distance is only meaningful once it says which one it
is, so this module answers both and never blurs them:

| question | function | the far country (61 chunks) |
|---|---|---|
| where is this on the planet | `metres_from_spawn` | 1 952 000 m |
| how far will I walk | `walking_metres_from_spawn` | ~2 784 m |

The planet's figure is what a map, a latitude or a climate band must
use. The walking figure is what any line a **player** reads must use,
and it is the same scale [survival.md](survival.md)'s `SprintCost`
measures a burst in — so "the village is 340 m away" and "one burst
carries 80 m" are numbers that can honestly be compared.

Found in adversarial review: this module reported the far country at
1 952 000 m while the sprint tests measured the safe ring at 684 m from
the *same* `RegionDifficulty` radii. Neither was wrong; one word was
doing two jobs.

## Status

- ✅ `JourneyRing` pure module: table, `ring_at`, `tier_at_distance`,
  `demands_at`, `distance_chunks`, `crossing_between`,
  `metres_from_spawn`.
- ✅ Derivation sweep against `RegionDifficulty.tier_at`, 0..400 chunks.
- ✅ Cumulative-demands assertion, pairwise over the whole table.
- ✅ Reflection test forbidding any entry-refusing method name.
- ✅ **Wired** (2026-09-20). `Discovery` is the caller this list was
  missing: `crossing_between` raises a real card on the shared message
  stack when the player walks a boundary, naming the ring, what is new and
  lethal there, and its packing list; and `demands_at` is the *only*
  difficulty input to what newly-walked ground pays, so the rings now grant
  as well as threaten. See [discovery.md](discovery.md).
- ✅ **The HUD's permanent "place" chip** (2026-09-20).
  `Discovery.place_chip`, beside the condition chips: the ring, how far out
  at walking scale, and how much ground is recorded. Built after a report
  that none of the journey layer could be spotted — everything else it fed
  was transient. See [discovery.md](discovery.md).
- ⬜ A ring's demands do not yet feed a departure checklist.
- ⬜ Ring names are not yet spoken by any NPC or written on any map.
