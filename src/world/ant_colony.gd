extends RefCounted

## Per-chunk ant colony population -- the myrmecochory (seed-harvesting)
## soil-invertebrate tier named in docs/concept/soil_fauna.md's "other soil
## fauna" open item, now closed for ants.
##
## Deliberately shaped like EarthwormPatch/FlowerPatch/TallGrass/DesertScrub/
## TundraLichen -- deterministic PixelNoise-seeded placement, a hard
## per-chunk cap, advance(delta) -- rather than sharing a base class with
## them (see DesertScrub's doc comment on why three similar things beats a
## premature abstraction).
##
## What is genuinely different from EarthwormPatch: a mound is a whole
## COLONY, not a single animal, and this pass gives it no rendered or eaten
## state at all (see "explicitly out of scope" in the soil_fauna.md doc) --
## only a place, and a small deterministic per-step chance that the colony
## sends a forager out to check the ground near its mound for a fallen grass
## seed (grassland) or a fallen windfall fruit/nut (forest/rainforest, see
## WINDFALL_CONSUMED_CHANCE below). There is no surfacing/weather machinery:
## ants are not driven by soil moisture the way earthworms are, and giving
## them one here would be unjustified plumbing for a behaviour this pass
## doesn't need.
##
## No RandomNumberGenerator, and no Godot string hash either for anything
## PER-CELL: all placement and per-step rolls are derived from the chunk seed
## via PixelNoise, which (unlike `hash`) decorrelates neighbouring cells and
## neighbouring steps -- the clustering bug this project has hit five times.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const AntPopulationModel = preload("res://src/world/ant_population_model.gd")
const PheromoneField = preload("res://src/world/pheromone_field.gd")

## Biomes with real organic soil an ant can excavate -- the same set
## EarthwormPatch uses, and for the same reasons (ocean has no soil, desert
## soil is too loose and dry, tundra is permafrost). Ants are NOT restricted
## to grassland in the real world (leafcutter and army ants are a defining
## feature of rainforest, for instance), so mounds are seeded across all
## three. What USED TO BE scoped to grassland alone was what a mound could
## actually forage: TallGrass, the only source of ground SEED in this game,
## only grows in grassland (see TallGrass._seed_initial_patches). A forest/
## rainforest mound now has a second forage target instead of sitting idle:
## a nearby fallen windfall fruit/nut ground item (the same
## EarthChunkManager.fruit_near/take_fruit_at API SquirrelNutCaching already
## uses), gated to real NUTS (TreeSpecies.is_nut) the same way
## SquirrelNutCaching gates its own pickup. See WINDFALL_CONSUMED_CHANCE's
## own doc comment for why this is a far more consumption-dominant case than
## the grass-seed myrmecochory above -- a single forager ant cannot carry off
## an intact nut/dried-fruit propagule the way a squirrel or bird can.
const SOIL_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Chance a given soil cell holds a mound. Real ant nest density per unit
## area is typically HIGHER than earthworm burrow density in the same soil
## (a hectare of temperate grassland commonly holds many dozens of nests
## across several species, against a much sparser scatter of worm burrows),
## so this sits above EarthwormPatch.SEED_CHANCE -- pinned as an ordering by
## test_mounds_are_denser_than_earthworm_burrows, not just asserted here.
## Still far under TallGrass.SEED_CHANCE: a mound is a whole colony's single
## entrance, not a blade of grass.
const MOUND_CHANCE := 0.05

## Hard cap per chunk. Deliberately LOWER than EarthwormPatch.MAX_WORMS (24)
## despite the higher per-cell chance above: one mound represents an entire
## colony ranging out over many tiles, not one individual the way a single
## worm is one worm, so far fewer of them are needed to represent a chunk's
## ground as "actively foraged." Above the ~50 a full soil chunk seeds at
## MOUND_CHANCE, so in practice it is what actually governs the count.
const MAX_MOUNDS := 10

## Chance, per call to advance(), that a given mound's colony sends a
## forager out to check the ground near it this step. A caller (see
## EarthChunkManager.step_ants) is expected to call advance() many times a
## second under normal play, the same cadence step_worms runs at -- so
## anything close to 1.0 would empty every seed within the first second of a
## chunk loading. Kept small so foraging reads as ongoing background
## activity, the same reasoning EarthwormPatch's SURFACE_RATE/BURROW_RATE
## comments give for why THEIR numbers are small. Pinned in range by
## test_forage_chance_is_small, and its actual foraging-in-the-flesh effect
## (a seed gets taken eventually, not every single call) is pinned by
## test_forage_roll_spreads_across_true_and_false.
const FORAGE_CHANCE := 0.05

## How close a fallen grass seed has to be to a mound for its colony to
## notice it, in tiles. SHORTER than SeedCaching.PICKUP_RADIUS_TILES (3.0,
## a foraging mouse's own noticing range): an ant's foraging range from its
## mound entrance is far smaller than a mouse's whole home range. Pinned by
## test_ant_forage_radius_is_shorter_than_rodent_pickup_radius, which only
## requires staying under 3.0 -- this specific value is otherwise a real
## design knob, not itself test-locked.
##
## 1.0 -> 2.0 (2026-09-05, "thriving ant colonies"): the concept doc's own
## "Pheromone trails" section already documented this exact doubling --
## "which matters here specifically because it is what makes more than one
## candidate food item plausible within reach at once" -- but the actual
## constant was never changed when that section shipped (confirmed via
## git history: FORAGE_RADIUS_TILES has been 1.0 in every commit since its
## introduction). At 1.0 tile, real dispatches were rare enough to catch by
## chance that docs/progress.md's own investigation of "ants don't carry
## anything" left it explicitly unresolved rather than loosen it without
## confirming the tradeoff -- this pass is that confirmation.
const FORAGE_RADIUS_TILES := 2.0

## How far a mound caches a harvested seed before it counts as planted, in
## tiles. This is the shortest-range disperser of the game's whole carrier
## family, and deliberately so, in order:
##   1. SeedDispersal (grazer epizoochory, coat-carried): 3.0 .. 14.0 tiles.
##   2. SeedEndozoochory (bird gut-passage, carried in flight): 10 .. 40.
##   3. SeedCaching (mouse scatter-hoard, carried on foot): 1.0 .. 6.0.
##   4. This (ant myrmecochory, carried by a single worker): shortest of all.
## Real myrmecochory moves a seed only centimetres to a couple of metres --
## the shortest-range seed dispersal mechanism that exists in nature, well
## under even a mouse's tiny cache range. Pinned below SeedCaching's own
## CARRY_MIN_TILES (not just its max) by
## test_ant_carry_range_is_shorter_than_rodent_carry_range, mirroring how
## SeedCaching itself is pinned below SeedDispersal/SeedEndozoochory in
## test_seed_caching.gd.
const CARRY_MIN_TILES := 0.15
const CARRY_MAX_TILES := 0.9

## Salt for the per-step foraging roll and the carrier-seed sample, so
## "does this mound forage this step" and "where does it cache the seed" are
## independent draws -- the same independent-second-sample technique
## EarthwormPatch's _RELUCTANCE_SALT uses to keep placement and reluctance
## from correlating.
const _FORAGE_SALT := 419
const _CARRY_SALT := 6131

## Salt for the initial-population seed roll (see _seed_initial_mounds) --
## independent of every other per-mound roll above for the same reason
## they're independent of each other: "how established is this colony
## already" must not correlate with "does it forage this exact step" or
## "where does it cache."
const _POPULATION_SALT := 88301

## Fraction of a windfall fruit/nut find a mound's forager consumes outright
## on the spot rather than surviving to be cached as a new sapling
## (see windfall_is_consumed). Its own constant, deliberately NOT a reuse of
## SquirrelNutCaching.NUT_CONSUMED_CHANCE (0.7) or SeedEndozoochory.
## GRANIVORY_CONSUMED_CHANCE (0.8): both of those model an animal that can
## physically carry the WHOLE propagule away intact (a squirrel in its
## mouth, a bird's whole gut) and only sometimes destroys it. A single
## forager ant cannot do that at all -- it cannot carry off an intact nut or
## dried fruit. Real ants interacting with fallen fruit/nut debris are
## documented almost entirely as scavengers/decomposers, stripping and
## consuming soft pulp/residue in place rather than dispersing the hard
## propagule itself; true myrmecochory in nature is specific to small,
## elaiosome-bearing seeds -- exactly the ground-seed case this file already
## models via FORAGE_CHANCE/CARRY_MIN_TILES/CARRY_MAX_TILES above. A fallen
## tree nut is a genuinely different, far more consumption-dominant case for
## this disperser, so this sits ABOVE both existing consumed-chance
## constants -- ants are the LEAST effective disperser of a large propagule
## of any forager in this game. Pinned by
## test_windfall_consumed_chance_is_higher_than_squirrel_and_sparrow. Never
## 1.0 though -- never say never, the same pattern every other
## consumed-vs-cached mechanic in this game follows -- a real, nonzero
## minority still gets carried the short CARRY_MIN_TILES..CARRY_MAX_TILES
## distance above and counts as planted, pinned by
## test_windfall_is_consumed_mostly_true_but_leaves_a_real_minority_cached.
const WINDFALL_CONSUMED_CHANCE := 0.93

## Salt for the windfall consumed-vs-cached roll (see windfall_carrier_seed_for/
## windfall_is_consumed), independent of both _FORAGE_SALT (does this mound
## forage this step) and _CARRY_SALT (where a harvested item gets cached) --
## the same independent-second-sample technique those two use to keep
## separate per-mound-per-step rolls from correlating with each other.
const _WINDFALL_SALT := 27457

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> true. The mounds a chunk seeds at construction; fixed for
## the chunk's whole life, exactly like EarthwormPatch's burrows.
var _mounds: Dictionary = {}

## How many times advance() has been called. The only per-tick state a
## mound needs THIS ROLL -- there is no surfacing value to animate and
## nothing here changes over real seconds, so a discrete step counter (not
## elapsed_seconds) is genuinely all that drives the per-step foraging roll
## and the carrier-seed sample below. (advance()'s `delta` now DOES have a
## real use elsewhere -- see SECONDS_PER_SIMULATED_DAY below -- just not
## for this particular roll.)
var _step_count: int = 0

## Real seconds of elapsed play time per simulated ecosystem day --
## mirrors EarthChunkManager.SECONDS_PER_SIMULATED_DAY's own VALUE (60),
## restated here rather than imported: EarthChunkManager already preloads
## AntColony, so the reverse import would be circular. Cross-checked by
## test_seconds_per_simulated_day_matches_earth_chunk_managers_own_constant
## so the two cannot silently drift apart. See "A queen, and where a
## colony's size comes from" in docs/concept/soil_fauna.md.
const SECONDS_PER_SIMULATED_DAY := 60.0

## Per-mound colony population (see AntPopulationModel) -- Vector2i cell ->
## float, defaulting to AntPopulationModel.STARTING_POPULATION for a mound
## never yet advanced.
var _population: Dictionary = {}

## Per-mound exponential moving average of recent forage outcomes, in
## [0, 1] -- 0 a colony that keeps coming home empty, 1 one that keeps
## finding food. Feeds capacity_at (see AntPopulationModel.capacity). Not
## present at all for a mound record_forage_result has never been called
## on, which capacity_at reads as 0.0 (the unfed baseline), same as a
## freshly-seeded colony with no track record yet.
var _forage_success: Dictionary = {}

## How much weight a single forage outcome carries in the EMA above --
## e.g. 0.3 means one result moves the average 30% of the way toward 1.0
## (success) or 0.0 (failure). Neither so twitchy that one lucky/unlucky
## roll swings capacity wildly, nor so sluggish that a colony's fortunes
## genuinely changing (a local food patch exhausted) takes dozens of
## attempts to register at all.
const FORAGE_SUCCESS_EMA_RATE := 0.3

## Per-mound exponential moving average of recent soil moisture, in
## [0, 1] -- see docs/concept/soil_fauna.md "Water, not just food: a
## second real growth driver". Fed by EarthChunkManager.step_ants via
## record_moisture, sampled from WeatherModel.soil_moisture the identical
## way EarthwormPatch.set_conditions already reads it. Not present at all
## for a mound record_moisture has never been called on, which
## capacity_at reads as 0.0 (parched), same fallback shape
## _forage_success already uses.
var _moisture: Dictionary = {}

## Same weight as FORAGE_SUCCESS_EMA_RATE -- a single moisture sample is
## exactly as consequential as a single forage outcome, matching
## AntPopulationModel.WATER_CAPACITY_BONUS being pinned equal to
## FOOD_CAPACITY_BONUS: neither signal is structurally twitchier or
## sluggisher than the other.
const MOISTURE_EMA_RATE := FORAGE_SUCCESS_EMA_RATE

var _population_model := AntPopulationModel.new()

## Per-mound trail pheromone (see PheromoneField) -- Vector2i cell ->
## PheromoneField, created lazily on first deposit so a mound that never
## successfully forages never allocates one. Different mounds are
## different colonies; each owns its own field so one colony's trail can
## never bleed into another's.
var _pheromones: Dictionary = {}

## How many foragers a mound may have concurrently active -- scales with
## its own population, the same "aggregate population promotes to visible
## individual markers" shape FishRenderer.target_count already uses for
## fish (see active_forager_cap_at).
##
## 3 -> 6 (2026-09-05, "real swarm intelligence and thriving ant
## colonies," requested directly after a live report of plentiful mounds
## and almost no visible ants): 3 was deliberately "a special sight, not a
## swarm" -- exactly the framing this request asks to change. A cap alone
## was never the whole story, though (see _seed_initial_mounds' own doc
## comment on the population floor this pass also raises) -- the pheromone
## trail's own recruitment (PheromoneField.best_candidate_index, biasing
## EVERY concurrently-dispatched forager toward the same known-good
## source) was already correct swarm behaviour, just invisible with at
## most one worker ever out to show it. Raising the cap is what lets that
## existing mechanism actually read as a swarm converging on a rich find,
## not new behaviour.
const MAX_CONCURRENT_FORAGERS := 6


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_mounds()


func mound_cells() -> Array:
	return _mounds.keys()


func has_mound(cell: Vector2i) -> bool:
	return _mounds.has(cell)


## Advances the colony's own step count (see _step_count), decays every
## mound's pheromone trail by real elapsed time, and grows/stalls every
## mound's own population toward its current capacity (see AntPopulationModel).
## `delta_seconds` FINALLY has a real use here beyond matching the shared
## patch-sim advance(delta) shape every other per-chunk sim in this project
## follows -- it used to be ignored outright ("ants have no ...
## value to animate over real seconds"), true only of the step counter,
## not of the two real-time mechanisms this pass adds.
func advance(delta_seconds: float) -> void:
	_step_count += 1
	for field in _pheromones.values():
		field.decay(delta_seconds)
	var delta_days := delta_seconds / SECONDS_PER_SIMULATED_DAY
	for cell in _mounds:
		_population[cell] = _population_model.step(population_at(cell), capacity_at(cell), delta_days)


## Whether this mound's colony sends a forager out to check for a nearby
## seed THIS step. A pure, PixelNoise-seeded roll against the mound's own
## position and the colony's current step -- never Godot's string hash,
## which correlates neighbouring inputs instead of spreading them.
func should_forage(cell: Vector2i) -> bool:
	return PixelNoise.unit(
		_seed_value + _step_count + _FORAGE_SALT, cell.x, cell.y
	) < FORAGE_CHANCE


## A deterministic seed for "the carry this mound's forager makes right now",
## derived from the mound's own position and the colony's current step so a
## reloaded chunk at the same step caches identically, and different mounds
## (or the same mound at a different step) don't collide on the same offset.
## Feed this into carry_distance_tiles/carry_direction to place the cache.
func carrier_seed_for(cell: Vector2i) -> int:
	return PixelNoise.value(_seed_value + _step_count + _CARRY_SALT, cell.x, cell.y)


## A deterministic seed for "is the windfall fruit/nut THIS mound's forager
## just grabbed consumed outright or actually cached", derived from the
## mound's own position and the colony's current step via its own salt
## (_WINDFALL_SALT) so it never correlates with should_forage's or
## carrier_seed_for's own rolls for the same (cell, step) -- the same
## independent-second-sample technique those two already use between each
## other. Feed this into windfall_is_consumed.
func windfall_carrier_seed_for(cell: Vector2i) -> int:
	return PixelNoise.value(_seed_value + _step_count + _WINDFALL_SALT, cell.x, cell.y)


## This mound's own current colony strength -- an abstract number, not a
## literal worker headcount (see AntPopulationModel.STARTING_POPULATION's
## own doc comment). Every real mound has a real entry from
## _seed_initial_mounds; the fallback below only ever answers for a cell
## that was never a real mound at all (e.g. a caller probing an arbitrary
## coordinate).
func population_at(cell: Vector2i) -> float:
	return _population.get(cell, AntPopulationModel.STARTING_POPULATION)


## How large a colony this mound can currently support -- rises with its
## own recent forage success (see record_forage_result) AND its own
## recent soil moisture (see record_moisture), the real feedback loop
## named in docs/concept/soil_fauna.md's "A queen, and where a colony's
## size comes from" / "Water, not just food: a second real growth
## driver".
func capacity_at(cell: Vector2i) -> float:
	return _population_model.capacity(_forage_success.get(cell, 0.0), _moisture.get(cell, 0.0))


## Records whether one dispatched forager's real round trip actually found
## food -- called once per trip, on real resolution (arrival), never at
## dispatch time, since dispatch itself does not yet know the outcome (see
## docs/concept/soil_fauna.md "Real foraging: a round trip, not an instant
## resolve"). Feeds the recent-success signal capacity_at reads.
func record_forage_result(cell: Vector2i, succeeded: bool) -> void:
	var current: float = _forage_success.get(cell, 0.0)
	var target := 1.0 if succeeded else 0.0
	_forage_success[cell] = lerpf(current, target, FORAGE_SUCCESS_EMA_RATE)


## Records this mound's own current soil moisture -- called by
## EarthChunkManager.step_ants on the same weather-day-scale cadence
## EarthwormPatch.set_conditions already samples on, not every step (see
## docs/concept/soil_fauna.md "Water, not just food"). Feeds the
## recent-moisture signal capacity_at reads.
func record_moisture(cell: Vector2i, moisture: float) -> void:
	var current: float = _moisture.get(cell, 0.0)
	_moisture[cell] = lerpf(current, clampf(moisture, 0.0, 1.0), MOISTURE_EMA_RATE)


## How far this mound's own colony is toward AntPopulationModel.
## MAX_REFERENCE_POPULATION, [0, 1] -- what a mound's own visual size
## reads (see ProceduralAntMoundSprite.world_width_for). A founding
## colony reads near 0; a colony that has actually reached the real
## ceiling capacity() can produce (both food and water abundant, given
## time to grow into it) reads at 1.
func growth_fraction_at(cell: Vector2i) -> float:
	return clampf(population_at(cell) / AntPopulationModel.MAX_REFERENCE_POPULATION, 0.0, 1.0)


## How many foragers this mound may have concurrently active -- always at
## least 1 (even a brand-new, unfed colony still sends its first scout
## out), rising toward MAX_CONCURRENT_FORAGERS as population fills the
## mound's own capacity. Mirrors FishRenderer's own population-to-visible-
## count promotion shape.
func active_forager_cap_at(cell: Vector2i) -> int:
	var capacity := capacity_at(cell)
	if capacity <= 0.0:
		return 1
	var fraction := population_at(cell) / capacity
	return clampi(roundi(fraction * MAX_CONCURRENT_FORAGERS), 1, MAX_CONCURRENT_FORAGERS)


## This mound's own trail pheromone field, or null if it has never laid
## one down -- a pure read, so a caller scoring forage candidates (see
## PheromoneField.best_candidate_index, which already accepts null) never
## forces an allocation just to find a mound has no trail yet.
func pheromones_at(cell: Vector2i) -> PheromoneField:
	return _pheromones.get(cell)


## Deposits into this mound's own trail field, creating it on first use.
## `tile` is a GLOBAL tile coordinate (see PheromoneField.deposit) --
## AntColony itself stays in cell/biome space throughout, same as every
## other method here; converting a real pixel position to a tile is the
## caller's job (EarthChunkManager already does this everywhere else).
func deposit_pheromone(cell: Vector2i, tile: Vector2i) -> void:
	if not _pheromones.has(cell):
		_pheromones[cell] = PheromoneField.new()
	_pheromones[cell].deposit(tile)


## How far this carry travels before the seed counts as cached, in tiles.
## Spread across CARRY_MIN_TILES..CARRY_MAX_TILES the same shape as
## SeedCaching.carry_distance_tiles/SeedDispersal.carry_distance_tiles, so
## different carries range differently rather than all landing at once
## distance.
static func carry_distance_tiles(carrier_seed: int) -> float:
	var unit := PixelNoise.unit(carrier_seed, 0, 0)
	return CARRY_MIN_TILES + (CARRY_MAX_TILES - CARRY_MIN_TILES) * unit


## Which way this carry heads, as a unit vector. Sampled independently of
## the distance above (different PixelNoise inputs) so direction and range
## don't correlate, the same independent-second-sample technique the class
## doc comment describes for _FORAGE_SALT/_CARRY_SALT.
static func carry_direction(carrier_seed: int) -> Vector2:
	var angle := PixelNoise.unit(carrier_seed, 1, 0) * TAU
	return Vector2(cos(angle), sin(angle))


## Whether a windfall fruit/nut find is consumed outright rather than
## surviving to be cached (see WINDFALL_CONSUMED_CHANCE). PixelNoise-seeded
## off `windfall_seed` (see windfall_carrier_seed_for) -- never Godot's
## string hash(), which correlates neighbouring inputs instead of spreading
## them.
static func windfall_is_consumed(windfall_seed: int) -> bool:
	return PixelNoise.unit(windfall_seed, 0, 0) < WINDFALL_CONSUMED_CHANCE


## Seeds every mound at a real, established population instead of the
## bare founding minimum -- see STARTING_POPULATION's own doc comment for
## why. Ranges [STARTING_POPULATION, AntPopulationModel.BASE_CAPACITY]:
## the floor is a genuinely young/struggling colony (a real, legitimate
## roll, not excluded), the ceiling is the unfed-baseline capacity every
## mound starts at before any real forage_success/moisture observation
## ever raises it -- deliberately never seeded ABOVE that ceiling, which
## would make PopulationModel.step read the mound as already over
## capacity and immediately start shrinking it back down before the
## player ever sees it settle. PixelNoise-seeded off its own independent
## salt so different mounds read as different ages/fortunes rather than
## one flat number for every mound in the world.
func _seed_initial_mounds() -> void:
	for y in _height:
		for x in _width:
			if _mounds.size() >= MAX_MOUNDS:
				return
			if not SOIL_BIOMES.has(_biome[y * _width + x]):
				continue
			if PixelNoise.unit(_seed_value, x, y) >= MOUND_CHANCE:
				continue
			var cell := Vector2i(x, y)
			_mounds[cell] = true
			_population[cell] = PixelNoise.range_value(
				_seed_value + _POPULATION_SALT, x, y,
				AntPopulationModel.STARTING_POPULATION, AntPopulationModel.BASE_CAPACITY
			)
