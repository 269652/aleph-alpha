# Wayfinding & Instruments

Most of this project's items get their behavior for free: a sword cuts
because of its material's hardness, a raft floats because of its
material's buoyancy, a torch burns because wood is flammable —
[materials.md](materials.md)'s property/shape grammar resolves almost
everything without anyone authoring "sword behavior" by hand. This doc is
the deliberate exception list: **items whose entire job is telling the
player something true about the world — direction, position, weather, or
time — which is not a physical property of the item itself and has to be
read from real game state instead.** A compass doesn't cut anything or
weigh anything; its only job is to correctly answer "which way is north,"
and that answer has to come from somewhere real.

## Why these can't emerge from physics

[synthesis.md](synthesis.md)'s own north star is "compose primitives, let
simulation resolve the result" — but an *instrument* isn't a physical
interaction between two objects, it's a **read + a UI**. A compass needle
doesn't swing because of Newtonian mechanics this game simulates (there is
no real magnetic field model here, nor should there be one for this); it
swings because game code asks "where is true north / my waypoint / my
home" and draws the answer. The same is true for a map (asks "which tiles
has this player actually visited," which needs a new **explored-tiles**
record — nothing currently tracks this), a weather glass (asks
[weather.md](weather.md)'s own live simulation what's coming), and a star
chart (asks [world.md](world.md)'s season/day-night clock). Every one of
these is legitimate, real information — this project already simulates
the answer — the gap is only that nothing surfaces it to the player yet.

## Design pillars

1. **Read real state, invent nothing.** Every instrument below answers its
   question from a system this project already runs (real tile
   coordinates, real weather, real season/day clock, real chunk
   load history) — never a value invented just for the item to have
   something to show.
2. **New tracking is scoped to exactly what's asked.** Where an instrument
   needs state that genuinely doesn't exist yet (explored tiles, for the
   Map), that gap is named explicitly rather than smuggled in as if it
   were free.
3. **Instruments are knowledge, not power.** None of these grant combat
   stats or crafting shortcuts — they only ever reveal information the
   simulation already has. This keeps them orthogonal to
   [items.md](items.md)'s rarity/affix system: an instrument's "quality"
   (see each entry) is about clarity/range of the information it reveals,
   never a stat roll.
4. **Reuse the crafting grammar for acquisition.** None of these are loot-
   table drops or vendor-only purchases by default — each has a real
   [crafting.md](crafting.md)/[materials.md](materials.md) recipe, so
   *how* a player gets one is the same "gather real materials, craft a
   real blueprint" loop as everything else, not a special case.

## Compass

Points toward one of two real references, switchable by the player:
**true north** (this world's own fixed +Y axis — see
[world.md](world.md)'s toroidal-map decision; "north" is simply a
constant screen/world direction, not a simulated magnetic field) or a
**bound waypoint** the player has set (see Waystone below, or a simple
"mark this spot" action with no crafting prerequisite beyond owning a
compass at all). Bearing is computed live from the player's real world
position and the target's real world position — literal vector math, no
new coordinate system. `EarthChunkManager._spawn_chunk_coord` (already
real, already used for region-difficulty tiering) is the natural default
target before the player ever sets their own waypoint — "point me home."

**Quality axis**: a rough compass only reads to the nearest 45° (matching
a genuinely crude needle); a fine compass reads exact bearing. This is a
real crafting-material question ([materials.md](materials.md) — a
magnetized-quality metal vs. a rough forged sliver), not a rarity roll.

## Map

A real, per-player record of **which tiles this player has actually been
within visibility range of**, rendered as a scaled-down, fogged
representation of the real terrain (biome color, elevation shading —
reusing [terrain_relief.md](terrain_relief.md)'s existing hillshade data,
not a second terrain renderer) — unexplored tiles stay blank. This is the
one instrument here that needs genuinely new tracking: nothing currently
records "has this player seen this tile," so a Map's real prerequisite is
a new **explored-tiles** record (a per-player set of visited chunk
coordinates is the natural granularity — chunk, not tile, matching every
other per-chunk system in this project, from ecosystem state to path
wear).

Once explored-tracking exists, a Map is a pure, honest reader of it —
disabling/losing the map item doesn't erase what the player has actually
seen, the same "disabling the surface must not remove the underlying
fact" principle
[docs/emergence/07-implementation-roadmap.md](../emergence/07-implementation-roadmap.md)'s
Phase 12 quest work already established for quests-as-projections. A real,
causally-grounded settlement, ruin
([exploration.md](exploration.md)), or worn road
([infrastructure.md](infrastructure.md)) appears on the map once its
tile has been explored — never a hint marker for something the player
hasn't actually found.

**Quality axis**: map resolution/detail level (does it show elevation
shading, does it label a discovered settlement's real name) scales with
the paper/ink-equivalent material it's drawn on and, once
[skills.md](skills.md) has a relevant node, the player's own cartography
skill — again a real material/skill input, not a rarity roll.

## Spyglass

Extends the player's own effective *sensing* range for anything already
real and discoverable at range — a distant settlement's smoke, a worn
road's own line, a grazing herd — without adding a new "detection" stat.
Mechanically the simplest of this doc's items: it doesn't reveal anything
that isn't ALREADY real and present, it just lets the existing
interaction-prompt/hover systems (see
[world.md](world.md)'s own "universal hover tooltip", already shipped)
resolve from further away when looking through it. Built from a
transparent, precisely-shaped material — a real
[materials.md](materials.md) optical-clarity property this doc doesn't
invent, just reads.

## Weather glass

A barometer-equivalent that reads
[weather.md](weather.md)'s own live simulation state a short real time
ahead of when a change actually lands — "storm coming" a real number of
in-game hours before it does, not a random flavor message. Since
`weather.md`'s own simulation already has to compute its next state
internally to transition smoothly, this item's whole job is exposing that
already-computed near-future value to the player early, at a resolution
("rain likely," not an exact hour) that reads as instrument-grade
uncertainty rather than a cheat-omniscient forecast.

## Star chart / seasonal almanac

Reads [world.md](world.md)'s own real day/night and season clock and
projects it forward — when the season will turn, roughly how many
real-world-grounded days remain in the current one, and (once
[climate_dynamics.md](climate_dynamics.md)'s live weather-cycle
simulation exists in enough places to matter) which regions are
seasonally best for what — again, always a real, already-simulated
number, read early, never invented.

## Waystone

The physical anchor a Compass/Map can point to and (per
[transportation.md](transportation.md)'s own still-open "fixed waypoint
network vs. craftable personal-portal" question) a candidate answer to
that exact open question: a Waystone is a **player-placed, real,
persistent world object** (same persistence convention as any other
player-built structure — see [persistence.md](persistence.md)) that
registers its own real chunk coordinate as a nameable waypoint. Placing
one doesn't itself grant fast travel (that's `transportation.md`'s own
mechanism to resolve); it's the compass/map layer's own answer to "which
real point in the world does the player care about enough to navigate
back to."

## Status

Originally a pure spec pass with nothing implemented, scaffolded per
`CLAUDE.md` ahead of any code. Building order, if picked up: Compass
first (needs zero new tracking, only real position math against an
already-real reference point), then Map (needs the new explored-tiles
record, which Spyglass/Weather glass/Star chart don't require), then the
read-only instruments (Spyglass, Weather glass, Star chart — no new
tracking, only new UI over already-simulated state), then Waystone
(depends on `transportation.md`'s own open waypoint-network question
being resolved first, so this doc doesn't pre-empt that decision).

All five non-Waystone instruments are now real (see `docs/progress.md`'s own
Wayfinding & Instruments entry for the full, current breakdown): Compass's
pure bearing math (`src/gameplay/compass.gd` — real bearing against this
world's fixed +Y-north convention, plus the rough/fine quality-axis
reading; `test_compass.gd`, 12/12 passing), Map's explored-tiles/
projection layer (`ExploredTiles`, `MapProjection`), Spyglass's hover-radius
relaxation, Weather glass's one-day-ahead read, and Star chart's
season-forward projection. `EarthChunkManager` exposes each's own
prerequisite as a real coordinator method (`spawn_chunk_coord()`,
`mark_chunk_explored`/`explored_chunks`/`is_chunk_explored`,
`current_weather`/`upcoming_weather`, `current_season`/`world_age_seconds`),
and each now has a real call site reading the player's actual position/
inventory: `/compass`, `/map`, `/weatherglass`, and `/almanac` are real dev-
console commands (`World._on_console_command`, `scenes/world.gd`), each
gated on the player actually owning the item; Spyglass is a real LIVE
passive effect on `World._update_hover_tooltip` rather than a command
(equipping one measurably relaxes `HoverTargetFinder`'s hover radius — this
required a real fix to `HoverTargetFinder.info_under`, which previously
re-capped its own selection at the bare constant regardless of the
caller's widened scan radius; it now takes an explicit `radius` param).
What's still missing for all five: only in-world UI (compass-needle
sprite, a real fogged map render, an on-screen forecast label, etc.) — the
dev console is a real, honest interim call site, not the design's own
final interaction, the same role `/give`/`/craft` already play elsewhere
in this project. Map's own remaining gap is unchanged: nothing calls
`mark_chunk_explored` from the player's actual movement/visibility-range
path yet (deliberately out of scope — see `ExploredTiles`' own doc comment
on why "when does a chunk get marked explored" stays a caller-side decision
for later).

Two of this doc's own named quality axes are still binary, not yet the
graded material/skill axis described above: Compass's rough/fine split is
real and tested (`rough_compass` vs. `compass`, the latter gated on owning
an `iron_ingot` rather than a plain stick/fibre input), but that's one
upgrade tier keyed to "which raw material," not yet this section's own
described magnetized-quality-metal property distinct from any other iron
ingot — `materials.md` has no such magnetic-quality axis to read yet. Map
is a single item with no resolution/detail tiers at all — no paper/ink-
quality material axis and no `skills.md` cartography-skill hook, since
neither a tiered Map recipe nor `skills.md` itself exist yet. `ExploredTiles`
also remains in-memory/session-only, not yet persisted across save/load (a
named gap in its own doc comment, unchanged by this pass — see the
per-player-vs-per-save Open Question below, which that persistence work
will need to answer). Waystone remains deliberately deferred (see its own
bullet above) — none of this pass touched it.

## Open questions

- Per-player vs. per-save explored-tiles: does a second character sharing
  a world start with a blank map, or does exploration belong to the
  world/save rather than the individual character? Ties into
  [persistence.md](persistence.md)'s existing player-vs-world save split.
- Does a Map ever go stale (a settlement that later became a ruin still
  drawn as a thriving settlement until re-visited), or does it always
  redraw live from current state the instant it's opened? The latter is
  simpler and arguably more honest to "read real state, invent nothing,"
  but a live-updating map the player never has to re-explore reduces the
  incentive to actually revisit a place.
- Multiplayer: is explored-tiles shared across a party (discover together)
  or strictly individual? No multiplayer exploration-sharing convention
  exists yet to extend.
