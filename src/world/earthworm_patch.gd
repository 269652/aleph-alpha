extends RefCounted

## Per-chunk earthworm population -- the soil-invertebrate tier that robins
## hunt (see docs/concept/soil_fauna.md).
##
## Deliberately shaped like FlowerPatch/TallGrass/DesertScrub/TundraLichen --
## deterministic seeded placement, a hard per-chunk cap, advance(delta), and a
## pure bool consumption method so a caller can just try and let this decide --
## rather than sharing a base class with them (see DesertScrub's doc comment on
## why three similar things beats a premature abstraction).
##
## What is genuinely different from those: a worm is never created or destroyed
## by the weather. Earthworms are a permanent resident population of a patch of
## ground; what the weather changes is how close to the SURFACE they are. So a
## chunk gets a fixed set of BURROWS at construction, and each one animates a
## `surfacing` value between "deep in the soil" (invisible, uncatchable) and
## "at the surface" (rendered, catchable).
##
## No RandomNumberGenerator, and no Godot string hash either: all placement is
## derived from the chunk seed via PixelNoise, which (unlike `hash`)
## decorrelates neighbouring cells -- the clustering bug this project has hit
## five times.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Biomes with real organic soil. Ocean has no soil, desert no moisture, and
## tundra is permafrost -- the boreal earthworm-free zone is a real and
## well-documented thing. Mirrors AmbientFlyerRenderer.BIRD_BIOMES, so the
## birds that eat worms live exactly where the worms do.
const SOIL_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Chance a given soil cell holds a burrow. Deliberately well under
## TallGrass.SEED_CHANCE (pinned by
## test_burrows_are_sparser_than_tall_grass_patches): a lawn is not
## wall-to-wall worm casts, and every surfaced worm is a sprite.
const SEED_CHANCE := 0.02

## Hard cap per chunk. Above the ~20 a full soil chunk seeds at SEED_CHANCE,
## so it only ever binds as a safety rail.
const MAX_WORMS := 24

## How fast a worm rises, in surfacing units per second. Slow enough that
## worms visibly emerge rather than popping into existence under the sprite
## layer (pinned by test_a_worm_takes_time_to_reach_the_surface).
const SURFACE_RATE := 0.5

## How fast it withdraws. Faster than it rises: a worm retreating from drying
## soil or a shadow is a flinch, coming up is a commitment.
const BURROW_RATE := 0.8

## How far up counts as "at the surface" -- visible to the sprite layer and
## catchable by a bird.
const SURFACED_THRESHOLD := 0.6

## How long an eaten burrow stays empty before another worm occupies it.
## Without this a robin could stand on one burrow and eat the same worm
## forever; with it, a lawn is a renewable feeding territory.
const RECOVERY_SECONDS := 45.0

## Soil warmth below which worms go deep and dormant, and the warmth by which
## temperature has stopped limiting them at all. Between the two the drive
## ramps linearly.
##
## MILD_WARMTH was 0.4, which is a warmth temperate soil essentially never
## reaches: soil_warmth multiplies climate temperature by a seasonal factor,
## so the game's own spawn point (Berlin, climate 0.413) peaks at 0.413 in
## MIDSUMMER and sits at 0.254 in the spring the world starts in. The gate
## was therefore throttled year-round, and combined with SURFACED_THRESHOLD
## (0.6) the measured drive at spawn topped out at 0.48 in a storm and 0.41
## in rain -- so a worm could never surface there in ANY weather, for the
## whole early game. Reported as "I can't see any worms or birds eating
## worms"; it was not a wiring bug, the mechanic was simply gated off.
##
## Calibrated so the intended behaviour actually holds at a temperate spawn:
## rain surfaces worms from spring onward, dry weather never does, and cold
## winter ground still suppresses them. Pinned by the four
## test_..._at_the_spawn_climate / _in_spring / _in_summer / winter tests,
## which assert the BEHAVIOUR rather than these numbers -- so re-tuning
## worldgen temperature or the season curve fails there loudly instead of
## silently switching the mechanic off again.
const COLD_CUTOFF := 0.12
const MILD_WARMTH := 0.28

## How much of a chunk's baseline climate warmth survives mid-winter.
##
## SeasonCycle.warmth_modifier troughs at exactly 0.0 mid-winter, and
## EarthChunkManager._warmth_at_pixel multiplies it straight into the climate
## temperature -- correct for fruiting, where a zero ripening RATE in winter is
## exactly right. Used as a soil temperature it is not: it would put every
## biome on the planet, tropics included, under COLD_CUTOFF for a quarter of
## every year, and it is already below the cutoff at world start (spring's
## warmth modifier is only ~0.15). Winter cools the soil; it does not freeze
## the rainforest.
const WINTER_SOIL_FLOOR := 0.55

## Salt for the per-burrow reluctance sample, so how eager a worm is to
## surface is uncorrelated with whether a burrow exists at all -- the same
## independent-second-sample technique FlowerPatch uses for species choice.
const _RELUCTANCE_SALT := 7717

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> surfacing, 0..1. The KEYS are the chunk's burrows (fixed
## for the chunk's whole life); the values are how far up the worm in each one
## currently is.
var _surfacing: Dictionary = {}
## Vector2i cell -> seconds of post-predation recovery remaining. Only present
## for burrows that were recently eaten out.
var _recovery: Dictionary = {}
## The current environmental surfacing drive (see surface_drive), refreshed by
## set_conditions from the live weather and season.
var _drive := 0.0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_burrows()


func worm_cells() -> Array:
	return _surfacing.keys()


func has_burrow(cell: Vector2i) -> bool:
	return _surfacing.has(cell)


func surfacing_at(cell: Vector2i) -> float:
	return _surfacing.get(cell, 0.0)


## ## Crawling out, and back down
##
## A worm crawls out of the earth rather than appearing on top of it. The
## sprite used to be created at full size the moment the worm counted as
## surfaced and freed the moment it stopped, so worms blinked in and out of
## existence -- this model already tracked how far up a worm was, and only the
## drawing ignored it.
##
## `emergence_for` turns that into how much of the worm is above ground: none
## at the threshold, all of it when fully surfaced. Below the threshold a worm
## is still underground and shows nothing, which is the same line the gameplay
## uses -- a bird can never see a worm it cannot take.
##
## Pure and static, so the renderer can ask without holding a patch.
static func emergence_for(surfacing: float) -> float:
	if surfacing <= SURFACED_THRESHOLD:
		return 0.0
	var span := 1.0 - SURFACED_THRESHOLD
	if span <= 0.0:
		return 1.0
	return clampf((surfacing - SURFACED_THRESHOLD) / span, 0.0, 1.0)


## How far a surfaced worm crawls from its cell's centre, in world pixels,
## and how fast it works around that path. A sub-tile offset rather than a
## change of cell, deliberately: the CELL is the worm's identity everywhere
## else (worm_cells/is_surfaced/take, and a robin's own targeting), so a worm
## that changed cells mid-approach would leave the bird pecking where it used
## to be. Small and slow -- a worm creeps.
const CRAWL_RADIUS_PX := 3.0
const CRAWL_SECONDS_PER_CYCLE := 11.0


## Where a surfaced worm is right now, relative to its cell's centre. Pure
## and deterministic per (seed, elapsed): the same worm at the same moment is
## in the same place, so a reloaded chunk looks identical.
##
## Two different frequencies on the two axes, so the path is a slow open
## curve rather than a circle or a straight shuttle -- a worm probing around
## itself, not orbiting a point.
static func crawl_offset(seed_value: int, elapsed_seconds: float) -> Vector2:
	var phase := float(seed_value % 360) * 0.0174533
	var t := elapsed_seconds * TAU / CRAWL_SECONDS_PER_CYCLE
	# Limited, not just scaled per axis: two independent sines compose to a
	# vector longer than either (up to ~1.12x here), so without this the
	# worm would drift slightly further from its cell than the radius this
	# constant promises.
	return Vector2(
		sin(t + phase) * CRAWL_RADIUS_PX,
		sin(t * 0.6 + phase * 1.7) * CRAWL_RADIUS_PX * 0.5
	).limit_length(CRAWL_RADIUS_PX)


## Whether there is a worm at the surface here right now -- what the sprite
## layer draws and what a bird can actually take.
func is_surfaced(cell: Vector2i) -> bool:
	return surfacing_at(cell) >= SURFACED_THRESHOLD


## How strong the drive has to be before this particular burrow's worm comes
## up, in [0,1). This is what makes the population response GRADED rather than
## a switch: even in good conditions a fraction of worms stay down, so drizzle
## brings a few up and a downpour brings most of them.
func reluctance_at(cell: Vector2i) -> float:
	return PixelNoise.unit(_seed_value + _RELUCTANCE_SALT, cell.x, cell.y)


## How hard the environment is pushing worms toward the surface, [0,1].
##
## `moisture` is how wet the ground is (see WeatherModel.soil_moisture): wet
## soil lets a worm respire and travel above ground without desiccating, which
## is the real reason robins famously forage after rain. `warmth` is soil
## temperature (see soil_warmth): below COLD_CUTOFF worms move deep and go
## dormant however wet it is.
static func surface_drive(moisture: float, warmth: float) -> float:
	var cold_gate := clampf(
		(warmth - COLD_CUTOFF) / (MILD_WARMTH - COLD_CUTOFF), 0.0, 1.0
	)
	return clampf(clampf(moisture, 0.0, 1.0) * cold_gate, 0.0, 1.0)


## Soil temperature [0,1] from a chunk's baseline climate temperature and the
## season's warmth modifier. Seasonal swing is a partial cooling, not a
## multiplication down to zero -- see WINTER_SOIL_FLOOR for why that
## distinction matters here but not for fruiting.
static func soil_warmth(climate: float, season_warmth: float) -> float:
	var seasonal := WINTER_SOIL_FLOOR + (1.0 - WINTER_SOIL_FLOOR) * clampf(season_warmth, 0.0, 1.0)
	return clampf(climate, 0.0, 1.0) * seasonal


## Refreshes the environmental drive from the live world. Cheap enough to call
## on the chunk manager's throttled step -- weather turns over on a day scale,
## far slower than a frame.
func set_conditions(moisture: float, warmth: float) -> void:
	_drive = surface_drive(moisture, warmth)


## Moves every burrow's worm toward where the current conditions want it, and
## ages post-predation recovery.
func advance(delta: float) -> void:
	for cell in _surfacing:
		var recovering: float = _recovery.get(cell, 0.0)
		if recovering > 0.0:
			recovering -= delta
			if recovering <= 0.0:
				_recovery.erase(cell)
			else:
				_recovery[cell] = recovering
			# An emptied burrow stays empty whatever the weather is doing.
			_surfacing[cell] = maxf(0.0, float(_surfacing[cell]) - BURROW_RATE * delta)
			continue
		# Strictly greater, so a drive of exactly 0.0 (frozen ground) can never
		# hold a zero-reluctance worm at the surface.
		var target := 1.0 if _drive > reluctance_at(cell) else 0.0
		var level: float = _surfacing[cell]
		if target > level:
			_surfacing[cell] = minf(target, level + SURFACE_RATE * delta)
		else:
			_surfacing[cell] = maxf(target, level - BURROW_RATE * delta)


## Eats the worm at `cell`. Returns false when there is nothing at the surface
## there -- so a bird can just try and let this decide, the same contract as
## FlowerPatch.drink and TallGrass.graze.
func take(cell: Vector2i) -> bool:
	if not is_surfaced(cell):
		return false
	_surfacing[cell] = 0.0
	_recovery[cell] = RECOVERY_SECONDS
	return true


func _seed_initial_burrows() -> void:
	for y in _height:
		for x in _width:
			if _surfacing.size() >= MAX_WORMS:
				return
			if not SOIL_BIOMES.has(_biome[y * _width + x]):
				continue
			if PixelNoise.unit(_seed_value, x, y) >= SEED_CHANCE:
				continue
			# Worms start underground: a freshly loaded chunk shows them
			# emerging over the next second or two rather than snapping into
			# existence all at once.
			_surfacing[Vector2i(x, y)] = 0.0
