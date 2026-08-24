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

## Structure building: pieces, rooms, and enterable houses

The sections above are design philosophy; this is the mechanism spec.
Terraria-style single-tile placement (bare earth, campfires) already exists.
This adds **structures**: assemblies of typed pieces that together form a
real, enterable building — the Valheim/Atlas-style construction the game
asks for, adapted honestly to a top-down 2D world.

### What "enterable" means in a top-down game

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
  reads differently).
- **Roof** — covers a room; hidden while the player is inside it.

Each piece has a **material** (wood, stone) carrying cost, durability, and
look. Materials exist so building has a progression that follows the
existing gather → craft → smelt chain rather than being a flat cosmetic
choice.

### Placement rules

Rules exist to stop floating nonsense, not to nag:

- A floor may be placed on any buildable ground (not water, not on an
  existing structure piece).
- A wall, door or window must sit on, or orthogonally touch, a floor piece
  — walls belong to a building, not to open wilderness.
- A roof must sit above a cell that is part of an enclosed room.
- Nothing may be placed where a piece already exists; destroying returns the
  piece's material (mirroring the existing build/destroy loop).

Placement validity is pure logic over a grid, so it can be asked the same
question by the player's build cursor and by the NPC village generator.

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
`VillageRenderer._find_dry_origin` closes the most visible instance of this
by mirroring `can_place`'s own "not water" rule before stamping, nudging to
nearby dry ground (or skipping the house if none is found) — but it is its
own bespoke check, not a call into `BuildingPlacement` itself, so other
placement rules (not overlapping an existing piece, walls needing an
adjacent floor) still aren't enforced for village generation. Full
unification — the village generator asking `BuildingPlacement` the same
question the player's build cursor does — remains a follow-up.

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

None of this changes the piece vocabulary or what gets persisted — a roof
is still one `wood_roof`/`stone_roof` chunk modification per cell (see
Persistence below). All of the above is resolved at PAINT time from the
neighbouring cells, exactly like terrain blending, so no new piece ids and
no save-format change are involved.

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
  unit-level piece/placement/room logic. `VillageRenderer._find_dry_origin`
  nudges a house's origin off a water pocket before stamping (see "One
  system, two builders" above), and every merchant villager gets a second,
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
