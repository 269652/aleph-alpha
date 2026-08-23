extends RefCounted

## A fixed-size grid slice of the world: generated terrain data plus any
## player-made modifications overlaid on top of it.

var width: int
var height: int
var elevation: PackedFloat32Array
var biome: PackedStringArray
var moisture: PackedFloat32Array
var temperature: PackedFloat32Array

## Player edits keyed by local tile coordinate (Vector2i) to a tile/structure id.
var modifications: Dictionary = {}

## Roof pieces (see BuildingPiece.CATEGORY_ROOF), keyed by local tile
## coordinate like `modifications` -- but on their OWN layer/dict, not merged
## into it. A roof sits ABOVE the room it covers, sharing its cell with the
## floor piece below (see docs/concept/building.md#pieces); `modifications`
## can only ever hold one tile id per cell, so a roof needs a separate
## Dictionary to coexist with the floor underneath it. Painted onto its own
## TileMapLayer (see TerrainRenderer.paint_roofs), which is what lets it be
## hidden while the player is indoors without touching the floor/wall layer.
var roof_modifications: Dictionary = {}

## Trees that spread into this chunk since it was generated (see TreeSpread/
## EarthChunkManager.step_tree_spread), each {position: Vector2, planted_at:
## float} -- planted_at is the world-age (seconds) it was planted at, used to
## gate forage/further spreading until it reaches its own genome's
## maturity_time (see TreeMaturity). The original map-generated forest is
## deterministic and regenerable, like terrain, so only these need
## persisting across an unload/reload.
var planted_trees: Array = []
