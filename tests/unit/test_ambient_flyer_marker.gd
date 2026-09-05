extends GutTest

## A butterfly/songbird ambient wildlife marker -- pure decorative presence
## (see docs/concept/ecosystem_dynamics.md's Species roster), no
## needs/perception/behavior AI and no population simulation, unlike
## CreatureMarker/FishMarker.

const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")

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
	## Blossoming trees (see EarthChunkManager.blossoms_near) -- a bee's other
	## food source. Empty by default, so every existing test that never sets
	## this is unaffected.
	var blossoms: Array = []
	var pollination_visit_calls: Array = []
	func blossoms_near(position: Vector2, radius_tiles: int) -> Array:
		var out: Array = []
		for b in blossoms:
			if position.distance_to(b["position"]) / TILE_SIZE <= float(radius_tiles):
				out.append(b)
		return out
	## Mirrors drink_nectar_at's contract for a tree instead of a flower (see
	## EarthChunkManager.record_pollination_visit_at). `visit_weight` defaults
	## to 1.0 to match the real signature -- the caller now passes a
	## fitness-scaled weight (see FruitingModel.visit_weight_for_fitness).
	func record_pollination_visit_at(position: Vector2, visit_weight: float = 1.0) -> bool:
		pollination_visit_calls.append(position)
		return true
	## Flower-side pollen exchange (see EarthChunkManager.pollinate_flower_at).
	## Records both arguments so a test can see what the marker was carrying
	## on arrival, and hands back the visited flower's own species -- as if
	## every stubbed flower were a pollen-giving male -- so a test can also
	## observe the marker's carried pollen actually updating. Falls back to
	## returning `carried_species` unchanged when the position matches no
	## stubbed flower, the same "nothing here" contract the real
	## EarthChunkManager.pollinate_flower_at has.
	var pollination_calls: Array = []
	func pollinate_flower_at(position: Vector2, carried_species: String) -> String:
		pollination_calls.append({"position": position, "carried": carried_species})
		for f in flowers:
			if f["position"].distance_to(position) < 0.01:
				return String(f["species"])
		return carried_species


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


# -- landing on a flower actually exchanges pollen (see Pollination) ---------
#
# Pollination was a complete, fully-tested pure module with no live caller:
# FlowerPatch.pollinate (its only caller) was itself only ever invoked from
# its own test file, so a meadow never actually shed seed through
# pollination. A marker landing on a flower now calls the flower-side world
# surface (EarthChunkManager.pollinate_flower_at) exactly the way it already
# calls drink_nectar_at, and remembers what it picked up for its next visit.

func test_landing_on_a_flower_exchanges_pollen():
	var world := StubScentWorld.new()
	world.flowers = [{"position": Vector2(0, 0), "species": "rose", "nectar": 1.0}]
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2(0, 0)
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._carried_pollen = "tulip"
	marker._forage_target = Vector2(0, 0)
	marker._forage_flower = Vector2(0, 0)
	marker._process(0.1)
	assert_eq(world.pollination_calls.size(), 1, "landing on a flower should exchange pollen")
	assert_eq(world.pollination_calls[0]["position"], Vector2(0, 0), "should exchange pollen at the flower's own position")
	assert_eq(
		world.pollination_calls[0]["carried"], "tulip",
		"should hand over whatever the marker was already carrying"
	)


## State persists ACROSS visits on one marker -- it is not reset every
## landing (see Pollination.pollen_after_visit's "a later male replaces it"
## contract: nothing resets it in between).
func test_carried_pollen_updates_and_carries_forward_into_the_next_visit():
	var world := StubScentWorld.new()
	world.flowers = [
		{"position": Vector2(0, 0), "species": "rose", "nectar": 1.0},
		{"position": Vector2(40, 0), "species": "rose", "nectar": 1.0},
	]
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2(0, 0)
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._forage_target = Vector2(0, 0)
	marker._forage_flower = Vector2(0, 0)
	marker._process(0.1)
	assert_eq(marker._carried_pollen, "rose", "should now carry whatever pollinate_flower_at handed back")

	# Done drinking from the first bloom (DRINK_SECONDS would otherwise hold
	# it there -- see PollinatorForaging.DRINK_SECONDS) and committed to the
	# second flower.
	marker._drink_remaining = 0.0
	marker.position = Vector2(40, 0)
	marker._forage_target = Vector2(40, 0)
	marker._forage_flower = Vector2(40, 0)
	marker._process(0.1)
	assert_eq(
		world.pollination_calls[1]["carried"], "rose",
		"the previous visit's pollen should carry forward into the next visit, not reset"
	)


# -- bees recognize blossoming fruit trees too (see docs/concept/flora.md) ---
#
# crop_potential used to be a pure function of the genome and time, zero
# connection to the pollinator system: bees only ever visited flowers. A
# blossoming apple/cherry tree (see EarthChunkManager.blossoms_near) is now
# merged straight into the same candidate list PollinatorForaging.
# choose_target already scatters/scores/claims over -- no changes to that
# machinery at all -- but only for BEES: real fruit trees are pollinated
# mainly by bees, and other nectar-feeders here keep working flowers only.

func test_a_bee_targets_a_blossoming_tree_when_that_is_all_thats_offered():
	var world := StubScentWorld.new()
	world.blossoms = [{"position": Vector2(20, 0), "species": "apple", "nectar": 1.0}]
	marker.scent_world = world
	marker.species = "bee"
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)  # >= SCENT_SNIFF_INTERVAL, forces a sniff
	assert_eq(marker._forage_target, Vector2(20, 0), "a bee should commit to the blossoming tree")


## Only bees -- a butterfly here has nothing to fly to, since flowers_near is
## empty and blossoms_near is deliberately not consulted for it.
func test_a_non_bee_pollinator_ignores_blossoming_trees():
	var world := StubScentWorld.new()
	world.blossoms = [{"position": Vector2(20, 0), "species": "apple", "nectar": 1.0}]
	marker.scent_world = world
	marker.species = "monarch"
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._process(1.0)
	assert_null(marker._forage_target, "a butterfly should not target a tree")


## Landing on a tree calls the TREE side of the world (record_pollination_
## visit_at), never drink_nectar_at -- a blossom is not a flower patch cell.
func test_landing_on_a_blossoming_tree_records_a_pollination_visit_not_a_drink():
	var world := StubScentWorld.new()
	world.blossoms = [{"position": Vector2(0, 0), "species": "apple", "nectar": 1.0}]
	marker.scent_world = world
	marker.species = "bee"
	marker.home = Vector2.ZERO
	marker.position = Vector2(0, 0)
	marker.wander_seed = 1
	marker.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker._forage_target = Vector2(0, 0)
	marker._forage_flower = Vector2(0, 0)
	marker._forage_target_is_tree = true
	marker._process(0.1)
	assert_eq(world.pollination_visit_calls.size(), 1, "should register a visit on the tree")
	assert_eq(world.drink_calls.size(), 0, "a tree blossom is not a flower patch cell")
	assert_eq(
		world.pollination_calls.size(), 0,
		"the flower-side pollen exchange must never fire for a tree-blossom visit"
	)


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


# -- trap-lining: a butterfly works a CIRCUIT, not one flower ---------------
#
# Reported: "Butterflies still get stuck infront of a signle flower". Real
# pollinators -- bumblebees, butterflies, hummingbirds -- forage a repeatable
# CIRCUIT of blooms (trap-lining) rather than re-working one, because a
# just-drained bloom is the worst bet in the patch.
#
# This is the acceptance measurement for that, and it is a real headless sim:
# one butterfly, a real patch of blooms, several simulated minutes, nectar
# regenerating exactly as FlowerPatch.advance does. What it counts is how many
# DISTINCT blooms the flyer actually landed on.


## A ring of `count` blooms around `centre` at `spread_px`, which is the shape
## a real patch has (a pollinator's local flowers are around it, not in a
## line) and the shape that makes "did it work a circuit" measurable.
func _ring_of_flowers(world: StubScentWorld, centre: Vector2, count: int, spread_px: float) -> void:
	for i in count:
		var angle := TAU * float(i) / float(count)
		var at := centre + Vector2.from_angle(angle) * spread_px
		world.flowers.append({"position": at, "species": "rose", "nectar": 1.0, "landing": at})


## How many different blooms this flyer put its feet on.
func _distinct_flowers_visited(world: StubScentWorld) -> int:
	var seen: Array = []
	for at in world.drink_calls:
		var known := false
		for other in seen:
			if at.distance_to(other) < PollinatorForaging.LANDING_DISTANCE:
				known = true
				break
		if not known:
			seen.append(at)
	return seen.size()


func test_a_butterfly_in_a_patch_works_several_flowers_not_one():
	var world := StubScentWorld.new()
	_ring_of_flowers(world, Vector2.ZERO, 6, 3.0 * TILE_SIZE)
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.species = "monarch"
	marker.wander_seed = 4242
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))

	for step in 3000:  # five simulated minutes
		marker._process(0.1)
		world.regenerate(0.1)

	var distinct := _distinct_flowers_visited(world)
	assert_ne(
		distinct, 1,
		"a butterfly must not spend five minutes on ONE bloom (distinct visited: %d, landings: %d)"
			% [distinct, world.drink_calls.size()]
	)
	assert_gte(
		distinct, 4,
		"a trap-lining butterfly works a circuit (distinct visited: %d of 6, landings: %d)"
			% [distinct, world.drink_calls.size()]
	)


## THE STANDING GUARD ON THIS WHOLE SYSTEM. Flutter, personality steering,
## trap-lining, the breathing orbits and the flap-glide gait all now shape the
## same sprite, and this file's own history is three separate ways of building
## a heading out of components that can cancel -- every one of which showed up
## live as "flyers stall and jitter on a fixed spot" (see
## AmbientFlyerMovement.direction_at's notes).
##
## So: with every one of them composed together and running, over several
## simulated minutes, a butterfly must never stop moving for longer than a
## drink takes. The only thing in this game allowed to hold a flyer still is
## sitting on a bloom.
func test_nothing_in_this_composition_can_stall_a_butterfly():
	var world := StubScentWorld.new()
	_ring_of_flowers(world, Vector2.ZERO, 5, 4.0 * TILE_SIZE)
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.species = "monarch"
	marker.wander_seed = 31337
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))

	var still_for := 0.0
	var worst_stall := 0.0
	var last := marker.position
	for step in 3000:  # five simulated minutes
		marker._process(0.1)
		world.regenerate(0.1)
		# A tenth of a second at 16px/s is 1.6px; anything under a tenth of
		# that is not travelling.
		if marker.position.distance_to(last) < 0.16:
			still_for += 0.1
			worst_stall = maxf(worst_stall, still_for)
		else:
			still_for = 0.0
		last = marker.position
	assert_lte(
		worst_stall, PollinatorForaging.DRINK_SECONDS + 1.0,
		"only drinking may hold a flyer still (worst stall %.1fs)" % worst_stall
	)


## The line this fixes, at the marker. A flyer's territory centre used to snap
## to whichever single bloom last fed it, so its whole relocation leash
## re-centred on one flower however many it was really working. It must now
## sit in the middle of the circuit -- which, for a ring of blooms, is the
## middle of the ring and NOT any one of them.
func test_a_foraging_butterflys_territory_is_its_circuit_not_its_last_flower():
	var world := StubScentWorld.new()
	var spread := 3.0 * TILE_SIZE
	_ring_of_flowers(world, Vector2.ZERO, 6, spread)
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.species = "monarch"
	marker.wander_seed = 4242
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))

	for step in 1800:  # three simulated minutes, long enough to work the ring
		marker._process(0.1)
		world.regenerate(0.1)

	assert_gt(marker._fed_at.size(), 1, "precondition: it fed at more than one bloom")
	var nearest_bloom := INF
	for f in world.flowers:
		nearest_bloom = minf(nearest_bloom, marker._origin.distance_to(f["position"]))
	assert_gt(
		nearest_bloom, 0.0,
		"the territory centre must not be sitting exactly on one of the blooms"
	)
	assert_lt(
		marker._origin.distance_to(Vector2.ZERO), spread,
		"it should sit inside the ring it is working, not out on the rim (was %s)"
			% marker._origin
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


## Renamed from "...just_keeps_flying": that used to be the literal
## contract here ("nothing to land on, so it stays airborne" -- for the
## WHOLE 20-second run) -- which is exactly the bug reported live, twice
## ("robins just fly from random point to point and don't switch between
## diverse actions"). See the IDLE REST section far below: a bird with
## nothing to hunt now still perches periodically (idle rest), so
## "stays airborne forever" is no longer part of this contract. What
## genuinely must still hold -- and is the actual point of this test --
## is that it never COMMITS to food that was never there: ground_forage
## must stay SEEKING for the entire run regardless of how long it goes
## without a meal.
func test_a_robin_with_nothing_to_hunt_never_commits_to_food_that_isnt_there():
	var world := StubWormWorld.new()
	_make_robin(world)
	for i in 400:
		marker._process(0.05)
		assert_eq(
			marker.ground_forage.phase, GroundForageBehavior.Phase.SEEKING,
			"nothing to hunt -- it must never commit to a worm that isn't there"
		)
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
	# It SETS DOWN over the last GroundForageBehavior.LANDING_DISTANCE rather
	# than snapping onto the worm on the frame it was declared arrived (see
	# _begin_ground_touchdown -- that snap measured 3.52 px against the 0.567 px
	# a robin covers in a frame). So "holds still" is what it does once it is
	# standing, which is what this waits out first.
	for i in 5:
		marker._process(0.05)
	var landed := marker.position
	for i in 5:
		marker._process(0.05)
	assert_eq(marker.position, landed, "a pecking bird holds still")
	assert_almost_eq(
		landed, Vector2(80, 0), Vector2.ONE,
		"and it is standing on the worm, not a few pixels off it"
	)


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


func test_carrying_a_seed_plants_it_at_the_birds_own_position_once_it_has_carried_far_enough():
	var world := StubFruitWorld.new()
	_make_fruit_robin(world)
	marker._carried_seed_species = "walnut"
	marker.position = Vector2(123, 45)
	# Pretend this bird already flew far enough before this frame -- further
	# than any possible SeedEndozoochory.CARRY_MAX_TILES roll -- so the very
	# next _process call resolves the carry at wherever it is right now.
	marker._carried_seed_start_position = marker.position - Vector2(10000, 0)
	var expected_position := marker.position
	marker._process(0.1)
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
	var first_carry_origin: Vector2 = marker._carried_seed_start_position

	world.fruit = [{"position": Vector2(90, 0), "species": "apple"}]
	marker._fruit_target = Vector2(90, 0)
	marker._take_targeted_fruit()
	assert_eq(marker._carried_seed_species, "cherry", "should still be carrying the FIRST seed eaten")
	assert_eq(
		marker._carried_seed_start_position, first_carry_origin, "the carry origin must not reset"
	)


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

const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")

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
	# Chosen (not just any small int) so the FIRST seed this bird eats
	# survives the granivory roll (see SeedEndozoochory.seed_is_consumed):
	# tests below that check WHERE a swallowed seed lands need it to
	# actually be planted, not destroyed. The roll's own distribution is
	# covered separately by test_a_sparrow_mostly_destroys_the_seed_it_eats_
	# rather_than_planting_it, which samples many wander_seeds instead of
	# relying on this one.
	marker.wander_seed = 4
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
	# Not just "well away" -- the REAL dispersal range SeedEndozoochory
	# intends (10-40 tiles), not the couple of tiles ordinary home-tethered
	# wander alone can reach. See _carry_direction/_step_seed_carrying for
	# how this is actually achieved, and the test below for the same claim
	# pinned across many birds rather than this one convenient seed.
	assert_gte(
		world.planted[0]["position"].distance_to(at), SeedEndozoochory.CARRY_MIN_TILES * TILE_SIZE,
		"a bird should carry seed the real intended dispersal range, not just a couple of tiles"
	)


## THE REPORTED SHORTFALL, pinned directly across many birds (not just one
## fixed wander_seed): ordinary wander alone is tethered to
## AmbientFlyerMovement's home-anchor radius, which is far smaller than
## SeedEndozoochory's 10-40 tile carry range -- measured before this fix at a
## hard ~2.5-tile ceiling for a sparrow, for every one of 30 sampled
## wander_seeds, regardless of what carry_distance_tiles actually intended
## for that bird (docs/progress.md has the full measurement). A bird now
## flies off in an actual heading while it carries (see
## SeedEndozoochory.carry_direction), and the carry resolves on REAL
## travelled distance rather than a fixed time budget (see
## _step_seed_carrying), so this must hold for many different birds, not
## just a convenient one.
func test_a_sparrows_seed_carry_reaches_the_real_dispersal_range_across_many_birds():
	for wander_seed in range(1, 21):
		var world := StubSeedWorld.new()
		var at := Vector2(3.0 * TILE_SIZE, 0.0)
		world.seeds.append({"position": at, "species": "clover"})

		var bird := AmbientFlyerMarker.new()
		bird.seed_world = world
		bird.species = "sparrow"
		bird.home = Vector2.ZERO
		bird.position = Vector2.ZERO
		bird.wander_seed = wander_seed
		bird.ground_forage = GroundForageBehavior.new()
		bird.setup(AmbientFlyerMovement.new(24.0, 40.0, 1.0))

		var start_position = null
		var net_tiles := -1.0
		for step in range(8000):  # 800 simulated seconds -- generous
			var was_carrying: bool = bird._carried_seed_species != ""
			bird._process(0.1)
			var is_carrying: bool = bird._carried_seed_species != ""
			if not was_carrying and is_carrying:
				start_position = bird.position
			if was_carrying and not is_carrying:
				net_tiles = start_position.distance_to(bird.position) / TILE_SIZE
				break
		bird.free()

		assert_gte(
			net_tiles, SeedEndozoochory.CARRY_MIN_TILES,
			"wander_seed %d: sparrow only carried %.2f tiles, short of the %.0f-tile minimum" % [
				wander_seed, net_tiles, SeedEndozoochory.CARRY_MIN_TILES
			]
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


# -- granivory, seed-vs-seed arbitration: nearest wins, not a fixed type ----
# order (see docs/concept/long_grass.md: a live probe found 11/11 measured
# dispersal events came from mice and ZERO from sparrows, because the OLD
# fixed worm > fruit > flower-seed > grass-seed priority meant ANY flower
# seed in range pre-empted a grass seed, however much closer the grass seed
# actually was). Worm and fruit still unconditionally outrank both seed
# kinds -- only the choice BETWEEN the two seed kinds is now by distance.

## With the grass seed much closer than the flower seed, the sparrow must go
## for the grass seed -- proof the old fixed flower-seed-always-first order is
## gone.
func test_a_sparrow_forages_the_nearer_grass_seed_over_a_farther_flower_seed():
	var world := StubSeedWorld.new()
	world.grass_seeds.append({"position": Vector2(1.0 * TILE_SIZE, 0.0)})
	world.seeds.append({"position": Vector2(8.0 * TILE_SIZE, 0.0), "species": "clover"})
	_sparrow_on(world)

	for step in 400:
		marker._process(0.1)

	assert_eq(world.grass_seeds.size(), 0, "the nearer grass seed should have been eaten")
	assert_eq(world.seeds.size(), 1, "the farther flower seed should be left alone")


## Companion to the above, with the two seeds' distances swapped: the flower
## seed being the closer one must still win. Together the two tests prove
## this is a real nearest-wins distance comparison, not just the old fixed
## order flipped the other way.
func test_a_sparrow_still_forages_the_nearer_flower_seed_over_a_farther_grass_seed():
	var world := StubSeedWorld.new()
	world.seeds.append({"position": Vector2(1.0 * TILE_SIZE, 0.0), "species": "clover"})
	world.grass_seeds.append({"position": Vector2(8.0 * TILE_SIZE, 0.0)})
	_sparrow_on(world)

	for step in 400:
		marker._process(0.1)

	assert_eq(world.seeds.size(), 0, "the nearer flower seed should have been eaten")
	assert_eq(world.grass_seeds.size(), 1, "the farther grass seed should be left alone")


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
	marker._carried_seed_start_position = marker.position - Vector2(10000, 0)
	marker._step_seed_carrying(0.0)
	assert_eq(seed_world.planted.size(), 1, "precondition: the flower seed got planted")
	assert_eq(marker._carried_seed_species, "", "precondition: the crop is empty again")

	fruit_world.fruit = [{"position": Vector2(80, 0), "species": "walnut"}]
	marker._fruit_target = Vector2(80, 0)
	marker._take_targeted_fruit()
	marker._carried_seed_start_position = marker.position - Vector2(10000, 0)
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


## PHASE 4: bird courtship (see BirdCourtship). The exact class of bug the
## comment on _scan_for_partners documents (a rule can be right and still
## produce ONE flyer orbiting nothing, because nothing drove two real
## markers through real frames) already bit the pollinator dance once --
## this is the same real-markers-real-frames test for the bird mechanism,
## not just BirdCourtship's own pure-function tests.
func test_two_robins_side_by_side_actually_begin_a_bird_court():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("robin", Vector2(100, 100), parent)
	var b := _flyer_in_tree("robin", Vector2(120, 100), parent)

	var began := false
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._bird_courting_with != 0 and b._bird_courting_with != 0:
			began = true
			break
	assert_true(began, "two robins 20px apart must actually start a display")
	assert_eq(a._bird_courting_with, b.get_instance_id())
	assert_eq(b._bird_courting_with, a.get_instance_id())


func test_pollinators_and_bird_court_never_cross_species_kinds():
	# The butterfly dance and the bird display are disjoint species sets
	# (Courtship.DANCING_SPECIES vs BirdCourtship.DANCING_SPECIES) -- a
	# robin must never end up dancing the butterfly orbit, or vice versa,
	# whatever a monarch happens to be doing nearby.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var robin := _flyer_in_tree("robin", Vector2(200, 200), parent)
	var monarch := _flyer_in_tree("monarch", Vector2(210, 200), parent)
	for i in 120:
		robin._process(FRAME)
		monarch._process(FRAME)
	assert_eq(robin._courting_with, 0, "a robin must never enter the butterfly dance")
	assert_eq(monarch._bird_courting_with, 0, "a monarch must never enter the bird display")


func test_a_bird_court_holds_a_fixed_point_rather_than_orbiting():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("robin", Vector2(100, 100), parent)
	var b := _flyer_in_tree("robin", Vector2(120, 100), parent)
	for i in 120:
		a._process(FRAME)
		b._process(FRAME)
		if a._bird_courting_with != 0:
			break
	assert_ne(a._bird_courting_with, 0, "precondition: the display began")
	# Once settled, position must stop changing -- a HOLD, not a figure
	# that keeps moving the way the butterfly orbit deliberately does.
	for i in 40:
		a._process(FRAME)
		b._process(FRAME)
	var settled: Vector2 = a.position
	for i in 60:
		a._process(FRAME)
		b._process(FRAME)
		assert_true(
			a.position.distance_to(settled) < 0.5,
			"a held display must not keep drifting once it has closed the gap"
		)


class StubBirdBreedingWorld:
	var offspring: Array = []
	var bird_births: Array = []
	func spawn_flyer_offspring(a_species: String, at: Vector2, inherited: Dictionary = {}) -> void:
		offspring.append({"species": a_species, "position": at, "traits": inherited})
	func record_bird_birth_at(at: Vector2, a_species: String, count: float = 1.0) -> void:
		bird_births.append({"position": at, "species": a_species, "count": count})


## A successful bird court must do BOTH halves of "the individual half
## reports to the aggregate half" -- spawn the visible chick (spawn_flyer_
## offspring, same call pollinators use) AND reconcile the population
## number that chick's chunk will be reloaded FROM (record_bird_birth_at) --
## see EcosystemSimulation.record_bird_birth's own doc comment for why a
## chick that skipped the second half would simply vanish on next load.
func test_a_successful_bird_court_spawns_a_chick_and_reconciles_the_population():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var world := StubBirdBreedingWorld.new()
	var born := false
	for attempt in 40:
		var at := Vector2(1000 + attempt * 40, 1000)
		var a := _flyer_in_tree("robin", at, parent)
		var b := _flyer_in_tree("robin", at + Vector2(20, 0), parent)
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
	assert_eq(world.offspring[0]["species"], "robin")
	assert_eq(world.bird_births.size(), 1, "the aggregate population must be reconciled exactly once too")
	assert_eq(world.bird_births[0]["species"], "robin")


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
	# midpoint: this measures the pair's SHARED TRANSLATION -- the climb and
	# the ground track -- with the whirl taken back out.
	var highest := 0.0
	var furthest := 0.0
	var angles := {}
	var whirled := 0.0
	# The midpoint the whirl actually began from, which is the point both the
	# climb and the ground track are measured off.
	var started: Vector2 = a._spiral_centre
	while a._spiralling_with != 0 and whirled < SpiralFlight.SPIRAL_SECONDS * 3.0:
		a._process(FRAME)
		b._process(FRAME)
		whirled += FRAME
		var midpoint := (a.position + b.position) * 0.5
		# Screen-up is -Y, so "how high" is how far the midpoint went negative.
		highest = maxf(highest, started.y - midpoint.y)
		furthest = maxf(furthest, absf(midpoint.x - started.x))
		# The WHIRL's own angle, with the pair's shared translation taken back
		# out. Measuring the raw offset from the centre measures the whirl plus
		# the climb plus the ground track, and once the orbit draws in to
		# SPIRAL_RADIUS_PX the translation (up to 19 px) dwarfs the 4.4 px
		# circle -- so the raw angle stops tracking the thing this asserts.
		angles[snappedf((a.position - midpoint).angle(), 0.3)] = true

	assert_gt(angles.size(), 8, "it has to actually whirl, several times round")
	assert_eq(a._spiralling_with, 0, "the whirl must end on its own")
	assert_almost_eq(
		whirled, SpiralFlight.SPIRAL_SECONDS, 0.2, "it must last about SPIRAL_SECONDS"
	)
	assert_gte(highest, SpiralFlight.RISE_PX - 0.5, "the pair must climb, together")
	# ...and go somewhere while they do it. A whirl that spins on one spot is
	# what read as frantic (see SpiralFlight.TRAVEL_M).
	assert_gt(highest + furthest, SpiralFlight.RISE_PX + 0.5, "they must also cover ground")
	assert_lte(
		(Vector2(furthest, highest)).length(),
		SpiralFlight.RISE_PX + SpiralFlight.TRAVEL_PX + 0.5,
		"and no further than the climb plus the ground track between them allow"
	)


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
const FlapGlide = preload("res://src/rendering/flap_glide.gd")


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
	# The orbit BREATHES rather than tracing a circle (see
	# SpiralFlight.RADIUS_SWING), so this is the band, not a point.
	assert_between(
		bold.position.distance_to(head),
		SpiralFlight.SPIRAL_RADIUS_PX / (1.0 + SpiralFlight.RADIUS_SWING) - 0.5,
		SpiralFlight.SPIRAL_RADIUS_PX / (1.0 - SpiralFlight.RADIUS_SWING) + 0.5,
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


# == ground-foraging songbirds: scattering off the ground near the player ====
#
# FlyerPersonality's boldness/FID continuum is deliberately butterfly-only
# (see test_a_sparrow_ignores_the_player_entirely above -- that stays true).
# But a real ground-foraging songbird still does the one plain thing every
# other sensed creature in this project already does when the player looms:
# it notices and gets away. This reuses CreaturePerception (is the player
# close enough to notice) and ThreatAvoidantWander (bias the flight heading
# away, keeping the sideways part) -- the same two pure modules the ground
# creature roster already senses/avoids threats through.

func test_a_ground_foraging_sparrow_scatters_when_the_player_gets_close():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var player := _player_at(Vector2(200, 200), parent)
	var bird := _flyer_in_tree(
		"sparrow",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX * 0.2, 0.0),
		parent
	)
	var started := bird.position.distance_to(player.position)
	for i in 30:
		bird._process(FRAME)
	assert_true(bird._flushed_by_player, "the player standing right on it must flush it")
	assert_gt(
		bird.position.distance_to(player.position), started, "and it must actually move away"
	)


## The same reaction, for the OTHER ground-foraging songbird -- proves the
## gate is FlyerDiet.forages_on_the_ground, not one species hardcoded in.
func test_a_ground_foraging_robin_scatters_too():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var bird := _flyer_in_tree(
		"robin",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX * 0.2, 0.0),
		parent
	)
	bird._process(FRAME)
	assert_true(bird._flushed_by_player)


## A bee takes nectar on the wing -- it never forages on the ground (see
## FlyerDiet.forages_on_the_ground) and it is not a true butterfly either
## (SpiralFlight.spirals), so this new reaction correctly leaves it exactly
## as before: the "which ambient creatures react to the player" boundary is
## real and tested, not silently widened to everything with wings.
func test_a_bee_still_does_not_react_to_the_player_at_all():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var bee := _flyer_in_tree(
		"bee",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX * 0.2, 0.0),
		parent
	)
	for i in 30:
		bee._process(FRAME)
		assert_false(bee._flushed_by_player)
		assert_false(bee._fleeing_from_player)


## A sparrow well outside the flush distance is just going about its life --
## the state must not latch on for a bird nowhere near the player.
func test_a_distant_sparrow_is_not_flushed():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var bird := _flyer_in_tree(
		"sparrow",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX * 4.0, 0.0),
		parent
	)
	for i in 30:
		bird._process(FRAME)
		assert_false(bird._flushed_by_player)


## The core ask: entering the perception radius flips the state to fleeing,
## and leaving it flips the state back -- mirroring
## test_a_fled_butterfly_settles_down_again's own shape for the butterfly
## mechanism.
func test_a_flushed_sparrow_settles_once_the_player_is_far_enough_away():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var player := _player_at(Vector2(200, 200), parent)
	var bird := _flyer_in_tree(
		"sparrow",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX * 0.2, 0.0),
		parent
	)
	for i in 10:
		bird._process(FRAME)
	assert_true(bird._flushed_by_player, "must actually be flushed first")
	player.position = Vector2(-9000, -9000)
	var settled := false
	for i in 120:
		bird._process(FRAME)
		if not bird._flushed_by_player:
			settled = true
			break
	assert_true(settled, "a scattered sparrow has to settle back down eventually")


## Pins the tuned constant itself, not just "somewhere well inside/outside
## it": a sparrow just inside SONGBIRD_FLUSH_DISTANCE_PX reacts, one just
## outside it does not.
func test_the_flush_distance_boundary_is_exact():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var just_inside := _flyer_in_tree(
		"sparrow",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX - 1.0, 0.0),
		parent
	)
	var just_outside := _flyer_in_tree(
		"sparrow",
		Vector2(200, 200) + Vector2(AmbientFlyerMarker.SONGBIRD_FLUSH_DISTANCE_PX + 1.0, 0.0),
		parent
	)
	just_inside._process(FRAME)
	just_outside._process(FRAME)
	assert_true(just_inside._flushed_by_player, "just inside the boundary must flush")
	assert_false(just_outside._flushed_by_player, "just outside it must not")


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


## IDLE REST -- reported live, after Phase 3/4 had already landed: "robins
## just fly from random point to point and don't switch between diverse
## actions / behaviour". Root cause: peck/walk/sing are all gated behind
## `perched`, and until now the ONLY thing that ever set `perched` was
## GroundForageBehavior actually committing to real food -- so a bird with
## nothing to eat nearby (a genuinely common condition: EarthwormPatch
## needs real soil moisture/warmth to surface anything at all) showed
## nothing but flight, forever, exactly as reported. Real birds spend much
## of their day perched whether or not they are actively eating.

func test_a_bird_with_no_food_anywhere_still_eventually_rests():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	# No worm_world/seed_world/fruit_world at all -- ground_forage exists
	# (set directly, the same way AmbientFlyerRenderer._build_marker does
	# for any species with a matching diet entry) but can never find
	# anything, the worst case this fix has to cover.
	bird.ground_forage = GroundForageBehavior.new()
	var rested := false
	for i in int((AmbientFlyerMarker.IDLE_REST_INTERVAL_SECONDS + 2.0) / FRAME):
		bird._process(FRAME)
		if bird.perched:
			rested = true
			break
	assert_true(rested, "a bird that can never find food must still occasionally rest")
	assert_eq(
		bird.ground_forage.phase, GroundForageBehavior.Phase.SEEKING,
		"idle rest must not touch ground_forage's own state -- it is a separate mechanism"
	)


func test_idle_rest_ends_and_the_bird_resumes_wander():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	bird.ground_forage = GroundForageBehavior.new()
	var steps := int((AmbientFlyerMarker.IDLE_REST_INTERVAL_SECONDS + AmbientFlyerMarker.IDLE_REST_DURATION_SECONDS + 3.0) / FRAME)
	var was_perched := false
	var resumed := false
	for i in steps:
		bird._process(FRAME)
		if bird.perched:
			was_perched = true
		elif was_perched:
			resumed = true
			break
	assert_true(was_perched, "precondition: it actually rested")
	assert_true(resumed, "a rest must actually end, not perch forever")


## Real food-seeking always outranks an idle rest -- a bird closing in on
## an actual worm must never be interrupted to go stand somewhere for no
## reason. Guaranteed by call order in _process (ground_forage.advance
## already claims the frame -- return true -- for anything but SEEKING,
## so _step_idle_rest is never even reached), confirmed directly here.
func test_idle_rest_never_fires_while_actively_pursuing_food():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	bird.ground_forage = GroundForageBehavior.new()
	bird._worm_target = Vector2(500, 500)  # far away -- never arrives within a frame
	for i in int((AmbientFlyerMarker.IDLE_REST_INTERVAL_SECONDS + 2.0) / FRAME):
		# Re-armed every frame: GroundForageBehavior's own DESCENT_TIMEOUT
		# (8s) would otherwise legitimately give up on an unreachable target
		# and return to SEEKING regardless of distance -- correct behaviour,
		# but not what this test isolates. Forcing DESCENDING back each
		# frame holds the bird in an active pursuit for the WHOLE window
		# (well past IDLE_REST_INTERVAL_SECONDS), purely to prove
		# _step_idle_rest is structurally unreachable while ground-forage
		# owns the frame -- not to model one real, continuous 14-second dive.
		bird.ground_forage.phase = GroundForageBehavior.Phase.DESCENDING
		bird.ground_forage._phase_elapsed = 0.0
		bird._process(FRAME)
		assert_false(
			bird.perched,
			"ground-forage owns this frame (DESCENDING) -- idle rest must never override perched"
		)


## PHASE 3: ground walk/hop and singing, the two rows Phase 1 measured but
## left unwired -- see docs/concept/ecosystem_dynamics.md's Phase 3
## writeup. Both are drawn only while `perched` (grounded), the same
## contract peck_frame already has, and both are additional alternatives
## to perched_frame, checked in the same branch, not a new state machine.

func test_a_bird_walks_during_the_resume_beat_after_a_peck():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	bird.ground_forage = GroundForageBehavior.new()
	bird.ground_forage.phase = GroundForageBehavior.Phase.RESUMING
	bird.perched = true
	bird.walk_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	bird.perched_frame = ImageTexture.new()
	bird._process(FRAME)
	assert_true(bird.walk_frames.has(bird.texture), "must show a walk frame during the resume beat")
	assert_ne(bird.texture, bird.perched_frame)


func test_a_bird_sings_when_its_own_song_roll_says_so():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	bird.wander_seed = 0
	bird._elapsed_time = 0.0  # BirdSong.should_sing(0, 0.0) is true
	bird.ground_forage = GroundForageBehavior.new()
	bird.ground_forage.phase = GroundForageBehavior.Phase.RESUMING
	bird.perched = true
	bird.sing_frames = [ImageTexture.new(), ImageTexture.new()]
	bird.walk_frames = [ImageTexture.new()]
	bird.perched_frame = ImageTexture.new()
	bird._process(FRAME)
	assert_true(bird.sing_frames.has(bird.texture), "singing must win over walking when the roll says sing")


func test_without_walk_or_sing_frames_a_grounded_bird_still_just_perches():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	bird.ground_forage = GroundForageBehavior.new()
	bird.ground_forage.phase = GroundForageBehavior.Phase.RESUMING
	bird.perched = true
	bird.perched_frame = ImageTexture.new()
	bird._process(FRAME)
	assert_eq(
		bird.texture, bird.perched_frame,
		"no walk_frames/sing_frames (an old caller, a test double) must be a no-op, not an error"
	)


## FLIGHT HEIGHT -- requested directly: "give birds a z height in their
## flight and scale size based on distance from ground / distance to
## camera". A top-down camera looking straight down makes "distance from
## the ground" and "distance from the camera" the SAME quantity -- there is
## no separate perspective axis to fake here, so one height value drives
## both the visual lift (offset.y, the same draw-only property the wingbeat
## bounce already uses -- see the test right below this one for why it must
## never touch `position`) and the scale shrink.
##
## Ground-truth for the height itself is `perched`, the same flag
## GroundForageBehavior/nectaring/touchdown already maintain: airborne
## rises toward FLIGHT_CRUISE_HEIGHT_PX, grounded falls back to 0 -- eased
## over real time (FLIGHT_HEIGHT_RATE_PX_PER_SEC) rather than snapping, so
## takeoff and landing both read as a real climb/descent instead of a pop.

func test_an_airborne_bird_climbs_toward_cruise_height():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	assert_eq(bird._flight_height, 0.0, "starts on the ground")
	for i in 300:
		bird._process(FRAME)
	assert_almost_eq(
		bird._flight_height, AmbientFlyerMarker.FLIGHT_CRUISE_HEIGHT_PX, 0.01,
		"a bird airborne this long must have reached cruise height"
	)


func test_a_grounded_bird_settles_back_to_zero_height():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for i in 300:
		bird._process(FRAME)
	assert_gt(bird._flight_height, 0.0, "must actually have climbed first")
	bird.perched = true
	for i in 300:
		bird._process(FRAME)
	assert_almost_eq(bird._flight_height, 0.0, 0.01, "landed birds return to ground height")


func test_height_changes_gradually_not_instantly():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	bird._process(FRAME)
	assert_lt(
		bird._flight_height, AmbientFlyerMarker.FLIGHT_CRUISE_HEIGHT_PX * 0.5,
		"one frame must not already be most of the way to cruise height"
	)
	assert_gt(bird._flight_height, 0.0, "...but it must have started climbing")


func test_a_higher_flying_bird_draws_smaller_and_higher_on_screen():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	# Wild-spawned adult, NOT begin_life() -- that starts a hatchling at
	# 0.45x scale (see LifeCycle.HATCHLING_SCALE), a growth confound this
	# test isn't about; age_seconds already defaults to LifeCycle.
	# MATURE_SECONDS, the same "spawned flyers start as ADULTS" contract
	# AmbientFlyerRenderer.build_bird relies on.
	bird.set_adult_scale(Vector2.ONE * 0.05)
	for i in 400:
		bird._process(FRAME)
	assert_true(bird.scale.x < 0.05, "cruise height must shrink the drawn size")
	assert_true(bird.offset.y < 0.0, "cruise height must lift the drawn sprite upward on screen")


func test_a_perched_bird_has_zero_height_and_its_full_ground_scale():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	bird.setup(AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	bird.set_adult_scale(Vector2.ONE * 0.05)
	bird.perched = true
	for i in 5:
		bird._process(FRAME)
	assert_almost_eq(bird.scale.x, 0.05, 0.0001, "grounded birds render at their real, unshrunk size")


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
	# Through FlapGlide, which is what decides when the wings are driving at
	# all; WingbeatBounce still owns the amplitude underneath it.
	assert_almost_eq(
		butterfly.offset.y,
		FlapGlide.body_offset(
			"monarch", butterfly._elapsed_time, AmbientFlyerMarker.FLAP_SECONDS_PER_FRAME,
			butterfly.flap_frames.size(), float(butterfly.texture.get_height()),
			butterfly.wander_seed
		),
		0.0001
	)
	assert_lte(
		absf(butterfly.offset.y),
		WingbeatBounce.amplitude_bodies("monarch")
			* float(butterfly.texture.get_height()) * 2.0 + 0.0001,
		"and the gait must not carry the body outside it"
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
## Real seed predation, not just dispersal (see SeedEndozoochory.
## GRANIVORY_CONSUMED_CHANCE, and docs/concept/flora.md's "No seed
## PREDATORS exist yet" open question, now closed for this one species): a
## true granivore like a sparrow digests and destroys the large majority of
## the ground seed it eats, only sometimes surviving gut passage to actually
## be planted. Sampled across many different wander_seeds -- a single bird
## only ever carries one seed at a time, so this cannot be observed by
## watching one bird eat repeatedly -- the same "spreads across true and
## false, not clustered on one side" shape
## test_forage_roll_spreads_across_true_and_false pins for AntColony.
## Talks to _take_targeted_seed/_step_seed_carrying directly (skipping the
## flight simulation) so 100 samples run fast, the same shortcut
## test_carrying_fruit_after_a_flower_seed_plants_a_tree_not_a_flower above
## already takes.
func test_a_sparrow_mostly_destroys_the_seed_it_eats_rather_than_planting_it():
	var consumed := 0
	var planted := 0
	for w in 100:
		var world := StubSeedWorld.new()
		world.seeds = [{"position": Vector2(50, 0), "species": "clover"}]
		_sparrow_on(world)
		marker.wander_seed = w
		marker._seed_target = Vector2(50, 0)
		marker._take_targeted_seed()
		marker._carried_seed_start_position = marker.position - Vector2(10000, 0)
		marker._step_seed_carrying(0.0)
		if world.planted.is_empty():
			consumed += 1
		else:
			planted += 1
	assert_gt(consumed, planted, "a real granivore destroys most of what it eats, not a coin flip")
	assert_gt(planted, 0, "but not literally every seed -- a minority still survives to be planted")


# -- the egg sprite: distinct from the tiny-scaled-adult look --------------
#
# Before this, an offspring rendered as the ADULT insect's own silhouette
# scaled down to LifeCycle.HATCHLING_SCALE from the moment it was spawned --
# a tiny adult, not anything egg-shaped, for the ENTIRE COURTING/MATED/EGG
# span (age_seconds < LifeCycle.HATCH_SECONDS). `egg_frame` (see
# ProceduralEggSprite, set by AmbientFlyerRenderer._build_marker) is shown
# instead for exactly that span; from STAGE_JUVENILE onward (age_seconds >=
# HATCH_SECONDS) nothing changes -- the existing scaled-adult sprite keeps
# growing via LifeCycle.size_scale_at exactly as it always has.
#
# Both halves are asserted by STAGE, not by a literal age value, so this
# stays true if the stage boundaries themselves are ever retuned.


func _pre_hatch_marker(egg: Texture2D) -> void:
	marker.egg_frame = egg
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))


func test_a_flyer_shows_its_egg_sprite_before_reaching_stage_juvenile():
	var egg := ImageTexture.new()
	_pre_hatch_marker(egg)
	marker.age_seconds = 0.0
	marker._process(1.0)
	assert_lt(
		LifeCycle.stage_at(marker.age_seconds), LifeCycle.STAGE_JUVENILE,
		"precondition: still pre-hatch after this step"
	)
	assert_eq(
		marker.texture, egg,
		"before STAGE_JUVENILE it should show the egg, not a scaled-down tiny adult"
	)


func test_a_flyer_shows_the_ordinary_scaled_adult_sprite_from_stage_juvenile_onward():
	var egg := ImageTexture.new()
	_pre_hatch_marker(egg)
	marker.age_seconds = LifeCycle.HATCH_SECONDS
	marker._process(1.0)
	assert_gte(
		LifeCycle.stage_at(marker.age_seconds), LifeCycle.STAGE_JUVENILE,
		"precondition: already hatched after this step"
	)
	assert_ne(
		marker.texture, egg,
		"from STAGE_JUVENILE onward it must be the ordinary (scaled) adult sprite, not the egg"
	)
	assert_true(
		marker.flap_frames.has(marker.texture),
		"should be animating the normal wing frames again, exactly as before this feature"
	)


## Without an egg_frame assigned (an older caller, or a test double), nothing
## should break -- the marker simply falls back to leaving the texture alone
## for that span rather than erroring, the same has_method-guard spirit every
## other optional field in this file follows.
func test_a_pre_hatch_flyer_with_no_egg_frame_set_does_not_error():
	marker.flap_frames = [ImageTexture.new()]
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 3
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))
	marker.age_seconds = 0.0
	marker._process(1.0)
	assert_lt(LifeCycle.stage_at(marker.age_seconds), LifeCycle.STAGE_JUVENILE)


# -- what a butterfly LOOKS like while it feeds ------------------------------
#
# Reported twice: "butterflies get stuck in front of a single flower". The
# forage RULE was measured and cleared (a butterfly visits 20-29 DISTINCT
# blooms per 600 simulated seconds, longest loiter 6.8-11.5s), so what is
# wrong is the picture, not the plan. On arrival the marker did
# `position = _forage_target` -- a hard snap onto an exact pixel -- and then,
# for the whole of PollinatorForaging.DRINK_SECONDS, never touched `position`
# again while _animate_wings ran the FLIGHT flap: `perched_frame` is generated
# by ProceduralBirdSprite alone (it is the only generate_perched_texture in
# src/rendering), so a butterfly had no settled frame at all and fell straight
# through to flap_frames. Net visual: a butterfly HOVERING, wings beating,
# motionless on one pixel, for 2.4 seconds, over and over -- which is exactly
# what "stuck IN FRONT OF a flower" describes.
#
# Real butterflies do not hover to feed. They LAND on the bloom and stand on
# it, hold the wings closed over the back and open them only slowly and
# occasionally (basking, not flying), and shuffle around the flower head
# working different florets with the proboscis. That is what these pin.

func _drinking_butterfly() -> void:
	marker.species = "monarch"
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 11
	marker.setup(AmbientFlyerMovement.new(16.0, 30.0, 0.7))
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	marker.settled_frames = [ImageTexture.new(), ImageTexture.new()]
	marker._drink_remaining = PollinatorForaging.DRINK_SECONDS


func test_a_drinking_butterfly_never_runs_the_flight_flap():
	_drinking_butterfly()
	for step in 20:  # 2.0s, inside DRINK_SECONDS
		marker._process(0.1)
		assert_false(
			marker.flap_frames.has(marker.texture),
			"a butterfly standing on a bloom must not beat its wings as if flying"
		)
		assert_true(
			marker.settled_frames.has(marker.texture),
			"it should be showing a settled, wings-folded frame"
		)


const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const NectaringPosture = preload("res://src/rendering/nectaring_posture.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")

const BUTTERFLY_SPEED := 16.0


## A monarch wired the way AmbientFlyerRenderer._build_marker wires one --
## real sprite, real settled frames, real drawn size. The shuffle is a
## fraction of the DRAWN body (see NectaringPosture.
## FLORET_SHUFFLE_BODY_FRACTION), so a bare ImageTexture.new() with no size
## and no scale would silently measure nothing.
func _drawn_monarch(world) -> void:
	var sprites := ProceduralButterflySprite.new()
	marker.species = "monarch"
	marker.texture = sprites.generate_texture("monarch", 3)
	marker.flap_frames = sprites.generate_flap_textures("monarch", 3)
	marker.settled_frames = sprites.generate_settled_textures("monarch", 3)
	marker.scale = (
		Vector2.ONE
		* ArtResolution.SPRITE_SCALE
		* FishRenderer.FISH_WORLD_SCALE
		* float(AmbientFlyerRenderer.FLYER_WORLD_SCALE["monarch"])
	)
	marker.scent_world = world
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 4242
	marker.setup(AmbientFlyerMovement.new(BUTTERFLY_SPEED, 30.0, 0.7))


## Steps until the flyer is actually drinking, and returns how far it moved on
## the frame it arrived (0 if it never got there).
func _step_until_drinking(step: float, budget: int) -> float:
	for i in budget:
		var before := marker.position
		marker._process(step)
		if marker._drink_remaining > 0.0:
			return before.distance_to(marker.position)
	return -1.0


# -- it MOVES while it feeds ------------------------------------------------


## The other half of "stuck in front of a flower": `position` was set once, on
## arrival, and then not touched again for the whole 2.4-second drink. A real
## butterfly walks around the flower head working different florets with the
## proboscis -- it is never a frozen pixel.
func test_a_feeding_butterfly_is_not_a_frozen_pixel():
	var world := StubScentWorld.new()
	world.flowers.append(
		{"position": Vector2(60, 0), "species": "rose", "nectar": 1.0, "landing": Vector2(60, 0)}
	)
	_drawn_monarch(world)
	assert_gte(_step_until_drinking(FRAME, 2000), 0.0, "precondition: it has to land first")

	var seen: Array[Vector2] = []
	while marker._drink_remaining > 0.0:
		marker._process(FRAME)
		seen.append(marker.position)
	var spread := 0.0
	for a in seen:
		for b in seen:
			spread = maxf(spread, a.distance_to(b))
	assert_gt(
		spread, 0.0,
		"a butterfly working a flower head does not hold one pixel for 2.4 seconds"
	)
	assert_gt(
		spread,
		0.5 * NectaringPosture.shuffle_reach_px(marker._drawn_body_px()),
		"and it works the head, not a twitch (moved across %.3f px)" % spread
	)


## ...but never off the bloom. The excursion is the size of a FLOWER HEAD, so
## it has to stay well inside PollinatorForaging.LANDING_DISTANCE -- otherwise
## "landed on this flower" and "standing on this flower" stop meaning the same
## thing and the forage rule's own arrival test starts disagreeing with the
## picture.
func test_a_feeding_butterfly_never_wanders_off_the_bloom_it_is_standing_on():
	var world := StubScentWorld.new()
	var bloom := Vector2(60, 0)
	world.flowers.append(
		{"position": bloom, "species": "rose", "nectar": 1.0, "landing": bloom}
	)
	_drawn_monarch(world)
	assert_gte(_step_until_drinking(FRAME, 2000), 0.0, "precondition: it has to land first")
	var worst := 0.0
	while marker._drink_remaining > 0.0:
		marker._process(FRAME)
		worst = maxf(worst, marker.position.distance_to(bloom))
	assert_lt(
		worst, PollinatorForaging.LANDING_DISTANCE,
		"it must still read as standing ON that bloom (strayed %.3f px)" % worst
	)


# -- it LANDS, rather than teleporting --------------------------------------


## On arrival the marker did `position = _forage_target` -- a hard snap of up
## to LANDING_DISTANCE onto an exact pixel, on the single frame the player is
## most likely to be watching this insect. It must now cover that last gap at
## its own airspeed like every other stretch of the approach.
func test_a_butterfly_alights_on_a_bloom_instead_of_teleporting_onto_it():
	var world := StubScentWorld.new()
	var bloom := Vector2(60, 0)
	world.flowers.append(
		{"position": bloom, "species": "rose", "nectar": 1.0, "landing": bloom}
	)
	_drawn_monarch(world)
	var arrival_jump := _step_until_drinking(FRAME, 2000)
	assert_gte(arrival_jump, 0.0, "precondition: it has to land first")
	assert_lte(
		arrival_jump, BUTTERFLY_SPEED * FRAME + 0.001,
		"nothing may move further in one frame than the flyer's own airspeed carries it"
	)
	assert_gt(
		marker.position.distance_to(bloom), 0.0,
		"it must not be standing exactly on the bloom the instant it is declared arrived"
	)


func test_and_it_really_is_standing_on_the_bloom_once_the_settle_is_over():
	var world := StubScentWorld.new()
	var bloom := Vector2(60, 0)
	world.flowers.append(
		{"position": bloom, "species": "rose", "nectar": 1.0, "landing": bloom}
	)
	_drawn_monarch(world)
	assert_gte(_step_until_drinking(FRAME, 2000), 0.0, "precondition: it has to land first")
	var settle := NectaringPosture.alighting_seconds(BUTTERFLY_SPEED, marker._drawn_body_px())
	for i in int(ceil(settle / FRAME)) + 1:
		marker._process(FRAME)
	assert_lte(
		marker.position.distance_to(bloom),
		NectaringPosture.shuffle_reach_px(marker._drawn_body_px()) + 0.001,
		"once it has set down it is on the flower, shuffle and all"
	)


# -- the wings, at the marker ------------------------------------------------


## Nothing is beating, so there is no lift pulse to rise and fall on -- the
## same statement the perched branch makes (see WingbeatBounce). A butterfly
## standing on a flower and bobbing as if flying is the hovering read all over
## again.
func test_a_drinking_butterfly_does_not_bob_on_a_wingbeat_it_is_not_making():
	var world := StubScentWorld.new()
	_drawn_monarch(world)  # real, SIZED frames: a zero-height texture bobs by zero anyway
	marker._drink_remaining = PollinatorForaging.DRINK_SECONDS
	marker.offset.y = 3.0
	for step in 20:
		marker._process(0.1)
		assert_eq(marker.offset.y, 0.0, "a settled butterfly's body sits where it is drawn")


## The whole reason the flight flap was showing: `perched_frame` is generated
## by ProceduralBirdSprite alone. Anything WITHOUT settled frames must still
## behave exactly as it did before this existed rather than erroring or
## freezing -- the same optional-field guard spirit as egg_frame/peck_frame.
func test_a_pollinator_with_no_settled_frames_still_animates_as_it_always_did():
	_drinking_butterfly()
	marker.settled_frames = []
	for step in 20:
		marker._process(0.1)
	assert_true(
		marker.flap_frames.has(marker.texture),
		"with nothing settled to show it falls back to the flap, as before"
	)


## Real basking is occasional. Across a whole stop the wings may swing open at
## most once -- if they opened and shut rhythmically it would just be a slower
## flap, which is the thing being fixed.
func test_the_settled_wings_swing_open_at_most_once_in_a_single_stop():
	_drinking_butterfly()
	var openings := 0
	var shut_frames := 0
	var was_shut := true
	var steps := int(PollinatorForaging.DRINK_SECONDS / FRAME)
	for step in steps:
		marker._process(FRAME)
		var open: bool = marker.texture != marker.settled_frames[0]
		if open and was_shut:
			openings += 1
		if not open:
			shut_frames += 1
		was_shut = not open
	assert_lte(openings, 1, "a feeding butterfly basks occasionally, it does not flap slowly")
	assert_gt(
		float(shut_frames) / float(steps), 0.5,
		"and the pose it HOLDS is wings-shut-over-the-back, not anything open"
			+ " (shut for %d of %d frames)" % [shut_frames, steps]
	)


## Flushing off a flower is the classic flight-initiation-distance
## measurement, and it must survive the settled pose: the moment it is
## airborne again it is flying, wings and all.
func test_a_butterfly_flushed_off_a_bloom_goes_straight_back_to_flying():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200) + Vector2(10.0, 0.0), parent)
	var sprites := ProceduralButterflySprite.new()
	shy.flap_frames = sprites.generate_flap_textures("monarch", 3)
	shy.settled_frames = sprites.generate_settled_textures("monarch", 3)
	shy._drink_remaining = PollinatorForaging.DRINK_SECONDS
	shy._process(FRAME)
	assert_true(shy._fleeing_from_player, "the player standing on it must flush it")
	assert_eq(shy._drink_remaining, 0.0, "and end the drink")
	assert_true(
		shy.flap_frames.has(shy.texture),
		"an airborne butterfly beats its wings again the instant it leaves the bloom"
	)


# -- the acceptance re-measurement ------------------------------------------
#
# The forage rule was cleared by measurement before any of this was written (a
# butterfly visits 20-29 DISTINCT blooms per 600 simulated seconds), and the
# whole risk of adding micro-motion to something the forage rule measures
# arrival against is that it quietly stops finding the next flower. So the
# same measurement runs here, over the same 600 simulated seconds, against a
# meadow big enough that the count is not capped by the meadow.


func test_a_butterfly_still_works_a_whole_meadow_over_ten_simulated_minutes():
	var world := StubScentWorld.new()
	_ring_of_flowers(world, Vector2.ZERO, 12, 3.0 * TILE_SIZE)
	_ring_of_flowers(world, Vector2.ZERO, 18, 6.0 * TILE_SIZE)
	_drawn_monarch(world)

	for step in 6000:  # ten simulated minutes
		marker._process(0.1)
		world.regenerate(0.1)

	var distinct := _distinct_flowers_visited(world)
	# Printed rather than only reported on failure: this is the acceptance
	# MEASUREMENT the whole forage rule was cleared by, and every pass that
	# touches how a flyer moves has to re-take it and show the number.
	gut.p(
		"FORAGE ACCEPTANCE: %d distinct blooms of %d, %d landings, over 600 simulated seconds"
			% [distinct, world.flowers.size(), world.drink_calls.size()]
	)
	assert_gte(
		distinct, 20,
		"micro-motion must not have cost the trap-line its circuit"
			+ " (distinct visited: %d of %d, landings: %d)"
				% [distinct, world.flowers.size(), world.drink_calls.size()]
	)


# == the one invariant: nothing ever outflies itself =========================
#
# The player asked "can you interpolate the state transitions?" and they were
# right: every state entry in the marker was a bare `position = <wherever the
# new state wants me>`, and a state entry is exactly the frame the player is
# most likely to be looking at the animal. Measured on the code as shipped, on
# 1/60 s frames, against a butterfly's own 0.267 px per frame:
#
#   courtship entry     14.89 px    the dance snapped onto a fixed 9 px orbit
#   spiral flight        3.27 px    the whirl swung the wide start radius at
#                                   the turn rate derived for a 4.4 px one
#   player-head dance    6.31 px    the same, round a head
#   worm arrival         3.52 px    `position = _worm_target`
#   fruit arrival        3.52 px    `position = _fruit_target`
#   seed arrival         3.52 px    `position = _seed_target`
#   grass seed arrival   3.52 px    `position = _grass_seed_target`
#   nectaring settle     0.40 px    eased, but sized `gap / airspeed`, and a
#                                   smoothstep runs 1.5x its average halfway
#
# So this section is ONE assertion, made everywhere: **nothing may move
# further in one step than the airspeed it is flying at carries it** (see
# FlightTransition, and AmbientFlyerMarker.airspeed_px_per_second, which is
# what "the airspeed it is flying at" means -- a cruise ordinarily, the burst
# while it is fleeing or flying one of the three aerial figures). That single
# statement catches all eight sites and any future one.

const FlightTransition = preload("res://src/rendering/flight_transition.gd")


## The worst single step any of these flyers took, as a multiple of what its
## own airspeed allowed on that step. Accumulated rather than asserted per
## frame so one failure names the worst moment instead of the first.
class Outflight:
	var worst_ratio := 0.0
	var worst_px := 0.0
	var allowed_px := 0.0
	var steps := 0

	func record(moved: float, ceiling_px: float) -> void:
		steps += 1
		if ceiling_px <= 0.0:
			return
		var ratio := moved / ceiling_px
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_px = moved
			allowed_px = ceiling_px

	func describe() -> String:
		return (
			"worst step %.4f px against an airspeed that allowed %.4f px (%.1fx) over %d steps"
			% [worst_px, allowed_px, worst_ratio, steps]
		)


## One step of one flyer, with the step it took measured against the airspeed
## it was flying at. The ceiling is the MORE permissive of the state it left
## and the state it arrived in, because the frame a flyer enters a new state
## belongs to both.
func _step_measured(flyer: AmbientFlyerMarker, delta: float, out: Outflight) -> void:
	var before := flyer.position
	var ceiling := FlightTransition.step_ceiling_px(flyer.airspeed_px_per_second(), delta)
	flyer._process(delta)
	ceiling = maxf(
		ceiling, FlightTransition.step_ceiling_px(flyer.airspeed_px_per_second(), delta)
	)
	out.record(before.distance_to(flyer.position), ceiling)


## Floating point only: the ceilings are derived by division and multiplied
## back out, so an exactly-at-the-limit step lands a few ULPs over.
const OUTFLIGHT_SLACK := 1.0 + 1.0e-4


func _assert_never_outflew(out: Outflight, what: String) -> void:
	assert_lte(
		out.worst_ratio, OUTFLIGHT_SLACK,
		"%s: %s -- nothing may move further in one frame than its own airspeed carries it"
			% [what, out.describe()]
	)


## Each case in the loops below gets its OWN patch of the world, far outside
## every other case's notice radius. add_child_autofree keeps the previous
## case's flyers alive in the tree and in FLOCK_GROUP until the test ends, and
## a leftover pair sitting on the same coordinates is a partner scan away from
## quietly changing what the next case measures.
func _case_origin(index: int) -> Vector2:
	return Vector2(1000.0 * float(index) + 100.0, 100.0)


# -- 1. the courtship dance --------------------------------------------------


func test_a_courtship_dance_never_outflies_the_butterflies_dancing_it():
	# The whole band of separations a pair can notice each other across, so the
	# widest entry the dance can ever be asked to make is covered.
	var gaps := [8, 16, 24, 32, 39]
	for case in gaps.size():
		var gap: int = gaps[case]
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child_autofree(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("monarch", at + Vector2(gap, 0), parent)
		var out := Outflight.new()
		var began := false
		for i in 60 * 10:
			_step_measured(a, FRAME, out)
			_step_measured(b, FRAME, out)
			# EITHER of them: the two commit on different frames (the second
			# only scans once its own search throttle expires), so watching one
			# of them alone can miss a dance the other is already flying.
			if a._courting_with != 0 or b._courting_with != 0:
				began = true
			elif began:
				break
		assert_true(began, "precondition: a pair %d px apart must dance" % gap)
		_assert_never_outflew(out, "a courtship dance entered from %d px apart" % gap)


# -- 2. the spiral flight ----------------------------------------------------


func test_a_whirl_never_outflies_the_butterflies_whirling_it():
	var gaps := [10, 22, 34, 46, 50]
	for case in gaps.size():
		var gap: int = gaps[case]
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child_autofree(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("swallowtail", at + Vector2(gap, 0), parent)
		var out := Outflight.new()
		var began := false
		for i in 60 * 10:
			_step_measured(a, FRAME, out)
			_step_measured(b, FRAME, out)
			if a._spiralling_with != 0 or b._spiralling_with != 0:
				began = true
			elif began:
				break
		assert_true(began, "precondition: a pair %d px apart must whirl" % gap)
		_assert_never_outflew(out, "a whirl entered from %d px apart" % gap)


# -- 3. the dance round the player's head ------------------------------------


func test_the_dance_round_a_players_head_never_outflies_the_butterfly():
	# Deliberately short of the notice radius at the far end: the flight
	# initiation distance is measured from the player's FEET but the orbit is
	# centred on their HEAD, so a butterfly standing right on the edge is
	# already outside the leash and lets go again.
	var reaches := [0.2, 0.4, 0.6]
	for case in reaches.size():
		var reach: float = reaches[case]
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child(parent)
		_player_at(at, parent)
		var bold := _butterfly_with_boldness(
			1.0, at + Vector2(SpiralFlight.NOTICE_RADIUS_PX * reach, 0.0), parent
		)
		var out := Outflight.new()
		for i in 60 * 8:
			_step_measured(bold, FRAME, out)
		assert_true(bold._dancing_at_player, "precondition: it has to be dancing")
		_assert_never_outflew(
			out, "a dance begun from %.0f%% of the notice radius" % (reach * 100.0)
		)
		# Freed rather than autofreed: this case's PLAYER has to leave the tree
		# with it. _nearest_player_position takes the first node in the "player"
		# group, so a leftover player from an earlier case is the one every
		# later butterfly measures itself against -- which silently puts them
		# hundreds of pixels "away" and hands them SimulationLod's slowest
		# update interval, in a test that measures per-frame movement.
		parent.free()


# -- 4-7. the four bird ground-forage arrivals -------------------------------


## Runs a ground forager until it has actually sat down on its food and pecked
## it, measuring every step. Returns false if it never got there.
func _forage_until_pecked(out: Outflight, budget: int = 4000) -> bool:
	var pecked := false
	for i in budget:
		_step_measured(marker, FRAME, out)
		if marker.ground_forage.phase == GroundForageBehavior.Phase.PECKING:
			pecked = true
		elif pecked and marker.ground_forage.phase == GroundForageBehavior.Phase.SEEKING:
			return true
	return pecked


func test_a_robin_never_outflies_itself_landing_on_a_worm():
	var world := _world_with_one_worm()
	_make_robin(world)
	var out := Outflight.new()
	assert_true(_forage_until_pecked(out), "precondition: it has to land on the worm")
	_assert_never_outflew(out, "a robin landing on a worm")


func test_a_robin_never_outflies_itself_landing_on_fallen_fruit():
	var world := StubFruitWorld.new()
	world.fruit = [{"position": Vector2(80, 0), "species": "cherry"}]
	_make_fruit_robin(world)
	var out := Outflight.new()
	assert_true(_forage_until_pecked(out), "precondition: it has to land on the fruit")
	_assert_never_outflew(out, "a robin landing on fallen fruit")


func test_a_sparrow_never_outflies_itself_landing_on_a_seed():
	var world := StubSeedWorld.new()
	world.seeds = [{"position": Vector2(80, 0), "species": "rose"}]
	_sparrow_on(world)
	var out := Outflight.new()
	assert_true(_forage_until_pecked(out), "precondition: it has to land on the seed")
	_assert_never_outflew(out, "a sparrow landing on a flower seed")


func test_a_sparrow_never_outflies_itself_landing_on_a_grass_seed():
	var world := StubSeedWorld.new()
	world.grass_seeds = [{"position": Vector2(80, 0)}]
	_sparrow_on(world)
	var out := Outflight.new()
	assert_true(_forage_until_pecked(out), "precondition: it has to land on the grass seed")
	_assert_never_outflew(out, "a sparrow landing on a grass seed")


# -- 8. the nectaring settle, which was eased but not slowed for the ease ----


## The one site that already interpolated -- and it still broke the invariant,
## in the least obvious way there is: the settle was sized `gap / airspeed`,
## which is the AVERAGE rate, and a smoothstep runs
## FlightTransition.EASE_PEAK_RATE times its average halfway through.
func test_an_alighting_butterfly_never_outflies_itself_even_mid_settle():
	var world := StubScentWorld.new()
	var bloom := Vector2(60, 0)
	world.flowers.append(
		{"position": bloom, "species": "rose", "nectar": 1.0, "landing": bloom}
	)
	_drawn_monarch(world)
	var out := Outflight.new()
	var drank := false
	for i in 2000:
		_step_measured(marker, FRAME, out)
		if marker._drink_remaining > 0.0:
			drank = true
		elif drank:
			break
	assert_true(drank, "precondition: it has to land and drink")
	_assert_never_outflew(out, "a butterfly alighting on a bloom")


# -- and the ordinary flight it is all measured against ----------------------


func test_ordinary_wander_never_outflies_the_flyer_either():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var moth := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var out := Outflight.new()
	for i in 60 * 30:
		_step_measured(moth, FRAME, out)
	_assert_never_outflew(out, "an ordinarily wandering butterfly")


func test_a_fleeing_butterfly_never_outflies_its_own_burst():
	var parent := Node2D.new()
	add_child_autofree(parent)
	_player_at(Vector2(200, 200), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200) + Vector2(10.0, 0.0), parent)
	var out := Outflight.new()
	var fled := false
	for i in 60 * 10:
		_step_measured(shy, FRAME, out)
		fled = fled or shy._fleeing_from_player
	assert_true(fled, "precondition: it has to bolt")
	_assert_never_outflew(out, "a butterfly bolting from the player")


# == and both partners still derive the same dance, with no messaging =========
#
# The subtlest risk in easing a PAIR entry: both partners compute the whole
# figure from the two ids and their own start offset, and never tell each
# other anything. If one eased in over a different duration than the other,
# they would converge onto different radii and stop reading as a pair. The
# joining partner therefore adopts the initiator's convergence exactly as it
# already adopts its clock and its centre, and their two start offsets are
# opposite by construction because the centre IS the midpoint.


func test_a_pair_stays_exactly_opposite_all_the_way_through_an_eased_entry():
	var gaps := [12, 24, 36]
	for case in gaps.size():
		var gap: int = gaps[case]
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child_autofree(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("monarch", at + Vector2(gap, 0), parent)
		for i in 120:
			a._process(FRAME)
			b._process(FRAME)
			if a._courting_with != 0 and b._courting_with != 0:
				break
		assert_ne(a._courting_with, 0, "precondition: the dance began")
		assert_eq(b._courting_with, a.get_instance_id(), "precondition: with each other")
		var worst_dot := -1.0
		var worst_radius_gap := 0.0
		while a._courting_with != 0:
			a._process(FRAME)
			b._process(FRAME)
			if a._courting_with == 0:
				break
			var from_a: Vector2 = a.position - a._courting_centre
			var from_b: Vector2 = b.position - b._courting_centre
			worst_dot = maxf(worst_dot, from_a.normalized().dot(from_b.normalized()))
			worst_radius_gap = maxf(worst_radius_gap, absf(from_a.length() - from_b.length()))
		assert_lt(
			worst_dot, -0.999,
			(
				"they must stay across the axis from each other from the first frame in"
				+ " (worst dot %.5f, %d px apart at the start)" % [worst_dot, gap]
			)
		)
		assert_lt(
			worst_radius_gap, 0.001,
			(
				"...and converge onto the same radius as each other, not two"
				+ " (worst %.5f px)" % worst_radius_gap
			)
		)


func test_a_whirling_pair_stays_exactly_opposite_through_its_eased_entry():
	var gaps := [14, 30, 46]
	for case in gaps.size():
		var gap: int = gaps[case]
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child_autofree(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("swallowtail", at + Vector2(gap, 0), parent)
		for i in 120:
			a._process(FRAME)
			b._process(FRAME)
			if a._spiralling_with != 0 and b._spiralling_with != 0:
				break
		assert_ne(a._spiralling_with, 0, "precondition: the whirl began")
		assert_eq(b._spiralling_with, a.get_instance_id(), "precondition: with each other")
		var worst_dot := -1.0
		var worst_radius_gap := 0.0
		while a._spiralling_with != 0:
			a._process(FRAME)
			b._process(FRAME)
			if a._spiralling_with == 0:
				break
			var from_a: Vector2 = a.position - a._spiral_centre
			var from_b: Vector2 = b.position - b._spiral_centre
			# The pair's shared climb and ground track move BOTH of them the
			# same way, so it is taken back out before the two offsets are
			# compared -- what has to stay opposite is the whirl itself.
			var shared: Vector2 = (
				SpiralFlight.rise(a._spiral_elapsed)
				+ SpiralFlight.travel(
					a._spiral_elapsed,
					Courtship.pair_seed(a.get_instance_id(), b.get_instance_id(), 0)
				)
			)
			from_a -= shared
			from_b -= shared
			worst_dot = maxf(worst_dot, from_a.normalized().dot(from_b.normalized()))
			worst_radius_gap = maxf(worst_radius_gap, absf(from_a.length() - from_b.length()))
		assert_lt(
			worst_dot, -0.999,
			"they must stay across the axis from each other (worst dot %.5f, gap %d)"
				% [worst_dot, gap]
		)
		assert_lt(
			worst_radius_gap, 0.001,
			"...and on the same radius (worst %.5f px)" % worst_radius_gap
		)


# == the EXIT, which is the half of a transition that is easy to miss ========
#
# All three aerial figures now begin without a jump, and all three used to END
# with one -- not in POSITION, which was always continuous, but in VELOCITY,
# which is what the eye actually reads as motion. On the frame a whirl ended,
# the flyer stopped orbiting at ~37 px/s and started wandering at 16 px/s along
# a heading AmbientFlyerMovement.direction_at picked from its own seed, with no
# relation to the tangent it had been flying. Measured across eight whirls on
# the code as shipped: a mean turn of 108 degrees on one frame, worst 168.
#
# The ceiling is not a taste threshold: it is how hard this animal can turn.
# A turn is flown by banking, the hardest bank it has is
# SpiralFlight.MAX_LOAD_FACTOR times its own weight, and at speed v that is a
# turn rate of a/v -- see SpiralFlight.turn_seconds, out of constants that
# already existed.


## How far a flyer's heading swings on the single frame an aerial figure ends.
func _exit_turn_degrees(a: AmbientFlyerMarker, b: AmbientFlyerMarker, spiralling: bool) -> float:
	var last_in := Vector2.ZERO
	for i in 60 * 15:
		var before := a.position
		var was: bool = a._spiralling_with != 0 if spiralling else a._courting_with != 0
		a._process(FRAME)
		b._process(FRAME)
		var moved := (a.position - before) / FRAME
		var still: bool = a._spiralling_with != 0 if spiralling else a._courting_with != 0
		if was and still:
			last_in = moved
		elif not was and not still and last_in.length() > 0.001 and moved.length() > 0.001:
			return rad_to_deg(absf(last_in.angle_to(moved)))
	return -1.0


## The hardest turn this butterfly can fly in one frame, in degrees. Derived,
## and the whole budget the exit has to fit inside.
func _one_frames_turn_degrees() -> float:
	return rad_to_deg(PI * FRAME / SpiralFlight.turn_seconds(PI, 16.0))


func test_a_whirl_does_not_end_with_the_butterfly_reversing():
	var worst := 0.0
	var measured := 0
	for case in 8:
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("swallowtail", at + Vector2(24, 0), parent)
		a._courting_cooldown = Courtship.COOLDOWN_SECONDS
		b._courting_cooldown = Courtship.COOLDOWN_SECONDS
		for i in 300:
			a._process(FRAME)
			b._process(FRAME)
			if a._spiralling_with != 0:
				break
		var turn := _exit_turn_degrees(a, b, true)
		if turn >= 0.0:
			worst = maxf(worst, turn)
			measured += 1
		parent.free()
	assert_gt(measured, 5, "precondition: most of these pairs have to actually whirl and stop")
	assert_lte(
		worst, _one_frames_turn_degrees(),
		(
			"a butterfly coming off a whirl turned %.1f degrees on one frame,"
			+ " and the hardest turn it can fly is %.1f"
		) % [worst, _one_frames_turn_degrees()]
	)


func test_nor_does_a_dance():
	var worst := 0.0
	var measured := 0
	for case in 5:
		var at := _case_origin(case)
		var parent := Node2D.new()
		add_child(parent)
		var a := _flyer_in_tree("monarch", at, parent)
		var b := _flyer_in_tree("monarch", at + Vector2(20, 0), parent)
		for i in 300:
			a._process(FRAME)
			b._process(FRAME)
			if a._courting_with != 0:
				break
		var turn := _exit_turn_degrees(a, b, false)
		if turn >= 0.0:
			worst = maxf(worst, turn)
			measured += 1
		parent.free()
	assert_gt(measured, 2, "precondition: these pairs have to actually dance and stop")
	assert_lte(
		worst, _one_frames_turn_degrees(),
		"a butterfly coming off a dance turned %.1f degrees on one frame" % worst
	)


## The turn has to finish, not merely start: a flyer that never let go of the
## tangent would fly off in a straight line forever, which is the opposite
## failure and just as wrong.
func test_and_the_turn_off_the_tangent_actually_finishes():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("swallowtail", Vector2(124, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 300:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0:
			break
	while a._spiralling_with != 0:
		a._process(FRAME)
		b._process(FRAME)
	var recovery := SpiralFlight.turn_seconds(PI, 16.0)
	for i in int(ceil(recovery / FRAME)) + 2:
		a._process(FRAME)
	assert_eq(
		a._exit_recovery_seconds, 0.0,
		"the flyer has to be back on ordinary wander once the turn is flown"
	)


## The bug this whole file has produced three separate ways: blending two
## headings componentwise gives a near-zero vector where they nearly oppose,
## and a flyer that moves by nothing is a flyer stalled in mid-air. The turn is
## a SLERP for exactly that reason, and this walks a whole recovery to prove it.
func test_turning_off_the_tangent_never_stalls_a_butterfly():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2(100, 100), parent)
	var b := _flyer_in_tree("swallowtail", Vector2(124, 100), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	for i in 300:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with != 0:
			break
	while a._spiralling_with != 0:
		a._process(FRAME)
		b._process(FRAME)
	for i in 120:
		var before := a.position
		a._process(FRAME)
		assert_gt(
			before.distance_to(a.position), 0.0,
			"only drinking may ever hold a flyer still (frame %d after a whirl)" % i
		)


# == the WINGS, which swap on one frame unless something says otherwise ======


## Landing: a butterfly alights with its wings SPREAD and folds them
## afterwards. The settled cycle used to be read off wall time, so an insect
## that had just been beating its wings was usually drawn fully shut on the
## very next frame -- the same one-frame swap, in the picture rather than in
## the position.
func test_a_butterfly_lands_with_its_wings_open_and_folds_them():
	var world := StubScentWorld.new()
	var bloom := Vector2(60, 0)
	world.flowers.append(
		{"position": bloom, "species": "rose", "nectar": 1.0, "landing": bloom}
	)
	_drawn_monarch(world)
	assert_gte(_step_until_drinking(FRAME, 2000), 0.0, "precondition: it has to land first")
	marker._process(FRAME)
	assert_eq(
		marker.texture, marker.settled_frames[marker.settled_frames.size() - 1],
		"the frame it sets down on is the fully-open one"
	)
	# ...and it is shut again well before the drink is over.
	for i in int(ceil(NectaringPosture.SECONDS_PER_CYCLE / FRAME)):
		marker._process(FRAME)
		if marker.texture == marker.settled_frames[0]:
			break
	assert_eq(marker.texture, marker.settled_frames[0], "and folds them, rather than holding open")


## Taking off: a real butterfly opens its wings and beats. The wing clock
## free-runs, so the stroke resumed at whatever frame wall time was on -- wings
## folded over the back to mid-downstroke on one frame. Flap frame 0 is the
## fully-open pose by construction (ProceduralButterflySprite.
## generate_flap_images has openness 1.0 at i = 0), so the stroke now starts
## there.
func test_a_butterfly_takes_off_from_the_open_winged_frame():
	var parent := Node2D.new()
	add_child_autofree(parent)
	# Out of range to begin with, so the insect actually gets to sit on the
	# bloom and let its free-running wing clock drift somewhere arbitrary before
	# anything flushes it.
	var player := _player_at(Vector2(200, 900), parent)
	var shy := _butterfly_with_boldness(0.0, Vector2(200, 200), parent)
	var sprites := ProceduralButterflySprite.new()
	shy.flap_frames = sprites.generate_flap_textures("monarch", 3)
	shy.settled_frames = sprites.generate_settled_textures("monarch", 3)
	shy._drink_remaining = PollinatorForaging.DRINK_SECONDS
	for i in 37:
		shy._process(FRAME)
	assert_true(shy.settled_frames.has(shy.texture), "precondition: it is settled on the bloom")

	player.position = shy.position + Vector2(6.0, 0.0)
	shy._process(FRAME)
	assert_true(shy.flap_frames.has(shy.texture), "precondition: the flush puts it back in the air")
	assert_eq(
		shy.texture, shy.flap_frames[0],
		"it opens its wings and beats, rather than resuming mid-stroke"
	)


# == the LATE JOIN, which is the ninth entry and the one that hid ============
#
# Markers are processed one after another, and a flyer that scanned and came up
# empty waits PARTNER_SEARCH_INTERVAL before scanning again -- so the second of
# a pair routinely joins a figure its partner began up to half a second ago,
# having flown ordinary wander the whole time. Adopting the partner's clock and
# the mirror of its start offset therefore threw the joiner onto the far side
# of an orbit it had never been on. Measured at the full half-second delay:
# **17.3x its own airspeed on one frame**, on top of every entry easing that had
# already been done. Both figures now RE-BASE on where the two actually are
# (see _begin_spiral_flight), which moves neither of them.


## Runs a pair that meet, with `delay` seconds of search throttle held against
## the second one so it is forced to join late. Returns the worst step either
## flyer took as a multiple of its own airspeed.
func _worst_step_joining_late(delay: float, spiralling: bool) -> float:
	var parent := Node2D.new()
	add_child(parent)
	var a := _flyer_in_tree("monarch", Vector2.ZERO, parent)
	var b := _flyer_in_tree(
		"swallowtail" if spiralling else "monarch", Vector2(24, 0), parent
	)
	if spiralling:
		a._courting_cooldown = Courtship.COOLDOWN_SECONDS
		b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._partner_search_cooldown = delay
	var out := Outflight.new()
	var joined := false
	for i in 300:
		_step_measured(a, FRAME, out)
		_step_measured(b, FRAME, out)
		var busy: bool = b._spiralling_with != 0 if spiralling else b._courting_with != 0
		if busy:
			joined = true
		elif joined:
			break
	var worst := out.worst_ratio if joined else -1.0
	parent.free()
	return worst


func test_a_butterfly_joining_a_whirl_late_does_not_teleport_into_it():
	for delay in [0.0, 0.1, 0.25, AmbientFlyerMarker.PARTNER_SEARCH_INTERVAL]:
		var worst := _worst_step_joining_late(delay, true)
		assert_gte(worst, 0.0, "precondition: it has to actually join (delay %.2f s)" % delay)
		assert_lte(
			worst, OUTFLIGHT_SLACK,
			"joining a whirl %.2f s late moved a butterfly %.1fx its own airspeed" % [delay, worst]
		)


func test_nor_does_one_joining_a_dance_late():
	for delay in [0.0, 0.1, 0.25, AmbientFlyerMarker.PARTNER_SEARCH_INTERVAL]:
		var worst := _worst_step_joining_late(delay, false)
		assert_gte(worst, 0.0, "precondition: it has to actually join (delay %.2f s)" % delay)
		assert_lte(
			worst, OUTFLIGHT_SLACK,
			"joining a dance %.2f s late moved a butterfly %.1fx its own airspeed" % [delay, worst]
		)


## ...and the re-base has to leave them a PAIR. This is the property the old
## adopt-the-mirror code was buying with that teleport, and it must survive
## being bought a different way.
func test_a_late_joined_pair_is_still_exactly_opposite_from_the_first_frame():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("monarch", Vector2.ZERO, parent)
	var b := _flyer_in_tree("swallowtail", Vector2(24, 0), parent)
	a._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._courting_cooldown = Courtship.COOLDOWN_SECONDS
	b._partner_search_cooldown = AmbientFlyerMarker.PARTNER_SEARCH_INTERVAL
	for i in 300:
		a._process(FRAME)
		b._process(FRAME)
		if b._spiralling_with != 0:
			break
	assert_eq(b._spiralling_with, a.get_instance_id(), "precondition: it joined late")
	assert_eq(a._spiral_centre, b._spiral_centre, "one whirl, one centre")
	assert_eq(a._spiral_elapsed, b._spiral_elapsed, "...and one clock")
	assert_eq(
		a._spiral_closing_seconds, b._spiral_closing_seconds,
		"...and one convergence, or they draw onto different radii"
	)
	var worst_dot := -1.0
	while a._spiralling_with != 0:
		a._process(FRAME)
		b._process(FRAME)
		if a._spiralling_with == 0:
			break
		var shared: Vector2 = (
			SpiralFlight.rise(a._spiral_elapsed)
			+ SpiralFlight.travel(
				a._spiral_elapsed,
				Courtship.pair_seed(a.get_instance_id(), b.get_instance_id(), 0)
			)
		)
		var from_a: Vector2 = a.position - a._spiral_centre - shared
		var from_b: Vector2 = b.position - b._spiral_centre - shared
		worst_dot = maxf(worst_dot, from_a.normalized().dot(from_b.normalized()))
	assert_lt(worst_dot, -0.999, "they must whirl opposite each other (worst dot %.5f)" % worst_dot)


# --- the robin wired through the behavior DSL (docs/concept/behavior_dsl.md) --
#
# _step_songbird_flight_response, _step_pair_interactions and
# _step_ground_forage are unchanged -- reused by calling them, not
# reimplemented. What's new is WHICH ONE runs first this frame, expressed
# as a real parsed behaviour script instead of the three sequential `if`s
# every other species still uses. Only robin is wired -- sparrow and every
# butterfly keep their original, direct dispatch, which is what the
# species-gating tests below prove, and what the rest of this file's
# existing flush/courtship/forage tests (unchanged, run against a real
# robin) prove stayed correct once routed through the tree.

func test_a_robin_is_given_a_parsed_behavior_tree():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	assert_not_null(bird._behavior_tree)
	assert_eq(bird._behavior_tree["kind"], "priority")


func test_a_sparrow_is_not_wired_yet_even_though_it_also_ground_forages():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("sparrow", Vector2(0, 0), parent)
	assert_null(bird._behavior_tree)


func test_a_butterfly_is_not_wired():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("monarch", Vector2(0, 0), parent)
	assert_null(bird._behavior_tree)


## The parse is a one-time cost, not a per-individual one (docs/concept/
## behavior_dsl.md's own open question) -- every robin gets the identical
## tree, not a fresh parse each spawn.
func test_every_robin_gets_the_identical_tree():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var a := _flyer_in_tree("robin", Vector2(0, 0), parent)
	var b := _flyer_in_tree("robin", Vector2(50, 50), parent)
	assert_eq(a._behavior_tree, b._behavior_tree)


## A robin marker built without movement (setup() never called, or built
## bare in a test) must not crash: the original code's own
## `if _movement == null: return` guard, preserved through the tree path.
func test_a_robin_with_no_movement_configured_does_not_crash():
	var bird := AmbientFlyerMarker.new()
	bird.species = "robin"
	add_child_autofree(bird)
	bird.set_process(false)
	bird._process(FRAME)
	# A real assertion, not just "didn't throw": the frame actually ran to
	# completion (this field advances unconditionally, near the top of
	# _process), rather than the test merely having reached this line
	# because GUT swallowed a script error silently.
	assert_almost_eq(bird._elapsed_time, FRAME, 0.0001)


## The exact scenario test_a_ground_foraging_robin_scatters_too already
## covers end to end, restated here as the tree-specific claim: the flush
## fires as the FIRST thing the tree tries, before courtship or foraging
## ever get a look in this frame.
func test_the_flush_leaf_is_tried_before_courtship_or_foraging():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var bird := _flyer_in_tree("robin", Vector2(0, 0), parent)
	var leaves: Array = bird._behavior_tree["children"]
	assert_eq(leaves[0]["atom"], "songbird_flush")
	assert_eq(leaves[1]["atom"], "bird_courtship")
	assert_eq(leaves[2]["atom"], "ground_forage")
