extends GutTest

## docs/concept/journey_rings.md / docs/concept/survival.md: sprinting costs
## stamina, and that cost is what makes distance a real decision.
##
## Measured before this module existed: `SurvivalMeters.spend_stamina` had
## exactly ONE caller in the whole game -- the sickness step
## (scenes/player.gd) -- so sprint was free, unlimited and exactly twice
## walking speed. A player could outrun every predator in the world for
## ever, which is why the world's danger gradient gated nothing: you could
## simply run past it. This module is the cost that makes the gradient real.

const SprintCost = preload("res://src/gameplay/sprint_cost.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const Player = preload("res://scenes/player.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
## The world's own play-scale tile, read rather than restated.
const TerrainRendererTileSize := 16
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")


# -- the cost is derived, not picked ------------------------------------

## The rate is a consequence of how long a burst should last, not a number
## somebody liked the look of: one named constant, and the rate falls out.
func test_the_drain_rate_is_derived_from_the_pinned_burst_length():
	assert_almost_eq(
		SprintCost.STAMINA_PER_SECOND,
		1.0 / SprintCost.SECONDS_OF_SPRINT_FROM_FULL,
		0.0001
	)


func test_a_full_bar_sprints_for_exactly_the_pinned_burst():
	var meters := SurvivalMeters.new()
	meters.stamina = 1.0
	var elapsed := 0.0
	while SprintCost.can_sprint(meters.stamina) and elapsed < 120.0:
		meters.spend_stamina(SprintCost.STAMINA_PER_SECOND * 0.1)
		elapsed += 0.1
	assert_almost_eq(
		elapsed,
		SprintCost.SECONDS_OF_SPRINT_FROM_FULL * (1.0 - SurvivalMeters.EXHAUSTED_THRESHOLD),
		0.25,
		"a burst runs from full down to the exhausted threshold, not to zero"
	)


## A burst is a burst: long enough to break contact or close a gap, short
## enough that it is a decision rather than a travel mode.
func test_the_burst_is_long_enough_to_matter_and_short_enough_to_be_a_decision():
	assert_true(SprintCost.SECONDS_OF_SPRINT_FROM_FULL >= 8.0, "shorter than this is not a burst, it is a twitch")
	assert_true(SprintCost.SECONDS_OF_SPRINT_FROM_FULL <= 30.0, "longer than this is just a faster walk")


# -- exhaustion gates it ------------------------------------------------

func test_a_full_bar_can_sprint():
	assert_true(SprintCost.can_sprint(1.0))


func test_an_exhausted_bar_cannot_sprint():
	assert_false(SprintCost.can_sprint(0.0))
	assert_false(
		SprintCost.can_sprint(SurvivalMeters.EXHAUSTED_THRESHOLD * 0.5),
		"below the game's own exhausted threshold is not a second opinion, it is that threshold"
	)


## The gate is the meters' OWN exhausted threshold, so "Exhausted" on the
## HUD and "cannot sprint" are one fact and cannot drift apart.
func test_the_gate_is_the_survival_meters_own_exhausted_threshold():
	assert_false(SprintCost.can_sprint(SurvivalMeters.EXHAUSTED_THRESHOLD - 0.001))
	assert_true(SprintCost.can_sprint(SurvivalMeters.EXHAUSTED_THRESHOLD + 0.001))
	var meters := SurvivalMeters.new()
	meters.stamina = SurvivalMeters.EXHAUSTED_THRESHOLD - 0.001
	assert_true(meters.is_exhausted(), "the same reading the HUD calls Exhausted")


func test_recovering_past_the_threshold_allows_sprinting_again():
	var meters := SurvivalMeters.new()
	meters.stamina = 0.0
	assert_false(SprintCost.can_sprint(meters.stamina), "precondition")
	meters.rest(SurvivalMeters.EXHAUSTED_THRESHOLD + 0.1)
	assert_true(SprintCost.can_sprint(meters.stamina))


## Recovery is slower than the spend, so a chase cannot be sprinted in
## instalments -- the whole point of a cost.
func test_recovering_a_full_bar_takes_longer_than_spending_it():
	var seconds_to_refill := 1.0 / SurvivalMeters.STAMINA_REGEN_PER_SECOND
	assert_gt(
		seconds_to_refill, SprintCost.SECONDS_OF_SPRINT_FROM_FULL,
		"a burst must cost more time to earn back than it buys"
	)


# -- and therefore distance costs something (requirement 3) --------------

## The assertion the whole danger gradient rests on: one bar of stamina
## does not carry you across a ring. A player cannot sprint from the safe
## hearth into lethal country -- they have to walk it, and walking is where
## the world gets to be dangerous at them.
##
## Measured when this test was first written: the safe ring's radius is
## 684 m at play scale (15 chunks x 32 tiles x 16 px over
## GroundSlide.PX_PER_METER) and one full burst is 80 m, so a burst is
## under a eighth of it. The assertion is deliberately the weaker,
## permanently-true statement -- a burst is under a FIFTH of the safe
## radius -- so a later retune of either number fails here loudly rather
## than quietly making sprint a travel plan again.
func test_one_full_burst_covers_only_a_fraction_of_the_safe_ring():
	var burst_metres: float = SprintCost.burst_distance_metres()
	var easy_ring_metres := (
		float(RegionDifficulty.EASY_RADIUS_CHUNKS)
		* float(EarthChunkManager.CHUNK_SIZE)
		* float(TerrainRendererTileSize) / GroundSlide.PX_PER_METER
	)
	assert_gt(easy_ring_metres, burst_metres * 5.0,
		"one burst must be a fraction of the safe ring, never a way across it")


## And the part that actually answers "you cannot stroll to the last boss":
## reaching the HARD tier is not a sprint, it is an expedition. Walking is
## free but slow, so the cost of distance is paid in the world's own time
## -- day, night, weather, hunger and whatever hunts there.
func test_reaching_lethal_country_is_an_expedition_not_a_dash():
	var hard_ring_metres := (
		float(RegionDifficulty.MEDIUM_RADIUS_CHUNKS)
		* float(EarthChunkManager.CHUNK_SIZE)
		* float(TerrainRendererTileSize) / GroundSlide.PX_PER_METER
	)
	var bursts_needed := hard_ring_metres / SprintCost.burst_distance_metres()
	assert_gt(bursts_needed, 30.0,
		"more than thirty full stamina bars of running -- so it is walked, in the open, over hours")
	var walking_seconds := (
		hard_ring_metres
		/ (Player.BASE_SPEED / GroundSlide.PX_PER_METER)
	)
	assert_gt(walking_seconds, 600.0, "and walking it takes real minutes, not a dash")


func test_the_burst_distance_is_derived_from_the_real_sprint_speed():
	assert_almost_eq(
		SprintCost.burst_distance_metres(),
		(
			Player.SPRINT_SPEED / GroundSlide.PX_PER_METER
			* SprintCost.SECONDS_OF_SPRINT_FROM_FULL * (1.0 - SurvivalMeters.EXHAUSTED_THRESHOLD)
		),
		0.5,
		"not a number typed in: the real sprint speed, for the real burst length"
	)


## Walking has no cost, so a player is never stranded: the cost is on the
## FAST option, which is what makes it a choice rather than a tax.
func test_walking_is_always_free():
	assert_eq(SprintCost.stamina_for_seconds(1.0, false), 0.0)
	assert_gt(SprintCost.stamina_for_seconds(1.0, true), 0.0)


func test_the_spend_scales_with_the_time_spent_sprinting():
	assert_almost_eq(
		SprintCost.stamina_for_seconds(2.0, true),
		SprintCost.stamina_for_seconds(1.0, true) * 2.0,
		0.0001
	)


func test_a_zero_or_negative_step_spends_nothing():
	assert_eq(SprintCost.stamina_for_seconds(0.0, true), 0.0)
	assert_eq(SprintCost.stamina_for_seconds(-1.0, true), 0.0)


# -- the restated constants are held to their real sources ---------------

## SprintCost is pure and must not preload a scene script or the renderer,
## so it restates two numbers. A restated number is a number that can
## drift, and these tests are what stop it.

func test_the_restated_sprint_speed_is_the_players_own():
	assert_eq(SprintCost.sprint_speed_px_per_second(), Player.SPRINT_SPEED)


func test_the_restated_tile_size_is_the_renderers_own():
	assert_eq(SprintCost.TILE_SIZE_PX, TerrainRendererTileSize)


# -- and it is really wired to the player --------------------------------
#
# A pure rule nothing calls is exactly the pattern the diagnosis found
# everywhere in this codebase (dodge, corpse, wounds: real, tested, zero
# callers). These tests are what stop SprintCost joining them.

const PlayerScene = preload("res://scenes/player.tscn")


func test_the_player_really_refuses_to_sprint_when_exhausted():
	var player = PlayerScene.instantiate()
	add_child(player)
	player.survival.stamina = 0.0
	assert_false(player.is_sprinting(), "exhausted legs do not run, whatever the key says")
	player.queue_free()


func test_the_player_spends_stamina_only_through_the_shared_rule():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(
		source.contains("SprintCost.stamina_for_seconds"),
		"the player must spend the shared rule's own figure, not a second opinion"
	)
	assert_true(
		source.contains("SprintCost.can_sprint"),
		"and gate on the shared rule's own threshold"
	)
