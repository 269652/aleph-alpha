extends GutTest

## Where a chunk's flyers are actually PUT, and what species they are (see
## FlyerSpawnLayout / docs/concept/ecosystem_dynamics.md's "Two butterflies
## meeting").
##
## This file exists because of a MEASUREMENT, not a feature request. Courtship
## was fully built and fully wired, and the player still never saw it, because
## a chunk's 2-4 butterflies were scattered over a 32x32-tile (512x512 px)
## square while two of them can only notice each other within
## Courtship.NOTICE_RADIUS_PX. Almost no chunk ever contained a pair that
## could meet at all. The encounter-rate measurement at the bottom of this
## file is the evidence, before and after.

const FlyerSpawnLayout = preload("res://src/rendering/flyer_spawn_layout.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")
const SpiralFlight = preload("res://src/gameplay/spiral_flight.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const SALT := "butterfly_spawn"

## Real rows on this project's Earth (see test_ambient_flyer_renderer.gd,
## which pins the same two conventions): the world is 19980 tiles tall and
## GeoCoordinates.latitude_for_tile maps a row to its latitude.
const GERMANY_ROW := 4162  # 52.50 deg N -- Brandenburg, the reported bug's coordinate
const KANSAS_ROW := 5550  # 40.00 deg N -- open country where two of the pool really overlap

## Two flyers whose HOME points are this far apart can meet only if both
## happen to be at the near edge of their own wander tether at the same
## moment. This is the generous, "could it ever happen" bound.
const CAN_EVER_MEET_PX := (
	Courtship.NOTICE_RADIUS_PX + 2.0 * AmbientFlyerRenderer.BUTTERFLY_RADIUS
)
## Homes this close are within noticing distance of each other with neither
## flyer having to go anywhere -- "they meet routinely" rather than "they
## could in principle".
const MEET_ROUTINELY_PX := Courtship.NOTICE_RADIUS_PX


# -- the scatter, kept for the flyers that really do scatter -----------------

func test_a_scatter_puts_exactly_the_wanted_number_inside_the_chunk():
	var cells := FlyerSpawnLayout.scattered_cells(
		Vector2i(64, GERMANY_ROW), CHUNK_SIZE, CHUNK_SIZE, SALT, 4
	)
	assert_eq(cells.size(), 4)
	var seen := {}
	for cell in cells:
		assert_between(cell.x, 64, 64 + CHUNK_SIZE - 1)
		assert_between(cell.y, GERMANY_ROW, GERMANY_ROW + CHUNK_SIZE - 1)
		seen[cell] = true
	assert_eq(seen.size(), 4, "no two flyers on the same cell")


func test_the_scatter_is_deterministic_for_a_chunk():
	var once := FlyerSpawnLayout.scattered_cells(
		Vector2i(64, GERMANY_ROW), CHUNK_SIZE, CHUNK_SIZE, SALT, 3
	)
	var twice := FlyerSpawnLayout.scattered_cells(
		Vector2i(64, GERMANY_ROW), CHUNK_SIZE, CHUNK_SIZE, SALT, 3
	)
	assert_eq(once, twice)


func test_the_count_is_a_guaranteed_range_never_zero():
	for x in 40:
		var wanted := FlyerSpawnLayout.wanted_count(
			Vector2i(x * CHUNK_SIZE, GERMANY_ROW), SALT, 2, 4, CHUNK_SIZE * CHUNK_SIZE
		)
		assert_between(wanted, 2, 4)


# -- the aggregation, which is what butterflies really do --------------------

## Real butterflies do not spread themselves evenly over a meadow. They
## CONGREGATE -- at a stand of nectar flowers, at a damp patch (mud-puddling
## clubs), at a landmark (hilltopping). A chunk's butterflies belonging to one
## loose aggregation is the biologically honest shape AND the one that fixes
## the encounter geometry at its source.
func test_an_aggregation_keeps_every_member_within_reach_of_every_other():
	var positions := FlyerSpawnLayout.aggregated_positions(
		Vector2i(64, GERMANY_ROW), CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT, 4
	)
	assert_eq(positions.size(), 4)
	for a in positions:
		for b in positions:
			assert_lte(
				a.distance_to(b), MEET_ROUTINELY_PX + 0.001,
				"any two of an aggregation must already be within noticing distance"
			)


## The radius is DERIVED from the noticing distance, not chosen: an
## aggregation whose members cannot reach each other is not an aggregation.
## The real-world check is that it lands on the scale a real butterfly
## aggregation actually has.
func test_the_aggregation_is_the_size_of_a_real_butterfly_aggregation():
	assert_almost_eq(
		2.0 * FlyerSpawnLayout.AGGREGATION_RADIUS_PX, Courtship.NOTICE_RADIUS_PX, 0.001,
		"the radius must BE half the noticing distance, not merely agree with it"
	)
	assert_gte(FlyerSpawnLayout.AGGREGATION_RADIUS_M, 1.0, "a puddling club is metres across")
	assert_lte(FlyerSpawnLayout.AGGREGATION_RADIUS_M, 5.0, "...not tens of metres")
	assert_almost_eq(
		FlyerSpawnLayout.AGGREGATION_RADIUS_PX,
		FlyerSpawnLayout.AGGREGATION_RADIUS_M * GroundSlide.PX_PER_METER,
		0.001
	)


## A chunk's flyers are freed with the chunk, so an aggregation that spilled
## over the edge would put butterflies in a neighbour's airspace and take
## them away again when the wrong chunk unloaded.
func test_an_aggregation_stays_inside_its_own_chunk():
	for x in 60:
		var origin := Vector2i(x * CHUNK_SIZE, GERMANY_ROW)
		var low := Vector2(origin) * float(TILE_SIZE)
		var high := low + Vector2(CHUNK_SIZE, CHUNK_SIZE) * float(TILE_SIZE)
		for at in FlyerSpawnLayout.aggregated_positions(
			origin, CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT, 4
		):
			assert_between(at.x, low.x, high.x)
			assert_between(at.y, low.y, high.y)


func test_different_chunks_aggregate_in_different_places():
	var sites := {}
	for x in 40:
		var site := FlyerSpawnLayout.aggregation_site(
			Vector2i(x * CHUNK_SIZE, GERMANY_ROW), CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT
		)
		sites[snappedf(site.x, 1.0)] = true
	assert_gt(sites.size(), 20, "the good patch must not be in the same corner of every chunk")


func test_an_aggregation_is_deterministic():
	var once := FlyerSpawnLayout.aggregated_positions(
		Vector2i(96, KANSAS_ROW), CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT, 3
	)
	var twice := FlyerSpawnLayout.aggregated_positions(
		Vector2i(96, KANSAS_ROW), CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT, 3
	)
	assert_eq(once, twice)


# -- what species an aggregation is made of ----------------------------------

## A pair can only court its own kind, and drawing each individual
## independently from the pool makes same-species neighbours a coin flip.
## Real meadows are not one-of-each: a species is present because its larval
## host plant grows there, one female lays dozens of eggs on one stand, and
## what emerges is a local cohort. So a chunk has a DOMINANT species and the
## occasional stray.
func test_a_meadow_is_mostly_one_species():
	var pool: Array[String] = ["monarch", "swallowtail"]
	var same := 0
	var chunks := 400
	for x in chunks:
		var origin := Vector2i(x * CHUNK_SIZE, KANSAS_ROW)
		var first := FlyerSpawnLayout.aggregation_species(pool, origin, SALT, 0)
		var second := FlyerSpawnLayout.aggregation_species(pool, origin, SALT, 1)
		if first == second:
			same += 1
	var share := float(same) / float(chunks)
	assert_gt(share, 0.6, "two butterflies in one meadow are usually the same kind")
	assert_lt(share, 1.0, "...but a meadow with only ever one kind is not a meadow either")


func test_a_stray_of_another_kind_still_turns_up():
	var pool: Array[String] = ["monarch", "swallowtail"]
	var seen := {}
	for x in 200:
		for member in 4:
			seen[FlyerSpawnLayout.aggregation_species(
				pool, Vector2i(x * CHUNK_SIZE, KANSAS_ROW), SALT, member
			)] = true
	assert_eq(seen.size(), 2, "both species must still occur somewhere")


func test_a_single_species_pool_still_works():
	var pool: Array[String] = ["swallowtail"]
	assert_eq(
		FlyerSpawnLayout.aggregation_species(pool, Vector2i(0, GERMANY_ROW), SALT, 0),
		"swallowtail"
	)


func test_an_empty_pool_names_nothing():
	var pool: Array[String] = []
	assert_eq(FlyerSpawnLayout.aggregation_species(pool, Vector2i.ZERO, SALT, 0), "")


# -- THE MEASUREMENT ---------------------------------------------------------
#
# The whole reason this module exists. Real spawn geometry, every real chunk
# origin along a real row, the real per-chunk count roll and the real species
# pool for that latitude -- no model of the system, the system itself.
#
# The numbers this prints are quoted in
# docs/concept/ecosystem_dynamics.md#two-butterflies-meeting.

const MEASURED_CHUNKS := 300


func _pool_at(biome_name: String, row: int) -> Array[String]:
	var renderer := AmbientFlyerRenderer.new()
	var chunk_stub := preload("res://src/world/chunk.gd").new()
	chunk_stub.width = CHUNK_SIZE
	chunk_stub.height = CHUNK_SIZE
	var abs_latitude := renderer._abs_latitude_for(chunk_stub, Vector2i(0, row))
	return renderer._in_range_pool(
		AmbientFlyerRenderer.TRUE_BUTTERFLY_SPECIES_POOL, biome_name, abs_latitude
	)


## One chunk's butterflies as (position, species) pairs, laid out the OLD way:
## ranked-hash scatter over every cell in the chunk, species drawn per cell.
func _scattered_meadow(origin: Vector2i, pool: Array[String]) -> Array:
	var wanted := FlyerSpawnLayout.wanted_count(
		origin, SALT,
		AmbientFlyerRenderer.MIN_BUTTERFLIES_PER_CHUNK,
		AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK,
		CHUNK_SIZE * CHUNK_SIZE
	)
	var out := []
	for cell in FlyerSpawnLayout.scattered_cells(origin, CHUNK_SIZE, CHUNK_SIZE, SALT, wanted):
		out.append([
			Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE),
			FlyerSpawnLayout.species_at_cell(pool, cell, SALT),
		])
	return out


## The same chunk laid out the NEW way: one aggregation, mostly one species.
func _aggregated_meadow(origin: Vector2i, pool: Array[String]) -> Array:
	var wanted := FlyerSpawnLayout.wanted_count(
		origin, SALT,
		AmbientFlyerRenderer.MIN_BUTTERFLIES_PER_CHUNK,
		AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK,
		CHUNK_SIZE * CHUNK_SIZE
	)
	var positions := FlyerSpawnLayout.aggregated_positions(
		origin, CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, SALT, wanted
	)
	var out := []
	for i in positions.size():
		out.append([positions[i], FlyerSpawnLayout.aggregation_species(pool, origin, SALT, i)])
	return out


func _has_pair_within(meadow: Array, radius: float, same_species_only: bool) -> bool:
	for i in meadow.size():
		for j in range(i + 1, meadow.size()):
			if same_species_only and meadow[i][1] != meadow[j][1]:
				continue
			if meadow[i][0].distance_to(meadow[j][0]) <= radius:
				return true
	return false


## Shares of chunks that contain, in order:
##  0: any pair at all that could ever meet
##  1: a SAME-SPECIES pair that could ever meet (courtship's real requirement)
##  2: a same-species pair close enough to meet routinely
##  3: any pair inside SpiralFlight's own, wider notice radius
func _encounter_rates(row: int, biome_name: String, aggregated: bool) -> Array:
	var pool := _pool_at(biome_name, row)
	var counts := [0, 0, 0, 0]
	for x in MEASURED_CHUNKS:
		var origin := Vector2i(x * CHUNK_SIZE, row)
		var meadow := (
			_aggregated_meadow(origin, pool) if aggregated else _scattered_meadow(origin, pool)
		)
		if _has_pair_within(meadow, CAN_EVER_MEET_PX, false):
			counts[0] += 1
		if _has_pair_within(meadow, CAN_EVER_MEET_PX, true):
			counts[1] += 1
		if _has_pair_within(meadow, MEET_ROUTINELY_PX, true):
			counts[2] += 1
		if _has_pair_within(meadow, SpiralFlight.NOTICE_RADIUS_PX, false):
			counts[3] += 1
	var rates := []
	for c in counts:
		rates.append(float(c) / float(MEASURED_CHUNKS))
	return rates


func _report(label: String, rates: Array) -> void:
	gut.p(
		"%s: any-pair-can-meet %.1f%% | same-species-can-meet %.1f%% | routinely %.1f%% | in-spiral-range %.1f%%"
		% [label, rates[0] * 100.0, rates[1] * 100.0, rates[2] * 100.0, rates[3] * 100.0]
	)


## Brandenburg, the coordinate the bug was reported at. Only ONE true
## butterfly is in range at 52.5 deg N (see AmbientFlyerRenderer.FLYER_RANGE:
## the monarch stops at 50 and the blue morpho is a rainforest species), so
## here the starvation is purely geometric.
func test_a_german_meadows_butterflies_could_almost_never_meet_and_now_can():
	var before := _encounter_rates(GERMANY_ROW, "grassland", false)
	var after := _encounter_rates(GERMANY_ROW, "grassland", true)
	_report("germany scattered", before)
	_report("germany aggregated", after)

	assert_lt(before[1], 0.25, "measured: almost no German chunk could ever produce a courtship")
	assert_gt(after[1], 0.99, "an aggregation must make it reachable in essentially every chunk")
	assert_gt(after[2], 0.99, "...and reachable without either flyer leaving its own tether")


## 40 deg N, where the monarch and the old-world swallowtail both range, so
## the SPECIES half of the problem is live as well as the geometric half.
func test_where_two_species_overlap_the_pool_no_longer_splits_the_meadow():
	var before := _encounter_rates(KANSAS_ROW, "grassland", false)
	var after := _encounter_rates(KANSAS_ROW, "grassland", true)
	_report("40N scattered", before)
	_report("40N aggregated", after)

	assert_lt(before[1], 0.2, "measured: a two-species pool halves an already tiny number")
	# NOT 100%, deliberately. STRAY_SHARE keeps a quarter of a meadow's
	# butterflies a different kind, and in a chunk holding only two of them a
	# single stray means no courtable pair at all. A meadow that could only
	# ever hold one species would be a duller thing than the real one, so the
	# remaining ~1 chunk in 9 is a design choice, not a shortfall -- and it is
	# the SPIRAL flight, which is cross-species, that makes those meadows lively
	# anyway (see the in-spiral-range column, 100%).
	assert_gt(after[1], 0.85, "clustering the species as well must recover nearly all of it")
	assert_gt(
		after[1] / maxf(before[1], 0.0001), 20.0,
		"the fix has to be an order-of-magnitude change, not a nudge"
	)


## The spiral flight is the behaviour the player asked for, and it is
## cross-species and noticed from further off -- so it is reachable in more
## chunks than courtship even before the layout change, and in essentially
## all of them after.
func test_the_spiral_flight_is_reachable_in_essentially_every_meadow():
	var after := _encounter_rates(GERMANY_ROW, "grassland", true)
	assert_gt(after[3], 0.99)
