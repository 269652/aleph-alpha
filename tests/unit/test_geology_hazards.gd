extends GutTest

## GeologyHazards.foul_air_at / flood_risk_at (see docs/concept/geology.md
## "Foul air deepens with distance from open air" / "Flooding compounds
## depth with nearby water").

const GeologyHazards = preload("res://src/world/geology_hazards.gd")
const Strata = preload("res://src/world/strata.gd")

var hazards: GeologyHazards


func before_each():
	hazards = GeologyHazards.new()


# -- foul_air_at: monotonically worse the further from open air -------------

func test_foul_air_is_lowest_in_topsoil_regolith():
	var topsoil: float = hazards.foul_air_at(Strata.LAYER_TOPSOIL_REGOLITH)
	var bedrock: float = hazards.foul_air_at(Strata.LAYER_BEDROCK)
	var deep_bedrock: float = hazards.foul_air_at(Strata.LAYER_DEEP_BEDROCK)
	var hydrothermal: float = hazards.foul_air_at(Strata.LAYER_HYDROTHERMAL)
	assert_lt(topsoil, bedrock)
	assert_lt(bedrock, deep_bedrock)
	assert_lt(deep_bedrock, hydrothermal)


func test_foul_air_is_a_fraction():
	for layer in Strata.LAYERS:
		var risk: float = hazards.foul_air_at(layer)
		assert_between(risk, 0.0, 1.0, "foul air risk for %s out of [0,1]" % layer)


func test_foul_air_unknown_layer_is_zero():
	assert_eq(hazards.foul_air_at("not_a_real_layer"), 0.0)


# -- flood_risk_at: base layer risk x distance falloff -----------------------

func test_flood_risk_falls_off_with_distance_from_water():
	var near: float = hazards.flood_risk_at(Strata.LAYER_BEDROCK, 1.0)
	var far: float = hazards.flood_risk_at(Strata.LAYER_BEDROCK, 500.0)
	assert_gt(near, far)


func test_flood_risk_grows_with_depth_at_the_same_distance():
	var shallow: float = hazards.flood_risk_at(Strata.LAYER_TOPSOIL_REGOLITH, 5.0)
	var deep: float = hazards.flood_risk_at(Strata.LAYER_DEEP_BEDROCK, 5.0)
	assert_gt(deep, shallow)


func test_flood_risk_is_a_fraction():
	for layer in Strata.LAYERS:
		for distance in [0.0, 10.0, 1000.0]:
			var risk: float = hazards.flood_risk_at(layer, distance)
			assert_between(risk, 0.0, 1.0, "flood risk for %s @ %f out of [0,1]" % [layer, distance])


func test_flood_risk_far_from_water_approaches_zero():
	assert_almost_eq(hazards.flood_risk_at(Strata.LAYER_HYDROTHERMAL, 100000.0), 0.0, 0.01)


func test_flood_risk_unknown_layer_is_zero():
	assert_eq(hazards.flood_risk_at("not_a_real_layer", 0.0), 0.0)
