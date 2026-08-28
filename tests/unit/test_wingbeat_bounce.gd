extends GutTest

## The little vertical bob a flying body makes once per wingbeat (see
## WingbeatBounce / docs/concept/ecosystem_dynamics.md's "The wingbeat
## bounce"), asked for as "maybe also make them bounce slightly with each wing
## flap".
##
## It is not decoration invented to satisfy that: lift is generated in PULSES,
## once per beat, so the body genuinely rises and falls at the wingbeat
## frequency. That undulation is a large part of why butterfly flight looks
## the way it does.

const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")


# -- where the amplitude comes from ------------------------------------------


## The whole derivation in one assertion. Model the lift as swinging
## sinusoidally about body weight at the wingbeat frequency; the body's
## vertical displacement is then g/omega^2 times the relative swing, and the
## swing cannot exceed 1 because a wing cannot pull the body DOWN through the
## stroke. So this is the physical MAXIMUM bob, not a number anybody picked.
func test_the_amplitude_is_the_physical_ceiling_on_a_pulsed_lift():
	for species in WingbeatBounce.FLIGHT.keys():
		var beat: Dictionary = WingbeatBounce.FLIGHT[species]
		var omega: float = TAU * float(beat["wingbeat_hz"])
		var expected: float = (
			GroundSlide.GRAVITY_MPS2 / (omega * omega) / float(beat["body_length_m"])
		)
		assert_almost_eq(WingbeatBounce.amplitude_bodies(species), expected, 0.000001)


## A monarch beats around ten times a second and is about 25 mm of body, which
## puts the bob at a couple of millimetres -- roughly a fifth of its own body
## from top to bottom of the cycle. That is the number the whole effect stands
## on, and it agrees with what a monarch actually looks like in the air: a
## visible undulation, not a hop and not a tremor.
func test_a_monarchs_bob_is_a_couple_of_millimetres_and_a_fifth_of_its_body():
	var beat: Dictionary = WingbeatBounce.FLIGHT["monarch"]
	var metres: float = (
		WingbeatBounce.amplitude_bodies("monarch") * float(beat["body_length_m"])
	)
	assert_between(metres, 0.002, 0.003, "the real bob is a couple of millimetres")
	assert_between(
		WingbeatBounce.amplitude_bodies("monarch") * 2.0, 0.1, 0.3,
		"top to bottom, that is a fifth or so of the body"
	)


## Every true butterfly has to bob enough to SEE, or the feature does not
## exist on screen.
func test_every_butterfly_bobs_a_visible_fraction_of_its_own_body():
	for species in AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL:
		assert_between(
			WingbeatBounce.amplitude_bodies(species), 0.05, 0.25,
			"%s must bob visibly but stay inside its own body" % species
		)


## No species gate anywhere in this module, and none needed: the bob goes as
## 1 / (frequency^2 x body length), and a bee at ~230 Hz or a sparrow at
## ~13 Hz on a 14 cm body simply falls out of it at a size nothing can draw.
## Structural rather than a branch -- the same reason a bee cannot enter
## SpiralFlight at all.
func test_bees_flies_and_songbirds_fall_out_of_it_on_their_own():
	var monarch := WingbeatBounce.amplitude_bodies("monarch")
	for species in ["bee", "fly", "sparrow", "robin", "kingfisher"]:
		assert_lt(
			WingbeatBounce.amplitude_bodies(species), monarch * 0.25,
			"%s must not inherit a butterfly's bob" % species
		)


func test_a_slower_flapper_bobs_more():
	assert_gt(
		WingbeatBounce.amplitude_bodies("blue_morpho"),
		WingbeatBounce.amplitude_bodies("monarch"),
		"the morpho is the slow, deep flapper of the three"
	)


func test_an_unknown_flyer_still_gets_an_answer():
	assert_almost_eq(
		WingbeatBounce.amplitude_bodies("not_a_real_species"),
		WingbeatBounce.amplitude_bodies(WingbeatBounce.FALLBACK_SPECIES),
		0.000001
	)


## Expressed as a fraction of the BODY rather than in metres, and that is a
## deliberate divergence worth pinning: this world draws its small flyers well
## above life size. A monarch's real 10 cm wingspan would be about a pixel and
## a quarter at GroundSlide.PX_PER_METER, and the sprite is several times
## that. A physically exact 2.5 mm bob would be three hundredths of a world
## pixel -- nothing. The RATIO is what transfers into a stylised world, the
## same reasoning FlyerPersonality.ESCAPE_SPEED_MULTIPLIER is built on.
func test_the_real_bob_in_world_pixels_would_be_invisible():
	var beat: Dictionary = WingbeatBounce.FLIGHT["monarch"]
	var literal_px: float = (
		WingbeatBounce.amplitude_bodies("monarch")
		* float(beat["body_length_m"])
		* GroundSlide.PX_PER_METER
	)
	assert_lt(literal_px, 0.1, "which is why this is a body fraction and not a distance")


# -- the bob itself ----------------------------------------------------------

## The butterfly sprite's own wing-beat cycle, as the marker drives it.
const FRAMES := ProceduralButterflySprite.FLAP_FRAME_COUNT
const PER_FRAME := 0.09
const BODY_PX := 20.0


func _bob(elapsed: float) -> float:
	return WingbeatBounce.bounce_offset("monarch", elapsed, PER_FRAME, FRAMES, BODY_PX)


## Phase-LOCKED, which is the whole request ("bounce slightly with each wing
## flap"): one bob per animation cycle, so the body and the wings are one
## motion rather than two things happening at once at different rates.
func test_one_bob_per_wing_beat():
	var cycle := PER_FRAME * float(FRAMES)
	for beat in 4:
		assert_almost_eq(_bob(cycle * float(beat)), _bob(0.0), 0.0001)


func test_the_body_is_at_its_lowest_and_highest_within_one_beat():
	var cycle := PER_FRAME * float(FRAMES)
	var lowest := -INF
	var highest := INF
	for step in 60:
		var here := _bob(cycle * float(step) / 60.0)
		lowest = maxf(lowest, here)
		highest = minf(highest, here)
	# Screen-up is -Y, so "highest" is the most negative offset.
	assert_lt(highest, -0.5, "it must actually rise")
	assert_gt(lowest, 0.5, "and actually fall")


func test_the_bob_never_leaves_the_body():
	var ceiling := WingbeatBounce.amplitude_bodies("monarch") * BODY_PX
	for step in 200:
		assert_lte(absf(_bob(float(step) * 0.013)), ceiling + 0.0001)


## A flyer whose sprite generator gave it no wing-beat frames (the fallback
## every marker has -- see AmbientFlyerMarker._animate_wings) has no beat to
## lock to, so there is nothing to bob against and it must sit still rather
## than divide by zero.
func test_a_flyer_with_no_wing_beat_does_not_bob():
	assert_eq(WingbeatBounce.bounce_offset("monarch", 1.0, PER_FRAME, 0, BODY_PX), 0.0)
	assert_eq(WingbeatBounce.bounce_offset("monarch", 1.0, 0.0, FRAMES, BODY_PX), 0.0)


## Proportional to the drawn body, so a juvenile that has not grown into its
## adult size yet (see LifeCycle.size_scale_at) bobs by less, without anything
## having to tell it to.
func test_a_smaller_body_bobs_less():
	var big := absf(WingbeatBounce.bounce_offset("monarch", 0.09, PER_FRAME, FRAMES, 20.0))
	var small := absf(WingbeatBounce.bounce_offset("monarch", 0.09, PER_FRAME, FRAMES, 5.0))
	assert_almost_eq(small * 4.0, big, 0.0001)
