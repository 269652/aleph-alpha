extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Pure per-chunk aquatic invertebrate simulation -- see docs/concept/
## aquatic_foraging.md's "Revised (2026-09-07)". Mirrors AquaticVegetation's
## own patch-sim contract line for line (PixelNoise-seeded smooth-noise
## field clustering, a hard per-chunk cap, advance(delta, growth_modifier),
## a pure graze(cell) -> bool, water-cell-gated seeding) -- the same "clone
## the proven shape, change what's genuinely different" convention
## AquaticVegetation itself already used against TallGrass.
##
## What is genuinely different from AquaticVegetation: this represents real
## aquatic insect larvae (mayfly/caddisfly/midge nymphs and similar) --
## trout's own real dominant food, the diet gap plain vegetation alone
## could never close for an insectivorous species (see FishDiet). GROWTH_
## RATE is tuned higher than AquaticVegetation's own -- a real insect-larva
## population turns over on the order of days/weeks, far faster than a weed
## bed's own rhizome-driven regrowth, so a grazed patch visibly recovers
## sooner.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Same field-clustering scale/threshold AquaticVegetation/TallGrass both
## use -- nothing about that measurement was specific to one producer's own
## density, and this lives in the identical water-cell space
## AquaticVegetation already does (both sims coexist in the same water --
## real ponds host both plants and insect life together, not one or the
## other).
const FIELD_NOISE_SCALE := 0.12
const FIELD_NOISE_THRESHOLD := 0.65

## Same overall density AquaticVegetation.SEED_CHANCE approximates, for the
## identical reason: nothing about eligible-cell density differs between
## the two producer layers, only their own regrowth rate does (see
## GROWTH_RATE below).
const SEED_CHANCE := 0.20

## Identical derivation to AquaticVegetation.MAX_PATCHES -- must accommodate
## SEED_CHANCE for a real, all-water chunk. See that constant's own doc
## comment; cross-checked by test_max_patches_accommodates_the_density_
## target_for_a_real_full_chunk so re-tuning CHUNK_SIZE/SEED_CHANCE can't
## silently under-size this again.
const MAX_PATCHES := 205

## Growth (0..1) gained per second of advance() -- 5x AquaticVegetation.
## GROWTH_RATE (0.01). A real insect-larva population's own turnover
## (days/weeks) is genuinely faster than a rooted plant's rhizome-driven
## regrowth, so a grazed patch of invertebrates recovers sooner than a
## grazed patch of vegetation at the same elapsed time -- pinned by
## test_growth_rate_is_faster_than_vegetations_own, not eyeballed.
const GROWTH_RATE := 0.05
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
## included here, not excluded, the same inclusion filter AquaticVegetation
## already reads it as.
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


func has_invertebrates(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent water cells. `growth_modifier` scales the
## growth INCREMENT only (see SeasonCycle.growth_modifier), the identical
## shape AquaticVegetation.advance already uses.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE * growth_modifier, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was anything to
## graze -- the pure contract a foraging fish just tries and lets this
## decide, the same shape AquaticVegetation.graze/TallGrass.graze already
## use.
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
				_patches[Vector2i(x, y)] = 1.0  # initial invertebrates start mature


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
		var h := absi(hash("%d_%d_%d_aquatic_invertebrates_spread" % [_seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if not _is_water_at(target.x, target.y):
			continue
		if _patches.has(target):
			continue
		_patches[target] = 0.0  # spread invertebrates start immature and must grow
