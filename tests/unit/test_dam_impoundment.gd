extends GutTest

## A stone check dam's real hydraulics -- see dam_impoundment.gd and
## docs/concept/rivers.md's "Dams" section.

const DamImpoundment = preload("res://src/world/dam_impoundment.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")


# -- crest height -----------------------------------------------------------

func test_a_hand_built_check_dam_is_a_realistic_height():
	# Real hand-stacked loose-stone check dams are waist-to-chest high, not
	# engineering structures. Anything metres tall would need real
	# engineering the player is not doing.
	assert_between(DamImpoundment.CREST_HEIGHT_M, 0.3, 2.0)


# -- pool surface -----------------------------------------------------------
#
# Steady state: the pool rises until what spills over the crest equals what
# the river brings in. That head is closed-form from the weir equation, so
# the pool needs no stored fill state.

func test_the_pool_surface_sits_above_the_crest_by_the_equilibrium_head():
	var bed := 300.0
	var surface := DamImpoundment.pool_surface_elevation_m(bed, 5.0, 12.0)
	var head := OpenChannelFlow.equilibrium_weir_head_m(5.0, 12.0)
	assert_almost_eq(surface, bed + DamImpoundment.CREST_HEIGHT_M + head, 0.0001)


func test_a_bigger_river_needs_more_head_to_pass_over_the_same_crest():
	var small := DamImpoundment.pool_surface_elevation_m(300.0, 5.0, 12.0)
	var big := DamImpoundment.pool_surface_elevation_m(300.0, 500.0, 12.0)
	assert_gt(big, small, "more discharge must stand deeper over the crest")


func test_a_wider_crest_needs_less_head_for_the_same_river():
	var narrow := DamImpoundment.pool_surface_elevation_m(300.0, 50.0, 5.0)
	var wide := DamImpoundment.pool_surface_elevation_m(300.0, 50.0, 50.0)
	assert_lt(wide, narrow, "a wider crest spills the same flow at less head")


# -- pooled depth -----------------------------------------------------------

func test_a_cell_below_the_pool_surface_is_flooded_to_that_surface():
	assert_almost_eq(DamImpoundment.pooled_depth_m(300.0, 302.5), 2.5, 0.0001)


func test_a_cell_above_the_pool_surface_is_not_flooded_at_all():
	assert_eq(DamImpoundment.pooled_depth_m(305.0, 302.5), 0.0)


func test_a_cell_exactly_at_the_pool_surface_has_no_depth():
	assert_eq(DamImpoundment.pooled_depth_m(302.5, 302.5), 0.0)


## The dam raises water, never lowers it -- a dammed cell must be at least
## as deep as the natural river was there.
func test_impounded_depth_never_falls_below_the_natural_depth():
	var natural := 0.4
	# A pool surface BELOW what the natural river already stood at.
	var shallow_pool := DamImpoundment.impounded_depth_m(natural, 300.0, 300.1)
	assert_gte(shallow_pool, natural, "a dam must never make a river shallower")


func test_impounded_depth_uses_the_pool_when_it_is_deeper_than_the_river():
	assert_almost_eq(DamImpoundment.impounded_depth_m(0.4, 300.0, 302.0), 2.0, 0.0001)


# -- backwater extent -------------------------------------------------------
#
# How far upstream the pooling reaches. Bounded on purpose: a real
# impoundment ends where the natural bed climbs above the pool surface, and
# the search must also stay affordable on a chunk-streamed world.

func test_the_backwater_reach_is_bounded():
	assert_gt(DamImpoundment.MAX_BACKWATER_TILES, 0)
	assert_lte(
		DamImpoundment.MAX_BACKWATER_TILES, 64,
		"an unbounded upstream walk is exactly what this world cannot afford"
	)


# -- structural failure -----------------------------------------------------
#
# Real dry-stacked stone fails by SLIDING when the water's push beats the
# friction holding the stone down. Both sides scale with the dam's own
# width, so width cancels and the limit is a real depth.

func test_a_shallow_pool_does_not_burst_the_dam():
	assert_false(DamImpoundment.exceeds_structural_limit(0.2))


func test_a_deep_enough_pool_bursts_the_dam():
	assert_true(DamImpoundment.exceeds_structural_limit(50.0))


## The failure depth must be a real consequence of the stone's own weight
## and friction, not an invented threshold -- and it must land somewhere a
## hand-stacked dam plausibly gives way.
func test_the_failure_depth_is_derived_and_physically_plausible():
	var limit := DamImpoundment.failure_depth_m()
	assert_between(
		limit, 0.5, 6.0,
		"a dry-stacked stone dam failing at %f m is not plausible" % limit
	)


## Force goes as depth squared while resistance is fixed, so failure is a
## sharp threshold: just under holds, just over does not.
func test_failure_is_a_real_threshold_not_a_gradient():
	var limit := DamImpoundment.failure_depth_m()
	assert_false(DamImpoundment.exceeds_structural_limit(limit * 0.95))
	assert_true(DamImpoundment.exceeds_structural_limit(limit * 1.05))


# -- impounded volume -------------------------------------------------------

func test_no_volume_without_depth():
	assert_eq(DamImpoundment.impounded_volume_m3(0.0, 100.0), 0.0)


func test_volume_is_depth_times_area():
	assert_almost_eq(DamImpoundment.impounded_volume_m3(2.0, 500.0), 1000.0, 0.0001)


# -- backwater falloff ------------------------------------------------------
#
# The pool is deepest at the dam face and thins upstream. Its EXTENT is a
# deliberate real-scale compression (see MAX_BACKWATER_TILES' own doc: a
# real check dam's pool is a fraction of one 1 km tile long, and on the
# Dreisam's real 4% gradient a literal pool could never reach even the next
# cell); its DEPTH stays real, from the weir equation.

func test_the_pool_is_at_full_depth_against_the_dam_face():
	assert_almost_eq(DamImpoundment.backwater_falloff(0.0), 1.0, 0.0001)


func test_the_pool_has_thinned_to_nothing_at_its_bound():
	assert_eq(DamImpoundment.backwater_falloff(float(DamImpoundment.MAX_BACKWATER_TILES)), 0.0)


func test_nothing_is_ponded_beyond_the_bound():
	assert_eq(DamImpoundment.backwater_falloff(DamImpoundment.MAX_BACKWATER_TILES + 1.0), 0.0)


func test_the_pool_thins_monotonically_upstream():
	var previous := 2.0
	for step in 10:
		var here := DamImpoundment.backwater_falloff(float(step) * 0.5)
		assert_lte(here, previous, "the pool must not deepen going upstream")
		previous = here


func test_falloff_never_leaves_the_unit_range():
	for tiles in [-1.0, 0.0, 1.5, 4.0, 100.0]:
		assert_between(DamImpoundment.backwater_falloff(tiles), 0.0, 1.0)


# -- boulders as flow obstacles ----------------------------------------------
#
# "boulders ... should properly affect path and flow of the water" -- the
# pure geometry half: how a boulder pushes the water's across-field around
# itself. The painter bakes these shifts per tile; the shader then draws
# the deflected waterline and current lines with no changes of its own.

## The push points AWAY from the boulder and fades with distance -- nothing
## beyond the radius, full strength against a touching neighbour.
func test_the_obstacle_push_repels_and_fades():
	var toward_bank := DamImpoundment.obstacle_across_shift(0.6, 0.2, 1.0)
	assert_gt(toward_bank, 0.0, "a tile outside the boulder must be pushed further out")
	var toward_centre := DamImpoundment.obstacle_across_shift(-0.1, 0.2, 1.0)
	assert_lt(toward_centre, 0.0, "a tile inside the boulder must be pushed further in")
	assert_almost_eq(
		DamImpoundment.obstacle_across_shift(0.6, 0.2, DamImpoundment.OBSTACLE_PUSH_RADIUS_TILES + 0.1),
		0.0, 0.0001
	)
	assert_gt(
		absf(DamImpoundment.obstacle_across_shift(0.6, 0.2, 0.5)),
		absf(DamImpoundment.obstacle_across_shift(0.6, 0.2, 2.0))
	)


## The boulder's own tile rails past the waterline -- a dry eyot the water
## visibly parts around -- keeping its bank side, and landing beyond the
## waterline's feather so the rock never renders half-wet.
func test_the_boulder_tile_becomes_a_dry_eyot():
	var RiverFlowShader = load("res://src/rendering/river_flow_shader.gd")
	assert_gt(
		DamImpoundment.eyot_across(0.3), 1.0 + RiverFlowShader.BANK_FEATHER
	)
	assert_lt(
		DamImpoundment.eyot_across(-0.3), -1.0 - RiverFlowShader.BANK_FEATHER
	)
	# Dead centre still picks a side rather than staying wet.
	assert_gte(absf(DamImpoundment.eyot_across(0.0)), 1.0 + RiverFlowShader.BANK_FEATHER)
