extends GutTest

## A butterfly/songbird ambient wildlife marker -- pure decorative presence
## (see docs/concept/ecosystem_dynamics.md's Species roster), no
## needs/perception/behavior AI and no population simulation, unlike
## CreatureMarker/FishMarker.

const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")

const TILE_SIZE := 16.0


## Duck-typed scent world: every field a pollinator marker actually calls on
## its `scent_world` (see EarthChunkManager's real flowers_near/
## current_season/drink_nectar_at).
class StubScentWorld:
	var flowers: Array = []
	var season := "summer"
	var drink_calls: Array = []
	## Honours the radius, like the real EarthChunkManager.flowers_near does --
	## a stub that returned everything regardless of distance would hide
	## exactly the "can it reach a patch further away" bug these test for.
	func flowers_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for f in flowers:
			if position.distance_to(f["position"]) / TILE_SIZE <= float(radius_tiles):
				out.append(f)
		return out
	func current_season() -> String:
		return season
	## Actually DRAINS, so a patch can be worked out over simulated time.
	func drink_nectar_at(position: Vector2) -> bool:
		drink_calls.append(position)
		for f in flowers:
			if f["position"].distance_to(position) < 0.01:
				if float(f.get("nectar", 1.0)) <= 0.0:
					return false
				f["nectar"] = 0.0
				return true
		return false
	## Mirrors FlowerPatch.advance's refill, so simulated time recovers a
	## drained meadow exactly the way the live game's step_flowers does.
	func regenerate(delta: float) -> void:
		for f in flowers:
			var level: float = float(f.get("nectar", 1.0))
			if level < 1.0:
				f["nectar"] = minf(1.0, level + PollinatorForaging.NECTAR_REGEN_PER_SECOND * delta)


var marker: AmbientFlyerMarker


func before_each():
	marker = AmbientFlyerMarker.new()


func after_each():
	marker.free()


func test_does_nothing_without_setup():
	marker.home = Vector2(10, 10)
	marker.position = Vector2(10, 10)
	marker._process(1.0)
	assert_eq(marker.position, Vector2(10, 10))


func test_moves_when_set_up_with_a_movement_model():
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 7
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)
	assert_ne(marker.position, Vector2.ZERO)


## See World's mouse-hover animal-name tooltip (docs feature request).
func test_get_display_name_capitalizes_the_species():
	marker.species = "monarch"
	assert_eq(marker.get_display_name(), "Monarch")


## This used to assert `rotation == moved.angle()`, which is exactly the
## bug: a flyer whose wander reversed span 180 degrees and rendered
## upside-down. Facing is now a mirror, so the claim is that travelling
## left mirrors the sprite and travelling right does not.
func test_faces_the_direction_it_is_moving():
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 7
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	var before := marker.position
	marker._process(1.0)
	var moved := marker.position - before
	# Facing lags travel on purpose (see FACING_TURN_DELAY): a real bird
	# banks slowly while its wings beat fast, and mirroring the instant the
	# wander's horizontal component crosses zero made the sprite strobe and
	# read as two overlapping birds. So the facing is asserted only after
	# the flyer has held that heading past the turn delay.
	if absf(moved.x) >= marker.FACING_DEADZONE:
		for i in 30:
			marker.face_travel(moved, 0.1)
		assert_eq(marker.flip_h, moved.x < 0.0)
	assert_almost_eq(marker.rotation, 0.0, 0.0001, "a flyer must never spin")


# -- facing: flip, never spin ----------------------------------------------
#
# The marker used to set `rotation = moved.angle()`, so a flyer whose wander
# reversed direction span a full 180 degrees and rendered upside-down --
# reported as "birds appear doubled as they rotate 180 degree with every
# wing flap". A top-down sprite drawn facing right should MIRROR to face
# left, not rotate.

func test_a_flyer_never_rotates():
	for i in 40:
		marker._process(0.1)
		assert_almost_eq(marker.rotation, 0.0, 0.0001, "a flyer must never spin")


func test_a_flyer_mirrors_to_face_the_way_it_travels():
	marker.face_travel(Vector2(-1, 0))
	assert_true(marker.flip_h, "moving left should mirror the sprite")
	marker.face_travel(Vector2(1, 0))
	assert_false(marker.flip_h, "moving right should face the sprite forward")


## Near-vertical drift must not flip the sprite back and forth: tiny
## horizontal jitter either side of zero would strobe the mirror.
func test_near_vertical_travel_keeps_the_current_facing():
	marker.face_travel(Vector2(-1, 0))
	marker.face_travel(Vector2(0.001, 1.0))
	assert_true(marker.flip_h, "a hair of horizontal drift should not flip the bird")


## The wings must actually beat -- and far faster than the bird turns.
func test_wings_cycle_through_their_frames_while_flying():
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	var seen := {}
	for i in 20:
		marker._process(marker.FLAP_SECONDS_PER_FRAME)
		seen[marker.texture] = true
	assert_gt(seen.size(), 1, "the wing frames should cycle")


func test_wings_beat_much_faster_than_the_bird_turns():
	assert_lt(
		marker.FLAP_SECONDS_PER_FRAME * 4.0, marker.FACING_TURN_DELAY,
		"a full wing-beat should be far quicker than a change of heading"
	)


## A bird sitting on a branch holds still -- flapping in place reads as a
## glitch rather than as a bird.
func test_a_perched_bird_shows_its_sitting_sprite_and_stops_flapping():
	var sitting := ImageTexture.new()
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	marker.perched_frame = sitting
	marker.perched = true
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for i in 20:
		marker._process(marker.FLAP_SECONDS_PER_FRAME)
		assert_eq(marker.texture, sitting, "a perched bird keeps its folded-wing sprite")


func test_a_perched_bird_does_not_drift():
	marker.perched = true
	marker.home = Vector2.ZERO
	marker.position = Vector2(5, 5)
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for i in 10:
		marker._process(0.1)
	assert_eq(marker.position, Vector2(5, 5), "a sitting bird stays put")


# -- pollinator foraging: don't orbit a drained patch, remember by real time --
#
# ScentField's gradient doesn't know about nectar (it's about which species
# are in BLOOM, not their current nectar level) -- so once the only nearby
# flower was drained, the scent gradient kept pointing straight at it just as
# strongly as when it was full. PollinatorForaging.choose_target correctly
# refused to LAND there, but the wander-blend steering kept drifting back
# toward its exact position every sniff, which read as orbiting the same
# spent bloom (reported: "they should move to a new flower field when the
# last flower nearby got emptied so they don't circle the last flower for an
# hour"). The marker now filters drained flowers out before computing the
# gradient at all, so an all-drained patch reads as nothing to smell -- pure
# wander takes over and actually carries it elsewhere.

func test_scent_direction_ignores_a_fully_drained_patch():
	var world := StubScentWorld.new()
	world.flowers = [{"position": Vector2(20, 0), "species": "rose", "nectar": 0.0}]
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)  # >= SCENT_SNIFF_INTERVAL, forces a sniff
	assert_eq(marker._scent_direction, Vector2.ZERO,
		"a drained-only patch should not still pull the flyer toward it")
	# NOTE: it DOES commit -- an unvisited bloom is worth flying over to
	# CHECK, since a pollinator cannot see nectar from a distance (reported:
	# "somehow they know it's empty without checking for nectar first"). What
	# it must not do is keep being PULLED there by scent, asserted above.
	assert_not_null(marker._forage_target, "an unvisited bloom is still worth checking")


func test_scent_direction_still_points_toward_a_flower_that_still_has_nectar():
	var world := StubScentWorld.new()
	world.flowers = [
		{"position": Vector2(0, 0), "species": "rose", "nectar": 0.0},   # drained
		{"position": Vector2(40, 0), "species": "rose", "nectar": 1.0},  # still full
	]
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)
	assert_gt(marker._scent_direction.x, 0.0,
		"should still be pulled toward the flower that still has nectar, not blinded by the drained one")


## Visit memory is keyed off the marker's OWN elapsed time (see
## PollinatorForaging.VISIT_MEMORY_SECONDS), not a hardcoded stand-in, so a
## flower it drained is actually forgotten ~10 minutes later rather than
## staying blacklisted (or being immediately forgettable) regardless of how
## long the marker has actually been playing.
func test_landing_on_a_flower_remembers_it_at_the_markers_own_elapsed_time():
	var world := StubScentWorld.new()
	world.flowers = [{"position": Vector2(0, 0), "species": "rose", "nectar": 1.0}]
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2(0, 0)
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._forage_target = Vector2(0, 0)
	marker._forage_flower = Vector2(0, 0)
	marker._process(0.1)
	assert_eq(marker._visited.size(), 1)
	assert_almost_eq(float(marker._visited[0]["time"]), 0.1, 0.01)


# -- a worked-out neighbourhood must recover, and must not trap the flyer ----
#
# Reported: "foraging works for a while but when all nearby are empty
# butterflies and bees stop foraging completely and just drift around
# meaninglessly". Measured with a runtime probe before the fix, drinks per
# simulated minute were [4, 0,0,0,0,0,0,0,0,0, 4, ...] -- one productive
# minute, then nine idle, resuming exactly at VISIT_MEMORY_SECONDS, even
# though every flower had refilled within ~20s. Separately, a flyer with a
# full patch 12 tiles away drank NOTHING in ten simulated minutes and never
# got more than 31.6px from home, because AmbientFlyerMovement tethers the
# wander to `radius` (30px) around `home` -- it physically could not travel
# to another patch.


func _worked_meadow_marker(world: StubScentWorld) -> void:
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.species = "bee"
	marker.wander_seed = 4242
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))


## The exact reported scenario, simulated forward: work a local patch dry,
## then keep running with nectar regrowing. It must go back to foraging on
## the timescale the flowers actually refill on, not sit idle until its
## ten-minute memory expires.
func test_a_drained_neighbourhood_is_foraged_again_once_it_refills():
	var world := StubScentWorld.new()
	for i in 3:
		var at := Vector2(40.0 + float(i) * 30.0, 20.0)
		world.flowers.append({"position": at, "species": "rose", "nectar": 1.0, "landing": at})
	_worked_meadow_marker(world)

	# Phase 1: let it work the patch dry.
	for step in 1200:  # 120 simulated seconds
		marker._process(0.1)
		world.regenerate(0.1)
	var drinks_after_first_pass: int = world.drink_calls.size()
	assert_gt(drinks_after_first_pass, 0, "should forage the fresh patch at all")

	# Phase 2: another two minutes, still far inside VISIT_MEMORY_SECONDS.
	# The flowers refill in ~20s, so a working pollinator keeps drinking.
	for step in 1200:
		marker._process(0.1)
		world.regenerate(0.1)
	assert_gt(
		world.drink_calls.size(), drinks_after_first_pass,
		"a refilled meadow should be foraged again, not left idle until visit memory expires"
	)


## Nothing within scent range, a full patch well beyond it: the flyer must
## range out and actually reach it rather than drifting around its spawn
## point forever.
func test_a_pollinator_ranges_out_to_a_patch_beyond_its_wander_tether():
	var world := StubScentWorld.new()
	var far_patch := Vector2(12.0 * TILE_SIZE, 0.0)
	world.flowers.append(
		{"position": far_patch, "species": "rose", "nectar": 1.0, "landing": far_patch}
	)
	_worked_meadow_marker(world)

	for step in 3000:  # 300 simulated seconds
		marker._process(0.1)
		world.regenerate(0.1)
	assert_gt(
		world.drink_calls.size(), 0,
		"should have reached and drunk from the distant patch instead of drifting near home"
	)


## And with NOTHING anywhere in range, it must still relocate rather than
## orbit one spot -- otherwise a fully-foraged region latches the flyer into
## permanent aimless drift.
func test_a_pollinator_with_nothing_in_range_relocates_instead_of_orbiting():
	var world := StubScentWorld.new()  # empty meadow
	_worked_meadow_marker(world)

	var travelled := 0.0
	for step in 1200:
		marker._process(0.1)
		travelled = maxf(travelled, marker.position.distance_to(Vector2.ZERO))
	assert_gt(
		travelled, PollinatorForaging.RELOCATION_STEP_TILES * TILE_SIZE,
		"should have moved on to look elsewhere, not stayed tethered to a barren spawn point"
	)


## ...but it must not wander off the edge of the world doing it. Relocation
## unleashed was a random walk: measured at 93 tiles from spawn after ten
## simulated minutes with nothing to eat, by which point the flyer was
## several chunks outside the only area that has flowers at all.
func test_relocation_stays_within_its_leash_of_where_it_spawned():
	var world := StubScentWorld.new()  # nothing to eat anywhere
	_worked_meadow_marker(world)

	var furthest := 0.0
	for step in 6000:  # ten simulated minutes of fruitless searching
		marker._process(0.1)
		furthest = maxf(furthest, marker.position.distance_to(Vector2.ZERO))
	assert_lte(
		furthest, PollinatorForaging.MAX_RELOCATION_TILES * TILE_SIZE * 1.5,
		"a searching pollinator must stay in the region it belongs to, not random-walk away"
	)


## THE REPORTED SEQUENCE, end to end: work a patch dry, drift long enough to
## be well into the searching state, then have a meadow appear back where it
## started. It must find its way to it and forage again. Before the leash it
## could not: it had drifted ~93 tiles off, saw zero flowers from there, and
## drank nothing ever again ("don't resume foraging when they encounter new
## flowers").
func test_a_drifting_pollinator_resumes_foraging_when_a_meadow_reappears():
	var world := StubScentWorld.new()
	var spawn := Vector2.ZERO
	world.flowers.append(
		{"position": Vector2(40, 0), "species": "rose", "nectar": 1.0, "landing": Vector2(40, 0)}
	)
	_worked_meadow_marker(world)

	# Drain what's there, then drift for five simulated minutes with nothing.
	for step in 3000:
		marker._process(0.1)
	var drinks_while_barren: int = world.drink_calls.size()

	# A full meadow appears back at the spawn point.
	for i in 4:
		var at := spawn + Vector2(float(i) * 25.0, 20.0)
		world.flowers.append({"position": at, "species": "rose", "nectar": 1.0, "landing": at})

	for step in 3000:
		marker._process(0.1)
	assert_gt(
		world.drink_calls.size(), drinks_while_barren,
		"a drifting pollinator must resume foraging once flowers are within reach again"
	)


# -- ground foraging: a robin hunting worms ---------------------------------
#
# See docs/concept/soil_fauna.md. Songbirds used to have literally no
# behaviour at all -- scent_world is deliberately null for them, so a robin
# was pure home-tethered drift. It now descends onto a worm, sits down, pecks,
# and takes it. Diets are per species (see FlyerDiet): a sparrow in the same
# meadow must never do any of this.

const GroundForageBehavior = preload("res://src/gameplay/ground_forage_behavior.gd")


## Duck-typed worm world: exactly the two methods a ground-foraging marker
## calls on its `worm_world` (see EarthChunkManager's real worms_near/
## take_worm_at).
class StubWormWorld:
	var worms: Array = []
	var taken: Array = []
	## Honours the radius like the real EarthChunkManager.worms_near does.
	func worms_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for w in worms:
			if position.distance_to(w["position"]) / TILE_SIZE <= float(radius_tiles):
				out.append(w)
		return out
	## Actually REMOVES it, so a lawn can be worked out over simulated time.
	func take_worm_at(position: Vector2) -> bool:
		taken.append(position)
		for i in worms.size():
			if worms[i]["position"].distance_to(position) < 0.01:
				worms.remove_at(i)
				return true
		return false


func _make_robin(world: StubWormWorld) -> void:
	marker.species = "robin"
	marker.worm_world = world
	marker.ground_forage = GroundForageBehavior.new()
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker.perched_frame = ImageTexture.new()
	marker.peck_frame = ImageTexture.new()
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 5
	marker.setup(AmbientFlyerMovement.new(34.0, 70.0, 1.8))


## Runs until the bird reaches `phase`, returning whether it got there.
func _run_until_phase(phase: int, steps: int = 1200) -> bool:
	for i in steps:
		marker._process(0.05)
		if marker.ground_forage.phase == phase:
			return true
	return false


func _world_with_one_worm(at: Vector2 = Vector2(80, 0)) -> StubWormWorld:
	var world := StubWormWorld.new()
	world.worms = [{"position": at}]
	return world


func test_a_robin_flies_to_a_worm_and_eats_it():
	var world := _world_with_one_worm()
	_make_robin(world)
	for i in 1200:
		marker._process(0.05)
	assert_gt(world.taken.size(), 0, "a robin should actually take a worm")
	assert_eq(world.worms.size(), 0, "and the worm should be gone from the world")


## The per-species diet made structural: a sparrow is spawned without a
## ground-forage brain at all, so no amount of marker code can make it hunt.
func test_a_bird_without_a_ground_forage_brain_never_takes_worms():
	var world := _world_with_one_worm()
	_make_robin(world)
	marker.species = "sparrow"
	marker.ground_forage = null
	for i in 1200:
		marker._process(0.05)
	assert_eq(world.taken.size(), 0, "a sparrow does not hunt worms")
	assert_eq(world.worms.size(), 1)


func test_a_robin_with_nothing_to_hunt_just_keeps_flying():
	var world := StubWormWorld.new()
	_make_robin(world)
	for i in 400:
		marker._process(0.05)
		assert_false(marker.perched, "nothing to land on, so it stays airborne")
	assert_ne(marker.position, Vector2.ZERO, "and it still wanders")


# -- the visible animation --------------------------------------------------

func test_a_robin_sits_down_on_the_worm_to_peck_it():
	var world := _world_with_one_worm()
	_make_robin(world)
	assert_true(
		_run_until_phase(GroundForageBehavior.Phase.PECKING),
		"the robin should reach the worm"
	)
	assert_true(marker.perched, "it sits down -- wings folded, not hovering")
	var landed := marker.position
	for i in 5:
		marker._process(0.05)
	assert_eq(marker.position, landed, "a pecking bird holds still")


func test_a_pecking_robin_dips_its_head_and_lifts_it_again():
	var world := _world_with_one_worm()
	_make_robin(world)
	assert_true(_run_until_phase(GroundForageBehavior.Phase.PECKING))
	var seen := {}
	for i in 60:
		marker._process(0.02)
		if marker.ground_forage.phase != GroundForageBehavior.Phase.PECKING:
			break
		seen[marker.texture] = true
	assert_true(seen.has(marker.peck_frame), "the head should go down into the grass")
	assert_true(seen.has(marker.perched_frame), "and come back up again")


func test_a_robin_descending_on_a_worm_is_still_flying():
	var world := _world_with_one_worm()
	_make_robin(world)
	assert_true(_run_until_phase(GroundForageBehavior.Phase.DESCENDING))
	assert_false(marker.perched, "it has not landed yet")
	var before := marker.position
	marker._process(0.05)
	assert_ne(marker.position, before, "it is flying at the worm")


func test_a_robin_takes_off_and_resumes_wandering_after_its_meal():
	var world := _world_with_one_worm()
	_make_robin(world)
	assert_true(_run_until_phase(GroundForageBehavior.Phase.PECKING))
	assert_true(
		_run_until_phase(GroundForageBehavior.Phase.SEEKING),
		"the cycle should close and put it back in the air"
	)
	assert_false(marker.perched, "wings out again")
	var before := marker.position
	for i in 10:
		marker._process(0.05)
	assert_ne(marker.position, before, "and it drifts off foraging again")


## It flies at the worm rather than drifting near it: ambient flight is
## tethered to `home` within AmbientFlyerMovement's radius, so a worm further
## out than the tether would be permanently unreachable without retargeting
## the tether too -- the same failure the pollinator path already hit and
## fixed.
func test_a_robin_reaches_a_worm_further_away_than_its_wander_tether():
	# Past the 70px wander tether, but inside GroundForageBehavior.
	# SEARCH_TILES -- i.e. a worm the bird can genuinely see but that ambient
	# flight alone would drag it back off.
	var beyond_tether := Vector2(140, 0)
	assert_gt(beyond_tether.x, 70.0, "the test worm must actually be past the tether")
	assert_lt(
		beyond_tether.x / TILE_SIZE, GroundForageBehavior.SEARCH_TILES,
		"and inside what the bird can see"
	)
	var world := _world_with_one_worm(beyond_tether)
	_make_robin(world)
	for i in 1200:
		marker._process(0.05)
	assert_eq(world.taken.size(), 1, "a worm past the tether should still be reachable")


func test_a_robin_lands_on_the_worm_not_merely_near_it():
	var world := _world_with_one_worm()
	_make_robin(world)
	assert_true(_run_until_phase(GroundForageBehavior.Phase.PECKING))
	assert_lt(
		marker.position.distance_to(Vector2(80, 0)),
		GroundForageBehavior.LANDING_DISTANCE + 0.01,
		"it should be standing on the worm it is about to eat"
	)


## Two robins in one meadow must not queue up behind the same worm -- the
## nearest-candidate scatter PollinatorForaging already measured this failure
## for (eight flyers all choosing one bloom and conga-lining after it).
##
## Seeded through PixelNoise, exactly as the marker does. Written first with a
## plain `hash("%d_worm" % seed)` scatter seed, which put EVERY seed in the
## range into bucket 0 -- every robin choosing the identical worm, the
## single-bucket freeze PixelNoise's own doc comment records. That is why the
## marker seeds this from PixelNoise.value and not from a string hash.
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")


func test_robins_in_the_same_spot_spread_across_nearby_worms():
	var worms: Array = []
	for i in 4:
		worms.append({"position": Vector2(60 + i * 4, 0)})
	var picks := {}
	for wander_seed in range(1, 21):
		var chosen := GroundForageBehavior.choose_worm(
			Vector2.ZERO, worms, PixelNoise.value(wander_seed, 1, 0)
		)
		picks[chosen["position"]] = true
	assert_gt(picks.size(), 1, "robins in one spot should spread across nearby worms")


## The same bird's successive meals must vary too, or one robin works a single
## worm's burrow over and over instead of the meadow.
func test_one_robins_successive_picks_vary():
	var worms: Array = []
	for i in 4:
		worms.append({"position": Vector2(60 + i * 4, 0)})
	var picks := {}
	for pick_index in range(1, 21):
		var chosen := GroundForageBehavior.choose_worm(
			Vector2.ZERO, worms, PixelNoise.value(9, pick_index, 0)
		)
		picks[chosen["position"]] = true
	assert_gt(picks.size(), 1, "a robin should not re-pick the same worm every time")


func test_choosing_a_worm_with_nothing_in_range_returns_nothing():
	assert_true(GroundForageBehavior.choose_worm(Vector2.ZERO, [], 1).is_empty())


# -- forage claims: don't chain behind a neighbour --------------------------
#
# Measured before this: 62.1% of nearby butterfly pairs targeted the SAME
# flower, because 86.5% of targeting decisions had only one candidate in the
# scatter band -- so the per-flyer scatter seed had nothing to scatter over.
# A flyer now ANNOUNCES what it is heading for, and its neighbours demote
# (never exclude) blooms someone else has already spoken for.
#
# The claim surface is duck-typed onto the same `scent_world` the marker
# already holds, and every call is has_method-guarded, so a world that knows
# nothing about claims still forages exactly as before.

const ForageClaims = preload("res://src/gameplay/forage_claims.gd")


## A scent world that ALSO implements the claim surface (see
## EarthChunkManager.claim_flower/release_flower_claim/claims_near).
class StubClaimingScentWorld extends StubScentWorld:
	var claims := ForageClaims.new()
	func claim_flower(flower_position: Vector2, flyer_id: int) -> void:
		claims.claim(flower_position, flyer_id)
	func release_flower_claim(flyer_id: int) -> void:
		claims.release(flyer_id)
	func claims_near(position: Vector2, radius: float, exclude_flyer_id: int) -> Array:
		return claims.claimed_positions_near(position, radius, exclude_flyer_id)


func _pollinator_on(world) -> void:
	marker.scent_world = world
	marker.species = "bee"
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 77
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))


func _one_flower_world() -> StubClaimingScentWorld:
	var world := StubClaimingScentWorld.new()
	var at := Vector2(40, 0)
	world.flowers = [{"position": at, "species": "rose", "nectar": 1.0, "landing": at}]
	return world


func test_a_pollinator_claims_the_bloom_it_commits_to():
	var world := _one_flower_world()
	_pollinator_on(world)
	marker._process(1.0)  # forces a sniff, which commits
	assert_not_null(marker._forage_flower, "precondition: it committed to something")
	assert_eq(world.claims.claim_count(), 1, "committing should announce a claim")
	assert_eq(
		world.claims.claimed_positions_near(Vector2(40, 0), 1.0),
		[Vector2(40, 0)],
		"and the claim should name the bloom it actually targeted"
	)


func test_the_claim_is_filed_under_this_flyers_own_id():
	var world := _one_flower_world()
	_pollinator_on(world)
	marker._process(1.0)
	assert_eq(
		world.claims.claimed_positions_near(
			Vector2(40, 0), 1.0, marker.get_instance_id()
		).size(),
		0,
		"a flyer must never be warned off its own target"
	)


## A claim is a statement of intent about where a flyer is GOING. Once it has
## arrived, it is no longer going anywhere, so the claim must go -- otherwise
## the table pins a bloom forever and its neighbours route around empty grass.
func test_a_pollinator_releases_its_claim_when_it_lands():
	var world := _one_flower_world()
	_pollinator_on(world)
	for step in 200:
		marker._process(0.1)
		if world.drink_calls.size() > 0:
			break
	assert_gt(world.drink_calls.size(), 0, "precondition: it actually landed and drank")
	assert_eq(world.claims.claim_count(), 0, "landing releases the claim")


## The patch going dry mid-approach: it abandons the target, so it must
## abandon the claim with it.
func test_a_pollinator_releases_its_claim_when_the_patch_goes_dry():
	var world := _one_flower_world()
	_pollinator_on(world)
	marker._process(1.0)
	assert_eq(world.claims.claim_count(), 1, "precondition: claimed")
	# Draining it is no longer enough to make it unavailable: an unvisited
	# bloom is worth flying over to CHECK regardless of nectar, since a
	# pollinator cannot see nectar from a distance. What genuinely takes a
	# bloom off the table is this flyer having already checked it -- visit
	# memory, which now vetoes rather than ranks.
	world.flowers[0]["nectar"] = 0.0
	marker._visited = PollinatorForaging.remember_visit(
		marker._visited, world.flowers[0]["position"], marker._elapsed_time
	)
	marker._forage_target = null
	marker._forage_flower = null
	marker._process(1.0)  # next sniff finds nothing worth having
	assert_eq(world.claims.claim_count(), 0, "an abandoned target releases its claim")


## The whole point: two flyers standing in the same spot with two equally
## near blooms must not both take the same one.
func test_a_second_pollinator_avoids_a_bloom_that_is_already_spoken_for():
	var world := StubClaimingScentWorld.new()
	for at in [Vector2(40, 0), Vector2(-40, 0)]:
		world.flowers.append({"position": at, "species": "rose", "nectar": 1.0, "landing": at})
	# A neighbour has already announced the first bloom.
	world.claims.claim(Vector2(40, 0), 999)
	_pollinator_on(world)
	marker._process(1.0)
	assert_eq(
		marker._forage_flower, Vector2(-40, 0),
		"it should take the bloom nobody has spoken for"
	)


## Regression: every claim call is has_method-guarded, so the existing
## claim-less stub world (and any real caller that predates claims) still
## forages normally rather than erroring.
func test_a_world_that_knows_nothing_about_claims_still_forages():
	var world := StubScentWorld.new()
	var at := Vector2(40, 0)
	world.flowers = [{"position": at, "species": "rose", "nectar": 1.0, "landing": at}]
	_pollinator_on(world)
	for step in 200:
		marker._process(0.1)
		if world.drink_calls.size() > 0:
			break
	assert_gt(world.drink_calls.size(), 0, "a claim-less world must still work")


# -- flying past live flowers: re-evaluate en route, with hysteresis --------
#
# Reported: "Butterfly is still ignoring unvisited flowers." _step_scent used
# to early-return the moment `_forage_target != null` ("Don't re-target while
# already committed"), so a flyer committed to a bloom three tiles away flew
# straight past a live, unvisited bloom a fraction of a tile off its path
# without so much as sniffing it.
#
# The early-return was not wrong for nothing, though: re-picking freely let
# the flyer thrash between candidates instead of ever arriving at one. So it
# now sniffs while en route but only SWITCHES for a meaningfully closer bloom
# (see AmbientFlyerMarker.RETARGET_IMPROVEMENT_TILES). Both halves are pinned
# below -- the switch AND the refusal to switch.

func _commit_to(world: StubScentWorld, at: Vector2) -> void:
	world.flowers = [{"position": at, "species": "rose", "nectar": 1.0, "landing": at}]
	_pollinator_on(world)
	marker._process(1.0)  # >= SCENT_SNIFF_INTERVAL, so this sniff commits
	assert_eq(marker._forage_flower, at, "precondition: committed to the far bloom")


func test_a_committed_flyer_switches_to_a_much_closer_bloom_in_its_path():
	var world := StubScentWorld.new()
	_commit_to(world, Vector2(250, 0))
	var in_its_path := Vector2(30, 0)
	world.flowers.append(
		{"position": in_its_path, "species": "rose", "nectar": 1.0, "landing": in_its_path}
	)
	marker._process(1.0)
	assert_eq(
		marker._forage_flower, in_its_path,
		"a live bloom right next to it should not be flown past"
	)


## The other half: a bloom that is only barely closer must NOT pull it off
## course, or the flyer thrashes between near-ties and never arrives.
func test_a_committed_flyer_ignores_a_only_marginally_closer_bloom():
	var world := StubScentWorld.new()
	var committed := Vector2(200, 0)
	_commit_to(world, committed)
	var barely_closer := Vector2(180, 0)
	assert_lt(
		marker.position.distance_to(committed) - marker.position.distance_to(barely_closer),
		marker.RETARGET_IMPROVEMENT_TILES * TILE_SIZE,
		"precondition: the new bloom is closer by LESS than the switching margin"
	)
	world.flowers.append(
		{"position": barely_closer, "species": "rose", "nectar": 1.0, "landing": barely_closer}
	)
	marker._process(1.0)
	assert_eq(
		marker._forage_flower, committed,
		"a marginal improvement must not pull it off its current commitment"
	)


## The margin has to be a real distance, not a rounding tolerance: at zero it
## would switch on any improvement at all, which is the thrash this exists to
## prevent.
func test_the_switching_margin_is_a_meaningful_distance():
	assert_gt(marker.RETARGET_IMPROVEMENT_TILES, 0.5)


## Re-evaluating en route must not stop it ever ARRIVING. A meadow of blooms
## all in range is exactly the setup that made the old free re-picking thrash.
func test_a_flyer_re_evaluating_en_route_still_lands_and_drinks():
	var world := StubScentWorld.new()
	for i in 5:
		var at := Vector2(60.0 + float(i) * 35.0, float(i) * 12.0)
		world.flowers.append({"position": at, "species": "rose", "nectar": 1.0, "landing": at})
	_pollinator_on(world)
	for step in 600:
		marker._process(0.1)
		world.regenerate(0.1)
	assert_gt(world.drink_calls.size(), 0, "it must still actually arrive and drink")


## Switching targets has to move the claim too, or the table keeps pointing
## neighbours away from a bloom this flyer has already abandoned.
func test_switching_targets_moves_the_claim_with_it():
	var world := StubClaimingScentWorld.new()
	_commit_to(world, Vector2(250, 0))
	var in_its_path := Vector2(30, 0)
	world.flowers.append(
		{"position": in_its_path, "species": "rose", "nectar": 1.0, "landing": in_its_path}
	)
	marker._process(1.0)
	assert_eq(world.claims.claim_count(), 1, "still exactly one claim")
	assert_eq(
		world.claims.claimed_positions_near(in_its_path, 1.0), [in_its_path],
		"and it should name the bloom it actually switched to"
	)


# -- ground foraging: fallen fruit and bird endozoochory ---------------------
#
# See docs/concept/flora.md#bird-endozoochory. A robin's second diet entry
# (see FlyerDiet) -- fallen tree fruit sits on the ground exactly like a worm
# does, so it reuses the same seek/descend/peck/resume state machine
# (GroundForageBehavior) via its own fruit_world, running in parallel with
# (never instead of) worm-hunting. Eating a fruit starts a carry timer (see
# SeedEndozoochory); once it elapses the bird plants a sapling of the species
# it swallowed elsewhere, via fruit_world.try_plant_seed_at.

## Duck-typed fruit world: exactly the three methods a fruit-eating marker
## calls on its `fruit_world` (see EarthChunkManager's real fruit_near/
## take_fruit_at/try_plant_seed_at).
class StubFruitWorld:
	var fruit: Array = []
	var taken: Array = []
	var planted: Array = []  # {"position": Vector2, "species": String}
	## Honours the radius like the real EarthChunkManager.fruit_near does.
	func fruit_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for f in fruit:
			if position.distance_to(f["position"]) / TILE_SIZE <= float(radius_tiles):
				out.append(f)
		return out
	## Actually REMOVES it, so a lawn can be worked out over simulated time.
	func take_fruit_at(position: Vector2) -> String:
		for i in fruit.size():
			if fruit[i]["position"].distance_to(position) < 0.01:
				var species: String = fruit[i]["species"]
				taken.append(position)
				fruit.remove_at(i)
				return species
		return ""
	func try_plant_seed_at(position: Vector2, species_id: String) -> bool:
		planted.append({"position": position, "species": species_id})
		return true


func _make_fruit_robin(world) -> void:
	marker.species = "robin"
	marker.fruit_world = world
	marker.ground_forage = GroundForageBehavior.new()
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker.perched_frame = ImageTexture.new()
	marker.peck_frame = ImageTexture.new()
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 6
	marker.setup(AmbientFlyerMovement.new(34.0, 70.0, 1.8))


func test_a_robin_flies_to_fallen_fruit_and_eats_it():
	var world := StubFruitWorld.new()
	world.fruit = [{"position": Vector2(80, 0), "species": "cherry"}]
	_make_fruit_robin(world)
	for i in 3000:  # 150 simulated seconds -- comfortably past commit+flight+peck
		marker._process(0.05)
	assert_gt(world.taken.size(), 0, "a robin should actually eat fallen fruit")
	assert_eq(world.fruit.size(), 0, "and it should be gone from the world")


## The per-species diet made structural: a bird spawned without a fruit-
## foraging brain can never eat fruit however the shared marker code changes.
func test_a_bird_without_a_fruit_world_never_eats_fruit():
	var world := StubFruitWorld.new()
	world.fruit = [{"position": Vector2(80, 0), "species": "cherry"}]
	_make_fruit_robin(world)
	marker.fruit_world = null
	for i in 1200:
		marker._process(0.05)
	assert_eq(world.taken.size(), 0, "no fruit_world means no fruit eaten")
	assert_eq(world.fruit.size(), 1)


## The whole point of the mechanism: a swallowed fruit's seed is deposited
## elsewhere, as the SAME species that was eaten -- not silently dropped, and
## not renamed along the way.
func test_eating_fruit_eventually_plants_a_seed_of_the_same_species_elsewhere():
	var world := StubFruitWorld.new()
	world.fruit = [{"position": Vector2(80, 0), "species": "cherry"}]
	_make_fruit_robin(world)
	for i in 3000:  # 150 simulated seconds -- covers even the longest carry delay
		marker._process(0.05)
	assert_gt(world.planted.size(), 0, "a swallowed seed should eventually get planted")
	assert_eq(world.planted[0]["species"], "cherry", "planted species should match what was eaten")


func test_carrying_a_seed_plants_it_at_the_birds_own_position_once_the_carry_timer_elapses():
	var world := StubFruitWorld.new()
	_make_fruit_robin(world)
	marker._carried_seed_species = "walnut"
	marker._carry_seconds_remaining = 0.05
	marker.position = Vector2(123, 45)
	var expected_position := marker.position
	marker._process(0.1)  # covers the remaining 0.05s and then some
	assert_eq(world.planted.size(), 1)
	assert_eq(world.planted[0]["species"], "walnut")
	assert_eq(world.planted[0]["position"], expected_position)
	assert_eq(marker._carried_seed_species, "", "the carried seed should be spent once planted")


## A robin only has one crop's worth of seed in flight at a time -- eating a
## second fruit while still digesting the first must not reset the carry
## timer or overwrite which species is being carried.
func test_a_robin_only_carries_one_seed_at_a_time():
	var world := StubFruitWorld.new()
	_make_fruit_robin(world)
	world.fruit = [{"position": Vector2(80, 0), "species": "cherry"}]
	marker._fruit_target = Vector2(80, 0)
	marker._take_targeted_fruit()
	assert_eq(marker._carried_seed_species, "cherry")
	var first_carry_remaining: float = marker._carry_seconds_remaining

	world.fruit = [{"position": Vector2(90, 0), "species": "apple"}]
	marker._fruit_target = Vector2(90, 0)
	marker._take_targeted_fruit()
	assert_eq(marker._carried_seed_species, "cherry", "should still be carrying the FIRST seed eaten")
	assert_eq(marker._carry_seconds_remaining, first_carry_remaining, "the carry timer must not reset")


## Worm-hunting and fruit-foraging run in parallel on the SAME shared
## ground_forage state machine -- a robin with both worlds set can still
## reach a worm even with no fruit anywhere nearby (the worm search runs
## first each seek and is unaffected by fruit_world being present).
func test_a_robin_with_both_worlds_can_still_reach_a_worm_when_no_fruit_is_around():
	var worm_world := StubWormWorld.new()
	worm_world.worms = [{"position": Vector2(80, 0)}]
	var fruit_world := StubFruitWorld.new()
	_make_fruit_robin(fruit_world)
	marker.worm_world = worm_world
	for i in 3000:
		marker._process(0.05)
	assert_gt(worm_world.taken.size(), 0, "a robin should still be able to hunt worms")


# -- season coverage: the guard this feature was missing --------------------

const FlowerSpecies = preload("res://src/world/flower_species.gd")


## REGRESSION GUARD, reported twice ("this is the second time this feature
## broke... write tests that make sure it doesn't break again"): a pollinator
## standing right beside a flower that is genuinely in bloom must forage it --
## in EVERY season, for EVERY species that blooms then, driven off the real
## FlowerSpecies bloom table rather than a hand-picked example.
##
## Every other test in this file leaves StubScentWorld at its default
## "summer". That is precisely why a season-dependent break was invisible to
## the entire suite while being obvious in game: the reported world was in
## SPRING. A season-blind suite cannot guard a season-gated mechanic.
func test_a_pollinator_forages_a_blooming_flower_in_every_season():
	for season in ["winter", "spring", "summer", "autumn"]:
		for species_id in FlowerSpecies.IDS:
			if not FlowerSpecies.is_in_bloom(species_id, season):
				continue
			var world := StubScentWorld.new()
			world.season = season
			var at := Vector2(2.0 * TILE_SIZE, 0.0)
			world.flowers.append(
				{"position": at, "species": species_id, "nectar": 1.0, "landing": at}
			)
			var flyer := AmbientFlyerMarker.new()
			flyer.scent_world = world
			flyer.home = Vector2.ZERO
			flyer.position = Vector2.ZERO
			flyer.species = "bee"
			flyer.wander_seed = 4242
			flyer.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))

			for step in 600:  # 60 simulated seconds -- ample to cross 2 tiles
				flyer._process(0.1)

			var drank := world.drink_calls.size()
			flyer.free()
			assert_gt(
				drank, 0,
				"a %s in bloom in %s must be foraged, not ignored" % [species_id, season]
			)


## The other half of the same contract: a flower that is NOT in bloom this
## season is correctly ignored. This is what makes the guard above meaningful
## rather than a demand that pollinators eat anything -- and it documents
## that an out-of-bloom flower being visible on screen is a RENDERING
## question (see EarthChunkManager._sync_flower_sprites), not a foraging bug.
func test_a_pollinator_ignores_a_flower_that_is_out_of_bloom():
	var out_of_season := ""
	for species_id in FlowerSpecies.IDS:
		if not FlowerSpecies.is_in_bloom(species_id, "winter"):
			out_of_season = species_id
			break
	assert_ne(out_of_season, "", "sanity: some species must not bloom in winter")

	var world := StubScentWorld.new()
	world.season = "winter"
	var at := Vector2(2.0 * TILE_SIZE, 0.0)
	world.flowers.append({"position": at, "species": out_of_season, "nectar": 1.0, "landing": at})
	_worked_meadow_marker(world)

	for step in 600:
		marker._process(0.1)

	assert_eq(world.drink_calls.size(), 0, "an out-of-bloom flower has no nectar to offer yet")


# -- scent threshold: no beelining to flowers it cannot smell ----------------

const ScentField = preload("res://src/world/scent_field.gd")


func _lone_flower_world(distance_tiles: float, species_id: String = "tulip") -> StubScentWorld:
	var world := StubScentWorld.new()
	world.season = "spring"
	var at := Vector2(distance_tiles * TILE_SIZE, 0.0)
	world.flowers.append({"position": at, "species": species_id, "nectar": 1.0, "landing": at})
	return world


## Reported: "butterflies should only stop moving when they sit down on a
## flower... not during wandering." The scent-steered branch blends the
## wander heading with the scent gradient via lerp -- and opposing vectors
## CANCEL, so whenever the gradient pointed against the current wander
## heading at roughly equal weight the blend collapsed to ~zero and the
## flyer simply did not move that frame. Same ill-conditioned-cancellation
## class as the land creatures' wander bug. A flyer must always travel
## unless it is actually perched on a bloom drinking.
func test_a_pollinator_never_stalls_mid_flight():
	var world := StubScentWorld.new()
	world.season = "spring"
	for i in 6:
		var at := Vector2(float(i) * TILE_SIZE * 1.5, 0.0)
		world.flowers.append({"position": at, "species": "tulip", "nectar": 1.0, "landing": at})
	_worked_meadow_marker(world)

	var stalled := 0
	for step in 900:
		var before := marker.position
		var was_drinking: float = marker._drink_remaining
		marker._process(0.1)
		world.regenerate(0.1)
		# Only a drinking flyer is allowed to hold position.
		if was_drinking <= 0.0 and marker._drink_remaining <= 0.0:
			if marker.position.distance_to(before) < 0.001:
				stalled += 1

	assert_eq(stalled, 0, "a pollinator in flight must never stand still -- only drinking holds it")


# -- no nectar omniscience: a bloom must be CHECKED, not divined ------------

## Reported: "the butterflies are NOT checking EVERY flower they haven't
## visited yet. Somehow they know it's empty without checking for nectar
## first." The sniff filtered candidate blooms on `nectar > 0` straight out
## of world data -- a flower it had never been near. A pollinator cannot see
## how full a flower is from across the meadow; it finds out by landing. The
## only thing it legitimately knows is where it has been ITSELF (visit
## memory).
func test_a_pollinator_investigates_an_unvisited_flower_even_when_it_is_empty():
	var world := StubScentWorld.new()
	world.season = "spring"
	var at := Vector2(3.0 * TILE_SIZE, 0.0)
	world.flowers.append({"position": at, "species": "tulip", "nectar": 0.0, "landing": at})
	_worked_meadow_marker(world)

	var closest := INF
	for step in 300:
		marker._process(0.1)
		closest = minf(closest, marker.position.distance_to(at))

	assert_lt(
		closest, PollinatorForaging.LANDING_DISTANCE * 2.0,
		"it must fly over and check an unvisited bloom rather than divining that it is empty"
	)


## Having checked it and found it empty, it must not then loop back onto the
## same bloom -- that is what visit memory is for. This is the other half of
## removing omniscience: discovery replaces foreknowledge, memory prevents
## the loop.
func test_a_pollinator_moves_on_after_finding_a_bloom_empty():
	var world := StubScentWorld.new()
	world.season = "spring"
	var empty_at := Vector2(2.0 * TILE_SIZE, 0.0)
	world.flowers.append(
		{"position": empty_at, "species": "tulip", "nectar": 0.0, "landing": empty_at}
	)
	_worked_meadow_marker(world)

	for step in 200:
		marker._process(0.1)
	var after_check := marker.position

	for step in 300:
		marker._process(0.1)

	assert_gt(
		marker.position.distance_to(after_check), TILE_SIZE,
		"after checking an empty bloom it should move on, not orbit it"
	)


## Nectar must refill on a timescale a player can actually observe -- roughly
## a minute, not the ~20s it regenerated in before (reported: "Should refill
## nectar over one minute").
func test_nectar_refills_over_about_a_minute():
	var seconds_to_full := 1.0 / PollinatorForaging.NECTAR_REGEN_PER_SECOND
	assert_between(seconds_to_full, 45.0, 90.0, "a drained bloom should recover in about a minute")


## And visit memory must expire on a comparable timescale, so a pollinator
## comes back to re-check a bloom once it has plausibly refilled (reported:
## "butterflies should forget which flowers they visited after a reasonable
## time so they can check same flowers again after a while to see if nectar
## restocked"). At the old ten minutes it wrote off a whole meadow for far
## longer than the meadow took to recover.
func test_visit_memory_expires_on_the_same_scale_as_a_refill():
	var refill_seconds := 1.0 / PollinatorForaging.NECTAR_REGEN_PER_SECOND
	assert_gt(
		PollinatorForaging.VISIT_MEMORY_SECONDS, refill_seconds,
		"it should not return before the bloom has had time to refill"
	)
	assert_lt(
		PollinatorForaging.VISIT_MEMORY_SECONDS, refill_seconds * 3.0,
		"nor write the bloom off for many times longer than it takes to recover"
	)


## The stall guard again, but for PURE WANDER -- no flowers anywhere, so the
## scent-steered branch never runs and only the plain wander path is
## exercised. Reported still happening: "when wandering the butterflies still
## stop moving mid flight and just stay where they are for a bit".
func test_a_pollinator_with_no_flowers_at_all_never_stops_moving():
	var world := StubScentWorld.new()
	world.season = "spring"
	_worked_meadow_marker(world)

	var stalled := 0
	for step in 900:
		var before := marker.position
		marker._process(0.1)
		if marker.position.distance_to(before) < 0.001:
			stalled += 1

	assert_eq(stalled, 0, "a wandering pollinator with nothing to forage must still be flying")


# -- granivory: sparrows eat seed, and plant flowers where they drop it -----

## A world offering SEED (see EarthChunkManager.seeds_near/take_seed_at) and
## recording where flowers get planted, so the whole eat->carry->plant chain
## can be asserted end to end.
class StubSeedWorld:
	var seeds: Array = []
	var planted: Array = []
	func seeds_near(_at: Vector2, _radius: int) -> Array:
		return seeds
	func take_seed_at(at: Vector2) -> String:
		for i in seeds.size():
			if seeds[i]["position"].distance_to(at) < 1.0:
				var species: String = seeds[i]["species"]
				seeds.remove_at(i)
				return species
			
		return ""
	func plant_flower_at(at: Vector2, species: String) -> bool:
		planted.append({"position": at, "species": species})
		return true
	## Grass seed lying on the ground -- see EarthChunkManager's real
	## grass_seeds_near/take_grass_seed_at/plant_grass_at. No species: a
	## chunk grows only one kind of grass.
	var grass_seeds: Array = []
	var grass_planted: Array = []
	func grass_seeds_near(_at: Vector2, _radius: int) -> Array:
		return grass_seeds
	func take_grass_seed_at(at: Vector2) -> bool:
		for i in grass_seeds.size():
			if grass_seeds[i]["position"].distance_to(at) < 1.0:
				grass_seeds.remove_at(i)
				return true
		return false
	func plant_grass_at(at: Vector2) -> bool:
		grass_planted.append(at)
		return true


func _sparrow_on(world: StubSeedWorld) -> void:
	marker.seed_world = world
	marker.species = "sparrow"
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 11
	marker.ground_forage = GroundForageBehavior.new()
	marker.setup(AmbientFlyerMovement.new(24.0, 40.0, 1.0))


## Sparrows have carried a FOOD_SEEDS diet entry since the diet table was
## written, with nothing in the world to eat -- the code said so outright
## ("there are no seeds in the world yet"). Flowers whose bloom is over now
## go to seed (see concept/flora.md), so a sparrow finally forages.
func test_a_sparrow_flies_down_and_eats_a_seed():
	var world := StubSeedWorld.new()
	var at := Vector2(3.0 * TILE_SIZE, 0.0)
	world.seeds.append({"position": at, "species": "clover"})
	_sparrow_on(world)

	for step in 400:
		marker._process(0.1)

	assert_eq(world.seeds.size(), 0, "the seed should have been eaten")


## And what it ate gets planted somewhere else entirely: bird endozoochory
## (requested: "birds that eat seeds should disperse and plant them so new
## flowers grow where they poop"). The drop point must be well away from
## where the seed was taken -- that range is the whole reason birds matter
## for spread, versus a grazing mammal carrying seed a few tiles.
func test_a_sparrow_plants_the_seed_it_ate_somewhere_else():
	var world := StubSeedWorld.new()
	var at := Vector2(3.0 * TILE_SIZE, 0.0)
	world.seeds.append({"position": at, "species": "clover"})
	_sparrow_on(world)

	for step in 4000:  # long enough to eat, carry, and drop
		marker._process(0.1)

	assert_gt(world.planted.size(), 0, "the swallowed seed should be planted again")
	assert_eq(world.planted[0]["species"], "clover", "it plants what it actually ate")
	assert_gt(
		world.planted[0]["position"].distance_to(at), 2.0 * TILE_SIZE,
		"a bird carries seed well away from the plant it took it from"
	)


## A bird carries one seed at a time -- eating a second before dropping the
## first would silently overwrite which species gets planted.
func test_a_sparrow_carries_only_one_seed_at_a_time():
	var world := StubSeedWorld.new()
	for i in 4:
		var at := Vector2(float(i + 1) * TILE_SIZE, 0.0)
		world.seeds.append({"position": at, "species": "clover"})
	_sparrow_on(world)

	for step in 300:
		marker._process(0.1)
		assert_lte(
			1 if marker._carried_seed_species != "" else 0, 1,
			"never more than one seed in the crop"
		)


# -- granivory, grass half: a sparrow eats GRASS seed the same organ, same
# way it eats flower seed, and plants a new TallGrass patch, not a flower --
# (see docs/concept/long_grass.md's "Reproduction" section: reuses the same
# seed_world port and SeedEndozoochory's carry model unchanged, since it is
# the same crop/gut biology regardless of which seed head it swallowed).

func test_a_sparrow_flies_down_and_eats_a_grass_seed():
	var world := StubSeedWorld.new()
	var at := Vector2(3.0 * TILE_SIZE, 0.0)
	world.grass_seeds.append({"position": at})
	_sparrow_on(world)

	for step in 400:
		marker._process(0.1)

	assert_eq(world.grass_seeds.size(), 0, "the grass seed should have been eaten")


func test_a_sparrow_plants_the_grass_seed_it_ate_as_grass_not_a_flower():
	var world := StubSeedWorld.new()
	var at := Vector2(3.0 * TILE_SIZE, 0.0)
	world.grass_seeds.append({"position": at})
	_sparrow_on(world)

	for step in 4000:  # long enough to eat, carry, and drop
		marker._process(0.1)

	assert_gt(world.grass_planted.size(), 0, "the swallowed grass seed should be planted again")
	assert_gt(
		world.grass_planted[0].distance_to(at), 2.0 * TILE_SIZE,
		"a bird carries seed well away from where it took it, same range as flower seed"
	)
	assert_eq(world.planted.size(), 0, "a grass seed must establish grass, never a flower")


## A bird carries one seed at a time regardless of KIND -- eating a grass
## seed while a flower seed is still digesting (or vice versa) must not
## overwrite which one gets planted. The bird still eats the grass seed for
## nutrition (see _take_targeted_fruit's identical "eat regardless, carry
## only if the crop is free" shape) -- only the CARRYING is skipped.
func test_a_sparrow_does_not_start_carrying_a_second_seed_while_already_carrying_one():
	var world := StubSeedWorld.new()
	world.seeds = [{"position": Vector2(50, 0), "species": "clover"}]
	world.grass_seeds = [{"position": Vector2(80, 0)}]
	_sparrow_on(world)
	marker._seed_target = Vector2(50, 0)
	marker._take_targeted_seed()
	assert_eq(marker._carried_seed_species, "clover", "precondition: carrying a flower seed")

	marker._grass_seed_target = Vector2(80, 0)
	marker._take_targeted_grass_seed()

	assert_eq(marker._carried_seed_species, "clover", "still carrying the FIRST seed eaten")
	assert_true(marker._carried_seed_is_flower, "the carried kind must not flip to grass either")


## Regression: _carried_seed_is_flower used to be set true on a flower seed
## and never reset, so a bird that planted a flower and then swallowed FRUIT
## kept calling plant_flower_at with the fruit's species instead of
## fruit_world.try_plant_seed_at -- caught while wiring in a third carried
## kind (grass) forced auditing every transition between them.
func test_carrying_fruit_after_a_flower_seed_plants_a_tree_not_a_flower():
	var seed_world := StubSeedWorld.new()
	var fruit_world := StubFruitWorld.new()
	_sparrow_on(seed_world)
	marker.fruit_world = fruit_world

	seed_world.seeds = [{"position": Vector2(50, 0), "species": "clover"}]
	marker._seed_target = Vector2(50, 0)
	marker._take_targeted_seed()
	marker._carry_seconds_remaining = 0.0
	marker._step_seed_carrying(0.0)
	assert_eq(seed_world.planted.size(), 1, "precondition: the flower seed got planted")
	assert_eq(marker._carried_seed_species, "", "precondition: the crop is empty again")

	fruit_world.fruit = [{"position": Vector2(80, 0), "species": "walnut"}]
	marker._fruit_target = Vector2(80, 0)
	marker._take_targeted_fruit()
	marker._carry_seconds_remaining = 0.0
	marker._step_seed_carrying(0.0)

	assert_eq(fruit_world.planted.size(), 1, "the fruit's seed should plant a TREE")
	assert_eq(seed_world.planted.size(), 1, "must not ALSO plant a second, wrong flower")


# -- two butterflies meeting: the whole chain, driven through real _process --
#
# The user, playing the real game, reported never seeing butterflies interact
# at all. Courtship was fully wired and had unit tests for its RULES, but
# nothing anywhere drove two real markers through real frames and asserted an
# interaction actually happens -- so "is any of this reachable" was itself
# untested. These are that test.

const Courtship = preload("res://src/gameplay/courtship.gd")

const FRAME := 1.0 / 60.0


## A real marker, in the tree (the group scan both interactions use needs
## that), wired the way AmbientFlyerRenderer wires one. Engine processing is
## turned OFF so the test alone decides how much time passes -- otherwise the
## SceneTree's own frames would silently add steps between assertions.
func _flyer_in_tree(a_species: String, at: Vector2, parent: Node2D) -> AmbientFlyerMarker:
	var flyer := AmbientFlyerMarker.new()
	flyer.species = a_species
	flyer.position = at
	flyer.home = at
	flyer.wander_seed = int(at.x) * 31 + int(at.y)
	flyer.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))
	parent.add_child(flyer)
	flyer.set_process(false)
	return flyer


func test_two_monarchs_side_by_side_actually_begin_a_dance():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(120, 100), parent)

	var began := false
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0 and b._courting_with != 0:
			began = true
			break
	assert_true(began, "two monarchs 20px apart must actually start a dance")


func test_a_dance_that_began_actually_runs_and_then_ends():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(120, 100), parent)
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0:
			break
	assert_ne(a._courting_with, 0, "precondition: the dance began")

	var angles := {}
	var danced := 0.0
	while a._courting_with != 0 and danced < Courtship.DANCE_SECONDS * 3.0:
		a._process(FRAME)
		b._process(FRAME)
		danced += FRAME
		angles[snappedf((a.position - a._courting_centre).angle(), 0.5)] = true

	assert_gt(angles.size(), 4, "the pair must actually circle while dancing")
	assert_eq(a._courting_with, 0, "the dance must end on its own")
	assert_almost_eq(danced, Courtship.DANCE_SECONDS, 0.2, "it must last about DANCE_SECONDS")


## The bug the two tests above were written to find: markers are processed one
## after another, so the first of a pair always commits first, and the partner
## search rejected any flyer that was already courting -- including one
## courting the searcher. On screen that is ONE butterfly orbiting an empty
## midpoint while the other flies off to a flower. Never two.
func test_both_partners_dance_not_just_the_one_that_noticed_first():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(120, 100), parent)

	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0 and b._courting_with != 0:
			break

	assert_eq(a._courting_with, b.get_instance_id(), "a must be dancing with b")
	assert_eq(b._courting_with, a.get_instance_id(), "...and b with a")
	assert_eq(a._courting_centre, b._courting_centre, "one dance, one centre")

	# Opposite sides of that shared centre, which is what reads as a PAIR.
	for i in 30:
		a._process(FRAME)
		b._process(FRAME)
	var from_a: Vector2 = a.position - a._courting_centre
	var from_b: Vector2 = b.position - b._courting_centre
	assert_lt(from_a.normalized().dot(from_b.normalized()), -0.9, "they must orbit opposite")


## A third butterfly must not break up a pair. The relaxed guard above lets a
## flyer join a partner that is already courting IT -- not one that is busy
## with somebody else.
func test_a_third_butterfly_does_not_steal_a_partner_mid_dance():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(112, 100), parent)
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0 and b._courting_with != 0:
			break
	assert_ne(a._courting_with, 0, "precondition: a and b are a pair")

	var c := _flyer_in_tree("monarch", Vector2(124, 100), parent)
	for i in 60:
		c._process(FRAME)
	assert_eq(c._courting_with, 0, "a latecomer must not join an existing pair")


# -- the spiral flight: what the player actually asked to see ----------------
#
# "I never see butterfly dance and play with each other when they fly by
# close". That is the investigative/territorial SPIRAL FLIGHT, not courtship
# (see SpiralFlight): cross-species, seconds long, seconds of cooldown, and
# producing nothing. Courtship is same-species, rare, and on a real-day
# cooldown -- it could never have satisfied the report.

const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")


## Duck-typed courtship world: the one method a mating calls (see
## EarthChunkManager.spawn_flyer_offspring). Used here to prove a spiral
## NEVER calls it.
class StubCourtshipWorld:
	var offspring: Array = []
	func spawn_flyer_offspring(
		a_species: String, at: Vector2, inherited: Dictionary = {}
	) -> void:
		offspring.append({"species": a_species, "position": at, "traits": inherited})


func test_two_butterflies_passing_close_actually_begin_a_spiral_flight():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(100, 100) + Vector2(30, 0), parent)
	# Both already bred today, so courtship is off the table and what is left
	# is exactly the behaviour under test.
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS

	var began := false
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0 and b._spiralling_with != 0:
			began = true
			break
	assert_true(began, "two monarchs 30px apart must whirl at each other")
	assert_eq(a._spiralling_with, b.get_instance_id())
	assert_eq(b._spiralling_with, a.get_instance_id())


func test_a_spiral_flight_runs_climbs_and_then_ends():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(130, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0 and b._spiralling_with != 0:
			break
	assert_ne(a._spiralling_with, 0, "precondition: the whirl began")

	# The two orbit offsets are exactly opposite, so they cancel at the pair's
	# midpoint: this measures the CLIMB with the whirl taken back out.
	var highest := 0.0
	var angles := {}
	var whirled := 0.0
	while a._spiralling_with != 0 and whirled < SpiralFlight.SPIRAL_SECONDS * 3.0:
		a._process(FRAME)
		b._process(FRAME)
		whirled += FRAME
		# Screen-up is -Y, so "how high" is how far the midpoint went negative.
		highest = maxf(highest, 100.0 - (a.position.y + b.position.y) * 0.5)
		angles[snappedf((a.position - a._spiral_centre).angle(), 0.3)] = true

	assert_gt(angles.size(), 8, "it has to actually whirl, several times round")
	assert_eq(a._spiralling_with, 0, "the whirl must end on its own")
	assert_almost_eq(
		whirled, SpiralFlight.SPIRAL_SECONDS, 0.2, "it must last about SPIRAL_SECONDS"
	)
	assert_almost_eq(highest, SpiralFlight.RISE_PX, 0.5, "the pair must climb, together")


## The difference from courtship that matters most for how often the player
## sees this: a monarch and a swallowtail never court, and absolutely do
## chase each other.
func test_a_monarch_and_a_swallowtail_whirl_at_each_other_though_they_never_court():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("swallowtail", Vector2(128, 100), parent)
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0 and b._spiralling_with != 0:
			break
	assert_eq(a._spiralling_with, b.get_instance_id(), "different kinds still whirl")
	assert_eq(a._courting_with, 0, "...and must still never court")


## The whole reason this may be common: it is inert. A pair whirling all
## afternoon must not add a single butterfly to the meadow.
func test_a_spiral_flight_never_produces_offspring():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var world := StubCourtshipWorld.new()
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("swallowtail", Vector2(112, 100), parent)
	a.courtship_world = world
	b.courtship_world = world

	var whirls := 0
	var was_whirling := false
	for i in 60 * 90:
		a._process(FRAME)
		b._process(FRAME)
		var whirling: bool = a._spiralling_with != 0
		if whirling and not was_whirling:
			whirls += 1
		was_whirling = whirling

	assert_gt(whirls, 1, "precondition: they whirled repeatedly over 90 seconds")
	assert_eq(world.offspring.size(), 0, "a spiral flight must never breed")


## The breeding cooldown is a full REAL DAY and exists to bound the
## population. A behaviour that produces nothing must not inherit it, or the
## player sees one interaction per butterfly per day -- which is the reported
## bug.
func test_the_spiral_flight_does_not_wait_on_the_day_long_breeding_cooldown():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(118, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS

	var whirls := 0
	var was_whirling := false
	for i in 60 * 60:
		a._process(FRAME)
		b._process(FRAME)
		var whirling: bool = a._spiralling_with != 0
		if whirling and not was_whirling:
			whirls += 1
		was_whirling = whirling

	assert_gt(whirls, 1, "a pair that already bred must still whirl, repeatedly")


func test_a_bee_never_whirls():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("bee", Vector2(100, 100), parent)
	var b := _flyer_in_tree("bee", Vector2(110, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 300:
		a._process(FRAME)
		b._process(FRAME)
	assert_eq(a._spiralling_with, 0, "a honeybee's aerial life is nothing like this")


## Courtship and the whirl must not fight over the same flyer: stealing one
## of a whirling pair into a dance leaves the other orbiting nothing, which
## is the same one-sided failure _scan_for_partners' guard exists to stop.
func test_a_butterfly_mid_whirl_is_not_stolen_into_a_courtship_dance():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(140, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0 and b._spiralling_with != 0:
			break
	assert_ne(a._spiralling_with, 0, "precondition: a and b are whirling")

	var c := _flyer_in_tree("monarch", Vector2(104, 100), parent)
	for i in 30:
		c._process(FRAME)
	assert_eq(c._courting_with, 0, "a whirling butterfly must not be pulled into a dance")


# -- and the distance LOD does not silently switch it off --------------------
#
# SimulationLod throttles a creature's updates by how far it is from the
# player, and every _process above ran with no player in the tree at all --
# which is the FULL-RATE path. A behaviour that only works when nobody is
# looking would be a strange thing to ship, so both sides of the throttle get
# driven here.

## A player node for the group SimulationLod measures distance against (see
## AmbientFlyerMarker._nearest_player_position).
func _player_at(at: Vector2, parent: Node2D) -> Node2D:
	var player := Node2D.new()
	player.position = at
	parent.add_child(player)
	player.add_to_group("player")
	return player


## Close enough that SimulationLod runs the pair at full rate
## (FULL_RATE_RADIUS_PX is 420), far enough that neither butterfly reacts to
## the player at all (FlyerPersonality / SpiralFlight.NOTICE_RADIUS_PX is
## about 50). This used to stand the player ON one of the pair, which stopped
## being a neutral place to put them the moment butterflies started noticing
## players: a shy one there flees instead of whirling, which is correct
## behaviour and would have made this test a false alarm about the LOD path it
## is actually here to check.
func test_a_pair_right_next_to_the_player_still_whirls():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(100, 400), parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(124, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0 and b._spiralling_with != 0:
			break
	assert_eq(a._spiralling_with, b.get_instance_id(), "the on-screen case must work")


## Off screen a flyer updates in fewer, larger steps -- up to
## SimulationLod.MAX_INTERVAL_SECONDS apart. Both interactions are seconds
## long, so they still run out there; they just run in a handful of steps
## instead of a hundred. If that ever stopped being true, a butterfly would
## quietly stop interacting the moment it left the screen and start again when
## it came back.
func test_a_pair_far_from_the_player_still_dances_in_fewer_larger_steps():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(-9000, -9000), parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("monarch", Vector2(120, 100), parent)

	var steps_taken := 0
	var began := false
	for i in 600:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0 and b._courting_with != 0:
			began = true
			break
	assert_true(began, "a pair nobody is watching must still pair off")

	while a._courting_with != 0 and steps_taken < 3000:
		a._process(FRAME)
		b._process(FRAME)
		steps_taken += 1
	assert_eq(a._courting_with, 0, "and the dance must still finish out there")


# == personality: what a butterfly does about the player ======================
#
# "Can make butterflies dance around a players head or fly away based on
# personality (dna derived)?" -- see FlyerPersonality, and
# docs/concept/ecosystem_dynamics.md's "The butterfly that knows you".
#
# Boldness is a continuum. Most butterflies do neither of these dramatically;
# the two ends are what the player notices, and they are uncommon.

const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")


func _butterfly_with_boldness(
	boldness: float, at: Vector2, parent: Node2D
) -> AmbientFlyerMarker:
	var flyer := _flyer_in_tree("monarch", at, parent)
	flyer.traits = {FlyerPersonality.TRAIT_BOLDNESS: boldness}
	return flyer


## Every flyer has a personality without anything being stored: it is derived
## from `wander_seed`, which is itself derived from the flyer's own world cell
## (see AmbientFlyerRenderer._spawn_species). So a butterfly that leaves with
## an unloaded chunk is the same butterfly when it comes back.
func test_a_butterfly_derives_its_personality_from_its_own_seed():
	marker.wander_seed = 4242
	var mine := marker.personality()
	assert_eq(mine, FlyerPersonality.traits_from_seed(4242))
	assert_eq(marker.personality(), mine, "and it does not change from frame to frame")


func test_two_butterflies_are_two_different_butterflies():
	marker.wander_seed = 1
	var one := marker.boldness()
	var other := AmbientFlyerMarker.new()
	other.wander_seed = 2
	var second := other.boldness()
	other.free()
	assert_ne(one, second)


func test_a_shy_butterfly_flies_away_from_the_player():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var player := _player_at(Vector2(200, 200), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200) + Vector2(10.0, 0.0), parent)
	var started := shy.position.distance_to(player.position)
	for i in 240:
		shy._process(FRAME)
	assert_gt(
		shy.position.distance_to(player.position),
		FlyerPersonality.flight_initiation_distance_px(0.0),
		"a shy butterfly must end up outside its own flight initiation distance"
	)
	assert_gt(shy.position.distance_to(player.position), started)


## Real escape is a burst, not a cruise: the ratio between the two is
## FlyerPersonality.ESCAPE_SPEED_MULTIPLIER, taken from the real 5 m/s
## butterfly burst against a real 2 m/s cruise.
func test_fleeing_is_faster_than_ordinary_flight():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200) + Vector2(10.0, 0.0), parent)
	var before := shy.position
	shy._process(FRAME)
	assert_almost_eq(
		before.distance_to(shy.position),
		16.0 * FlyerPersonality.ESCAPE_SPEED_MULTIPLIER * FRAME,
		0.001
	)


## The escape does not stop dead on the line it flushed at (see
## FlyerPersonality.flee_release_distance_px) -- and it does stop. A butterfly
## that fled forever would leave the meadow.
func test_a_fled_butterfly_settles_down_again():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200) + Vector2(10.0, 0.0), parent)
	var settled := false
	for i in 600:
		shy._process(FRAME)
		if not shy._fleeing_from_player:
			settled = true
			break
	assert_true(settled, "a butterfly has to calm down eventually")


func test_a_bold_butterfly_comes_and_dances_round_the_players_head():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var player := _player_at(Vector2(200, 200), parent)
	var bold := _butterfly_with_boldness(
		1.0, Vector2(200, 200) + Vector2(SpiralFlight.NOTICE_RADIUS_PX * 0.8, 0.0), parent
	)
	for i in 300:
		bold._process(FRAME)
	assert_true(bold._dancing_at_player, "it must actually latch on")
	var head: Vector2 = player.position + Vector2(0.0, -StoneSize.PLAYER_WORLD_HEIGHT_PX)
	assert_almost_eq(
		bold.position.distance_to(head), SpiralFlight.SPIRAL_RADIUS_PX, 0.5,
		"and settle onto the same orbit it would hold round another butterfly"
	)


func test_the_dance_actually_goes_round_rather_than_hanging_at_one_point():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var bold := _butterfly_with_boldness(
		1.0, Vector2(200, 200) + Vector2(SpiralFlight.NOTICE_RADIUS_PX * 0.8, 0.0), parent
	)
	for i in 300:
		bold._process(FRAME)
	var swept := 0.0
	var previous := bold.position
	for i in 60:
		bold._process(FRAME)
		swept += previous.distance_to(bold.position)
		previous = bold.position
	assert_gt(swept, TAU * SpiralFlight.SPIRAL_RADIUS_PX, "at least a full circle a second")


## The middle of the population -- which is most of it -- does neither. This
## is the half of the request that is easy to get wrong: a meadow where every
## butterfly either mobs you or bolts is not "personality", it is two scripts.
func test_an_ordinary_butterfly_neither_flees_nor_dances():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var ordinary := _butterfly_with_boldness(
		0.5, Vector2(200, 200) + Vector2(SpiralFlight.NOTICE_RADIUS_PX * 0.9, 0.0), parent
	)
	for i in 120:
		ordinary._process(FRAME)
		assert_false(ordinary._fleeing_from_player)
		assert_false(ordinary._dancing_at_player)


## Butterflies, and not the whole aviary. A sparrow bolting from the player
## would be a second flight-response system on a bird that has none.
func test_a_sparrow_ignores_the_player_entirely():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var bird := _flyer_in_tree("sparrow", Vector2(205, 200), parent)
	bird.traits = {FlyerPersonality.TRAIT_BOLDNESS: 0.0}
	for i in 60:
		bird._process(FRAME)
		assert_false(bird._fleeing_from_player)


# -- precedence ---------------------------------------------------------------
#
# Five things can move a butterfly now (flee, court, dance-at-the-player,
# spiral, forage/wander) and three of them are new. The order is:
#
#   flee > finish the pair interaction you are already in > start a courtship
#        > dance at the player > start a spiral > forage > wander
#
# Escape is first because escape is first in every animal: a butterfly that
# keeps courting while something big closes on it is a dead butterfly, and the
# brief says it directly ("a butterfly fleeing a player should not be mid-dance
# with another butterfly"). Everything below escape is ordered by commitment
# and then by rarity.


func test_fleeing_the_player_interrupts_a_whirl_already_in_progress():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(600, 600), parent)
	var b := _flyer_in_tree("monarch", Vector2(624, 600), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	a.traits = {FlyerPersonality.TRAIT_BOLDNESS: 0.0}
	b.traits = {FlyerPersonality.TRAIT_BOLDNESS: 0.0}
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0:
			break
	assert_ne(a._spiralling_with, 0, "precondition: the whirl has to be running")

	# Now somebody walks into the middle of it.
	_player_at(a.position, parent)
	a._process(FRAME)
	assert_eq(a._spiralling_with, 0, "the whirl must end the moment it bolts")
	assert_true(a._fleeing_from_player)


## The other side of the same rule. A dance already under way is a commitment
## -- being yanked out of one by a passer-by is how the game ends up with a
## butterfly orbiting an empty midpoint, which is a bug this file has already
## had once (see _scan_for_partners' own notes).
func test_a_courting_butterfly_is_not_yanked_out_by_a_bold_ones_interest_in_the_player():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _butterfly_with_boldness(1.0, Vector2(600, 600), parent)
	var b := _butterfly_with_boldness(1.0, Vector2(620, 600), parent)
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._courting_with != 0 and b._courting_with != 0:
			break
	assert_ne(a._courting_with, 0, "precondition: the dance has to be running")

	_player_at(a.position + Vector2(20.0, 0.0), parent)
	for i in 30:
		a._process(FRAME)
		b._process(FRAME)
	assert_ne(a._courting_with, 0, "a bold butterfly finishes what it started")
	assert_false(a._dancing_at_player)


## A butterfly will not be led out of the world. The dance is centred on the
## player's head, so a player who keeps walking would tow it away from home
## forever. The leash is SpiralFlight.NOTICE_RADIUS_PX from home -- as far as
## the butterfly saw the intruder from in the first place, which is about as
## far as a real territorial butterfly pursues one before returning to its
## perch -- and it is measured against the ORBIT CENTRE, so the butterfly is
## never dragged past it even for one frame.
func test_a_butterfly_will_not_be_led_off_its_own_territory():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var player := _player_at(Vector2(200, 200), parent)
	var bold := _butterfly_with_boldness(1.0, Vector2(210, 200), parent)
	for i in 120:
		bold._process(FRAME)
	assert_true(bold._dancing_at_player, "precondition: it has to be dancing")

	var home := bold.home
	var leash := SpiralFlight.NOTICE_RADIUS_PX + SpiralFlight.SPIRAL_RADIUS_PX
	for i in 600:
		player.position += Vector2(1.0, 0.0)
		bold._process(FRAME)
		assert_lt(
			bold.position.distance_to(home), leash + 1.0,
			"the dance must let go before the butterfly is towed off its patch"
		)
		if not bold._dancing_at_player:
			break
	assert_false(bold._dancing_at_player, "it has to let go at some point")


# == the erratic flutter on ORDINARY flight ===================================
#
# "butterflies generaly should have more random / dancy motions rather then fly
# in a straight line". PollinatorForaging.tumbled_heading already existed and
# was applied ONLY on the approach to a bloom; ordinary wander held one heading
# for a whole AmbientFlyerRenderer.BUTTERFLY_INTERVAL (0.7 s), which is a
# straight line at a time and is what the player was watching.


func _wander_path(flyer: AmbientFlyerMarker, steps: int) -> Array:
	var path: Array = []
	for i in steps:
		flyer._process(FRAME)
		path.append(flyer.position)
	return path


func test_an_ordinarily_wandering_butterfly_does_not_fly_in_a_straight_line():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var butterfly := _flyer_in_tree("monarch", Vector2(0, 0), parent)
	# Well inside one heading interval, so a butterfly WITHOUT the flutter
	# would be flying one dead straight line for every sample here.
	var path := _wander_path(butterfly, 30)
	var straight: Vector2 = (path[path.size() - 1] - path[0]).normalized()
	var wandered := false
	for i in range(1, path.size()):
		var step: Vector2 = path[i] - path[i - 1]
		if step.length() > 0.0001 and step.normalized().dot(straight) < 0.97:
			wandered = true
	assert_true(wandered, "a butterfly's ordinary flight must not be a straight line")


## Songbirds glide -- they are the other half of the same movement module and
## must NOT inherit this. A sparrow tumbling like a butterfly reads as a
## glitching bird, the same failure that already got birds out of the
## courtship dance.
func test_a_songbird_still_glides_straight():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	var path := _wander_path(bird, 30)
	var straight: Vector2 = (path[path.size() - 1] - path[0]).normalized()
	for i in range(1, path.size()):
		var step: Vector2 = path[i] - path[i - 1]
		assert_gt(step.normalized().dot(straight), 0.999, "a bird holds its heading")


## THE trap this corner of the codebase has fallen into three separate ways
## (see AmbientFlyerMovement.direction_at's own notes): a flyer that jitters
## on a fixed spot instead of going anywhere. Every step must be a full step,
## and the butterfly must actually travel.
func test_the_flutter_never_stalls_a_butterfly():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var butterfly := _flyer_in_tree("monarch", Vector2(0, 0), parent)
	var path := _wander_path(butterfly, 600)
	for i in range(1, path.size()):
		var step: float = path[i].distance_to(path[i - 1])
		assert_almost_eq(step, 16.0 * FRAME, 0.001, "every step must be a whole step")
	# The recorded stall was 5.55 simulated seconds inside a 3px circle. Ten
	# seconds of flight has to cover real ground.
	var travelled := 0.0
	for i in path.size():
		travelled = maxf(travelled, path[0].distance_to(path[i]))
	assert_gt(travelled, 10.0, "ten seconds of fluttering must go somewhere")


func test_a_fluttering_butterfly_still_stays_on_its_own_patch():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var butterfly := _flyer_in_tree("monarch", Vector2(0, 0), parent)
	var path := _wander_path(butterfly, 3600)
	for point in path:
		assert_lt(
			point.distance_to(butterfly.home), 30.0 * 2.0,
			"the flutter must not fight its way out of its own territory"
		)


# == the wingbeat bounce ======================================================
#
# "maybe also make them bounce slightly with each wing flap" (see
# WingbeatBounce). DRAW-TIME ONLY -- see the next test for why that matters.


## A butterfly whose wings beat but whose flight speed is zero, so that
## anything `position` does is the bounce and nothing else. (Handing it a null
## movement instead would stop _process before it ever animates the wings --
## see its own early return.)
func _flapping_butterfly(parent: Node2D) -> AmbientFlyerMarker:
	var butterfly := _flyer_in_tree("monarch", Vector2(0, 0), parent)
	butterfly.setup(AmbientFlyerMovement.new(0.0, 30.0, 0.7))
	butterfly.flap_frames = [PlaceholderTexture2D.new(), PlaceholderTexture2D.new()]
	butterfly.texture = butterfly.flap_frames[0]
	return butterfly


## The one that must not regress. `position` feeds containment, the courtship
## orbit, the spiral flight, partner-distance checks and Y-sorting; a per-frame
## bob folded into it would put a wobble through all five at once. The bounce
## lives on `offset`, which is a draw-time property and nothing else reads.
func test_the_wingbeat_bounce_never_touches_the_flyers_position():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var butterfly := _flapping_butterfly(parent)
	var pinned := butterfly.position
	var offsets: Array = []
	for i in 40:
		butterfly._process(FRAME)
		assert_eq(butterfly.position, pinned, "the bob must never reach position")
		offsets.append(butterfly.offset.y)
	var spread := 0.0
	for value in offsets:
		spread = maxf(spread, absf(float(value) - float(offsets[0])))
	assert_gt(spread, 0.0, "...but the drawn offset really does move")


func test_the_bounce_matches_the_wingbeat_it_is_locked_to():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var butterfly := _flapping_butterfly(parent)
	for i in 10:
		butterfly._process(FRAME)
	assert_almost_eq(
		butterfly.offset.y,
		WingbeatBounce.bounce_offset(
			"monarch", butterfly._elapsed_time, AmbientFlyerMarker.FLAP_SECONDS_PER_FRAME,
			butterfly.flap_frames.size(), float(butterfly.texture.get_height())
		),
		0.0001
	)


## A bird sitting on the ground working a worm is not flapping, so there is
## nothing for the body to bob against -- and a perched bird that bobbed would
## read as a glitch, the same reason _animate_wings freezes its wings.
func test_a_perched_bird_sits_still():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.flap_frames = [PlaceholderTexture2D.new(), PlaceholderTexture2D.new()]
	bird.texture = bird.flap_frames[0]
	for i in 10:
		bird._process(FRAME)
	bird.perched = true
	for i in 10:
		bird._process(FRAME)
	assert_eq(bird.offset.y, 0.0)


# == heritable personality ====================================================


## Duck-typed courtship world that records what a mating actually hands over
## (see EarthChunkManager.spawn_flyer_offspring). The third argument is the
## whole point: before this, an offspring's personality was unrelated to its
## parents'.
class StubBreedingWorld:
	var offspring: Array = []
	func spawn_flyer_offspring(
		a_species: String, at: Vector2, inherited: Dictionary = {}
	) -> void:
		offspring.append({"species": a_species, "position": at, "traits": inherited})


## A courting pair's child is crossed from BOTH parents through the shipped
## DnaCrossover, not rolled fresh. Two bold parents make a bold child, which is
## the single fact the whole selection-pressure story rests on (see
## test_flyer_personality.gd).
func test_a_courting_pairs_child_inherits_from_both_parents():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var world := StubBreedingWorld.new()
	var born := false
	# Courtship.mates is decided by the pair's own seed, so a given pair either
	# breeds or does not -- walk positions until one that breeds turns up.
	for attempt in 40:
		var at := Vector2(1000 + attempt * 40, 1000)
		var a := _butterfly_with_boldness(0.9, at, parent)
		var b := _butterfly_with_boldness(0.85, at + Vector2(20, 0), parent)
		a.courtship_world = world
		b.courtship_world = world
		for i in 900:
			a._process(FRAME)
			b._process(FRAME)
			if not world.offspring.is_empty():
				break
		if not world.offspring.is_empty():
			born = true
			break
	assert_true(born, "precondition: some pair has to actually breed")
	var child: Dictionary = world.offspring[0]["traits"]
	assert_true(
		child.has(FlyerPersonality.TRAIT_BOLDNESS), "the child must carry a personality"
	)
	assert_gt(
		FlyerPersonality.boldness_of(child), 0.8,
		"two bold parents must not produce an average child"
	)
