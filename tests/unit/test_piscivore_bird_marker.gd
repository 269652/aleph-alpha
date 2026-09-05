extends GutTest

## A fish-eating bird (kingfisher) marker -- cruises like an ambient flyer
## until it commits to a dive on nearby water, then on a successful grab,
## actually decrements the real aquatic population (see
## docs/concept/ecosystem_dynamics.md's "fish-eating birds").

const PiscivoreBirdMarker = preload("res://src/rendering/piscivore_bird_marker.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const PiscivoreBirdBehavior = preload("res://src/gameplay/piscivore_bird_behavior.gd")
const PiscivoreAppetite = preload("res://src/gameplay/piscivore_appetite.gd")


## A stub fish standing at a fixed spot, with the one method a startled fish
## needs (see FishMarker.bolt_from).
class StubFish:
	extends Node2D
	var bolted_from = null
	func bolt_from(threat: Vector2) -> void:
		bolted_from = threat


## Duck-typed world (the EarthChunkManager contract the marker uses): where
## the nearest fish is, taking one, startling one, and a log of catches.
##
## `nearest_fish_position` is what turned this bird from a wanderer that
## happened across water into a hunter that goes to the fish -- a bird whose
## territory was inland essentially never fished before.
class StubWorld:
	var population := 5.0
	var fish: Node2D = null
	var recorded_catches: Array = []
	var startled: Array = []
	var capacity := 10.0
	func fish_population_near(_pixel_position: Vector2) -> float:
		return population
	## What the water could support -- paired with the population above so the
	## bird can tell a healthy pond from a worked-out one (see
	## PiscivoreAppetite.will_hunt).
	func fish_capacity_near(_pixel_position: Vector2) -> float:
		return capacity
	func record_fish_catch_near(pixel_position: Vector2, count: float) -> void:
		recorded_catches.append({"position": pixel_position, "count": count})
	func nearest_fish_position(_pixel_position: Vector2, _max_distance: float):
		return fish if fish != null and is_instance_valid(fish) else null
	func catch_nearest_fish(_pixel_position: Vector2, _max_distance: float) -> String:
		if fish == null or not is_instance_valid(fish):
			return ""
		fish.queue_free()
		fish = null
		return "goldfish"
	func startle_fish_near(_pixel_position: Vector2, threat: Vector2, _max: float) -> bool:
		startled.append(threat)
		if fish != null and is_instance_valid(fish):
			fish.bolt_from(threat)
		return true


var marker: PiscivoreBirdMarker


func before_each():
	marker = PiscivoreBirdMarker.new()
	marker.home = Vector2.ZERO
	marker.position = Vector2.ZERO
	marker.wander_seed = 7


func after_each():
	marker.free()


## See World's mouse-hover animal-name tooltip (docs feature request).
func test_get_display_name_capitalizes_the_species():
	marker.species = "kingfisher"
	assert_eq(marker.get_display_name(), "Kingfisher")


func test_does_nothing_without_setup():
	marker._process(1.0)
	assert_eq(marker.position, Vector2.ZERO)


func test_stays_cruising_when_no_fish_are_nearby():
	var world := StubWorld.new()
	world.population = 0.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for i in 20:
		marker._process(0.1)
	assert_eq(marker._behavior.phase, PiscivoreBirdBehavior.Phase.CRUISE)
	assert_eq(world.recorded_catches.size(), 0)


func test_eventually_dives_when_fish_are_present():
	var world := StubWorld.new()
	world.population = 5.0
	world.capacity = 5.0
	# "Fish are present" now means a fish is actually there to hunt: the bird
	# goes TO one rather than waiting for its wander to cross water.
	world.fish = StubFish.new()
	add_child_autofree(world.fish)
	world.fish.position = Vector2(12, 0)
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	var dove := false
	for i in 20:
		marker._hunger = 1.0
		marker._activity = PiscivoreAppetite.ACTIVITY_HUNT
		marker._process(0.1)
		if marker._behavior.phase != PiscivoreBirdBehavior.Phase.CRUISE:
			dove = true
			break
	assert_true(dove, "bird should dive when fish are present")


## Overwhelming fish presence still doesn't guarantee any single dive
## succeeds (see PiscivoreBirdBehavior.CATCH_CHANCE) -- run enough dive
## cycles that at least one grab should succeed, and confirm it actually
## reaches the world.
func test_a_successful_grab_records_a_catch_against_the_world():
	var world := StubWorld.new()
	world.population = 1000.0
	world.capacity = 1000.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for i in 2000:
		# A fresh fish for every hunt: the bird takes the one it catches, and
		# a stub with a single fish would only ever support one strike.
		if world.fish == null or not is_instance_valid(world.fish):
			world.fish = StubFish.new()
			add_child_autofree(world.fish)
			world.fish.position = marker.position + Vector2(4, 0)
		marker._hunger = 1.0
		marker._activity = PiscivoreAppetite.ACTIVITY_HUNT
		marker._process(0.1)
		if not world.recorded_catches.is_empty():
			break
	assert_gt(world.recorded_catches.size(), 0, "at least one dive should succeed within this many attempts")
	assert_almost_eq(world.recorded_catches[0]["count"], 1.0, 0.001)


# -- both outcomes are visible -----------------------------------------------
#
# A strike used to resolve as a number changing: the bird bobbed and the
# aquatic population went down by one. Requested directly -- "if the
# kingfisher succeeds we should see the fish being carried away and eaten and
# if it fails we should see the fish evade with a fast movement".

func _hunt_until(world: StubWorld, wanted_success: bool, frames: int) -> bool:
	for i in frames:
		if world.fish == null or not is_instance_valid(world.fish):
			world.fish = StubFish.new()
			add_child_autofree(world.fish)
			world.fish.position = marker.position + Vector2(4, 0)
		# Held hungry on purpose. Appetite is real time now -- two real hours
		# between meals (see PiscivoreAppetite) -- and these tests are about
		# what a STRIKE does, not about how often one happens. The pacing has
		# its own tests.
		marker._hunger = 1.0
		marker._activity = PiscivoreAppetite.ACTIVITY_HUNT
		marker._process(0.1)
		var struck := marker._behavior.phase == PiscivoreBirdBehavior.Phase.CARRYING
		if wanted_success and struck:
			return true
		# A miss is now delivered to the TARGETED fish directly rather than
		# to whatever the world finds nearest, so that is what is checked.
		if not wanted_success and world.fish != null and is_instance_valid(world.fish) 				and world.fish.bolted_from != null:
			return true
	return false


func test_a_caught_fish_is_visibly_carried_off():
	var world := StubWorld.new()
	world.population = 1000.0
	world.capacity = 1000.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	assert_true(_hunt_until(world, true, 3000), "precondition: a strike landed")
	assert_not_null(marker._carried_fish, "a caught fish must be visible in the beak")


func test_the_carried_fish_is_eventually_eaten():
	var world := StubWorld.new()
	world.population = 1000.0
	world.capacity = 1000.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	assert_true(_hunt_until(world, true, 3000), "precondition: a strike landed")
	for i in 200:
		marker._process(0.1)
		if marker._carried_fish == null:
			break
	assert_null(marker._carried_fish, "the fish gets swallowed rather than carried forever")


## The one that got away actually gets away.
func test_a_missed_strike_sends_the_fish_bolting():
	var world := StubWorld.new()
	world.population = 1000.0
	world.capacity = 1000.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	assert_true(_hunt_until(world, false, 3000), "precondition: a strike missed")
	assert_not_null(
		world.fish.bolted_from,
		"the fish the bird actually aimed at should be the one that bolts"
	)


# -- a bird does not fish out a chunk ----------------------------------------
#
# The reported problem, stated as a behaviour: the kingfisher hunted
# continuously and would work a pond until nothing was left in it.

func test_a_bird_left_alone_all_day_takes_only_a_couple_of_fish():
	var world := StubWorld.new()
	world.population = 20.0
	world.capacity = 20.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	# A whole in-game day, at a coarse step -- appetite is what is being
	# measured, so the step only has to be small enough to resolve a strike.
	var step := 1.0
	var elapsed := 0.0
	while elapsed < PiscivoreAppetite.SECONDS_PER_IN_GAME_DAY:
		if world.fish == null or not is_instance_valid(world.fish):
			world.fish = StubFish.new()
			add_child_autofree(world.fish)
			world.fish.position = marker.position + Vector2(4, 0)
		marker._process(step)
		elapsed += step
	assert_lte(
		world.recorded_catches.size(), 3,
		"a bird should take a couple of fish a day, not empty the pond"
	)


## And it stops working water that has already been worked out, which is what
## protects a population that is actually in trouble.
func test_a_bird_leaves_a_depleted_pond_alone():
	var world := StubWorld.new()
	world.population = 1.0   # almost nothing left...
	world.capacity = 20.0    # ...in water that should hold plenty
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	for _i in 400:
		world.fish = StubFish.new() if world.fish == null or not is_instance_valid(world.fish) else world.fish
		if world.fish.get_parent() == null:
			add_child_autofree(world.fish)
			world.fish.position = marker.position + Vector2(4, 0)
		marker._hunger = 1.0  # hungry throughout: only the pond's state should stop it
		marker._activity = PiscivoreAppetite.ACTIVITY_HUNT
		marker._process(0.1)
	assert_eq(
		world.recorded_catches.size(), 0,
		"a hungry bird still leaves a worked-out pond alone"
	)


# -- the wings actually flap --------------------------------------------------
#
# The marker used to show one static resting-pose texture for its whole
# life -- cruising, hovering, diving, carrying a fish home, all one frame.
# Every other flyer (AmbientFlyerMarker._animate_wings) cycles flap_frames
# and holds perched_frame while truly at rest; this marker never did
# (reported: "fix the kingfisher's wings").

func test_flying_cycles_through_the_flap_frames_over_time():
	var world := StubWorld.new()
	world.population = 0.0  # nothing to hunt: stays cruising/patrolling
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	marker.flap_frames = [
		ImageTexture.new(), ImageTexture.new(), ImageTexture.new(), ImageTexture.new()
	]
	var seen := {}
	for i in 40:
		marker._process(0.05)
		seen[marker.texture] = true
	assert_gt(seen.size(), 1, "a flying kingfisher should cycle through its wing-beat frames")


func test_a_perched_kingfisher_holds_the_perched_frame():
	var world := StubWorld.new()
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker.perched_frame = ImageTexture.new()
	marker._hunger = 0.0
	marker._activity = PiscivoreAppetite.ACTIVITY_PERCH
	marker._process(0.1)
	assert_eq(
		marker.texture, marker.perched_frame,
		"a perched kingfisher should hold still, not flap"
	)


func test_hunting_still_flaps_rather_than_freezing_on_one_frame():
	var world := StubWorld.new()
	world.population = 1000.0
	world.capacity = 1000.0
	world.fish = StubFish.new()
	add_child_autofree(world.fish)
	world.fish.position = Vector2(4, 0)
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	marker.flap_frames = [
		ImageTexture.new(), ImageTexture.new(), ImageTexture.new(), ImageTexture.new()
	]
	var seen := {}
	for i in 60:
		if world.fish == null or not is_instance_valid(world.fish):
			world.fish = StubFish.new()
			add_child_autofree(world.fish)
			world.fish.position = marker.position + Vector2(4, 0)
		marker._hunger = 1.0
		marker._activity = PiscivoreAppetite.ACTIVITY_HUNT
		marker._process(0.05)
		seen[marker.texture] = true
	assert_gt(
		seen.size(), 1,
		"the wings should keep beating through the hunt/hover/dive/carry sequence too"
	)


## PHASE 3: a real dive pose (IllustratedBirdSprite.generate_dive_textures)
## instead of reusing the flap cycle through the strike -- see
## docs/concept/ecosystem_dynamics.md's Phase 3 writeup.
func test_a_diving_kingfisher_shows_its_own_dive_frame_not_a_flap_frame():
	var world := StubWorld.new()
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker.dive_frames = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	marker._behavior.phase = PiscivoreBirdBehavior.Phase.DIVING
	marker._process(0.05)
	assert_true(
		marker.dive_frames.has(marker.texture),
		"a diving kingfisher must show one of its own dive frames"
	)
	assert_false(marker.flap_frames.has(marker.texture))


func test_without_dive_frames_a_diving_kingfisher_falls_back_to_flapping():
	var world := StubWorld.new()
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	marker.flap_frames = [ImageTexture.new(), ImageTexture.new()]
	marker._behavior.phase = PiscivoreBirdBehavior.Phase.DIVING
	marker._process(0.05)
	assert_true(
		marker.flap_frames.has(marker.texture),
		"no dive_frames set (an old caller, a test double) must be a no-op, not an error"
	)


func test_without_flap_frames_the_marker_keeps_its_original_texture():
	var world := StubWorld.new()
	world.population = 0.0
	marker.setup(world, AmbientFlyerMovement.new(20.0, 40.0, 1.0))
	marker.species = "kingfisher"
	var original := ImageTexture.new()
	marker.texture = original
	for i in 10:
		marker._process(0.05)
	assert_eq(
		marker.texture, original,
		"a marker with no flap_frames (an old caller, a test double) should be a no-op, not an error"
	)
