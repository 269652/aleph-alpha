# Long Grass

## Design pillars

1. **A patch is a small field, not one oversized tuft.** Every mature
   `TallGrass` simulation cell renders several illustrated blade cards from
   `assets/sprites/grass_blades.png`, with deterministic variation.
2. **Depth is readable in a top-down world.** Cards share their ground anchor
   and are ordered from back to front by that anchor, allowing the player and
   creatures to pass naturally behind foreground blades while retaining clear
   feet/ground placement.
3. **Motion is cheap and physical.** Wind and nearby walkers bend blade tops on
   the GPU. Roots never translate, a walker leaves a short-lived wake, and the
   field uses one shared material rather than per-blade scripts or materials.

## Mechanism

`IllustratedGrassPatch` selects a tile from the delivered 10×10 illustrated
blade atlas (about 128 pixels per source cell) by stable cell seed. Each selected card is rooted at its own
deterministic sub-tile offset. Growth multiplies the entire patch scale. The
shader adds ordinary wind plus a radial, directionally-away bend around the
player's world position. `EarthChunkManager` updates that one shared player
position uniform once per frame and creates patches only within decoration
LOD range.

Tall grass initially occupies at least one fifth of eligible grassland cells,
with a 128-patch hard chunk cap. This makes a traversable field while retaining
a fixed maximum number of cards under the existing decoration LOD.

## Status

- 🚧 Atlas-backed, layered patch rendering and player wake are being wired.
- ⬜ Creature wake uses the same shader input but is not yet wired.
