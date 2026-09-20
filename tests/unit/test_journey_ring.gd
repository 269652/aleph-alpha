extends GutTest

## The player-facing half of RegionDifficulty (see
## docs/concept/journey_rings.md): named rings, what is new and lethal in
## each, and what each one expects a traveller to be carrying.
##
## The whole point of this module is that it must NEVER be a second
## opinion about where the danger starts, so the load-bearing test here is
## the sweep that compares every ring's tier against RegionDifficulty's own
## answer at the same distance -- and the reflection test that makes it
## impossible for a later session to turn a pressure into a fence.

const JourneyRing = preload("res://src/gameplay/journey_ring.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Lithology = preload("res://src/world/lithology.gd")

## Far enough out to cover both RegionDifficulty radii and a long stretch of
## unbounded HARD beyond them -- 400 chunks is ~12 800 km, further than any
## great-circle walk on this planet.
const SWEEP_CHUNKS := 400

var region_difficulty: RegionDifficulty


func before_each():
	region_difficulty = RegionDifficulty.new()


# -- the table -------------------------------------------------------------


func test_the_table_runs_outward_from_zero_with_no_gap_and_no_overlap():
	var rings: Array = JourneyRing.rings()
	assert_gt(rings.size(), 1, "a journey of one ring is not a journey")
	assert_eq(rings[0]["inner_chunks"], 0, "the first ring must start at spawn")
	for i in range(rings.size() - 1):
		assert_eq(
			rings[i + 1]["inner_chunks"],
			rings[i]["outer_chunks"] + 1,
			"gap or overlap between %s and %s" % [rings[i]["id"], rings[i + 1]["id"]]
		)
	assert_eq(
		rings[rings.size() - 1]["outer_chunks"],
		JourneyRing.UNBOUNDED,
		"the outermost ring must have no outer edge -- Earth does not stop"
	)


func test_every_ring_has_an_id_a_name_and_a_line_about_what_is_lethal():
	var seen_ids: Array = []
	for ring in JourneyRing.rings():
		assert_false(seen_ids.has(ring["id"]), "duplicate ring id %s" % ring["id"])
		seen_ids.append(ring["id"])
		assert_gt((ring["id"] as String).length(), 0)
		assert_gt((ring["name"] as String).length(), 0)
		assert_gt(
			(ring["description"] as String).length(),
			20,
			"%s has no line telling the player what changed" % ring["id"]
		)


func test_every_distance_lands_in_exactly_one_ring():
	for distance in range(0, SWEEP_CHUNKS + 1):
		var matches: int = 0
		for ring in JourneyRing.rings():
			var outer: int = ring["outer_chunks"]
			var inside: bool = (
				distance >= ring["inner_chunks"]
				and (outer == JourneyRing.UNBOUNDED or distance <= outer)
			)
			if inside:
				matches += 1
				assert_eq(
					JourneyRing.ring_at(distance)["id"],
					ring["id"],
					"ring_at(%d) disagrees with the table" % distance
				)
		assert_eq(matches, 1, "distance %d matched %d rings" % [distance, matches])


func test_ring_at_beyond_the_table_is_still_the_outermost_ring():
	var rings: Array = JourneyRing.rings()
	var outermost: Dictionary = rings[rings.size() - 1]
	assert_eq(JourneyRing.ring_at(100000)["id"], outermost["id"])


# -- it derives, it never contradicts --------------------------------------


func test_ring_tier_equals_region_difficultys_tier_at_every_distance():
	for distance in range(0, SWEEP_CHUNKS + 1):
		var mine: int = JourneyRing.tier_at_distance(distance)
		var theirs: int = region_difficulty.tier_at(Vector2i(distance, 0), Vector2i.ZERO)
		assert_eq(
			mine,
			theirs,
			"at %d chunks the rings say tier %d and RegionDifficulty says %d"
			% [distance, mine, theirs]
		)


func test_ring_tier_agrees_over_real_chunk_coordinates_in_every_direction():
	# Not just the +x axis: negative, diagonal and off-origin spawns, fed
	# through this module's own distance_chunks, must reach RegionDifficulty's
	# own verdict for the same pair of coordinates.
	var spawn := Vector2i(-317, 2044)
	for dx in range(-70, 71, 7):
		for dy in range(-70, 71, 7):
			var coord := spawn + Vector2i(dx, dy)
			var distance: int = JourneyRing.distance_chunks(coord, spawn)
			assert_eq(
				JourneyRing.tier_at_distance(distance),
				region_difficulty.tier_at(coord, spawn),
				"disagreement at offset (%d, %d)" % [dx, dy]
			)


func test_each_tier_is_covered_by_at_least_one_ring():
	# Guards the sweep above against a degenerate table that agreed with
	# RegionDifficulty only because it never left one tier.
	var tiers_used: Array = []
	for ring in JourneyRing.rings():
		if not tiers_used.has(ring["tier"]):
			tiers_used.append(ring["tier"])
	assert_true(tiers_used.has(RegionDifficulty.Tier.EASY), "no ring is EASY")
	assert_true(tiers_used.has(RegionDifficulty.Tier.MEDIUM), "no ring is MEDIUM")
	assert_true(tiers_used.has(RegionDifficulty.Tier.HARD), "no ring is HARD")
	assert_gt(
		JourneyRing.rings().size(),
		tiers_used.size(),
		"the rings must SUBDIVIDE the tiers, not merely rename them"
	)


# -- the boundaries are somebody's constant --------------------------------


func test_the_easy_band_ends_on_region_difficultys_own_easy_radius():
	var last_easy: Dictionary = JourneyRing.ring_at(RegionDifficulty.EASY_RADIUS_CHUNKS)
	assert_eq(
		last_easy["outer_chunks"],
		RegionDifficulty.EASY_RADIUS_CHUNKS,
		"a ring boundary that should BE the easy radius has drifted off it"
	)
	assert_eq(last_easy["tier"], RegionDifficulty.Tier.EASY)


func test_the_medium_band_ends_on_region_difficultys_own_medium_radius():
	var last_medium: Dictionary = JourneyRing.ring_at(RegionDifficulty.MEDIUM_RADIUS_CHUNKS)
	assert_eq(
		last_medium["outer_chunks"],
		RegionDifficulty.MEDIUM_RADIUS_CHUNKS,
		"a ring boundary that should BE the medium radius has drifted off it"
	)
	assert_eq(last_medium["tier"], RegionDifficulty.Tier.MEDIUM)


func test_hearth_radius_is_the_named_share_of_the_easy_radius():
	assert_eq(
		JourneyRing.HEARTH_RADIUS_CHUNKS,
		RegionDifficulty.EASY_RADIUS_CHUNKS / JourneyRing.HEARTH_DIVISOR_OF_EASY
	)
	# A share that rounded to 0 or to the whole easy band would silently
	# delete one of the two easy rings.
	assert_gt(JourneyRing.HEARTH_RADIUS_CHUNKS, 0)
	assert_lt(JourneyRing.HEARTH_RADIUS_CHUNKS, RegionDifficulty.EASY_RADIUS_CHUNKS)


func test_march_radius_is_the_geometric_mean_of_the_two_region_radii():
	# The medium band is where distance starts doubling rather than adding,
	# so the honest cut is the point the same FACTOR from each end.
	assert_eq(
		JourneyRing.MARCH_RADIUS_CHUNKS * JourneyRing.MARCH_RADIUS_CHUNKS,
		RegionDifficulty.EASY_RADIUS_CHUNKS * RegionDifficulty.MEDIUM_RADIUS_CHUNKS,
		"MARCH_RADIUS_CHUNKS is no longer the geometric mean of the two radii"
	)
	assert_gt(JourneyRing.MARCH_RADIUS_CHUNKS, RegionDifficulty.EASY_RADIUS_CHUNKS)
	assert_lt(JourneyRing.MARCH_RADIUS_CHUNKS, RegionDifficulty.MEDIUM_RADIUS_CHUNKS)


# -- demands accumulate ----------------------------------------------------


func test_demands_are_cumulative_pairwise_over_the_whole_table():
	var rings: Array = JourneyRing.rings()
	for near in range(rings.size()):
		for far in range(near + 1, rings.size()):
			for demand in rings[near]["demands"]:
				assert_true(
					(rings[far]["demands"] as Array).has(demand),
					(
						"%s demands %s but the further %s does not"
						% [rings[near]["id"], demand, rings[far]["id"]]
					)
				)


func test_each_ring_outward_adds_at_least_one_new_demand():
	# Cumulative alone is satisfied by five identical lists; the packing
	# list has to actually GROW or the rings say nothing new.
	var rings: Array = JourneyRing.rings()
	for i in range(rings.size() - 1):
		assert_gt(
			(rings[i + 1]["demands"] as Array).size(),
			(rings[i]["demands"] as Array).size(),
			"%s asks nothing %s did not" % [rings[i + 1]["id"], rings[i]["id"]]
		)


func test_the_innermost_ring_demands_nothing():
	assert_eq(
		(JourneyRing.rings()[0]["demands"] as Array).size(),
		0,
		"a player who has not left the hearth is not yet being asked for anything"
	)


func test_demands_at_a_distance_are_that_distances_own_rings_demands():
	for distance in [0, 3, 9, 20, 45, 200]:
		assert_eq(JourneyRing.demands_at(distance), JourneyRing.ring_at(distance)["demands"])


func test_no_demand_is_named_twice_within_a_ring():
	for ring in JourneyRing.rings():
		var seen: Array = []
		for demand in ring["demands"]:
			assert_false(seen.has(demand), "%s lists %s twice" % [ring["id"], demand])
			seen.append(demand)


# -- no wall exists --------------------------------------------------------


func test_nothing_here_can_refuse_entry():
	# The world's order is enforced by danger and cold, never by an
	# invisible fence (docs/concept/journey_rings.md, pillar 3).
	var forbidden: Array = [
		"can_enter",
		"is_blocked",
		"may_pass",
		"is_allowed",
		"can_pass",
		"blocks_entry",
		"is_locked",
		"requires_level",
		"gate_at",
	]
	var declared: Array = []
	for method in JourneyRing.new().get_script().get_script_method_list():
		declared.append(method["name"])

	# Self-check: if reflection ever stops reporting this script's own
	# methods, every assertion below would pass vacuously.
	assert_true(
		declared.has("ring_at"),
		"reflection returned no known method -- the guard below would be vacuous"
	)

	for forbidden_name in forbidden:
		assert_false(
			declared.has(forbidden_name),
			(
				"JourneyRing.%s() exists -- this module must never be able to say no"
				% forbidden_name
			)
		)


# -- crossing is an event --------------------------------------------------


func test_a_step_within_a_ring_is_not_a_crossing():
	assert_true(JourneyRing.crossing_between(1, 2).is_empty(), "1 -> 2 is inside one ring")
	assert_true(JourneyRing.crossing_between(20, 25).is_empty(), "20 -> 25 is inside one ring")
	assert_true(
		JourneyRing.crossing_between(300, 301).is_empty(), "300 -> 301 is inside one ring"
	)
	assert_true(JourneyRing.crossing_between(7, 7).is_empty(), "standing still is not a crossing")


func test_a_step_outward_across_a_boundary_reports_the_ring_entered():
	var entered: Dictionary = JourneyRing.crossing_between(
		JourneyRing.HEARTH_RADIUS_CHUNKS, JourneyRing.HEARTH_RADIUS_CHUNKS + 1
	)
	assert_eq(entered["id"], JourneyRing.ring_at(JourneyRing.HEARTH_RADIUS_CHUNKS + 1)["id"])


func test_a_step_inward_across_a_boundary_also_reports_the_ring_entered():
	# Coming home is news too; a caller that wants only outward crossings
	# can compare the ring bounds itself.
	var entered: Dictionary = JourneyRing.crossing_between(
		JourneyRing.HEARTH_RADIUS_CHUNKS + 1, JourneyRing.HEARTH_RADIUS_CHUNKS
	)
	assert_eq(entered["id"], JourneyRing.ring_at(JourneyRing.HEARTH_RADIUS_CHUNKS)["id"])


func test_jumping_several_rings_reports_the_ring_landed_in():
	var entered: Dictionary = JourneyRing.crossing_between(0, SWEEP_CHUNKS)
	assert_eq(entered["id"], JourneyRing.ring_at(SWEEP_CHUNKS)["id"])


func test_a_walk_outward_raises_each_ring_exactly_once_and_in_order():
	var raised: Array = []
	for distance in range(1, SWEEP_CHUNKS + 1):
		var crossing: Dictionary = JourneyRing.crossing_between(distance - 1, distance)
		if not crossing.is_empty():
			raised.append(crossing["id"])

	var expected: Array = []
	for i in range(1, JourneyRing.rings().size()):
		expected.append(JourneyRing.rings()[i]["id"])
	assert_eq(raised, expected, "a walk to the edge of the world must card each ring once")


# -- the world's own units -------------------------------------------------


func test_distance_chunks_is_chebyshev_and_symmetric():
	for dx in range(-9, 10):
		for dy in range(-9, 10):
			var a := Vector2i(41, -7)
			var b := a + Vector2i(dx, dy)
			var expected: int = maxi(absi(dx), absi(dy))
			assert_eq(JourneyRing.distance_chunks(a, b), expected)
			assert_eq(JourneyRing.distance_chunks(b, a), expected, "distance is not symmetric")


func test_chunk_size_agrees_with_the_chunk_manager():
	# Restated rather than preloaded, so a small pure module does not pull
	# in the whole streaming layer -- the agreement is pinned here instead
	# (the idiom BuilderMarker and Lithology already use).
	assert_eq(JourneyRing.CHUNK_SIZE_TILES, EarthChunkManager.CHUNK_SIZE)


func test_km_per_tile_agrees_with_the_world_scale():
	assert_almost_eq(JourneyRing.KM_PER_TILE, Lithology.KM_PER_TILE, 0.0001)


func test_metres_per_chunk_is_a_chunk_of_tiles_at_the_world_scale():
	assert_almost_eq(
		JourneyRing.METRES_PER_CHUNK,
		JourneyRing.CHUNK_SIZE_TILES * JourneyRing.KM_PER_TILE * 1000.0,
		0.0001
	)


func test_metres_from_spawn_is_the_distance_in_the_players_own_units():
	assert_almost_eq(JourneyRing.metres_from_spawn(0), 0.0, 0.0001)
	assert_almost_eq(
		JourneyRing.metres_from_spawn(1), JourneyRing.METRES_PER_CHUNK, 0.0001
	)
	assert_almost_eq(
		JourneyRing.metres_from_spawn(15), 15.0 * JourneyRing.METRES_PER_CHUNK, 0.0001
	)


func test_metres_from_spawn_grows_with_every_ring_boundary():
	var previous: float = -1.0
	for ring in JourneyRing.rings():
		var metres: float = JourneyRing.metres_from_spawn(ring["inner_chunks"])
		assert_gt(metres, previous, "%s is not further out than the ring inside it" % ring["id"])
		previous = metres


func test_every_demand_in_the_table_is_a_declared_constant_not_a_bare_string():
	# The repo rule is that tuned values are named constants, and a demand
	# id is one: a raw "warmth " typed into one ring would read as a second,
	# different demand and quietly break the cumulative chain.
	var declared_demands: Array = [
		JourneyRing.DEMAND_PROVISIONS,
		JourneyRing.DEMAND_WEAPON,
		JourneyRing.DEMAND_WARMTH,
		JourneyRing.DEMAND_LIGHT,
		JourneyRing.DEMAND_ANSWER_TO_VENOM,
	]
	var used: Array = []
	for ring in JourneyRing.rings():
		for demand in ring["demands"]:
			assert_true(
				declared_demands.has(demand),
				"%s demands %s, which is not one of the module's own constants"
				% [ring["id"], demand]
			)
			if not used.has(demand):
				used.append(demand)
	assert_eq(
		used.size(),
		declared_demands.size(),
		"a declared demand constant is never asked for by any ring"
	)


func test_crossing_between_is_exactly_a_change_of_ring_for_every_pair():
	# Exhaustive over every pair in the bounded part of the table: a
	# crossing is reported if and only if the ring index changed, and it is
	# always the ring landed in. Catches an off-by-one in ring_index_at
	# that the single-boundary cases above could step over.
	var span: int = RegionDifficulty.MEDIUM_RADIUS_CHUNKS + 10
	for from_distance in range(0, span + 1):
		for to_distance in range(0, span + 1):
			var crossing: Dictionary = JourneyRing.crossing_between(from_distance, to_distance)
			var changed: bool = (
				JourneyRing.ring_at(from_distance)["id"] != JourneyRing.ring_at(to_distance)["id"]
			)
			if changed:
				assert_eq(
					crossing["id"],
					JourneyRing.ring_at(to_distance)["id"],
					"%d -> %d reported the wrong ring" % [from_distance, to_distance]
				)
			else:
				assert_true(
					crossing.is_empty(),
					"%d -> %d is inside one ring but reported a crossing"
					% [from_distance, to_distance]
				)
