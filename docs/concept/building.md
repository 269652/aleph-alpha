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

**A house stands IN its plot, not across it** (2026-09-19). Reported live
with a screenshot of three cottages in a row: *"make the cottages a bit
smaller and add a padding so they have a gap between them and the top
doesn't get clipped"*.

The slicer was the obvious suspect and was not the problem, which is worth
recording because it is where anyone would look first. Measured on the real
sheets (`tools/probe_cottage_row.gd`), every finished cottage frame has
**zero** transparent pixels on all four edges — the cell bands are cut
tight to the art by construction (`VariantSheetGrid`) — and that tight crop
was then scaled to **exactly** the plot width. So two houses on
neighbouring plots touched at the pixel with no street between them, and a
roof that reaches well above its own plot ran straight into whatever stood
north of it.

`BuildingCatalog.PLOT_MARGIN_SHARE` leaves air on each side, and
`drawn_plot_width_tiles` is the ONE place that answer lives, so the
illustrated-sheet path and the procedural placeholder cannot disagree about
how much of a plot a building covers — otherwise dropping a sheet in would
visibly move the house, and a street of half-arted buildings would carry
two different rhythms. Measured on a real cottage row: **52px drawn on a
64px plot, 12px of air.**

A share rather than a fixed number of tiles, so the air scales with the
building: a manor stands in proportionally as much ground as a cottage
does. The trade-off is deliberate — a bigger building gets a wider gap,
which reads as a bigger house standing in more of its own land rather than
as an inconsistent street. The share is pinned from both sides by what it
produces, never as a number: two houses on adjacent plots must stand more
than a quarter of a tile apart (under that it is a seam, not a gap, at the
size a tile is really drawn), and a building must still cover more than
three quarters of its own plot (under that it stops reading as a building
on that ground and starts reading as a model of one).

> **The collision body is unchanged and still covers the whole footprint.**
> Only the PICTURE moved. The plot is reserved ground either way — the
> layout routes roads around the whole of it — so the air between two
> houses is eaves and garden rather than a path between them. It does mean
> a few world pixels of collision with nothing drawn on them; at
> `PLOT_MARGIN_SHARE` on a two-tile plot that is under a fifth of a tile
> per side, and shrinking the body instead would open a walkable slot
> between every pair of houses, which is a gameplay change nobody asked
> for. Named here rather than left to be rediscovered.
>
> Single-tile **placeables** (`farm`, `sagewerk`, `storage`) are untouched:
> they draw through `IllustratedStructureSprite.drawn_width_tiles`, which
> answers a different question for a different thing — how wide a placeable
> is drawn, from its catalog twin — and they were sized by their own
> separate pass. A `farmhouse` the whole building and a `farm` the placeable
> therefore now sit slightly differently on their ground; that duality
> predates this and is not what was reported.
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
doorstep must be ground that can carry a building
(`EarthChunkManager.is_buildable_ground_at`: not water, not the forest
biome — a standing tree does not count, the village fells it when it
places the building or paves the square; found live (2026-09-16): one
tree on the 8×6 square vetoed the whole plaza, and the town hall with
it, in most real settlement chunks) and unmodified; a villager whose
plot fits nowhere stays homeless, as today, rather than being squeezed
onto water or forest. The player's own rule stays
`is_buildable_terrain_at` — fell the trees first. `SettlementGenerator` keeps its
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

**A hall is a workplace, not a home (2026-09-19).** `interior_family`
already sorts buildings into room shapes — `cottage`/`house`/`manor` for
the three house tiers, and `hall` for the City Hall, the warehouse, the
trade hall and the mage guild. Only the three house families had plans;
`hall` fell through `InteriorTemplates._variants_for`'s fail-open default
and was silently furnished as a **cottage**, bed and all. Nobody noticed
while nothing happened indoors — and then [mage_guild.md](mage_guild.md)
put three masters in one, standing around somebody's bedroom.

A hall has its own plans now, and they are shaped by what a hall *is*:

- **No bed.** A hall is where a trade meets, not where anyone sleeps. The
  slot vocabulary is the same one houses use (`T` tables, `C` chairs, `S`
  shelves, `K` hearth, `P` pictures, `R` rugs, `W` the occupation's own
  piece, `L` candles), minus `B` — and that absence is test-pinned rather
  than merely observed, because a bed in a City Hall is exactly the kind of
  thing a later plan would reintroduce by copy-paste.
- **A big room with business off it.** Each plan is one open floor — long
  enough to hold a table people gather at and *room for several people to
  stand*, which a cottage does not have — plus one or more side chambers
  through wall gaps, so it still satisfies the same "more than one room"
  rule houses and manors do.
- **The occupation still decides the furnishing.** A guild's `W` and `S`
  slots resolve through `HouseDecor.piece_for_slot` exactly as a house's
  do, so a mage guild gets a workbench and bookshelves where a warehouse
  gets crates and cupboards — one shape, many trades, the same mechanism
  that already makes a smith's cottage differ from a farmer's.

**`workshop` and `farmstead` still fall back to cottage plans.** That is
the same gap this section just closed for `hall`, left open honestly for
the buildings that need it (the sawmill, the blacksmith, the brewery, the
farmhouse) and pinned by a test that names exactly which families are
still borrowing, so a *new* family cannot join them silently.

**A room can hold a group, not only a resident.** `HouseInteriorView.
place_occupants` stands several people up at once — spread evenly across
`standing_cells()` (open floor with nothing on it, never the doorway,
which has to stay clear or there is no way back out) rather than queued by
the door. The first of them takes the template's own resident cell and
becomes that room's `_resident`, so everything above — Talk, the indoor
prompt, `resident_identity`/`resident_position` — keeps reading one field
and needs no knowledge that groups exist. A house still holds exactly one
villager; the first room in the game that holds a group is the **mage
guild**, whose masters are in residence rather than "at home" and so are
not gated on `is_at_home()` at all (see
[mage_guild.md](mage_guild.md)).

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

### The ground a building stands on, and the kerb round its plot

Reported live with a screenshot (2026-09-20): *"the background of the
houses 2x2 should be variable; if the city hall is placed on the plaza it
should have cobblestone background so it looks seamless... also there
should be some kind of border so the hitbox is visible."*

The first half is what "a building stands on the ground; it does not
replace it" (below, 2026-09-19) already answers: a footprint is an overlay,
so a house on grass shows the grass it was raised on and the ground under a
building is as variable as the ground is.

**The square is the one thing an overlay cannot answer.** Placement LIFTS
the paving it covers -- `_place_building_over_roads` erases the Road
modification from every footprint cell before writing the building's own
ids -- so a hall raised on the village square falls back to the *biome*
under it and shows the grassland the square was paved over. That is not a
seam, it is a hole punched in the square, and it is exactly what the
screenshot shows. Measured before the fix with
`tools/probe_building_ground.gd` across three real settlements near lat
48.6 lon 12.7: 28 buildings, and all three town halls painting ground that
was not the square they stand on.

**So a building reads its own kerb -- and which building it is.** The kerb
is the ring of cells immediately around the footprint -- 18 cells round a
4x3 hall, 12 round a 2x2 cottage. A building whose kerb carries more than
`TerrainRenderer.PAVED_KERB_SHARE` of laid Road **and** which a village
raises on its own paving to begin with
(`BuildingCatalog.PAVED_PLOT_BUILDING_IDS`) paints that Road under itself,
and the hall is cobbled right up to its own walls; anything else stays the
plain overlay above, with the ground it was raised on showing through.

The share is half, and the measurements are what put it there. On those
same three villages every town hall's kerb is 12 of 18 paved (67%), the
same 12 of 18 in all three because the plaza and the civic plot are both
pure functions of the chunk and its seed. An ordinary house, farmhouse or
sawmill plot ran 7-43% -- its doorstep and a spur, no more. Trails do not
count, only the laid Road tier ([infrastructure.md](infrastructure.md)): a
building standing in ground worn by walking is standing in worn ground.

**The share alone stopped being enough, and the reason is geometry, not a
badly chosen number.** Reported with three farmhouses in shot, each
standing on its own grey pad: *"make the farm houses ground grass instead
of cobblestone... only buildings placed on pavement like the city hall
should get the pavement bg"*. Re-measured on the same three settlements
once the square stopped being abandoned at founding
([village_market_square.md](village_market_square.md)):

| plot | kerb paved | on the square |
| --- | --- | --- |
| `farmhouse` (13, 19) | 14/14 (100%) | no |
| `farmhouse` (20, 19) | 11/14 (79%) | no |
| `house_small` (17, 19) | 10/12 (83%) | no |
| `city_hall` (14, 13) | 12/18 (67%) | **yes** |

Ten buildings across those three villages painted cobbles while standing on
open ground, and the worst offenders beat the hall. A plot wedged between
the square's southern rows and the second street is ringed by paving on
every side while standing on none of it, so **no threshold can separate the
two** -- the hall's own 67% is below the farmhouse's 100%.

What separates them is not local geometry at all: it is which buildings a
village ever raises on its own paving, and exactly one does. The civic plot
IS the paved square -- `EarthChunkManager._civic_plot_origin_for` refuses a
plot whose every footprint cell is not already a road tile -- while every
other placement path refuses a modified footprint outright
(`can_build_house_from_blueprint` with `road_allowed` false,
`_is_clear_settlement_site`, `VillageLayout._street_plot_fits`). So the
rule asks both questions, and both halves earn their keep: a hall raised
somewhere with no paving round it keeps the ground it was raised on like
anything else, and a farmhouse ringed by the whole village keeps its grass.

**Nothing about this is persisted.** The ground is re-derived from the
chunk on every paint, so a village saved before this existed heals on its
next load -- the same property that lets an older village re-derive and
pave its square (`VillageRenderer._lay_plaza_if_missing`), and the same
property that un-paves every farmhouse pad an older save already carries.

`TerrainRenderer` preloads `BuildingCatalog` for this, which the literal
`BUILDING_OVERLAY_TILE_IDS` list deliberately avoids -- a named divergence,
not an oversight. The overlay question genuinely needs nothing but an id;
a kerb is read around a whole PLOT, and a footprint is the one thing only
the catalog knows. The list stays literal.

**Confirmed on a real render**, not only by test, the way every other
"what does this look like" question in this repo is
(`tools/probe_village_render.gd`, under `xvfb` + Mesa software GL): the
hall's plot is cobbled continuously into the plaza around it with no seam
and no square, and a cottage's plot shows the grass it stands in. The
probe takes a third frame since the farmhouse report -- that plot is the
hardest case there is, ringed by the square on one side and the second
street on the other -- and it shows the farmhouse and its yard standing on
grass with the village's paving running past it.

**The kerb is drawn, too.** `ProceduralFootprintKerbSprite` draws the
footprint's own outline at art resolution -- a dark edge with a lighter
inner line and a joint every few pixels, so it reads as laid kerb stones
rather than a debug rectangle -- and the building node carries it beneath
its art, built from the same `footprint_px` the `StaticBody2D`'s
`RectangleShape2D` is built from. What is drawn IS the hitbox, not a
picture of one that can drift from it, which is what
`test_the_kerb_a_building_draws_is_exactly_its_own_collision_rect` pins.
Its middle is fully transparent: the kerb marks the plot, it never paints
over the ground the rule above just chose. "Visible" is measured, not
eyeballed: `contrast_over` composites the kerb's own drawn pixels onto a
ground and returns how far they land from it, and every ground a kerb can
lie on must clear `MIN_GROUND_CONTRAST` -- 0.44 over the village's
cobbles, 0.28 over bare earth, 0.31 over the grass beside a plot, against
a floor of 0.12. A construction site draws no kerb -- it has no collision
body yet, and a border round a hitbox that does not exist would be a lie.

**Honest gaps.** The kerb is drawn on a paved plot too, where it is an
outline over the square rather than a boundary between two surfaces. That
is what "so the hitbox is visible" asked for, and it does mean a village
square carries outlines a photograph of one would not. And an earth cell
beside a PAVED plot still blends toward it as though it were open ground
(`_neighbor_biomes` reads overlays as unmodified): real, but it cannot
arise today, since a paved plot is by definition ringed by paving rather
than by earth.

### A building's own yard, drawn behind it

Asked for directly, with the art dropped in: *"I added
farmhouse_bg_overlay.png which should be rendered as background behind the
3x2 farmhouse it should use a random variation so that each farmhouses bg
looks different"*, and then, when it did not show: *"farm houses don't use
the 3x2 background image as background..."* and *"I also added bg overlays
for cottages ..."*.

The kerb above says where a plot *is*. This says what stands on it. A
farmhouse is a working yard as much as a building — a woodpile, a barrel, a
bench, a washing line, a beaten path through the grass — and none of that is
in the building's own sheet, which draws only the house.

- **A yard is one sheet of whole scenes, not props to place.** The delivered
  `farmhouse_bg_overlay.png` is a 3×3 grid of nine finished yards, each drawn
  at the plot's own 3:2 shape. Picking one picture is a far smaller mechanism
  than scattering props and deciding what may overlap what, and it is the
  same "one sheet, seeded cell" shape `BuildingLifecycleSheet` already uses
  to make a street of cottages a street of DIFFERENT cottages.
- **A sheet's cells must be the SHAPE of the plot they fill**, because a
  yard is scaled to the plot's whole rect. The farmhouse's 1536×1024 cuts
  into 512×341 cells at 1.50 for its 3×2 plot; `cottage_bg_overlay.png`'s
  1254×1254 cuts into 418×418 at 1.00 for the cottage's 2×2. That is a fact
  about the art, checkable the moment a sheet is declared, so it is checked
  there (`test_every_declared_yard_is_the_shape_of_the_plot_it_fills`)
  rather than left for a screenshot.
- **A cottage has a yard of its own.** It is the one building with both a
  variant sheet and a yard, so a street of cottages carries 25 house
  pictures × 9 gardens rather than nine repeats — and the two are salted
  apart, so a given cottage does not always arrive in the same garden.
- **Which yard is seeded from the building's own seed**, the same
  `record["seed"]` its house variant is already picked from, salted so the
  two axes cannot move together. Two farmhouses in one village differ; one
  farmhouse looks the same on every reload.
- **It is drawn BETWEEN the kerb and the house.** Children paint in tree
  order (see `_spawn_building_node`), so the yard lies on the ground the kerb
  marks out and the house stands on top of it.
- **It is scaled to the WHOLE plot, in both axes** — `footprint` tiles wide
  by `footprint` tiles deep, the same rect the kerb and the collision shape
  are built from (`IllustratedStructureSprite.plot_background_texture`).

  This was the bug behind *"farm houses don't use the 3x2 background image
  as background"*, and it is worth recording because the first version was
  specified wrong here rather than coded wrong: this doc said "same width as
  the house's own art, by the same `drawn_plot_width_tiles` rule", and a
  test pinned it in those words. Measured (`tools/probe_building_yard.gd`),
  that produced a yard of 79×53 art px against a house of 79×54 — the same
  width and a pixel shorter — so the yard sat entirely inside the house's
  own silhouette and 14.6% of its opaque pixels reached the screen.

  Two different widths were being conflated. A house is deliberately drawn
  narrower than its plot (`PLOT_MARGIN_SHARE`) so two neighbours have a
  street between them, which is a fact about **walls**; two neighbouring
  yards meeting is grass meeting grass. The ground takes the plot and the
  house stands inside it, which is also what makes a 3×2 picture the
  background of a 3×2 plot.

  Everything else in `IllustratedStructureSprite` is scaled by width alone,
  letting the art's own aspect set the height, because everything else is an
  object **standing on** the ground and a building taller than its footprint
  stays taller. A yard is not an object on the ground; it *is* the ground,
  so its rect is the plot's rect. Measured after: farmhouse 96×64 with 44.3%
  of the yard visible past its house, cottage 64×64 with 56.8%.
- **It is an overlay like everything else here.** A building with no yard
  sheet declared draws exactly what it drew before; the wiring is per
  building id (`BuildingCatalog.background_sheet_for`), so the farmhouse
  having one costs nothing anywhere else.
- **A building that borrows art borrows the yard with it.** `draws_as` (see
  the asset contract) hands over the whole picture, so the fisher's hut,
  drawn as a farmhouse, stands in a farmhouse's yard — asked for directly:
  *"the fisher hut should get a yard too"*. Its OWN seed still picks which
  of the nine, so the hut by the pond and the farmhouse up the street are
  different pictures. Borrowing art is the only way to inherit a yard; a
  building that declares neither still stands on bare plot
  (`test_a_building_that_borrows_nothing_inherits_no_yard`).
- **And the kerb survives underneath it**, though it is painted first:
  measured on the delivered sheet, 0 of 5118 pixels in the yard's outer
  three-pixel band are opaque, so the line round the plot is never covered.
  Pinned by `test_a_yard_never_paints_over_the_kerb_at_the_plots_own_edge`
  rather than left to luck — yard art bled to the edge would quietly erase
  the kerb of every building that stands in one.

**The background must be flooded off, not keyed off.** Both delivered
sheets have no alpha channel and paint their transparency as a grey-and-white
**checkerboard**, which is a new problem here: every other sheet in this
project keys flat magenta or near-black. A sheet that needs this is listed
by path (`_CHECKERBOARD_SHEETS`), because which key a file needs is a fact
about that file; measured, a farmhouse cell is 63% checker and a cottage
cell 39%, and both use the same two tones.

A flat colour key cannot separate it from the art, because the checker's
lighter square and the art's **white flower highlights are the same colour**
— the tones measure about 253 and 213, and a flower highlight sits at 235
and above. Measured: one source cell holds 46,354 near-white pixels, almost
all of them checker; 63 survive keying at drawn size, and those are the
flowers. A flat key takes every one of them.

What separates them is **connectivity**, not colour: the checker reaches the
cell's own edge, and a flower enclosed in foliage does not. So the key
floods inward from the edge over checker-coloured pixels — the same shape
`IllustratedCharacterSprite._remove_background_by_flood` already uses on
`head.png`, for the same reason. Unlike the head's flood it steps between
the checker's two tones freely (they differ by about 40/255, far more than
a per-step tolerance would allow) because what is followed here is a KNOWN
two-tone pattern rather than an unknown gradient into the art.

Two refinements, each measured on the real sheet rather than reasoned about:

- **The darker square is a safe seed anywhere in the cell**, not only at the
  edge, since nothing in the art is that particular grey. That is what
  clears checker showing through a gap in the foliage, which is enclosed by
  art and so can never be reached from the edge — 86 such pixels in one
  cell.
- **The flood then widens by a bounded two pixels** under a looser grey
  rule, which takes the anti-aliased edges where one square meets the next
  and where a square meets the art. The seed rule cannot be loosened that
  far without also swallowing a grey rock; bounding the widening to the one
  or two pixels anti-aliasing actually spans cannot reach a rock's interior
  however grey it is. Measured: 82 px of grey fringe survived before it.

### When the ground says no: water, a split spine, and a drowned square

`BiomeClassifier` knows nothing of hydrology, so a lake still reads as
"grassland" and `SettlementGenerator` will happily settle it. Three rules
keep a village honest about ground it cannot actually build on. All three
were measured against the real world near lat 48.6 lon 12.7
(`tools/probe_village_houses_live.gd`, `tools/probe_village_ghost.gd`) and
reported in play first.

**A village only settles where there is room for all of it.** When
`VillageLayout.layout` cannot house the whole roster, `VillageRenderer`
founds nothing there — no streets, no mill, no villagers, no settlement
record — rather than a village nobody can live in. Reported first as *"Some
villages have no houses"*, and tightened from "not one house" to "not every
house" when a riverside chunk ended up with a market square and a single
cottage: *"They should only settle where there's enough space and the
square wins; houses should just be moved further away connected by
streets"*.

That rule only makes sense because the layout really does look: **a street
that places nothing no longer ends the village.** It can come up empty
because the square took the whole spine, or because that row happens to be
water; neither means the village has nowhere to live, so the walk carries
on to the next street. It stays bounded by the chunk without a break —
a further street only opens while it is inside the edge margin, and only
when the gate lane reaching it is really clear.

**The square slides rather than drowns.** The plaza was pinned to the
chunk's exact middle, so a river through that middle meant no square — and
with no square there is no civic plot, and so no city hall, ever.
`VillageLayout.plaza_x0_for` slides it along the street, west and east
alternately, nearest first, to the first column where the whole square is
dry. Nowhere dry and it stays at the designed centre, where `layout` finds
it unclear and honestly lays none.

It briefly also demanded a run wide enough for the square *plus a house
beside it*, on the reasoning that a square swallowing its whole street
leaves the village nowhere to live. Measured on chunk (661,139) near lat
49.8 lon 10.6 — reported three times as "no plaza, no city hall" — that
trade is the wrong way round. The dry pocket there is about nine tiles, the
square fits on it, and the rule made the village take three houses and no
square instead. **A house does not have to stand on the spine**; a village
that fills its spine opens a further street and reaches it by the gate
lane. A square can only ever straddle a street. So the rule is gone, and
its consequence is handled where it belongs: a spine whose whole run is
taken by the square no longer ends the village — its houses go to the next
street. That exception is deliberately bounded to the spine and to a
village that has placed nothing at all, so a chunk is never walked to the
bottom placing nothing.

The predicate is deliberately a WATER test (`is_dry`), not the general
buildable/occupied pair. Every consumer of a village's square — the
founding layout, the reload's re-paving, the civic plot, the growth
ladder's next plot, the well/stall/gate props — has to derive the same
rectangle with nothing persisted, so the input must be the one thing that
never changes once the world is seeded: trees get felled and ground gets
built on, rivers do not move. `skeleton`, `layout`, `industry_plot`,
`next_street_plot` and `SettlementGenerator.generate_settlement` all take
it optionally; omitted, the square stands at its designed centre exactly
as before.

And it is the **generated** world's water, never
`is_water_at_global`: a fisher's dug pond
([village_ponds.md](village_ponds.md)) is real water that refuses a house,
but it lives in `chunk.modifications`, so a square sited by it *moves* when
somebody digs. Measured: one row of pond dug across a square slid it from
x0=12 to x0=4, stranding the paving already laid.
`EarthChunkManager.is_generated_water_at_global` is the rule every
square-siting caller asks — see
[village_market_square.md](village_market_square.md), "The square is sited
by water that never moves".

The square is also never **abandoned** over a few cells of it. Founding
used to demand all 48 clear, and a sawmill's road spur crossing three of
them cost one village its square, its civic plot and therefore its city
hall for good — the houses simply took the ground. Founding now keeps any
square that is `plaza_is_worth_laying`, claims the whole rect so nothing
creeps into it, and paves the cells it can really take.

**A drowned square costs a square, not the village.** The plaza is the
only thing further streets used to hang on: side streets ran down its two
edges, so a village whose centre was water broke out of the growth loop at
once and stopped at whatever its spine could take. A column of water
through a chunk does both things at the same time — it drowns the plaza
AND splits the spine — which is how a riverside village ended up standing
with three houses and five villagers (reported twice, with a screenshot).
A village without a square now opens further streets anyway, tied back by
a **gate lane**: one column at the spine run's own start, reserved before
the street it reaches is laid out (no plot can want it — every street's
plots begin `_GATE_CLEARANCE_TILES` east of the spine's start) and paved
only once that street is actually built on, exactly the rule the side
streets already followed.

**What counts on reload is a DWELLING, not a building.** A save written
before the founding gate existed can hold a village's mill and its paving
and not one home. Any building at all used to send the chunk down the
recovery branch, which matches villagers to houses that are not there and
spawns the whole roster regardless — five villagers with nowhere to live,
measured on two real chunks. `spawn_village` now counts dwellings
(`BuildingCatalog.capacity_of > 0`): with none, the site is re-laid from
scratch, so good ground gets its houses raised and bad ground founds
nothing. The double-placement this branch guards against cannot happen in
that state either — a village with no house cannot grow a second set of
them.

### Asset contract (what an artist/generator must deliver)

Everything below lights up by dropping the file in and bumping
`TerrainRenderer.ATLAS_VERSION` (tiles) or simply relaunching (sheets);
there is no registry to edit. Until a file exists, a procedural placeholder
draws so the system is playable and testable without art.

**Or a borrowed sheet, where a placeholder box is too little.** A catalog
entry may name another building's art with `draws_as`, which borrows the
whole picture -- the building's sheet AND the yard it stands in (see "A
building's own yard, drawn behind it"), since a borrowed house on bare
plot beside the real thing in its finished yard reads as forgotten rather
than as a stand-in. The borrowed sheet
becomes the LAST link of its own chain (`BuildingCatalog.draws_as_of`,
`finished_sheet_chain`): the building draws as its stand-in until its own
file lands, and the day it does, it wins with no code change at all —
removing the one line is then pure tidying. Asked for directly, for the
fisher's hut: *"use farmhouse sprite until illustration exists"*
([village_ponds.md](village_ponds.md), "The hut on the bank"). Read with
the SHEET's own grid, never the borrower's, since farmhouse.png has six
columns where every other contract sheet has eight. Pinned by
`test_a_borrowed_sheet_never_hides_the_buildings_own` and
`test_a_borrowed_sheet_is_read_with_its_own_grid`. A building whose
stand-in is a plain box still gets the procedural placeholder above; this
is for the case where "it should look like a farmhouse" is the real
answer.

**Building sheets** — `assets/sprites/buildings/<building_id>.png`
(`house_small`, `house_medium`, `house_large`, `city_hall` …), 1536×1024,
8 columns × 5 rows, black background, magenta cell dividers and a thin
near-white rule line on every cell boundary. Rows: 0
construction ×8 (scaffold → shell → roof, left to right), 1 active ×8 (lit
windows / chimney smoke loop), 2 idle ×8 (loop or repeats), 3 burning ×8,
4 ruined ×8.

> **…but not every sheet is eight columns.** Reported live with two
> buildings in shot: *"There are still two buildings with wrong crops …
> Please fix the slicer."* The mill and the store were the ones the grid and
> the inset below fixed; the **farmhouse** was a different fault in the same
> place. Measured off each sheet's own magenta dividers
> (`tools/probe_building_lifecycle_sheet.gd`): `sawmill.png` 8×~143px,
> `warehouse.png` 8×~146px, `city_hall.png` 8×~189px, `blacksmith.png`
> 8×~189px, `brewery.png` 8×~190px — and **`farmhouse.png` SIX** ×~182px.
> Its art is on a 256px pitch, so reading it at 192 cut 64px off every
> farmhouse: rendered (`tools/probe_building_idle_crops.gd`), the tree and
> the left-hand third of the farmyard, with the house sitting off-centre in
> its own frame. `BuildingCatalog.sheet_columns_of` carries the exception,
> `construction_stage_for` takes the building id so a six-column sheet has
> six stages rather than eight, and
> `test_every_contract_sheet_is_read_with_the_column_count_its_art_is_drawn_on`
> reads every sheet's real columns rather than trusting the table.

> **Columns are on a pitch. Rows are not.** (Corrected 2026-09-17, twice —
> the second correction is the one that measured instead of assuming.)
> Reported live: *"the warehouse has the rows cropped wrongly."*
>
> **Columns.** 1536/8 is exactly 192, and profiling confirms the art in
> every column really does start ~12px inside one of 0, 192, 384 … 1344, on
> all four 8-column sheets. So a column is cut by even division
> (`IllustratedStructureSprite.even_cell_rect`), minus
> `CELL_INSET` = 3px for the rule line drawn on the boundary —
> that line is neither magenta nor near-black, so neither chroma key
> removes it and a cell cut exactly on the grid keeps it as a hard white
> hairline up its own edge (196 such pixels on sagewerk's idle frame
> before the inset, 0 after).
>
> **Rows.** No pitch lands on them. The drawn boundaries are at 188, 376,
> 566, 786 on `warehouse`; 190, 387, 578, 789 on `sawmill`; elsewhere again
> on `city_hall` and `blacksmith`. Two guesses were shipped before this was
> measured: an even fifth of the canvas (204.8) clipped 9px off `sawmill`'s
> roof, and the column pitch (192) clipped 13px off `city_hall`'s footings,
> 26px off `blacksmith`'s last row, and cut `wooden_fence`'s real 256px
> rows at 384. So rows are **read off the sheet** by
> `VariantSheetGrid.content_bands`, which finds the bands holding real
> drawing — not the dark cell background, not the magenta margin, not the
> rule line — and falls back to even division on any sheet it cannot
> resolve. Its 2% art-share threshold is pinned against all five real
> sheets: at 2% every one resolves to its 5 drawn rows, at 1% `city_hall`
> splits into 7, at 5% `sawmill` splits into 6.
>
> What the inset does NOT clear: where a magenta divider is antialiased
> against a cell's black background it leaves a tail of near-black
> magenta-hued pixels a few px inside the boundary (~100 of them on
> `city_hall`'s left edge, ~3% luminance). Keying those out is not an
> option — 30,000+ pixels of that same hue and brightness sit well away
> from any boundary on every sheet, as real shadow and roof art — so the
> dark half of the fringe stays.
>
> The consequence worth stating plainly: **a frame from one of these sheets
> is not square and the sheets do not agree on a row height.** `sagewerk`'s
> idle frame is 186×183, `storage`'s 186×169, `city_hall`'s 186×186. That
> disagreement is the regression guard — any pitch would give all three the
> same height.

Each cell is scaled on screen so the cell's WIDTH equals the
footprint's width (`footprint_frame_texture`): a `w`-wide house draws
`ART_TILE_SIZE`·w art px wide, drawn at `ArtResolution.SPRITE_SCALE` so it
occupies exactly 16·w WORLD units — the same pixels-per-world-unit the
ground it stands on already paints at (see
[art_resolution.md](art_resolution.md); buildings drew at 16·w art px
until 2026-09-16, carrying half the resolution of their own terrain). The bottom `d` tiles of that height are the
ground footprint — draw the roof there, seen from the top-down camera —
and everything above overhangs the row north of the house. The door must
sit on the bottom edge in column `w/2` (integer division, i.e. right of
centre for a 2-wide house), the whole facade south-facing. Until the
file exists, `ProceduralBuildingPlaceholderSprite` draws a roof-over-walls
box of the right footprint. (Construction progress will pick row 0's
column from `progress` — `clampi(floori(progress × 8), 0, 7)` — once the
village raises buildings over time; today only row 2 is shown.)

**Building variant sheets** — `assets/sprites/buildings/<sheet name>.png`, a plain **5 columns x 5 rows** grid of 25 complete
buildings, one per cell, **black background, NO magenta dividers**, each
house drawn in the same 3/4 top-down view and the same scale as its
neighbours, its ground footprint at the bottom of its own cell exactly as
the lifecycle sheets' cells are. Any pixel size works — the slicer derives
the cell rect from the image's own dimensions, so a 1400x1100 sheet and a
2800x2200 one both cut cleanly.

This is a SECOND, simpler contract beside the 8x5 lifecycle sheet above,
for buildings there are many real drawn versions of. A finished building
picks its cell from its own seed (`BuildingCatalog.variant_cell_for`), so
a street of cottages reads as a street of DIFFERENT cottages rather than
one house repeated down the road. It has no lifecycle rows at all and
never claims to: a RISING building still draws from the lifecycle sheet's
construction row, and only the FINISHED building prefers a variant
(`BuildingCatalog.finished_sheet_for`). Purely additive — a building with
no variant sheet, or one whose file is not on disk yet, falls through the
same lifecycle-sheet-then-procedural-placeholder chain as before.

Only the background may be black: the loader keys out pixels below 0.05 in
every channel (`IllustratedStructureSprite._BLACK_MAX`), so a near-black
roof or outline inside the art survives, but a genuinely black one would
be punched through.

Declared today for all three village houses, sharing the one first-tier
cottage sheet. That is deliberate rather than lazy: no house had a
lifecycle sheet of its own at all, so every village house drew as a
procedural box — declaring the cottage art for only the smallest tier
would leave a street half beautiful cottages and half boxes, which reads
worse than either extreme. The scaler sizes each cell to its own footprint
without distorting it, so a medium or large house is simply a bigger
cottage, and a different seed picks a different one of the 25 anyway. When
grander art for those tiers lands they get their own entries and nothing
else changes. Nothing that is not a home has one — a hall, a mill or a
brewery drawn as a cottage would be drawing the wrong building, and each
already has its own lifecycle sheet.

**Building lifecycle variation sheets** — `assets/sprites/buildings/<name>.png`,
**8 columns x 10 rows**, cells separated by real **magenta divider lines**,
with a row of column labels across the top, a column of row labels down the
left and a blank margin on the right. Any pixel size works: the cells are
found between the divider lines, and the art window is the consecutive run
of bands whose sizes are most alike, so the label bands and the margin are
skipped without anyone writing down where they sit
(`VariantSheetGrid.art_bands`, measured by
`tools/probe_building_lifecycle_sheet.gd`). The sheets print their own row
meanings, and those are the contract:

| row | meaning | row | meaning |
|----:|---------|----:|---------|
| 0 | Build (Foundation) | 5 | Idle 3 (Variants) |
| 1 | Build (Frames) | 6 | Damaged (1) |
| 2 | Build (Construction) | 7 | Damaged (2) |
| 3 | Complete (Idle 1) | 8 | Destroyed (1) |
| 4 | Idle 2 (Details) | 9 | Destroyed (2) |

This is the THIRD and richest contract beside the two above, and it is the
one that gives a building a real **construction animation**: three build
rows of eight frames is 24 frames, walked left to right and row by row as
the site's own labour accrues (`BuildingLifecycleSheet.build_cell_for`),
where the 8x5 sheet's single construction row had eight. Three idle rows
are 24 finished looks on top, so a street of cottages is a street of
different cottages AND each one is the same house it was while it was
rising (`idle_cell_for`).

A building picks ONE of its declared variation sheets from its own seed and
keeps it for life (`BuildingLifecycleSheet.sheet_for`). Nothing that is not a
home has one.

**A building stands on the ground; it does not replace it (2026-09-19).**
Reported with four of them in shot: *"Cottages and Manors are clipped"*.
Nothing was clipped. Every cell of a building's footprint — the anchor
carrying the building id, and `BuildingCatalog.FOOTPRINT_TILE_ID` on the
rest — fell through `atlas_coords_for_modification` to the plain-earth slot,
so the whole plot painted as a hard brown rectangle. A building's art is
scaled to its plot's WIDTH and keeps its own aspect, so a cottage covers
about 97% of its plot's depth and a manor as little as 85% (measured,
`tools/probe_building_fit.gd`) — and the bare brown band left above the roof
is what reads as the roof being cut off inside a box.

This is exactly the bug a farm rail already had, with exactly its fix: a
building is a real `Sprite2D` standing on the ground, so it has no ground
tile of its own to paint and the grass it was raised on goes on showing
around it (`TerrainRenderer.BUILDING_OVERLAY_TILE_IDS`). The list is pinned
against `BuildingCatalog` rather than trusted, which is how it caught
`trade_hall` and `mage_guild` the day they were added.

**A cell is cut where the drawing ends, not where it thins (2026-09-20).**
Reported with five of them in shot: *"Cottages are still slightly clipped at
the top despite having free space in the 2x2 tile."* This time they really
were — and the cut happened in the SLICER, long before anything placed them.
The roof apex, its finial and the whole chimney cap were outside the cropped
cell: measured on `cottage_3.png`, the band was rows 421–569 where the
drawing runs 390–570, losing 31 rows off the top and 13px off each side.

The cause is not about houses. `VariantSheetGrid.art_bands` calls a sheet row
a divider when 60% of it is magenta — and **a row crossing eight roof apexes
is mostly magenta**, because sparse art reads as background. On
`cottage_*.png` and `manor_*.png` there is no divider to find at all: no row
on either reaches even a 0.99 magenta share, where `house_1_*.png` reaches
1.000. So a band simply began wherever the roofs' silhouette thinned past
the threshold.

The fix is not a threshold. `content_bands` already existed for precisely
this, and says so in its own comment — *"art_bands looks for magenta divider
lines, and the line here is near-white"*. What was wrong is that the grid
**kind** is a property of the sheet and was hardcoded to `dividers` for every
variation sheet alike. The cottage and manor sheets declare
`IllustratedStructureSprite.GRID_CONTENT` now (bands read off the art on both
axes), `house_1_*` keeps `dividers`, and the chain asks the sheet instead of
assuming. `GRID_KINDS` is published off the reader's own constants, so a
sheet naming a kind nothing can read fails loudly rather than falling through
to the even cut — which is how these sheets spent their life being read the
wrong way.

Two consequences, both handled rather than shipped. Reading by art reaches
far enough on some cells to swallow the sheet's own pale **rule line**, which
would have traded a clipped roof for a white scratch across the eaves; it is
trimmed, and trimmed *through*, since a chimney tip from the row above
survives a row or two past the rule. A rule is told from a drawing by SPAN
rather than colour: a roof apex is 9–31 opaque pixels across a ~174-wide
cell, a rule runs the whole way. And a whole cottage is about a fifth taller
than a cut one, which made it the tallest thing on the street again — the
exact misorder the ladder below exists to correct — so `_DRAW_SCALES` moved
0.85 → 0.80, still pinned by that ladder's own two tests.

The guard describes the defect rather than the constants: the sheet row above
a crop must be **essentially empty or essentially full**, because a partly
covered row is the silhouette of a roof being sliced. Every cut measured
before the fix sat at 40–52%; every whole crop is at 0–17% or 100%.

**…and the same house RISING (2026-09-20).** Reported the moment a village
started one: *"it's clipped and doesn't use the intermediate construction
sprites so you can see the progress... also it's scaled improperly"*. All
three are one fault, and it is the pass above stopping one chain short. The
grid kind is a property of the SHEET, `finished_sheet_chain` asks the sheet
for it — and `construction_sheet_chain` still NAMED `dividers` for every
house, so a cottage or manor going up was cut on magenta lines its own sheet
does not draw.

Measured before the fix (`tools/probe_construction_stage.gd`), `cottage_1`
row 0 as the build runs: cells **145×105, 149×105, 153×105**, where the
sheet's own content cut gives **171×174** every time and the finished house
is 172 wide. A cell half the sheet's own pitch tall, changing shape frame to
frame, drawn scaled to one fixed plot width, is precisely a house that is
clipped, scaled wrong, and unreadable as a stage of anything. After: every
stage within 2% of the finished house's own width, drawn 21.0 × 21.0 world
units at every one of the five stages, and the strip reads left to right as
footings → frame → truss → roof → house
(`tools/probe_construction_render.gd`, kept).

The guard above is now asked of the rising house as well as the standing one
(`test_no_rising_house_crop_cuts_through_the_top_of_its_own_drawing`), plus
a scale guard against the finished cell
(`test_every_stage_of_one_build_is_drawn_at_the_scale_its_finished_house_
will_be`) — the cut it catches was 11–16% narrow. **Why it took a report to
find:** the existing crop guard read its sheets with `load()` as a
`Texture2D`, which answers null for art whose imported artifact has never
been generated in that checkout — every headless run on a fresh clone. It
was erroring on `cottage_3` rather than guarding, while the bug shipped one
chain along. It reads through `SpriteSheetLoader` now, which falls back to
the file's own bytes.

**Somebody is working on it (2026-09-20).** Asked for directly, watching a
village raise a cottage: *"the construction site should show a builder
working on it"*. A site was a picture of a building going up and nothing
else: the stage sprite changed as labour accrued, and the plot was
otherwise empty ground.

The labour is not abstract, so the worker is not decoration. A settlement
spends real spare hands on its projects — `SettlementSpareCapacity` scaled
by `settlement_productivity`, the `builder_count` `ConstructionCatchup`
charges the project's required hours against — and that number is already
the difference between a hall that rises and one that does not. The
builder is that number made visible.

- **One builder per site that is really being worked.** A
  `ConstructionWorkerMarker` stands on the plot while its settlement has
  hands on the work, and is gone the moment the project completes, is
  abandoned, or its chunk unloads — the site node's own life exactly
  (`_sync_construction_site`/`_free_construction_site`), because a worker
  outliving the site he works is a ghost.
- **Nobody, when nobody is working.** `builder_count` is zero for a
  settlement with no spare capacity — everyone fed, gathering, or too few
  households to spare one — and a site that is accruing no labour shows no
  worker. A figure standing over a project that has not moved in a week is
  a lie the ledger would be telling for us.
- **One figure, not a crew.** `builder_count` is settlement-WIDE and shared
  across every project that settlement has going, so drawing one worker per
  unit at each site would show the same hands two and three times over. One
  builder per site is the honest reading of a shared number: somebody is
  working here.
- **A small purpose-built walker**, like the Farmer and the Lumberjack and
  for the same reason — not the `NpcMarker` schedule stack. He paces his
  own plot, works a spell, and moves on, and he never leaves the footprint:
  the site is the job. Drawn by `ProceduralBuilderSprite` in the same tiny
  silhouette style at the same `SIZE`, with a mallet up rather than an axe
  held or a shaft pulled, so the three workers a village has out at once
  are told apart at a glance.

**The house tiers read as a ladder (2026-09-19).** Asked in the same breath:
*"also scale down cottage to be smaller than house"*. Measured, a cottage
drew 26.0 × 26.0 world px against a house's 39.5 × 24.0 — the smallest tier
was the tallest building on the street. Both are drawn at the same share of
their own plot width and their plots differ only in width (2×2 against 3×2),
so the whole misorder came from the art's aspect: a cottage is drawn square,
a house low and wide.

`BuildingCatalog._DRAW_SCALES` carries the correction, because how big a
building is drawn is a fact about the *building* rather than about whichever
sheet its picture came from — and both the illustrated path and the
procedural placeholder then read one answer. Pinned by what it produces
rather than as a number somebody liked, the same discipline
`PLOT_MARGIN_SHARE` keeps: against the REAL sheets, a cottage must come out
smaller than a house in both dimensions and a house shorter than a manor,
and a cottage must still cover most of its own plot or it stops reading as a
building on that ground. Now 22.5 × 22.5, 39.5 × 24.0, 39.5 × 37.5.

**One tier, one building (2026-09-19).** All three house tiers used to share
the five `house_1_*` sheets, which this doc called deliberate *"until grander
art for those tiers lands, at which point they get their own entries"*. It
landed, and was asked for directly: *"I added cottage and manor sprites...
please fix that villages use scaled houses for those and use the real
illustrations ... cottage 2x2; house 3x2; manor 3x3"*.

| tier | footprint | art |
|---|---|---|
| `house_small` | 2×2 | `cottage_1.png` .. `cottage_5.png` |
| `house_medium` | 3×2 | `house_1_1.png` .. `house_1_5.png` |
| `house_large` | 3×3 | `manor_1.png` .. `manor_5.png` |

The manor was 4×3 — wider than it was deep, and as wide as the town hall,
which is the shape the real manor illustration then had to squeeze into. The
footprints given above are also what the art's own aspect ratios want: a
rendered cottage cell is square, a house cell is half again as wide as deep,
and a manor cell is very nearly square.

**A variation set carries the grid its own art is drawn on.** The cottage and
manor sheets are the OLDER 8×5 contract at the top of this section, not
`house_1_*`'s 8×10 one — measured, not assumed
(`tools/probe_building_lifecycle_sheet.gd` reads five divider-separated row
bands and eight columns off `cottage_1.png`, and the rendered cells confirm
the rows: row 0 a foundation ring, row 2 a finished building, row 3 one on
fire). So `BuildingLifecycleSheet.grid_for` says a set's columns, rows, build
rows and idle rows, and `build_cell_for`/`idle_cell_for` and both sheet
chains read it rather than assuming every set is the richest one. A cottage
therefore rises through its sheet's single eight-stage construction row where
a medium house still walks all 24 of its own frames, and a finished cottage
or manor is only ever drawn from its idle row — never the burning or ruined
ones beside it.

The manor is also **off the flat variant sheet**: `house_1.png` is a page of
25 cottages, so a manor whose own sheet were missing would fall back to a
picture of a cottage, which is exactly what "villages use scaled houses"
described. It falls through to the honest procedural placeholder instead. The
two smaller tiers keep it — for a cottage that page IS cottage art.

Which picture a building actually gets is one ordered chain, best first
(`BuildingCatalog.finished_sheet_chain` / `construction_sheet_chain`), each
entry naming how its own grid is read — `even`, `gutters` or `dividers`.
The renderer takes the first whose file is really on disk, so declaring art
that has not been dropped in yet changes nothing, and a missing file never
drops a building back to a procedural box while better art exists. The flat
variant sheet is deliberately absent from the construction chain: it draws
25 finished cottages and no scaffold.

**Village prop sheets** — `assets/sprites/landmarks/<landmark_id>.png` by
default, one drawing per prop, background keyed out
(`LandmarkSheet`). A prop whose delivered art differs declares the
difference per id rather than having it assumed: where the file actually
is, whether it is a grid of variants, and how that grid's cells are found.
The **well** (delivered 2026-09-17) differs on all three — 25 wells in a
5x5 grid with magenta divider lines, in `assets/sprites/buildings/well.png`
beside the house sheets it was drawn alongside — and a well picks its own
from its seed, so no two wells in a region need be the same well.

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
- ✅ **The village grows** (2026-09-16, full detail in
  [village_growth.md](village_growth.md)). The catalog gained five more
  whole-building entities — `sawmill`, `farmhouse`, `warehouse`,
  `blacksmith`, `brewery` — each with its real sheet already on disk and
  its price shared with `CraftingRecipeBook` rather than duplicated. Every
  village with timber in reach is founded with a sawmill at the forest
  edge, joined to the street by a real road spur (`VillageLayout.industry_
  plot`); as households move in (`VillageImmigration`), the village raises
  the next rung its size entitles it to (`VillageGrowth`) on the next free
  street frontage (`VillageLayout.next_street_plot`), houses for homeless
  households first. The three houses gained recipes so a queued house has
  real material to wait on and real labour hours to accrue — deliberately
  with no `ItemCatalog` entry, which is what keeps a house off every
  crafting bench. Clicking any building opens `HousePanel` on its
  household's real needs, happiness and productivity
  (`EarthChunkManager.household_report_at`).
- ✅ **A village fells the trees it needs** (2026-09-16). **A named
  divergence from the "also not in the forest" rule above, for the VILLAGE
  GENERATOR ONLY.** That rule refuses the forest BIOME outright, and
  measuring real terrain around 51.2°N 13.6°E showed what it cost: of 22
  real villages, only 12 (55%) could lay a plaza at all, and forest was the
  blocker in every single failing case — water in none of them. No plaza
  means no civic plot, which means no city hall, so nearly half of all
  villages were losing their civic centre to trees they would have cleared
  in an afternoon.
  `VillageRenderer._is_buildable_local` now asks only `is_water_at_global`:
  a village sites on anything that is not water, for its square, its house
  plots and its roads alike. That is this doc's own other sentence made
  true — *"the NPCs / Player must first fell all trees to make space for the
  building"* — and it is not a promise the code fails to keep, because
  `place_building` and `build_at_global` already call
  `_clear_vegetation_on_cells` and `_block_ground_cover_on_cells` on
  everything they write, and `TreeRenderer.spawn_trees` will not put a tree
  back on a modified cell. Re-measured after the change: 22 of 22 (100%)
  lay a plaza, 22 of 22 site a sawmill, and every village places all five
  of its houses.
  The **player's** own build gate is deliberately untouched:
  `is_buildable_terrain_at` still refuses the forest biome and a tile with
  a tree still standing on it, because a player fells trees by hand and
  should be told when one is in the way, while a village founding itself
  simply clears its site. `SettlementGenerator` still refuses to found a
  village in a forest-DOMINANT chunk at all, so this clears the wooded
  patches inside an otherwise open chunk rather than carving a town out of
  deep forest.
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
- ✅ **City Hall over time** (2026-09-16). The plaza's civic plot
  (`VillageLayout.skeleton`) is where the village raises its own town
  hall through the settlement-construction ledger — `CivicBuildDecision`
  (three households, spare hands, wood and stone gathered into the village
  market) starts a settlement-owned `ConstructionProject`; labour accrues
  from spare capacity; a construction site drawn from `city_hall.png`'s
  row 0 (`BuildingCatalog.construction_stage_for`) stands on the plot and
  the real `city_hall` building replaces it on completion, its doorstep
  still the street. Full account in
  [civic_construction.md](civic_construction.md) "Meeting Hall". Tested
  (`test_civic_build_decision.gd`,
  `test_earth_chunk_manager_city_hall_rising.gd`).
- ✅ **Somebody is working on the site** (2026-09-20).
  `ConstructionWorkerMarker` + `ProceduralBuilderSprite`: one builder on a
  site its settlement really has hands on, gone with the site itself, and
  legible at the size he is really drawn (both failures of the first draft
  are pinned as measurements, not taste). Full account above, "Somebody is
  working on it". Tested (`test_procedural_builder_sprite.gd`,
  `test_construction_worker_marker.gd`,
  `test_earth_chunk_manager_city_hall_rising.gd`).
- ✅ **The square under a hall, and the kerb round every plot**
  (2026-09-20). The overlay rule above leaves a building showing the
  ground it was raised on — but placement LIFTS the paving it covers, so a
  hall on the village square showed the grassland the square was paved
  over. A building now reads its own kerb (`TerrainRenderer.building_
  ground_tile_for`/`building_ground_by_cell`, `PAVED_KERB_SHARE`): mostly
  paved means it stands on the square and paints that paving, anything
  less stays the plain overlay. Re-derived per paint, nothing persisted,
  so older villages heal on reload. `ProceduralFootprintKerbSprite` draws
  the plot's own outline from the same rect as the collision body,
  beneath the building's art, with its visibility over every ground
  measured rather than eyeballed (`contrast_over`/`MIN_GROUND_CONTRAST`).
  Measured before and after on three real settlements
  (`tools/probe_building_ground.gd`) and confirmed on a real render
  (`tools/probe_village_render.gd`). Tested (`test_building_ground.gd`,
  `test_procedural_footprint_kerb_sprite.gd`, `test_terrain_renderer.gd`,
  `test_earth_chunk_manager_buildings.gd`).

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

## Houses stand shoulder to shoulder

Suggested directly, with three houses and the gaps between them in shot:
*"could save some space in villages by omitting the gap between houses"*.
`VillageLayout.PLOT_GAP_TILES` is **0** — a street's plots are flush, the
way a village street actually looks, and it is real space: one tile per
pair, on every street, in every village. Measured on a real village
(`tools/probe_village_map.gd`), one street row went from `hhh.hhhh` to
`hhhhhhhhhh`: the same ground carrying three more house tiles.

What is still guarded is what the gap was ever load-bearing for — two plots
must never **overlap** — and that is the claimed-cells check, not the
spacing. `test_adjacent_plots_on_the_same_street_never_overlap` asserted the
opposite until this (no two footprints even orthogonally adjacent), and the
reversal is the player's, not a correction.

The PLAZA keeps its own one-tile clearance, split out as
`PLAZA_CLEARANCE_TILES`. It shared the plot-gap constant and is a different
question: the square is never frontage, so a house flush against it would
stand in the space the square *is*.

## Village props: where a stand, a well or a bed gets its real art

Asked for directly, from a screenshot of a village whose houses and city
hall are real pixel art standing beside a market stall drawn from code:
*"all procedural stands, wells, beds etc"*.

Every village prop — the shared **well**, **stall** and **gate**, and the
per-occupation workspot props **field**, **forge**, **dock**, **garden**
and **hunting_ground** — is drawn by `ProceduralLandmarkSprite`, generated
pixel by pixel at runtime. `LandmarkSheet` gives each of them the same way
in that a building already has:

> Put a PNG at `res://assets/sprites/landmarks/<id>.png` and it takes over.
> Until that file exists, the procedural sprite is drawn exactly as before.

Nothing else changes when one arrives. `VillageRenderer._landmark_texture`
asks `LandmarkSheet` first and falls back, so art can land one prop at a
time without a half-converted village looking broken.

**What a file has to be**, matching the building sheets already in the
repo (`house_1.png`, `city_hall.png`):

- A **black background**, keyed out on load by the same threshold
  `IllustratedStructureSprite` uses for buildings.
- Authored **oversized** for pixel detail. The renderer scales it back by
  `ArtResolution.SPRITE_SCALE`, so the prop's world footprint is unchanged
  whatever size the file is — see [art_resolution.md](art_resolution.md).

**One image is enough, and that is deliberate.** A house sheet is a 5×5
grid because twenty-five cottages keep a street from looking repeated; a
well is a well, and asking for twenty-five drawings of one to get one on
screen is the wrong trade. A prop that someone does decide is worth varying
declares its grid in `LandmarkSheet._SHEET_GRIDS` and then draws from it
seeded by its own position, exactly the way a house does — the grid is
gutter-detected, so the cells need not be evenly spaced.

`hunting_ground` was for a while the one prop with no drawing of its own,
and that was not the harmless cosmetic gap it was recorded as: an id this
catalog does not know falls back to the **well's** sprite, so every hunter
in a village stood what looked like a second well out behind the houses —
reported live as *"there are 3 wells and one stand all over the place"* and
measured on the real load path with `tools/probe_village_props.gd`. It has
its own drawing now (a drying rack with a hide stretched on it), and the
rule that let it through is pinned by test: every work tag in
`NpcIdentity.WORK_LOCATION_BY_OCCUPATION` must be one
`ProceduralLandmarkSprite` can actually draw.

### Status

- ✅ `LandmarkSheet` — path, existence, grid and seeded variant cell, with
  the procedural sprite as the fallback (`test_landmark_sheet.gd`).
- ✅ `VillageRenderer._landmark_texture` routes every prop through it
  (`test_village_renderer.gd`).
- 🚧 The art itself. `well.png` and `stall.png` (delivered as
  `assets/sprites/buildings/stand.png` — a 5×5 grid, magenta-keyed rather
  than black-background like the building sheets, gutters measured
  directly off the real PNG with `tools/_probe_stand_bands.gd`/
  `_probe_stand_frame.gd`) are both real now; every other prop
  (`gate`/`field`/`forge`/`dock`/`garden`/`hunting_ground`) still draws
  procedurally, which is exactly what the tests currently pin.
- ⬜ **Beds and other furniture are NOT covered.** They are painted into
  the furniture `TileMapLayer` rather than spawned as prop sprites
  (`HouseDecor`), so they need their own path; this contract is for the
  props `VillageRenderer` places.
