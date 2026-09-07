extends RefCounted

## Per-chunk honeybee colony population -- see docs/concept/bees.md, the
## direct sibling of AntColony (docs/concept/soil_fauna.md#a-queen-and-
## where-a-colonys-size-comes-from). Mirrors AntColony's own placement/
## population/food-economy shape wherever the real biology genuinely
## agrees (a queen-driven population bounded by what foragers bring
## home), and departs from it deliberately in three places bees.md names
## explicitly: capacity is bounded by forage success ALONE (no separate
## water/moisture input -- there is no comparably central "is there water
## nearby" driver for a hive the way there is for a digging,
## larvae-humidity-dependent ant nest), a colony that loses its home
## ABSCONDS to a brand new site rather than refounding in place, and
## honey storage is both the colony's own real food reserve AND the exact
## quantity a player harvest withdraws -- one number, two roles, by
## design (see withdraw_honey).
##
## Deliberately shaped like EarthwormPatch/AntColony -- deterministic
## PixelNoise-seeded placement, a hard per-chunk cap, advance(delta) --
## rather than sharing a base class with them (see DesertScrub's own doc
## comment on why three similar things beats a premature abstraction).
##
## No pheromone-trail recruitment, no scout/resolver wave dispatch --
## deliberately not built for bees in this pass (see bees.md's own "What's
## reused verbatim, what's a deliberate new duplicate, and why": real
## honeybee recruitment is the waggle dance, a genuinely different signal
## from a laid scent trail, and modeling it faithfully is a separate piece
## of work).

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const BeePopulationModel = preload("res://src/world/bee_population_model.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")

## Biomes with a real tree for a wild colony to hang its comb from --
## deliberately NOT AntColony.SOIL_BIOMES's own excavatable-soil framing
## (a hive is not dug into the ground, it hangs from a branch -- see the
## supplied art), though the real set happens to coincide with
## CaterpillarRenderer.CATERPILLAR_BIOMES (another tree-dependent
## resident): grassland, forest, and rainforest all grow real trees in
## this game; desert/tundra/mountain/ocean do not.
const HIVE_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Chance a given tree-bearing cell holds a wild hive. Deliberately far
## BELOW AntColony.MOUND_CHANCE (0.05, see test_hives_are_sparser_than_
## ant_mounds): a real wild honeybee colony forages over a territory of
## several real square kilometres, an order of magnitude beyond a single
## ant nest's tiny local patch -- correspondingly far fewer hives per
## unit area is the real-world-correct density, not an arbitrary
## rarity/aesthetic choice.
const HIVE_CHANCE := 0.015

## Hard cap per chunk. A single real wild colony's own foraging range
## already covers a huge area relative to a chunk -- more than a small
## handful sharing one chunk's worth of flowers would be its own
## un-real-world crowding this doc has no separate mechanism for. Kept at
## 1 rather than AntColony.MAX_MOUNDS's own 2: a hive is a rarer, more
## individually significant landmark than an ant mound, the same "fewer,
## bigger, more legible neighbours" reasoning that already motivated
## AntColony.MAX_MOUNDS's own 10 -> 2 cut.
const MAX_HIVES := 1

## Chance, per call to advance(), that a given hive's colony sends a
## forager out to check for real nearby nectar this step -- mirrors
## AntColony.FORAGE_CHANCE's own "small per-step chance, ongoing
## background activity" reasoning. A real honeybee colony forages far
## more continuously through a day than an ant colony's occasional
## scouting trips, so this sits ABOVE AntColony.FORAGE_CHANCE, an
## ordering, not an eyeballed number.
const FORAGE_CHANCE := 0.15

## How far a hive's own forage reach extends, in tiles -- deliberately
## reuses PollinatorForaging.FORAGE_SEARCH_TILES directly rather than a
## second, independently-chosen number: it is already this exact
## codebase's own real, tuned "how far a bee/butterfly searches for a
## flower" distance, and a hive-tied forager's own search is the same
## real animal behaviour, just now round-tripping home instead of
## wandering a trapline. Restated as a local constant (not imported,
## avoiding a needless cross-module dependency for one float) but
## cross-checked by test so the two cannot silently drift apart.
const FORAGE_RADIUS_TILES := 18.0

## Salt for the per-step foraging roll, independent of every other
## per-hive roll for the same reason AntColony's own salts are (see that
## file's _FORAGE_SALT doc comment): "does this hive forage this step"
## must not correlate with any other per-hive-per-step decision.
const _FORAGE_SALT := 733

## Salt for the per-step budding (swarm) roll.
const _BUD_SALT := 941039

## How much real honey one completed, successful forage trip deposits
## into its hive's own stockpile -- mirrors AntColony.
## FOOD_PER_SUCCESSFUL_FORAGE's own "one trip, one unit" simplification:
## real bees convert nectar to honey through enzymatic processing and
## evaporation over days in the comb, and modeling that whole process is
## well past the fidelity this game's other forage economies operate at.
## Matches BeePopulationModel.HONEY_PER_BEE_PER_DAY's own unit choice --
## one successful trip feeds one bee for one day.
const FOOD_PER_SUCCESSFUL_FORAGE := 1.0

## How much weight a single forage outcome carries in the recent-success
## EMA -- mirrors AntColony.FORAGE_SUCCESS_EMA_RATE exactly, the identical
## "neither twitchy nor sluggish" reasoning.
const FORAGE_SUCCESS_EMA_RATE := 0.3

## Same weight as FORAGE_SUCCESS_EMA_RATE -- mirrors AntColony.WARMTH_EMA_
## RATE exactly.
const WARMTH_EMA_RATE := FORAGE_SUCCESS_EMA_RATE

## Real winter dormancy floor -- mirrors AntColony.DORMANCY_FLOOR exactly,
## reusing EarthwormPatch.COLD_CUTOFF/MILD_WARMTH for the identical real
## soil-and-air-temperature signal (same climate, same real mechanism): a
## clustering, dormant colony still needs SOME food to survive winter on
## its own stored reserve, never all the way to zero upkeep.
const DORMANCY_FLOOR := 0.2

## How many foragers a hive may have concurrently active -- mirrors
## AntColony.active_forager_cap_at's own "aggregate population promotes
## to visible individual markers, scaled by population/capacity" shape,
## without the wave-spread dispatch ants also have (see this file's own
## header doc comment on pheromone recruitment being out of scope here).
const MAX_CONCURRENT_FORAGERS := 10

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int
var _step_count: int = 0

## Vector2i cell -> true. Mirrors AntColony._mounds exactly, except a hive
## CAN be removed from this over the colony's life (absconding, and a
## hive harvested to structural collapse) -- unlike a mound, which is
## fixed for the chunk's whole life.
var _hives: Dictionary = {}

var _population: Dictionary = {}
var _forage_success: Dictionary = {}
var _warmth: Dictionary = {}
var _food_stored: Dictionary = {}
var _population_model := BeePopulationModel.new()

## Mirrors AntColony.SECONDS_PER_SIMULATED_DAY exactly -- see that
## constant's own doc comment for why this is restated locally rather
## than imported (EarthChunkManager already preloads BeeColony; the
## reverse import would be circular), cross-checked by test.
const SECONDS_PER_SIMULATED_DAY := 60.0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_hives()


func hive_cells() -> Array:
	return _hives.keys()


func has_hive(cell: Vector2i) -> bool:
	return _hives.has(cell)


## Mirrors AntColony.advance exactly in shape: grows/stalls every hive's
## population toward its current capacity, and depletes real honey for
## real upkeep. Deliberately does NOT contain AntColony's own
## _maybe_refound escape hatch -- a collapsed hive stays at exactly 0.0
## population forever under advance() alone (see should_abscond_at):
## for bees, "the home site failed" is answered by relocating the whole
## colony elsewhere (abscond_to, dispatched by EarthChunkManager once it
## has found a real new site, the same AntColony/EarthChunkManager
## "abstract economy here, real ground search there" split budding
## already uses), never a same-site respawn.
func advance(delta_seconds: float) -> void:
	_step_count += 1
	var delta_days := delta_seconds / SECONDS_PER_SIMULATED_DAY
	for cell in _hives:
		_population[cell] = _population_model.step(population_at(cell), capacity_at(cell), delta_days)
		_deplete_food(cell, delta_days)


## How much a hive's population, honey reserve, and win/lose position
## overall says this site has genuinely failed -- see bees.md's
## "Absconding" section for the three real triggers this names, of which
## only the third (starvation) is actually detectable from inside the
## colony's own economy; "destroyed" (harvested to structural collapse)
## is a real-world event the harvest mechanic itself already knows about
## and calls abscond_to for directly, without ever consulting this
## predicate at all.
##
## Population reaching a literal 0.0 can never recover through ordinary
## logistic growth alone -- growth is proportional to CURRENT population,
## and zero population growing at any rate is still zero (the identical
## hard-floor fact AntColony's own _maybe_refound exists to work around;
## here, the "recovery" is relocation instead of a same-site respawn).
func should_abscond_at(cell: Vector2i) -> bool:
	if not has_hive(cell):
		return false
	return population_at(cell) <= 0.0


## The colony's own pure half of relocation (see bees.md's
## "Absconding"): moves the FULL population and FULL remaining honey to
## a freshly-searched new site -- unlike bud_new_hive's even swarm split,
## absconding is the whole colony moving house together, not
## reproducing. A no-op at an invalid destination, the same defensive
## "just try and let this decide" contract bud_new_hive already has --
## neither site is touched if `to_cell` is not real, valid, unoccupied
## tree-bearing ground (EarthChunkManager is expected to have already
## searched for one; this stays safe regardless).
func abscond_to(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not is_valid_hive_site(to_cell):
		return
	var population := population_at(from_cell)
	var honey := honey_stored_at(from_cell)
	_hives.erase(from_cell)
	_population.erase(from_cell)
	_food_stored.erase(from_cell)
	_forage_success.erase(from_cell)
	_warmth.erase(from_cell)
	_hives[to_cell] = true
	_population[to_cell] = population
	_food_stored[to_cell] = honey


## Colony budding/swarming (see bees.md's "Real-world grounding": the
## real mechanism a honeybee colony reproduces by -- the old queen
## leaves with roughly half the workforce to found a new colony
## elsewhere, while the hive left behind raises a new queen and carries
## on). Near-direct port of AntColony.is_overpopulated_at/should_bud/
## bud_new_mound: the real biology genuinely converges here (see bees.md
## header). BeePopulationModel.MAX_REFERENCE_POPULATION is already "the
## ceiling capacity() can ever produce" -- population chasing a capacity
## that never exceeds it already IS the natural maximum, not a second,
## redundant concept invented on top of it.
func is_overpopulated_at(cell: Vector2i) -> bool:
	return population_at(cell) >= BeePopulationModel.MAX_REFERENCE_POPULATION


## Chance, per call to advance(), that a genuinely overpopulated hive
## actually attempts to swarm this step -- mirrors AntColony.BUD_CHANCE's
## own "small per-step chance, ongoing background activity" reasoning.
const BUD_CHANCE := 0.05

func should_bud(cell: Vector2i) -> bool:
	if not is_overpopulated_at(cell):
		return false
	return PixelNoise.unit(_seed_value + _step_count + _BUD_SALT, cell.x, cell.y) < BUD_CHANCE


## The actual split: half the colony's population AND half its real
## honey reserve, so the new hive is not born starving and the parent is
## not left with an oddly outsized reserve for its own now-halved
## population -- mirrors AntColony.bud_new_mound's identical reasoning
## and shape exactly.
func bud_new_hive(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not is_valid_hive_site(to_cell):
		return
	var half_population := population_at(from_cell) * 0.5
	var half_honey := honey_stored_at(from_cell) * 0.5
	_population[from_cell] = half_population
	_food_stored[from_cell] = half_honey
	_hives[to_cell] = true
	_population[to_cell] = half_population
	_food_stored[to_cell] = half_honey


## The same two real-world facts _seed_initial_hives itself gates a
## brand-new hive on: a real tree-bearing biome (HIVE_BIOMES), and not
## already somebody else's nest -- mirrors AntColony.is_valid_mound_site
## exactly. A pure, cheap check; the real ground-level half of site
## selection (is there real forage nearby) is EarthChunkManager's own
## job, the identical "BeeColony owns the abstract economy,
## EarthChunkManager owns the real ground" split AntColony already keeps.
func is_valid_hive_site(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _hives.has(cell):
		return false
	return HIVE_BIOMES.has(_biome[cell.y * _width + cell.x])


## Whether this hive's colony sends a forager out to check for real
## nearby nectar THIS step -- mirrors AntColony.should_forage exactly, a
## pure PixelNoise-seeded roll, never Godot's string hash.
func should_forage(cell: Vector2i) -> bool:
	return PixelNoise.unit(_seed_value + _step_count + _FORAGE_SALT, cell.x, cell.y) < FORAGE_CHANCE


## This hive's own current colony strength -- an abstract number, not a
## literal bee headcount (see BeePopulationModel.STARTING_POPULATION's
## own doc comment). Mirrors AntColony.population_at's own fallback
## exactly: a cell that was never a real hive at all reads the starting
## default, same as a freshly-seeded one would.
func population_at(cell: Vector2i) -> float:
	return _population.get(cell, BeePopulationModel.STARTING_POPULATION)


## How large a colony this hive can currently support -- rises with its
## own recent forage success (see record_forage_result), gated by its
## own real, on-hand honey reserve (see honey_availability_fraction):
## however good recent luck has been, a colony cannot support more bees
## than its own actual stockpile can currently feed. Deliberately just
## the ONE input (see this file's own header doc comment) -- no second
## moisture/water term the way AntColony.capacity_at has.
func capacity_at(cell: Vector2i) -> float:
	return _population_model.capacity(_forage_success.get(cell, 0.0)) * honey_availability_fraction(cell)


## Records whether one dispatched forager's real round trip actually
## found nectar -- mirrors AntColony.record_forage_result exactly: feeds
## the recent-success signal capacity_at reads, AND (a successful trip
## only) the real honey reserve that same capacity is now also gated by.
func record_forage_result(cell: Vector2i, succeeded: bool) -> void:
	var current: float = _forage_success.get(cell, 0.0)
	var target := 1.0 if succeeded else 0.0
	_forage_success[cell] = lerpf(current, target, FORAGE_SUCCESS_EMA_RATE)
	if succeeded:
		deposit_food(cell, FOOD_PER_SUCCESSFUL_FORAGE)


## This hive's own real, currently-stored honey reserve -- mirrors
## AntColony.food_stored_at's own fallback exactly: a real hive not yet
## present in _food_stored (never advanced, never fed) reads its own
## founding reserve, the same "unset reads as the fresh-hive default"
## shape population_at already uses.
func honey_stored_at(cell: Vector2i) -> float:
	return _food_stored.get(cell, _founding_honey_reserve())


## Adds real honey to this hive's own reserve -- mirrors
## AntColony.deposit_food exactly.
func deposit_food(cell: Vector2i, amount: float) -> void:
	_food_stored[cell] = honey_stored_at(cell) + amount


## Removes up to `amount` of REAL, on-hand honey from this hive and
## returns exactly how much was actually taken (never more than was
## really stored, never a negative reserve) -- the harvest mechanic's own
## direct hook into the colony's real economy (see bees.md's "Harvesting
## honey": there is deliberately no separate "loot" number a hive carries
## alongside its real food reserve -- taking honey and constraining the
## colony's own future growth are the SAME lever, by design). A hive
## struck when genuinely empty yields 0.0, honestly, rather than ever
## going negative.
func withdraw_honey(cell: Vector2i, amount: float) -> float:
	var on_hand := honey_stored_at(cell)
	var taken := clampf(amount, 0.0, on_hand)
	_food_stored[cell] = on_hand - taken
	return taken


## Mirrors AntColony.food_availability_fraction exactly, against
## BeePopulationModel's own honey-denominated constants. A population of
## 0 reads 0.0, not 1.0 -- see that method's own doc comment for why an
## extinct colony must never read as "fully food-secure."
func honey_availability_fraction(cell: Vector2i) -> float:
	var population := population_at(cell)
	if population <= 0.0:
		return 0.0
	var needed := population * BeePopulationModel.HONEY_PER_BEE_PER_DAY * BeePopulationModel.HONEY_BUFFER_DAYS
	if needed <= 0.0:
		return 0.0
	return clampf(honey_stored_at(cell) / needed, 0.0, 1.0)


func _deplete_food(cell: Vector2i, delta_days: float) -> void:
	var consumed := (
		population_at(cell) * BeePopulationModel.HONEY_PER_BEE_PER_DAY * delta_days
		* dormancy_multiplier_at(cell)
	)
	_food_stored[cell] = maxf(0.0, honey_stored_at(cell) - consumed)


## Mirrors AntColony.dormancy_multiplier_at exactly, reusing the identical
## EarthwormPatch.COLD_CUTOFF/MILD_WARMTH real soil-temperature signal --
## same climate, same real mechanism, no separate bee-specific
## temperature model needed.
func dormancy_multiplier_at(cell: Vector2i) -> float:
	var warmth: float = _warmth.get(cell, 1.0)
	var cold_gate := clampf(
		(warmth - EarthwormPatch.COLD_CUTOFF) / (EarthwormPatch.MILD_WARMTH - EarthwormPatch.COLD_CUTOFF),
		0.0, 1.0
	)
	return DORMANCY_FLOOR + (1.0 - DORMANCY_FLOOR) * cold_gate


## A freshly-seeded (or newly re-established) hive is never born already
## starving -- exactly a full HONEY_BUFFER_DAYS reserve for its own
## seeded starting population, mirroring AntColony._founding_food_reserve
## exactly.
func _founding_honey_reserve() -> float:
	return (
		BeePopulationModel.STARTING_POPULATION
		* BeePopulationModel.HONEY_PER_BEE_PER_DAY
		* BeePopulationModel.HONEY_BUFFER_DAYS
	)


## Records this hive's own current soil/air warmth -- mirrors
## AntColony.record_warmth exactly; feeds dormancy_multiplier_at.
func record_warmth(cell: Vector2i, warmth: float) -> void:
	var current: float = _warmth.get(cell, 1.0)
	_warmth[cell] = lerpf(current, clampf(warmth, 0.0, 1.0), WARMTH_EMA_RATE)


## How far this hive's own colony is toward BeePopulationModel.
## MAX_REFERENCE_POPULATION, [0, 1] -- what a hive's own growth-stage art
## frame reads (see IllustratedBeehiveSprite.growth_stage_index). Mirrors
## AntColony.growth_fraction_at exactly.
func growth_fraction_at(cell: Vector2i) -> float:
	return clampf(population_at(cell) / BeePopulationModel.MAX_REFERENCE_POPULATION, 0.0, 1.0)


## Mirrors AntColony.active_forager_cap_at exactly, against
## MAX_CONCURRENT_FORAGERS above. Always >= 1, the same reason ants'
## version is: even an economically "extinct" hive (population 0, not
## yet noticed by should_abscond_at's own caller) still tries one lone
## forager, which is the only way it could ever accumulate real honey
## again at all.
func active_forager_cap_at(cell: Vector2i) -> int:
	var capacity := capacity_at(cell)
	if capacity <= 0.0:
		return 1
	var fraction := population_at(cell) / capacity
	return clampi(roundi(fraction * MAX_CONCURRENT_FORAGERS), 1, MAX_CONCURRENT_FORAGERS)


## Seeds every hive at a real, established population instead of the bare
## founding minimum -- mirrors AntColony._seed_initial_hives's own
## reasoning exactly: a wild colony is not freshly founded the instant a
## chunk loads, most have already existed in this simulated world for
## real, if unmodeled, time. Also seeds a full starting honey reserve
## (_founding_honey_reserve) so a freshly-seeded colony is never born
## already starving.
func _seed_initial_hives() -> void:
	for y in _height:
		for x in _width:
			if _hives.size() >= MAX_HIVES:
				return
			if not HIVE_BIOMES.has(_biome[y * _width + x]):
				continue
			if PixelNoise.unit(_seed_value, x, y) >= HIVE_CHANCE:
				continue
			var cell := Vector2i(x, y)
			_hives[cell] = true
			_population[cell] = BeePopulationModel.STARTING_POPULATION
			_food_stored[cell] = _founding_honey_reserve()
