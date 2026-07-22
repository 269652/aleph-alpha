extends GutTest

const TreeMaturity = preload("res://src/gameplay/tree_maturity.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

var maturity := TreeMaturity.new()

const _POSITION := Vector2(500, 500)
var _genome := TreeGenome.new(hash("%d_%d" % [500, 500]))


func test_original_positions_are_always_mature():
	var result := maturity.mature_positions([_POSITION], [], 0.0)
	assert_eq(result, [_POSITION])


func test_a_sapling_below_its_genomes_maturity_time_is_excluded():
	var saplings := [{"position": _POSITION, "planted_at": 0.0}]
	var result := maturity.mature_positions([], saplings, _genome.maturity_time * 0.5)
	assert_eq(result.size(), 0)


func test_a_sapling_past_its_genomes_maturity_time_is_included():
	var saplings := [{"position": _POSITION, "planted_at": 0.0}]
	var result := maturity.mature_positions([], saplings, _genome.maturity_time + 1.0)
	assert_eq(result, [_POSITION])


func test_maturity_is_measured_from_planted_at_not_from_zero():
	# Planted at world_age 100 with a maturity_time of, say, 30s isn't mature
	# yet at world_age 110 (only 10s old) even though 110 > 30.
	var saplings := [{"position": _POSITION, "planted_at": 100.0}]
	var result := maturity.mature_positions([], saplings, 100.0 + _genome.maturity_time * 0.5)
	assert_eq(result.size(), 0)


func test_combines_always_mature_originals_with_matured_saplings():
	var original := Vector2(1, 1)
	var saplings := [{"position": _POSITION, "planted_at": 0.0}]
	var result := maturity.mature_positions([original], saplings, _genome.maturity_time + 1.0)
	assert_eq(result.size(), 2)
	assert_true(result.has(original))
	assert_true(result.has(_POSITION))
