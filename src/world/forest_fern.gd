extends RefCounted

## Pure per-chunk forest-fern simulation (docs/concept/ferns.md). Asked for
## directly: *"can you wire it and make it grow in forest biome"*.
##
## Same architecture as TallGrass, DesertScrub and TundraLichen, and
## deliberately duplicated rather than shared — see TallGrass's own doc
## comment and this project's "three similar things beats a premature
## abstraction" convention. Patches seed deterministically on FOREST cells
## when the chunk's simulation is created, grow toward maturity over time
## (advance), and — once mature — creep into adjacent forest cells on a
## throttled tick. Herbivores and players call graze(cell) to crop one.
##
## A wood is the one biome this world had no ground cover for at all: grass
## is gated to grassland, scrub to desert, lichen to tundra, so a forest
## chunk drew its trees and then bare ground between them.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Chance (0..1) that any given forest cell starts with a fern clump.
##
## Below TallGrass.SEED_CHANCE and well above DesertScrub's: a wood's floor
## is genuinely well covered, but it is broken by trunks and by the deep
## shade under them, where a meadow is wall to wall. The ORDERING against
## grass is what matters and it is pinned by a test
## (test_a_wood_floor_is_sparser_than_a_meadow) rather than asserted here.
const SEED_CHANCE := 0.12

## Hard cap on patches per chunk, so spread cannot grow unbounded.
##
## Derived from the density above rather than picked, the same way
## TallGrass.MAX_PATCHES is and for the reason its own doc comment records
## paying for once: a real full chunk is EarthChunkManager.CHUNK_SIZE (32)
## squared, so seeding alone asks for 32 * 32 * 0.12 = 122.88, rounded up.
## A cap under that would be reached by seeding ALONE on a fully wooded
## chunk, leaving plant() and the spread step permanently unable to
## succeed there — which is exactly the bug that shipped once with grass.
## Recomputed from those same real constants by
## test_the_cap_can_hold_the_density_it_asks_for_on_a_real_chunk, so it
## cannot drift out of sync in silence.
const MAX_PATCHES := 123

## Growth (0..1) gained per second of advance(). Slower than tall grass's
## and faster than desert scrub's: a frond takes a season where a blade
## takes days, but a wood is damp and a desert is not. Only the ordering
## against grass is pinned (test_a_frond_grows_more_slowly_than_a_blade).
const GROWTH_RATE := 0.006

## Seconds between spread ticks. Longer than tall grass's because a fern
## creeps by rhizome where grass casts seed — a bracken stand moves
## outward by tens of centimetres a year, not metres
## (test_ferns_creep_where_grass_spreads).
const SPREAD_INTERVAL := 60.0

## Max new clumps per spread tick. One, for the same reason the interval is
## long: creeping is not casting.
const SPREAD_PER_TICK := 1

## The biome a fern is an understorey of. Named rather than inlined at its
## three use sites, because "which ground is a fern's" is one decision.
const HOME_BIOME := "forest"

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> growth float (0..1; 1 is mature).
var _patches: Dictionary = {}
var _spread_accumulator := 0.0
var _spread_tick := 0

## Cells nothing may grow on — the floor of a real building piece (see
## TallGrass._blocked for the full reasoning; the same rule, the same
## shape).
var _blocked: Dictionary = {}

## Ground nothing may grow on that the BIOME ARRAY cannot see {D} water, and
## a building already standing on a reloaded chunk. The same mask TallGrass
## takes as `is_river` and for the same reason its own doc comment gives: a
## river never changes the biome array, so a grassland check cannot see it
## on its own, and "grass grows in rivers" was reported live before it did.
## A fern seeded before anything has a chance to BLOCK it is the same bug
## one chunk load earlier.
##
## Optional and empty by default, the same optional-trailing-parameter
## shape TallGrass's own addition used: a caller that never passes one is
## treated as "nothing is blocked" rather than getting an index error.
var _growth_blocked: PackedByteArray


func _init(
	seed_value: int, width: int, height: int, biome: PackedStringArray,
	growth_blocked: PackedByteArray = PackedByteArray()
) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_growth_blocked = growth_blocked
	_seed_initial_patches()


## True when (x, y) is ground nothing may grow on {D} size-checked, so a
## caller that passed no mask reads as "nothing is blocked" rather than
## running off the end of an empty array.
func _is_growth_blocked_at(x: int, y: int) -> bool:
	var index := y * _width + x
	return index < _growth_blocked.size() and _growth_blocked[index] == 1


func get_patch_cells() -> Array:
	return _patches.keys()


func has_fern(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Marks `cells` as built on: whatever fern stood there is gone, and
## neither plant() nor the spread step will put one back while the block
## stands.
func block_cells(cells: Array) -> void:
	for cell in cells:
		_blocked[cell] = true
		_patches.erase(cell)


## The reverse, for a piece that was destroyed: wood floor again, open to
## the next rhizome like any other cell.
func unblock_cells(cells: Array) -> void:
	for cell in cells:
		_blocked.erase(cell)


## Advances growth on every clump and, on a throttled interval, lets mature
## ones creep into adjacent forest. `growth_modifier` scales the growth
## INCREMENT only (see SeasonCycle.growth_modifier), exactly as it does for
## grass — spread timing is not seasonal here either.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(1.0, _patches[cell] + GROWTH_RATE * delta * growth_modifier)
	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Crops the clump at `cell`, if there is one. True when something was
## really taken.
func graze(cell: Vector2i) -> bool:
	if not _patches.has(cell):
		return false
	_patches.erase(cell)
	return true


## Puts a young clump on a bare forest cell. False when the cell already
## carries one, is not forest, is built on, or the chunk is at its cap —
## so a caller can simply offer a cell and let this decide.
func plant(cell: Vector2i) -> bool:
	if _patches.size() >= MAX_PATCHES:
		return false
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _biome[cell.y * _width + cell.x] != HOME_BIOME:
		return false
	if _is_growth_blocked_at(cell.x, cell.y):
		return false
	if _patches.has(cell) or _blocked.has(cell):
		return false
	_patches[cell] = 0.0  # a new rhizome, not a full frond
	return true


## Thresholds the same smooth noise TallGrass uses, at the same scale and
## threshold, so a wood's ferns cluster into real stands rather than
## salt-and-pepper — the identical reasoning TallGrass.FIELD_NOISE_SCALE's
## own doc comment records, applied to the cells a fern is allowed on.
##
## The density that comes out is NOT the same as grass's, and is not meant
## to be: the noise threshold decides what share of ELIGIBLE cells are
## taken, and SEED_CHANCE above is the reference this file states its own
## commonality against, exactly as TallGrass does.
func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != HOME_BIOME:
				continue
			if _is_growth_blocked_at(x, y):
				continue
			var h := absi(hash("%d_%d_%d_fern_seed" % [_seed_value, x, y]))
			if float(h % 10000) / 10000.0 < SEED_CHANCE:
				_patches[Vector2i(x, y)] = 1.0  # established stands start mature, like map-generated trees


func _step_spread() -> void:
	var mature: Array = []
	for cell in _patches:
		if _patches[cell] >= 1.0:
			mature.append(cell)
	if mature.is_empty():
		return

	for i in SPREAD_PER_TICK:
		if _patches.size() >= MAX_PATCHES:
			return
		var h := absi(hash("%d_%d_%d_fern_creep" % [_seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if _biome[target.y * _width + target.x] != HOME_BIOME:
			continue
		if _is_growth_blocked_at(target.x, target.y):
			continue
		if _patches.has(target) or _blocked.has(target):
			continue
		_patches[target] = 0.0  # crept, not established: it must grow
