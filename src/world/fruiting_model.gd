extends RefCounted

## Per-tree fruit phenology (docs/concept/ecosystem_dynamics.md, "Plant
## phenology"). Models one tree's repeating bearing cycle as a continuous
## fruit stock over elapsed time: fruits grow (immature) -> ripen (hang,
## edible) -> abscise (fall to the ground) -> the tree re-enters growing.
## Deterministic: purely a function of the genome and time, no RNG.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

## Peak crop a maximally fruitful tree (fruit_yield == 1) can bear at once.
const MAX_CROP := 12

## ## The crop follows the calendar
##
## A bearing cycle is a year, and the year is four seasons, so the phases are
## expressed as the season boundaries they actually mean rather than as loose
## fractions. Spring 0.00-0.25, summer 0.25-0.50, autumn 0.50-0.75, winter
## 0.75-1.00 (see SeasonCycle).
##
## These were 0.5 and 0.8, which put the start of ripening at the start of
## autumn and abscission at four fifths of the year -- MIDWINTER. Fruit hung on
## bare branches through the cold and a good part of a crop never came down at
## all, because the window ran off the end of the year (reported: fruit staying
## on the tree until winter, and not all of it dropping).

## ## Each species ripens at its own time
##
## Cherries ripen in early summer and apples in autumn; the nuts come down with
## the leaves. One fixed ripening date for every tree in the world meant
## nothing bore fruit through most of summer and a cherry tree never carried a
## cherry when it should have (reported).
##
## Phases are year fractions: spring 0.00-0.25, summer 0.25-0.50, autumn
## 0.50-0.75, winter 0.75-1.00 (see SeasonCycle). `ripe` is when the crop is
## first ready, `fallen` when the last of it is down.
const RIPENING_BY_SPECIES := {
	# Early summer, and over before the apples are ready.
	"cherry": {"ripe": 0.32, "fallen": 0.50},
	# The classic autumn harvest.
	"apple": {"ripe": 0.55, "fallen": 0.74},
	# Nuts come down with the leaves.
	"walnut": {"ripe": 0.58, "fallen": 0.74},
	"hazelnut": {"ripe": 0.56, "fallen": 0.74},
	"acorn": {"ripe": 0.60, "fallen": 0.74},
	# Cones open late and hang on longest.
	"pine": {"ripe": 0.62, "fallen": 0.74},
}

## Nothing ripens before the end of spring, however warm it is: a tree in
## spring is still in blossom, and fruit cannot precede the flower.
const EARLIEST_RIPE_PHASE := 0.25

## What an unlisted species does: a plain autumn crop.
const _DEFAULT_RIPENING := {"ripe": 0.55, "fallen": 0.74}

## How far into its ripe window a crop starts dropping.
##
## Three points, not two: the fruit BECOMES ripe, hangs there a while, and then
## abscises until none is left. Collapsing "becomes ripe" and "starts falling"
## into one number made the whole stretch before ripening read as ripe --
## a cherry tree carrying ripe fruit in early spring, before it had blossomed.
const ABSCISSION_FRACTION := 0.4


static func _ripening_for(species: String) -> Dictionary:
	return RIPENING_BY_SPECIES.get(species, _DEFAULT_RIPENING)


## When this species' crop is first ripe, as a fraction of the year.
static func ripe_phase_for(species: String) -> float:
	return float(_ripening_for(species)["ripe"])


## When the last of this species' crop is down.
static func fallen_phase_for(species: String) -> float:
	return float(_ripening_for(species)["fallen"])
## How much warmth (growing-degree-day analogue) brings the harvest FORWARD,
## as a fraction of the year.
##
## It used to shorten the whole bearing CYCLE, by up to half. That put the
## crop on its own clock, drifting against the calendar: at full warmth a tree
## bore twice a year, so half its harvests landed in winter and the phases
## stopped meaning the seasons they are named after. A warm climate ripening
## its fruit early is real; a tree that does not know when winter is, is not.
##
## The cycle is a year, always. Warmth moves the ripening window earlier
## within it -- an early variety in a warm valley picks sooner -- and the crop
## is still down before the frost.
const WARMTH_EARLINESS := 0.08

## Length of one bearing cycle at neutral warmth: a YEAR. A tree flowers,
## sets fruit, ripens it and sheds it once through the seasons, which is what
## the abscission window below is a window OF.
##
## This used to be genome.maturity_time -- 20 to 60 SECONDS. That is how long
## a sapling takes to grow up (TreeMaturity), an entirely different quantity,
## and borrowing it meant every mature tree shed its whole crop twice a
## minute: a measured 1524 fruit per minute from a 40-tree stand against a
## ground-item budget of 80, so the world churned a hundred-odd labelled,
## clickable nodes a second and the ground under every tree carried stacks of
## a hundred apples (reported: "way too much fruit are being dropped", and
## the lag that came with it).
##
## It survived unnoticed for exactly the same reason the 30-second
## reproduction cooldown did -- the ecology simulation was never actually
## stepping (see World.owns_ecosystem_simulation_for), so nothing that
## depended on real elapsed world time had ever been observed running.
const BEARING_CYCLE_SECONDS := SeasonCycle.SECONDS_PER_YEAR


## Crop potential (max simultaneous ripe fruit) for a genome, scaled by a
## named species' own yield character (see TreeSpecies.yield_multiplier_for)
## -- defaults to 1.0, reproducing the un-species'd behaviour exactly for any
## caller that doesn't know about species yet.
func crop_potential(genome, yield_multiplier: float = 1.0) -> int:
	return int(round(genome.fruit_yield * MAX_CROP * yield_multiplier))


## -- pollination feedback (see docs/concept/flora.md) ------------------------
##
## Bee visits to a blossoming, insect-pollinated tree (TreeSpecies.
## needs_pollinators_for) nudge its yield up from a reduced floor toward the
## species' full ceiling as they accumulate over one bearing cycle -- the
## feedback flora.md flagged as missing: flowers fed pollinators, but a visit
## never fed anything back. Callers compose this INTO the existing
## yield_multiplier crop_potential already takes (species_yield * this),
## rather than this replacing that multiplier.

## The floor an insect-pollinated tree with ZERO visits this cycle still sits
## at. Real apples and cherries are not self-sterile: an isolated tree still
## sets some fruit from self- or incidental pollination (a breeze carrying
## pollen a short distance, a visit from something other than a bee), just far
## below what cross-pollination by a working hive achieves. Grounded at a
## fifth of the ceiling -- low enough that bees visibly matter, never zero.
const UNPOLLINATED_YIELD_FLOOR := 0.2

## Visits within one bearing cycle at which pollination is treated as fully
## done -- more visits beyond this keep the yield at its ceiling rather than
## climbing further. A single tree in blossom for a few weeks is realistically
## worked by a hive dozens of times over that window; this is comfortably
## inside that range; keep it below PollinatorForaging.MAX_REMEMBERED_VISITS's
## general order of magnitude so it exercises the same real bearing-cycle
## timescale a live game session actually reaches, not an implausible count.
const POLLINATION_SATURATION_VISITS := 20

## `visits`: how many times a bee has landed on this tree so far in the
## current bearing cycle (see ChoppableTree.pollination_visits_in_cycle) --
## a float, not an int, now that an individual bee's own fitness can weight
## one visit as somewhat more or less than 1 (see visit_weight_for_fitness).
## Negative counts (should never happen, but a caller's own bug should not
## propagate here) are treated as zero -- the same floor as never having been
## visited at all.
static func pollination_factor(visits: float) -> float:
	var progress := clampf(
		maxf(visits, 0.0) / float(POLLINATION_SATURATION_VISITS), 0.0, 1.0
	)
	return lerpf(UNPOLLINATED_YIELD_FLOOR, 1.0, progress)


## How much one bee's visit counts toward pollination_factor's visit
## accumulator, scaled by that individual bee's own AnimalFitness.
## fitness_score (0..1) -- AnimalFitness's first real caller here (see
## EarthChunkManager.record_pollination_visit_at / AmbientFlyerMarker's
## bee-landing call site).
##
## A fitter, more vigorous bee genuinely transfers pollen somewhat more
## effectively per visit, but real per-individual variation in pollinator
## foraging efficiency (body size/condition) is a modest fraction, not an
## order of magnitude -- so this stays a gentle +/-15% swing around the flat
## 1.0 every other pollination_factor test already assumes for an average
## bee (fitness 0.5), never enough on its own to meaningfully dent
## POLLINATION_SATURATION_VISITS (20): even the fittest bee's single visit
## (1.15) is 5.75% of that saturation point, not a shortcut to it.
const VISIT_WEIGHT_MIN := 0.85
const VISIT_WEIGHT_MAX := 1.15

static func visit_weight_for_fitness(fitness_score: float) -> float:
	return lerpf(VISIT_WEIGHT_MIN, VISIT_WEIGHT_MAX, clampf(fitness_score, 0.0, 1.0))


## Length in seconds of one full grow->ripen->fall cycle: ONE YEAR, for every
## species, always.
##
## Neither the genome nor the species scales this, and both were tried. The
## species' ripening_multiplier used to scale it, which meant a cherry (0.65)
## ran a bearing cycle two thirds of a year long and a pine (1.8) one nearly
## two years long. The per-species phases below are fractions OF A YEAR --
## cherry ripens at 0.32, early summer -- so applying them to a cycle that is
## not a year put the fruit somewhere new every year. Measured before the fix:
## a cherry shed 24 fruit a year in two windows, the second in the middle of
## WINTER, while a pine shed NOTHING in a year at all (reported: fruit not
## accumulating).
##
## That is the same conflation BEARING_CYCLE_SECONDS was introduced to kill,
## coming back in through a different door. How fast a species ripens is WHEN
## in the year it bears, which ripe_phase_for/fallen_phase_for already say. It
## is not how OFTEN it bears: an apple tree and a pine both fruit once a year,
## in different months.
##
## `genome`, `warmth` and `ripening_multiplier` are all accepted and unread.
## Kept in the signature because per-genome bearing character (an early vs late
## variety) is a plausible thing to reintroduce here deliberately -- but it
## would belong in the PHASES, not in this length.
func _cycle_length(_genome, _warmth: float, _ripening_multiplier: float = 1.0) -> float:
	return BEARING_CYCLE_SECONDS


## How far forward warmth brings the ripening window, as a phase offset.
##
## Only the two ripening phases move; the end of abscission stays pinned to the
## end of autumn, because that boundary is the one thing the calendar decides
## rather than the weather.
static func _earliness(warmth: float) -> float:
	return clampf(warmth, 0.0, 1.0) * WARMTH_EARLINESS


## {growing:int, ripe:int} at a point in time: immature and ripe-hanging counts.
func state_at(
	genome, elapsed_seconds: float, warmth: float,
	yield_multiplier: float = 1.0, ripening_multiplier: float = 1.0
) -> Dictionary:
	var crop := crop_potential(genome, yield_multiplier)
	if crop <= 0:
		return {"growing": 0, "ripe": 0}
	var phase := _phase_at(elapsed_seconds, genome, warmth, ripening_multiplier)
	var window := _window_for(genome, warmth)
	var growing := 0
	if phase < window.grow_end:
		growing = int(round(crop * (phase / maxf(window.grow_end, 0.0001))))
	# The ripe count IS the hanging count -- not a second opinion about it.
	return {
		"growing": growing,
		"ripe": hanging_at(genome, elapsed_seconds, warmth, yield_multiplier, ripening_multiplier),
	}


## How many of this tree's crop are still ON the tree at this moment.
##
## The single source of truth for a crop. What the canopy draws is this number,
## and what falls between two moments is the DECREASE in it (see
## fallen_between) -- so a fruit cannot hit the ground without leaving the tree,
## because falling is leaving the tree.
##
## They used to be computed separately, from windows that disagreed about
## warmth: the displayed window was shifted earlier by `_earliness` and the
## falling window was not, so a tree ripened up to four days before its fruit
## was willing to drop, and cherries hit the ground under a canopy drawn bare
## (reported).
func hanging_at(
	genome, elapsed_seconds: float, warmth: float,
	yield_multiplier: float = 1.0, ripening_multiplier: float = 1.0
) -> int:
	var crop := crop_potential(genome, yield_multiplier)
	if crop <= 0:
		return 0
	var phase := _phase_at(elapsed_seconds, genome, warmth, ripening_multiplier)
	return _hanging_at_phase(crop, phase, _window_for(genome, warmth))


## Whole fruit still hanging at `phase` of the bearing cycle.
##
## Floored rather than rounded, and that matters: the fallen count is the
## difference between two of these, so rounding would let a fruit appear to
## fall and un-fall as the count rounded up and back down.
func _hanging_at_phase(crop: int, phase: float, window: Dictionary) -> int:
	if phase < window.grow_end:
		return 0
	if phase < window.fall_start:
		return crop
	if phase >= window.fall_end:
		return 0
	var remaining: float = 1.0 - (phase - window.fall_start) / maxf(
		window.fall_end - window.fall_start, 0.0001
	)
	return clampi(int(floorf(crop * remaining)), 0, crop)


## The three points of a bearing cycle: ripe, then dropping, then bare.
##
## Warmth can bring the harvest forward, but never before the blossom: a tree
## cannot carry ripe fruit in spring, because in spring it is still flowering.
## Without the clamp a warm-climate cherry ripened at 0.24 -- the last sliver of
## spring -- which is a tree fruiting before it bloomed.
func _window_for(genome, warmth: float) -> Dictionary:
	var species := TreeSpecies.species_for_bias(genome.species_bias)
	var grow_end := maxf(ripe_phase_for(species) - _earliness(warmth), EARLIEST_RIPE_PHASE)
	var fall_end := maxf(fallen_phase_for(species), grow_end + 0.01)
	return {
		"grow_end": grow_end,
		"fall_end": fall_end,
		"fall_start": grow_end + (fall_end - grow_end) * ABSCISSION_FRACTION,
	}


func _phase_at(
	elapsed_seconds: float, genome, warmth: float, ripening_multiplier: float
) -> float:
	var length := _cycle_length(genome, warmth, ripening_multiplier)
	return fposmod(elapsed_seconds, length) / length


## Whether the crop is at genuine PEAK ripeness right now (docs/concept/
## progression.md "Ecological literacy" -- a real, tested definition against
## this model's own output, not an invented calendar band): the plateau after
## the crop has fully ripened (hanging_at has reached its own crop_potential)
## but before any of it has begun to abscise. hanging_at IS the real ripeness
## signal (see this file's own doc comment); peak is simply the stretch where
## it reads at its own maximum -- the instant even one fruit has left the
## tree, ripeness is past its peak. False for an empty crop (crop_potential
## <= 0): there is no peak for nothing to reach.
func is_peak_ripe(
	genome, elapsed_seconds: float, warmth: float,
	yield_multiplier: float = 1.0, ripening_multiplier: float = 1.0
) -> bool:
	var crop := crop_potential(genome, yield_multiplier)
	if crop <= 0:
		return false
	return hanging_at(genome, elapsed_seconds, warmth, yield_multiplier, ripening_multiplier) == crop


## Which fruit of a crop of `crop` left the tree, given that `count` of them
## did.
##
## From the TOP of the order down. Each fruit's position in the canopy comes
## from its index and never moves, so a crop empties one fruit at a time from
## its own scattered positions rather than thinning uniformly -- and the fruit
## that leaves index k is the one that lands under where index k hung, which is
## what makes it the same cherry rather than a new one.
func fallen_indices(crop: int, count: int) -> Array:
	var indices: Array = []
	var taken := clampi(count, 0, maxi(crop, 0))
	for step in taken:
		indices.append(crop - 1 - step)
	return indices


## Ripe fruits that left the tree during (t0, t1].
##
## The DECREASE in the hanging count, not a separate integral over a separate
## window. Computing the two independently is what let a tree drop cherries
## while drawn bare: the windows disagreed about warmth (see hanging_at).
##
## Whole cycles in between are counted in full, so a span longer than a year
## still yields a crop per year rather than only the part-cycle at each end.
func fallen_between(
	genome, t0: float, t1: float, warmth: float,
	yield_multiplier: float = 1.0, ripening_multiplier: float = 1.0
) -> int:
	if t1 <= t0:
		return 0
	var crop := crop_potential(genome, yield_multiplier)
	if crop <= 0:
		return 0
	var length := _cycle_length(genome, warmth, ripening_multiplier)
	var window := _window_for(genome, warmth)

	# Everything shed from time zero up to each end, differenced. Expressed as
	# a cumulative count so that stepping the world in seconds and stepping it
	# in years give the same answer: rounding each step's own increment instead
	# is why nothing ever fell (fruiting steps once a second, and one second of
	# a crop is a ten-thousandth of a fruit, which rounds to zero forever).
	return _shed_by(crop, length, t1, window) - _shed_by(crop, length, t0, window)


## Whole fruit shed from time 0 up to `t` -- a full crop per completed cycle,
## plus however much of the current cycle's crop has already left the tree.
func _shed_by(crop: int, length: float, t: float, window: Dictionary) -> int:
	if t <= 0.0:
		return 0
	var full_cycles := int(floorf(t / length))
	var phase := fposmod(t, length) / length
	# Before it ripens nothing has been shed THIS cycle; the crop that is not
	# hanging yet has not fallen, it has not grown.
	var shed_this_cycle := 0
	if phase >= window.grow_end:
		shed_this_cycle = crop - _hanging_at_phase(crop, phase, window)
	return full_cycles * crop + shed_this_cycle


