extends GutTest

## Per-individual flyer PERSONALITY -- a heritable boldness trait, and what a
## butterfly does about the player because of it (see FlyerPersonality /
## docs/concept/ecosystem_dynamics.md's "The butterfly that knows you").
##
## The headline claim these tests exist to prove is an EMERGENT one, not a
## scripted one: nothing anywhere decides "the meadow should get shyer". A
## player who nets every butterfly that comes to dance around their head is
## simply removing the bold half of the gene pool before it breeds, and shy
## parents make shy children through the SHIPPED DnaCrossover. The meadow
## learning to avoid that player is arithmetic, not a rule --
## test_a_meadow_the_player_nets_the_bold_out_of_grows_shy_over_generations is
## the whole feature.

const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")
const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")


# -- the trait itself --------------------------------------------------------


## Deterministic from the individual: the same butterfly is always the same
## butterfly. This is what lets personality survive a chunk unload/reload
## without being stored anywhere -- `wander_seed` is already derived from the
## flyer's own world cell (see AmbientFlyerRenderer._spawn_species), so the
## butterfly that comes back is the one that left.
func test_the_same_seed_is_always_the_same_butterfly():
	var once := FlyerPersonality.traits_from_seed(90210)
	var again := FlyerPersonality.traits_from_seed(90210)
	assert_eq(once, again)


func test_different_butterflies_have_different_personalities():
	var distinct := {}
	for i in 50:
		distinct[FlyerPersonality.boldness_of(FlyerPersonality.traits_from_seed(i))] = true
	assert_gt(distinct.size(), 40, "50 butterflies must not share a handful of personalities")


func test_boldness_is_always_a_real_fraction():
	for i in 500:
		var boldness := FlyerPersonality.boldness_of(FlyerPersonality.traits_from_seed(i * 7919))
		assert_between(boldness, 0.0, 1.0)


## A flyer whose traits were never filled in (a marker built by hand in a
## test, a diorama bird) must still answer the question, and must answer it
## with the unremarkable middle -- not with an accidental 0.0, which is the
## shyest possible animal and would have every hand-placed butterfly bolting
## from the player.
func test_a_flyer_with_no_traits_is_an_average_one():
	assert_almost_eq(FlyerPersonality.boldness_of({}), FlyerPersonality.MIDDLING_BOLDNESS, 0.001)


# -- the distribution --------------------------------------------------------


## "Most butterflies should do neither dramatically; the extremes should be
## noticeable and uncommon."
##
## Boldness is the mean of two independent uniform halves, which is the
## triangular distribution -- bounded to [0,1] by construction, peaked in the
## middle, thin at both ends. Both rejected alternatives are pinned by what
## this test measures: a single uniform hash would make the extremes exactly
## as common as the middle, and a clamped Gaussian would pile probability UP
## at the two ends, making the extremes commoner than the middle rather than
## rarer.
func test_most_butterflies_are_middling_and_the_extremes_are_rare():
	var samples := 4000
	var total := 0.0
	var middle := 0
	var extreme := 0
	for i in samples:
		var boldness := FlyerPersonality.boldness_of(
			FlyerPersonality.traits_from_seed(hash("distribution_%d" % i))
		)
		total += boldness
		if absf(boldness - 0.5) <= 0.25:
			middle += 1
		if boldness <= 0.1 or boldness >= 0.9:
			extreme += 1
	assert_almost_eq(total / float(samples), 0.5, 0.02, "the population must sit in the middle")
	assert_gt(float(middle) / float(samples), 0.6, "most butterflies are unremarkable")
	assert_lt(float(extreme) / float(samples), 0.1, "the extremes must be uncommon")
	assert_gt(float(extreme) / float(samples), 0.005, "...but not so rare nobody ever sees one")


## The dance is meant to be a thing you notice, not a thing you never see:
## a meadow holds hundreds of butterflies (266 were counted in one), so even a
## few percent is several of them.
func test_a_meadow_full_of_butterflies_holds_a_few_that_will_dance_at_you():
	var meadow := 266
	var dancers := 0
	for i in meadow:
		if FlyerPersonality.is_bold_enough_to_dance(
			FlyerPersonality.boldness_of(FlyerPersonality.traits_from_seed(hash("meadow_%d" % i)))
		):
			dancers += 1
	assert_between(dancers, 1, 40, "a meadow's dancers: uncommon, but present")


# -- flight initiation distance ----------------------------------------------


## Flight initiation distance (FID) is a real, measured quantity: how close a
## predator/human gets before the animal breaks and flies. Butterfly FIDs are
## measured in the low metres, and the SHYEST individual is the top of that
## band -- which is the endpoint this constant is.
func test_the_shyest_butterfly_flushes_from_metres_away():
	var shy := FlyerPersonality.flight_initiation_distance_px(0.0)
	assert_almost_eq(
		shy / GroundSlide.PX_PER_METER, FlyerPersonality.SHYEST_FLUSH_DISTANCE_M, 0.001
	)
	assert_between(
		shy / GroundSlide.PX_PER_METER, 1.0, 4.0, "real butterfly FIDs are in the low metres"
	)


## The other endpoint is not "flees from very close" but "does not flee".
## Bold individuals of many taxa have effectively no flight response to a
## human -- they can be walked up to and, in a butterfly's case, landed on by
## hand. Without a zero endpoint the boldest butterfly would still bolt at the
## exact moment it was supposed to be dancing round the player's head.
func test_the_boldest_butterfly_does_not_flush_at_all():
	assert_almost_eq(FlyerPersonality.flight_initiation_distance_px(1.0), 0.0, 0.001)


func test_bolder_always_means_it_lets_you_closer():
	var previous := FlyerPersonality.flight_initiation_distance_px(0.0)
	for step in range(1, 21):
		var here := FlyerPersonality.flight_initiation_distance_px(float(step) / 20.0)
		assert_lt(here, previous, "FID must fall with boldness at every step")
		previous = here


## A butterfly cannot flush from something it has not noticed. SpiralFlight
## already owns the real "how far off a butterfly reacts to a passing object"
## number (4 m -- territorial butterflies launch at conspecifics, birds,
## leaves and thrown pebbles from several metres), so the shyest possible
## flush has to fit inside it or the two would be describing different worlds.
func test_the_shyest_butterfly_flushes_from_inside_the_distance_it_can_notice_the_player():
	assert_lt(
		FlyerPersonality.flight_initiation_distance_px(0.0), SpiralFlight.NOTICE_RADIUS_PX
	)


# -- what it does about the player -------------------------------------------


func test_a_shy_butterfly_flees_a_player_that_comes_close():
	var response := FlyerPersonality.player_response(0.0, GroundSlide.PX_PER_METER * 1.0)
	assert_eq(response, FlyerPersonality.FLEE)


func test_a_shy_butterfly_ignores_a_player_that_stays_away():
	var response := FlyerPersonality.player_response(0.0, SpiralFlight.NOTICE_RADIUS_PX * 2.0)
	assert_eq(response, FlyerPersonality.NONE)


func test_a_bold_butterfly_comes_and_dances_round_the_player():
	assert_eq(
		FlyerPersonality.player_response(1.0, SpiralFlight.NOTICE_RADIUS_PX * 0.9),
		FlyerPersonality.DANCE
	)


func test_an_ordinary_butterfly_does_neither_at_arms_length():
	assert_eq(
		FlyerPersonality.player_response(0.5, SpiralFlight.NOTICE_RADIUS_PX * 0.9),
		FlyerPersonality.NONE,
		"the middle of the population must not react dramatically"
	)


## The two responses are the two ends of ONE continuum and must never both be
## live for the same animal. The threshold is DERIVED from exactly that: a
## butterfly may only be counted bold enough to dance once its own FID has
## fallen below the radius it would be orbiting at (SpiralFlight's, reused --
## a butterfly holds the same distance from a thing it is investigating
## whether that thing is another butterfly or a head). Anything shyer would
## be fleeing from inside its own dance.
func test_nothing_ever_both_flees_and_dances():
	for step in 101:
		var boldness := float(step) / 100.0
		if not FlyerPersonality.is_bold_enough_to_dance(boldness):
			continue
		assert_lt(
			FlyerPersonality.flight_initiation_distance_px(boldness),
			SpiralFlight.SPIRAL_RADIUS_PX,
			"a dancer at boldness %f would flee from inside its own orbit" % boldness
		)


func test_the_dance_threshold_is_derived_from_the_orbit_it_dances_at():
	var threshold := FlyerPersonality.DANCE_BOLDNESS_THRESHOLD
	assert_almost_eq(
		FlyerPersonality.flight_initiation_distance_px(threshold),
		SpiralFlight.SPIRAL_RADIUS_PX,
		0.001,
		"the threshold IS the boldness whose FID equals the orbit radius"
	)


# -- how fast it runs away ---------------------------------------------------


## An escape is maximum exertion, not a cruise. The multiplier is the REAL
## ratio between the two -- a monarch cruises around 2 m/s and a burst tops
## out near 5 m/s (SpiralFlight already owns that burst figure) -- rather than
## an absolute speed, because this world's butterfly cruise is its own
## stylised number (AmbientFlyerRenderer.BUTTERFLY_SPEED) and an absolute
## 5 m/s dropped on top of it would read as a teleport.
func test_fleeing_is_a_burst_not_a_cruise():
	assert_almost_eq(
		FlyerPersonality.ESCAPE_SPEED_MULTIPLIER,
		SpiralFlight.BURST_SPEED_MPS / FlyerPersonality.CRUISE_SPEED_MPS,
		0.0001
	)
	assert_gt(FlyerPersonality.ESCAPE_SPEED_MULTIPLIER, 1.0)


## Escape does not stop at the line it started on. In the escape-distance
## literature an animal that flushes at its FID puts about that much distance
## again between itself and the threat before settling, so the release
## distance is FID + distance-fled rather than a hysteresis fudge picked to
## stop the flee/don't-flee decision chattering at the boundary (which it also
## happens to prevent).
func test_a_fleeing_butterfly_keeps_going_past_the_line_it_flushed_at():
	for boldness in [0.0, 0.2, 0.4]:
		var flush := FlyerPersonality.flight_initiation_distance_px(boldness)
		assert_gt(FlyerPersonality.flee_release_distance_px(boldness), flush)


# -- heritability ------------------------------------------------------------


func test_a_child_of_two_bold_parents_is_bold():
	var bold_a := {FlyerPersonality.TRAIT_BOLDNESS: 0.9}
	var bold_b := {FlyerPersonality.TRAIT_BOLDNESS: 0.95}
	for i in 20:
		var child := FlyerPersonality.inherit(bold_a, bold_b, i)
		assert_gt(FlyerPersonality.boldness_of(child), 0.8)


func test_a_child_of_two_shy_parents_is_shy():
	var shy_a := {FlyerPersonality.TRAIT_BOLDNESS: 0.1}
	var shy_b := {FlyerPersonality.TRAIT_BOLDNESS: 0.05}
	for i in 20:
		var child := FlyerPersonality.inherit(shy_a, shy_b, i)
		assert_lt(FlyerPersonality.boldness_of(child), 0.2)


## A child is never an exact copy of a parent -- DnaCrossover's own mutation
## nudge is what keeps a lineage from freezing, and it is the SHIPPED
## crossover doing it, not a second one written here.
func test_a_child_is_never_exactly_either_parent():
	var a := {FlyerPersonality.TRAIT_BOLDNESS: 0.3}
	var b := {FlyerPersonality.TRAIT_BOLDNESS: 0.7}
	for i in 20:
		var child_boldness := FlyerPersonality.boldness_of(FlyerPersonality.inherit(a, b, i))
		assert_ne(child_boldness, 0.3)
		assert_ne(child_boldness, 0.7)


# -- the emergent payoff -----------------------------------------------------

## How many butterflies the simulated meadow holds, and for how many
## generations the player works it. Simulation parameters, not game constants:
## the meadow is the size of a real one (266 butterflies were counted in a
## single loaded meadow) and is big enough that the measured shift is many
## times the sampling noise of a mean over it.
const MEADOW := 266
const GENERATIONS := 10

## How close the player has to be to swing a net over a butterfly. A butterfly
## net's hoop sits about a metre from the hand, so a person standing still can
## reach roughly that far past themselves. Grounded here rather than in
## FlyerPersonality because it is a property of the PLAYER's tool, not of the
## butterfly -- and because nothing in the live game swings it yet (see
## FlyerPersonality's own "who calls this, honestly").
const NET_REACH_PX := GroundSlide.PX_PER_METER * 1.0


func _founding_meadow(salt: String) -> Array:
	var meadow: Array = []
	for i in MEADOW:
		meadow.append(FlyerPersonality.traits_from_seed(hash("%s_%d" % [salt, i])))
	return meadow


func _mean_boldness(meadow: Array) -> float:
	var total := 0.0
	for individual in meadow:
		total += FlyerPersonality.boldness_of(individual)
	return total / float(meadow.size())


## Whoever is left pairs off and breeds a whole new meadow, through the
## SHIPPED DnaCrossover (see FlyerPersonality.inherit) -- the exact path a
## courting pair's offspring takes in the live game (see
## AmbientFlyerMarker._finish_courtship). Non-overlapping generations, so
## "several generations later" means what it says and no founder is still
## sitting in the population at the end propping the average up.
##
## Both parents are picked at random from the survivors rather than off
## neighbouring array slots. Pairing slot i with slot i+1 was tried first and
## measured: it makes every pair of consecutive offspring share a parent, so
## lineages are lost fast and the meadow DRIFTS -- 0.041 of undisturbed drift
## over these ten generations, a third of the whole effect being measured.
## That is real genetic drift, but it is drift out of an artificial mating
## structure (butterflies do not court the individual next to them in an
## array), and it was swamping the signal.
func _next_generation(survivors: Array, generation: int) -> Array:
	var meadow: Array = []
	var count := survivors.size()
	for i in MEADOW:
		var first := absi(hash("mate_a_%d_%d" % [generation, i])) % count
		var second := absi(hash("mate_b_%d_%d" % [generation, i])) % count
		if second == first:
			second = (first + 1) % count
		meadow.append(FlyerPersonality.inherit(
			survivors[first], survivors[second], hash("child_%d_%d" % [generation, i])
		))
	return meadow


## The only thing the player does: walk the meadow and swing at whatever is
## still within reach when they get there. What decides who that is, is the
## SAME player_response the live marker steers on -- a butterfly that flushed
## is a metre and more away by the time the net arrives, and everything that
## did not flush is in it. There is no rule here about boldness at all.
func _escaped_the_net(individual: Dictionary) -> bool:
	return FlyerPersonality.player_response(
		FlyerPersonality.boldness_of(individual), NET_REACH_PX
	) == FlyerPersonality.FLEE


func _worked_meadow(salt: String, keep_the_ones_that_flee: bool) -> Array:
	var meadow := _founding_meadow(salt)
	var trace: Array = [_mean_boldness(meadow)]
	for generation in GENERATIONS:
		var survivors: Array = []
		for individual in meadow:
			if _escaped_the_net(individual) == keep_the_ones_that_flee:
				survivors.append(individual)
		assert_gt(survivors.size(), 1, "the meadow must not be wiped out")
		meadow = _next_generation(survivors, generation)
		trace.append(_mean_boldness(meadow))
	return trace


## THE feature. Nothing anywhere says "get shyer".
##
## The control run inside the same test is what makes the number mean
## anything: identical founders, identical breeding, identical generation
## count, nobody swinging a net. If an undisturbed meadow drifted as far, the
## drop would be an artefact of DnaCrossover rather than a response to the
## player -- so the assertion is against the DRIFT, measured here, and not
## against a tolerance somebody liked the look of.
func test_a_meadow_the_player_nets_the_bold_out_of_grows_shy_over_generations():
	var netted := _worked_meadow("meadow", true)
	var undisturbed := _founding_meadow("meadow")
	var start := _mean_boldness(undisturbed)
	for generation in GENERATIONS:
		undisturbed = _next_generation(undisturbed, generation)
	var drift: float = absf(_mean_boldness(undisturbed) - start)
	var shift: float = netted[0] - netted[netted.size() - 1]

	gut.p("netted meadow mean boldness by generation: %s" % [netted])
	gut.p("undisturbed meadow drifted %f over the same %d generations" % [drift, GENERATIONS])

	assert_lt(
		netted[netted.size() - 1],
		netted[0],
		"a meadow whose bold butterflies are netted must end up shyer than it started"
	)
	assert_gt(shift, drift * 5.0, "and by far more than an untouched meadow drifts")
	assert_gt(shift, 0.1, "the shift has to be big enough to be a thing the player notices")


## The falsifiable half. NO player behaviour does this -- a net cannot catch
## the butterflies that flew away and miss the ones sitting still. It is here
## because if the machinery could only ever push boldness DOWN, the result
## above would be a decay hiding in the crossover rather than selection. Run
## the same pressure the other way round and the meadow gets bolder.
func test_the_same_pressure_pointed_the_other_way_makes_the_meadow_bolder():
	var trace := _worked_meadow("meadow", false)
	gut.p("inverted pressure mean boldness by generation: %s" % [trace])
	assert_gt(trace[trace.size() - 1], trace[0] + 0.1)


# -- which flyers have a personality at all ----------------------------------


## Personality steering is a BUTTERFLY behaviour, the same roster that already
## whirls (SpiralFlight.spirals). A sparrow that bolted from the player would
## be a second, unrelated flight-response system bolted onto a bird that
## already has none, and a bee orbiting a head is not a thing bees do.
func test_only_the_true_butterflies_react_to_the_player():
	for species in AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL:
		assert_true(FlyerPersonality.reacts_to_player(species), "%s should react" % species)
	for species in ["bee", "fly", "sparrow", "robin", "kingfisher"]:
		assert_false(FlyerPersonality.reacts_to_player(species), "%s should not" % species)
