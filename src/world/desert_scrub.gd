extends RefCounted

## Pure per-chunk desert-scrub simulation. Same architecture as TallGrass
## (deliberately duplicated, not shared -- see that file's doc comment and
## this project's "three similar things beats a premature abstraction"
## convention): patches seed deterministically on desert cells when the
## chunk's simulation is created, grow toward maturity over time (advance),
## and -- once mature -- spread into adjacent desert cells on a throttled
## tick. Herbivores/players call graze(cell) to strip a patch.
##
## Flavor tuning vs. TallGrass: desert scrub is sparser (SEED_CHANCE half of
## grass's) and grows more slowly (GROWTH_RATE half of grass's, real desert
## plants are slow-growing), and spreads on a longer interval with fewer new
## patches per tick, since scrub colonizing bare desert is a slower process
## than grass filling in a meadow. These orderings are pinned by
## test_desert_scrub.gd's test_seed_chance_is_sparser_than_tall_grass /
## test_growth_rate_is_slower_than_tall_grass, not just asserted in this
## comment.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Chance (0..1) that any given desert cell starts with a scrub patch.
const SEED_CHANCE := 0.04
## Hard cap on patches per chunk, so spread can't grow unbounded.
const MAX_PATCHES := 64
## Growth (0..1) gained per second of advance(). Slower than tall grass:
## desert scrub is a slow-growing plant.
const GROWTH_RATE := 0.005
## Seconds between spread ticks. Longer than tall grass's: scrub colonizing
## bare desert is a slower process than grass filling in a meadow.
const SPREAD_INTERVAL := 45.0
## Max new patches created per spread tick.
const SPREAD_PER_TICK := 1

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> growth float (0..1; 1 is mature).
var _patches: Dictionary = {}
var _spread_accumulator := 0.0
var _spread_tick := 0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_patches()


func get_patch_cells() -> Array:
	return _patches.keys()


func has_scrub(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent desert cells.
func advance(delta: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was scrub to strip.
func graze(cell: Vector2i) -> bool:
	return _patches.erase(cell)


func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != "desert":
				continue
			var roll := float(absi(hash("%d_%d_%d_scrub_seed" % [_seed_value, x, y])) % 10000) / 10000.0
			if roll < SEED_CHANCE:
				_patches[Vector2i(x, y)] = 1.0  # initial scrub starts mature, like map-generated trees


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
		var h := absi(hash("%d_%d_%d_scrub_spread" % [_seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if _biome[target.y * _width + target.x] != "desert":
			continue
		if _patches.has(target):
			continue
		_patches[target] = 0.0  # spread scrub starts immature and must grow
