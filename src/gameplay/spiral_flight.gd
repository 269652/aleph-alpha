extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

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
## Real spiral flights keep the two within about half a metre to a metre --
## visibly TIGHTER than the wide, slow courtship flight, which is half of
## what makes the two read as different behaviours at a glance.
const SPIRAL_SEPARATION_M := 0.7
const SPIRAL_RADIUS_M := SPIRAL_SEPARATION_M * 0.5
const SPIRAL_RADIUS_PX := SPIRAL_RADIUS_M * PX_PER_METER

## How fast a butterfly flies in one of these. A spiral flight is maximum
## exertion, not a cruise: a monarch cruises around 2 m/s and tops out near
## 5 m/s, and the whirl is the top end.
const BURST_SPEED_MPS := 5.0

## Turns per second, DERIVED rather than chosen: the burst speed divided by
## the circumference of the circle the flyer is actually flying. Comes out
## far faster than Courtship.DANCE_TURNS_PER_SECOND, which is the other half
## of what makes the two behaviours distinguishable -- a tight fast whirl
## that climbs, against a wide slow orbit that stays put.
const TURNS_PER_SECOND := BURST_SPEED_MPS / (TAU * SPIRAL_RADIUS_M)

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
const RISE_M := 1.5
const RISE_PX := RISE_M * PX_PER_METER

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
static func offset(elapsed: float, start_offset: Vector2) -> Vector2:
	var held := clampf(elapsed, 0.0, SPIRAL_SECONDS)
	var t := held / SPIRAL_SECONDS
	var radius := lerpf(start_offset.length(), SPIRAL_RADIUS_PX, t)
	var angle := start_offset.angle() + TAU * TURNS_PER_SECOND * held
	return Vector2.from_angle(angle) * radius + rise(held)
