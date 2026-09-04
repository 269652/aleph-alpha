extends RefCounted

## The meadow a player walks into is what the wind already did (see
## docs/concept/flora.md#the-meadow-you-arrive-to-is-what-the-wind-already-did).
##
## The baked meadow used to be an independent coin flip per grassland cell:
## a uniform speckle at a density set by one constant. Two neighbouring cells
## both flowering was as likely as any other pair, so it produced adjacent
## pairs and triples constantly ("flowers spread or grow way too dense"), and
## it had no relationship whatever to the wind -- a world whose entire
## dispersal model is "light seed goes downwind" nevertheless STARTED
## isotropic, and only began to look windswept for a player who stood and
## watched one chunk for a long time.
##
## This runs the same kernel the live world runs (WindDispersal, same
## WEIGHT_FLOWER_SEED class the live plants shed at), from sparse founders,
## under the region's prevailing wind, through the same establishment gate
## live seed passes (FlowerEstablishment).
##
## Pure and engine-free: seeds and a biome array in, cells out.

const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WindDispersal = preload("res://src/world/wind_dispersal.gd")

## How far apart the possible founding plants are, in tiles -- the coarse
## world grid a meadow can start on. This, with FOUNDER_CHANCE and
## SEEDS_PER_PLANT, is what sets how much meadow a region has; the
## establishment gate only decides how it is arranged.
const FOUNDER_GRID_TILES := 16

## Not every grid cell founds a meadow, or the founders themselves would be a
## lattice however well jittered inside their cells.
const FOUNDER_CHANCE := 0.5

## How much seed one plant has already put on the ground by the time the
## player arrives. Small: this is not a season's shedding, it is the shape of
## a lineage, and the generations below multiply it.
const SEEDS_PER_PLANT := 3

## How many times over the lineage has shed. Two is the smallest number that
## makes this a SPREAD rather than a scatter: the offspring of a plant that
## already travelled downwind starts from further downwind again, which is
## what draws a meadow out into streaks instead of a halo round each founder.
const GENERATIONS := 2

## How far outside the chunk founders still have to be considered.
##
## Load-bearing for seams, not a fudge factor. A cell's fate depends on every
## seed that landed within MIN_SPACING_TILES of it, and such a seed can have
## come from a founder up to GENERATIONS lineage-hops away -- so any founder
## nearer than this can change what grows in this chunk, and any founder
## further away provably cannot. Together with FlowerEstablishment.survivors
## being order-independent, that makes two neighbouring chunks compute the
## identical answer for the ground they share.
const INFLUENCE_MARGIN_TILES := (
	float(GENERATIONS) * WindDispersal.MAX_TRAVEL_TILES + FlowerEstablishment.MIN_SPACING_TILES
)

## PixelNoise salts. Independent samples so "is there a founder here", "where
## exactly", "of what species" and "how vigorous is this seed" cannot
## correlate -- the single-bucket/banding failure this project has hit five
## times (see PixelNoise's own doc comment).
const _FOUNDER_SALT := 3121
const _JITTER_X_SALT := 6421
const _JITTER_Y_SALT := 9349
const _SPECIES_SALT := 12227
const _VIGOUR_SALT := 15733


## Where meadows started, in WORLD tiles, within the inclusive window
## `low`..`high`.
##
## World-space rather than chunk-space is the whole trick: a founder near a
## chunk edge seeds ACROSS the boundary, so meadows cross chunk lines instead
## of each one stopping dead at a seam. The same ground answers the same
## however the window around it is drawn.
static func founder_tiles(world_seed: int, low: Vector2i, high: Vector2i) -> Array:
	var out: Array = []
	var grid := float(FOUNDER_GRID_TILES)
	var gx0 := floori(float(low.x) / grid)
	var gx1 := floori(float(high.x) / grid)
	var gy0 := floori(float(low.y) / grid)
	var gy1 := floori(float(high.y) / grid)
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			if PixelNoise.unit(world_seed + _FOUNDER_SALT, gx, gy) >= FOUNDER_CHANCE:
				continue
			# Jittered anywhere inside its own grid cell, so the founding
			# population is not itself a visible lattice.
			var tile := Vector2i(
				gx * FOUNDER_GRID_TILES
				+ PixelNoise.range_index(world_seed + _JITTER_X_SALT, gx, gy, FOUNDER_GRID_TILES),
				gy * FOUNDER_GRID_TILES
				+ PixelNoise.range_index(world_seed + _JITTER_Y_SALT, gx, gy, FOUNDER_GRID_TILES)
			)
			if tile.x < low.x or tile.x > high.x or tile.y < low.y or tile.y > high.y:
				continue
			out.append(tile)
	return out


## The baked meadow for one chunk: chunk-LOCAL Vector2i cell -> species id.
##
## `origin_tiles` is the chunk's global tile origin, `biome` its own
## width*height biome array, `wind_direction`/`wind_strength` the region's
## PREVAILING wind (see WeatherModel.prevailing_wind_direction) -- the long-run
## wind the landscape was shaped by, not one particular day's.
static func colonise(
	world_seed: int,
	origin_tiles: Vector2i,
	width: int,
	height: int,
	biome: PackedStringArray,
	wind_direction: Vector2,
	wind_strength: float,
	max_flowers: int
) -> Dictionary:
	var direction := (
		wind_direction.normalized() if wind_direction.length() > 0.0 else Vector2.RIGHT
	)
	var strength := clampf(wind_strength, 0.0, 1.0)
	var margin := ceili(INFLUENCE_MARGIN_TILES)
	var founders := founder_tiles(
		world_seed,
		origin_tiles - Vector2i(margin, margin),
		origin_tiles + Vector2i(width + margin, height + margin)
	)

	# Every founder's whole seed rain, shed unconditionally. Deliberately NOT
	# gated generation by generation: a plant's lineage then depends only on
	# itself and the wind, which is what bounds INFLUENCE_MARGIN_TILES above
	# and lets neighbouring chunks agree exactly. Which of the rain actually
	# becomes a plant is the establishment gate's business, below, and it is
	# a separate question by design (see FlowerEstablishment).
	var rain: Array = []
	for founder in founders:
		# One species per lineage: the seed of a rose is a rose. It also means
		# a meadow comes in species-clumped patches rather than every bloom
		# being an independent roll, which is what a real one looks like.
		var species: String = FlowerSpecies.IDS[PixelNoise.range_index(
			world_seed + _SPECIES_SALT, founder.x, founder.y, FlowerSpecies.IDS.size()
		)]
		rain.append_array(lineage(founder, species, world_seed, direction, strength))

	var meadow := {}
	for grain in FlowerEstablishment.survivors(rain):
		if meadow.size() >= max_flowers:
			break
		var local: Vector2i = grain["cell"] - origin_tiles
		if local.x < 0 or local.x >= width or local.y < 0 or local.y >= height:
			continue  # established, but in a neighbouring chunk's ground
		# Flowers are meadow plants: seed that lands in the sea or on bare
		# rock is simply lost, which is itself a real check on spread.
		if biome[local.y * width + local.x] != "grassland":
			continue
		meadow[local] = grain["species"]
	return meadow


## One founder's whole seed rain: the founder itself, then GENERATIONS rounds
## of shedding, every grain carrying the founder's species.
##
## Shed UNCONDITIONALLY -- a grain sheds whether or not it would have
## established. That is deliberate, and it is what bounds
## INFLUENCE_MARGIN_TILES: a lineage then depends only on its founder and the
## wind, on nothing any other founder did, so two neighbouring chunks compute
## the identical rain for the ground they share. What this models is the SEED
## RAIN; which of it becomes a plant is a separate question that
## FlowerEstablishment answers over the whole rain at once.
static func lineage(
	founder: Vector2i, species: String, world_seed: int, direction: Vector2, strength: float
) -> Array:
	var rain: Array = [_grain(founder, species, world_seed + founder.x * 31 + founder.y * 37)]
	var wave: Array[Vector2i] = [founder]
	for generation in GENERATIONS:
		var next: Array[Vector2i] = []
		for parent in wave:
			for i in SEEDS_PER_PLANT:
				# Distinct primes per input so a parent's own seeds, and two
				# neighbouring parents' seeds, cannot collide into one landing.
				var grain_seed: int = (
					world_seed
					+ parent.x * 8887
					+ parent.y * 2503
					+ i * 131
					+ generation * 7919
				)
				var landing := WindDispersal.landing_offset(
					grain_seed, WindDispersal.WEIGHT_FLOWER_SEED, direction, strength
				) / float(TerrainRenderer.TILE_SIZE)
				var tile := parent + Vector2i(roundi(landing.x), roundi(landing.y))
				next.append(tile)
				rain.append(_grain(tile, species, grain_seed))
		wave = next
	return rain


## One grain of the seed rain, in the shape FlowerEstablishment.survivors
## wants. `rank` is the seed's own vigour, derived from the seed's identity
## rather than from where it happens to sit in the list -- that is what makes
## the gate order-independent, and therefore what makes chunk seams invisible.
static func _grain(tile: Vector2i, species: String, grain_seed: int) -> Dictionary:
	return {
		"cell": tile,
		"species": species,
		"rank": PixelNoise.value(grain_seed + _VIGOUR_SALT, tile.x, tile.y),
	}
