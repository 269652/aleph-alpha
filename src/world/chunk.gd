extends RefCounted

## A fixed-size grid slice of the world: generated terrain data plus any
## player-made modifications overlaid on top of it.

var width: int
var height: int
var elevation: PackedFloat32Array
var biome: PackedStringArray
var moisture: PackedFloat32Array
var temperature: PackedFloat32Array
## 1 where EarthChunkGenerator.is_river_at_global is true, 0 otherwise --
## never folded into `biome` itself (see docs/concept/rivers.md's
## Rendering section: a river never becomes an eighth biome). Lets
## worldgen-time decoration placement (TreeRenderer.spawn_trees, TallGrass)
## exclude river cells without each needing its own live generator
## reference -- they already receive the whole Chunk.
var is_river: PackedByteArray

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

## Real statics (see BuildingStatics / docs/concept/timber_construction.md
## #real-statics-a-support-graph-over-the-piece-grid): how many continuous
## real seconds each currently-unsupported piece cell (keyed like
## `modifications`) has accumulated toward BuildingStatics.GRACE_SECONDS
## before it topples/collapses, and the world-age each was last checked (so
## the next check can compute a real elapsed delta rather than assuming a
## fixed per-event tick). Only ever holds entries for cells CURRENTLY
## unsupported -- a piece that regains its support path is dropped from
## both, forgetting whatever instability it had built up. Not persisted
## across an unload/reload -- an accepted gap, the same class of limitation
## the Lumberjack's own in-progress shaping state already has (see that
## doc's "Offscreen catch-up" status note).
var structural_instability: Dictionary = {}
var structural_checked_at: Dictionary = {}

## Withering (see BuildingDecay / docs/concept/timber_construction.md
## #withering-decay-as-a-bounded-closed-form-catch-up): each placed piece's
## own `condition` (1.0 = new, decaying toward 0.0), keyed like
## `modifications`, and the world-age each was last advanced -- the same
## "value + last-checked-at" pairing structural_instability/
## structural_checked_at already use above, for the same reason (the next
## catch-up pass needs a real elapsed delta, not a fixed per-event tick).
## Sparse like those two: a cell absent here simply hasn't decayed from 1.0
## yet, not "unknown." Not persisted across an unload/reload -- an accepted
## gap, the exact same class of limitation structural_instability's own doc
## comment above already names (EarthChunkManager keeps an IN-SESSION
## unloaded-condition record instead, the same way it does for aggregate
## ecology, so a chunk unloaded and reloaded within one session still
## catches up correctly; only a real app restart loses it).
var piece_condition: Dictionary = {}
var piece_condition_checked_at: Dictionary = {}
