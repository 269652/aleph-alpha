extends RefCounted

## Which cells of a cave-bearing layer are natural VOID -- the passage
## geometry itself (see docs/concept/underground.md "The cave network and
## Strata.KIND_VOID").
##
## Two things make this different from the coordinate-hash density rolls
## StonePlacement/Strata use for scattered objects:
##
## 1. A cave is CONNECTED. A per-cell density roll produces a scatter of
##    unreachable pockets, which is not a cave. Every conduit pattern here
##    is built from a continuous field instead -- a level set of a smooth
##    2D field is a curve, so its passages join by construction.
## 2. The void fraction is not a tuning knob. It is DERIVED from real cave
##    surveys: a pattern's measured passage density times its real mean
##    passage width. The generator's threshold is then calibrated to
##    reproduce that number (see _threshold_for), so the survey is the
##    spec and the threshold is only how the field is made to hit it.

const CavePattern = preload("res://src/world/cave_pattern.gd")

const CAVE_PATTERNS: Array[String] = [
	CavePattern.PATTERN_BRANCHWORK,
	CavePattern.PATTERN_NETWORK_MAZE,
	CavePattern.PATTERN_ANASTOMOTIC,
	CavePattern.PATTERN_RAMIFORM,
	CavePattern.PATTERN_SPONGEWORK,
]

## A tile at PLAY scale, from the player's own real height:
## TerrainRenderer.TILE_SIZE / GroundSlide.PX_PER_METER. Restated here
## rather than preloaded (a pure generator should not pull in the renderer)
## and pinned by test_metres_per_tile_agrees_with_the_world_scale.
##
## Note this is the play-scale tile, not EarthChunkGenerator's ~1km map
## tile -- the project's existing, deliberate scale fiction (see that
## file's own "Minecraft-like scale" note). Cave passages are metres wide,
## so the underground can only be built at play scale.
const METRES_PER_TILE := 1.426

## Surveyed passage density, km of passage per km^2 of cave footprint.
##
## - branchwork: Mammoth Cave, ~676km of passage across roughly 150km^2.
## - network_maze: Optymistychna (gypsum), ~257km within roughly 2km^2 --
##   the densest real cave pattern there is, and why a maze plays as open
##   space where a branchwork plays as a thread.
## - ramiform: Lechuguilla, ~240km within roughly 13km^2.
## - anastomotic: a branchwork conduit braided into parallel anastomosing
##   tubes. Real anastomotic zones run 2-5 tubes where a branchwork has
##   one, so this is branchwork's own density times BRAID_TUBE_COUNT
##   rather than an independent figure.
## - spongework: the least-anchored of the five. Flank-margin caves are
##   chamber-dominated with little integrated passage, so this sits below
##   ramiform; it is not taken from a single named survey the way the
##   others are. Flagged as such in underground.md's Status.
const BRAID_TUBE_COUNT := 4.0
const BRANCHWORK_DENSITY_KM_PER_KM2 := 4.5

const PASSAGE_DENSITY_KM_PER_KM2 := {
	CavePattern.PATTERN_BRANCHWORK: BRANCHWORK_DENSITY_KM_PER_KM2,
	CavePattern.PATTERN_NETWORK_MAZE: 128.0,
	CavePattern.PATTERN_ANASTOMOTIC: BRANCHWORK_DENSITY_KM_PER_KM2 * BRAID_TUBE_COUNT,
	CavePattern.PATTERN_RAMIFORM: 18.5,
	CavePattern.PATTERN_SPONGEWORK: 6.0,
}

## Real mean passage width. Stream conduits are metres across; hypogenic
## and flank-margin caves are ROOMS -- Carlsbad's Big Room is 190m wide --
## so their mean is far higher even though their passage length is not.
const CONDUIT_WIDTH_M := 3.0
const CHAMBER_WIDTH_M := 8.0

const MEAN_PASSAGE_WIDTH_M := {
	CavePattern.PATTERN_BRANCHWORK: CONDUIT_WIDTH_M,
	CavePattern.PATTERN_NETWORK_MAZE: CONDUIT_WIDTH_M,
	CavePattern.PATTERN_ANASTOMOTIC: CONDUIT_WIDTH_M,
	CavePattern.PATTERN_RAMIFORM: CHAMBER_WIDTH_M,
	CavePattern.PATTERN_SPONGEWORK: CHAMBER_WIDTH_M,
}

## How the field is shaped for each pattern. All five ask the same
## question ("how void-prone is this cell") of a differently-built field,
## the same one-class-differently-parameterised shape Strata already uses
## for its four layers.
##
## - LEVEL_SET: void near a contour of a smooth field. Contours of a
##   continuous 2D field are curves, so the passages join -- this is what
##   makes branchwork and anastomotic real conduit systems rather than
##   scatter.
## - JOINTS: void near a line of either of two near-orthogonal joint sets.
##   Two intersecting line families always cross, so the grid is connected.
## - BLOBS: void where a smooth field is high. Produces rooms/cavities;
##   at low frequency those rooms are large, at high frequency they are
##   many and isolated.
const SHAPE_LEVEL_SET := "level_set"
const SHAPE_JOINTS := "joints"
const SHAPE_BLOBS := "blobs"

const FIELD_SHAPE := {
	CavePattern.PATTERN_BRANCHWORK: SHAPE_LEVEL_SET,
	CavePattern.PATTERN_ANASTOMOTIC: SHAPE_LEVEL_SET,
	CavePattern.PATTERN_NETWORK_MAZE: SHAPE_JOINTS,
	CavePattern.PATTERN_RAMIFORM: SHAPE_BLOBS,
	CavePattern.PATTERN_SPONGEWORK: SHAPE_BLOBS,
}

## Real joint sets in bedded rock are near-orthogonal. Offset from the
## axes so a maze does not read as a drawn grid.
const JOINT_SET_A_DEGREES := 20.0
const JOINT_SET_B_DEGREES := 110.0

## Samples used to calibrate a pattern's threshold, strided so they span
## many passage-spacings rather than one -- a smooth field sampled over a
## single wavelength says nothing about its own distribution.
const CALIBRATION_SAMPLES := 96
const CALIBRATION_STRIDE := 17

var _noise_cache: Dictionary = {}
var _frequency_cache: Dictionary = {}
var _threshold_cache: Dictionary = {}


## The fraction of a cave-bearing region's cells that are open passage,
## derived from that pattern's own survey numbers: km of passage per km^2
## times metres of width, over 1000 m/km. Zero for a pattern with no cave.
func porosity_of(pattern: String) -> float:
	if not CAVE_PATTERNS.has(pattern):
		return 0.0
	var density: float = PASSAGE_DENSITY_KM_PER_KM2[pattern]
	var width_m: float = MEAN_PASSAGE_WIDTH_M[pattern]
	return density * width_m / 1000.0


## Characteristic spacing between neighbouring passages, in metres,
## derived from the survey numbers rather than chosen -- and derived
## DIFFERENTLY per shape, because the three geometries are not the same
## shape of object:
##
## - A conduit system is lines. D km of passage per km^2 laid out as
##   parallel lines spacing s apart gives D = 1000/s, so s = 1000/D.
## - A joint maze is two such families, both contributing to the same
##   measured density, hence the doubling.
## - Spongework and ramiform are CAVITIES, not lines, so line spacing does
##   not apply at all. A cavity of width w packed on a lattice of spacing
##   s covers (pi/4)(w/s)^2 of the area, so hitting porosity p needs
##   s = w * sqrt(pi / (4p)). Using the line formula here was a real bug:
##   it put spongework's cavities 167m apart, which at its porosity meant
##   a few enormous merged blobs carrying a through-route -- the one thing
##   spongework is defined by NOT having.
func passage_spacing_m(pattern: String) -> float:
	var density: float = PASSAGE_DENSITY_KM_PER_KM2.get(pattern, 0.0)
	if density <= 0.0:
		return 0.0
	var shape: String = FIELD_SHAPE.get(pattern, "")
	if shape == SHAPE_BLOBS:
		var width_m: float = MEAN_PASSAGE_WIDTH_M[pattern]
		return width_m * sqrt(PI / (4.0 * porosity_of(pattern)))
	var families := 2.0 if shape == SHAPE_JOINTS else 1.0
	return families * 1000.0 / density


## Half-width, in tiles, of a conduit in a level-set pattern -- which is
## exactly what this pattern's calibrated threshold means once the field
## is a distance (see _field_at's SHAPE_LEVEL_SET branch).
##
## Worth having as more than a debug accessor: the threshold is calibrated
## against the surveyed POROSITY alone and knows nothing about passage
## width, so if the width it independently produces matches the surveyed
## mean passage width, two unrelated survey numbers have agreed. That is a
## real check on the model rather than a restatement of its input.
func conduit_half_width_tiles(pattern: String) -> float:
	if FIELD_SHAPE.get(pattern, "") != SHAPE_LEVEL_SET:
		return 0.0
	return -_threshold_for(pattern)


## Whether this cell is natural cave void. False everywhere for a pattern
## with no cave (including PATTERN_NONE and any unknown pattern), which is
## the honest majority answer on a planet whose bedrock is mostly
## insoluble.
func is_void_at(pattern: String, global_x: int, global_y: int) -> bool:
	if not CAVE_PATTERNS.has(pattern):
		return false
	return _field_at(pattern, global_x, global_y) >= _threshold_for(pattern)


## How void-prone this cell is; higher is more void-prone. Shape-specific,
## unitless, and only ever compared against this pattern's own calibrated
## threshold -- never against another pattern's.
func _field_at(pattern: String, global_x: int, global_y: int) -> float:
	return _field_value(pattern, _noise_for(pattern), global_x, global_y)


## _field_at against an EXPLICIT noise instance, so the frequency
## calibration below can measure a probe field without recursing through
## the very cache it is trying to fill.
func _field_value(pattern: String, noise: FastNoiseLite, global_x: int, global_y: int) -> float:
	var spacing_tiles: float = maxf(passage_spacing_m(pattern) / METRES_PER_TILE, 1.0)
	match FIELD_SHAPE[pattern]:
		SHAPE_JOINTS:
			var half_spacing := spacing_tiles
			var a := _distance_to_joint_set(global_x, global_y, JOINT_SET_A_DEGREES, half_spacing)
			var b := _distance_to_joint_set(global_x, global_y, JOINT_SET_B_DEGREES, half_spacing)
			return -minf(a, b)
		SHAPE_LEVEL_SET:
			# Approximate DISTANCE IN TILES to the field's zero contour,
			# negated so nearer reads as more void-prone.
			#
			# Banding on the raw value |f| < t instead was a real bug, not
			# a simplification: a value band's width in tiles is t/|grad f|,
			# and a noise field's gradient varies enormously between its
			# steep flanks and its saddles. The band therefore pinched to
			# well under a tile along every steep stretch and the conduit
			# came out as a dotted line -- 25% of its cells in the largest
			# connected component instead of one continuous passage.
			# Dividing by the local gradient is the standard implicit-
			# surface distance approximation and makes the ribbon a
			# genuinely constant width, which is what a conduit is.
			var value := noise.get_noise_2d(global_x, global_y)
			var d_dx := (
				noise.get_noise_2d(global_x + 1, global_y)
				- noise.get_noise_2d(global_x - 1, global_y)
			) * 0.5
			var d_dy := (
				noise.get_noise_2d(global_x, global_y + 1)
				- noise.get_noise_2d(global_x, global_y - 1)
			) * 0.5
			var gradient := sqrt(d_dx * d_dx + d_dy * d_dy)
			if gradient <= 0.0:
				return -INF
			return -absf(value) / gradient
		_:
			return noise.get_noise_2d(global_x, global_y)


## Distance from this point to the nearest line of a family of parallel
## lines at `degrees`, spaced `spacing` apart.
func _distance_to_joint_set(global_x: int, global_y: int, degrees: float, spacing: float) -> float:
	var normal := deg_to_rad(degrees + 90.0)
	var along_normal := float(global_x) * cos(normal) + float(global_y) * sin(normal)
	var offset := along_normal / spacing
	return absf(offset - round(offset)) * spacing


func _build_noise(pattern: String, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Single octave, deliberately. FastNoiseLite defaults to 5-octave FBM,
	# whose highest octave carries detail 16x finer than the passage
	# spacing -- fine enough to chop a conduit band only a couple of tiles
	# wide into disconnected dots. A conduit that does not join is not a
	# conduit, so the fractal detail costs more than it buys here.
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.seed = hash("cave_network_%s" % pattern)
	noise.frequency = frequency
	return noise


## The field frequency for a pattern.
##
## The naive choice -- one cycle per surveyed passage spacing -- satisfies
## only ONE of the two survey numbers. Porosity is pinned by the threshold
## (see _threshold_for), so whatever contour length the field happens to
## produce, the conduits are squeezed or widened to hit that porosity: at
## one cycle per spacing the field lays down about 2.5x more contour than
## the surveyed passage density, and the conduits came out 0.42 tiles
## half-wide against a surveyed 1.05.
##
## So the frequency is calibrated instead. For a band of half-width h
## around contours of total length L per unit area, porosity p = 2hL, and
## L is proportional to frequency -- so h is inversely proportional to it.
## Measuring h once at a reference frequency therefore gives the exact
## scaling needed, in a single step, to land on the surveyed width while
## the threshold independently holds the surveyed porosity. Both numbers
## are then load-bearing, and the two agreeing is a real check on the
## model rather than a restatement of its input.
func _frequency_for(pattern: String) -> float:
	if _frequency_cache.has(pattern):
		return _frequency_cache[pattern]
	var spacing_tiles: float = maxf(passage_spacing_m(pattern) / METRES_PER_TILE, 1.0)
	var frequency := 1.0 / spacing_tiles
	if FIELD_SHAPE.get(pattern, "") == SHAPE_LEVEL_SET:
		var probe := _build_noise(pattern, frequency)
		var produced_half_width := -_quantile_threshold(pattern, probe)
		var surveyed_half_width: float = (
			MEAN_PASSAGE_WIDTH_M[pattern] / 2.0 / METRES_PER_TILE
		)
		if produced_half_width > 0.0 and surveyed_half_width > 0.0:
			frequency *= produced_half_width / surveyed_half_width
	_frequency_cache[pattern] = frequency
	return frequency


func _noise_for(pattern: String) -> FastNoiseLite:
	if _noise_cache.has(pattern):
		return _noise_cache[pattern]
	var noise := _build_noise(pattern, _frequency_for(pattern))
	_noise_cache[pattern] = noise
	return noise


## The field value above which a cell is void, chosen so that exactly
## porosity_of(pattern) of cells clear it. Calibrated by sampling the
## field's own distribution rather than solved analytically, because the
## answer depends on the noise's distribution as well as the threshold --
## which is exactly the sort of number CLAUDE.md forbids eyeballing.
func _threshold_for(pattern: String) -> float:
	if _threshold_cache.has(pattern):
		return _threshold_cache[pattern]
	var threshold := _quantile_threshold(pattern, _noise_for(pattern))
	_threshold_cache[pattern] = threshold
	return threshold


## The quantile of `noise`'s own field distribution that leaves exactly
## porosity_of(pattern) of cells above it.
func _quantile_threshold(pattern: String, noise: FastNoiseLite) -> float:
	var values: Array[float] = []
	for iy in CALIBRATION_SAMPLES:
		for ix in CALIBRATION_SAMPLES:
			values.append(
				_field_value(pattern, noise, ix * CALIBRATION_STRIDE, iy * CALIBRATION_STRIDE)
			)
	values.sort()
	var porosity := porosity_of(pattern)
	var index := int(floor(float(values.size()) * (1.0 - porosity)))
	index = clampi(index, 0, values.size() - 1)
	return values[index]
