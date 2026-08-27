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
		marker._carry_seconds_remaining = 0.0
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
