extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Pure per-chunk aquatic vegetation simulation -- see docs/concept/
## aquatic_foraging.md. Mirrors TallGrass's own patch-sim contract almost
## exactly (PixelNoise-seeded smooth-noise field clustering so patches read
## as real weed-beds rather than salt-and-pepper noise, a hard per-chunk
## cap, advance(delta, growth_modifier), a pure graze(cell) -> bool) -- the
## same "clone the proven shape, change what's genuinely different"
## convention EarthwormPatch itself already used against this same sibling
## family.
##
## What is genuinely different from TallGrass: seeding is gated to WATER
## cells (`is_water`, the identical Chunk.blocks_ground_cover mask
## TallGrass itself already reads to keep grass OUT of the water -- read
## here as an INCLUSION filter instead) rather than a land biome, and there
## is no ground-seed-shedding layer at all -- real aquatic plants spread by
## fragmentation/rhizome growth into adjacent water, which the existing
## throttled _step_spread mechanism already models without needing a
## second, carried-seed entity the way TallGrass's own land-animal-carried
## seed does.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Same field-clustering scale/threshold TallGrass itself uses -- both
## values were independently measured against a real probe for "reads as a
## field, not scattered dots" (see docs/concept/long_grass.md); nothing
## about that measurement was specific to grassland's own density, so
## reusing it rather than re-deriving a second pair from scratch is the
## honest choice, not a shortcut.
const FIELD_NOISE_SCALE := 0.12
const FIELD_NOISE_THRESHOLD := 0.65

## The overall density (0..1) this noise scale/threshold combination
## approximates within whatever cells are actually eligible (TallGrass's
## own grassland cells there, water cells here) -- restated from
## TallGrass.SEED_CHANCE's own doc comment ("at scale 0.12, threshold
## 0.65 gave ~20% overall coverage") since the parameters above are
## identical, not re-measured independently. What differs is the
## ELIGIBLE cell count a real chunk actually offers: a river a few tiles
## wide or a modest lake is nowhere near as much of a chunk as its
## grassland extent usually is, so the real, average per-chunk patch
## count comes out proportionally smaller on its own -- but MAX_PATCHES
## below still has to accommodate the WORST case (a whole chunk of open
## water), exactly the failure TallGrass's own MAX_PATCHES doc comment
## already names and fixed once (initial seeding alone hitting the cap,
## permanently blocking spread) -- reusing a smaller cap here without
## re-deriving it against this same density would silently reintroduce
## that identical bug for water instead of land.
const SEED_CHANCE := 0.20

## Must actually accommodate SEED_CHANCE for a REAL, all-water chunk --
## see SEED_CHANCE's own doc comment on why this can't just be an
## arbitrarily smaller number. Derived from EarthChunkManager.CHUNK_SIZE
## (32, kept a plain literal rather than imported -- EarthChunkManager
## already imports AquaticVegetation, so importing it back would be
## circular): 32 squared * SEED_CHANCE (0.20) = 204.8, rounded up to 205,
## the identical derivation and identical result TallGrass.MAX_PATCHES
## already reached for the identical reason. Cross-checked by test
## (test_max_patches_accommodates_the_density_target_for_a_real_full_chunk)
## so re-tuning CHUNK_SIZE or SEED_CHANCE can't silently under-size this
## again.
const MAX_PATCHES := 205

## Growth (0..1) gained per second of advance() -- same rate TallGrass
## itself uses; nothing about real growth speed distinguishes a water
## plant from a land one at this level of abstraction.
const GROWTH_RATE := 0.01
const SPREAD_INTERVAL := 30.0
const SPREAD_PER_TICK := 2

var _width: int
var _height: int
var _is_water: PackedByteArray
var _seed_value: int

## Vector2i cell -> growth float (0..1; 1 is mature).
var _patches: Dictionary = {}
var _spread_accumulator := 0.0
var _spread_tick := 0


## `is_water` is the same shape as Chunk.blocks_ground_cover's own
## per-cell mask (1 where a real chunk has a river or lake cell) --
## included here, not excluded, the mirror image of how TallGrass reads
## the identical mask.
func _init(seed_value: int, width: int, height: int, is_water: PackedByteArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_is_water = is_water
	_seed_initial_patches()


func _is_water_at(x: int, y: int) -> bool:
	var index := y * _width + x
	return index < _is_water.size() and _is_water[index] == 1


func get_patch_cells() -> Array:
	return _patches.keys()


func has_vegetation(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent water cells. `growth_modifier` scales the
## growth INCREMENT only (see SeasonCycle.growth_modifier), the identical
## shape TallGrass.advance already uses.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE * growth_modifier, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was vegetation to
## graze -- the pure contract a foraging fish (or, later, anything else
## that eats aquatic plants) just tries and lets this decide, the same
## shape TallGrass.graze/EarthwormPatch.take already use.
func graze(cell: Vector2i) -> bool:
	return _patches.erase(cell)


func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if not _is_water_at(x, y):
				continue
			var n := PixelNoise.smooth(_seed_value, float(x) * FIELD_NOISE_SCALE, float(y) * FIELD_NOISE_SCALE)
			if n > FIELD_NOISE_THRESHOLD:
				_patches[Vector2i(x, y)] = 1.0  # initial vegetation starts mature


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
		var h := absi(hash("%d_%d_%d_aquatic_vegetation_spread" % [_seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if not _is_water_at(target.x, target.y):
			continue
		if _patches.has(target):
			continue
		_patches[target] = 0.0  # spread vegetation starts immature and must grow
