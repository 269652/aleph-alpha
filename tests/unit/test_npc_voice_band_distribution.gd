extends GutTest

## Where NpcVoice's band edges come from -- the reason that module gets a
## second, dedicated test file (docs/concept/dialogue.md, NpcVoice: "banded
## by quantile, not by a threshold... the band edges are measured against
## the real generator and pinned by a 5000-seed distribution test").
##
## Two facts make any eyeballed cut useless, and both are asserted below
## rather than asserted in prose:
##   - with 8 independent uniform genes, P(max >= 0.85) = 1 - 0.85^8 = 72.8%,
##     so a "0.85 is strong" cut brands nearly three villagers in four;
##   - an axis built as a linear combination of those genes concentrates
##     hard at its mean (CLT), so an even-thirds cut of [0, 1] leaves almost
##     the whole village in the middle band.
##
## The population is drawn through the REAL generator -- SettlementGenerator
## picks which chunks host a village, and its own NpcIdentity roster builds
## the genomes -- so these are the seeds the game actually rolls, not
## range(n). Nothing here constructs an EarthChunkManager: settlement
## placement is pure hashing and costs nothing.

const NpcVoice = preload("res://src/dialogue/npc_voice.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")

## Matches test_settlement_generator.gd's own fixtures -- neither value
## reaches a genome, they only shape the house positions we throw away.
const TILE_SIZE := 16
const CHUNK_SIZE := 32

## The spec asks for >= 5000 real seeds; 6000 is 1200 whole settlements, so
## no village is half-sampled.
const SAMPLE_VILLAGERS := 6000

## How wide a band of chunk columns each scan row covers. Only ~1 chunk in
## SETTLEMENT_CHANCE_DENOMINATOR hosts a village, so a row yields ~10.
const SCAN_ROW_WIDTH := 300

## A third of the population per band, and how far off that a real draw is
## allowed to land. The calibration sample is the same construction the
## pinned edges were measured from, so it is held tight; the holdout region
## is a different part of the map entirely and gets sampling slack.
const EXPECTED_BAND_SHARE := 1.0 / 3.0
const BAND_SHARE_TOLERANCE := 0.02
const HOLDOUT_BAND_SHARE_TOLERANCE := 0.04

## How far a freshly measured edge may sit from the pinned constant. Axis
## values are multiples of 1/40000, so this is slack for the sample, not for
## an eyeball.
const EDGE_TOLERANCE := 0.01

## The two arithmetic facts above, as numbers this file checks rather than
## repeats: 1 - 0.85^8, and the share an even-thirds cut of [0, 1] leaves in
## the middle band (a 4-gene contrast axis has sd = 1/sqrt(48) = 0.144, so
## +/-1/6 is +/-1.15 sd).
const ARGMAX_STRONG_CUT := 0.85
const EXPECTED_ARGMAX_STRONG_SHARE := 0.728
const ARGMAX_STRONG_SHARE_TOLERANCE := 0.03
const MIN_NAIVE_MID_SHARE := 0.60

## Two disjoint regions of the map, so "the edges generalize" is a real
## claim about different villages and not the same draw twice.
const CALIBRATION_ORIGIN := Vector2i(0, 0)
const HOLDOUT_ORIGIN := Vector2i(20000, 20000)

var _calibration: Array = []
var _holdout: Array = []


func before_all():
	_calibration = _population_traits(CALIBRATION_ORIGIN, SAMPLE_VILLAGERS)
	_holdout = _population_traits(HOLDOUT_ORIGIN, SAMPLE_VILLAGERS)


## Walks real chunk coordinates, keeps the ones the real placement rule says
## host a village, and collects those villagers' real genomes.
func _population_traits(region_origin: Vector2i, wanted: int) -> Array:
	var generator := SettlementGenerator.new()
	var samples: Array = []
	var row := 0
	while samples.size() < wanted:
		for column in SCAN_ROW_WIDTH:
			var coord := region_origin + Vector2i(column, row)
			if not generator.has_settlement_at(coord, "grassland"):
				continue
			var settlement := generator.generate_settlement(
				coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
			)
			for npc in settlement.npcs:
				if samples.size() < wanted:
					samples.append(npc.genome.traits)
		row += 1
		if row > 2000:
			fail_test("scanned %d rows without finding %d villagers" % [row, wanted])
			break
	return samples


## band -> share of the population, for one axis under the given edges.
func _band_shares(samples: Array, axis_name: String, edges: Dictionary) -> Dictionary:
	var counts := {"low": 0, "mid": 0, "high": 0}
	for traits in samples:
		var value: float = NpcVoice.axes_for(traits)[axis_name]
		var band := "mid"
		if value < float(edges["low"]):
			band = "low"
		elif value >= float(edges["high"]):
			band = "high"
		counts[band] += 1
	var shares := {}
	for band in counts:
		shares[band] = float(counts[band]) / float(samples.size())
	return shares


func test_the_real_generator_yields_a_full_sized_sample():
	assert_eq(_calibration.size(), SAMPLE_VILLAGERS)
	assert_eq(_holdout.size(), SAMPLE_VILLAGERS)
	assert_ne(_calibration[0], _holdout[0], "the two regions must be different villagers")


## The pinned constants ARE the output of this measurement -- re-run it and
## the numbers in NpcVoice.BAND_EDGES come back. This is what keeps them
## from being eyeballed: the printed Dictionary is the re-pin instruction.
func test_pinned_edges_are_the_ones_measured_from_the_real_generator():
	var measured := NpcVoice.measure_band_edges(_calibration)
	gut.p("measured BAND_EDGES: %s" % measured)
	for axis_name in NpcVoice.AXES:
		var pinned: Dictionary = NpcVoice.BAND_EDGES[axis_name]
		assert_almost_eq(
			float(measured[axis_name]["low"]), float(pinned["low"]), EDGE_TOLERANCE, axis_name
		)
		assert_almost_eq(
			float(measured[axis_name]["high"]), float(pinned["high"]), EDGE_TOLERANCE, axis_name
		)


## The pin itself: with the shipped edges, each band holds a third of a real
## village population, on every axis.
func test_every_band_holds_a_third_of_the_real_population():
	for axis_name in NpcVoice.AXES:
		var shares := _band_shares(_calibration, axis_name, NpcVoice.BAND_EDGES[axis_name])
		for band in NpcVoice.BANDS:
			assert_between(
				float(shares[band]),
				EXPECTED_BAND_SHARE - BAND_SHARE_TOLERANCE,
				EXPECTED_BAND_SHARE + BAND_SHARE_TOLERANCE,
				"%s_%s share %.4f" % [axis_name, band, shares[band]]
			)


## Measured on one region, still thirds on another -- the edges describe the
## generator, not the sample they were cut from.
func test_the_edges_hold_on_villages_the_calibration_never_saw():
	for axis_name in NpcVoice.AXES:
		var shares := _band_shares(_holdout, axis_name, NpcVoice.BAND_EDGES[axis_name])
		for band in NpcVoice.BANDS:
			assert_between(
				float(shares[band]),
				EXPECTED_BAND_SHARE - HOLDOUT_BAND_SHARE_TOLERANCE,
				EXPECTED_BAND_SHARE + HOLDOUT_BAND_SHARE_TOLERANCE,
				"%s_%s share %.4f" % [axis_name, band, shares[band]]
			)


## Why the edges are measured at all, fact one: cutting [0, 1] into even
## thirds is the obvious thing to do and it is wrong, because a 4-gene
## contrast axis concentrates at its mean.
func test_an_even_thirds_cut_of_the_axis_range_would_swallow_everyone_into_mid():
	var naive := {"low": 1.0 / 3.0, "high": 2.0 / 3.0}
	for axis_name in NpcVoice.AXES:
		var shares := _band_shares(_calibration, axis_name, naive)
		assert_gt(
			float(shares["mid"]),
			MIN_NAIVE_MID_SHARE,
			"%s mid share under an even-thirds cut: %.4f" % [axis_name, shares["mid"]]
		)


## Why the edges are measured at all, fact two: reading the genome the way
## the game does today -- one argmax gene, "strong" if it cleared some high
## number -- brands 1 - 0.85^8 = 72.8% of villagers strong.
func test_a_fixed_strong_cut_on_the_argmax_gene_brands_three_villagers_in_four():
	var strong := 0
	for traits in _calibration:
		var best := 0.0
		for gene in traits:
			best = maxf(best, float(traits[gene]))
		if best >= ARGMAX_STRONG_CUT:
			strong += 1
	var share := float(strong) / float(_calibration.size())
	assert_almost_eq(share, EXPECTED_ARGMAX_STRONG_SHARE, ARGMAX_STRONG_SHARE_TOLERANCE)


## Every strong voice actually occurs in a real population -- a key the
## renderer has a phrasing pool for but no villager ever carries is dead
## content, and one that swallows a quarter of the village is a flat cast.
func test_every_non_mid_voice_key_is_carried_by_real_villagers():
	var counts := {}
	for traits in _calibration:
		var key := NpcVoice.voice_key_for(traits)
		counts[key] = int(counts.get(key, 0)) + 1
	gut.p("voice_key spread: %s" % counts)
	for axis_name in NpcVoice.AXES:
		for band in ["low", "high"]:
			var key := NpcVoice.key_for(axis_name, band)
			var share := float(int(counts.get(key, 0))) / float(_calibration.size())
			assert_between(share, 0.02, 0.25, "%s share %.4f" % [key, share])


## Characterization of the measured spread above, not a new requirement:
## across both regions every one of the 15 keys is carried by somebody, mid
## ones included, so the renderer has no pool it can never reach. Counted
## over both samples because a mid key is rare by construction (all five
## axes mid at once) and 6000 villagers is thin cover for it.
func test_every_voice_key_including_the_rare_mid_ones_is_reachable():
	var carried := {}
	for traits in _calibration + _holdout:
		carried[NpcVoice.voice_key_for(traits)] = true
	for key in NpcVoice.voice_keys():
		assert_true(carried.has(key), "no real villager ever voices %s" % key)


## A villager average on all five axes has no strong voice, and that is
## supposed to be rare rather than the default -- the opposite failure to
## the even-thirds cut above.
func test_a_mid_voice_key_is_the_rare_case_not_the_common_one():
	var mid_keys := 0
	for traits in _calibration:
		if NpcVoice.parse_key(NpcVoice.voice_key_for(traits))["band"] == "mid":
			mid_keys += 1
	var share := float(mid_keys) / float(_calibration.size())
	assert_lt(share, 0.05, "mid voice_key share %.4f" % share)
