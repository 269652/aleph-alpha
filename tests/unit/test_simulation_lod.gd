extends GutTest

## How often an ambient creature updates, by how far it is from the player.
##
## Measured on this machine at 1920x1080 with vsync off, after the rendering
## costs were dealt with: hiding the water overlay, the ground tint, every
## entity, every creature or the whole terrain each changed the frame rate by
## nothing (34-42 fps, all inside run-to-run noise), and dropping draw calls
## from 204 to 57 did not help either. Rendering at a NINTH of the pixels did
## not help either. That is what CPU-bound looks like: the frame is script
## work, not pixels.
##
## The script work is per-creature, and there are a lot of them -- 266
## butterflies were counted in one meadow. Nearly all of them are off screen,
## because the camera shows about 20x11 tiles out of the 3x3 chunks kept
## decorated. Something the player cannot see does not need sixty updates a
## second.

const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")


## On screen, nothing changes: full rate, no visible stepping.
func test_a_creature_the_player_can_see_updates_every_frame():
	assert_eq(SimulationLod.update_interval(0.0), 0.0)
	assert_eq(SimulationLod.update_interval(SimulationLod.FULL_RATE_RADIUS_PX - 1.0), 0.0)


func test_a_creature_far_away_updates_less_often():
	assert_gt(SimulationLod.update_interval(SimulationLod.FULL_RATE_RADIUS_PX + 1.0), 0.0)


## The further off, the cheaper -- never the other way round.
func test_the_update_interval_never_shortens_with_distance():
	var previous := -1.0
	for step in 40:
		var interval := SimulationLod.update_interval(float(step) * 60.0)
		assert_gte(interval, previous, "a more distant creature must not cost more")
		previous = interval


## Bounded: a creature that never updates is a creature that has stopped
## existing, and the world is meant to keep living while the player is away.
func test_even_the_most_distant_creature_still_updates():
	var interval := SimulationLod.update_interval(100000.0)
	assert_gt(interval, 0.0)
	assert_lte(interval, SimulationLod.MAX_INTERVAL_SECONDS)


## The saving has to be worth having: an off-screen creature should cost a
## small fraction of an on-screen one.
func test_an_off_screen_creature_costs_a_fraction_of_an_on_screen_one():
	var far := SimulationLod.update_interval(SimulationLod.FULL_RATE_RADIUS_PX * 4.0)
	assert_gte(far, 1.0 / 12.0, "a distant creature should update at most a dozen times a second")


## The player must never catch a creature stepping: the full-rate radius has
## to cover more than the camera can actually show, so anything visibly
## moving is moving smoothly.
func test_the_full_rate_radius_covers_more_than_the_visible_screen():
	var half_view_px := DisplayScaling.visible_tiles_across(1280.0, 720.0) * 0.5 * 16.0
	assert_gt(
		SimulationLod.FULL_RATE_RADIUS_PX, half_view_px,
		"everything on screen must still update every frame"
	)


const DisplayScaling = preload("res://src/rendering/display_scaling.gd")


## FPS regression round 13 (docs/concept/soil_fauna.md): the full-rate set
## was ~5x the visible area -- 420 px against a 184 px half-diagonal at the
## design zoom -- so ~105 creatures stepped every frame for a screen that
## shows a fraction of them. Full rate must cover the screen (the pin above)
## and not much more: a quarter's margin past the half-diagonal, so a
## creature stepping onto the screen is already at full rate.
func test_the_full_rate_radius_stays_close_to_the_visible_screen():
	var half_width_px := DisplayScaling.visible_tiles_across(1280.0, 720.0) * 0.5 * 16.0
	var half_height_px := half_width_px * 720.0 / 1280.0
	var half_diagonal_px := sqrt(half_width_px * half_width_px + half_height_px * half_height_px)
	assert_lte(
		SimulationLod.FULL_RATE_RADIUS_PX, half_diagonal_px * 1.25,
		"the full-rate radius must not reach far beyond what the camera shows"
	)


## The far population is the real cost: ~1,800 parked creatures each woken
## every MAX_INTERVAL_SECONDS is a per-frame wake count that no frame rate
## changes (the interval is enforced in frames). At 0.5 s that was ~60 full
## steps a frame, ~30 ms of any frame. The budget: the far population must
## cost at most fifteen wakes a frame.
func test_far_wakes_stay_within_a_per_frame_budget():
	var parked_population := 1800
	var far_frames := SimulationLod.frames_between_updates(
		SimulationLod.FULL_RATE_RADIUS_PX + SimulationLod.FALLOFF_PX
	)
	assert_lte(
		float(parked_population) / float(far_frames), 15.0,
		"far wakes per frame at the reference frame rate"
	)


func test_the_far_interval_is_exactly_pinned():
	assert_eq(SimulationLod.MAX_INTERVAL_SECONDS, 2.0)
	assert_eq(SimulationLod.FULL_RATE_RADIUS_PX, 200.0)
