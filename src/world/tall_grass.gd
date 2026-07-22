extends RefCounted

## Pure per-chunk tall-grass simulation. Patches seed deterministically on
## grassland cells when the chunk's simulation is created, grow toward
## maturity over time (advance), and -- once mature -- spread into adjacent
## grassland cells on a throttled tick (same centralized-ticking idea as
## TreeSpread: bounded work per tick, never per-patch-per-frame). Herbivores
## (and later scything players) call graze(cell) to eat a patch.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed / tick, so a reloaded chunk reproduces the same initial layout.

## Chance (0..1) that any given grassland cell starts with a grass patch.
const SEED_CHANCE := 0.08
## Hard cap on patches per chunk, so spread can't grow unbounded.
const MAX_PATCHES := 64
## Growth (0..1) gained per second of advance().
const GROWTH_RATE := 0.01
## Seconds between spread ticks.
const SPREAD_INTERVAL := 30.0
## Max new patches created per spread tick.
const SPREAD_PER_TICK := 2

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


func has_grass(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent grassland cells.
func advance(delta: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was grass to eat.
func graze(cell: Vector2i) -> bool:
	return _patches.erase(cell)


func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != "grassland":
				continue
			var roll := float(absi(hash("%d_%d_%d_grass_seed" % [_seed_value, x, y])) % 10000) / 10000.0
			if roll < SEED_CHANCE:
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
