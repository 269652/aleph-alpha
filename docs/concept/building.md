## Player agency: building, base, and eventually society

- Terraria-style tile placement/destruction: build a house, a base, dig
  through terrain. Persists in the chunked world (see [world.md](world.md)).
- See [housing.md](housing.md) for the expressive/social decoration layer
  on top of this functional placement system.
- Longer-term: MMO-driven villages, player-influenced economy, and society —
  explicitly a post-MVP layer built once single-player building/persistence
  and the ecosystem/NPC simulations are solid (see
  [../roadmap.md](../roadmap.md)).

## Base defense: diegetic threat, not scripted raid waves

Decided in a 2026-07-16 brainstorm against Valheim's escalating-raid mechanic:
**the homestead does not attract scripted, automatically-scaling monster
waves as it grows.** That would contradict the danger gradient's own premise
([synthesis.md](synthesis.md)) that civilization/home is the safe end of the
axis.

Instead, any threat to a built-up homestead is **diegetic** — it follows from
the same simulated causes as everything else, not a difficulty dial:

- A ranch holding high-fitness/rare-DNA stock is a genuinely valuable target,
  so **rival dynasties or NPC poachers** (per [factions.md](factions.md)'s
  emergent reputation/competition and [pvp.md](pvp.md)'s zone-based stakes)
  may actually come for it — the same butcher-vs-breed-vs-tame incentive
  that applies to wild apex creatures applies to *your* prize breeding stock.
  This is competition between lineages, not a wave-defense minigame.
- Ordinary wildlife has no reason to suddenly assault a settled area; if it
  ever does, it should be traceable to a real simulated cause (a
  drought pushing a starving population toward the only remaining food
  source, e.g.), not an abstract "threat level" counter.

This applies identically to NPC villages, not just the player's own
homestead — a settlement's wealth and population are the real cause behind
any threat it faces, never a difficulty dial. See
[quests.md](quests.md#village-endangerment-the-attractor-mechanism) for the
full mechanism, and [npc.md](npc.md#settlement-growth-migration-toward-player-built-structures)
for how a player-built structure cluster is, mechanically, the same kind of
settlement as an NPC village once it grows enough to qualify.

## Buildings are entities; interiors are scenes

Decided 2026-09-14, after a full pass of fixes to the piece model below
(roofs from above, facades, wall thickness, invisible furniture, doors that
could not be reached) all traced to one root cause: a real building is a
3D thing, and drawing it as a ring of top-down tiles never reads right.
The user's call: *"change the housing completely and make them a single
sprite / entity like in Anno... NPCs would then be able to use algorithms
to build efficient villages / cities with Anno like constraints. The
player can enter buildings or houses which would then load and switch to
the interior scene... so a House small from the outside would be big
inside."* This section is the spec for that model; the piece model that
follows it is retained only for structures older saves already contain.

### Design pillars

1. **One building, one entity.** A building is a `BuildingCatalog` id with
   a rectangular footprint in tiles, a door cell on its south edge, and a
   doorstep (the tile just south of the door). It is drawn as ONE sprite
   standing on its footprint, collides as ONE body covering the footprint,
   and is owned as ONE property. No cell of it is walked into from outside.
2. **The exterior is Anno, the interior is Stardew.** Outside, the world is
   the top-down map it always was and a house is a 3/4-view illustration
   on it. Entering is a real transition into an authored interior room
   that can be larger than the footprint, with real walls and furniture the
   player collides with, and a way back out at its door.
3. **The sheet is the lifecycle.** Every building sheet is one file,
   1536×1024, eight columns by five rows, black background, magenta
   dividers — exactly the convention `assets/sprites/buildings/
   blacksmith.png` (and farmhouse/sawmill/warehouse/city_hall/brewery)
   already follow. Row 0: eight construction stages; row 1: ACTIVE
   (chimney smoke, lit windows — an eight-frame loop); row 2: IDLE; row 3:
   BURNING; row 4: RUINED. A building's `progress` (construction), the
   time of day / whether anyone is home (active vs idle), and its
   `condition` (burning, then ruin) each pick a row; nothing about the
   lifecycle is invented in code that the art does not already show.
4. **One system, two builders — still.** The village generator and the
   player place the same entities from the same catalog through the same
   `place_building` call and the same `ConstructionProject` ledger; a
   villager's house and the player's own house are the same kind of thing
   with different owners.
5. **Villages are laid out, not scattered.** Buildings stand on streets:
   a road is laid first, houses take road frontage with their doors facing
   it, spaced by rule, the plaza (well, stall) sits on the main street and
   the gate at its end. The layout is a pure, seeded, testable algorithm
   over a buildability predicate — Anno's constraint style at village
   scale, with room for growth rules later.
6. **Nothing the world already knows about buildings changes shape.** A
   building's anchor cell carries its id in `chunk.modifications` exactly
   like today's single-tile placeables (campfire, sagewerk, city_hall), and
   every other footprint cell carries the reserved `building_footprint`
   marker — so every existing "is structure X within N tiles" scan,
   occupancy check, settlement census and construction decision keeps
   working unchanged, and a building persists as chunk data the way
   everything else does.

### Mechanism

**Catalog** (`BuildingCatalog`, pure data): `house_small` (2×2),
`house_medium` (3×2), `house_large` (4×3) to start; per id a footprint,
door (`x = width / 2` on the bottom row), doorstep (door + (0, 1)), sheet
path (`assets/sprites/buildings/<id>.png`, drawn by a procedural
placeholder box until the file lands), interior family, capacity, labor
hours and material cost (the existing house recipes' inputs).
`choose_house_id(occupation, genome, seed)` is `HouseBlueprint.
choose_blueprint_id`'s own occupation-pool + personality-nudge rule over
the new ids, so a village keeps its variety. `occupies(tile_id)` is the one
predicate the occupancy seams read (ground-cover blocking, the tree apron,
water reclaim, siting).

**Placement** (`EarthChunkManager.place_building(chunk_coord, origin,
id, facing, seed, owner)`): writes the anchor id and footprint markers,
records `Chunk.buildings[origin] = {id, facing, seed, condition, progress,
owner}` (persisted as its own per-chunk file, like roofs/furniture), spawns
the node immediately (a `Node2D` at the footprint's bottom-centre so
Y-sorting is against the building's base — a `Sprite2D` child offset
upward, and a `StaticBody2D` covering the footprint on the ground collision
layer), and clears/blocks vegetation on the footprint as a stamped
structure does today. `remove_building` reverses all of it.
`building_at_global(x, y)` answers for any footprint cell;
`building_door_near(pixel, radius)` finds a doorstep for the Enter prompt.
Facing is south only in this pass (every sheet is drawn south-facing);
the field exists so a later pass can add other faces.

**Village layout** (`VillageLayout.layout(...)`, pure): a main east–west
street through the chunk's middle, paved end to end as the real Road
tile (`TerrainRenderer.ROAD_TILE_ID` — the infrastructure doc's Road
tier, a LAID surface that never wears and nothing grows on; older saves'
trail-drawn streets are repaved on load), with a paved **plaza** at its
centre (`VillageLayout.skeleton`: 8 tiles wide, three rows north of the
street and two south) — the **civic plot** on the plaza's north half is
the town hall's reserved site, its door on the street ([civic_construction.md](civic_construction.md):
the hall rises there over time), the **well** and the **stall** stand on
its south half, and a **gate** marks the street's entrance at its west
end. Houses take the NORTH side of each street so every door faces south
onto it (the doorstep IS a road cell), one-tile gaps between plots, never
straddling the plaza; when the main street is full the next opens a
fixed pitch further south, tied back to the plaza by two side streets
down its flanks. A village whose square isn't clear (water, forest, an
old house standing on it) gets no plaza and no hall — honestly, tested —
rather than a square with a lake in it. The plaza and landmarks are a
pure function of the chunk and its seed, so an older village re-derives
and paves its square on its next load where it is clear
(`VillageRenderer._lay_plaza_if_missing`) without persisting anything.
`SettlementGenerator` derives its landmark positions from the same
skeleton, so props and paving always agree. Every plot's footprint and
doorstep must be buildable (`is_buildable_terrain_at`) and unmodified;
a villager whose plot fits nowhere stays homeless, as today, rather than
being squeezed onto water or forest. `SettlementGenerator` keeps its
outputs (`house_positions` become doorsteps, which is what every consumer
used); `VillageRenderer.spawn_village` places buildings instead of
stamping pieces, sets each villager's home to its doorstep, hides a
villager who is "at home" (they are inside), and keeps landmarks, workspot
props, market and settlement founding exactly as before.

**One house id.** Every village house gets a `ConstructionProject`
(created and completed at once, per [civic_construction.md](civic_construction.md)'s
"village houses, properly"), so `record_settlement_founded_if_new` grants
`project.property_id()` (`house_<cx>_<cy>_<ox>_<oy>`) — the single scheme
player houses already use; the per-cell `_piece_property_id` and the
per-villager-index id are retired.

**Entering** (`HouseInteriorView`): standing on a doorstep shows "Enter";
the interior is an authored `InteriorTemplates` room plan — v2
(2026-09-16): multi-room (interior partitions with gaps; a cottage's
bedroom and hearth room, a house's three rooms, a manor's four), windows
on the outer wall, one or two candles for light, one cell the resident
stands on when home, and typed slots (bed, table, seat, rug, shelf,
picture, hearth, workshop piece, light) that `HouseDecor.piece_for_slot`
fills for the resident's REAL occupation (from the building record — a
smith's workshop slot is an anvil, a farmer's a barrel, a merchant sits on
a couch and shelves books where a working household has a chair and a
cupboard); three plans per family, picked by the house's seed, every plan
validated (enclosed, one south door, every room reachable). Drawn from the
existing tile set (the illustrated floor/wall/window/furniture tiles —
furniture is procedural until its PNG lands, see the asset contract), its
walls, windows and solid furniture (bed, table, bookshelf, couch, hearth,
workbench, anvil, barrel, crate, chest, cupboard — a chair, rug, picture
or candle you walk past) as bodies on their own `INTERIOR_COLLISION_LAYER`,
each candle an additive `TorchGlow` quad, plus a real threshold body one
cell past the door so nothing but the real Leave action gets a player
out. This is
built inside an **isolated `SubViewport`** (`World._build_interior_view`,
the same real "a separate scene, not paint" pattern the character
creator's own diorama already uses), stretched full-screen through a
`SubViewportContainer` — not a `Node2D` sitting among the outdoor
world's own nodes any more (an earlier version was exactly that, and the
real outside world kept showing through around whatever patch of floor a
backdrop failed to out-cover; no backdrop sized to a room can out-cover a
camera that is bigger than every room). The interior gets its own
`Camera2D`, fit to the room's own size (however small) rather than reusing
the outdoor world's fixed 4x zoom, so the room actually fills the screen.
The real (possibly networked) Player node is untouched for the whole
visit — no collision/z-index/position change, it simply stays parked at
the real doorstep — so chunk streaming, NPC schedules and the clock all
keep running unaffected — **time does not stop indoors.** `InteriorAvatar`,
a small local-only stand-in that exists only inside the isolated
SubViewport, is what actually walks around; the real Player's own step
still keeps survival, mana, talking and inventory running (warmth indoors
is a constant) but no longer touches movement or the character view at
all indoors. "Leave" on the interior's own door cell (checked against the
avatar's position) frees the interior's content and hides the viewport;
nothing about the real Player changes. Predators do not target an indoor
player.

**Residents inside.** The indoor avatar is the player's own character —
`InteriorAvatar` hosts a real `CharacterView` dressed from the player's
appearance, every worn armor slot and the held weapon (`Player.
_interior_outfit`), animated by its own walking. And the house's own
villager is there when they are home: `EarthChunkManager.
resident_marker_for(record)` finds the outdoor `NpcMarker` whose identity
seed the record remembers (older records fall back to the marker whose
home is this doorstep), and if that marker `is_at_home()` — the very same
"arrived home on a home-tagged entry" state that hides it outdoors, so a
villager is never in two places — `HouseInteriorView.place_resident`
stands an `InteriorResident` on the template's own resident cell: their
own `CharacterView` dressed by `HeroAppearance` for their occupation and
seed (identical to the outdoor dressing, so it IS the same person),
facing the door, idle, solid on the interior layer. A villager who is out
at the well leaves an honestly empty house. Talking works indoors exactly
as outdoors (`Player._talk_target_identity`: the resident within the same
`TALK_RADIUS` of the avatar, the same greeting); World's indoor prompt
shows "Leave" on the exit cell, else "Talk" within reach of the resident,
else nothing. Doorstep scans (`nearest_npc_near`) skip at-home villagers,
so "Enter" is what a doorstep offers rather than a "Talk" through the
wall.

**Older saves.** A settlement chunk that has no buildings yet but still
holds piece-built houses has those pieces (and their roof/furniture/upper
entries) wiped once on load, excluding any cell covered by a player-owned
`ConstructionProject`; the village then regenerates as buildings. Player-
built piece structures stay exactly as they are and keep the legacy
mechanisms below (rooms, roofs, upper floors) until their owner rebuilds
them in the new model — nothing of the player's is deleted.

**Retired for houses, named honestly**: per-piece statics and withering
(a building has one `condition`; ruin is a sheet row, not a collapse
graph), the roof/facade/upper-floor paint families, room detection for
"is the player indoors" (an interior is a scene, not a flood fill),
two-story stairs (an interior template may have more than one room).
Player piece placement is retired with them; the player's blueprint build
places a finished building through the same ledger, and hiring a builder
for a house returns in the construction-over-time pass. See Status.

### Asset contract (what an artist/generator must deliver)

Everything below lights up by dropping the file in and bumping
`TerrainRenderer.ATLAS_VERSION` (tiles) or simply relaunching (sheets);
there is no registry to edit. Until a file exists, a procedural placeholder
draws so the system is playable and testable without art.

**Building sheets** — `assets/sprites/buildings/<building_id>.png`
(`house_small`, `house_medium`, `house_large`, `city_hall` …), 1536×1024,
8 columns × 5 rows, black background, magenta cell dividers. Rows: 0
construction ×8 (scaffold → shell → roof, left to right), 1 active ×8 (lit
windows / chimney smoke loop), 2 idle ×8 (loop or repeats), 3 burning ×8,
4 ruined ×8. Each cell is scaled on screen so the cell's WIDTH equals the
footprint's width (`footprint_frame_texture`): a `w`-wide house draws
16·w px wide and 17·w px tall. The bottom `d` tiles of that height are the
ground footprint — draw the roof there, seen from the top-down camera —
and everything above overhangs the row north of the house. The door must
sit on the bottom edge in column `w/2` (integer division, i.e. right of
centre for a 2-wide house), the whole facade south-facing. Until the
file exists, `ProceduralBuildingPlaceholderSprite` draws a roof-over-walls
box of the right footprint. (Construction progress will pick row 0's
column from `progress` — `clampi(floori(progress × 8), 0, 7)` — once the
village raises buildings over time; today only row 2 is shown.)

**Furniture tiles** — `assets/sprites/furniture/<piece_id>.png`, one
square image per `CATEGORY_FURNITURE` piece id (`wood_bed`, `wood_table`,
`wood_chair`, `wood_rug`, `wood_bookshelf`, `couch`, `photo_frame`,
`hearth`, `workbench`, `anvil`, `barrel`, `crate`, `chest`, `cupboard`,
`candle`), any size ≥ 128 px, top-down, the object centred, background
transparent or the sheets' own near-black / magenta (keyed by the same
pass the wall sheets use). `IllustratedBuildingPieceSprite` composites it
over the wood floor and resizes it to `ART_TILE_SIZE` (32 px), so the tile
stays opaque; until the file exists, `ProceduralBuildingPieceSprite`
draws the piece. Only a real furniture id is ever looked up there.

**Road tile** — `assets/sprites/terrain/road.png`, one seamless 32 px
tile, no dividers, no directional variants (see
[infrastructure.md](infrastructure.md)).

### Status

- ✅ **Catalog + world registry.** `BuildingCatalog`, `Chunk.buildings`,
  `EarthChunkManager.place_building`/`remove_building`/`building_at_global`/
  `buildings_in_chunk`/`building_door_near`, real node + collision, water
  reclaim on load. Tested (`test_building_catalog.gd`,
  `test_earth_chunk_manager_buildings.gd`).
- ✅ **Village layout.** `VillageLayout`'s real road-frontage placement;
  `VillageRenderer` rewritten around it end to end — chooses each
  villager's house, places real buildings before roads (a real ordering
  bug found and fixed here, see `docs/progress.md`), sets each NPC's home
  to its real doorstep, hides a villager once they've actually arrived
  home, is idempotent across reloads (a real duplication bug found and
  fixed, see `docs/progress.md`). Village houses own real property
  through the same `ConstructionProject`/`HouseholdStore` scheme the
  player's own houses use ("one house id"). **Layout v2 (2026-09-16):**
  real Road-tier streets paved end to end, a central plaza with the civic
  plot / well / stall on it, a gate at the street's entrance, side
  streets to a second street, landmarks derived from the same skeleton,
  older villages' plazas re-derived and paved on reload where clear
  (`test_village_layout.gd` 26, `test_settlement_generator.gd`,
  `test_village_renderer.gd` 36). Each house also remembers its own
  villager (occupation + identity seed on the record, backfilled for
  older saves on reload) so the interior is furnished for the real
  resident.
- ✅ **Older saves.** A settlement chunk still carrying old-style
  piece-built houses has them wiped once on load and regenerates as
  whole-building entities in the same load, protecting any player-owned
  piece structure at the same site.
- ✅ **Entering.** `InteriorTemplates` (real authored room shapes ×
  occupation-themed furniture) + `HouseInteriorView` (the real scene:
  shared-tile-set floor/wall/furniture, real collision including a door
  threshold, a room-fit `Camera2D`) built inside an isolated `SubViewport`
  (`World._build_interior_view`) so the real outdoor world can never show
  through, + `InteriorAvatar` (the local-only stand-in that actually walks
  around inside it) + player indoors state (`is_indoors`/`enter_building`/
  `exit_building`, `_authority_step_indoors` — the real Player node itself
  is never moved or re-collided, only parked) + World's "Enter"/"Leave"
  prompt + the predator-targeting gate. Tested end to end
  (`test_interior_templates.gd`, `test_house_interior_view.gd`,
  `test_interior_avatar.gd`, `test_player.gd`, `test_creature_marker.gd`,
  `test_world_interaction_prompt_throttle.gd`). The three gaps this
  redesign first shipped with are closed (2026-09-16): the avatar is the
  player's real `CharacterView` with armor and weapon; the interior is
  furnished for the resident's REAL occupation from the building record;
  and "Residents inside" is built — the at-home villager stands in their
  room as an `InteriorResident`, Talk works indoors, doorstep scans skip
  at-home villagers (`test_npc_marker.gd`,
  `test_earth_chunk_manager_prompt_scans.gd`).
- ✅ **Player building re-route** (2026-09-16). A learned blueprint places
  ONE real catalog house (`EarthChunkManager.BUILDING_ID_BY_RECIPE_ID`:
  small_house → house_small, cottage → house_medium, manor → house_large)
  through `place_building`, owned by the player's household on the record
  itself, and the existing ledger runs unchanged (a COMPLETE
  `ConstructionProject`, `HouseholdStore` property, move-in).
  `can_build_house_from_blueprint` validates the whole site — every
  footprint cell and the doorstep, in one chunk, buildable and empty (a
  road doorstep is allowed and stays paved). `Player.
  _try_build_house_from_blueprint` refuses to raise a house over the hero's
  own tile and leaves its reason or result in `house_build_message`
  (`/buildhouse` prints it). The ten two-story blueprints map to "" — "no
  whole-building form yet" — and are off the merchant's shelf until real
  two-story sheets exist. The instant hire fork (`hire_builder_for_house`
  and its `BuilderMarker` spawner) is retired with the piece pipeline: a
  build the player cannot do themselves says that hiring returns with
  construction-over-time ([workforce.md](workforce.md)). Legacy piece houses
  in older saves are untouched (`HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID` stays
  for them). Tested (`test_earth_chunk_manager_player_house.gd`,
  `test_player.gd`, `test_shop.gd`).

## Legacy: structure building from pieces (older player-built structures only)

Everything from here to "Persistence" describes the per-tile piece model
that preceded the entity model above. It is no longer used for any house
— village or player — and stays only because older saves contain player-
built piece structures that must keep working (rooms, roofs, upper floors,
furniture on their floors). No new mechanism should be built on it.

### What "enterable" meant in the piece model

Valheim and Atlas are 3D: you walk through a door and the walls are simply
around you. Top-down 2D has no such luxury — a roof drawn over a floor would
hide everything under it, and a player standing "inside" is, geometrically,
standing on the same plane as the roof.

So enterability is defined by **enclosure**, not by 3D space:

- A set of wall pieces **encloses** a region when that region cannot reach
  the outside world by orthogonal steps through non-wall cells. This is a
  flood fill from the region outward: if it escapes the structure's bounding
  box, the region is outdoors.
- An enclosed region with at least one floor piece is a **room**. A building
  is one or more connected rooms.
- Doors are wall-category pieces that are **passable**: they block the flood
  fill for enclosure purposes (a house with a closed door is still a house)
  but do not block movement, so the player walks in through them.
- A **roof** is drawn above its room's cells and hides while the player is
  inside that room, so the interior is visible exactly when it matters. The
  roof is what makes a house read as a building from outside without
  blinding the player within.

This gives the same player experience as the 3D games — approach, walk in
through the door, be inside a space that is yours — using the one mechanism
a 2D grid can express exactly.

### Pieces

Every piece is one tile. Categories, and what each is *for*:

- **Floor** — claims ground as part of a building. Walkable. Required for a
  room to count as a room (an empty walled ring is a fence, not a house).
- **Wall** — blocks movement and encloses. The structural backbone.
- **Door** — a wall that is passable. Encloses but lets people through.
- **Window** — a wall that is not passable but does not block sight lines
  (reserved for a later line-of-sight layer; today it is a wall variant that
  reads differently). In a settlement house, a window also glows at night
  (see [housing.md](housing.md#night-lighting-ambient)).
- **Roof** — covers a room; hidden while the player is inside it.

Each piece has a **material** (wood, stone) carrying cost, durability, and
look. Materials exist so building has a progression that follows the
existing gather → craft → smelt chain rather than being a flat cosmetic
choice.

### Placement rules

Rules exist to stop floating nonsense, not to nag:

- A floor may be placed on any buildable ground (not water, not on an
  existing structure piece). **Water is one rule, not several:** a cell is
  water for building exactly when the terrain painter would paint it as
  water — the ocean biome, a river's channel *plus its bank apron*, a lake,
  a sea pocket, or a still-water pocket too small to count as a lake but
  wet enough to paint (`EarthChunkManager.is_water_at_global`, the same
  predicate the river/lake overlay paints from). Before this the
  buildability check and the painted surface were two different
  predicates, and the gap between them is exactly where a stone house with
  a pond in its living room came from.
- A wall, door or window must sit on, or orthogonally touch, a floor piece
  — walls belong to a building, not to open wilderness.
- A roof must sit above a cell that is part of an enclosed room.
- Nothing may be placed where a piece already exists; destroying returns the
  piece's material (mirroring the existing build/destroy loop).
- **A piece occupies its tile against vegetation, in both directions.** A
  structure stamped onto a cell fells whatever is growing there (and forgets
  its persisted record, so it does not return from disk); a tile a real
  piece stands on grows nothing afterwards — no map-generated tree respawns
  onto it when the chunk reloads, and no spread or bird-dropped seed takes
  root on it. Only a *real* `BuildingPiece` occupies: an earth path or a
  campfire is a chunk modification too, and neither uproots a tree.
  The same holds for ground cover: tall grass, flowers, desert scrub and
  tundra lichen are cleared from every cell a real piece stands on and can
  neither seed, spread nor regrow there while the piece stands
  (`block_cells` on each cover simulation, wired at chunk load before the
  first sprite sync, at stamp and at player build; `unblock_cells` when the
  piece is destroyed). Trees keep a one-cell **apron** as well: no tree
  spawns or spreads onto a cell that touches a piece (8-neighbourhood,
  `BuildingPiece.touches_piece`), because a trunk against the front wall
  blocks the door as surely as one inside the room.

Placement validity is pure logic over a grid, so it can be asked the same
question by the player's build cursor and by the NPC village generator.

That purity is also why the vegetation rule above does **not** live in
`BuildingPlacement`: a grid of piece ids has no notion of a world with trees
standing in it. It is enforced instead at the three world-facing seams where
a tree and a piece can actually meet — see "One system, two builders" and
the status list below.

### One system, two builders

**NPC villages use exactly these pieces.** A village house is not a
decorative sprite with a painted-on door — it is a real assembly of floors,
walls, a door and a roof, generated from a blueprint, occupying real cells,
enclosing a real room the player can walk into. That is the point: the
player and the settlement generator build with one vocabulary, so anything
true of a player's house is true of a villager's.

`HouseBlueprint` turns a seed and a footprint into a piece list. The village
generator stamps blueprints; the player places pieces by hand. Neither
knows about the other.

This means the village generator's stamping bypasses `BuildingPlacement.
can_place` entirely (it writes chunk modifications directly, not through the
placement-validity check above) — a real gap: a house's ring-layout anchor
could land on a water pocket (a chunk's dominant biome only gates the whole
chunk, not every individual cell, so a grassland-dominant chunk can still
have a pond/river cutting through it) and get stamped straight into it.
`VillageRenderer._fit_house` closes the visible instances of this before
stamping: the whole footprint *and the doorstep outside the door* must lie
inside the chunk, on buildable ground (the one water rule above, no forest
biome, no standing tree) and free of any existing modification — so a
house can neither stand in a pond, nor be stamped over a neighbour, nor be
truncated at a chunk edge. `_find_clear_origin` searches outward from the
ring-layout anchor, nearest first, across the whole of the house's own
chunk (the chunk edge is the only bound — two of ten probed villages sit
in chunks that are ~85% lake, whose only dry ground lay 15-25 tiles from
most anchors) for the nearest origin that fits; if the chosen shape fits
nowhere, the villager builds a
smaller one from `_FALLBACK_BLUEPRINT_IDS` (a small cottage, then a tiny
hut), and only when not even a hut fits is the house skipped. This is
still a bespoke check rather than a call into `BuildingPlacement` itself
(walls needing an adjacent floor is not re-verified — a catalog blueprint
already guarantees it), so full unification — the village generator asking
`BuildingPlacement` the same question the player's build cursor does —
remains a follow-up.

A **second** instance of that gap has now been closed: standing vegetation.
Reported as a tree with its trunk rooted in a village house's stone floor
and its canopy drawn over the masonry. Unlike the water case it was *not*
closed inside `VillageRenderer`, because nudging is the wrong answer here —
trees only grow in forest/rainforest, so a village that avoided them would
have nowhere to go, and a real settlement clears the wood rather than
dodging it. It was closed on the world side instead, because the collision
has three directions, not one, and `_load_chunk`'s ordering means no single
site can see them all:

1. **The house arrives second.** `_load_chunk` spawns trees before it spawns
   the village that stamps houses over them, so on a fresh visit the
   structure lands on standing trunks. `EarthChunkManager.
   stamp_structure_at_global` now fells them (and prunes the matching
   `Chunk.planted_trees` records).
2. **The forest arrives second, next time.** `chunk.modifications` is loaded
   from disk *before* trees spawn, so without a check the deterministic
   forest respawns straight into a persisted house — including a
   player-built one the village generator never re-stamps.
   `TreeRenderer.spawn_trees` now skips a cell a real piece holds.
3. **A seed arrives later still.** `EarthChunkManager._can_root_at` now
   refuses a cell carrying a real piece, so nothing sprouts on a floor
   afterwards.

Boulders and ore have the identical bug with the identical shape, and are
now covered in directions 2 and 3's sense but not 1's: `StoneRenderer.
spawn_stones` (and `spawn_mountain_veins`, whose separate slope-gated
placement runs at the same point in `_load_chunk`) now skip a cell a real
piece holds, so stone no longer regrows inside a persisted house; nothing
seeds a boulder, so there is no direction 3 for it. Direction 1 — a house
stamped over a boulder that is already standing in this session — is still
open, and needs `_loaded_stones` added to `_clear_vegetation_on_cells`'s
loop. See the Status list below.

### A blueprint catalog, not one box

Reported directly: "the houses the npcs build are minimal and don't look
neat and diverse... we want Anno 1800 like houses and villages... so maybe
we need house blueprints which function as template/recipe for the npcs
building their houses... there should be enough different blueprints that
every house in a village can look different... NPCs choice though."

Before this, `HouseBlueprint` generated exactly one shape: a wall ring
around a floor interior, fixed at 5x4, with one seeded door and no windows
at all. Every villager in every settlement built the identical box, in one
of two materials. `HouseBlueprint` is now a real CATALOG of named shapes
(`HouseBlueprint.BLUEPRINT_IDS`) spanning a tiny one-room hut through
wide/tall/bright cottages to genuinely L-shaped manors — real footprint-size
and window-count variety, plus (for the L entries) a non-rectangular
silhouette, not just a recolour of the same box.

**Built from three safe, tested geometric primitives, not hand-pixeled
floor plans.** A blueprint recipe is a footprint size, a window count, and
an optional corner notch — `build()` assembles it by (1) filling a plain
wall-ring rectangle, (2) carving the notch out if the recipe declares one
(erasing those cells entirely and upgrading any newly-exposed floor cell to
a wall), then (3) punching a door and the requested number of windows
through whichever wall cells qualify. A cell qualifies for a door/window
when it has *exactly one* floor neighbour and at least one missing
(exterior) neighbour — one rule that correctly excludes both an ordinary
rectangle's corners (zero floor neighbours) and an L-shape's own inner
corner (two floor neighbours at once) without any shape-specific
special-casing. Hand-authoring each shape as raw ASCII art was considered
and rejected: it is exactly the kind of content that can silently produce
an unenclosed or two-door house with no obvious symptom until someone looks
at a screenshot; every blueprint this system can produce is provably a
real, single, enclosable room (verified by `RoomDetector` in the test
suite, for every catalog entry, not spot-checked).

**Which blueprint a villager builds is their own choice, not raw noise.**
`choose_blueprint_id(occupation, genome, seed_value)` picks from a
per-occupation pool (`HouseBlueprint.BLUEPRINT_POOL_BY_OCCUPATION`, ordered
plain → showy, weighted by simple repetition the same way biome species
pools already are) — a farmer or guard tends toward a hut or small cottage,
a merchant toward a bright or grand one, a blacksmith toward something wide
enough for a real workspace. The villager's `NpcGenome` (see
[npc.md](npc.md)'s "personality should be DNA derived") then nudges *where
in that pool* the choice lands: a bold/greedy-dominant NPC's roll is pushed
into the showy (larger/later) half of their own occupation's pool, a
cautious/stoic one into the plain half, a neutral trait picks uniformly.
Occupation decides what a villager could plausibly build; personality
colours which of those options they actually pick — the same "identity
actually matters mechanically" pillar this project's NPC system already
commits to elsewhere.

### How a house reads from above

A correct piece layout is not the same thing as a building that *looks*
like one. Reported directly, with the blueprint catalog above already in
place: "the buildings don't resemble houses at all... just some randomly
placed stones and wood panels". Three separate causes, each structural
rather than a matter of prettier textures:

**1. The roof is the exterior, so it must cover the exterior.** Roofs
originally covered only the FLOOR cells — the room interior — leaving the
wall ring uncovered. From above that reads inside-out: a wooden ring with
a differently-textured rectangle sitting inside it, which is a courtyard,
not a house. A roof covers the whole footprint, walls included. Entering
still reveals the interior, because roof-hiding keys on
`RoomDetector.room_containing` (the room's own cells) rather than on "all
roof cells" — so the wall cap stays while the room opens up, which is
also what a cutaway of a real building looks like.

**2. A house needs a facade, or the player cannot find the door.** A roof
covering *everything* is geometrically honest but hides the one thing the
player needs to see. Real top-down games solve this the same way: the roof
stops one row short of the front, leaving a visible facade band carrying
the door and windows. So the door is placed on the FRONT (south) wall
rather than wherever a wall cell first qualifies, and the southernmost
wall cell of every column stays unroofed. A villager's house therefore
reads as roof-above-facade, with its entrance legible from outside — and
the door is somewhere a person would actually put one.

**3. A pitched roof reads as a roof; a flat one reads as a floor.** A
single shingle texture tiled across a rectangle is, visually, a brick
patio. What makes a roof read as a roof from above is the PITCH: a ridge
line along the top, two slopes falling away from it, one catching the
light and one in shade. That is per-cell context, not per-tile art, so it
is derived the same way `TerrainRenderer` already derives biome blends and
corners from neighbours (`dominant_blend_for`/`corner_direction_for`) —
a pure classifier over the cell set, feeding an atlas family:

- The ridge runs along the footprint's LONGER axis, because real rafters
  span the shorter direction.
- Each cell's shade comes from its distance to the ridge, brightest at the
  ridge and falling toward the eaves, with the light-facing slope (up-left,
  this project's established light direction) a full step brighter than the
  shaded one.
- Quantized into a small fixed number of bands rather than a continuous
  ramp, so it stays a bounded atlas family like every other one here.

**4. Per-tile rim shading is what made it read as loose panels.** Every
piece tile drew its own bright top-left and dark bottom-right rim. Twenty
wall tiles in a ring therefore drew twenty individually-outlined boxes —
an internal grid over the whole building, which is precisely the "randomly
placed panels" the report describes. A rim belongs on the STRUCTURE's
outer boundary, not on each cell: a piece tile is rimmed only on the sides
where it actually borders something that is not part of the same building.
That is again neighbour context, expressed as a 4-bit edge mask over the
cell's cardinal sides, so the atlas family is (material × band × edge
mask) rather than one tile per piece id.

**5. A second storey reads as a second facade band — never as a second
floor painted over the first.** Reported directly once two-story houses
went live: "there are still no 2 story houses... also now most houses
don't even have a door." An upper storey shares the ground floor's exact
footprint (see [housing.md](housing.md)'s "Two-story houses"), and it was
first drawn in place, on a layer above everything, with the same wall and
window art — which from a bird's-eye view is *indistinguishable* from a
one-story house, except that the upper storey's own front wall/window
sits squarely over the ground floor's door. Real top-down games depict
height the same way they depict the facade in point 2: a taller building
shows MORE facade band, stacked. So from outside, the only part of an
upper storey ever drawn is its own facade cells (the same southernmost-
per-column rule), each painted one row UP — over the roof's own front row
— so a two-story house reads as roof-above-facade-above-facade: door and
ground windows on the bottom band, the upper storey's windows on the band
above, roof above that. Nothing else of the upper storey is drawn from
outside; its interior, side and back cells are under the roof exactly as
the ground floor's own are. That band therefore sits on a layer ABOVE the
roof (`EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX`), and its windows are
lit one row up too. Entering the house on the ground floor removes the
upper band along with the roof (downstairs, the ground room is the view);
going upstairs draws the whole upper storey in place, with the player
lifted above it (`UPPER_FLOOR_OCCUPANT_Z_INDEX`) so the floor they stand on
cannot paint over them, and downstairs villagers correctly hidden beneath
it.

**6. The facade is a *face*, not an interior wall seen from outside.**
Reported once the catalog, roofs and second storeys were all in: the
buildings still "look poor and basic; not like sophisticated architecture".
Points 2 and 5 decide *where* the facade band is, but the band was painted
with the same log/brick tile as an interior wall — every house was a roof
over a strip of whatever it was made of. A real street face is its own
art: half-timbered plaster between dark timbers on a wood or timber house
(the frame in the material's own tone, so sawn timber still tells against
rough wood), dressed ashlar over a darker plinth on a stone one; the roof's
overhang casting a shadow down the top rows of every facade cell (the one
cue that turns a flat band into a wall standing under a roof); a sill and
shutters framing a window; a lintel over the door and a worn step at its
foot. The upper storey's band (point 5) is its own variant — a string
course or sill beam where the ground storey has its plinth — so two
stacked bands never read as one repeated row. Like the roof pitch (point
3) this is resolved at paint time from context, not a new piece id: a
wall, window or door cell with no building piece directly south of it is
a facade cell and takes the facade variant
(`ProceduralBuildingPieceSprite.generate_facade_variant_image`, a material
× category × storey atlas family baked after the trail tile); every other
wall cell keeps the plain tile the player sees from inside.

None of this changes the piece vocabulary or what gets persisted — a roof
is still one `wood_roof`/`stone_roof` chunk modification per cell (see
Persistence below), and an upper-floor piece is still stored at its own
cell. All of the above is resolved at PAINT time from the neighbouring
cells and the player's own position, exactly like terrain blending, so no
new piece ids and no save-format change are involved.

**7. Real illustrated art, per piece id, replacing the procedural pattern
where a real sheet exists.** The same "hand-drawn sheet wins, procedural is
the fallback" seam `IllustratedTerrainSprite` already established for
biome ground tiles: `IllustratedBuildingPieceSprite.has_piece_art(piece_id)`
gates whether `TerrainRenderer._piece_image` draws from a real
user-supplied illustration (`assets/sprites/buildings/wood_wall.png`/
`stone_wall.png`, a 6-column sheet — door, window, wall, a spare wall
variant, two spare narrow corner-post variants, only the first three wired
so far; `wood_floor.png`, a single image) or falls through to
`ProceduralBuildingPieceSprite.generate_image` exactly as before. A piece
with no real sheet yet (stone floor, the timber tier, roofs) is untouched.
This is additive art only — it changes no piece id, no placement rule, and
no save data, the same guarantee point 6's facade family and the roof
pitch family (point 3) already keep.

### Persistence

Pieces persist through the existing per-chunk modification system (see
[world.md](world.md) and `EarthChunkManager`'s `MODIFICATIONS_DIR`), which
already stores a tile id per cell and already survives chunk unload and
restart. Structures need no new save path — a placed wall is a chunk
modification like any other.

### Status / mechanisms

- ✅ `building_piece.gd` — the piece catalog (category, material, cost,
  passability, durability), tested.
- ✅ `building_placement.gd` — placement/removal validity over a grid, with
  a refusal *reason* so a build cursor can explain itself, tested.
- ✅ `room_detector.gd` — enclosure flood fill; rooms, and whether a given
  cell is indoors, tested. Doors block the fill while staying walkable,
  which is what makes a house enterable without ceasing to be enclosed.
- ✅ `house_blueprint.gd` — a CATALOG of named blueprints (see "A blueprint
  catalog, not one box" above), each a seed away from a real piece list,
  shared by the player's prefabs and the village generator, tested. Every
  single catalog entry is verified to enclose exactly one real room, so
  village houses cannot silently degrade back into scenery. Which blueprint
  a villager builds is chosen from their own occupation/personality
  (`choose_blueprint_id`), not picked uniformly at random.
- ✅ Piece rendering, wall/window collision, door passability, roof
  hide-on-enter. `ProceduralBuildingPieceSprite` gives all 10 piece ids
  (floor/wall/door/window/roof × wood/stone) their own atlas tile, alongside
  campfire/furnace in the same shared atlas `TerrainRenderer` already
  builds. `EarthChunkManager.build_at_global`/`destroy_at_global` spawn/free
  a StaticBody2D+CollisionShape2D for any wall/window piece (the same
  mechanism trunks/boulders/ore already use to block movement -- this
  project has no generic tile-solidity check), and restore it for
  disk-persisted pieces on chunk reload. A roof piece paints onto its own
  `TileMapLayer` (`EarthChunkManager.set_roof_layer`, `Chunk.
  roof_modifications` -- separate from `modifications` since a roof shares
  its cell with the floor beneath it) and is erased over exactly the room
  (`RoomDetector.room_containing`) the player is currently standing inside,
  restored the moment they leave it; recomputed every `update()` call
  rather than throttled by "has the player's tile changed", since a
  structure can be built/destroyed while the player stands still (a real
  bug this caught in testing -- a throttle keyed only on player movement
  never re-checked room membership after a hut was stamped around a
  stationary player). `EarthChunkManager.stamp_structure_at_global` writes
  a whole structure's pieces in one call + one repaint (used by the village
  generator, see below) rather than one `build_at_global` call per cell,
  which would repaint the owning chunk once per cell.
- ✅ Real terrain buildability (docs/concept/housing.md's own "Real
  terrain buildability" entry has the full detail) -- reported directly:
  *"houses / buildings cannot be built on river / water; also not in the
  forest... the NPCs / Player must first fell all trees to make space for
  the building."* `EarthChunkManager.is_buildable_terrain_at` (not ocean
  or forest biome, no river, no lake, no standing tree) is the one real
  check `can_build_house_from_blueprint` (the player's own instant
  self-build), `BuilderMarker._buildable_ground` (the hired path -- a
  permissive `return true` before this), and `VillageRenderer._fit_house`
  (the village generator -- ocean-only before this, missing rivers/lakes)
  all now share, refusing/re-siting a placement UPFRONT
  rather than ever reaching `stamp_structure_at_global` with a tree still
  standing on the footprint. This is what makes the vegetation-clearing
  entry immediately below now a defensive fallback rather than the
  primary mechanism for the player-build and village-generation seams
  specifically (it still fires for a hypothetical future caller of
  `stamp_structure_at_global` that skips the new gate, and the hired-
  builder seam never called it either way, since `BuilderMarker` places
  pieces one at a time via `build_at_global`, not the bulk path) -- named
  here so this entry and the one below don't quietly drift apart.
- ✅ A piece occupies its tile against vegetation (see "Placement rules" and
  "One system, two builders"), tested at all three seams.
  `stamp_structure_at_global` collects the cells it wrote a real
  `BuildingPiece` to and hands them to `_clear_vegetation_on_cells`, which
  `queue_free()`s any tree standing on them, drops it from `_loaded_trees`
  in the same breath (that registry is iterated elsewhere without an
  `is_instance_valid` guard) and prunes the matching `Chunk.planted_trees`
  records so a persisted sapling under the footprint does not come back from
  disk — closing direction 1, the house stamped over a standing trunk.
  `TreeRenderer.spawn_trees` skips a cell whose `chunk.modifications` holds
  a real piece — closing direction 2, the deterministic forest respawning
  into a persisted house on revisit. `_can_root_at` refuses such a cell —
  closing direction 3, a spread or bird-dropped seed sprouting on a floor.
  `TreeRooting.can_root_in` still answers only the BIOME half of "can a tree
  stand here"; occupancy is a separate, second refusal.
- ✅ Livable village houses — one pass over three reports at once ("still
  look poor and basic... still not furnished... some are built so that you
  can't enter", with a screenshot of a stone house with a pond *inside* it;
  and "they shouldn't be able to build anything on water tiles and trees /
  grass must be cut before and can't grow back inside a house"):
  - *Furniture and stairs were there but invisible.* Every furniture id and
    `wood_stairs` fell through `ProceduralBuildingPieceSprite.generate_
    image`'s `match` to the plain floor tile, so a fully furnished room
    drew as bare boards. They have real art now, pinned by the file's own
    every-piece-visually-distinct test (which was already red on `main`
    for exactly this reason, and for `stone_dam` == `boulder`).
  - *One water rule* (see "Placement rules"): `EarthChunkManager.
    is_water_at_global` is the single predicate behind buildability AND the
    painted river/lake overlay, so a wet cell can no longer be buildable —
    before, buildability asked `is_river_at_global`/`is_lake_at_global`
    while the painter drew water from a wider hydrology probe (sea pockets,
    small still-water pockets, the river bank apron). A persisted house
    piece found standing in water on chunk load is washed away and the
    chunk re-saved (`_reclaim_pieces_standing_in_water`), so worlds saved
    before this heal on the next visit; dams and boulders are exempt since
    they belong in water.
  - *Ground cover is cleared and kept out* (see "Placement rules"):
    `TallGrass`/`FlowerPatch`/`DesertScrub`/`TundraLichen.block_cells` on
    every cell a real piece stands on — wired at chunk load (before the
    first sprite sync), at stamp and at player build, released on destroy
    — and trees keep the one-cell apron via `BuildingPiece.touches_piece`
    at all three tree seams (`spawn_trees`, `step_tree_spread`, the
    stamp's own clearing).
  - *Siting* (see "One system, two builders"): `_fit_house` /
    `_find_clear_origin` — footprint + doorstep inside the chunk, buildable
    and unoccupied, searched nearest-first across the whole chunk (was a
    6-tile radius, then 12), smaller fallback shapes before a skip. Measured by re-running the real `spawn_village` on ten
    real settlements around 48.6°N 12.7°E (50 houses): 46 stamped, none
    truncated, overlapping, in water, unfurnished or with a lost/blocked
    door; 18 of the 46 are fallback shapes; **4 houses are still skipped**,
    all in two chunks that are ~85% lake with 126 and 89 buildable cells
    respectively (one of them a scatter inside forest), so their villagers
    stand without a house — the honest remaining gap. The real fix there is
    upstream: `SettlementGenerator.has_settlement_at` gates on the chunk's
    DOMINANT biome only, which still says "grassland" for a chunk that is
    mostly a lake; founding a settlement only where enough buildable ground
    exists is a follow-up (it would move existing villages in saved
    worlds, so it is not done as a side effect here).
  - *The facade family* (see "How a house reads from above", point 6).
  [housing.md](housing.md)'s Status carries the household side of the same
  pass.
- ✅ Real illustrated wall/door/window/floor art (see "How a house reads
  from above", point 7) — `IllustratedBuildingPieceSprite` replaces the
  procedural pattern for wood/stone wall, door, window and wood floor with
  a real user-supplied illustration; every other piece (stone floor, the
  timber tier, roofs) is unaffected. `ATLAS_VERSION` bumped to
  `art_resolution_v26_illustrated_building_pieces`.
- ✅ The same rule for boulders and ore, closed on **both** sides.
  `StoneRenderer.spawn_stones` had the identical bug with the identical
  shape — it iterated its cells over `chunk.biome` and never consulted
  `chunk.modifications`, and `_load_chunk` runs it *before* the village is
  stamped — so a boulder regrew inside a persisted house on every revisit,
  including a player-built one. It now skips a cell a real `BuildingPiece`
  holds, via a shared `_piece_occupies` helper, closing direction 2 for
  stone exactly as `spawn_trees` closes it for the forest. The same guard is
  applied to `spawn_mountain_veins`, whose placement rule is different
  (slope-gated, see `MountainOrePlacement`) but which is called from the
  same `_load_chunk` step into the same `_loaded_stones` list, so a
  player-built mountain shelter no longer sprouts ore through its floor.
  The narrowness is pinned by its own test, the same way the forest's is:
  plain earth under a boulder is a modification too and must not clear it.
  Direction 1 — a house stamped over an ALREADY-SPAWNED boulder in the
  same session — is closed in `_clear_vegetation_on_cells`, which now walks
  `_loaded_stones[chunk_coord]` alongside `_loaded_trees` and
  `queue_free()`s (and drops from the registry) every stone the footprint
  covers, mountain ore veins included since they land in the same list.
  There is no persisted-record half to prune: stone has no
  `planted_trees` equivalent, it regenerates deterministically, and the
  respawn guard above catches it on the next load. Direction 3 does not
  apply — nothing seeds a boulder. Pinned by
  `test_building_piece_occupancy_clears_stones_on_a_stamped_footprint` and
  its narrowness twin `..._leaves_a_stone_beside_the_footprint_standing`.
- ✅ Village houses rebuilt from blueprints, replacing the decorative
  `ProceduralHouseSprite`. `VillageRenderer._stamp_house` picks a real named
  `HouseBlueprint` shape via `choose_blueprint_id` (the villager's own
  occupation/personality, not a fixed 5x4 box any more -- see "A blueprint
  catalog, not one box" above), builds it (seeded wood/stone material)
  centred on each villager's ring-layout anchor, and stamps it via
  `stamp_structure_at_global`; a house is a chunk modification now, not a
  spawned node. A villager's `home_position` resolves to the house's own
  DOOR cell (found by scanning the stamped pieces for `CATEGORY_DOOR`), not
  the raw anchor point, so a villager standing "at home" is standing
  somewhere it could actually have walked to rather than the middle of a
  wall or floor cell. `_door_facing_direction` derives which way a door
  opens from its own actual floor neighbour rather than assuming a plain
  box's 4 sides, so an L-shaped blueprint's door (which can land on the
  notch's own exposed edge, not one of the bounding rectangle's 4 sides)
  still points a merchant's personal trading stand at open ground instead
  of a wall. Verified end-to-end against a real loaded chunk (real walls,
  exactly one door, real floor, a roof all present), not just the
  unit-level piece/placement/room logic. `VillageRenderer._fit_house` sites
  a house on clear, dry, in-chunk ground before stamping (see "One system,
  two builders" above), and every merchant villager gets a second,
  personal trading stand next to their own door (the same "stall" sprite as
  the shared village-square one), not just the one shared landmark.
- ✅ Per-occupation workspot props close the gap the merchant-stand pass left
  open (reported: "no per-occupation building beyond the shared landmarks
  and a merchant's own stand"). `NpcIdentity.WORK_LOCATION_BY_OCCUPATION` is
  the single shared mapping both `NpcPlanner.FakeNpcPlanner` (which
  `location_tag` a villager's schedule sends them to by day) and
  `VillageRenderer` (which prop, if any, actually stands there) read from,
  so the two can't drift the way two hand-maintained copies eventually
  would. `ProceduralLandmarkSprite` gained a field (farmer), forge
  (blacksmith), dock (fisher) and garden (herbalist) prop alongside its
  existing well/stall/gate; merchant and guard already had a real prop at
  their work tag (a personal stand, the shared gate) so they're
  intentionally skipped. `VillageRenderer.spawn_village` stamps one such
  prop per qualifying villager at that villager's own `workspot_position`
  (not a shared village-square point), so two herbalists in one settlement
  each get their own garden rather than sharing one.
- ⬜ Player-facing build cursor/piece selection UI (placing pieces by hand is
  currently only reachable via `stamp_structure_at_global`/`build_at_global`
  directly, not through the hotbar/inventory the way campfire/furnace are).
- ⬜ Shelter effects (warmth, safety) for being in an enclosed room, tying
  building into [survival.md](survival.md).
