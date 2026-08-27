extends GutTest

## FishMarker: a lightweight (no needs/perception/behavior AI, unlike
## CreatureMarker) swimming entity -- reuses CreatureWander's pure idle-drift
## pattern, but stays confined to water tiles instead of orbiting freely, so a
## small pond's fish don't wander up onto the grass.

const FishMarker = preload("res://src/rendering/fish_marker.gd")
const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")

const TILE_SIZE := 16


## Duck-typed world, same shape as CreatureMarker's tests: every tile is the
## same biome unless overridden.
class StubWorld:
	var biome := "ocean"
	func biome_at_global(_x: int, _y: int) -> String:
		return biome


## Only the tile the fish starts on is water; every other tile is land -- lets
## tests assert the fish never swims off its home tile.
class SinglePondWorld:
	var home_tile: Vector2i
	func biome_at_global(x: int, y: int) -> String:
		return "ocean" if Vector2i(x, y) == home_tile else "grassland"


## Water fills every tile column up to (and including) max_water_tile_x --
## a straight north-south shoreline, for asserting a fish slides along it
## rather than beaching or freezing against it.
class ShorelineWorld:
	var max_water_tile_x := 6
	func biome_at_global(x: int, _y: int) -> String:
		return "ocean" if x <= max_water_tile_x else "grassland"


## Ocean everywhere (like StubWorld), but also records every
## record_water_disturbance call so ripple-burst tests can inspect exactly
## when/how many rings actually fired.
class RippleTrackingWorld:
	var positions: Array[Vector2] = []
	func biome_at_global(_x: int, _y: int) -> String:
		return "ocean"
	func record_water_disturbance(world_pos: Vector2) -> void:
		positions.append(world_pos)


## Single-water-tile confinement (like SinglePondWorld) that ALSO tracks
## ripple calls, so "a fish that cannot move never ripples" can assert on
## the actual call count instead of only on position.
class ConfinedRippleTrackingWorld:
	var home_tile: Vector2i
	var positions: Array[Vector2] = []
	func biome_at_global(x: int, y: int) -> String:
		return "ocean" if Vector2i(x, y) == home_tile else "grassland"
	func record_water_disturbance(world_pos: Vector2) -> void:
		positions.append(world_pos)


## Mirrors test_creature_marker.gd's own StubPlayer/_add_stub_player: a bare
## Node2D in the "player" group is all _nearest_player_position needs.
class StubPlayer:
	extends Node2D


var marker: FishMarker
var _extra: Array = []


func before_each():
	marker = FishMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.species = "goldfish"
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()
	for node in _extra:
		if is_instance_valid(node):
			node.free()
	_extra = []


func _add_stub_player(at: Vector2) -> StubPlayer:
	var player := StubPlayer.new()
	player.position = at
	add_child(player)
	player.add_to_group("player")
	_extra.append(player)
	return player


## See World's mouse-hover animal-name tooltip (docs feature request).
func test_get_display_name_capitalizes_the_species():
	marker.species = "goldfish"
	assert_eq(marker.get_display_name(), "Goldfish")


func test_position_changes_after_processing():
	var before := marker.position
	marker._process(0.5)
	assert_ne(marker.position, before)


func test_stays_within_a_bounded_range_of_home_over_many_steps():
	for i in 100:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), CreatureWander.WANDER_RADIUS * 2.0)


func test_two_markers_with_different_seeds_move_differently():
	var other := FishMarker.new()
	other.home = Vector2(100, 100)
	other.position = Vector2(100, 100)
	other.wander_seed = 999
	add_child(other)

	marker._process(0.5)
	other._process(0.5)
	assert_ne(marker.position, other.position)

	remove_child(other)
	other.free()


## Without setup() called, there's no world to check against -- same
## isolated-test fallback CreatureMarker uses (world defaults to null).
func test_swims_freely_when_no_world_is_configured():
	for i in 50:
		marker._process(0.2)


# -- configure_wander / step_wander: a diorama-scale caller that keeps this
# -- fish's own _process disabled (a small pond needs a MUCH smaller radius
# -- than the real world's WANDER_RADIUS -- see CreatureWander.wander_radius's
# -- own doc comment) can still drive the exact same real algorithm manually,
# -- one call per frame, instead of reimplementing swimming from scratch
# -- (reported live, of the character preview diorama's own earlier
# -- point-to-point fish: "fish don't swim like in the real game").

func test_configure_wander_overrides_the_radius_used_by_step_wander():
	marker.configure_wander(5.0, CreatureWander.WANDER_SPEED)
	for i in 200:
		marker.step_wander(0.1)
	assert_lt(
		marker.position.distance_to(marker.home), 5.0 * 2.0,
		"should stay bounded near the small configured radius, not the real-world default"
	)


func test_configure_wander_overrides_the_speed_used_by_step_wander():
	marker.configure_wander(CreatureWander.WANDER_RADIUS, 1.0)
	var before := marker.position
	marker.step_wander(1.0)
	assert_almost_eq(marker.position.distance_to(before), 1.0, 0.01)


func test_step_wander_moves_the_fish_even_while_its_own_processing_is_disabled():
	marker.set_process(false)
	var before := marker.position
	marker.step_wander(0.5)
	assert_ne(marker.position, before)
	assert_ne(marker.position, marker.home)


func test_never_swims_onto_land_when_confined_to_a_single_water_tile():
	var world := SinglePondWorld.new()
	world.home_tile = Vector2i(6, 6)
	marker.home = Vector2((6.5) * TILE_SIZE, (6.5) * TILE_SIZE)
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	for i in 100:
		marker._process(0.3)
		var tile_x := int(floor(marker.position.x / TILE_SIZE))
		var tile_y := int(floor(marker.position.y / TILE_SIZE))
		assert_eq(world.biome_at_global(tile_x, tile_y), "ocean", "fish left the water on step %d" % i)


## The core of "still don't move naturally": a fish must turn gradually
## toward its new heading, never snap instantly to it -- bounded by
## TURN_RATE, provable without depending on CreatureWander's exact target.
func test_heading_turn_rate_is_bounded_per_frame():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._current_heading = Vector2.LEFT
	var before_angle := marker._current_heading.angle()

	marker._process(0.1)

	var turned := absf(angle_difference(before_angle, marker._current_heading.angle()))
	assert_lte(turned, FishMarker.TURN_RATE * 0.1 + 0.01, "heading should turn gradually, not snap")


## The sprite's rotation must track its actual swim heading, so the fish
## visibly points the way it's swimming rather than always facing however
## its base art was drawn.
func test_sprite_rotation_tracks_the_swim_heading():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._process(0.3)
	assert_almost_eq(marker.rotation, marker._current_heading.angle(), 0.01)


## Even with gradual turning, a fish must actually reach a materially
## different heading over many steps -- smoothing shouldn't mean it never
## turns, just that it doesn't teleport.
func test_heading_eventually_changes_over_many_steps():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	var start_angle := marker._current_heading.angle()
	for i in 200:
		marker._process(0.1)
	assert_gt(absf(angle_difference(start_angle, marker._current_heading.angle())), 0.05)


# -- attraction to a cast fishing line (see EarthChunkManager.set_attraction_point) --

## An attracted fish must steer toward the target instead of wandering --
## "no attraction to nearby fish" was the reported gap.
func test_attraction_target_pulls_the_fish_toward_it():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker.position = Vector2(1000, 1000)
	var target := Vector2(1000, 1300)  # straight down
	marker.set_attraction(target)

	var before_distance := marker.position.distance_to(target)
	for i in 60:
		marker._process(0.2)
	assert_lt(marker.position.distance_to(target), before_distance, "an attracted fish should close in on the target")


func test_clear_attraction_returns_the_fish_to_normal_wander():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker.set_attraction(Vector2(2000, 2000))
	marker.clear_attraction()
	assert_null(marker.attract_target)


## Attraction must still respect the shore -- a fish drawn toward a bobber
## just past the beach should not follow it onto land.
func test_attraction_still_respects_water_clearance():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.0 * TILE_SIZE, 6.5 * TILE_SIZE)
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)
	marker.set_attraction(Vector2(20.0 * TILE_SIZE, 6.5 * TILE_SIZE))  # well onto land

	var water_edge_x := (world.max_water_tile_x + 1) * TILE_SIZE
	for i in 200:
		marker._process(0.25)
		assert_lt(marker.position.x, water_edge_x - FishMarker.CLEARANCE_PX + 0.01)


func test_swims_around_within_a_larger_water_body():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	for i in 60:
		marker._process(0.3)
	assert_ne(marker.position, marker.home)


## The reported stranding bug: a fish whose wander heading pointed at the
## shore used to just stop dead for the whole direction interval, piling
## fish up motionless along the waterline. It must instead deflect and keep
## swimming (any turn that stays in water), every single frame.
func test_fish_keeps_moving_along_a_shoreline_instead_of_freezing():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.5 * TILE_SIZE, 6.5 * TILE_SIZE)  # water tile right at the shore
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	var moved := 0
	for i in 150:
		var before := marker.position
		marker._process(0.25)
		if marker.position != before:
			moved += 1
	assert_eq(moved, 150, "a fish beside a shoreline should deflect and keep swimming every frame, never freeze")


## The other half of "stranded at the shoreline": moving is gated on the
## fish keeping CLEARANCE_PX of open water on every side of its center --
## roughly the sprite's half-extent -- so no part of the fish ever visually
## overlaps the beach, whichever way it's pointing.
func test_fish_clearance_keeps_it_clear_of_the_waterline():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.0 * TILE_SIZE, 6.5 * TILE_SIZE)  # inside the shore tile, clear of the edge
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)

	var water_edge_x := (world.max_water_tile_x + 1) * TILE_SIZE
	for i in 200:
		marker._process(0.25)
		assert_lt(
			marker.position.x, water_edge_x - FishMarker.CLEARANCE_PX + 0.01,
			"the fish's center must stay at least CLEARANCE_PX clear of the waterline (step %d)" % i
		)


# -- water-ripple bursts: "wagging the tail", not one poke at a time --------
##
## A real fish's stroke is several quick tail beats in a row, which push a
## short STREAK of rings across the surface -- not one isolated ring, and not
## a continuous churn either (see FishMarker.RIPPLE_INTERVAL_MIN's own doc
## comment on staying unhurried against the shared disturbance buffer).
## Reported directly: "It should produce a streak of rings but only when
## wagging the tail, so that the interference creates a forward pattern,
## just like when the player walks through water."

## _step_water_ripple's movement gate needs one PRIOR position sample before
## it can tell "did it move" -- so the very first call is always a silent
## warm-up (see _last_ripple_check_position), never a trigger. Every test
## below accounts for that one warm-up frame before the forced 0.01s interval
## can actually fire.
func test_a_ripple_trigger_fires_a_burst_of_several_rings_not_just_one():
	var world := RippleTrackingWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._water_ripple_interval = 0.01  # force the next tick to trigger a burst

	marker._process(0.02)  # warm-up: establishes the prior-position sample
	for i in FishMarker.TAIL_WAG_RING_COUNT:
		marker._process(FishMarker.TAIL_WAG_RING_SPACING + 0.01)

	assert_eq(world.positions.size(), FishMarker.TAIL_WAG_RING_COUNT)


## The rings of one burst land at DIFFERENT moments (and therefore different
## positions, since the fish keeps swimming) rather than all at once on the
## triggering frame -- that's what makes it read as a streak/wake instead of
## a single fat blob.
func test_burst_rings_are_spaced_out_over_multiple_frames_not_fired_at_once():
	var world := RippleTrackingWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._water_ripple_interval = 0.01

	marker._process(0.02)  # warm-up frame: no ring yet
	assert_eq(world.positions.size(), 0, "the warm-up frame must not itself fire a ring")

	marker._process(0.02)  # crosses the interval: first ring of the burst
	assert_eq(world.positions.size(), 1, "only the burst's first ring should fire on the triggering frame")

	marker._process(FishMarker.TAIL_WAG_RING_SPACING + 0.01)
	assert_eq(world.positions.size(), 2, "the second ring should wait a full TAIL_WAG_RING_SPACING")


## After a burst finishes, the fish goes back to gliding silently for a full
## (unhurried) ripple_interval before the next wag -- it must not keep
## streaming rings continuously.
func test_no_further_rings_fire_immediately_after_a_burst_completes():
	var world := RippleTrackingWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._water_ripple_interval = 0.01

	marker._process(0.02)  # warm-up
	for i in FishMarker.TAIL_WAG_RING_COUNT:
		marker._process(FishMarker.TAIL_WAG_RING_SPACING + 0.01)
	assert_eq(world.positions.size(), FishMarker.TAIL_WAG_RING_COUNT, "precondition: burst finished")

	marker._process(0.05)  # far short of another full ripple_interval
	assert_eq(
		world.positions.size(), FishMarker.TAIL_WAG_RING_COUNT,
		"no new ring should fire until the next unhurried interval elapses"
	)


# -- ripple frequency: occasional, not continuous ----------------------------
##
## Reported live, once the diorama's fish first ran through this real timing
## in a small, always-visible pond: "The fish still produce ripples all the
## time -- only fast move flap boost should produce ripples like in the real
## ingame." Every individual ripple genuinely IS gated behind a flap burst
## (see the burst-mechanics tests just above) -- that correlation was already
## correct, and confirmed as such earlier. What was never checked is the
## other half: whether flap bursts themselves are RARE enough, relative to
## how long a single ripple stays visible (WaterShader.RIPPLE_LIFETIME, the
## shader's own fade-out), for the pond to read as "occasionally flapping"
## rather than "a ring is always fading somewhere". A burst's own LAST ring
## only finishes decaying TAIL_WAG_RING_SPACING * (TAIL_WAG_RING_COUNT - 1)
## after the burst starts, PLUS a full RIPPLE_LIFETIME -- well after the next
## burst was scheduled to start at the pre-fix RIPPLE_INTERVAL_MIN/MAX
## (1.1-2.6s), so consecutive bursts' visible rings overlapped almost every
## time -- exactly the "all the time" complaint.

## The fraction of any given moment a continuously-swimming fish's own
## ripples are visible (mid-burst, or a past ring from the last burst still
## decaying) -- derived from the actual constants, not eyeballed, so a
## future change to burst timing or RIPPLE_LIFETIME is automatically
## re-checked against this same property rather than silently drifting.
func _expected_visible_ripple_fraction() -> float:
	var last_ring_offset := FishMarker.TAIL_WAG_RING_SPACING * float(FishMarker.TAIL_WAG_RING_COUNT - 1)
	var visible_duration := last_ring_offset + WaterShader.RIPPLE_LIFETIME
	var avg_interval := (FishMarker.RIPPLE_INTERVAL_MIN + FishMarker.RIPPLE_INTERVAL_MAX) * 0.5
	var avg_cycle := last_ring_offset + avg_interval
	return visible_duration / avg_cycle


## A fish visibly rippling well under half the time reads as "occasional"
## rather than "constant" -- the property the live report actually named.
func test_ripples_stay_occasional_not_continuous_by_the_numbers():
	assert_lt(
		_expected_visible_ripple_fraction(), 0.4,
		"a fish's own ripples should visibly fade out between bursts, not overlap into constant rippling"
	)


## The same property, measured directly on a real running fish rather than
## derived algebraically -- catches anything the formula above might miss
## (the warm-up frame, actual PixelNoise-driven interval variance). Simulates
## several real minutes of continuous swimming so the seeded random
## intervals average out.
func test_a_swimming_fish_actually_goes_quiet_between_bursts_most_of_the_time():
	var world := RippleTrackingWorld.new()
	marker.setup(world, TILE_SIZE)

	var dt := 0.1
	var duration := 240.0
	var elapsed := 0.0
	var ripple_times: Array[float] = []
	var previous_count := 0
	while elapsed < duration:
		marker._process(dt)
		elapsed += dt
		if world.positions.size() > previous_count:
			for i in (world.positions.size() - previous_count):
				ripple_times.append(elapsed)
			previous_count = world.positions.size()

	var quiet_samples := 0
	var total_samples := 0
	var t := 0.0
	while t < duration:
		total_samples += 1
		var visible := false
		for ripple_time in ripple_times:
			if t >= ripple_time and t - ripple_time < WaterShader.RIPPLE_LIFETIME:
				visible = true
				break
		if not visible:
			quiet_samples += 1
		t += 1.0  # sample once a second -- fine enough to catch multi-second gaps

	var quiet_fraction := float(quiet_samples) / float(total_samples)
	assert_gt(
		quiet_fraction, 0.5,
		"the pond should visibly go quiet more than half the time -- measured only %.0f%% quiet" % (quiet_fraction * 100.0)
	)


## The movement half of "only when wagging the tail": a fish that genuinely
## cannot move (boxed into a single water tile) never fires a ripple at all,
## no matter how long it sits there -- mirrors Player._step_water_ripples'
## own gate on actually moving through the water.
func test_a_fish_that_cannot_move_at_all_never_ripples():
	var world := ConfinedRippleTrackingWorld.new()
	world.home_tile = Vector2i(6, 6)
	marker.home = Vector2(6.5 * TILE_SIZE, 6.5 * TILE_SIZE)
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)
	marker._water_ripple_interval = 0.01

	for i in 50:
		marker._process(0.3)

	assert_eq(world.positions.size(), 0, "a fish that never actually moves should never ripple")


# -- flap speed & shore-anticipation follow-up ------------------------------

## Follow-up request: "also only when they flap tail fast" -- a burst isn't
## just faster rings, the fish itself swims faster while it lasts.
func test_fish_swims_faster_during_a_wag_burst_than_while_gliding():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	marker._water_ripple_interval = 0.01
	marker._current_heading = Vector2.RIGHT

	marker._process(0.02)  # warm-up: no burst yet
	var before_trigger := marker.position
	marker._process(0.02)  # triggers the burst -- flapping this frame
	var flap_distance := before_trigger.distance_to(marker.position)

	for i in FishMarker.TAIL_WAG_RING_COUNT:  # let the burst finish
		marker._process(FishMarker.TAIL_WAG_RING_SPACING + 0.01)
	var before_glide := marker.position
	marker._process(0.02)  # an ordinary glide frame, same delta as above
	var glide_distance := before_glide.distance_to(marker.position)

	assert_gt(flap_distance, glide_distance, "a flapping fish should swim faster than a gliding one")


## Follow-up request: "avoid trying to turn into the border of the water so
## that the fish doesn't flicker when repelled from the edge" -- once the
## heading has turned away from a shore a steering target keeps pointing at,
## it must not keep swinging back toward land every other frame.
func test_heading_does_not_flicker_back_toward_land_near_a_shore():
	var world := ShorelineWorld.new()
	marker.home = Vector2(6.0 * TILE_SIZE, 6.5 * TILE_SIZE)
	marker.position = marker.home
	marker.setup(world, TILE_SIZE)
	marker.set_attraction(Vector2(20.0 * TILE_SIZE, 6.5 * TILE_SIZE))  # straight into land

	# An occasional slow correction as the fish drifts along the shore is
	# expected and fine (real "sliding along the shore" behavior); genuine
	## "flicker" is the heading swinging back and forth EVERY frame, which
	# used to happen because the smoothing target restarted its deflection
	# search from scratch (toward the always-blocked raw attraction target)
	# every single frame. Bounding total sign changes over the whole run
	# distinguishes the two: dozens of transitions across 100 frames would
	# be the old every-frame flicker; a small handful is just occasional
	# drift-correction along the wall.
	var transitions := 0
	var was_facing_away := false
	for i in 100:
		marker._process(0.1)
		var facing_away: bool = marker._current_heading.x <= 0.01
		if i > 0 and facing_away != was_facing_away:
			transitions += 1
		was_facing_away = facing_away

	assert_lte(transitions, 3, "the heading should not swing back and forth toward/away from the shore every frame")


# -- a startled fish still cannot leave the water ----------------------------
#
# The first version of the escape moved the fish directly and returned before
# the shore-clearance machinery ran, so a fish dodging a kingfisher shot
# straight out of the water and flopped across the grass -- with the bird then
# calmly following it onto land to eat it (reported exactly that way).

## A pond with a real shore: water above tile row 8, land below it, so a fish
## bolting "south" is bolting straight at the bank.
class ShoreWorld:
	func biome_at_global(_x: int, y: int) -> String:
		return "ocean" if y < 8 else "grassland"


func test_a_bolting_fish_stays_in_the_water():
	var world := ShoreWorld.new()
	var fish := FishMarker.new()
	add_child_autofree(fish)
	fish.home = Vector2(64.0, 64.0)  # tile row 4, well inside the water
	fish.position = fish.home
	fish.wander_seed = 5
	fish.setup(world, TILE_SIZE)
	# Startled from BELOW, so the escape heading points straight at the bank.
	fish.bolt_from(fish.position + Vector2(0.0, 40.0))
	for _i in 120:
		fish._process(1.0 / 60.0)
		var tile_y := int(floor(fish.position.y / float(TILE_SIZE)))
		assert_lt(
			tile_y, 8,
			"a panicking fish must not flop onto the bank (ended at %s)" % str(fish.position)
		)


func test_a_bolt_is_faster_than_an_ordinary_swim():
	assert_gt(FishMarker.BOLT_SPEED, CreatureWander.WANDER_SPEED * 2.0)


func test_a_bolt_wears_off():
	var fish := FishMarker.new()
	add_child_autofree(fish)
	fish.bolt_from(Vector2(10, 10))
	assert_true(fish.is_bolting())
	fish._process(FishMarker.BOLT_SECONDS + 0.1)
	assert_false(fish.is_bolting(), "a fish calms down again")


# -- distance-based simulation LOD (see SimulationLod, CreatureMarker's own
# _lod_step/_nearest_player_position) -------------------------------------
##
## Nothing throttled FishMarker's per-frame work before this: every fish in
## every loaded chunk ran its full swim/shore/ripple logic every single
## frame regardless of how far it was from the player, unlike CreatureMarker
## (which already throttles distant creatures to fewer, larger steps -- see
## SimulationLod's own doc comment on why: almost nothing in a loaded chunk
## is ever on screen). A fish this far out should sit idle across several
## small frames, then take one full step once enough time has actually
## accumulated -- proving the skip is a genuine throttle (time banked, not
## lost) rather than the fish simply never moving again.
func test_a_fish_far_from_the_player_does_not_take_a_full_step_every_frame():
	var world := StubWorld.new()
	marker.setup(world, TILE_SIZE)
	# Comfortably past SimulationLod's falloff distance, so this fish is
	# throttled to its slowest rate (MAX_INTERVAL_SECONDS, 0.5s).
	_add_stub_player(marker.position + Vector2(5000, 0))

	var before := marker.position
	marker._process(0.1)
	assert_eq(
		before, marker.position,
		"a fish this far from the player should not take a full step on a single 0.1s frame"
	)

	marker._process(0.1)
	marker._process(0.1)
	assert_eq(
		before, marker.position,
		"still short of the throttled interval after 0.3s accumulated"
	)

	marker._process(0.3)  # crosses the accumulated ~0.5s interval
	assert_ne(
		before, marker.position,
		"once enough time has accumulated, the throttled fish should finally take its full step"
	)
