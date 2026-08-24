extends GutTest

## GeologyOreGenesis: layer-aware ore type weighting, extending
## OrePlacement's coordinate-hash shape (see docs/concept/geology.md "The
## four layers" table -- coal shallow, iron bedrock/deep bedrock, copper
## the hydrothermal zone, grounded in real porphyry copper deposit
## genesis).

const GeologyOreGenesis = preload("res://src/world/geology_ore_genesis.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")
const Strata = preload("res://src/world/strata.gd")

var genesis: GeologyOreGenesis


func before_each():
	genesis = GeologyOreGenesis.new()


func _distribution_for(layer: String, samples: int) -> Dictionary:
	var counts := {"iron": 0, "copper": 0, "coal": 0}
	for i in samples:
		var t: String = genesis.ore_type_at(i, i * 31 + 7, layer)
		counts[t] = counts.get(t, 0) + 1
	return counts


func test_ore_type_is_always_a_known_ore_placement_type():
	for layer in Strata.LAYERS:
		for i in 50:
			var t: String = genesis.ore_type_at(i, i * 17, layer)
			assert_true(OrePlacement.ORE_TYPES.has(t), "unknown ore type %s in %s" % [t, layer])


func test_ore_type_deterministic():
	var a := genesis.ore_type_at(12, 34, Strata.LAYER_BEDROCK)
	var b := genesis.ore_type_at(12, 34, Strata.LAYER_BEDROCK)
	assert_eq(a, b)


func test_ore_type_varies_by_layer_at_the_same_coordinate():
	# Not every coordinate needs to differ, but across many coordinates the
	# per-layer weighting must actually change outcomes somewhere.
	var differs := false
	for i in 100:
		var topsoil := genesis.ore_type_at(i, i, Strata.LAYER_TOPSOIL_REGOLITH)
		var hydrothermal := genesis.ore_type_at(i, i, Strata.LAYER_HYDROTHERMAL)
		if topsoil != hydrothermal:
			differs = true
			break
	assert_true(differs, "layer weighting should change the outcome somewhere")


func test_coal_dominates_topsoil_regolith():
	var counts := _distribution_for(Strata.LAYER_TOPSOIL_REGOLITH, 400)
	assert_gt(counts["coal"], counts["iron"])
	assert_gt(counts["coal"], counts["copper"])


func test_iron_dominates_bedrock():
	var counts := _distribution_for(Strata.LAYER_BEDROCK, 400)
	assert_gt(counts["iron"], counts["coal"])
	assert_gt(counts["iron"], counts["copper"])


func test_iron_dominates_deep_bedrock_even_more_than_bedrock():
	var bedrock := _distribution_for(Strata.LAYER_BEDROCK, 400)
	var deep := _distribution_for(Strata.LAYER_DEEP_BEDROCK, 400)
	var bedrock_iron_fraction := float(bedrock["iron"]) / 400.0
	var deep_iron_fraction := float(deep["iron"]) / 400.0
	assert_gt(deep_iron_fraction, bedrock_iron_fraction)


func test_copper_dominates_the_hydrothermal_zone():
	var counts := _distribution_for(Strata.LAYER_HYDROTHERMAL, 400)
	assert_gt(counts["copper"], counts["iron"])
	assert_gt(counts["copper"], counts["coal"])


func test_unknown_layer_falls_back_to_ore_placements_own_weighting():
	var t := genesis.ore_type_at(5, 5, "not_a_real_layer")
	assert_true(OrePlacement.ORE_TYPES.has(t))
