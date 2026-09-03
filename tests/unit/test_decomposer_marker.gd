extends GutTest

## Ants and carrion bugs -- the tier that finishes what a player's own
## butchering doesn't (see docs/concept/carrion.md). Directly scans the
## Carcass/CarcassGuts groups (the same get_tree().get_nodes_in_group shape
## Player's own melee-sweep steps already use) rather than needing an
## injected "world" -- there's nothing chunk-specific about "is there
## carrion nearby" the way there is for e.g. worms.

const DecomposerMarker = preload("res://src/rendering/decomposer_marker.gd")
const CarrionForageBehavior = preload("res://src/gameplay/carrion_forage_behavior.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")

var marker: DecomposerMarker
var carcass: Carcass


func before_each():
	marker = DecomposerMarker.new()
	marker.species = "ant"
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 7
	add_child_autofree(marker)


func after_each():
	if is_instance_valid(carcass):
		carcass.free()


func _rotten_carcass_at(at: Vector2) -> Carcass:
	var c := Carcass.new()
	c.species = "boar"
	c.position = at
	add_child_autofree(c)
	c._process(Carcass.ROT_SECONDS + 1.0)  # make it rotten immediately
	return c


func test_joins_the_decomposer_group():
	assert_true(marker.is_in_group(DecomposerMarker.GROUP_NAME))


func test_stays_near_home_while_nothing_to_eat():
	for i in 30:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), DecomposerMarker.WANDER_RADIUS_PX * 2.0)


## The full loop, end to end: a rotten carcass nearby is eventually found,
## walked to, and actually bitten -- its real decompose health drops.
func test_finds_and_bites_a_nearby_rotten_carcass():
	carcass = _rotten_carcass_at(Vector2(110, 100))
	var before: float = carcass._decompose_health
	for i in 200:
		marker._process(0.5)
		if carcass._decompose_health < before:
			break
	assert_lt(carcass._decompose_health, before)


func test_eating_a_rotten_carcass_eventually_frees_it():
	carcass = _rotten_carcass_at(Vector2(102, 100))  # close, so it arrives quickly
	for i in 400:
		marker._process(0.5)
		if carcass.is_queued_for_deletion():
			break
	assert_true(carcass.is_queued_for_deletion())


# -- target preference: fly-blown carcasses out-compete fresh ones (see -----
# docs/concept/carrion.md, docs/concept/flies.md, CarrionForageBehavior.
# effective_distance) -----------------------------------------------------

## A fly-blown carcass is a farther but real, visible signal a decomposer
## should be measurably more likely to path toward than a nearer, fresh one
## -- the same real "scavengers cue off circling flies" grounding
## effective_distance documents. Not rotten: _nearest_carrion has no
## rotten-ness gate of its own, only take_bite does, so a fresh carcass is a
## perfectly valid (if less attractive) target here.
func test_prefers_a_fly_blown_carcass_over_a_closer_fresh_one():
	var fresh := Carcass.new()
	fresh.species = "boar"
	fresh.position = marker.position + Vector2(20, 0)  # the nearer of the two
	add_child_autofree(fresh)

	var blown := Carcass.new()
	blown.species = "boar"
	blown.position = marker.position + Vector2(26, 0)  # farther, but fly-blown
	add_child_autofree(blown)
	blown._process(Carcass.FLY_ATTRACTION_DELAY_SECONDS + 1.0)  # a founder fly finds it
	assert_gt(blown.fly_count(), 0, "sanity: flies should have found the farther carcass by now")
	assert_eq(fresh.fly_count(), 0, "sanity: the closer carcass has no flies yet")
	assert_lt(
		marker.position.distance_to(fresh.position), marker.position.distance_to(blown.position),
		"sanity: raw distance alone should favour the closer, fresh carcass"
	)

	marker._process(CarrionForageBehavior.REHUNT_SECONDS)  # become willing to commit
	var target := marker._nearest_carrion()

	assert_eq(target, blown, "a fly-blown carcass should out-compete a nearer, fresh one")


## Once its target is gone, the decomposer goes back to seeking rather than
## getting stuck waiting on a target that no longer exists.
func test_returns_to_seeking_once_its_target_is_consumed():
	carcass = _rotten_carcass_at(Vector2(101, 100))
	carcass._decompose_health = 0.001  # one bite finishes it
	for i in 200:
		marker._process(0.5)
		if carcass.is_queued_for_deletion():
			break
	marker._process(1.0)
	assert_eq(marker._behavior.phase, CarrionForageBehavior.Phase.SEEKING)


# -- disease: anthrax-like carry vector (see docs/concept/disease.md) ---------
#
# Real blowflies/carrion beetles feeding on an infected carcass mechanically
# carry spores onward -- DecomposerMarker is that same insect (see
# carrion.md), so it's the carry vector rather than a new bespoke one.

func test_a_decomposer_picks_up_disease_feeding_on_a_contaminated_carcass():
	carcass = _rotten_carcass_at(Vector2(102, 100))
	carcass.region_tier = RegionDifficulty.Tier.HARD  # clamps the carry roll to certain
	carcass.contaminated = true
	for i in 200:
		marker._process(0.5)
		if marker.carrying_disease:
			break
	assert_true(marker.carrying_disease)


func test_a_decomposer_does_not_pick_up_disease_from_a_clean_carcass():
	carcass = _rotten_carcass_at(Vector2(102, 100))
	carcass.region_tier = RegionDifficulty.Tier.HARD
	# _rotten_carcass_at's own _process already auto-rolled contamination
	# (see Carcass._roll_contamination) -- forced clean here so THIS test
	# isolates the carry logic from that separate, already-covered roll.
	carcass.contaminated = false
	for i in 50:
		marker._process(0.5)
	assert_false(marker.carrying_disease)


func test_a_carrying_decomposer_contaminates_the_next_clean_carcass_it_feeds_on():
	marker.carrying_disease = true
	carcass = _rotten_carcass_at(Vector2(102, 100))
	carcass.contaminated = false  # force clean -- see the sibling test's comment above
	for i in 200:
		marker._process(0.5)
		if carcass.contaminated:
			break
	assert_true(carcass.contaminated)


# -- LOD throttle: expensive carrion scanning is distance-scaled (see
# CreatureMarker/AmbientFlyerMarker's own _lod_step/SimulationLod), not run
# unconditionally every single frame regardless of whether anyone is close
# enough to see it. -----------------------------------------------------------

func test_far_from_the_player_does_not_rescan_carrion_on_every_process_call():
	# Reach the moment a fresh decomposer is willing to commit to a target
	# (see CarrionForageBehavior.REHUNT_SECONDS) with no player registered
	# yet, so this priming step runs at full, un-throttled rate and isn't
	# itself part of what this test is checking.
	marker._process(CarrionForageBehavior.REHUNT_SECONDS)
	assert_true(marker._behavior.can_commit(), "sanity: primed and willing to commit")

	# A player far enough away that SimulationLod parks this marker at its
	# slowest update rate (see FULL_RATE_RADIUS_PX/FALLOFF_PX/
	# MAX_INTERVAL_SECONDS) -- comfortably past where the falloff saturates.
	var player := Node2D.new()
	add_child_autofree(player)
	player.add_to_group("player")
	player.position = marker.position + Vector2(
		SimulationLod.FULL_RATE_RADIUS_PX + SimulationLod.FALLOFF_PX + 1.0, 0
	)

	# A rotten carcass placed right beside the decomposer -- if _step_seeking
	# (and so _nearest_carrion) ran on every one of the frames below, an
	# un-throttled decomposer would find and commit to it almost immediately.
	carcass = _rotten_carcass_at(marker.position + Vector2(5, 0))

	# Many tiny steps, each far under the ~0.5s LOD interval this far from
	# the player.
	for i in 20:
		marker._process(0.01)

	assert_eq(
		marker._behavior.phase, CarrionForageBehavior.Phase.SEEKING,
		"far from the player, a decomposer should not re-scan for carrion on every _process call -- it should still be waiting out its LOD interval"
	)
