extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Pure per-chunk tall-grass simulation. Patches seed on grassland cells,
## clustered into fields by smooth noise (see FIELD_NOISE_SCALE/
## FIELD_NOISE_THRESHOLD), when the chunk's simulation is created, grow
## toward maturity over time (advance), and -- once mature -- spread into
## adjacent grassland cells on a throttled tick (same centralized-ticking
## idea as TreeSpread: bounded work per tick, never per-patch-per-frame).
## Herbivores (and later scything players) call graze(cell) to eat a patch.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Reference overall density (0..1) grassland starts covered in grass.
## Reported live: "remove the percentage of overall grass blades instead
## make them stick more together forming fields using perlin noise /
## voronoi" -- an independent per-cell roll against this chance gave the
## right overall coverage but, because each roll is uncorrelated with its
## neighbours, painted scattered individual dots rather than a field a
## player would read as a meadow (see _seed_initial_patches, which now
## thresholds smooth noise instead). This constant itself stays as the
## reference commonality other systems compare their own rarity against
## (DesertScrub, EarthwormPatch, WildCropPatch, TundraLichen all pin
## themselves rarer than this in their own tests) and the density the noise
## threshold below was empirically tuned to approximate.
const SEED_CHANCE := 0.20
## Hard cap on patches per chunk, so spread can't grow unbounded. Must
## actually accommodate the density target above for a REAL chunk, derived
## from EarthChunkManager.CHUNK_SIZE (32, kept a plain literal here rather
## than imported -- EarthChunkManager already imports TallGrass, so importing
## it back would be circular): 32 squared * SEED_CHANCE (0.20) = 204.8,
## rounded up to 205. The previous value (128, ~12.5% of a full chunk) was
## well under this documented ~20% target, so on any chunk that generated
## mostly/fully grassland, initial seeding ALONE already reached the cap
## before any spread or planting happened, leaving plant() permanently unable
## to succeed there (confirmed live: a real Berlin chunk dense enough in
## grassland hit exactly this, failing
## test_earth_chunk_manager.gd's test_plant_grass_at_establishes_a_new_patch
## deterministically). See test_tall_grass.gd's
## test_max_patches_accommodates_the_density_target_for_a_real_full_chunk,
## which independently recomputes this same derivation from
## EarthChunkManager's real constants so it re-verifies automatically if
## either ever changes, rather than silently drifting out of sync again.
const MAX_PATCHES := 205

## Lattice-cell size (in cells/tiles) of the smooth-noise field
## _seed_initial_patches thresholds: how large one noise "bump" spans.
## Small enough that several distinct fields fit across one 32-tile chunk,
## large enough that a field reads as a many-tile meadow rather than
## degenerating back into per-tile noise. Measured empirically (a real probe
## sweeping scale x threshold combinations, deleted after use per this
## project's convention -- see docs/concept/long_grass.md) rather than
## eyeballed, together with FIELD_NOISE_THRESHOLD below -- pinned exactly by
## test_field_noise_scale_and_threshold_are_pinned_to_their_measured_values.
const FIELD_NOISE_SCALE := 0.12
## Cells whose noise sample exceeds this threshold seed grass. Chosen from
## the same probe as FIELD_NOISE_SCALE: at scale 0.12, threshold 0.65 gave
## ~20% overall coverage across many sampled chunks, matching SEED_CHANCE's
## old target density (the two aren't read together at runtime -- this is
## just how the value was picked).
const FIELD_NOISE_THRESHOLD := 0.65
## Growth (0..1) gained per second of advance().
const GROWTH_RATE := 0.01
## Seconds between spread ticks.
const SPREAD_INTERVAL := 30.0
## Max new patches created per spread tick.
const SPREAD_PER_TICK := 2

## How far a shed seed can land from the mature patch that dropped it, in
## cells (see docs/concept/long_grass.md's "Reproduction" section). Mirrors
## FlowerPatch.SEED_FALL_RADIUS: seed falls close by default, and carrying it
## further than this is what an animal is for.
const SEED_FALL_RADIUS := 2

## Hard cap on ground seed per chunk, the same bounding rationale as
## MAX_PATCHES -- an unattended field must not carpet itself in seed over a
## long session. Kept well under MAX_PATCHES so the shed layer never
## approaches the density of the standing grass itself.
const MAX_GROUND_SEEDS := 48

## Expected seconds between shed events for a single mature patch. Longer
## than FlowerPatch.SECONDS_PER_SEED_FALL (40.0) because every mature patch
## sheds here (up to MAX_PATCHES = 205), where a flower meadow's shedding
## population is the much smaller "past bloom and pollinated" subset of
## MAX_FLOWERS = 40 -- tuned up so the aggregate accumulation rate stays the
## same order of magnitude rather than flooding the ground the moment a
## field matures.
const SECONDS_PER_SEED_FALL := 60.0

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> growth float (0..1; 1 is mature).
var _patches: Dictionary = {}
var _spread_accumulator := 0.0
var _spread_tick := 0

## Vector2i cell -> true. Seed is its OWN entity lying on the ground, not a
## state of the patch (see docs/concept/long_grass.md), so it can be queried,
## eaten, and carried independent of the plant it fell from. No species
## field, unlike FlowerPatch's ground seed: a chunk grows exactly one kind of
## grass, so there is nothing for a carried seed to disambiguate.
var _ground_seeds: Dictionary = {}
var _shed_accumulator := 0.0
var _shed_index := 0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_patches()


func get_patch_cells() -> Array:
	return _patches.keys()


func has_grass(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent grassland cells. `growth_modifier` scales the
## growth INCREMENT only (see SeasonCycle.growth_modifier) -- spread timing is
## untouched, so a slow winter still colonises new cells on the same clock,
## it just grows in more slowly once there.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE * growth_modifier, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was grass to eat.
func graze(cell: Vector2i) -> bool:
	return _patches.erase(cell)


## Drops seed from mature patches onto nearby ground (see SEED_FALL_RADIUS).
## Unlike FlowerPatch.shed_seed, there is no bloom-season gate -- a mature
## TallGrass patch (growth >= 1.0) is reproductively active the instant it
## grows in, the same rule that already lets map-seeded grass start mature.
func shed_seed(delta: float) -> void:
	if _ground_seeds.size() >= MAX_GROUND_SEEDS:
		return
	var mature: Array = []
	for cell in _patches:
		if _patches[cell] >= 1.0:
			mature.append(cell)
	if mature.is_empty():
		return
	# One shed event per SECONDS_PER_SEED_FALL per mature patch, so a denser
	# field drops seed proportionally faster than a sparse one -- the same
	# shape as FlowerPatch.shed_seed's own accumulator.
	_shed_accumulator += delta * float(mature.size()) / SECONDS_PER_SEED_FALL
	while _shed_accumulator >= 1.0 and _ground_seeds.size() < MAX_GROUND_SEEDS:
		_shed_accumulator -= 1.0
		_shed_index += 1
		var parent: Vector2i = mature[_shed_index % mature.size()]
		var h := absi(hash("%d_%d_grass_seed_fall" % [_seed_value, _shed_index]))
		var offset := Vector2i(
			(h % (SEED_FALL_RADIUS * 2 + 1)) - SEED_FALL_RADIUS,
			((h / 13) % (SEED_FALL_RADIUS * 2 + 1)) - SEED_FALL_RADIUS
		)
		var cell := parent + offset
		if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
			continue
		if _ground_seeds.has(cell):
			continue
		_ground_seeds[cell] = true


func ground_seed_cells() -> Array:
	return _ground_seeds.keys()


## Takes the seed lying at `cell`, if there is one. Returns whether a seed
## was actually there -- no species to report, unlike FlowerPatch's
## take_ground_seed, since a chunk grows only one kind of grass.
func take_ground_seed(cell: Vector2i) -> bool:
	return _ground_seeds.erase(cell)


## Establishes a brand-new, immature patch at `cell` -- the counterpart of
## FlowerPatch.plant, and the sink a bird's or mouse's carried grass seed
## lands in once it is done being carried (see docs/concept/long_grass.md).
## Returns false when the cell already has grass, isn't grassland, or the
## chunk is at its cap, so a caller can just offer a drop and let this decide.
func plant(cell: Vector2i) -> bool:
	if _patches.size() >= MAX_PATCHES:
		return false
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _biome[cell.y * _width + cell.x] != "grassland":
		return false
	if _patches.has(cell):
		return false
	_patches[cell] = 0.0  # planted, not map-seeded: starts as a shoot and must grow
	return true


## Thresholds smooth noise (FIELD_NOISE_SCALE/FIELD_NOISE_THRESHOLD) rather
## than rolling each cell independently (see SEED_CHANCE's own doc comment):
## neighbouring noise samples stay close together, so this carves out
## contiguous blobs -- real fields -- instead of salt-and-pepper. Sampled in
## this chunk's own LOCAL cell coordinates against _seed_value, the same
## per-chunk-deterministic inputs every other roll in this file already
## uses (see class doc: "a reloaded chunk reproduces the same initial
## layout") -- two separate chunks' fields are NOT guaranteed to continue
## into each other seamlessly across the boundary between them, a deliberate
## scope cut (this only needed to read as fields WITHIN a chunk, not a
## seamless world-spanning one -- not asked for, and would need a shared
## noise seed sampled in global tile coordinates instead).
func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != "grassland":
				continue
			var n := PixelNoise.smooth(_seed_value, float(x) * FIELD_NOISE_SCALE, float(y) * FIELD_NOISE_SCALE)
			if n > FIELD_NOISE_THRESHOLD:
				_patches[Vector2i(x, y)] = 1.0  # initial grass starts mature, like map-generated trees


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
		var h := absi(hash("%d_%d_%d_grass_spread" % [_seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if _biome[target.y * _width + target.x] != "grassland":
			continue
		if _patches.has(target):
			continue
		_patches[target] = 0.0  # spread grass starts immature and must grow
