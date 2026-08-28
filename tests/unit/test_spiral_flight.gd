extends GutTest

## The butterfly SPIRAL FLIGHT -- two butterflies meeting on a close pass and
## whirling round each other up into the air (see SpiralFlight /
## docs/concept/ecosystem_dynamics.md's "Two butterflies meeting").
##
## This is NOT courtship. It is the investigative/territorial whirl real
## butterflies perform between males, between species and between individuals
## that have already mated -- the thing the player actually reported never
## seeing ("I never see butterfly dance and play with each other when they fly
## by close"). Courtship (rare, same-species, on a real-day cooldown, sometimes
## producing young) is a different behaviour and lives in Courtship.

const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")


# -- who whirls at whom ------------------------------------------------------

## The whole point of the reported behaviour: it happens on a close pass,
## between whoever happens to pass. can_court is same-species-only because a
## monarch and a swallowtail share a meadow and not a lineage -- but they very
## much do chase each other, and a real butterfly will investigate a passing
## bird, a falling leaf, and a thrown pebble too.
func test_two_different_butterflies_still_whirl_at_each_other():
	assert_true(SpiralFlight.can_spiral("monarch", "swallowtail"))
	assert_false(
		Courtship.can_court("monarch", "swallowtail"),
		"precondition: courtship is the same-species one"
	)


func test_a_butterfly_whirls_at_its_own_kind_too():
	assert_true(SpiralFlight.can_spiral("monarch", "monarch"))


## The spiral flight is a LEPIDOPTERAN display. A honeybee's aerial
## interactions are nothing like it (drones congregate far from the meadow,
## workers simply avoid each other at a bloom), and a songbird performing a
## tight two-second corkscrew reads as a bird glitching -- the exact failure
## that got birds excluded from the courtship dance.
func test_bees_and_birds_do_not_spiral():
	for species in ["bee", "sparrow", "robin", "kingfisher", "fly"]:
		assert_false(SpiralFlight.spirals(species), "%s must not spiral" % species)
		assert_false(SpiralFlight.can_spiral(species, "monarch"))


func test_every_true_butterfly_spirals():
	for species in AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL:
		assert_true(SpiralFlight.spirals(species), "%s should spiral" % species)


# -- how far apart they notice each other ------------------------------------

## Real butterflies detect and fly at a passing conspecific from several
## metres -- territorial males of Pararge/Hypolimnas react to intruders at
## roughly 2-6 m, and that reactive approach is precisely what makes the
## behaviour common. Measured in METRES against this project's one yardstick
## (GroundSlide.PX_PER_METER, itself derived from the player's real height),
## never in invented pixels.
func test_the_notice_distance_is_a_real_butterflys_detection_range():
	assert_gte(SpiralFlight.NOTICE_RADIUS_M, 2.0)
	assert_lte(SpiralFlight.NOTICE_RADIUS_M, 6.0)
	assert_almost_eq(
		SpiralFlight.NOTICE_RADIUS_PX,
		SpiralFlight.NOTICE_RADIUS_M * GroundSlide.PX_PER_METER,
		0.001,
		"pixels must be derived from metres, not chosen separately"
	)


## Wider than courtship's, deliberately: a butterfly flies at anything it
## notices, but only pairs off with one it is practically on top of. This is
## also what makes a close pass produce something visible where courtship
## produces nothing.
func test_a_close_pass_is_noticed_from_further_off_than_a_courtship_partner():
	assert_gt(SpiralFlight.NOTICE_RADIUS_PX, Courtship.NOTICE_RADIUS_PX)


# -- how long it lasts, and how often ----------------------------------------

func test_the_spiral_is_over_in_a_second_or_two():
	assert_gte(SpiralFlight.SPIRAL_SECONDS, 1.0, "shorter than this and nobody sees it")
	assert_lte(SpiralFlight.SPIRAL_SECONDS, 4.0, "a passing tussle, not a performance")
	assert_lt(
		SpiralFlight.SPIRAL_SECONDS, Courtship.DANCE_SECONDS,
		"the passing whirl must be the shorter of the two"
	)


## The constraint that sets the gap between bouts is a real TIME BUDGET, not a
## chosen number: field studies of territorial butterflies put roughly 5-15%
## of active time into aerial interactions, and an animal that spends more
## than that whirling does not feed enough. The cooldown is derived from the
## duty cycle and the spiral's own length, so the two cannot drift apart.
func test_a_butterfly_spends_a_real_time_budget_on_this_not_all_day():
	assert_gte(SpiralFlight.SPIRAL_DUTY_CYCLE, 0.05)
	assert_lte(SpiralFlight.SPIRAL_DUTY_CYCLE, 0.15)
	var cycle: float = SpiralFlight.SPIRAL_SECONDS + SpiralFlight.COOLDOWN_SECONDS
	assert_almost_eq(
		SpiralFlight.SPIRAL_SECONDS / cycle, SpiralFlight.SPIRAL_DUTY_CYCLE, 0.001,
		"the cooldown must BE the duty cycle, not merely agree with it"
	)


## The reported behaviour has to read as COMMON. It must not inherit the
## breeding cooldown, which is a full real day and exists to bound the
## POPULATION -- a spiral flight produces nothing, so nothing about it needs
## bounding on that scale.
func test_the_whirl_does_not_wait_on_the_breeding_cooldown():
	assert_lt(SpiralFlight.COOLDOWN_SECONDS, 60.0, "a player must see it more than once a minute")
	assert_lt(SpiralFlight.COOLDOWN_SECONDS, LifeCycle.MATE_SECONDS / 1000.0)
	assert_lt(SpiralFlight.COOLDOWN_SECONDS, Courtship.COOLDOWN_SECONDS / 1000.0)


# -- the shape of it ---------------------------------------------------------

## No teleport. Courtship snaps both partners onto a fixed-radius orbit the
## instant it starts, which is a visible jump of up to a body length; the
## spiral instead starts from exactly where the flyer already is and closes in
## from there, which is what "they flew at each other" has to look like.
func test_the_spiral_begins_exactly_where_the_flyer_already_is():
	var start := Vector2(17.0, -6.0)
	assert_almost_eq(SpiralFlight.offset(0.0, start).x, start.x, 0.001)
	assert_almost_eq(SpiralFlight.offset(0.0, start).y, start.y, 0.001)


func test_the_pair_whirl_round_each_other():
	var start := Vector2(20.0, 0.0)
	var angles := {}
	for step in 24:
		var elapsed := float(step) * SpiralFlight.SPIRAL_SECONDS / 24.0
		var here := SpiralFlight.offset(elapsed, start)
		# The climb is a shared translation, so the WHIRL is what is left once
		# it is taken back out.
		angles[snappedf((here - SpiralFlight.rise(elapsed)).angle(), 0.3)] = true
	assert_gt(angles.size(), 8, "it has to actually go round, several times")


## Two butterflies whirling read as two only if they stay opposite each other.
## Nothing has to agree at runtime for that: each side starts from its own
## offset to the shared midpoint, and those are already exactly opposite.
func test_the_two_stay_on_opposite_sides_of_the_axis_they_climb():
	var start := Vector2(13.0, 4.0)
	for step in 12:
		var elapsed := float(step) * SpiralFlight.SPIRAL_SECONDS / 12.0
		var mine := SpiralFlight.offset(elapsed, start) - SpiralFlight.rise(elapsed)
		var theirs := SpiralFlight.offset(elapsed, -start) - SpiralFlight.rise(elapsed)
		assert_lt(
			mine.normalized().dot(theirs.normalized()), -0.99,
			"the pair must stay across the axis from one another"
		)


## The recognisable part of the real behaviour: they go UP. Screen-up is -Y in
## this top-down world, and both partners rise together, so the pair reads as
## two butterflies chasing each other into the air rather than two sprites
## circling a patch of grass.
func test_the_pair_climb_while_they_whirl():
	var start := Vector2(10.0, 0.0)
	var previous := 1.0
	for step in 20:
		var elapsed := float(step) * SpiralFlight.SPIRAL_SECONDS / 20.0
		var height := -SpiralFlight.rise(elapsed).y
		assert_gte(height, previous - 1.0, "the climb must not reverse")
		previous = height
	assert_almost_eq(
		-SpiralFlight.rise(SpiralFlight.SPIRAL_SECONDS).y, SpiralFlight.RISE_PX, 0.001
	)


## Real spiral flights carry the pair a metre or three above the vegetation.
## Kept to the low end of that so the climb stays inside the flyer's own
## wander radius -- a whirl that flung a butterfly off its territory would
## leave it fighting its own home tether all the way back down.
func test_the_climb_is_real_but_stays_inside_the_butterflys_territory():
	assert_gte(SpiralFlight.RISE_M, 1.0)
	assert_lte(SpiralFlight.RISE_M, 3.0)
	assert_lt(
		SpiralFlight.RISE_PX, AmbientFlyerRenderer.BUTTERFLY_RADIUS,
		"the climb must not exceed the flyer's own home tether"
	)


# -- why it looks different from courtship -----------------------------------

## Derived, not chosen: the whirl rate is a real burst flight speed divided by
## the circumference of the circle the flyer is actually flying. A butterfly
## in a spiral flight is at maximum exertion, not cruising.
func test_the_whirl_rate_is_a_real_burst_flight_speed():
	assert_gte(SpiralFlight.BURST_SPEED_MPS, 3.0, "slower than this is a cruise")
	assert_lte(SpiralFlight.BURST_SPEED_MPS, 6.0, "faster than this is not a butterfly")
	assert_almost_eq(
		TAU * SpiralFlight.SPIRAL_RADIUS_M * SpiralFlight.TURNS_PER_SECOND,
		SpiralFlight.BURST_SPEED_MPS,
		0.001,
		"turns per second must BE speed / circumference"
	)


func test_the_whirl_is_visibly_faster_than_the_courtship_dance():
	assert_gt(
		SpiralFlight.TURNS_PER_SECOND, 2.0 * Courtship.DANCE_TURNS_PER_SECOND,
		"the passing whirl and the courtship glide must not look alike"
	)


## Tighter than the courtship orbit, and still two sprites. Real spiral
## flights hold the pair within roughly half a metre to a metre of each other
## -- much closer than the wide, slow courtship flight -- and at this game's
## scale that is still comfortably more than a butterfly is wide.
func test_the_pair_close_to_a_separation_that_still_reads_as_two():
	var drawn_width := (
		float(ProceduralButterflySprite.SIZE.x)
		* ArtResolution.SPRITE_SCALE
		* FishRenderer.FISH_WORLD_SCALE
		* float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["monarch"])
	)
	var separation := 2.0 * SpiralFlight.SPIRAL_RADIUS_PX
	assert_gt(separation, drawn_width, "closer than one butterfly wide is one blob")
	assert_lt(
		separation, 2.0 * Courtship.DANCE_RADIUS_PX,
		"the whirl must be visibly TIGHTER than the courtship orbit"
	)
	assert_gte(SpiralFlight.SPIRAL_SEPARATION_M, 0.3)
	assert_lte(SpiralFlight.SPIRAL_SEPARATION_M, 1.0)


func test_the_pair_converge_from_wherever_they_happened_to_meet():
	var start := Vector2(SpiralFlight.NOTICE_RADIUS_PX * 0.5, 0.0)
	var ended := SpiralFlight.offset(SpiralFlight.SPIRAL_SECONDS, start)
	var horizontal := (ended - SpiralFlight.rise(SpiralFlight.SPIRAL_SECONDS)).length()
	assert_almost_eq(horizontal, SpiralFlight.SPIRAL_RADIUS_PX, 0.001)
	assert_lt(horizontal, start.length(), "they must close on each other, not drift apart")


# -- and what it deliberately cannot do --------------------------------------

## A spiral flight is not a mating. Nothing here decides an outcome, so
## nothing downstream can turn one into an offspring even by mistake -- the
## population bound lives entirely in Courtship/LifeCycle and this behaviour
## is free to be as common as the real thing precisely because it is inert.
## Every butterfly in a chunk loads at the same instant, so without a stagger
## a whole club whirls on one frame, falls silent for exactly
## COOLDOWN_SECONDS together, and whirls together again -- a choreographed
## meadow, the same complaint already logged against pollinator routing ("not
## all bees and butterflies fly the same route following each other").
##
## Uniform over the cooldown is not a fudge: it is the stationary
## distribution of "this butterfly last whirled at some point in the past
## cycle", which is the truth about an animal that did not come into
## existence when the chunk loaded.
func test_a_freshly_loaded_club_does_not_whirl_in_lockstep():
	var seen := {}
	for seed_value in 200:
		var stagger := SpiralFlight.stagger_seconds(seed_value)
		assert_gte(stagger, 0.0)
		assert_lt(stagger, SpiralFlight.COOLDOWN_SECONDS)
		seen[snappedf(stagger, 0.5)] = true
	assert_gt(seen.size(), 20, "the stagger has to actually spread them out")


func test_the_stagger_is_deterministic_per_flyer():
	assert_eq(SpiralFlight.stagger_seconds(77), SpiralFlight.stagger_seconds(77))
	assert_ne(SpiralFlight.stagger_seconds(77), SpiralFlight.stagger_seconds(78))


func test_nothing_here_can_produce_offspring():
	var module = SpiralFlight.new()
	for forbidden in ["mates", "pair_seed", "leads"]:
		assert_false(
			module.has_method(forbidden),
			"a spiral flight must have no %s -- it is not a pairing" % forbidden
		)


# -- the orbit primitive, shared with the player dance ------------------------

## The whirl geometry, split out of offset() so the SAME shape can be flown
## round something that is not another butterfly. A bold butterfly orbiting a
## player's head (see FlyerPersonality) is this behaviour aimed at a different
## object -- which is already this module's own grounding, since real
## territorial butterflies launch at conspecifics, birds, leaves and thrown
## pebbles alike. Reusing it is what stops there being a third dance shape in
## the game with a third set of constants to justify.


func test_the_orbit_starts_exactly_where_the_flyer_already_is():
	var start := Vector2(11.0, -4.0)
	var at_zero := SpiralFlight.converging_orbit(
		0.0, start, SpiralFlight.SPIRAL_RADIUS_PX, 1.0
	)
	assert_almost_eq(
		at_zero.distance_to(start), 0.0, 0.001, "nothing may teleport when an orbit begins"
	)


func test_the_orbit_closes_onto_the_radius_it_was_given():
	var start := Vector2(40.0, 0.0)
	var wanted := 7.5
	var at_end := SpiralFlight.converging_orbit(
		SpiralFlight.SPIRAL_SECONDS, start, wanted, 1.0
	)
	assert_almost_eq(at_end.length(), wanted, 0.001)


## The one real difference from offset(): a whirl between two butterflies is
## over in SPIRAL_SECONDS, but an orbit round a player lasts as long as the
## player stands there. A clamped angle would freeze the dance mid-circle with
## the butterfly hanging at one point of it.
func test_the_orbit_keeps_turning_after_a_two_butterfly_whirl_would_have_ended():
	var start := Vector2(10.0, 0.0)
	var quarter_later := 0.25 / SpiralFlight.TURNS_PER_SECOND
	var at_end := SpiralFlight.converging_orbit(
		SpiralFlight.SPIRAL_SECONDS, start, SpiralFlight.SPIRAL_RADIUS_PX,
		SpiralFlight.TURNS_PER_SECOND
	)
	var later := SpiralFlight.converging_orbit(
		SpiralFlight.SPIRAL_SECONDS + quarter_later, start, SpiralFlight.SPIRAL_RADIUS_PX,
		SpiralFlight.TURNS_PER_SECOND
	)
	assert_gt(at_end.distance_to(later), SpiralFlight.SPIRAL_RADIUS_PX, "it must still be moving")


## The two-butterfly whirl is exactly this primitive plus the climb -- there
## is one geometry here, not two that have to be kept in step by hand.
func test_the_two_butterfly_whirl_is_that_orbit_plus_the_climb():
	var start := Vector2(-6.0, 9.0)
	for tenth in 30:
		var elapsed := float(tenth) * 0.1
		var held: float = clampf(elapsed, 0.0, SpiralFlight.SPIRAL_SECONDS)
		var rebuilt: Vector2 = SpiralFlight.converging_orbit(
			held, start, SpiralFlight.SPIRAL_RADIUS_PX, SpiralFlight.TURNS_PER_SECOND
		) + SpiralFlight.rise(held)
		assert_almost_eq(SpiralFlight.offset(elapsed, start).distance_to(rebuilt), 0.0, 0.0001)
