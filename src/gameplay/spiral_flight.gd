extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const FlightIrregularity = preload("res://src/gameplay/flight_irregularity.gd")

## Two butterflies meeting on a close pass and whirling round each other up
## into the air -- the SPIRAL FLIGHT (see
## docs/concept/ecosystem_dynamics.md's "Two butterflies meeting").
##
## ## What this is, and what it deliberately is not
##
## This is the single most recognisable thing butterflies do, and it is not
## courtship. When two butterflies meet they fly at each other and corkscrew
## rapidly upward for a second or two before breaking off. Real lepidopterists
## call it a spiral flight or an ascending flight, and it happens **between
## males, between different species, and between individuals that have already
## mated** -- it is investigative and territorial, not a pairing.
##
## Courtship (see Courtship) is the other one: same species only, a slow wide
## orbit, a cooldown of a full real day, and sometimes an egg. The player
## reported never seeing butterflies interact at all ("I never see butterfly
## dance and play with each other when they fly by close"), and courtship
## alone could never have satisfied that -- it is deliberately rare, and it
## was also geometrically starved (see FlyerSpawnLayout).
##
## So this behaviour is built to be the COMMON one: a wider notice radius,
## cross-species, seconds long, on a cooldown measured in seconds rather than
## days, and producing **nothing**. That last part is what lets it be common
## safely: the population bound lives entirely in Courtship/LifeCycle, and a
## behaviour with no outcome needs no bound. There is deliberately no `mates`,
## no `pair_seed` and no `leads` here, and
## test_nothing_here_can_produce_offspring pins their absence.
##
## Pure and engine-free like the rest of the behaviour modules: this decides
## WHO whirls and WHERE the whirl puts them. Driving it is
## AmbientFlyerMarker._step_spiral_flight's job, which is the only caller.

## World pixels per real metre -- this project's one yardstick, derived from
## the player's real height (see GroundSlide.PX_PER_METER). Every distance
## below is stated in METRES and converted here, so none of them is a pixel
## count somebody liked the look of.
const PX_PER_METER := GroundSlide.PX_PER_METER

## How far off a butterfly notices another and flies at it.
##
## Real: territorial butterflies react to a passing intruder from several
## metres -- Pararge aegeria and Hypolimnas males launch at conspecifics
## (and at passing birds, leaves and thrown pebbles) from roughly 2-6 m.
## That reactive approach is exactly what makes the behaviour common, and it
## is deliberately WIDER than Courtship.NOTICE_RADIUS_PX: a butterfly flies
## at anything it notices, but only pairs off with one it is practically on
## top of.
const NOTICE_RADIUS_M := 4.0
const NOTICE_RADIUS_PX := NOTICE_RADIUS_M * PX_PER_METER

## How long the whirl lasts. Real spiral flights between two passing
## individuals are over in a second or two -- genuine territorial contests
## can run much longer, but those are a different, rarer thing and modelling
## them would make the common case unwatchable.
const SPIRAL_SECONDS := 2.0

## How far apart the pair hold each other while they climb, in metres.
##
## Real spiral flights keep the two within about half a metre to a metre --
## visibly TIGHTER than the wide, slow courtship flight, which is half of
## what makes the two read as different behaviours at a glance.
##
## That "half a metre to a metre" is a RANGE, and the range is the
## observation. Drawing it as one fixed number was drawing a perfect circle,
## which is exactly what the player saw ("only a circle"). The nominal below
## is the middle of the pair's working separation; the orbit breathes across
## the whole band (see RADIUS_SWING).
const SPIRAL_SEPARATION_MIN_M := 0.5
const SPIRAL_SEPARATION_MAX_M := 1.0
const SPIRAL_SEPARATION_M := 0.7
const SPIRAL_RADIUS_M := SPIRAL_SEPARATION_M * 0.5
const SPIRAL_RADIUS_PX := SPIRAL_RADIUS_M * PX_PER_METER

## How far the radius may swing either side of nominal, as a fraction.
##
## DERIVED from the observed band above rather than chosen: the orbit is
## modelled as r(t) = r0 / (1 + k*w(t)) with w in [-1, 1] (see
## converging_orbit for why that form and not r0 * (1 + k*w)), so the widest
## the pair ever get is r0 / (1 - k). Setting that equal to half of
## SPIRAL_SEPARATION_MAX_M is what fixes k. The tight side then comes out at
## r0 / (1 + k), and the test pins that this is still no closer than
## SPIRAL_SEPARATION_MIN_M -- i.e. the swing uses the real band and does not
## leave it at either end.
const RADIUS_SWING := 1.0 - SPIRAL_SEPARATION_M / SPIRAL_SEPARATION_MAX_M

## The tightest the pair ever whirl. The hardest moment of the turn, and so
## the one the load ceiling below has to be honoured at.
const TIGHTEST_RADIUS_M := SPIRAL_RADIUS_M / (1.0 + RADIUS_SWING)

## How fast a butterfly flies in one of these IN A STRAIGHT LINE. A spiral
## flight is maximum exertion, not a cruise: a monarch cruises around 2 m/s
## and tops out near 5 m/s, and the whirl is the top end.
const BURST_SPEED_MPS := 5.0

## The hardest a butterfly can turn, as a multiple of its own weight.
##
## NOT a new number: it is the lift ceiling this game already derived, in
## WingbeatBounce. A turn is flown by banking, so the wings have to make
## enough lift to hold the body up AND supply the centripetal force; the load
## factor is exactly how many times body weight that is. WingbeatBounce's
## whole amplitude derivation stands on the fact that a wing cannot pull the
## body DOWN through its stroke, so the lift swings about weight with relative
## depth e <= 1 -- which puts peak lift at (1 + e) x weight, at most twice.
##
## Held here as a literal rather than imported because src/gameplay does not
## depend on src/rendering (see PollinatorForaging's own note on the same
## point); the two are pinned equal by
## test_the_load_ceiling_is_the_lift_ceiling_this_game_already_derived.
const MAX_LOAD_FACTOR := 1.0 + 1.0

## How fast the flyer actually goes ROUND, in metres per second.
##
## The burst speed is what it can do in a straight line; this is what it can
## do round a 35 cm circle, and they are not the same thing. Flying the full
## 5 m/s burst round SPIRAL_RADIUS_M demands v^2/r = 71 m/s^2 of centripetal
## acceleration -- over seven g. Nothing with wings pulls seven g, and the
## result on screen was a butterfly whipping round a nine-pixel circle twice a
## second: reported as "the dance is overly dramatic".
##
## So the TURN limits this, not the wing: v = sqrt(a_max * r), evaluated at
## the tightest point of the breathing orbit so the ceiling holds throughout
## rather than only on average. Comes out around half the old rate, which is
## the drama fix -- and it is a correction rather than a taste change: the old
## number was flying a manoeuvre the animal cannot fly.
const ORBIT_SPEED_MPS := sqrt(MAX_LOAD_FACTOR * GroundSlide.GRAVITY_MPS2 * TIGHTEST_RADIUS_M)

## Turns per second at the nominal radius, DERIVED rather than chosen: the
## orbital speed divided by the circumference of the circle the flyer is
## actually flying. Still comfortably faster than
## Courtship.DANCE_TURNS_PER_SECOND, which is the other half of what makes the
## two behaviours distinguishable -- a tight fast whirl that climbs and pulls
## away, against a wide slow orbit that stays put.
const TURNS_PER_SECOND := ORBIT_SPEED_MPS / (TAU * SPIRAL_RADIUS_M)

## How far the pair climb before breaking off, in metres.
##
## Real spiral flights carry the two a metre or three above the vegetation
## (sometimes far higher). The low end is taken deliberately: the climb has
## to stay inside the flyer's own wander radius
## (AmbientFlyerRenderer.BUTTERFLY_RADIUS), or a whirl would fling a
## butterfly off its territory and leave it fighting its own home tether all
## the way back down. Pinned by
## test_the_climb_is_real_but_stays_inside_the_butterflys_territory.
##
## Screen-up is -Y in this top-down world, so this is a NEGATIVE Y offset.
## How far along its ascent path the pair actually go, in metres. This is the
## whole excursion, and it is what has to fit inside the territory.
const ASCENT_M := 1.5

## A real ascending flight goes up AND AWAY: the two chase each other off
## across the meadow as they climb, they do not spin on one spot. Spinning on
## the spot is a large part of why a fast turn reads as frantic rather than as
## flight -- the second half of "overly dramatic and only a circle".
##
## So the ascent above is decomposed at forty-five degrees, which is the
## statement that an ascending flight covers about as much ground as it gains.
## The excursion is unchanged by that -- it is the same 1.5 m path, just no
## longer a purely vertical one -- so the territory budget RISE_M was already
## capped against still holds, and
## test_the_whole_excursion_stays_inside_the_butterflys_territory pins it.
##
## Screen-up is -Y in this top-down world, so the climb is a NEGATIVE Y offset.
##
## Both come out well under BURST_SPEED_MPS once divided by SPIRAL_SECONDS,
## which matters: the orbit, the climb and the ground track are three
## components of ONE velocity, and their sum has to fit inside a real burst
## rather than exceed it (pinned by
## test_the_three_things_it_is_doing_at_once_fit_inside_one_burst -- the old
## model spent the entire burst on the orbit and then added the climb on top).
const ASCENT_COMPONENT := sqrt(0.5)
const RISE_M := ASCENT_M * ASCENT_COMPONENT
const RISE_PX := RISE_M * PX_PER_METER
const TRAVEL_M := ASCENT_M * ASCENT_COMPONENT
const TRAVEL_PX := TRAVEL_M * PX_PER_METER

## What share of its flying time a butterfly may spend doing this.
##
## Field time-budget studies of territorial butterflies put roughly 5-15% of
## active time into aerial interactions; an animal spending more than that
## whirling does not feed enough, and in this game a spiralling flyer is not
## foraging (see AmbientFlyerMarker._process). So the gap between bouts is
## not a number that was picked -- it is whatever makes the duty cycle come
## out right, and test_a_butterfly_spends_a_real_time_budget_on_this_not_all_day
## pins that the two agree.
const SPIRAL_DUTY_CYCLE := 0.1
const COOLDOWN_SECONDS := SPIRAL_SECONDS * (1.0 - SPIRAL_DUTY_CYCLE) / SPIRAL_DUTY_CYCLE

## Which species do this at all.
##
## True butterflies only. A honeybee's aerial life is nothing like it (drones
## congregate kilometres from the meadow; workers simply avoid one another at
## a bloom), and a songbird performing a tight two-second corkscrew reads as a
## bird glitching in place -- the exact failure that already got birds
## excluded from the courtship dance. Structural, not a branch: a bee has no
## way to enter this at all.
const SPIRALLING_SPECIES := {"monarch": true, "swallowtail": true, "blue_morpho": true}


static func spirals(species: String) -> bool:
	return SPIRALLING_SPECIES.has(species)


## How long after spawning this flyer is first willing to whirl.
##
## Every butterfly in a chunk comes into existence on the same frame, so
## without this a whole club whirls together, falls silent for exactly
## COOLDOWN_SECONDS together, and whirls together again -- a choreographed
## meadow, which is the same complaint already logged against pollinator
## routing ("not all bees and butterflies fly the same route following each
## other").
##
## Uniform over the cooldown is not a fudge to break up the pattern: it is
## the stationary distribution of "this butterfly last whirled at some point
## in the past cycle", which is the truth about an animal that did not begin
## existing when the chunk loaded. Applied by AmbientFlyerRenderer, which is
## what knows a flyer is one of a chunk's freshly-loaded many -- a marker
## built by hand (a diorama, a test) is deliberately not staggered.
static func stagger_seconds(seed_value: int) -> float:
	var unit := float(absi(hash("%d_spiral_stagger" % seed_value)) % 10000) / 10000.0
	return unit * COOLDOWN_SECONDS


## Whether these two will whirl at each other. CROSS-SPECIES on purpose --
## unlike Courtship.can_court, which is same-kind-only because a monarch and a
## swallowtail share a meadow and not a lineage. They do very much chase each
## other, and that is the behaviour being modelled here.
static func can_spiral(species_a: String, species_b: String) -> bool:
	return spirals(species_a) and spirals(species_b)


## The pair's shared climb `elapsed` seconds in -- the same translation for
## both of them, which is why they stay opposite each other across it.
##
## Linear: a butterfly in a spiral flight is climbing at a steady beat, and a
## linear ramp also keeps position continuous at both ends of the behaviour
## (nothing jumps when it starts, nothing jumps when it stops).
static func rise(elapsed: float) -> Vector2:
	var t := clampf(elapsed / SPIRAL_SECONDS, 0.0, 1.0)
	return Vector2(0.0, -RISE_PX * t)


## The pair's shared GROUND TRACK `elapsed` seconds in -- the same translation
## for both of them, exactly like `rise`, so they stay opposite each other
## across it without agreeing on anything at runtime.
##
## The direction comes from the pair's own seed, so both partners compute the
## same answer from the same input and no flyer ever reaches into the other
## (the one place this file allows that is documented in AmbientFlyerMarker,
## and this is not it). Different pairs in one meadow drift different ways.
##
## Linear for the same reason the climb is: it keeps position continuous at
## both ends of the behaviour, so nothing jumps when the whirl starts or stops.
## The heading is drawn from the seed over the UPPER half-circle only, and
## that restriction is a projection decision rather than a claim about
## butterflies. This world is top-down and draws height as screen-up (-Y), so
## the climb and the ground track land on the same two axes. A track drawn
## over the full circle can point straight down the screen and cancel the
## climb exactly -- measured, when it first did: the pair's whole shared
## translation came out at 0.07px over a full whirl, which is a pair spinning
## on one spot, the very thing the ground track exists to stop. Going "up and
## away" has to read as up and away.
static func travel(elapsed: float, pair_seed: int) -> Vector2:
	var t := clampf(elapsed / SPIRAL_SECONDS, 0.0, 1.0)
	var heading := PI + float(absi(hash("%d_spiral_track" % pair_seed)) % 3141) * 0.001
	return Vector2.from_angle(heading) * TRAVEL_PX * t


## Where this butterfly should be relative to the pair's shared midpoint,
## `elapsed` seconds into the whirl.
##
## `start_offset` is its OWN offset from that midpoint at the moment the whirl
## began, which does three things at once and is why it is a parameter rather
## than a constant:
##
## - the offset at elapsed 0 is exactly `start_offset`, so nothing teleports
##   when the behaviour starts (Courtship.dance_offset snaps both partners
##   onto a fixed-radius orbit instead, a visible jump of up to a body
##   length);
## - the two partners' start offsets are exactly opposite by construction --
##   the midpoint is the midpoint -- so they stay across the axis from each
##   other for the whole climb without agreeing on anything at runtime, the
##   same no-message-passing property the courtship dance has;
## - the pair CONVERGE from however far apart they happened to meet down to
##   SPIRAL_RADIUS_PX, which is what "they flew at each other" looks like.
static func offset(elapsed: float, start_offset: Vector2, pair_seed: int = 0) -> Vector2:
	var held := clampf(elapsed, 0.0, SPIRAL_SECONDS)
	return (
		converging_orbit(held, start_offset, SPIRAL_RADIUS_PX, TURNS_PER_SECOND, pair_seed)
		+ rise(held)
		+ travel(held, pair_seed)
	)


## The whirl geometry on its own, without the climb: `start_offset` swung
## round the shared centre while it is drawn in onto a circle of `radius_px`
## over SPIRAL_SECONDS.
##
## Split out of offset() so the SAME shape can be flown round something that
## is NOT another butterfly. A bold butterfly orbiting the player's head (see
## FlyerPersonality / AmbientFlyerMarker._step_player_dance) is this behaviour
## aimed at a different object, which is already this module's own grounding:
## a territorial butterfly launches at conspecifics, passing birds, falling
## leaves and thrown pebbles alike, and a person walking through the meadow is
## one more such object. Sharing the geometry is what keeps the game from
## growing a third dance shape with a third set of constants to justify.
##
## Two differences from offset(), both deliberate:
##
## - no `rise`. A pair of butterflies whirl UP and break off at the top; a
##   butterfly investigating a head is already at head height and has nowhere
##   to climb to (the caller centres it on the head -- see
##   StoneSize.PLAYER_WORLD_HEIGHT_PX).
## - the angle is NOT clamped. A whirl between two butterflies is over in
##   SPIRAL_SECONDS, but an orbit round a player lasts as long as the player
##   stands there, and clamping would freeze the dance at one point of the
##   circle with the butterfly hanging motionless on it. Only the CONVERGENCE
##   is time-limited, which is what makes the approach finish.
## ## And why it is not a circle
##
## `seed_value` makes the orbit BREATHE, which is the "only a circle" half of
## the report. Real spiral flights are chaotic ascending chases -- irregular,
## jagged, and never a clean ellipse -- and the pair's separation is observed
## as a RANGE (see SPIRAL_SEPARATION_MIN_M/MAX_M), not as one number.
##
## The perturbation is the SAME irregularity a butterfly's ordinary flight
## already has in this game (FlightIrregularity, factored out of the flutter),
## not a second wobble with its own constants. Its amplitude is RADIUS_SWING,
## which is derived from the observed separation band rather than chosen.
##
## The radius is written r0 / (1 + k*w) rather than r0 * (1 + k*w) for a
## reason that is worth stating: a flyer holds an AIRSPEED, so on a radius
## that varies it turns at w = v/r -- tighter means faster round. With the
## reciprocal form the angular rate is exactly (v/r0) * (1 + k*w), whose
## integral is closed-form, so the swept angle below is the true integral of a
## real varying turn rate rather than an approximation of one. That matters:
## accumulating the angle per frame instead would make the figure depend on
## frame rate and on SimulationLod's step size, which is precisely the class
## of bug this system has already produced three separate ways.
##
## At elapsed 0 the perturbation cannot move anything -- `closing` is 0, so
## the radius is exactly `start_offset.length()`, and the swept angle is
## exactly 0 -- so nothing teleports when an orbit begins, as before.
static func converging_orbit(
	elapsed: float,
	start_offset: Vector2,
	radius_px: float,
	turns_per_second: float,
	seed_value: int = 0
) -> Vector2:
	var closing := clampf(elapsed / SPIRAL_SECONDS, 0.0, 1.0)
	var breathing := radius_px / (
		1.0 + RADIUS_SWING * FlightIrregularity.wobble(elapsed, seed_value)
	)
	var radius := lerpf(start_offset.length(), breathing, closing)
	# The exact integral of TAU * turns_per_second * (1 + k*w(t)) dt.
	var swept := TAU * turns_per_second * (
		elapsed + RADIUS_SWING * FlightIrregularity.wobble_integral(elapsed, seed_value)
	)
	return Vector2.from_angle(start_offset.angle() + swept) * radius
