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
## WINDFALL_CONSUMED_CHANCE below).
##
## No RandomNumberGenerator, and no Godot string hash either for anything
## PER-CELL: all placement and per-step rolls are derived from the chunk seed
## via PixelNoise, which (unlike `hash`) decorrelates neighbouring cells and
## neighbouring steps -- the clustering bug this project has hit five times.
##
## Ants ARE now driven by real soil conditions the same way earthworms are
## (see record_moisture/record_warmth below) -- moisture feeds capacity()'s
## own real growth bonus, and warmth throttles upkeep via a real winter
## dormancy (see dormancy_multiplier_at's own doc comment) -- this class's
## original "no surfacing/weather machinery" framing predates both and is
## no longer accurate.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const AntPopulationModel = preload("res://src/world/ant_population_model.gd")
const PheromoneField = preload("res://src/world/pheromone_field.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")

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
##
## 10 -> 2 (2026-09-06, "make there much less mounds, I'd say 1 for every
## 5" -- taken literally against this exact constant, see docs/concept/
## soil_fauna.md's "A real food economy" section). Fewer, individually
## bigger and better-fed colonies (see STARTING_POPULATION/BASE_CAPACITY
## and MOUND_WORLD_WIDTH_MAX moving together with this) read as real
## neighbours a player can learn and return to, not an undifferentiated
## scatter of a dozen indistinguishable small holes.
const MAX_MOUNDS := 2

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

## How close a SCOUTING forager (see docs/concept/soil_fauna.md's
## "Scouting: real search, not omniscient dispatch") has to physically be
## to a real leaf/seed/nut to notice it at all -- a scout no longer knows
## where food is in advance the way the old omniscient dispatch did; it
## has to actually wander close enough to sense it. Derived as HALF
## FORAGE_RADIUS_TILES (not an independently-eyeballed number) so a scout
## genuinely has to cover real ground within its own home range before
## stumbling onto something, rather than sensing the whole range at once
## from wherever it happens to be standing -- which would just be
## omniscience again, at a smaller radius. Pinned by test_sense_radius_
## is_half_the_forage_radius.
const SENSE_RADIUS_TILES := FORAGE_RADIUS_TILES * 0.5

## How many real items a scout must sense together (see AntForagerMarker.
## _sense_food_nearby) before it counts as a real CLUSTER worth recruiting
## other ants for, rather than something one ant can quietly clean up
## alone -- reported live: "these scouts should only lay out pheromones
## after they discovered a cluster for which multiple ants are needed".
## 3, not 2: a pair sitting together is still well within what a single
## forager handles over a couple of ordinary trips without ever needing
## to recruit help; real mass recruitment in ant colonies kicks in for
## genuinely rich finds, not the first hint of more than one item. A real
## design knob, not itself test-locked (see FORAGE_RADIUS_TILES's own doc
## comment for the identical precedent) -- pinned by test_cluster_
## threshold_is_pinned so a future change is a deliberate edit, not a
## silent drift.
const CLUSTER_THRESHOLD := 3

## How many scouts go out TOGETHER, spread evenly around a circle (see
## EarthChunkManager._dispatch_ant_scout_wave/AntScoutWander.spread_
## heading), when a mound has no known active trail to recruit toward --
## reported live: "the mound should send out multiple scouts in random
## directs". Naturally clamped by active_forager_cap_at like any other
## dispatch (a young mound with a cap of 1 still only ever gets one scout
## out, wave or not) -- this is "how many to ATTEMPT", not a guarantee.
## 3, matching CLUSTER_THRESHOLD's own reasoning: enough real coverage of
## the mound's small home range to plausibly find something without
## committing a large fraction of a young colony's whole workforce to
## speculative exploration at once.
const SCOUT_WAVE_SIZE := 3

## How many resolvers go out once a mound DOES have a known active trail
## (see EarthChunkManager._dispatch_ant_resolver_wave) -- reported live:
## "when the scouts return the mound dispatches more ants which follow /
## resolve the pheromone trails". Smaller than SCOUT_WAVE_SIZE: a
## confirmed cluster is a focused, already-de-risked effort, not blind
## exploration, so it does not need as many committed at once -- the
## trail persists (see PheromoneField.decay/invalidate_near) long enough
## for further waves across later step_ants ticks if the cluster is still
## good.
const RESOLVER_WAVE_SIZE := 2

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

## How much real food one completed, successful forage trip deposits into
## its mound's own stockpile (see food_stored_at/deposit_food), regardless
## of which of the three forage kinds (seed/windfall/leaf) it was -- a
## plain, equal-weight deposit rather than an invented per-food-type
## nutrition table nothing in this file has ever measured. Defined as
## exactly 1.0 to match AntPopulationModel.FOOD_PER_ANT_PER_DAY's own
## "one food unit is one ant's daily ration" unit choice: one successful
## trip feeds one ant for one day. Does not touch or replace any of the
## existing myrmecochory above (WINDFALL_CONSUMED_CHANCE/CARRY_MIN_TILES/
## CARRY_MAX_TILES) -- a real ant colony genuinely both feeds itself on
## part of what it forages (a myrmecochorous seed's own fatty elaiosome,
## a fallen fruit's soft pulp) and disperses the rest, so a deposit here
## and a plant/consume roll there are compatible uses of the same trip,
## not competing ones.
const FOOD_PER_SUCCESSFUL_FORAGE := 1.0

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

## Per-mound exponential moving average of recent soil warmth, in [0, 1] --
## the sibling record_moisture above never needed for capacity() (a real
## GROWTH bonus, safely defaulting to 0.0/"none earned yet"), but a real
## winter dormancy does (see dormancy_multiplier_at below, a real upkeep
## PENALTY, which must NOT default to "coldest possible" for a mound that
## has simply never had its first reading yet -- see that default's own
## doc comment). Fed by EarthChunkManager.step_ants via record_warmth, the
## same cadence/source EarthwormPatch.soil_warmth already reads (this
## project's own "same soil, same real signal" precedent).
var _warmth: Dictionary = {}

## Same weight as MOISTURE_EMA_RATE -- see that constant's own doc comment;
## warmth is not structurally twitchier or sluggisher than moisture either.
const WARMTH_EMA_RATE := MOISTURE_EMA_RATE

## Per-mound real, depleting/accumulating food reserve, in the same "food
## units" FOOD_PER_SUCCESSFUL_FORAGE/AntPopulationModel.FOOD_PER_ANT_PER_DAY
## are measured in -- see food_stored_at/deposit_food/
## food_availability_fraction and docs/concept/soil_fauna.md's "A real
## food economy" section. Unlike _forage_success/_moisture above (a
## rolling average of recent LUCK), this is a real quantity: it goes up
## exactly when food is actually carried home and down exactly as fast as
## the colony's own population actually eats from it.
var _food_stored: Dictionary = {}

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
## trail's own recruitment (PheromoneField.gradient_direction, biasing
## EVERY concurrently-scouting forager toward the same known-good
## source) was already correct swarm behaviour, just invisible with at
## most one worker ever out to show it. Raising the cap is what lets that
## existing mechanism actually read as a swarm converging on a rich find,
## not new behaviour.
##
## 6 -> 15 (2026-09-06, matching the new flat starting population -- see
## docs/concept/soil_fauna.md's "A real food economy" section): fewer,
## bigger colonies (MAX_MOUNDS just dropped to a fifth of its previous
## value) would otherwise mean LESS total visible ant activity across the
## world even though each colony individually thrives harder. A healthy,
## well-fed mound can now visibly have as many workers out at once as it
## actually starts with.
const MAX_CONCURRENT_FORAGERS := 15


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
		if _maybe_refound(cell):
			continue
		_population[cell] = _population_model.step(population_at(cell), capacity_at(cell), delta_days)
		_deplete_food(cell, delta_days)


## A mound whose population has genuinely hit a literal 0.0 can never
## recover through ordinary logistic growth alone -- growth is
## proportional to CURRENT population, and zero population growing at any
## rate is still zero (confirmed directly: test_a_starved_colony_does_
## not_recover_through_ordinary_growth_alone feeds a guaranteed forage
## success on every single advance() call for a real 200 simulated days
## and population never moves off 0.0). Real ant nest sites DO get
## recolonized once conditions improve -- a new queen/swarm founds again
## where an old colony died out -- so this is that, abstracted the same
## way _seed_initial_mounds already abstracts "a colony is already here"
## at chunk-load time: once real, on-hand food genuinely piles back up at
## an empty mound (see REFOUNDING_FOOD_THRESHOLD's own doc comment for
## why that is NOT the same standard a brand-new mound starts at), a
## fresh colony re-founds there at STARTING_POPULATION exactly as a
## brand-new one would -- still fragile at first (food_availability_
## fraction reads low relative to that fresh population's own upkeep
## until the ordinary economy has time to catch up), the same real
## vulnerability any newly-founded colony already has.
##
## Still reachable even for an "extinct" mound: EarthChunkManager.
## _dispatch_forager's own active_forager_cap_at floors at 1 forager
## regardless of population, so a lone forager keeps trying, and can keep
## depositing real food home, even after every worker has starved.
func _maybe_refound(cell: Vector2i) -> bool:
	if population_at(cell) > 0.0:
		return false
	if food_stored_at(cell) < REFOUNDING_FOOD_THRESHOLD:
		return false
	_population[cell] = AntPopulationModel.STARTING_POPULATION
	return true


## How much real, on-hand food counts as "enough evidence this site is
## viable again" for a fully extinct mound to re-found. Deliberately NOT
## _founding_food_reserve()'s own full, multi-day standard: reported live,
## after that first version shipped -- "when an ant mound collapses and
## hits 0 population then it stays at 0 population even if new ants enter
## or bring food. the food stock correctly increments, but the population
## stays zero" -- confirmed directly (a throwaway diagnostic probe, not a
## logic bug): gating on a full 45.0-unit reserve took over 22 REAL
## MINUTES to ever re-found, even under a perfectly successful lone
## forager trip (the only kind an extinct mound can still send, see
## _maybe_refound's own doc comment) every 30 real seconds -- a threshold
## nobody would ever realistically observe recover. 3 successful trips'
## worth (FOOD_PER_SUCCESSFUL_FORAGE * 3.0) is real, repeated evidence the
## site is productive again -- not a single lucky fluke, but nowhere near
## a full mature colony's own reserve -- mirroring CLUSTER_THRESHOLD's own
## identical "3, not 1, not a fluke" reasoning.
const REFOUNDING_FOOD_THRESHOLD := FOOD_PER_SUCCESSFUL_FORAGE * 3.0


## Colony budding (reported live: "ant mounds should have a maximum
## capacity and upon overpopulation half of the colony will found a new
## mound, hatch a new queen and grow the new colony again... they should
## found based on minimum distance to original mound and food
## availability within scout radius") -- real ant colonies bud/split this
## way once a nest genuinely outgrows its site, a new queen and a share of
## the workforce founding a fresh, independent colony nearby rather than
## the parent growing without limit forever.
##
## AntPopulationModel.MAX_REFERENCE_POPULATION is already named "the
## ceiling capacity() can ever produce" (see that constant's own doc
## comment) -- population chasing a capacity that itself never exceeds it
## means this already IS the real, natural maximum a mound can sustain,
## not a second, redundant "capacity" concept invented on top of it.
func is_overpopulated_at(cell: Vector2i) -> bool:
	return population_at(cell) >= AntPopulationModel.MAX_REFERENCE_POPULATION


## The same two real-world facts _seed_initial_mounds itself already
## gates a brand-new mound on: real, excavatable soil (SOIL_BIOMES), and
## not already somebody else's entrance. EarthChunkManager is expected to
## call this once per real candidate cell while searching for a real bud
## site (see docs/concept/soil_fauna.md's own "Colony budding" section) --
## a pure, cheap check, no world/food knowledge needed here at all (that
## half of site selection is EarthChunkManager's own job, the same
## "AntColony owns the abstract economy, EarthChunkManager owns the real
## ground" split every other mound accessor already keeps).
func is_valid_mound_site(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _mounds.has(cell):
		return false
	return SOIL_BIOMES.has(_biome[cell.y * _width + cell.x])


## Chance, per call to advance(), that a genuinely overpopulated mound
## actually ATTEMPTS to bud this step -- mirrors FORAGE_CHANCE/MOUND_
## CHANCE's own "small deterministic per-step chance, ongoing background
## activity, not a single guaranteed burst the instant the condition is
## met" reasoning exactly. Keeps EarthChunkManager's own real site-search
## (checking real food at every real candidate cell) naturally rare even
## while a colony sits at its own reference maximum for a long stretch,
## rather than repeating an expensive search every single step.
const BUD_CHANCE := 0.05

## Salt for the per-step budding roll, independent of every other per-mound
## roll for the same reason they are all independent of each other (see
## _FORAGE_SALT's own doc comment) -- "does this overpopulated mound bud
## THIS step" must not correlate with "does it forage this exact step".
const _BUD_SALT := 27644437

func should_bud(cell: Vector2i) -> bool:
	if not is_overpopulated_at(cell):
		return false
	return PixelNoise.unit(_seed_value + _step_count + _BUD_SALT, cell.x, cell.y) < BUD_CHANCE


## The actual split: "half of the colony" -- both its population AND its
## real stored food reserve, so the new colony is not born starving
## (mirrors _founding_food_reserve's own "never born already starving"
## reasoning) and the parent is not left with an oddly outsized reserve
## for its own now-halved population. A no-op at an invalid target (the
## caller is expected to have already checked is_valid_mound_site, but
## this stays safe on its own regardless, the same defensive "just try
## and let this decide" contract invalidate_pheromone_near and friends
## already have) -- neither mound is touched at all if `to_cell` turns
## out not to be real, excavatable, unoccupied soil.
func bud_new_mound(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not is_valid_mound_site(to_cell):
		return
	var half_population := population_at(from_cell) * 0.5
	var half_food := food_stored_at(from_cell) * 0.5
	_population[from_cell] = half_population
	_food_stored[from_cell] = half_food
	_mounds[to_cell] = true
	_population[to_cell] = half_population
	_food_stored[to_cell] = half_food


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


## How much of a mound's own abstract colony strength one crushed forager
## costs -- the smallest indivisible unit this abstraction can represent
## ("one worker," not a percentage), the same "real, if inherently
## judgment-called, design knob" framing FORAGE_RADIUS_TILES's own doc
## comment already uses. Pinned by
## test_forager_crushed_reduces_population_by_one_worker.
const FORAGER_CRUSH_POPULATION_LOSS := 1.0


## A real forager belonging to this mound died underfoot (see
## docs/concept/soil_fauna.md's own "Generalized to ants too" -- "no effect
## on the mound's own population/food economy beyond the one forager
## actually lost", now closed by EarthChunkManager.crush_ants_near calling
## this). Floors at 0.0, the same floor ordinary starvation already
## respects (see _deplete_food/AntPopulationModel.step's own logistic-growth
## contract) -- a mound can lose its very last forager without ever reading
## a nonsensical negative population. A cell that was never a real mound at
## all still accepts this harmlessly (population_at's own documented
## fallback default minus the loss), the same "narrows, doesn't break" shape
## every other optional/best-effort query in this codebase already has.
func forager_crushed(cell: Vector2i) -> void:
	_population[cell] = maxf(0.0, population_at(cell) - FORAGER_CRUSH_POPULATION_LOSS)


## A real forager belonging to this mound was eaten by a real bird
## predator (a robin or sparrow hunting live ants -- see
## EarthChunkManager.take_ant_near) rather than crushed underfoot. The
## SAME population-loss effect as forager_crushed (losing a worker is
## losing a worker, whichever killed it), deliberately kept as its own,
## distinctly-named method rather than a reuse of forager_crushed:
## crushing is the one cause the PLAYER can trigger, and costs Karma
## (Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY, applied by whichever caller
## actually did the crushing -- never here), while a bird's natural
## predation is not the player's doing and must never carry that same
## penalty. Keeping the two call sites distinct is what lets
## EarthChunkManager wire each cause to its own correct consequence
## without a branch inside AntColony itself.
func forager_eaten(cell: Vector2i) -> void:
	_population[cell] = maxf(0.0, population_at(cell) - FORAGER_CRUSH_POPULATION_LOSS)


## How large a colony this mound can currently support -- rises with its
## own recent forage success (see record_forage_result) AND its own
## recent soil moisture (see record_moisture), the real feedback loop
## named in docs/concept/soil_fauna.md's "A queen, and where a colony's
## size comes from" / "Water, not just food: a second real growth
## driver" -- gated by its own real, on-hand food reserve (see
## food_availability_fraction and "A real food economy" in that same
## doc): however good recent luck and rainfall have been, a colony
## cannot support more than its own actual stockpile can currently feed.
func capacity_at(cell: Vector2i) -> float:
	return (
		_population_model.capacity(_forage_success.get(cell, 0.0), _moisture.get(cell, 0.0))
		* food_availability_fraction(cell)
	)


## Records whether one dispatched forager's real round trip actually found
## food -- called once per trip, on real resolution (arrival), never at
## dispatch time, since dispatch itself does not yet know the outcome (see
## docs/concept/soil_fauna.md "Real foraging: a round trip, not an instant
## resolve"). Feeds the recent-success signal capacity_at reads, AND (a
## successful trip only) the real food reserve that same capacity is now
## also gated by (see "A real food economy" in that same doc) -- the one
## place a completed trip's outcome is already reported is the one place
## that outcome needs to feed both.
func record_forage_result(cell: Vector2i, succeeded: bool) -> void:
	var current: float = _forage_success.get(cell, 0.0)
	var target := 1.0 if succeeded else 0.0
	_forage_success[cell] = lerpf(current, target, FORAGE_SUCCESS_EMA_RATE)
	if succeeded:
		deposit_food(cell, FOOD_PER_SUCCESSFUL_FORAGE)


## This mound's own real, currently-stored food reserve, in the same
## "food units" FOOD_PER_SUCCESSFUL_FORAGE/AntPopulationModel.
## FOOD_PER_ANT_PER_DAY are measured in. A real mound not yet present in
## _food_stored (never advanced, never fed) reads as _seed_initial_mounds'
## own seeded value would be BEFORE any real depletion -- the same
## "unset reads as the fresh-mound default" fallback shape population_at
## already uses.
func food_stored_at(cell: Vector2i) -> float:
	return _food_stored.get(cell, _founding_food_reserve())


## Adds real food to this mound's own reserve -- called whenever a
## completed forage trip actually brings something home (see
## record_forage_result) or directly by a caller that already knows an
## amount (kept separate from record_forage_result so "a trip succeeded"
## and "food increased by this much" stay two independently-testable
## facts, even though the former always implies the latter today).
func deposit_food(cell: Vector2i, amount: float) -> void:
	_food_stored[cell] = food_stored_at(cell) + amount


## How much of a healthy FOOD_BUFFER_DAYS-day reserve, at this mound's own
## CURRENT population's upkeep rate, is actually on hand right now -- [0, 1],
## 1.0 a colony sitting on a full or better buffer (capacity_at reads
## exactly what recent forage-success/moisture already say it should,
## unconstrained), less than that a colony running low, 0.0 one that has
## genuinely run out OR has no population left at all to report on.
##
## A population of 0 reads 0.0, not 1.0 -- checked directly, not assumed:
## PopulationModel.step has its own real, existing "carrying_capacity <=
## 0.0 -> population immediately reads exactly 0.0" rule (a genuine, real
## famine, not a smooth approach to it), which THIS mechanism's own
## capacity_at multiplier is the first thing ever able to actually drive
## to a literal zero for ants. Reading a population-0 mound as "fully
## food-secure" would have been a real lie the instant that happened --
## capacity_at would recompute at its full forage-success/moisture-driven
## ceiling (up to MAX_REFERENCE_POPULATION) for a colony that has, in
## fact, gone completely extinct, and (population stuck at exactly 0.0
## being the one input a pure logistic multiplier can never grow back
## from on its own) stay that convincingly-healthy-looking forever.
## Reading 0.0 instead means an extinct mound's own food stat honestly
## reports "nothing," not "thriving."
func food_availability_fraction(cell: Vector2i) -> float:
	var population := population_at(cell)
	if population <= 0.0:
		return 0.0
	var needed := population * AntPopulationModel.FOOD_PER_ANT_PER_DAY * AntPopulationModel.FOOD_BUFFER_DAYS
	if needed <= 0.0:
		return 0.0
	return clampf(food_stored_at(cell) / needed, 0.0, 1.0)


## The real upkeep a mound's own population represents -- more ants, more
## mouths, more draw on the same reserve every simulated day, throttled by
## dormancy_multiplier_at in cold soil. Clamped at zero: a colony cannot owe
## food it does not have.
func _deplete_food(cell: Vector2i, delta_days: float) -> void:
	var consumed := (
		population_at(cell) * AntPopulationModel.FOOD_PER_ANT_PER_DAY * delta_days
		* dormancy_multiplier_at(cell)
	)
	_food_stored[cell] = maxf(0.0, food_stored_at(cell) - consumed)


## Below this soil warmth, ants go dormant -- cluster deep in the mound and
## barely feed at all -- mirroring EarthwormPatch's own COLD_CUTOFF/
## MILD_WARMTH cold-gate exactly (same soil, same real mechanism: real
## ants, like real earthworms sharing the same ground, drastically cut
## activity in cold soil; unlike worms they do not need to surface to do
## this, but the same warmth-driven ramp still governs how much a mound
## actually consumes). Reused directly rather than a second,
## independently-eyeballed pair of numbers for the identical soil.
##
## DORMANCY_FLOOR, not all the way to 0.0 -- mirrors EarthwormPatch.
## WINTER_SOIL_FLOOR's own "a seasonal swing is a partial cooling, not a
## multiplication down to zero" reasoning exactly: a genuinely dormant
## colony still needs SOME food to survive winter on stored fat, the same
## as a real overwintering colony. Reported live: "now i don't see any ant
## mounds at all anymore (fresh start, winter)" -- confirmed root cause,
## directly: FOOD_BUFFER_DAYS(3) * SECONDS_PER_SIMULATED_DAY(60) = 180
## real seconds is far shorter than a real winter's near-total lack of
## forage success (bare trees drop no windfall, fallen leaf litter ages
## into its own terminal decay stage with nothing replacing it -- see
## docs/concept/leaf_litter.md), so every mound was starving to a literal
## population 0.0 well within one season -- and, worse, PopulationModel.
## step's own hard "carrying_capacity <= 0.0 -> population immediately
## 0.0" rule meant that was PERMANENT (see _maybe_refound below for the
## other half of this fix: a hard 0.0 floor here alone would only move
## the same permanent-death bug to "a sufficiently long or severe cold
## spell" instead of actually fixing it).
const DORMANCY_FLOOR := 0.2

func dormancy_multiplier_at(cell: Vector2i) -> float:
	var warmth: float = _warmth.get(cell, 1.0)
	var cold_gate := clampf(
		(warmth - EarthwormPatch.COLD_CUTOFF) / (EarthwormPatch.MILD_WARMTH - EarthwormPatch.COLD_CUTOFF),
		0.0, 1.0
	)
	return DORMANCY_FLOOR + (1.0 - DORMANCY_FLOOR) * cold_gate


## A freshly-seeded mound is never born already starving -- exactly a full
## FOOD_BUFFER_DAYS reserve for its OWN seeded starting population (see
## _seed_initial_mounds), so food_availability_fraction reads exactly 1.0
## the instant a mound is (re)seeded, derived from the same constants that
## reserve is measured against rather than a second, independently-chosen
## number that could drift from what "a full buffer" actually means.
func _founding_food_reserve() -> float:
	return (
		AntPopulationModel.STARTING_POPULATION
		* AntPopulationModel.FOOD_PER_ANT_PER_DAY
		* AntPopulationModel.FOOD_BUFFER_DAYS
	)


## Records this mound's own current soil moisture -- called by
## EarthChunkManager.step_ants on the same weather-day-scale cadence
## EarthwormPatch.set_conditions already samples on, not every step (see
## docs/concept/soil_fauna.md "Water, not just food"). Feeds the
## recent-moisture signal capacity_at reads.
func record_moisture(cell: Vector2i, moisture: float) -> void:
	var current: float = _moisture.get(cell, 0.0)
	_moisture[cell] = lerpf(current, clampf(moisture, 0.0, 1.0), MOISTURE_EMA_RATE)


## Records this mound's own current soil warmth -- called by
## EarthChunkManager.step_ants on the same cadence/source record_moisture
## already uses (EarthwormPatch.soil_warmth's own climate+season_warmth
## computation, reused directly rather than a second, independent reading
## of the identical soil). Feeds dormancy_multiplier_at, which throttles
## real food upkeep in cold soil (see that function's own doc comment).
func record_warmth(cell: Vector2i, warmth: float) -> void:
	var current: float = _warmth.get(cell, 1.0)
	_warmth[cell] = lerpf(current, clampf(warmth, 0.0, 1.0), WARMTH_EMA_RATE)


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
## one down -- a pure read, so a scouting forager sensing a local gradient
## (see PheromoneField.gradient_direction, called only when this is
## non-null -- see AntForagerMarker._step_scouting) never forces an
## allocation just to find a mound has no trail yet.
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


## Real directional trail deposit for a CLUSTER find (see
## PheromoneField.deposit_trail's own doc comment and docs/concept/
## soil_fauna.md "Scouting: real search, not omniscient dispatch") --
## creates the field on first use, same as deposit_pheromone.
func deposit_pheromone_trail(cell: Vector2i, tile: Vector2i, direction: Vector2, amount: float) -> void:
	if not _pheromones.has(cell):
		_pheromones[cell] = PheromoneField.new()
	_pheromones[cell].deposit_trail(tile, direction, amount)


## Whether this mound's own trail field currently holds a real, followable
## cluster trail (see PheromoneField.has_active_trail) -- what step_ants
## checks to decide whether to dispatch RESOLVERS (a known cluster is
## still being worked) or a fresh WAVE of blind scouts (nothing known yet).
## False on a mound that has never deposited at all -- no allocation
## needed just to answer "no".
func has_active_pheromone_trail(cell: Vector2i) -> bool:
	var field: PheromoneField = _pheromones.get(cell)
	return field != null and field.has_active_trail()


## The nearest real trail near `position` (see PheromoneField.
## nearest_trail_near) -- {} on a mound that has never deposited at all,
## the same "no allocation just to answer empty" reasoning
## has_active_pheromone_trail already uses.
func nearest_pheromone_trail_near(cell: Vector2i, position: Vector2, tile_size: float) -> Dictionary:
	var field: PheromoneField = _pheromones.get(cell)
	if field == null:
		return {}
	return field.nearest_trail_near(position, tile_size)


## Masks this mound's own trail near `position` as spent (see
## PheromoneField.invalidate_near) -- a genuine no-op on a mound that has
## never deposited at all, since there is nothing there yet that could
## mislead a future resolver.
func invalidate_pheromone_near(cell: Vector2i, position: Vector2, radius_tiles: float, tile_size: float) -> void:
	var field: PheromoneField = _pheromones.get(cell)
	if field == null:
		return
	field.invalidate_near(position, radius_tiles, tile_size)


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
## why. Flat AntPopulationModel.STARTING_POPULATION for every mound
## (2026-09-06, "start at 15 ants at the beginning," a specific number
## taken literally -- superseded the previous pass's own seeded RANGE,
## [STARTING_POPULATION, BASE_CAPACITY], which existed only because that
## pass had no specific number to seed instead of one). _POPULATION_SALT
## is kept, unused for now, rather than deleted: a future pass reintroducing
## per-mound variance (ages/fortunes) around this same specific number
## would want its own independent roll, exactly this one already is.
##
## Also seeds this mound's starting food reserve (_founding_food_reserve,
## a full FOOD_BUFFER_DAYS buffer for its own starting population -- see
## "A real food economy" in docs/concept/soil_fauna.md) so a freshly-
## founded colony is never born already starving.
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
			_population[cell] = AntPopulationModel.STARTING_POPULATION
			_food_stored[cell] = _founding_food_reserve()
