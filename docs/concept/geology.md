# Geology

What is underneath the ground. `stone.md` is the loose rock lying *on* the
surface and `resources.md`/`smelting.md` cover ore already exposed in a
surface boulder; this doc is everything *beneath* that -- the rock the
player has to dig down into, and the four real, distinct depths that make
digging down mean something different at every stage.

## Design pillars

**Real strata, not a backdrop.** The underground is not a painted cave
texture the player walks through -- it is actual per-chunk simulation data
(`Strata`), the same class of thing `EarthChunkManager` already keeps for
wild crops and decomposers, just answering "solid rock / ore / open tunnel"
instead of "growing / ripe / fallen". A cell you haven't mined yet is solid
because the sim says so, not because nobody drew a hole there yet.

**One doorway mechanism, reused recursively.** This project already solved
"reveal what's normally hidden the moment the player crosses a threshold,
and hide it again the moment they leave" for building interiors
(`RoomDetector` + `TerrainRenderer.paint_roofs`'s `hidden_cells`, see
`building.md`). A cave mouth is the same problem turned ninety degrees: the
threshold is a hole in the ground instead of a doorway, and what gets
revealed is a chamber of diggable rock instead of a floor and walls. Each
shaft between one layer and the next is that exact mechanism applied again,
recursively, one layer down.

**Four real layers, not one depth number.** Real ground is not
uniform with depth: the first few metres are weathered mantle, then solid
crustal rock, then rock under real pressure at real mine depths, and
mineral veins concentrate wherever hot circulating fluids once passed
through -- four qualitatively different places to be standing, not four
tiers of the same number turned up. Each is a `Strata` instance, differently
PARAMETERIZED (rock density, which ores concentrate there, how foul the air
gets, how much water wants in) rather than four separate classes, because
the underlying question -- "what's in this cell" -- never actually changes,
only the odds.

**Digging is real work with real risk.** An unsupported gap in rock fails
the way real unsupported roof spans do: bending stress under a span's own
weight grows with the SQUARE of that span, not linearly, so a wide open
tunnel is disproportionately more dangerous than two narrow ones (real
mining engineering's stand-up-time-vs-span relationship, e.g. Lauffer/
Bieniawski charts). Depth carries its own real hazards independent of
collapse: foul air (real "blackdamp" -- CO2 buildup / oxygen depletion from
poor natural ventilation, which gets worse the further a working sits from
open air) and flooding (real groundwater intrusion, which gets worse both
with depth relative to the water table and with proximity to a body of
surface water that can feed a breach).

## Real-world grounding

### The four layers

| layer | real correlate | typical real depth | what concentrates there |
|---|---|---|---|
| **topsoil / regolith** | weathered rock mantle | 0-3m | coal (shallow sedimentary seams) |
| **bedrock** | solid, unweathered upper crust | 3-50m | iron (banded formations reached by early shaft mining) |
| **deep bedrock** | crustal rock at real deep-mine depth | 50-300m | iron, at higher richness than bedrock |
| **hydrothermal zone** | fault/vein systems fed by circulating heated water | interspersed through the deep crust | copper (real porphyry/epithermal copper deposits are a hydrothermal phenomenon, not a random deep-rock inclusion) |

The depth figures are real orders of magnitude, not exact numbers a player
ever sees -- global regolith thickness genuinely runs a few metres on
stable ground, solid bedrock mining historically starts in single-to-low
double-digit metres, and the deepest real mines (South Africa's gold mines)
reach several kilometres, which is the same "keeps going, gets worse" shape
`deep bedrock` models. Copper is weighted toward the hydrothermal layer
specifically because real porphyry copper deposits genuinely form that way
-- this is the one place this doc's ore weighting is grounded in a named
real-world DEPOSIT TYPE rather than just "rarer/deeper", the same way
`stone.md`'s size classes are grounded in the real Wentworth scale rather
than invented tiers.

### Collapse: stress grows with the square of the span

A real unsupported roof span bends under its own weight like a simple beam;
simple-beam bending stress scales with span SQUARED, not span itself, which
is exactly why historic room-and-pillar mining kept unsupported spans to a
strict few metres between timber sets rather than treating "a bit wider" as
proportionally a bit riskier. `TunnelSupport.collapse_chance_for` models
that squared relationship directly: chance is ~0 below a real safe-span
reference (mirroring that historic timber-set spacing) and climbs with the
square of how far the span exceeds it, capped at a ceiling so a very wide
opening is dangerous but not an instant, un-survivable guarantee.

### Foul air deepens with distance from open air

Real "blackdamp" (oxygen-depleted, carbon-dioxide-enriched mine air) is a
ventilation problem, not a chemistry one: natural convective airflow (the
stack effect that keeps a mine shaft breathing) weakens the further a
working sits from an opening to the surface, so foul air risk is
overwhelmingly a function of how deep/enclosed the layer is, not what rock
it cuts through. `foul_air_at(layer)` is a monotonically increasing risk
by layer for exactly that reason -- topsoil/regolith workings sit close
enough to the surface to ventilate passively; the hydrothermal zone does
not.

### Flooding compounds depth with nearby water

Real groundwater intrusion has two real, independent drivers this doc keeps
separate rather than folding into one number: how likely a layer is to sit
below the local water table at all (deeper layers, more likely), and how
hydraulically connected a specific working is to a body of surface water
that can feed a breach (closer, more likely -- real mine flooding disasters
are disproportionately breaches into a nearby flooded channel or an old
flooded working, not a dry deep mine spontaneously flooding). `flood_risk_at
(layer, distance_to_nearest_surface_water)` multiplies a per-layer base risk
by a falloff on that distance, so a shallow working right under a lake can
still be dangerous, and a deep working far from any surface water is safer
than the depth alone would suggest.

## Mechanism

**Strata** (`src/world/strata.gd`) is the pure per-chunk, per-layer sim: for
a given `(layer, chunk_origin, local_cell)` it deterministically answers
whether that cell is `SOLID` rock, an `ORE` deposit (and which ore), or
already an open `TUNNEL` -- the same "hash the coordinates, compare to a
density" idiom `StonePlacement`/`OrePlacement` already use, just re-keyed by
layer instead of biome. Mining a cell (`mine_at`) is the one piece of real
mutable state it carries: once mined, that cell is `TUNNEL` for the rest of
that `Strata` instance's life, mirroring a played-out stone/ore node's
`queue_free` permanence.

**Cave entrances** (`src/world/cave_entrance_placement.gd`) are placed the
same deterministic-hash-per-tile way as `StonePlacement`/`OrePlacement`,
sparse and weighted toward the `mountain` biome (real cave/adit mouths
overwhelmingly occur where exposed rock already breaks the surface, not on
flat ground) -- mirroring `MountainOrePlacement`'s own "takes slope/biome as
input, doesn't compute it" convention.

**Reveal-on-entry, reused recursively.** Standing on a placed cave-entrance
tile reveals a real chamber of `Strata` topsoil/regolith cells around it --
the exact `RoomDetector.room_containing` + `paint_roofs(hidden_cells)`
shape `building.md` already uses for indoor reveal, generalized: instead of
ERASING a roof tile while the player is under it, the diggable-rock layer
SPAWNS real mineable nodes for the chamber's cells while the player is near
the entrance, and despawns them (without losing the `Strata`'s own mined-
state, which lives independently of whether a node is currently spawned to
represent it) once the player leaves. Each of the deeper three layers
(bedrock, deep bedrock, hydrothermal) is reached the same way in principle
-- a shaft found while digging the layer above, recursively re-running this
exact reveal mechanism one layer down -- but only the topsoil/regolith
reveal is actually wired to the engine today; see Status.

**Mining a diggable rock cell** behaves exactly like `MinableOre` -- a
`SOLID` cell yields plain stone, an `ORE` cell yields ore scaled by
pickaxe power through the same `OreYield` shape, both dropped via
`WorldItemBus` -- because it uses the same swing-driven "attack" interaction
and the same hover-tooltip contract every other world object in this game
already uses (see `CLAUDE.md`'s house-style notes); there is no dedicated
"dig" key.

## Status

- ✅ `Strata`: per-chunk, per-layer solid/ore/tunnel cell sim, all four
  layers configured (topsoil/regolith, bedrock, deep bedrock, hydrothermal),
  deterministic, with real mining mutation (`mine_at`).
- ✅ Layer-aware ore genesis (`GeologyOreGenesis`), extending
  `OrePlacement`'s coordinate-hash shape with real per-layer ore weighting
  (coal favored shallow, iron favored bedrock/deep bedrock, copper favored
  the hydrothermal zone -- grounded in real porphyry copper deposit
  genesis, see "Real-world grounding" above).
- ✅ `TunnelSupport.collapse_chance_for(unsupported_span)`: real
  span-squared bending-stress relationship, zero below a real safe-span
  reference, capped at a ceiling.
- ✅ `foul_air_at(layer)` / `flood_risk_at(layer, distance_to_nearest_surface_
  water)`: real, tested, per-layer hazard functions (`GeologyHazards`).
- ✅ `CaveEntrancePlacement`: sparse, deterministic, mountain-biome-weighted
  cave-mouth placement, mirroring `StonePlacement`/`OrePlacement`'s own
  convention.
- ✅ Topsoil/regolith layer wired fully end-to-end and playable: standing
  near a placed cave entrance reveals real `Strata`-sourced diggable rock/
  ore cells (`DiggableRock`, mirroring `MinableOre`'s shape exactly --
  real `WorldItemBus` drops, real removal, same hover-tooltip contract),
  and they despawn (without losing mined state) once the player leaves.
- ⬜ The physical shaft/transition from topsoil/regolith down into bedrock,
  and bedrock into deep bedrock, and deep bedrock into the hydrothermal
  zone -- i.e. the engine-side "walk onto a shaft cell found while digging
  layer N, reveal layer N+1" wiring. All three deeper layers' `Strata`
  configuration, ore weighting, and hazard functions are fully implemented
  and fully tested; the game does not yet let a player physically reach
  them. A deliberately scoped, honestly documented gap -- see this
  system's task scope note.
- ⬜ Collapse/foul-air/flood-risk are not yet triggered as live gameplay
  events (no actual cave-in, no actual air/water damage-over-time tick).
  The pure hazard functions exist and are tested; nothing calls them from
  the diggable-rock reveal/mining path yet.
- ⬜ Underground art: `DiggableRock` currently draws with the existing flat
  procedural stone/ore fallback (`ProceduralStoneSprite`/
  `ProceduralOreSprite`), not a cave-specific illustrated sheet -- no such
  sheet exists yet, the same honestly-documented fallback `stone.md`
  itself already describes for any future stone class with no art of its
  own.
