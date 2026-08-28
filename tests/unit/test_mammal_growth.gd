extends GutTest

## MammalGrowth (src/gameplay/mammal_growth.gd): the mammal counterpart to
## LifeCycle's pollinator egg/hatch/juvenile/adult stages, minus the egg and
## hatch stages a live birth never has -- see the module's own doc comment
## for why this is its own module rather than LifeCycle reused wholesale.
##
## Maturation duration is now a per-species-SIZE-TIER function, keyed off
## CreatureInfo.MAX_HEALTH_BY_SPECIES (the same size signal the rest of the
## codebase already trusts for "how big/tough is this species") -- see the
## module's own doc comment for the three tiers and their real-world
## grounding. mouse/deer/bear stand in as one representative per tier
## throughout this file.

const MammalGrowth = preload("res://src/gameplay/mammal_growth.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")

## One representative species per tier (see MammalGrowth's tier doc comment):
## mouse is the roster's smallest (SMALL tier), deer a mid-size herbivore
## (MEDIUM tier), bear the roster's largest (LARGE tier).
const TIER_REPRESENTATIVES := ["mouse", "deer", "bear"]


func test_a_newborn_starts_at_a_real_nonzero_juvenile_fraction():
	for species in TIER_REPRESENTATIVES:
		assert_almost_eq(
			MammalGrowth.size_scale_at(0.0, species), MammalGrowth.NEWBORN_SCALE, 0.0001,
			"newborn fraction for %s" % species
		)
	assert_gt(MammalGrowth.NEWBORN_SCALE, 0.0, "a live birth is not an egg -- never starts at zero size")
	assert_lt(MammalGrowth.NEWBORN_SCALE, 1.0, "still visibly smaller than an adult")


func test_size_scale_increases_monotonically_toward_maturity_for_every_tier():
	for species in TIER_REPRESENTATIVES:
		var mature_seconds := MammalGrowth.mature_seconds_for(species)
		var previous := MammalGrowth.size_scale_at(0.0, species)
		var steps := 20
		for i in range(1, steps + 1):
			var age: float = mature_seconds * float(i) / float(steps)
			var current := MammalGrowth.size_scale_at(age, species)
			assert_gte(current, previous, "%s growth must never shrink a juvenile back down" % species)
			previous = current


func test_size_scale_reaches_full_size_exactly_at_maturity_for_every_tier():
	for species in TIER_REPRESENTATIVES:
		var mature_seconds := MammalGrowth.mature_seconds_for(species)
		assert_almost_eq(
			MammalGrowth.size_scale_at(mature_seconds, species), 1.0, 0.0001,
			"%s should be fully grown exactly at its own maturity" % species
		)


func test_size_scale_stays_at_full_size_after_maturity_for_every_tier():
	for species in TIER_REPRESENTATIVES:
		var mature_seconds := MammalGrowth.mature_seconds_for(species)
		assert_eq(MammalGrowth.size_scale_at(mature_seconds * 5.0, species), 1.0)


func test_is_mature_is_false_before_the_threshold_for_every_tier():
	for species in TIER_REPRESENTATIVES:
		var mature_seconds := MammalGrowth.mature_seconds_for(species)
		assert_false(MammalGrowth.is_mature(mature_seconds - 1.0, species), "%s should not be mature yet" % species)


func test_is_mature_is_true_at_and_after_the_threshold_for_every_tier():
	for species in TIER_REPRESENTATIVES:
		var mature_seconds := MammalGrowth.mature_seconds_for(species)
		assert_true(MammalGrowth.is_mature(mature_seconds, species), "%s should be mature exactly at threshold" % species)
		assert_true(MammalGrowth.is_mature(mature_seconds + 1.0, species), "%s should stay mature after" % species)


## The three tiers must be strictly ordered smallest-species-fastest ->
## largest-species-slowest, pinned directly rather than by eyeballed
## comments (this repo's CLAUDE.md rule for tuned constants) -- a real mouse
## reaches sexual maturity in weeks, a real deer takes over a year, a real
## bear/lion takes several years.
func test_the_three_size_tiers_are_strictly_ordered_small_lt_medium_lt_large():
	var mouse_seconds := MammalGrowth.mature_seconds_for("mouse")
	var deer_seconds := MammalGrowth.mature_seconds_for("deer")
	var bear_seconds := MammalGrowth.mature_seconds_for("bear")
	assert_lt(mouse_seconds, deer_seconds, "a mouse should mature faster than a deer")
	assert_lt(deer_seconds, bear_seconds, "a deer should mature faster than a bear")


## Tier assignment is keyed off CreatureInfo.MAX_HEALTH_BY_SPECIES, not
## picked per-species by eye -- pinned against a couple of boundary
## species so the keying itself is under test, not just the three
## representatives above.
func test_tier_assignment_is_keyed_off_max_health_by_species():
	# squirrel (9.0) sits well under SMALL_TIER_MAX_HEALTH -- same tier as mouse.
	assert_eq(
		MammalGrowth.mature_seconds_for("squirrel"), MammalGrowth.mature_seconds_for("mouse"),
		"squirrel's max_health is small-tier, same as mouse"
	)
	# wolf (29.0) sits in the broad middle band -- same tier as deer/boar/horse.
	assert_eq(
		MammalGrowth.mature_seconds_for("wolf"), MammalGrowth.mature_seconds_for("deer"),
		"wolf's max_health is medium-tier, same as deer"
	)
	# lion (45.0) sits at/above LARGE_TIER_MIN_HEALTH -- same tier as bear.
	assert_eq(
		MammalGrowth.mature_seconds_for("lion"), MammalGrowth.mature_seconds_for("bear"),
		"lion's max_health is large-tier, same as bear"
	)
	assert_true(
		CreatureInfo.MAX_HEALTH_BY_SPECIES["mouse"] < MammalGrowth.SMALL_TIER_MAX_HEALTH,
		"sanity check: mouse's own max_health is actually under the small-tier boundary"
	)
	assert_true(
		CreatureInfo.MAX_HEALTH_BY_SPECIES["bear"] >= MammalGrowth.LARGE_TIER_MIN_HEALTH,
		"sanity check: bear's own max_health is actually at/over the large-tier boundary"
	)


## Real land mammals take far longer to mature than a pollinator's whole
## egg-to-adult life cycle (LifeCycle.MATURE_SECONDS is a pollinator's ENTIRE
## life cycle, ~1 real week) -- pinned as an ordering test rather than an
## eyeballed comment, matching this repo's own convention for tuned
## constants (see e.g. seed_caching.gd/earthworm_patch.gd). Every tier,
## including the fastest-maturing one, must clear this floor.
func test_every_tier_takes_meaningfully_longer_than_a_pollinators_whole_life_cycle():
	for species in TIER_REPRESENTATIVES:
		assert_gt(
			MammalGrowth.mature_seconds_for(species), LifeCycle.MATURE_SECONDS * 4.0,
			"%s maturing should take dramatically longer than an insect's whole life cycle" % species
		)


## An unrecognized/unset species (e.g. a bare test marker with no info yet)
## must not crash -- mirrors CreatureInfo._init's own generic fallback.
func test_an_unknown_species_falls_back_without_crashing():
	assert_gt(MammalGrowth.mature_seconds_for("totally-unknown-species"), 0.0)
	assert_gt(MammalGrowth.size_scale_at(0.0, ""), 0.0)
	assert_false(MammalGrowth.is_mature(0.0, ""))
