extends RefCounted

## The sward -- the low rosette layer between the tussocks (see
## docs/concept/ground_cover.md).
##
## Reported live, looking at a real grassland chunk at noon: "the bare grass
## parts feel empty". They were: TallGrass covers ~20% of grassland (clustered
## into fields) and FlowerPatch seeds 3.5% of cells, so about three quarters of
## a meadow carried nothing at all -- a flat tiled blade texture whose seams you
## can count, and one cobble every few tiles.
##
## This is the layer that goes there, and it is deliberately NOT scatter. A
## real meadow has two plant layers: the tussock a grazer takes in mouthfuls,
## and beneath it a carpet of rosette-forming herbs -- clover, plantain, daisy,
## yarrow -- that are mostly leaves and ankle-high. How much sward a cell
## carries is a CONSEQUENCE of two things the simulation already tracks, which
## is what makes it a readout rather than decoration:
##
##   SHADE suppresses. A tussock closing over a cell shades the rosettes out.
##
##   GRAZING releases. Every species here grows from a crown pressed flat
##   against the soil, so a bite that takes a grass's growing point with it
##   merely trims theirs. That one anatomical difference is why hard grazing
##   converts a meadow to clover and plantain -- the real "grazing lawn" -- and
##   why a sheep pasture and a hay meadow on the same soil look nothing alike.
##
## Deliberately shaped like TallGrass/DesertScrub/FlowerPatch/EarthwormPatch/
## AntColony -- deterministic PixelNoise placement, a chunk-sized grid, no
## RandomNumberGenerator -- rather than sharing a base class with them (see
## DesertScrub's doc comment on why several similar things beats a premature
## abstraction).
##
## What is genuinely different: there is no per-cell stored cover and no
## growth. The ecology is ONE pure function (`cover_for`) of the cell's own
## inherent richness, the live tall-grass growth, and how hard it has been
## grazed lately. Keeping it pure is what lets the renderer ask for an answer
## against the CURRENT grass growth instead of this sim having to be told about
## grass every tick.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")

## Where a pasture sward grows. Grassland only for this pass: a forest herb
## layer is real and is the obvious next biome, but the species this draws
## (see ProceduralSwardSprite) are a pasture's.
const SWARD_BIOMES := {"grassland": true}

## How much of a cell the richest ungrazed, unshaded ground carries. Not 1.0:
## even the best sward is plants with soil between them, and reserving the top
## of the range for the grazing bonus is what lets a grazing lawn read as
## visibly denser than untouched ground.
const MAX_BASE_COVER := 0.7

## ...and the poorest. Above zero so bare-looking ground still carries the odd
## rosette -- a meadow with genuinely empty cells reads as a hole, which is the
## complaint this module exists to answer.
const MIN_BASE_COVER := 0.15

## How much of the base cover a fully closed tussock takes away. Not all of it:
## a rosette under grass is shaded, not dead, and it comes straight back when
## the grass is grazed off.
const SHADE_SUPPRESSION := 0.65

## How much a fully grazed cell adds back on top. Larger than SHADE_SUPPRESSION
## costs, which is the whole grazing-lawn effect: a hard-grazed cell under a
## tussock ends up carrying MORE sward than an untouched bare one. Pinned by
## test_a_grazed_tussock_beats_an_ungrazed_gap.
const GRAZING_RELEASE := 0.5

## The most rosettes one cell can show. A ceiling on instance count as much as
## an art choice -- the sward is the majority of the ground, so this multiplies
## across a whole chunk.
const MAX_PLANTS_PER_CELL := 4

## How many tall-grass spread intervals it takes for a grazed cell to close
## over again. Expressed against `TallGrass.SPREAD_INTERVAL` -- the clock on
## which the tussocks actually come back -- rather than as an eyeballed number
## of seconds, so retuning grass regrowth keeps the two in step.
const RECOVERY_SPREADS := 4.0

## Below this a cell is simply ungrazed. An exponential decay never reaches
## zero, and "not quite zero forever" would leave every cell an animal ever
## walked across permanently marked.
const GRAZED_EPSILON := 0.01

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> grazing memory (0..1). Only cells that have actually been
## grazed appear, so an untouched meadow costs nothing to store.
var _grazing: Dictionary = {}


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome


## ## The one piece of ecology
##
## How much sward a cell carries, 0..1. All three inputs are 0..1 and are
## clamped rather than trusted: `tall_grass_growth` in particular is read live
## from another simulation, and an out-of-range value must never reach
## `plant_count_for` and produce an instance count the renderer cannot honour.
static func cover_for(base: float, tall_grass_growth: float, grazing: float) -> float:
	var richness := clampf(base, 0.0, 1.0)
	var shade := clampf(tall_grass_growth, 0.0, 1.0)
	var grazed := clampf(grazing, 0.0, 1.0)
	var ground := lerpf(MIN_BASE_COVER, MAX_BASE_COVER, richness)
	var shaded := ground * (1.0 - SHADE_SUPPRESSION * shade)
	return clampf(shaded + GRAZING_RELEASE * grazed, 0.0, 1.0)


## How many rosettes that much cover draws. Cover drives how MANY plants a cell
## shows rather than how big they are: a richer patch of sward is more plants,
## not larger ones.
##
## Rounded rather than floored so the top of the range is actually reachable,
## and floored at zero so bare ground stays genuinely bare -- without a real
## zero the sward would be a uniform carpet and the shade/grazing readout would
## have nothing to read against.
static func plant_count_for(cover: float) -> int:
	return int(roundf(clampf(cover, 0.0, 1.0) * float(MAX_PLANTS_PER_CELL)))


## This cell's own inherent richness -- deterministic, from the chunk seed.
## Soil varies; a meadow is not uniform, and a sward that carried exactly the
## same density on every cell would read as a texture rather than as ground.
func base_at(cell: Vector2i) -> float:
	if not _is_sward_cell(cell):
		return 0.0
	return PixelNoise.unit(_seed_value, cell.x, cell.y)


## Live cover for a cell, given the tall grass standing on it right now.
func cover_at(cell: Vector2i, tall_grass_growth: float) -> float:
	if not _is_sward_cell(cell):
		return 0.0
	return cover_for(base_at(cell), tall_grass_growth, _grazing.get(cell, 0.0))


func plant_count_at(cell: Vector2i, tall_grass_growth: float) -> int:
	return plant_count_for(cover_at(cell, tall_grass_growth))


## A herbivore took a bite here (see EarthChunkManager.graze_grass_at, which a
## CreatureMarker reaches through _take_forage_bite).
##
## Steps toward fully grazed by a fraction of the REMAINING headroom rather
## than by a flat amount, so repeated grazing compounds -- a meadow kept under
## stock is different from one an animal wandered across once -- while never
## leaving [0,1].
func record_graze(cell: Vector2i) -> void:
	if not _is_sward_cell(cell):
		return
	var current: float = _grazing.get(cell, 0.0)
	_grazing[cell] = current + (1.0 - current) * GRAZE_FRACTION


## How much of the remaining headroom one bite takes.
const GRAZE_FRACTION := 0.5


## The tussocks come back, and the sward closes again. Exponential so it is
## frame-rate independent by construction: two half-steps land exactly where
## one whole step does, which a `value - rate * delta` ramp does not guarantee
## once it clamps at zero.
func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or _grazing.is_empty():
		return
	var half_life := TallGrass.SPREAD_INTERVAL * RECOVERY_SPREADS / 4.0
	var factor := pow(0.5, delta_seconds / half_life)
	for cell in _grazing.keys().duplicate():
		var decayed: float = _grazing[cell] * factor
		if decayed < GRAZED_EPSILON:
			_grazing.erase(cell)
		else:
			_grazing[cell] = decayed


## ## The species, and where each plant goes
##
## Four rosette-formers of a plausible Central European pasture sward. What
## they share is the one thing that matters here: a growing point pressed flat
## against the soil, which is why grazing favours them (see cover_for).
##
## Indices into this array are what `plants_for_cell` hands the renderer, and
## `ProceduralSwardSprite` paints one silhouette per entry.
const SPECIES := ["clover", "plantain", "daisy", "yarrow"]

## How far into a cell a plant's centre can sit, as a fraction. Kept off the
## very edge so a rosette drawn at MAX_PLANT_SCALE cannot visibly straddle a
## tile boundary and smear one cell's readout into its neighbour's.
const PLANT_MARGIN := 0.18

## Per-plant size jitter. A rosette is not a stamp; drawing every one at the
## same size reads as clones.
const MIN_PLANT_SCALE := 0.75
const MAX_PLANT_SCALE := 1.25


## The plants one cell shows, in UNIT space: `offset` is a fraction of the
## cell, so this is tile-size agnostic and fully testable without a renderer.
##
## Each plant is laid out on its own slice of the cell (a `count`-way split of
## the unit square's diagonal band, jittered within its slice) rather than by
## an independent roll per plant, which is what keeps two rosettes off the same
## spot -- overlapping rosettes read as one bigger plant, the opposite of what
## cover is supposed to say.
##
## Every roll is PixelNoise on the cell and the plant index. Godot's string
## `hash` correlates badly across near-identical inputs and has bitten this
## project repeatedly (village houses all one size, whole rows of leaves at one
## angle); neighbouring cells laying out identical sward would be the same bug
## in a new place.
static func plants_for_cell(cell: Vector2i, count: int, seed_value: int) -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	var wanted := clampi(count, 0, MAX_PLANTS_PER_CELL)
	if wanted <= 0:
		return plants
	var span := 1.0 - 2.0 * PLANT_MARGIN
	var slice := span / float(wanted)
	for index in wanted:
		var salt := seed_value + index * 7919
		var jitter_x := PixelNoise.unit(salt, cell.x, cell.y)
		var jitter_y := PixelNoise.unit(salt + 1, cell.x, cell.y)
		# The slice runs along X; Y is free within the whole margin band, so a
		# cell reads as scattered rather than as a row of plants.
		plants.append({
			"species": int(PixelNoise.value(salt + 2, cell.x, cell.y) % SPECIES.size()),
			"offset": Vector2(
				PLANT_MARGIN + slice * (float(index) + jitter_x),
				PLANT_MARGIN + span * jitter_y
			),
			"rotation": PixelNoise.unit(salt + 3, cell.x, cell.y) * TAU,
			"scale": lerpf(
				MIN_PLANT_SCALE, MAX_PLANT_SCALE, PixelNoise.unit(salt + 4, cell.x, cell.y)
			),
		})
	return plants


## Every plant this cell shows right now, given the tall grass standing on it.
func plants_at(cell: Vector2i, tall_grass_growth: float) -> Array[Dictionary]:
	return plants_for_cell(cell, plant_count_at(cell, tall_grass_growth), _seed_value)


func _is_sward_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _height:
		return false
	return SWARD_BIOMES.has(_biome[cell.y * _width + cell.x])
