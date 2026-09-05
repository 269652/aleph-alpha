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
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

## Minimal duck-typed `_world` (see DecomposerMarker.setup) wrapping a real
## LeafLitterField -- mirrors test_creature_marker.gd's own ForageWorld
## stub-around-a-real-model shape, rather than reinventing a fake in-memory
## leaf list.
class LeafLitterWorld:
	extends RefCounted
	var field := LeafLitterField.new()

	func nearest_leaf_litter_near(pixel_position: Vector2, radius_px: float) -> Dictionary:
		return field.nearest_leaf_near(pixel_position, radius_px)

	func consume_leaf_litter_at(pixel_position: Vector2) -> bool:
		return field.consume_leaf_at(pixel_position)

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


## Bug report: "gigantic ant blobs". ProceduralDecomposerSprite's art canvas
## (SIZE := 12) is authored at ArtResolution.DETAIL_MULTIPLIER, the same
## oversample-then-scale-down convention every other sprite generator in this
## codebase follows (trees, creatures, fish, items -- see art_resolution.gd)
## -- but unlike every one of those, DecomposerMarker never actually applied
## ArtResolution.SPRITE_SCALE to the sprite it built, so it rendered at its
## raw 12x12 art-canvas size instead of its intended tiny insect world size.
## Direct precedent for this exact failure mode: ProceduralItemSprite's own
## doc comment records a fallen cherry once being "as wide as the tile it lay
## on" for the identical missing-scale reason.
func test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_raw_art_canvas():
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * ArtResolution.SPRITE_SCALE)


## Bug report: "gigantic ant blobs... but they don't move". _step_seeking
## only ever pulled a decomposer BACK toward home once it had drifted past
## WANDER_RADIUS_PX -- nothing ever sent it wandering away from home in the
## first place, so an idle decomposer with no carrion/food nearby sat on
## exactly one frozen position forever. test_stays_near_home_while_nothing_
## to_eat above still passes either way (frozen trivially satisfies "stays
## within 2x radius"), which is why this went unnoticed -- this test asserts
## actual movement instead.
func test_wanders_when_idle_instead_of_sitting_frozen():
	var positions_seen := {}
	for i in 30:
		marker._process(0.5)
		positions_seen[marker.position] = true
	assert_gt(
		positions_seen.size(), 1,
		"an idle decomposer should actually wander around home, not sit on one frozen position forever"
	)


## The wander-heading interval is DERIVED from this file's own wander
## geometry (see its doc comment), not eyeballed -- pinned here so that
## relationship stays visible and intentional rather than silently drifting
## if WANDER_RADIUS_PX/WALK_SPEED/WANDER_SPEED_FRACTION ever change.
func test_wander_direction_change_interval_is_derived_not_eyeballed():
	assert_almost_eq(
		DecomposerMarker.WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS,
		DecomposerMarker.WANDER_RADIUS_PX / (DecomposerMarker.WALK_SPEED * DecomposerMarker.WANDER_SPEED_FRACTION),
		0.001
	)


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
## effective_distance documents. Not rotten: _nearest_food has no
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
	var target := marker._nearest_food()

	assert_eq(target, blown, "a fly-blown carcass should out-compete a nearer, fresh one")


## A target closer than one whole approach step (WALK_SPEED * delta) but
## still outside ARRIVE_DISTANCE_PX used to make an unclamped step overshoot
## straight past it, then overshoot back on the very next step -- forever,
## a decomposer that commits to a real, reachable target and then orbits it
## without ever arriving (see _step_approaching's own doc comment). Only
## exposed once ambient wander (see test_wanders_when_idle_instead_of_
## sitting_frozen) gave APPROACHING a real gap to close instead of always
## starting already inside ARRIVE_DISTANCE_PX. Drives APPROACHING directly
## (bypassing SEEKING/commit) so this is deterministic regardless of
## wander's own randomness.
func test_approaching_a_close_target_does_not_overshoot_and_orbit_forever():
	carcass = _rotten_carcass_at(marker.position + Vector2(6.0, 0.0))
	marker._target = carcass
	marker._behavior.phase = CarrionForageBehavior.Phase.APPROACHING
	for i in 20:
		marker._process(0.5)
		if marker._behavior.phase == CarrionForageBehavior.Phase.FEEDING:
			break
	assert_eq(
		marker._behavior.phase, CarrionForageBehavior.Phase.FEEDING,
		"a target closer than one approach step should still be reached, not orbited forever"
	)


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

# -- fallen fruit/nuts: ants are opportunistic, not carrion specialists (see
# docs/concept/carrion.md, docs/concept/flora.md, AntColony's own already-
# real but invisible windfall foraging) -- a decomposer finding a nearby
# fallen fruit/nut should eat it exactly the way it eats carrion, just in
# one visit instead of a health pool whittled down over several bites: a
# dropped cherry is not a boar carcass. ---------------------------------

func _fallen_fruit_at(at: Vector2, species_id: String = "cherry") -> DroppedItem:
	var fruit := DroppedItem.new()
	fruit.item_stack = ItemStack.new(Item.new(species_id, species_id.capitalize(), "food", 20), 1)
	fruit.position = at
	add_child_autofree(fruit)
	return fruit


func test_forages_and_eats_nearby_fallen_fruit_when_theres_no_carrion():
	var fruit := _fallen_fruit_at(Vector2(105, 100))
	for i in 200:
		marker._process(0.5)
		if fruit.is_queued_for_deletion():
			break
	assert_true(fruit.is_queued_for_deletion())


## Closes the loop docs/concept/leaf_litter.md promises: a fallen leaf is no
## longer a real DroppedItem node (see LeafLitterField/LeafLitterRenderer) --
## it is chunk-specific plain data, reached through an injected `_world` (see
## DecomposerMarker.setup) exactly the way worms already are for other
## markers. Proven end to end rather than just reasoned about -- the same
## precedent test_forages_and_eats_nearby_fallen_fruit_when_theres_no_
## carrion above already sets for fruit.
func test_forages_and_eats_a_nearby_fallen_leaf():
	var world := LeafLitterWorld.new()
	world.field.add_leaf(Vector2(105, 100), "cherry", "autumn", 0.0)
	marker.setup(world)
	for i in 200:
		marker._process(0.5)
		if world.field.leaves().is_empty():
			break
	assert_true(world.field.leaves().is_empty(), "a decomposer should forage and eat a fallen leaf too")


## Without an injected _world at all (most of this file's own tests, and
## every decomposer that predates this feature), leaf litter is simply never
## found -- the marker keeps foraging carrion/fruit exactly as before, not a
## crash from an assumed-present dependency.
func test_never_looks_for_leaf_litter_without_an_injected_world():
	assert_null(marker._world, "precondition: this marker never had setup() called")
	var found := marker._nearest_food()
	assert_null(found, "no carrion/fruit/leaf exists near this marker at all")


## The filter has to be real (TreeSpecies.IDS), not "any dropped_item" --
## otherwise an ant would wander off eating dropped ore/tools/weapons, which
## is not what "ants forage fallen fruit" means.
func test_ignores_a_dropped_item_that_is_not_food():
	var stone := DroppedItem.new()
	stone.item_stack = ItemStack.new(Item.new("iron_ore", "Iron Ore", "material", 20), 1)
	stone.position = Vector2(105, 100)
	add_child_autofree(stone)
	for i in 200:
		marker._process(0.5)
	assert_false(
		stone.is_queued_for_deletion(),
		"a decomposer should not eat non-food ground items like ore"
	)


## Bug report ("game dropped from 60fps to 4-5fps"): LiftableStone
## deliberately shares DroppedItem.GROUP_NAME (see its own doc comment --
## "It joins the group DroppedItem uses... so the existing pickup sweep...
## collects it with no special case of its own") so the player's pickup
## sweep can find it, but it is NOT a DroppedItem and has no `item_stack`
## at all. _nearest_food assumed every member of that group was a real
## DroppedItem and accessed `.item_stack` unconditionally -- a script
## error on every single stone within SEARCH_RADIUS_PX, every SEEKING
## scan, for every ant near any of this game's very common loose stones.
## Repeated GDScript errors are not free (string formatting + backtrace
## capture + console I/O per hit) -- multiplied across many ants near many
## stones, every relevant frame, this is a real, measured-live cause of
## the reported collapse, not a cosmetic log nuisance.
func test_ignores_a_liftable_stone_sharing_the_dropped_item_group():
	var stone := LiftableStone.new()
	stone.position = Vector2(105, 100)
	add_child_autofree(stone)
	for i in 200:
		marker._process(0.5)
	# The real assertion is simply that this loop completed without the
	# engine ever raising "Invalid access to property or key 'item_stack'
	# on a base object of type 'Node2D (liftable_stone.gd)'" -- GUT fails
	# a test outright on an unhandled script error during its run, so
	# reaching this line at all is the fix. Kept as an explicit assert
	# rather than an empty test so the intent reads without the comment.
	assert_false(stone.is_queued_for_deletion(), "a decomposer must never treat a stone as edible")


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
	# (and so _nearest_food) ran on every one of the frames below, an
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
